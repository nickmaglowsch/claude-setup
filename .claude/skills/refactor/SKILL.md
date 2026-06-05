---
name: refactor
description: "Refactoring pipeline: analyzes a target file or directory for code quality issues, plans safe incremental improvements, optionally writes tests first as a safety net, implements the changes, and reviews the result. Orchestrates refactor-planner → (test-writer) → parallel-task-orchestrator → code-reviewer."
argument-hint: "<file, directory, or description of what to refactor>"
---

# Refactor Pipeline

You are orchestrating the full refactoring pipeline. Follow these steps strictly in order.

## Input

The refactoring target (file path, directory, or description of what to improve):

$ARGUMENTS

## Step 0.03: Cheap routing check — should this be `/refactor-lite`?

Before asking auto-commit, worktree, or orchestration questions, spend at most 2-3 minutes on a bounded read-only check:
- Identify the target file(s) or package.
- Use targeted `Glob`/`Grep`/bounded `Read` only where needed to estimate scope, callers, and whether independent parallel work exists.
- Do not launch planner/test-writer/reviewer/implementer agents in this step.

Route to `/refactor-lite` and stop this workflow if the refactor appears to be any of:
- 1-2 likely refactor tasks.
- A single target file/module, or mostly overlapping target files.
- A linear sequence such as rename → extract → simplify → verify.
- A cleanup where task isolation would force multiple agents to re-read the same code.
- Documentation/config-only cleanup.

Proceed with full `/refactor` only when the work likely needs 3+ independent refactor tasks that can run in parallel, or when the target is broad enough to exceed a single warm context.

If routing to lite, tell the user: "This looks cheaper and equally safe as `/refactor-lite` because <reason>. Switching to the lite workflow." Then immediately follow `.claude/skills/refactor-lite/SKILL.md` from Step 1 using the same `$ARGUMENTS`, skipping all remaining full `/refactor` steps.

## Step 0.1: Auto-commit opt-in

Ask: "Enable auto-commit and PR?" (Yes / No) → `AUTO_COMMIT`.

**If `AUTO_COMMIT=true`:**
1. Run `git rev-parse --abbrev-ref HEAD` to get `CURRENT_BRANCH`. If `CURRENT_BRANCH` is `main` or `master`: `BRANCH_ACTION=new`. Else ask: "Branch `<name>` exists — create new or commit here?" → `BRANCH_ACTION=new/current`.
2. Ask: "How should changes be committed?"
   - **Squash** — single commit at the end summarizing all changes
   - **Per-wave** — one commit per parallel execution wave (e.g., Wave 1: 3 tasks → 1 commit)
   - **Per-task at end** — full parallel run, then one atomic commit per task in order
   → `COMMIT_MODE=squash/per-wave/per-task-at-end`
3. Generate `refactor/<3-5-word-slug>` from `$ARGUMENTS` → `AUTO_COMMIT_BRANCH`.
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
   - **"Create new branch"** → set `BRANCH_ACTION=new`. Generate `AUTO_COMMIT_BRANCH=refactor/<3-5-word-slug>` from `$ARGUMENTS` if not already generated. Run the same base-branch Q&A as Step 0.1 step 4 to pick `BASE_BRANCH`.
   - **"Skip worktree"** → set `USE_WORKTREE=false` and fall through to the `USE_WORKTREE=false` branch above.

2. Resolve the worktree branch and base:
   - **If `AUTO_COMMIT=true`**: `WT_BRANCH=$AUTO_COMMIT_BRANCH`, `WT_BASE=$BASE_BRANCH` (both set in Step 0.1).
   - **If `AUTO_COMMIT=false`**:
     - Ask: "Branch name for the worktree?" Suggest `refactor/<3-5-word-slug>` derived from `$ARGUMENTS`. Store as `WT_BRANCH`.
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

## Step 1: Plan — Two-phase planning with user Q&A

