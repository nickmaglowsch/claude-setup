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
- If `$ARGUMENTS` starts with or contains `--brainstorm`, set `BRAINSTORM=true` and strip `--brainstorm` from the arguments to get the clean PRD content.
- Otherwise, `BRAINSTORM=false` and the full arguments are the PRD content.

## Step 0.1: Auto-commit opt-in

Use `AskUserQuestion` to ask: "Enable auto-commit and PR for this run?"
- Option A: "Yes — create a branch, commit when implementation is complete, and open a PR"
- Option B: "No — skip all git automation (default)"

Store result as `AUTO_COMMIT` = true / false.

**If `AUTO_COMMIT=true`:**

1. Check the current branch:
   ```bash
   git rev-parse --abbrev-ref HEAD
   ```
   - If the result is `main` or `master`: set `BRANCH_ACTION=new` (no question needed)
   - If on any other branch: use `AskUserQuestion`:
     - "A branch already exists (`<current-branch-name>`). What would you like to do?"
     - Option A: "Create a new branch (recommended)"
     - Option B: "Commit to the current branch (`<current-branch-name>`)"
   - Store as `BRANCH_ACTION` = new / current

2. Use `AskUserQuestion`:
   - "How should changes be committed?"
   - Option A: "Single squash commit — one commit summarizing the whole feature"
   - Option B: "One commit per task — each task gets its own commit message"
   - Store as `COMMIT_MODE` = squash / per-task

3. Derive branch name from the clean PRD content in `$ARGUMENTS`:
   - Generate a kebab-case 3-5 word slug summarizing the feature (e.g., `add-user-auth-oauth`)
   - Branch name: `feat/<slug>`
   - Store as `AUTO_COMMIT_BRANCH`

4. **Create and check out the branch now** (before any work begins):
   ```bash
   git checkout -b <AUTO_COMMIT_BRANCH>
   ```
   If the command fails (branch already exists), append `-2` to the name and retry once. Update `AUTO_COMMIT_BRANCH` with the final name used.

**If `AUTO_COMMIT=false`:** set `BRANCH_ACTION=none`, `COMMIT_MODE=none`. Skip all follow-up questions.

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

## Step 2: Implement — Run parallel-task-orchestrator

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
- If tests fail:
  - Report the failures to the user
  - Ask whether to proceed with the review, fix the issues first, or skip
- If no test infrastructure is detected, skip this step
- This step runs regardless of whether TDD mode was used — it is part of the always-on test awareness

## Step 2.5: Auto-commit and PR

**Skip this entire step if `AUTO_COMMIT=false`.**

### 2.5a: Safety check

Run:
```bash
git rev-parse --abbrev-ref HEAD
```

If the result is `main` or `master`, abort this step with:
```
Auto-commit aborted: currently on main/master branch. Commit manually.
```
Do not run any git add/commit/push. Proceed to Step 3.

### 2.5b: Stage and commit

**If `COMMIT_MODE=squash`** — single commit:

Generate a Conventional Commit message:
- Format: `feat(<optional-scope>): <short description>` (max 72 chars for subject line)
- Short description derived from the PRD title / first sentence
- Optional body: up to 3 bullet points summarizing what was implemented (derived from task file objectives in `tasks/`)

Run:
```bash
git add -A
git commit -m "feat: <description>" -m "- <bullet 1>
- <bullet 2>
- <bullet 3>"
```

**If `COMMIT_MODE=per-task`** — tasks were already committed during Step 2 (one commit per task by the orchestrator). Skip this section; proceed to 2.5c (Push).

### 2.5d: Push

```bash
git push -u origin <branch-name>
```

If push fails, display a warning with the manual push command but continue.

### 2.5e: Open PR

Check if `gh` is available and authenticated:
```bash
gh auth status 2>/dev/null && echo "GH_OK" || echo "GH_UNAVAILABLE"
```

**If `GH_OK`:**

Generate PR body:
- 1-2 sentence summary of what was built
- "## Changes" section listing each task objective as a bullet
- "## Review Notes" placeholder (review hasn't run yet)

Run:
```bash
gh pr create \
  --title "feat: <description>" \
  --body "<pr-body>" \
  --base main
```

If successful, display the PR URL.

**If `GH_UNAVAILABLE`:**

Display a ready-to-copy command block:
```
Run this to open the PR:

  gh pr create \
    --title "feat: <description>" \
    --base main \
    --body '<pr-body>'
```

### 2.5f: Report status

```
## Auto-commit complete
- Branch: <branch-name>
- Committed: <commit count> commit(s)
- Push: succeeded / failed (see above)
- PR: opened at <url> / ready-to-copy command displayed
```

## Step 3: Review — Run code-reviewer

Before launching the code-reviewer, check if TDD mode was used by reading any task file from `tasks/` and looking for a `## TDD Mode` section.

Launch the `code-reviewer` agent using the Task tool with:
- `subagent_type: "code-reviewer"`
- Tell it to review all changes against `tasks/updated-prd.md`
- Tell it to write the review report to `tasks/review-report.md`
- **If TDD mode was used**, include these additional review criteria in the prompt:
  - Were tests written for each task that had TDD mode enabled?
  - Do the tests meaningfully cover the acceptance criteria from the task files?
  - Are there tasks with TDD mode that appear to be missing tests?
  - Do tests follow project conventions?
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

### Review
- [compliance score]
- [critical issues if any]

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
