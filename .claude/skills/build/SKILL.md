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
1. Run `git rev-parse --abbrev-ref HEAD` to get `CURRENT_BRANCH`. If `CURRENT_BRANCH` is `main` or `master`: `BRANCH_ACTION=new`. Else ask: "Branch `<name>` exists — create new or commit here?" → `BRANCH_ACTION=new/current`.
2. Ask: "How should changes be committed?"
   - **Squash** — single commit at the end summarizing all changes
   - **Per-wave** — one commit per parallel execution wave (e.g., Wave 1: 3 tasks → 1 commit)
   - **Per-task at end** — full parallel run, then one atomic commit per task in order
   → `COMMIT_MODE=squash/per-wave/per-task-at-end`
3. Generate `feat/<3-5-word-slug>` from PRD content → `AUTO_COMMIT_BRANCH`.
4. **If `BRANCH_ACTION=new`:**
   - Run `git fetch origin` to get latest remote state.
   - Detect default branch: run `git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||'`. If empty or error, default to `main`. Store as `DEFAULT_BRANCH`.
   - Ask: "Which branch should `<AUTO_COMMIT_BRANCH>` be based on?"
     - Option 1: `<DEFAULT_BRANCH>` (remote default)
     - Option 2: `<CURRENT_BRANCH>` (current branch)
     - Option 3: Other (enter branch name)
   - Store chosen base as `BASE_BRANCH`.
   - **Do not create the branch yet** — Step 0.1b performs the actual `git checkout -b` or `git worktree add -b` based on the worktree choice.

**If `AUTO_COMMIT=false`:** `BRANCH_ACTION=none`, `COMMIT_MODE=none`.

## Step 0.1b: Worktree opt-in and branch creation

Ask: "Run workflow in a new git worktree? (enables running multiple pipelines in parallel in the same project)" (Yes / No) → `USE_WORKTREE`.

Store `WORKTREE_PATH=""` as the default. It is set to the new worktree's relative path only if one is created.

### If `USE_WORKTREE=false`:

- **If `AUTO_COMMIT=true` AND `BRANCH_ACTION=new`**: run `git checkout -b <AUTO_COMMIT_BRANCH> <BASE_BRANCH>`. On failure append `-2` to `AUTO_COMMIT_BRANCH`, retry once.
- Otherwise: take no action here. Continue to Step 0.2.

### If `USE_WORKTREE=true`:

1. **If `AUTO_COMMIT=true` AND `BRANCH_ACTION=current`**: worktrees require a fresh branch (git disallows two worktrees on the same branch). Ask: "Worktree needs a new branch. Switch to a new branch, or skip the worktree and commit on the current branch?"
   - **"Create new branch"** → set `BRANCH_ACTION=new`. Generate `AUTO_COMMIT_BRANCH=feat/<3-5-word-slug>` from the PRD content if not already generated. Run the same base-branch Q&A as Step 0.1 step 4 to pick `BASE_BRANCH`.
   - **"Skip worktree"** → set `USE_WORKTREE=false` and fall through to the `USE_WORKTREE=false` branch above.

2. Resolve the worktree branch and base:
   - **If `AUTO_COMMIT=true`**: `WT_BRANCH=$AUTO_COMMIT_BRANCH`, `WT_BASE=$BASE_BRANCH` (both set in Step 0.1).
   - **If `AUTO_COMMIT=false`**:
     - Ask: "Branch name for the worktree?" Suggest `feat/<3-5-word-slug>` derived from the PRD content. Store as `WT_BRANCH`.
     - Run `git fetch origin` and detect `DEFAULT_BRANCH` (same as Step 0.1 step 4).
     - Get `CURRENT_BRANCH` if not already set.
     - Ask: "Which branch should `<WT_BRANCH>` be based on?" with the same three options (default / current / other). Store as `WT_BASE`.

