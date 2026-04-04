---
name: build
description: "Full build pipeline: takes a PRD, breaks it into tasks, implements them in parallel, and reviews the result. Orchestrates prd-task-planner → parallel-task-orchestrator → code-reviewer."
argument-hint: "[--brainstorm] <PRD or path to PRD file>"
---

# Build Pipeline

You are orchestrating the full build pipeline. Follow these steps strictly in order.

## Input

The raw arguments (may include `--brainstorm` flag):

$ARGUMENTS

**Parse flags before proceeding:**
- If `$ARGUMENTS` starts with or contains `--brainstorm`, set `BRAINSTORM=true` and strip `--brainstorm` to get the clean PRD content.
- Otherwise, `BRAINSTORM=false` and the full arguments are the PRD content.

## Step 0.1: Auto-commit opt-in

Ask: "Enable auto-commit and PR?" (Yes / No) → `AUTO_COMMIT`.

**If `AUTO_COMMIT=true`:**
1. Run `git rev-parse --abbrev-ref HEAD`. If `main`/`master`: `BRANCH_ACTION=new`. Else ask: "Branch `<name>` exists — create new or commit here?" → `BRANCH_ACTION=new/current`.
2. Ask: "Single squash commit or one commit per task?" → `COMMIT_MODE=squash/per-task`.
3. Generate `feat/<3-5-word-slug>` from PRD content → `AUTO_COMMIT_BRANCH`.
4. `git checkout -b <AUTO_COMMIT_BRANCH>`. On failure append `-2`, retry once.

**If `AUTO_COMMIT=false`:** `BRANCH_ACTION=none`, `COMMIT_MODE=none`.

## Step 0.2: Orchestration Mode Selection

Ask the user which orchestration mode to use for implementation:

Use `AskUserQuestion` with:
- Question: "How should tasks be implemented?"
- Options:
  - **Default (Recommended)**: Use `parallel-task-orchestrator` — proven sub-agent approach with wave-based parallel execution
  - **Agent Teams (Beta)**: Use Claude Code's native Agent Teams feature — separate sessions coordinating via shared task list

Store the result as `ORCHESTRATION_MODE` (`parallel` or `agent-teams`).

## Step 0: Clean up — Remove stale task files

Before starting, remove any leftover files from a previous build run:
- Use Bash to run `rm -rf tasks/` to clear the entire tasks directory
- This prevents stale task files from being picked up by the orchestrator

## Step 0.5 (if BRAINSTORM=true): Design brainstorm

**Skip this step if BRAINSTORM=false.**

1. Launch the `prd-task-planner` agent using the Task tool with:
   - `subagent_type: "prd-task-planner"`
   - Prompt: `MODE: BRAINSTORM\n\n<clean PRD content>`
   - Wait for it to complete. **Save the returned agent ID** — this agent will be resumed in Step 1a.

2. Read `tasks/design-options.md`.

3. Present the design options to the user using `AskUserQuestion`. Build one question per option listed in the file, using the option names as labels and their summaries/trade-offs as descriptions. Include a "Custom direction" option. Ask: "Which design approach should we use for this feature?"

4. Collect the user's chosen option. Store it as `CHOSEN_DESIGN`.

## Step 1: Plan — Two-phase planning with user Q&A

### Step 1a: Discovery — Explore codebase & surface questions

**If BRAINSTORM=true** — resume the agent from Step 0.5:
- `resume: "<agent-id-from-step-0.5>"`
- Prompt: `MODE: DISCOVERY\n\nChosen design direction: <CHOSEN_DESIGN>\n\n<clean PRD content>`
- Tell it to output questions to `tasks/planning-questions.md`
- The agent already has full codebase context from the brainstorm phase — it will skip re-exploration.

**If BRAINSTORM=false** — launch a fresh agent:
- `subagent_type: "prd-task-planner"`
- Prompt: `MODE: DISCOVERY\n\n<PRD content>`
- Tell it to output questions to `tasks/planning-questions.md`