### Step 1a: Discovery — Analyze code & surface questions

Launch the `refactor-planner` agent using the Task tool with:
- `subagent_type: "refactor-planner"`
- Prompt: `MODE: DISCOVERY\n\nTarget: <target from $ARGUMENTS>\nTASKS_DIR=$TASKS_DIR`
- Tell it to output questions to `$TASKS_DIR/refactor-questions.md`

Wait for it to complete. **Save the returned agent ID** — you will resume this agent in Step 1c.

### Step 1b: User Q&A — Present questions and collect answers

1. Read `$TASKS_DIR/refactor-questions.md`
2. Present the code audit summary and each question to the user using `AskUserQuestion`
3. Collect all answers — pay special attention to:
   - Whether the user wants tests written first (Step 1.5 gate)
   - Scope and backward compatibility constraints

### Step 1c: Generate — Resume planner with answers

Resume the **same** refactor-planner agent (using the agent ID from Step 1a) with:
- `resume: "<agent-id-from-step-1a>"`
- Provide all user answers in the prompt, formatted clearly
- Prepend `MODE: GENERATE` to the prompt
- Tell it to generate the refactoring task files and `$TASKS_DIR/refactor-plan.md` in `$TASKS_DIR/`
- Include `TASKS_DIR=$TASKS_DIR` in the resume prompt

Wait for it to complete. Confirm that task files were created in `$TASKS_DIR/`.

### Step 1d: Task review — Present plan and get approval

This step always runs. Do not skip it.

1. Read all `task-*.md` files from `$TASKS_DIR/`. For each, extract:
   - Task number and title
   - Objective
   - Dependencies

2. Present the full refactoring plan to the user:
   ```
   ## Refactoring Plan (N tasks)

   1. task-01-name — [Objective]
      Dependencies: None
   2. task-02-name — [Objective]
      Dependencies: task-01
   ...
   ```
   Then add: "You can also open and edit any file in `$TASKS_DIR/` directly before proceeding."

3. Use `AskUserQuestion` with a single question: "How would you like to proceed?"
   - **"Looks good — start refactoring"** — continue to Step 1.5
   - **"Regenerate with feedback"** — user provides feedback via the "Other" field

4. **If user approves**: proceed to Step 1.5.

5. **If user requests regeneration**: resume the **same** refactor-planner agent (from Step 1a) with:
   - `resume: "<agent-id-from-step-1a>"`
   - Prompt: `MODE: GENERATE\n\nTASKS_DIR=$TASKS_DIR\n\nUser feedback on the refactoring plan:\n<feedback>\n\nPlease regenerate the task files incorporating this feedback.`
   - Wait for it to complete, then **loop back to the top of Step 1d**.
   - **Iteration cap**: max 3 regeneration cycles. If the user requests a 4th, stop looping — surface the stuck state and ask whether to abort the workflow or proceed to Step 1.5 with the current plan.

## Step 1.5: Safety net — Write missing tests (if requested)

**Skip this step if the user did not ask for tests to be written first.**

If the user answered yes to writing tests before refactoring:

Launch the `test-writer` agent using the Task tool with:
- `subagent_type: "test-writer"`
- Prompt: `Write tests for <target> to create a safety net before refactoring. Focus on covering the behavior that the refactoring tasks will touch.`

Wait for it to complete, then read the test-writer's final output. It reports whether the tests it wrote pass. If all tests pass, proceed to Step 1.6. If any test fails, do NOT proceed — surface the failures to the user and ask whether to abort or to fix the failing tests first.

## Step 1.6: Fast-path detection — Should we skip the orchestrator?

Read all `$TASKS_DIR/task-*.md` files and classify `FAST_PATH=true` if ANY of:
- 2 or fewer tasks (regardless of dependencies)
- All tasks are sequential: linear dependency chain OR all tasks touch overlapping files (no parallelism possible)
- Only 1 task out of 3+ could run in parallel (orchestrator adds overhead for negligible parallelism)

