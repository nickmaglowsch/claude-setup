---
name: debug-workflow
description: "Debug pipeline: investigates a bug, diagnoses root cause, writes failing tests, implements fix via TDD, and reviews the result. Orchestrates bug-investigator -> bug-fixer -> code-reviewer."
argument-hint: "[--fresh] [bug description] [Logs: 'command'] [Tests: 'command']"
---

# Debug Pipeline

You are orchestrating the full debug pipeline. Follow these steps strictly in order.

## Input

The user's bug report:

$ARGUMENTS

## Step 0.1: Parse flags and auto-commit opt-in

**Parse flags:** If `$ARGUMENTS` starts with `--fresh`, set `FRESH=true` and strip `--fresh` to get the clean bug report. Store the cleaned bug report as `BUG_DESCRIPTION`. Otherwise `FRESH=false` and `BUG_DESCRIPTION=$ARGUMENTS`.

Use `AskUserQuestion` to ask: "Enable auto-commit and PR for this run?"
- Option A: "Yes — create a branch, commit the fix when it's complete, and open a PR"
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

   Note: there is no commit granularity question for debug-workflow — always a single commit.

2. Derive branch name from `BUG_DESCRIPTION` (the clean bug description, after stripping `--fresh`):
   - Generate a kebab-case 3-5 word slug (e.g., `login-500-auth-upgrade`)
   - Branch name: `fix/<slug>`
   - Store as `AUTO_COMMIT_BRANCH`

**If `AUTO_COMMIT=false`:** set `BRANCH_ACTION=none`. Skip all follow-up questions.

## Step 0: Clean up — Remove stale debug artifacts

Before starting, remove any leftover files from a previous debug run:
- Use Bash to run `rm -rf tasks/` to clear the entire tasks directory
- This prevents stale diagnosis and questions files from interfering

## Step 0.5: App Recon — Discover how to interact with the app

Check whether to run app-scout:
- Run via Bash: `find .claude/app-context.md -mmin -60 2>/dev/null`
- **If the file path is returned (exists and < 1 hour old) AND `FRESH=false`:** Use it directly — skip launching app-scout. Proceed to Step 1.
- **Otherwise (file missing, stale, or `--fresh` was passed):** Launch the `app-scout` agent using the Task tool with:
  - `subagent_type: "app-scout"`
  - Prompt: `Perform project recon. Write your findings to .claude/app-context.md.`

Wait for it to complete. If the agent fails or the file is not created, log a warning and proceed without it — this is a best-effort step.

## Step 1: Investigate — Two-phase investigation with user Q&A

### Step 1a: Discovery — Explore codebase & surface questions

Read `.claude/app-context.md` (from Step 0.5). If it exists, build the bug-investigator prompt as follows — otherwise use just the bug report:

```
MODE: DISCOVERY

<full bug report from BUG_DESCRIPTION>

## App Context (from pre-recon)

The following was pre-discovered about this project. Use these commands directly —
do not re-discover what is already documented here. Re-check running status yourself.

<full content of .claude/app-context.md>
```

Launch the `bug-investigator` agent using the Task tool with:
- `subagent_type: "bug-investigator"`
- Provide the constructed prompt above
- Tell it to output questions to `tasks/debug-questions.md`

Wait for it to complete. **Save the returned agent ID** — you will resume this agent in Step 1c.

### Step 1b: User Q&A — Present questions and collect answers

1. Read `tasks/debug-questions.md`
2. Present each question to the user using `AskUserQuestion` — use the questions, context, and options from the file to construct clear choices
3. Collect all answers

### Step 1c: Diagnose — Resume investigator with answers

Resume the **same** bug-investigator agent (using the agent ID from Step 1a) with:
- `resume: "<agent-id-from-step-1a>"`
- Provide all user answers in the prompt, formatted clearly
- Prepend `MODE: DIAGNOSE` to the prompt
- Tell it to write the diagnosis to `tasks/bug-diagnosis.md`

Wait for it to complete. Confirm that `tasks/bug-diagnosis.md` was created.

### Step 1d: Diagnosis review — Present diagnosis and get approval

This step always runs. Do not skip it.

1. Read `tasks/bug-diagnosis.md`. Extract:
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
   Then add: "You can also open `tasks/bug-diagnosis.md` directly to read the full diagnosis."

3. Use `AskUserQuestion` with a single question: "How would you like to proceed?"
   - **"Looks good — apply the fix"** — continue to Step 2
   - **"Re-diagnose with feedback"** — user provides feedback via the "Other" field

4. **If user approves**: proceed to Step 2.