Wait for it to complete. **Save the returned agent ID** — you will resume this agent in Step 1c.

### Step 1b: User Q&A — Present questions and collect answers

1. Read `tasks/planning-questions.md`
2. Present each question to the user using `AskUserQuestion` — use the questions, context, and options from the file to construct clear choices
3. Collect all answers

### Step 1c: Generate — Resume planner with answers

Resume the **same** prd-task-planner agent (using the agent ID from Step 1a) with:
- `resume: "<agent-id-from-step-1a>"`
- Provide all user answers in the prompt, formatted clearly
- Prepend `MODE: GENERATE` to the prompt
- Tell it to generate the updated PRD and task files in `tasks/`

Wait for it to complete. Confirm that task files were created in `tasks/`.

### Step 1d: Task review — Present plan and get approval

This step always runs. Do not skip it.

1. Read all `task-*.md` files from `tasks/`. For each, extract:
   - Task number and title (from filename or `# Task N:` heading)
   - Objective (first line of `## Objective` section)
   - Dependencies (from `## Dependencies` section)

2. Present the full task plan to the user as a formatted list:
   ```
   ## Task Plan (N tasks)

   1. task-01-name — [Objective]
      Dependencies: None
   2. task-02-name — [Objective]
      Dependencies: task-01
   ...
   ```
   Then add: "You can also open and edit any file in `tasks/` directly before proceeding."

3. Use `AskUserQuestion` with a single question: "How would you like to proceed?"
   - **"Looks good — start implementation"** — continue to Step 2
   - **"Regenerate with feedback"** — user provides feedback via the "Other" field

4. **If user approves**: proceed to Step 2.

5. **If user requests regeneration**: resume the **same** prd-task-planner agent (from Step 1a/1c) with:
   - `resume: "<agent-id-from-step-1a>"`
   - Prompt: `MODE: GENERATE\n\nUser feedback on the task plan:\n<feedback>\n\nPlease regenerate the task files incorporating this feedback.`
   - Wait for it to complete, then **loop back to the top of Step 1d** to re-present the updated plan.

## Step 1e: Fast-path detection — Should we skip the orchestrator?

Before launching the orchestrator, analyze the task files to determine if orchestration overhead is justified.

**Read all `tasks/task-*.md` files and extract:**
1. Total task count
2. Per-task: files to modify (from `## Files to Modify` or `## Context Files` sections)
3. Per-task: explicit dependencies (from `## Dependencies` or `Depends on:` lines)

**Classify as `FAST_PATH=true` if ANY of these conditions are met:**
- **2 or fewer tasks** (regardless of dependencies)
- **All tasks are sequential**: every task depends on the previous one (linear chain), OR all tasks touch overlapping files (no parallelism possible)
- **Most tasks are sequential**: only 1 task out of 3+ could run in parallel (orchestrator adds overhead for negligible parallelism)

**Set `FAST_PATH=false` otherwise** (3+ tasks with real parallelism opportunities).

## Step 2: Implement

### Fast path (`FAST_PATH=true`) — Direct implementation

> **Note**: If `ORCHESTRATION_MODE=agent-teams` was selected, inform the user: "Fast-path detected (≤2 tasks or all sequential). Using direct implementation instead of Agent Teams — orchestration overhead is not justified for simple tasks." The env var setup from Step 0.2 is skipped in fast-path mode.

Implement the tasks yourself, sequentially, in the current conversation context. For each task file in order:

1. Read the task file fully (objective, requirements, acceptance criteria, context files)
2. Read all referenced context files
3. Implement the task following the requirements and acceptance criteria
4. If the task has a `## TDD Mode` section, follow the RED → GREEN → REFACTOR → VERIFY cycle (including test adequacy check)
5. After each task, collect the Implementation Notes section from your work. After all tasks are done, write `tasks/implementation-notes.md` consolidating all notes.
6. **If `COMMIT_MODE=per-task`:** after completing each task, run:
   ```bash
   git add -A
   git commit -m "feat: <task-objective-from-task-file>"
   ```