Otherwise `FAST_PATH=false`.

Refactoring task files often have linear dependency chains (rename → extract → simplify → decompose) and tend toward fast-path more than feature builds.

## Step 2: Implement

### Fast path (`FAST_PATH=true`) — Direct implementation

If `ORCHESTRATION_MODE=agent-teams`: inform the user "Fast-path detected — using direct implementation instead of Agent Teams; orchestration overhead is not justified for simple refactors." Skip the env-var setup from Step 0.2.

Implement tasks yourself, sequentially, in the current session. For each task file in order: (1) read the task file fully, (2) read any referenced tests, (3) apply the refactor, (4) run **the project test command** (the same one Step 1.5 used to write the safety net, or whichever command the task file specifies) to verify behavior is preserved — refactor tasks rarely have their own per-task test commands; the safety net is the verification surface, (5) write `$TASKS_DIR/notes/task-NN.md` with notes on what was changed and why, plus anything risky for review (Decisions / Deviations / Trade-offs / Risks). After all tasks: concatenate `$TASKS_DIR/notes/task-*.md` (sorted) into `$TASKS_DIR/implementation-notes.md` with a `# Implementation Notes` header.

Commit handling: if `COMMIT_MODE=per-wave`, after each task run `git add -A && git diff --staged --quiet || git commit -m "refactor: <task-objective>"`. If `COMMIT_MODE=per-task-at-end`, skip — commits happen in Step 2.5b.

Fast-path keeps continuous session context across tasks (no cold reads) and avoids the orchestrator overhead, which is rarely justified for refactors with sequential dependencies.

### Full path (`FAST_PATH=false`) — Run orchestrator

**If `ORCHESTRATION_MODE=parallel`** (default):

Launch the `parallel-task-orchestrator` agent using the Task tool with:
- `subagent_type: "parallel-task-orchestrator"`
- Tell it to read and execute all tasks from `$TASKS_DIR/`
- Include `TASKS_DIR=$TASKS_DIR` in the launch prompt
- Tell it to batch same-wave tasks that share module/directory context when safe, and to keep sub-agent returns short because detailed notes must be written to `$TASKS_DIR/notes/`.
- **If `COMMIT_MODE=per-wave`**: Include `COMMIT_MODE=per-wave` in the launch prompt so the orchestrator commits after each wave.
- **If `COMMIT_MODE=squash`, `per-task-at-end`, or `AUTO_COMMIT=false`**: Launch normally with no additional commit instructions.

Wait for it to complete. Note any issues reported.

**If `ORCHESTRATION_MODE=agent-teams`** (Beta):

First, enable the required env var by finding the user's settings file (check `.claude/settings.local.json`, then `.claude/settings.json`, then `~/.claude/settings.json`) and adding `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` to the `env` object, preserving all existing settings. If no settings file exists, create `.claude/settings.local.json` with the env var.

Do NOT spawn a sub-agent. Instead, execute Agent Teams orchestration directly in this session:
1. Read `.claude/agents/agent-teams-orchestrator.md` (check `~/.claude/agents/` for global installs, `.claude/agents/` for local)
2. Follow those instructions directly in this session to orchestrate tasks using Agent Teams teammates, passing `TASKS_DIR=$TASKS_DIR` as session context
3. Produce the same outputs: `$TASKS_DIR/implementation-notes.md` and `$TASKS_DIR/execution-metrics.md`

Note: Per-wave commits in Agent Teams mode are handled by the agent-teams-orchestrator when `COMMIT_MODE=per-wave` is passed in the session context. Per-task-at-end commits are handled by the skill layer in Step 2.5b (runs after Agent Teams execution completes).

After Agent Teams execution completes (whether successful or not), **clean up the env var**: read the settings file that was modified above, remove `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` from the `env` object, and write it back. If the `env` object is now empty, remove it entirely. This prevents the beta env var from persisting across future sessions.

