---
name: debug-workflow
description: "Debug pipeline: investigates a bug, diagnoses root cause, writes failing tests, implements fix via TDD, and reviews the result. Orchestrates bug-investigator -> bug-fixer -> code-reviewer."
argument-hint: "[--fresh] <bug description in plain language>"
---

# Debug Pipeline

You are orchestrating the full debug pipeline. Follow these steps strictly in order.

## Input

The user's bug report:

$ARGUMENTS

## Step 0.1: Parse flags and auto-commit opt-in

If `$ARGUMENTS` starts with `--fresh`: `FRESH=true`, strip it → `BUG_DESCRIPTION`. Else `FRESH=false`, `BUG_DESCRIPTION=$ARGUMENTS`.

Ask: "Enable auto-commit and PR?" (Yes / No) → `AUTO_COMMIT`.

**If `AUTO_COMMIT=true`:**
1. Run `git rev-parse --abbrev-ref HEAD` to get `CURRENT_BRANCH`. If `CURRENT_BRANCH` is `main` or `master`: `BRANCH_ACTION=new`. Else ask: "Branch `<name>` exists — create new or commit here?" → `BRANCH_ACTION=new/current`. (No commit granularity question — debug always uses a single commit.)
2. Generate `fix/<3-5-word-slug>` from `BUG_DESCRIPTION` → `AUTO_COMMIT_BRANCH`.
3. **If `BRANCH_ACTION=new`:**
   - Run `git fetch origin` to get latest remote state.
   - Detect default branch: run `git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||'`. If empty or error, default to `main`. Store as `DEFAULT_BRANCH`.
   - Ask: "Which branch should `<AUTO_COMMIT_BRANCH>` be based on?"
     - Option 1: `<DEFAULT_BRANCH>` (remote default)
     - Option 2: `<CURRENT_BRANCH>` (current branch)
     - Option 3: Other (enter branch name)
   - Store chosen base as `BASE_BRANCH`.
   - **Do not create the branch yet** — Step 0.1b performs the actual `git checkout -b` or `git worktree add -b` based on the worktree choice.

**If `AUTO_COMMIT=false`:** `BRANCH_ACTION=none`.

## Step 0.1b: Worktree opt-in and branch creation

Ask: "Run workflow in a new git worktree? (enables running multiple pipelines in parallel in the same project)" (Yes / No) → `USE_WORKTREE`.

Store `WORKTREE_PATH=""` as the default. It is set to the new worktree's relative path only if one is created.

### If `USE_WORKTREE=false`:

- **If `AUTO_COMMIT=true` AND `BRANCH_ACTION=new`**: run `git checkout -b <AUTO_COMMIT_BRANCH> <BASE_BRANCH>`. On failure append `-2` to `AUTO_COMMIT_BRANCH`, retry once.
- Otherwise: take no action here. Continue to Step 0a.

### If `USE_WORKTREE=true`:

1. **If `AUTO_COMMIT=true` AND `BRANCH_ACTION=current`**: worktrees require a fresh branch (git disallows two worktrees on the same branch). Ask: "Worktree needs a new branch. Switch to a new branch, or skip the worktree and commit on the current branch?"
   - **"Create new branch"** → set `BRANCH_ACTION=new`. Generate `AUTO_COMMIT_BRANCH=fix/<3-5-word-slug>` from `BUG_DESCRIPTION` if not already generated. Run the same base-branch Q&A as Step 0.1 step 3 to pick `BASE_BRANCH`.
   - **"Skip worktree"** → set `USE_WORKTREE=false` and fall through to the `USE_WORKTREE=false` branch above.

2. Resolve the worktree branch and base:
   - **If `AUTO_COMMIT=true`**: `WT_BRANCH=$AUTO_COMMIT_BRANCH`, `WT_BASE=$BASE_BRANCH` (both set in Step 0.1).
   - **If `AUTO_COMMIT=false`**:
     - Ask: "Branch name for the worktree?" Suggest `fix/<3-5-word-slug>` derived from `BUG_DESCRIPTION`. Store as `WT_BRANCH`.
     - Run `git fetch origin` and detect `DEFAULT_BRANCH` (same as Step 0.1 step 3).
     - Get `CURRENT_BRANCH` if not already set.
     - Ask: "Which branch should `<WT_BRANCH>` be based on?" with the same three options (default / current / other). Store as `WT_BASE`.