This avoids orchestrator overhead and gives you continuous context across tasks — each task benefits from seeing the work done in previous tasks without reading files cold.

### Full path (`FAST_PATH=false`) — Run orchestrator

**If `ORCHESTRATION_MODE=parallel`** (default):

**If `COMMIT_MODE=per-task`:**

Launch the `parallel-task-orchestrator` agent using the Task tool with:
- `subagent_type: "parallel-task-orchestrator"`
- Tell it to read and execute all tasks from `tasks/`
- Include this additional instruction in the prompt:
  > "Run tasks **sequentially** (one at a time, no parallel waves). After each task-implementer completes, run the following bash commands before starting the next task:
  > ```bash
  > git add -A
  > git commit -m "feat: <task-objective-from-task-file>"
  > ```
  > Use the task's `## Objective` line as the commit message description."

**If `COMMIT_MODE=squash` or `AUTO_COMMIT=false`:**

Launch the `parallel-task-orchestrator` agent using the Task tool with:
- `subagent_type: "parallel-task-orchestrator"`
- Tell it to read and execute all tasks from `tasks/`

Wait for it to complete. Note any issues reported.

**If `ORCHESTRATION_MODE=agent-teams`** (Beta):

First, enable the required env var by finding the user's settings file (check `~/.claude/settings.json`, then `.claude/settings.json`, then `.claude/settings.local.json`) and adding `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` to the `env` object, preserving all existing settings. If no settings file exists, create `.claude/settings.local.json` with the env var.

Do NOT spawn a sub-agent. Instead, execute Agent Teams orchestration directly in this session:
1. Read `.claude/agents/agent-teams-orchestrator.md` (check `~/.claude/agents/` for global installs, `.claude/agents/` for local)
2. Follow those instructions directly in this session to orchestrate tasks using Agent Teams teammates
3. Produce the same outputs: `tasks/implementation-notes.md` and `tasks/execution-metrics.md`

Note: Per-task commits are not supported in Agent Teams mode (teammates run in parallel). If `COMMIT_MODE=per-task` was selected, fall back to squash-style commit after all tasks complete. Auto-commit/branch handling (if `AUTO_COMMIT=true`) applies identically to both modes.

## Step 2b: Build check — Verify the project compiles

Before reviewing, run a quick build/lint check to catch obvious breakage:
- Look for a `package.json`, `Makefile`, `Cargo.toml`, or similar build config in the project root
- Run the appropriate build command (e.g., `npm run build`, `pnpm build`, `make`, `cargo check`)
- If the build fails, report the errors to the user and ask whether to proceed with the review or fix first
- If no build system is detected, skip this step

## Step 2c: Test verification — Run the project's test suite

After the build check, run the project's full test suite to catch regressions and verify implementation:
- Look for test configuration: `package.json` (check for "test" script), `pytest.ini`/`pyproject.toml`, `go.mod`, `Cargo.toml`, or other test framework config
- Run the appropriate test command (e.g., `npm test`, `pnpm test`, `pytest`, `go test ./...`, `cargo test`)
- If tests fail: report the failures and ask whether to proceed, fix, or skip
- If no test infrastructure is detected, skip this step

## Step 2.5: Auto-commit and PR

**Skip if `AUTO_COMMIT=false`.**

**2.5a Safety:** Run `git rev-parse --abbrev-ref HEAD`. If `main`/`master`: abort ("Auto-commit aborted: on main/master. Commit manually.") → proceed to Step 3.

**2.5b Commit:**
- `COMMIT_MODE=squash`: `git add -A && git commit -m "feat: <PRD summary>" -m "- <task objective>..."` (72-char subject, ≤3 body bullets from task objectives).
- `COMMIT_MODE=per-task`: already committed in Step 2. Skip to push.