## Step 2b: Build check — Verify the project compiles

Run a quick build/lint check to catch obvious breakage:
- Look for a `package.json`, `Makefile`, `Cargo.toml`, or similar build config
- Run the appropriate build command (e.g., `npm run build`, `pnpm build`, `make`, `cargo check`)
- If the build fails, report to the user and ask whether to proceed or fix first
- If no build system is detected, skip this step

## Step 2c: Test verification — Confirm behavior is preserved

This step is especially critical for refactoring — the primary success criterion is that all existing tests still pass.

- Run the full test suite (e.g., `npm test`, `pnpm test`, `pytest`, `go test ./...`, `cargo test`)
- If tests fail: report the failures and ask whether to fix, proceed anyway, or stop
- If no test suite exists, note this prominently — behavior preservation cannot be verified automatically

## Step 2d: Simplify — Final polish pass (opt-in, one pass)

The refactor tasks already did the structural work (rename/extract/decompose). A `/simplify` pass is an optional final polish that catches local cleanups the tasks introduced. It **mutates code**, so behavior preservation must be re-verified — the same primary success criterion as the refactor itself.

**Guard:** Only offer this step if Step 2c passed with no regressions. If tests failed or there is no test suite to verify against, **skip this step entirely** — never apply unverifiable cleanups on top of a refactor. Set `SIMPLIFY_RAN=false`.

1. Use `AskUserQuestion`: "Run a `/simplify` polish pass on the refactored code before review?"
   - **"Yes — simplify"** — run the polish pass
   - **"No — skip"** → set `SIMPLIFY_RAN=false` and proceed to Step 2.5

2. **If "Yes"**: invoke the `simplify` skill via the Skill tool. Tell it to scope to the full branch diff against the base branch, so changes already committed in `per-wave`/`per-task-at-end` modes are covered — not just uncommitted edits. Wait for it to finish.

3. **Re-verify behavior preservation**: re-run the Step 2b build check and the full test suite from Step 2c.
   - If any test that passed before now fails, the cleanup broke behavior: report the regressions and ask whether to (a) keep simplify's changes and continue, (b) revert the simplify changes (`git checkout -- <files>` / `git restore`) and continue, or (c) stop. Do not silently proceed — behavior preservation is the contract.
   - If green, set `SIMPLIFY_RAN=true`.

Simplify's edits are left uncommitted and flow into the existing Step 2.5b commit logic.

## Step 2.5: Auto-commit and PR

**Skip if `AUTO_COMMIT=false`.**

**2.5a Safety:** Run `git rev-parse --abbrev-ref HEAD`. If `main`/`master`: abort ("Auto-commit aborted: on main/master. Commit manually.") → proceed to Step 3.

**2.5b Commit:**

- **`COMMIT_MODE=squash`**: Read all `$TASKS_DIR/task-*.md` files. Extract the `## Objective` line from each. Run:
  ```bash
  git add -A
  git commit -m "refactor: <$ARGUMENTS summary>" -m "$(cat <<'EOF'
  - <objective from task-01>
  - <objective from task-02>
  - <objective from task-03>
  ... (one bullet per task, no cap)
  EOF
  )"
  ```
  Subject line: 72-char max. Body: one bullet per task objective, all listed (no 3-bullet cap).

- **`COMMIT_MODE=per-wave`**: Commits were made by the orchestrator during execution. Run `git add -A` to catch any unstaged changes left after the final wave, then commit any remainder:
  ```bash
  git add -A
  git diff --staged --quiet || git commit -m "refactor: post-run cleanup"
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
     git commit -m "refactor: <task objective>"
     ```
  5. Repeat for each task in order.
  6. After all per-task commits, run `git add -A && git diff --staged --quiet || git commit -m "refactor: miscellaneous changes"` to catch any files not covered by the task-file manifests.

