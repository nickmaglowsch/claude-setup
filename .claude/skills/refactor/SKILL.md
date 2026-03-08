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

## Step 0.1: Auto-commit opt-in

Ask: "Enable auto-commit and PR?" (Yes / No) → `AUTO_COMMIT`.

**If `AUTO_COMMIT=true`:**
1. Run `git rev-parse --abbrev-ref HEAD`. If `main`/`master`: `BRANCH_ACTION=new`. Else ask: "Branch `<name>` exists — create new or commit here?" → `BRANCH_ACTION=new/current`.
2. Ask: "Single squash commit or one commit per task?" → `COMMIT_MODE=squash/per-task`.
3. Generate `refactor/<3-5-word-slug>` from `$ARGUMENTS` → `AUTO_COMMIT_BRANCH`.
4. `git checkout -b <AUTO_COMMIT_BRANCH>`. On failure append `-2`, retry once.

**If `AUTO_COMMIT=false`:** `BRANCH_ACTION=none`, `COMMIT_MODE=none`.

## Step 0: Clean up — Remove stale task files

Before starting, remove any leftover files from a previous run:
- Use Bash to run `rm -rf tasks/` to clear the entire tasks directory

## Step 1: Plan — Two-phase planning with user Q&A

### Step 1a: Discovery — Analyze code & surface questions

Launch the `refactor-planner` agent using the Task tool with:
- `subagent_type: "refactor-planner"`
- Prompt: `MODE: DISCOVERY\n\nTarget: <target from $ARGUMENTS>`
- Tell it to output questions to `tasks/refactor-questions.md`

Wait for it to complete. **Save the returned agent ID** — you will resume this agent in Step 1c.

### Step 1b: User Q&A — Present questions and collect answers

1. Read `tasks/refactor-questions.md`
2. Present the code audit summary and each question to the user using `AskUserQuestion`
3. Collect all answers — pay special attention to:
   - Whether the user wants tests written first (Step 1.5 gate)
   - Scope and backward compatibility constraints

### Step 1c: Generate — Resume planner with answers

Resume the **same** refactor-planner agent (using the agent ID from Step 1a) with:
- `resume: "<agent-id-from-step-1a>"`
- Provide all user answers in the prompt, formatted clearly
- Prepend `MODE: GENERATE` to the prompt
- Tell it to generate the refactoring task files and `tasks/refactor-plan.md` in `tasks/`

Wait for it to complete. Confirm that task files were created in `tasks/`.

### Step 1d: Task review — Present plan and get approval

This step always runs. Do not skip it.

1. Read all `task-*.md` files from `tasks/`. For each, extract:
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
   Then add: "You can also open and edit any file in `tasks/` directly before proceeding."

3. Use `AskUserQuestion` with a single question: "How would you like to proceed?"
   - **"Looks good — start refactoring"** — continue to Step 1.5
   - **"Regenerate with feedback"** — user provides feedback via the "Other" field

4. **If user approves**: proceed to Step 1.5.

5. **If user requests regeneration**: resume the **same** refactor-planner agent (from Step 1a) with:
   - `resume: "<agent-id-from-step-1a>"`
   - Prompt: `MODE: GENERATE\n\nUser feedback on the refactoring plan:\n<feedback>\n\nPlease regenerate the task files incorporating this feedback.`
   - Wait for it to complete, then **loop back to the top of Step 1d**.

## Step 1.5: Safety net — Write missing tests (if requested)

**Skip this step if the user did not ask for tests to be written first.**

If the user answered yes to writing tests before refactoring:

Launch the `test-writer` agent using the Task tool with:
- `subagent_type: "test-writer"`
- Prompt: `Write tests for <target> to create a safety net before refactoring. Focus on covering the behavior that the refactoring tasks will touch.`

Wait for it to complete. Confirm tests pass before proceeding — do not start refactoring if tests are failing.

## Step 2: Implement — Run parallel-task-orchestrator

**If `COMMIT_MODE=per-task`:**

Launch the `parallel-task-orchestrator` agent using the Task tool with:
- `subagent_type: "parallel-task-orchestrator"`
- Tell it to read and execute all tasks from `tasks/`
- Include this additional instruction in the prompt:
  > "Run tasks **sequentially** (one at a time, no parallel waves). After each task-implementer completes, run the following bash commands before starting the next task:
  > ```bash
  > git add -A
  > git commit -m "refactor: <task-objective-from-task-file>"
  > ```
  > Use the task's `## Objective` line as the commit message description."

**If `COMMIT_MODE=squash` or `AUTO_COMMIT=false`:**

Launch the `parallel-task-orchestrator` agent using the Task tool with:
- `subagent_type: "parallel-task-orchestrator"`
- Tell it to read and execute all tasks from `tasks/`

Wait for it to complete. Note any issues reported.

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

## Step 2.5: Auto-commit and PR

**Skip if `AUTO_COMMIT=false`.**

**2.5a Safety:** Run `git rev-parse --abbrev-ref HEAD`. If `main`/`master`: abort ("Auto-commit aborted: on main/master. Commit manually.") → proceed to Step 3.

**2.5b Commit:**
- `COMMIT_MODE=squash`: Read `tasks/refactor-plan.md` (or derive from task objectives). `git add -A && git commit -m "refactor: <$ARGUMENTS summary>" -m "- <improvement 1>..."` (72-char subject, ≤3 body bullets).
- `COMMIT_MODE=per-task`: already committed in Step 2. Skip to push.

**2.5d Push:** `git push -u origin <branch-name>`. On failure, show manual command and continue.

**2.5e PR:** Run `gh auth status 2>/dev/null && echo GH_OK || echo GH_UNAVAILABLE`.
- `GH_OK`: Create PR body (1-2 sentence summary + "## Changes" task bullets + "## Behavior Preservation" noting test results). Run `gh pr create --title "refactor: <desc>" --body "<body>" --base main`. Display URL.
- `GH_UNAVAILABLE`: Display ready-to-copy `gh pr create` command.

**2.5f Report:** `Branch: <name> | Commits: <N> | Push: ok/failed | PR: <url or manual>`

## Step 3: Review — Run code-reviewer

Launch the `code-reviewer` agent using the Task tool with:
- `subagent_type: "code-reviewer"`
- Tell it to review all changes against `tasks/refactor-plan.md`
- Tell it to write the review report to `tasks/refactor-review-report.md`
- Include these refactor-specific review criteria in the prompt:
  - Is behavior preserved? Are there any logic changes that shouldn't be there?
  - Do all existing tests still pass?
  - Is the code measurably cleaner, simpler, or more maintainable than before?
  - Are the changes minimal and focused — no unrelated modifications?
  - If the scope included public APIs, are signatures preserved (or are breaking changes intentional and documented)?

Wait for it to complete.

## Step 4: Report

Summarize the full refactoring run to the user:

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

### Review
- [compliance score]
- [behavior preserved: yes/no]
- [critical issues if any]

### Auto-Commit
- [skipped — not enabled]
  OR
- Branch: <branch-name>
- PR: <url or "manual command displayed">

### Next Steps
- [e.g., review the changes, run manual tests, address any regressions]
```

## Rules
- Run steps **sequentially** — each depends on the previous
- If Step 1 fails (no tasks created), stop and report the issue
- If Step 2c finds regressions, escalate to the user before proceeding to review
- Always run Step 3 — never skip the review
- Behavior preservation is the primary success criterion — a refactor that breaks tests is a failure