**2.5d Push:** `git push -u origin <branch-name>`. On failure, show manual command and continue.

**2.5e PR:** Run `gh auth status 2>/dev/null && echo GH_OK || echo GH_UNAVAILABLE`.
- `GH_OK`: Create PR body (1-2 sentence summary + "## Changes" task objectives + "## Review Notes" placeholder). Run `gh pr create --title "feat: <desc>" --body "<body>" --base main`. Display URL.
- `GH_UNAVAILABLE`: Display ready-to-copy `gh pr create` command.

**2.5f Report:** `Branch: <name> | Commits: <N> | Push: ok/failed | PR: <url or manual>`

## Step 3: Review — Run code-reviewer

Before launching the code-reviewer, check if TDD mode was used by reading any task file from `tasks/` and looking for a `## TDD Mode` section. Also check if `tasks/implementation-notes.md` and `tasks/execution-metrics.md` exist.

Launch the `code-reviewer` agent using the Task tool with:
- `subagent_type: "code-reviewer"`
- Tell it to review all changes against `tasks/updated-prd.md`
- Tell it to write the review report to `tasks/review-report.md`
- **If `tasks/implementation-notes.md` exists**, tell it to read this file for implementer decision context
- **If TDD mode was used**, include these additional review criteria in the prompt:
  - Were tests written for each task that had TDD mode enabled?
  - Do the tests meaningfully cover the acceptance criteria from the task files?
  - Are there tasks with TDD mode that appear to be missing tests?
  - Do tests follow project conventions?
  - Run the test adequacy deep-check (verify each test calls the code under test, has specific assertions, and would catch real regressions)
  - If any implementer declared "TDD not feasible", verify the reason is valid
- **If TDD mode was not used**, still tell the reviewer to check general test coverage as part of the standard review

Wait for it to complete.

## Step 3b: Auto-fix — Address critical review issues (one pass)

Read `tasks/review-report.md`. Check if the `### Critical` section contains any items.

**If critical issues are found:**
1. Collect all items listed under `### Critical` (file paths, line numbers, descriptions)
2. For each distinct file affected, launch a `task-implementer` sub-agent (parallel where no file conflicts) with a prompt that includes:
   - The specific critical issue(s) for that file verbatim from the report
   - Instruction to fix only these specific issues, touching no other code
3. Wait for all task-implementers to complete.
4. Re-run the code-reviewer (same criteria as Step 3) **once more** against `tasks/updated-prd.md`. Write the updated report to `tasks/review-report.md` (overwrite).

**If no critical issues:** proceed directly to Step 4.

Do not loop — the auto-fix runs at most once. If critical issues persist after the retry, report them in Step 4.

## Step 4: Report

Check if `tasks/execution-metrics.md` exists (produced by the orchestrator in full-path mode). If not (fast-path mode), generate equivalent metrics from your own execution.

Summarize the full pipeline run to the user:

```
## Build Complete

### Planning
- [X tasks created]

### Implementation
- [tasks completed / total]
- [any issues]

### Build Check
- [passed / failed / skipped]

### Testing
- [test suite status: all passed / X failed / not detected]
- [if TDD: TDD compliance summary]

### Execution Metrics
- Tasks: [completed/total] | Waves: [N] | Retries: [N]
- TDD: [N/M tasks used TDD] | TDD skipped: [N (reasons)]
- Implementation notes: [see tasks/implementation-notes.md or "inline above"]

### Review
- [compliance score]
- [critical issues if any]
- [if implementation notes reviewed: decision assessment summary]

### Auto-Commit
- [skipped — not enabled]
  OR
- Branch: <branch-name>
- PR: <url or "manual command displayed">

### Next Steps
- [what the user should do — e.g., run tests, fix issues, deploy]
```

## Rules
- Run the steps **sequentially** — each depends on the previous
- If Step 1 fails (no tasks created), stop and report the issue
- If Step 2 has partial failures, still run Step 3 to review what was completed
- Always run Step 3 — never skip the review