**2.5d Push:** `git push -u origin <branch-name>`. On failure, show manual command and continue.

**2.5e PR:** Run `gh auth status 2>/dev/null && echo GH_OK || echo GH_UNAVAILABLE`.
- `GH_OK`: Create PR body (1-2 sentence summary + "## Changes" task bullets + "## Behavior Preservation" noting test results). Run `gh pr create --title "refactor: <desc>" --body "<body>" --base main`. Display URL.
- `GH_UNAVAILABLE`: Display ready-to-copy `gh pr create` command.

**2.5f Report:** `Branch: <name> | Commits: <N> | Push: ok/failed | PR: <url or manual>`

## Step 3: Review — Run code-reviewer

Check if `$TASKS_DIR/implementation-notes.md` and `$TASKS_DIR/execution-metrics.md` exist (produced by the orchestrator).

Before launching the reviewer, gather a compact review packet:
- Resolve `DEFAULT_BRANCH` from `origin/HEAD` with `main` fallback.
- Capture `git diff --stat $DEFAULT_BRANCH...HEAD`, `git diff --name-only $DEFAULT_BRANCH...HEAD`, and `git log --oneline $DEFAULT_BRANCH..HEAD`.
- Capture build/test commands run in Steps 2b/2c and their pass/fail summaries. Do not paste full logs unless failures need specific excerpts.

Launch the `code-reviewer` agent using the Task tool with:
- `subagent_type: "code-reviewer"`
- Tell it to review all changes against `$TASKS_DIR/refactor-plan.md`
- **If `$TASKS_DIR/implementation-notes.md` exists**, tell it to read this file for implementer decision context
- Tell it to write the review report to `$TASKS_DIR/refactor-review-report.md`
- Include `TASKS_DIR=$TASKS_DIR` in the launch prompt
- Include the compact review packet in the prompt. Tell it to review diff-scoped changes first, reading changed files and requirement files as needed, and to expand to unchanged files only when required to verify behavior, contracts, or conventions.
- Include these refactor-specific review criteria in the prompt:
  - Is behavior preserved? Are there any logic changes that shouldn't be there?
  - Do all existing tests still pass?
  - Is the code measurably cleaner, simpler, or more maintainable than before?
  - Are the changes minimal and focused — no unrelated modifications?
  - If the scope included public APIs, are signatures preserved (or are breaking changes intentional and documented)?
- **If `SIMPLIFY_RAN=true`**: append `A /simplify polish pass already ran on these changes — do NOT re-flag reuse, simplification, efficiency, or altitude items as Minor issues. Focus on behavior preservation, correctness, and whether the code is measurably cleaner.` so the report stays signal-dense.

Wait for it to complete.

## Step 4: Report

Summarize the full refactoring run to the user:

Check if `$TASKS_DIR/execution-metrics.md` exists (produced by the orchestrator in full-path mode). If not (fast-path mode), generate equivalent metrics inline from your own execution.

```
## Refactor Complete

### Target
- [What was refactored]

### Changes Made
- [N tasks completed]
- [Key improvements: what's better now]

### Build Check
- [passed / failed / skipped]

### Tests
- [all passed / N regressions / no test suite]

### Simplify
- [ran — behavior preserved / ran — broke X, user chose Y / skipped / not offered (no green baseline)]

### Execution Metrics
- Tasks: [completed/total] | Waves: [N] | Retries: [N]
- Implementation notes: [see $TASKS_DIR/implementation-notes.md]

### Review
- [compliance score]
- [behavior preserved: yes/no]
- [critical issues if any]

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
- [e.g., review the changes, run manual tests, address any regressions]
```

## Rules
- Run steps **sequentially** — each depends on the previous
- If Step 1 fails (no tasks created), stop and report the issue
- If Step 2c finds regressions, escalate to the user before proceeding to review
- Always run Step 3 — never skip the review
- Behavior preservation is the primary success criterion — a refactor that breaks tests is a failure