3. Sanitize `$WT_BRANCH` into a filesystem-safe path segment (same rules as Step 0a's `SANITIZED`): replace `/` with `-`, strip non-`[A-Za-z0-9._-]`, trim leading/trailing dashes. Store as `WT_PATH_SEG`.

4. Create the worktree and branch atomically:
   ```bash
   git worktree add -b "$WT_BRANCH" ".claude-worktrees/$WT_PATH_SEG" "$WT_BASE"
   ```
   On failure (branch or path already exists), append `-2` to both `$WT_BRANCH` and `$WT_PATH_SEG` and retry once. If it still fails, abort with a clear error to the user. **If the retry succeeds and `AUTO_COMMIT=true`, set `AUTO_COMMIT_BRANCH=$WT_BRANCH`** so downstream commit/push/PR/report steps target the renamed branch.

5. `cd ".claude-worktrees/$WT_PATH_SEG"`. All subsequent steps run inside the worktree.

6. Set `WORKTREE_PATH=".claude-worktrees/$WT_PATH_SEG"` for the final report.

## Step 0.2: Orchestration Mode Selection

Check for a saved orchestration mode preference:
- Run: `cat ~/.claude/user-preferences.json 2>/dev/null`
- If the file exists and contains an `"orchestrationMode"` key:
  - Log: "Using saved orchestration mode: `<value>`"
  - Set `ORCHESTRATION_MODE` to the saved value (`parallel` or `agent-teams`)
  - Skip the rest of this step and proceed to Step 0.

If no saved preference, ask the user which orchestration mode to use:

Use `AskUserQuestion` with:
- Question: "How should tasks be implemented?"
- Options:
  - **Default (Recommended)**: Use `parallel-task-orchestrator` — proven sub-agent approach with wave-based parallel execution
  - **Agent Teams (Beta)**: Use Claude Code's native Agent Teams feature — separate sessions coordinating via shared task list

Store the result as `ORCHESTRATION_MODE` (`parallel` or `agent-teams`).

Then ask: "Save this as your default orchestration mode?" (Yes / No).

If Yes: run this command, replacing `<ORCHESTRATION_MODE>` with the actual value (`parallel` or `agent-teams`):
```bash
MODE=<ORCHESTRATION_MODE> python3 -c "
import json, os
path = os.path.expanduser('~/.claude/user-preferences.json')
prefs = json.load(open(path)) if os.path.exists(path) else {}
prefs['orchestrationMode'] = os.environ['MODE']
json.dump(prefs, open(path, 'w'), indent=2)
"
```

## Step 0: Resolve TASKS_DIR + clean up

### Step 0a: Resolve TASKS_DIR

Run the following in Bash to determine the branch-scoped task directory:

```bash
RAW_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
if [ -z "$RAW_BRANCH" ] || [ "$RAW_BRANCH" = "HEAD" ]; then
  SHORT_SHA=$(git rev-parse --short HEAD 2>/dev/null || echo "")
  RAW_BRANCH=${SHORT_SHA:+detached-$SHORT_SHA}
fi
if [ -z "$RAW_BRANCH" ]; then
  echo "Warning: not a git repo — using tasks/ as task directory" >&2
  TASKS_DIR="tasks"
else
  SANITIZED=$(echo "$RAW_BRANCH" | tr '/' '-' | tr -cs 'A-Za-z0-9._-' '-' | sed 's/^-*//; s/-*$//')
  [ -z "$SANITIZED" ] && SANITIZED="unknown-branch"
  TASKS_DIR="tasks/$SANITIZED"
fi
```

Store `TASKS_DIR` as a session variable — use it everywhere below.

### Step 0b: Clean up stale task files

Use Bash to run `rm -rf "$TASKS_DIR"` to clear only this branch's task directory.
This prevents stale task files from being picked up by the orchestrator.

## Step 0.5 (if BRAINSTORM=true): Design brainstorm

**Skip this step if BRAINSTORM=false.**

1. Launch the `prd-task-planner` agent using the Task tool with:
   - `subagent_type: "prd-task-planner"`
   - Prompt:
     ```
     TASKS_DIR=$TASKS_DIR
     MODE: BRAINSTORM

     <clean PRD content>
     ```
   - Wait for it to complete. **Save the returned agent ID** — this agent will be resumed in Step 1a.

2. Read `$TASKS_DIR/design-options.md`.

3. Present the design options to the user using `AskUserQuestion`. Build one question per option listed in the file, using the option names as labels and their summaries/trade-offs as descriptions. Include a "Custom direction" option. Ask: "Which design approach should we use for this feature?"

4. Collect the user's chosen option. Store it as `CHOSEN_DESIGN`.

## Step 1: Plan — Two-phase planning with user Q&A

### Step 1a: Discovery — Explore codebase & surface questions

**If BRAINSTORM=true** — resume the agent from Step 0.5:
- `resume: "<agent-id-from-step-0.5>"`
- Prompt:
  ```
  TASKS_DIR=$TASKS_DIR
  MODE: DISCOVERY

  Chosen design direction: <CHOSEN_DESIGN>

  <clean PRD content>
  ```
- Tell it to output questions to `$TASKS_DIR/planning-questions.md`
- The agent already has full codebase context from the brainstorm phase — it will skip re-exploration.

**If BRAINSTORM=false** — launch a fresh agent:
- `subagent_type: "prd-task-planner"`
- Prompt:
  ```
  TASKS_DIR=$TASKS_DIR
  MODE: DISCOVERY

  <PRD content>
  ```
- Tell it to output questions to `$TASKS_DIR/planning-questions.md`

Wait for it to complete. **Save the returned agent ID** — you will resume this agent in Step 1c.

### Step 1b: User Q&A — Present questions and collect answers

1. Read `$TASKS_DIR/planning-questions.md`
2. Present each question to the user using `AskUserQuestion` — use the questions, context, and options from the file to construct clear choices
3. Collect all answers

### Step 1c: Generate — Resume planner with answers

Resume the **same** prd-task-planner agent (using the agent ID from Step 1a) with:
- `resume: "<agent-id-from-step-1a>"`
- Provide all user answers in the prompt, formatted clearly
- Prepend `MODE: GENERATE` to the prompt
- Tell it to generate the updated PRD and task files in `$TASKS_DIR/`

Wait for it to complete. Confirm that task files were created in `$TASKS_DIR/`.

### Step 1d: Task review — Present plan and get approval

This step always runs. Do not skip it.

1. Read all `task-*.md` files from `$TASKS_DIR/`. For each, extract:
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
   Then add: "You can also open and edit any file in `$TASKS_DIR/` directly before proceeding."

3. Use `AskUserQuestion` with a single question: "How would you like to proceed?"
   - **"Looks good — start implementation"** — continue to Step 1e
   - **"Regenerate with feedback"** — user provides feedback via the "Other" field

4. **If user approves**: proceed to Step 1e.

5. **If user requests regeneration**: resume the **same** prd-task-planner agent (from Step 1a/1c) with:
   - `resume: "<agent-id-from-step-1a>"`
   - Prompt: `MODE: GENERATE\n\nUser feedback on the task plan:\n<feedback>\n\nPlease regenerate the task files incorporating this feedback.`
   - Wait for it to complete, then **loop back to the top of Step 1d** to re-present the updated plan.

## Step 1e: Fast-path detection — Should we skip the orchestrator?

Before launching the orchestrator, analyze the task files to determine if orchestration overhead is justified.

**Read all `$TASKS_DIR/task-*.md` files and extract:**
1. Total task count
2. Per-task: files to modify (from `## Files to Modify` or `## Context Files` sections)
3. Per-task: explicit dependencies (from `## Dependencies` or `Depends on:` lines)

**Classify as `FAST_PATH=true` if ANY of these conditions are met:**
- **2 or fewer tasks** (regardless of dependencies)
- **All tasks are sequential**: every task depends on the previous one (linear chain), OR all tasks touch overlapping files (no parallelism possible)
- **Most tasks are sequential**: only 1 task out of 3+ could run in parallel (orchestrator adds overhead for negligible parallelism)

**Set `FAST_PATH=false` otherwise** (3+ tasks with real parallelism opportunities).

## Step 1f: Plan review — Validate task plan soundness

**Skip this step only if there are 2 or fewer tasks.** Plan review is cheap insurance for any plan large enough to have real dependency or scoping risk — run it even for 3+ task sequential plans (FAST_PATH decoupling: skipping the orchestrator is not a reason to skip the sanity check).

**Initialize `PLAN_REVIEW_ITER = 1`** as you enter Step 1f (before 1f.1). Increment it each time you loop back to 1f.1 from 1f.3. Used below to drive the iteration-3 nudge.

### 1f.1: Launch plan review

Launch the `code-reviewer` agent using the Task tool with:
- `subagent_type: "code-reviewer"`
- Prompt:
  ```
  TASKS_DIR=$TASKS_DIR

  MODE: PLAN REVIEW

  Apply the five plan-review checks defined under the "Plan Review Criteria" heading in your own agent definition: (1) Dependency soundness, (2) PRD coverage gaps, (3) Task file conflicts, (4) Task sizing, (5) TDD spec consistency.

  Read all `$TASKS_DIR/task-*.md` files and `$TASKS_DIR/updated-prd.md` before running the checks. Write the plan review report to `$TASKS_DIR/plan-review-report.md`. You MUST emit the `### Plan Issues Found` section with all three severity buckets (Critical / Important / Minor) — use `- None` for buckets with no issues. Do not omit the section or any sub-heading.
  ```

Wait for it to complete.

### 1f.2: Present plan review results

1. Read `$TASKS_DIR/plan-review-report.md`. Extract the `### Plan Issues Found` section (Critical / Important / Minor items).

2. Present the plan issues summary to the user as a formatted list. If no issues were found in any category, note "No plan issues found."

3. Use `AskUserQuestion` with a single question: "How would you like to proceed?"
   - **"Proceed anyway"** — continue to Step 2 (even if issues were found)
   - **"Regenerate with feedback"** — user provides feedback via the "Other" field; the planner will regenerate task files incorporating the plan review findings and user feedback
   - **"Edit files manually"** — user edits task files in `$TASKS_DIR/` directly, then re-runs plan review

### 1f.3: Handle user choice

(The `PLAN_REVIEW_ITER` counter was initialized at the top of Step 1f. Read below for how it gates the soft nudge.)

**Loop guardrail — soft nudge after iteration 3.** If `PLAN_REVIEW_ITER >= 3` AND the user's choice at 1f.2 was either "Regenerate with feedback" or "Edit files manually" (i.e., any choice that will cause a loop-back to 1f.1), insert this message before proceeding with that choice: "Heads up — this is plan-review iteration N. If the reviewer keeps flagging the same class of issue, consider either editing files manually (if you haven't), picking 'Proceed anyway' and fixing at implementation time, or stopping to revise the PRD itself." Then honor the user's choice. The nudge fires on every looping iteration from N=3 onward, not just once. Do not hard-cap the loop.