3. Sanitize `$WT_BRANCH` into a filesystem-safe path segment (same rules as Step 0a's `SANITIZED`): replace `/` with `-`, strip non-`[A-Za-z0-9._-]`, trim leading/trailing dashes. Store as `WT_PATH_SEG`.

4. Create the worktree and branch atomically:
   ```bash
   git worktree add -b "$WT_BRANCH" ".claude-worktrees/$WT_PATH_SEG" "$WT_BASE"
   ```
   On failure (branch or path already exists), append `-2` to both `$WT_BRANCH` and `$WT_PATH_SEG` and retry once. If it still fails, abort with a clear error to the user.

5. `cd ".claude-worktrees/$WT_PATH_SEG"`. All subsequent steps run inside the worktree.

6. Set `WORKTREE_PATH=".claude-worktrees/$WT_PATH_SEG"` for the final report.

## Step 0a: Resolve TASKS_DIR

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

## Step 0b: Clean up — Remove stale debug artifacts

Before starting, remove any leftover files from a previous debug run:
- Use Bash to run `rm -rf "$TASKS_DIR"` to clear this branch's task directory
- This prevents stale diagnosis and questions files from interfering

## Step 0.5: App Recon — Discover how to interact with the app

Check whether to run app-scout:
- Run via Bash: `find .claude/app-context.md -mmin -60 2>/dev/null`
- **If the file path is returned (exists and < 1 hour old) AND `FRESH=false`:** Use it directly — skip launching app-scout. Proceed to Step 1.
- **Otherwise (file missing, stale, or `--fresh` was passed):** Launch the `app-scout` agent using the Task tool with:
  - `subagent_type: "app-scout"`
  - Prompt: `Perform project recon. Write your findings to .claude/app-context.md.`

Wait for it to complete. If the agent fails or the file is not created, log a warning and proceed to Step 0.7 without `.claude/app-context.md`. Downstream steps will use generic fallbacks (no pre-discovered test command, no log surfaces) — this is non-fatal.

## Step 0.7: Bug Classification — Infer debug strategy from description

Analyze `BUG_DESCRIPTION` and the `## Debug Surfaces` section from `.claude/app-context.md` (if available) to produce a `DEBUG_STRATEGY` — a structured plan of what to check and in what order.

### Classification rules

Scan `BUG_DESCRIPTION` for signal keywords and map them to surface categories:

| Signal patterns | Category | Priority surfaces |
|---|---|---|
| blank screen, white page, not rendering, broken layout, CSS, UI, visual, flicker | **frontend** | Browser (Playwright open + screenshot + console errors), then server logs |
| console error, JavaScript error, React error, hydration, client-side | **frontend-js** | Browser (Playwright evaluate for console errors), then source code search |
| 500 error, server error, crash, stack trace, timeout, gateway error | **backend** | Server logs first, then API endpoint probing with curl |
| wrong data, missing data, stale, not saving, duplicate, data integrity, migration | **data** | Database queries, then server logs, then API probing |
| not loading, slow, hanging, spinner forever, performance, latency | **performance** | Server logs (timing), API probing (response time), database (slow queries) |
| login, auth, session, token, 401, 403, permission, forbidden, unauthorized | **auth** | Auth discovery (built into bug-investigator), server logs, API probing |
| webhook, integration, third-party, external API, callback, sync | **integration** | Server logs, API probing, then cache/queue if available |
| queue, job, worker, background, cron, async, retry | **worker** | Worker/queue logs, cache/queue CLI, server logs |
| cache, stale data, invalidation, redis, TTL | **cache** | Cache CLI (redis-cli), server logs |

If multiple categories match, combine their surfaces (higher-priority category's surfaces come first). If no keywords match, default to **general**: server logs → API probing → browser check.

### Build the DEBUG_STRATEGY

Produce a structured block (internal — not shown to the user):

```
DEBUG_STRATEGY:
  category: <matched category or "general">
  surfaces:
    1. <surface>: <specific command or action from Debug Surfaces>
    2. <surface>: <specific command or action>
    3. <surface>: <specific command or action>
  browser_needed: true/false
  database_needed: true/false
  log_commands: <from app-context "Debug Surfaces > Logs > Primary", or "How to Get Logs">
  test_commands: <from app-context "How to Run Tests">
```

**Rules:**
- Only include surfaces that are actually available (detected by app-scout). If Playwright CLI is "Not installed", do not include browser surfaces — fall back to curl for URL checks.
- Pull specific commands from the `## Debug Surfaces` section — do not invent commands.
- Always include `log_commands` and `test_commands` if they were detected (they are useful regardless of category).
- If `## Debug Surfaces` is not present (app-scout failed, old format, or no app-context), fall back to `## How to Get Logs` and `## How to Run Tests` from app-context.md. If neither exists, omit those fields.
- **Backward compatibility:** If `BUG_DESCRIPTION` contains `Logs: '<command>'` or `Tests: '<command>'` patterns (old invocation style), extract and add them to `log_commands` / `test_commands` fields directly.

## Step 1: Investigate — Two-phase investigation with user Q&A

### Step 1a: Discovery — Explore codebase & surface questions

Read `.claude/app-context.md` (from Step 0.5). Build the bug-investigator prompt as follows:

```
MODE: DISCOVERY

<full bug report from BUG_DESCRIPTION>

## Debug Strategy (auto-classified)

<DEBUG_STRATEGY from Step 0.7>

Follow this strategy as your investigation starting point. Check the recommended
surfaces in order. You may deviate if evidence leads elsewhere, but start here.

## App Context (from pre-recon)

The following was pre-discovered about this project. Use these commands directly —
do not re-discover what is already documented here. Re-check running status yourself.

<full content of .claude/app-context.md>
```

If `.claude/app-context.md` does not exist, omit the App Context section but still include the Debug Strategy (using generic fallbacks from Step 0.7).

Launch the `bug-investigator` agent using the Task tool with:
- `subagent_type: "bug-investigator"`
- Provide the constructed prompt above
- Tell it to output questions to `$TASKS_DIR/debug-questions.md`
- Include `TASKS_DIR=$TASKS_DIR` in the launch prompt

Wait for it to complete. **Save the returned agent ID** — you will resume this agent in Step 1c.

### Step 1b: User Q&A — Present questions and collect answers

1. Read `$TASKS_DIR/debug-questions.md`
2. Present each question to the user using `AskUserQuestion` — use the questions, context, and options from the file to construct clear choices
3. Collect all answers

### Step 1c: Diagnose — Resume investigator with answers

Resume the **same** bug-investigator agent (using the agent ID from Step 1a) with:
- `resume: "<agent-id-from-step-1a>"`
- Provide all user answers in the prompt, formatted clearly
- Prepend `MODE: DIAGNOSE` to the prompt
- Tell it to write the diagnosis to `$TASKS_DIR/bug-diagnosis.md`

Wait for it to complete. Confirm that `$TASKS_DIR/bug-diagnosis.md` was created.

### Step 1d: Diagnosis review — Present diagnosis and get approval

This step always runs. Do not skip it.

1. Read `$TASKS_DIR/bug-diagnosis.md`. Extract:
   - Root cause summary
   - Proposed fix approach
   - Affected files

2. Present the diagnosis to the user as a formatted summary:
   ```
   ## Diagnosis Summary

   **Root cause:** [root cause]
   **Proposed fix:** [fix approach]
   **Affected files:** [list]
   ```
   Then add: "You can also open `$TASKS_DIR/bug-diagnosis.md` directly to read the full diagnosis."

3. Use `AskUserQuestion` with a single question: "How would you like to proceed?"
   - **"Looks good — apply the fix"** — continue to Step 2
   - **"Re-diagnose with feedback"** — user provides feedback via the "Other" field

4. **If user approves**: proceed to Step 2.

5. **If user requests re-diagnosis**: resume the **same** bug-investigator agent (from Step 1a) with:
   - `resume: "<agent-id-from-step-1a>"`
   - Prompt: `MODE: DIAGNOSE\n\nUser feedback on the diagnosis:\n<feedback>\n\nPlease revise the diagnosis incorporating this feedback.`
   - Wait for it to complete, then **loop back to the top of Step 1d** to re-present the updated diagnosis.
   - **Iteration cap**: max 3 re-diagnose cycles. If the user requests a 4th, stop looping — surface the stuck state and ask whether to abort the workflow or proceed to Step 2 with the current diagnosis.

## Step 2: Fix — Run bug-fixer with adaptive TDD

Read `.claude/app-context.md` and extract the test infrastructure details to pass to the bug-fixer:
- **Test command**: from `## How to Run Tests`
- **Test framework**: from `## Tech Stack` or `## Debug Surfaces`
- **Test file conventions**: from `## Tech Stack` (e.g., `*.test.ts`, `*.spec.js`, `__tests__/`)
- **Test directory**: infer from detected patterns

Launch the `bug-fixer` agent using the Task tool with:
- `subagent_type: "bug-fixer"`
- Tell it to read `$TASKS_DIR/bug-diagnosis.md` for the diagnosis
- Include `TASKS_DIR=$TASKS_DIR` in the launch prompt
- Pass along the test commands and log commands from `.claude/app-context.md` (from the `## How to Run Tests` and `## Debug Surfaces > Logs` sections) so the fixer can use them
- **Pass the test infrastructure details** so the fixer doesn't have to rediscover them:
  ```
  ## Test Infrastructure (from pre-recon)
  - Test framework: [framework]
  - Test command: [command]
  - Test file conventions: [pattern]
  - Test directory: [path]
  ```
- Tell it to follow adaptive TDD: write a failing test first (with test adequacy check), then fix, then verify
- Tell it to include Implementation Notes in its output

Wait for it to complete. Note any TDD skips or issues reported. Save the bug-fixer's Implementation Notes output for passing to the reviewer.

## Step 2b: Build check — Verify the project compiles

Before reviewing, run a quick build/lint check to catch obvious breakage:
- Look for a `package.json`, `Makefile`, `Cargo.toml`, or similar build config in the project root
- Run the appropriate build command (e.g., `npm run build`, `pnpm build`, `make`, `cargo check`)
- If the build fails, report the errors to the user and ask whether to proceed with the review or fix first
- If no build system is detected, skip this step

## Step 2.5: Auto-commit and PR

**Skip if `AUTO_COMMIT=false`.**

**2.5a Safety:** Run `git rev-parse --abbrev-ref HEAD`. If `main`/`master`: abort ("Auto-commit aborted: on main/master. Commit manually.") → proceed to Step 3.

**2.5c Commit:** Read `$TASKS_DIR/bug-diagnosis.md` for `## Bug Summary` and root cause. Run `git add -A && git commit -m "fix: <BUG_DESCRIPTION summary>" -m "- <root cause>\n- <fix approach>"` (72-char subject, 1-2 body bullets).

**2.5d Push:** `git push -u origin <branch-name>`. On failure, show manual command and continue.

**2.5e PR:** Run `gh auth status 2>/dev/null && echo GH_OK || echo GH_UNAVAILABLE`.
- `GH_OK`: Create PR body (1-2 sentence bug/fix summary + "## Root Cause" from diagnosis + "## Changes" files + "## Test Plan"). Run `gh pr create --title "fix: <desc>" --body "<body>" --base main`. Display URL.
- `GH_UNAVAILABLE`: Display ready-to-copy `gh pr create` command.

**2.5f Report:** `Branch: <name> | Commits: 1 | Push: ok/failed | PR: <url or manual>`

## Step 3: Review — Run code-reviewer with debug-specific criteria

Write the bug-fixer's Implementation Notes to `$TASKS_DIR/implementation-notes.md` so the reviewer can read them.

Launch the `code-reviewer` agent using the Task tool with:
- `subagent_type: "code-reviewer"`
- Tell it to review all changes against `$TASKS_DIR/bug-diagnosis.md`
- Tell it to read `$TASKS_DIR/implementation-notes.md` for the fixer's decision context
- Tell it to write the review report to `$TASKS_DIR/debug-review-report.md`
- Include `TASKS_DIR=$TASKS_DIR` in the launch prompt
- **Include these additional debug-specific review criteria in the prompt:**
  - Was the root cause identified in the diagnosis actually addressed by the fix?
  - Are there any regressions introduced by the fix?
  - Was a test written for the bug? If not, is the reason documented and valid? (Verify: if test framework exists, "effort disproportionate" is not a valid reason)
  - Are the changes minimal and focused on the bug fix (no unrelated changes)?
  - Run the test adequacy deep-check on any new tests

Wait for it to complete.

## Step 3b: Auto-fix — Address critical review issues (one pass)

Read `$TASKS_DIR/debug-review-report.md`. Check if the `### Critical` section contains any items.

**If critical issues are found:**
1. Collect all items listed under `### Critical` (file paths, line numbers, descriptions)
2. Launch a `task-implementer` sub-agent with a prompt that includes:
   - The list of critical issues verbatim from the report
   - Instruction to fix only these specific issues, touching no other code
   - Include `TASKS_DIR=$TASKS_DIR` in the launch prompt
3. Wait for it to complete.
4. Re-run the code-reviewer (same criteria as Step 3) **once more**. Write the updated report to `$TASKS_DIR/debug-review-report.md` (overwrite).

**If no critical issues:** proceed directly to Step 4.

Do not loop — the auto-fix runs at most once. If critical issues persist after the retry, report them to the user in Step 4.

## Step 4: Report

Summarize the full debug pipeline run to the user:

```
## Debug Complete

### Investigation
- [Root cause summary from bug-diagnosis.md]

### Fix
- [What was changed]
- [Tests added or why not]
- [Implementation decisions: key notes from bug-fixer]

### Verification
- [Test results]
- [Build results]
- [Regression status]

### Debug Metrics
- TDD: [used / skipped (reason)]
- Test adequacy: [adequate / flagged issues]
- Files changed: [count and list]

### Review
- [Compliance score from review]
- [Critical issues if any]
- [Decision assessment from implementation notes review]

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
- [What the user should do -- e.g., manual verification, deploy, monitor]
```

## Rules
- Run the steps **sequentially** — each depends on the previous
- If Step 0.5 fails (no app-context.md created), log a warning and continue
- If Step 1 fails (no diagnosis created), stop and report the issue
- If Step 2 fails (fix could not be implemented), still run Step 3 to review what was attempted
- Always run Step 3 — never skip the review
- If the bug-fixer reports it could not write tests, note this in the final report