5. **If user requests re-diagnosis**: resume the **same** bug-investigator agent (from Step 1a) with:
   - `resume: "<agent-id-from-step-1a>"`
   - Prompt: `MODE: DIAGNOSE\n\nUser feedback on the diagnosis:\n<feedback>\n\nPlease revise the diagnosis incorporating this feedback.`
   - Wait for it to complete, then **loop back to the top of Step 1d** to re-present the updated diagnosis.

## Step 2: Fix — Run bug-fixer with adaptive TDD

Launch the `bug-fixer` agent using the Task tool with:
- `subagent_type: "bug-fixer"`
- Tell it to read `tasks/bug-diagnosis.md` for the diagnosis
- Pass along any test commands and log commands from the original `$ARGUMENTS` so the fixer can use them
- Tell it to follow adaptive TDD: write a failing test first, then fix, then verify

Wait for it to complete. Note any TDD skips or issues reported.

## Step 2b: Build check — Verify the project compiles

Before reviewing, run a quick build/lint check to catch obvious breakage:
- Look for a `package.json`, `Makefile`, `Cargo.toml`, or similar build config in the project root
- Run the appropriate build command (e.g., `npm run build`, `pnpm build`, `make`, `cargo check`)
- If the build fails, report the errors to the user and ask whether to proceed with the review or fix first
- If no build system is detected, skip this step

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

### 2.5b: Create branch (if BRANCH_ACTION=new)

```bash
git checkout -b <AUTO_COMMIT_BRANCH>
```

If the branch already exists (exit code non-zero), append `-2` to the name and retry once.

### 2.5c: Stage and commit

Read `tasks/bug-diagnosis.md` to extract:
- The `## Bug Summary` paragraph (for the commit body)
- The root cause line (one sentence, for context)

Generate a Conventional Commit message:
- Format: `fix(<optional-scope>): <short description>` (max 72 chars for subject line)
- Short description derived from `BUG_DESCRIPTION`
- Optional body: 1-2 bullet points from `## Bug Summary` or `## Root Cause` in `tasks/bug-diagnosis.md`

Run:
```bash
git add -A
git commit -m "fix: <description>" -m "- <root cause summary>
- <fix approach>"
```

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
- 1-2 sentence summary of the bug and fix
- "## Root Cause" section (from `tasks/bug-diagnosis.md`)
- "## Changes" section listing affected files
- "## Test Plan" section (from the test strategy in `tasks/bug-diagnosis.md`)

Run:
```bash
gh pr create \
  --title "fix: <description>" \
  --body "<pr-body>" \
  --base main
```

If successful, display the PR URL.

**If `GH_UNAVAILABLE`:**

Display a ready-to-copy command block:
```
Run this to open the PR:

  gh pr create \
    --title "fix: <description>" \
    --base main \
    --body '<pr-body>'
```

### 2.5f: Report status

```
## Auto-commit complete
- Branch: <branch-name>
- Committed: 1 commit
- Push: succeeded / failed (see above)
- PR: opened at <url> / ready-to-copy command displayed
```

## Step 3: Review — Run code-reviewer with debug-specific criteria

Launch the `code-reviewer` agent using the Task tool with:
- `subagent_type: "code-reviewer"`
- Tell it to review all changes against `tasks/bug-diagnosis.md`
- Tell it to write the review report to `tasks/debug-review-report.md`
- **Include these additional debug-specific review criteria in the prompt:**
  - Was the root cause identified in the diagnosis actually addressed by the fix?
  - Are there any regressions introduced by the fix?
  - Was a test written for the bug? If not, is the reason documented and valid?
  - Are the changes minimal and focused on the bug fix (no unrelated changes)?

Wait for it to complete.

## Step 3b: Auto-fix — Address critical review issues (one pass)

Read `tasks/debug-review-report.md`. Check if the `### Critical` section contains any items.

**If critical issues are found:**
1. Collect all items listed under `### Critical` (file paths, line numbers, descriptions)
2. Launch a `task-implementer` sub-agent with a prompt that includes:
   - The list of critical issues verbatim from the report
   - Instruction to fix only these specific issues, touching no other code
3. Wait for it to complete.
4. Re-run the code-reviewer (same criteria as Step 3) **once more**. Write the updated report to `tasks/debug-review-report.md` (overwrite).

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

### Verification
- [Test results]
- [Build results]
- [Regression status]

### Review
- [Compliance score from review]
- [Critical issues if any]

### Auto-Commit
- [skipped — not enabled]
  OR
- Branch: <branch-name>
- PR: <url or "manual command displayed">

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