**If "Proceed anyway"**:
Log "Plan review issues noted. Proceeding to implementation." Continue to Step 2. This is a valid exit regardless of whether issues remain.

**If "Regenerate with feedback"**:

1. Collect the user's feedback from their `AskUserQuestion` response (the "Other" field).
2. **Validate feedback is non-empty.** If the user picked "Regenerate with feedback" but left the "Other" field blank (or provided only whitespace), re-prompt via `AskUserQuestion`: "Regeneration needs either specific feedback or a direction. Provide feedback, or switch to 'Edit files manually' / 'Proceed anyway'." Do not resume the planner with an empty feedback block — it has no new signal to work from and will likely produce a near-identical plan.
3. Read `$TASKS_DIR/plan-review-report.md` and extract the `### Plan Issues Found` section contents (the reviewer's output contract guarantees this section exists).
4. Resume the **same** `prd-task-planner` agent (agent ID from Step 1a) with:
   - `resume: "<agent-id-from-step-1a>"`
   - Prompt: `TASKS_DIR=$TASKS_DIR\n\nMODE: GENERATE\n\nPlan review found issues requiring changes. User feedback:\n<feedback text collected in step 1>\n\nPlan review findings:\n<contents of "### Plan Issues Found" section extracted in step 3>\n\nPlease regenerate the task files addressing these issues.`
5. Wait for regeneration to complete.
6. Increment `PLAN_REVIEW_ITER` and **loop back to the top of Step 1f.1** — re-run the plan review on the new task files.

**If "Edit files manually"**:

1. Display: "Edit the files in `$TASKS_DIR/` directly. When done, reply to continue."
2. Wait for user confirmation.
3. Increment `PLAN_REVIEW_ITER` and **loop back to the top of Step 1f.1** — re-run the plan review against the edited files.

**Loop exit conditions.** The loop exits whenever the user selects "Proceed anyway" at Step 1f.2, regardless of iteration count or remaining issues. A clean review ("No plan issues found") still requires the user to confirm via "Proceed anyway" — the skill does not auto-advance. There is no hard retry cap.

## Step 2: Implement

### Fast path (`FAST_PATH=true`) — Direct implementation

> **Note**: If `ORCHESTRATION_MODE=agent-teams` was selected, inform the user: "Fast-path detected (≤2 tasks or all sequential). Using direct implementation instead of Agent Teams — orchestration overhead is not justified for simple tasks." The env var setup from Step 0.2 is skipped in fast-path mode.

Implement the tasks yourself, sequentially, in the current conversation context. For each task file in order:

1. Read the task file fully (objective, requirements, acceptance criteria, context files)
2. Read all referenced context files
3. Implement the task following the requirements and acceptance criteria
4. If the task has a `## TDD Mode` section, follow the RED → GREEN → REFACTOR → VERIFY cycle (including test adequacy check)
5. After each task, collect the Implementation Notes section from your work. After all tasks are done, write `$TASKS_DIR/implementation-notes.md` consolidating all notes.
6. **If `COMMIT_MODE=per-wave`:** after completing each task, check if the current "wave" (group of sequential tasks with no parallelism in fast-path) warrants a commit. In fast-path mode, commit after each task:
   ```bash
   git add -A
   git diff --staged --quiet || git commit -m "feat: <task-objective-from-task-file>"
   ```
   **If `COMMIT_MODE=per-task-at-end`:** skip — commits are created in Step 2.5b after all tasks complete.

This avoids orchestrator overhead and gives you continuous context across tasks — each task benefits from seeing the work done in previous tasks without reading files cold.

### Full path (`FAST_PATH=false`) — Run orchestrator

**If `ORCHESTRATION_MODE=parallel`** (default):

Launch the `parallel-task-orchestrator` agent using the Task tool with:
- `subagent_type: "parallel-task-orchestrator"`
- Prompt:
  ```
  TASKS_DIR=$TASKS_DIR
  Read and execute all tasks from `$TASKS_DIR/`
  ```
- **If `COMMIT_MODE=per-wave`**: Include `COMMIT_MODE=per-wave` in the launch prompt so the orchestrator commits after each wave. Also include: `Use commit subject prefix 'feat:' instead of 'refactor:' for per-wave commits.`
- **If `COMMIT_MODE=squash`, `per-task-at-end`, or `AUTO_COMMIT=false`**: Launch normally with no additional commit instructions.

Wait for it to complete. Note any issues reported.

**If `ORCHESTRATION_MODE=agent-teams`** (Beta):

> **Before starting**: Verify no Agent Teams team is already active in this session. If team creation fails, inform the user and fall back to the default `parallel-task-orchestrator` approach automatically. See `agent-teams-orchestrator.md` → Known Limitations for details.

First, enable the required env var by finding the user's settings file (check `.claude/settings.local.json`, then `.claude/settings.json`, then `~/.claude/settings.json`) and adding `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` to the `env` object, preserving all existing settings. If no settings file exists, create `.claude/settings.local.json` with the env var.

Do NOT spawn a sub-agent. Instead, execute Agent Teams orchestration directly in this session:
1. Read `.claude/agents/agent-teams-orchestrator.md` (check `~/.claude/agents/` for global installs, `.claude/agents/` for local)
2. Follow those instructions directly in this session to orchestrate tasks using Agent Teams teammates, passing `TASKS_DIR=$TASKS_DIR` so teammates know where to read and write task files
3. Produce the same outputs: `$TASKS_DIR/implementation-notes.md` and `$TASKS_DIR/execution-metrics.md`

Note: Per-wave commits in Agent Teams mode are handled by the agent-teams-orchestrator when `COMMIT_MODE=per-wave` is passed in the session context. Per-task-at-end commits are handled by the skill layer in Step 2.5b (runs after Agent Teams execution completes). Auto-commit/branch handling (if `AUTO_COMMIT=true`) applies identically to both modes.

After Agent Teams execution completes (whether successful or not), **clean up the env var**: read the settings file that was modified above, remove `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` from the `env` object, and write it back. If the `env` object is now empty, remove it entirely. This prevents the beta env var from persisting across future sessions.

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

- **`COMMIT_MODE=squash`**: Read all `$TASKS_DIR/task-*.md` files. Extract the `## Objective` line from each. Run:
  ```bash
  git add -A
  git commit -m "feat: <PRD summary>" -m "$(cat <<'EOF'
  - <objective from task-01>
  - <objective from task-02>
  - <objective from task-03>
  ... (one bullet per task, no cap)
  EOF
  )"
  ```
  Subject line: 72-char max. Body: one bullet per task objective, all listed (no bullet cap).

- **`COMMIT_MODE=per-wave`**: Commits were made by the orchestrator (or fast-path) during execution. Run `git add -A` to catch any unstaged changes left after the final wave, then commit any remainder:
  ```bash
  git add -A
  git diff --staged --quiet || git commit -m "feat: post-run cleanup"
  ```
  If nothing is staged after `git add -A`, skip the final commit.

- **`COMMIT_MODE=per-task-at-end`**: Full parallel run is complete. Now create one commit per task in task-file order:
  1. Run `git add -A` to stage all changes.
  2. Read each `$TASKS_DIR/task-NN-*.md` file in numerical order.
  3. For each task, extract its `## Objective` line and the list of files it touched (from the `## Target Files` section).
  4. Use `git restore --staged .` to unstage everything, then selectively stage only the files for this task using `git add <file1> <file2> ...`, then commit:
     ```bash
     git restore --staged .
     git add <files for this task>
     git commit -m "feat: <task objective>"
     ```
  5. Repeat for each task in order.
  6. After all per-task commits, run `git add -A && git diff --staged --quiet || git commit -m "feat: miscellaneous changes"` to catch any files not covered by the task-file manifests.

**2.5d Push:** `git push -u origin <branch-name>`. On failure, show manual command and continue.

**2.5e PR:** Run `gh auth status 2>/dev/null && echo GH_OK || echo GH_UNAVAILABLE`.
- `GH_OK`: Create PR body (1-2 sentence summary + "## Changes" task objectives + "## Review Notes" placeholder). Run `gh pr create --title "feat: <desc>" --body "<body>" --base main`. Display URL.
- `GH_UNAVAILABLE`: Display ready-to-copy `gh pr create` command.

**2.5f Report:** `Branch: <name> | Commits: <N> | Push: ok/failed | PR: <url or manual>`

## Step 3: Review — Run code-reviewer

Before launching the code-reviewer, check if TDD mode was used by reading any task file from `$TASKS_DIR/` and looking for a `## TDD Mode` section. Also check if `$TASKS_DIR/implementation-notes.md` and `$TASKS_DIR/execution-metrics.md` exist.

Launch the `code-reviewer` agent using the Task tool with:
- `subagent_type: "code-reviewer"`
- Prompt:
  ```
  TASKS_DIR=$TASKS_DIR
  Review all changes against `$TASKS_DIR/updated-prd.md` and write the review report to `$TASKS_DIR/review-report.md`.
  ```
- **If `$TASKS_DIR/implementation-notes.md` exists**, tell it to read this file for implementer decision context
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

Read `$TASKS_DIR/review-report.md`. Check if the `### Critical` section contains any items.

**If critical issues are found:**
1. Collect all items listed under `### Critical` (file paths, line numbers, descriptions)
2. For each distinct file affected, launch a `task-implementer` sub-agent (parallel where no file conflicts) with a prompt that includes:
   - `TASKS_DIR=$TASKS_DIR` so the sub-agent knows where shared-context lives
   - The specific critical issue(s) for that file verbatim from the report
   - Instruction to fix only these specific issues, touching no other code
3. Wait for all task-implementers to complete.
4. Re-run the code-reviewer (same criteria as Step 3) **once more** against `$TASKS_DIR/updated-prd.md`. Write the updated report to `$TASKS_DIR/review-report.md` (overwrite).

**If no critical issues:** proceed directly to Step 4.

Do not loop — the auto-fix runs at most once. If critical issues persist after the retry, report them in Step 4.

## Step 4: Report

Check if `$TASKS_DIR/execution-metrics.md` exists (produced by the orchestrator in full-path mode). If not (fast-path mode), generate equivalent metrics from your own execution.

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
- Implementation notes: [see $TASKS_DIR/implementation-notes.md or "inline above"]

### Review
- [compliance score]
- [critical issues if any]
- [if implementation notes reviewed: decision assessment summary]

### Auto-Commit
- [skipped — not enabled]
  OR
- Branch: <branch-name>
- PR: <url or "manual command displayed">

### Worktree
- [omit this section entirely if `WORKTREE_PATH` is empty]
  OR
- Path: <WORKTREE_PATH>
- Cleanup: `git worktree remove <WORKTREE_PATH>` (run from the original repo root)

### Next Steps
- [what the user should do — e.g., run tests, fix issues, deploy]
```

## Rules
- Run the steps **sequentially** — each depends on the previous
- If Step 1 fails (no tasks created), stop and report the issue
- If Step 2 has partial failures, still run Step 3 to review what was completed
- Always run Step 3 — never skip the review
