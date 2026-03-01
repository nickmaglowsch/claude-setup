---
name: debug
description: "Debug pipeline: investigates a bug, diagnoses root cause, writes failing tests, implements fix via TDD, and reviews the result. Orchestrates bug-investigator -> bug-fixer -> code-reviewer."
argument-hint: "[bug description] [Logs: 'command'] [Tests: 'command']"
---

# Debug Pipeline

You are orchestrating the full debug pipeline. Follow these steps strictly in order.

## Input

The user's bug report:

$ARGUMENTS

## Step 0: Clean up — Remove stale debug artifacts

Before starting, remove any leftover files from a previous debug run:
- Use Bash to run `rm -rf tasks/` to clear the entire tasks directory
- This prevents stale diagnosis and questions files from interfering

## Step 1: Investigate — Two-phase investigation with user Q&A

### Step 1a: Discovery — Explore codebase & surface questions

Launch the `bug-investigator` agent using the Task tool with:
- `subagent_type: "bug-investigator"`
- Provide the full bug report content above as the prompt
- Prepend `MODE: DISCOVERY` to the prompt
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

### Next Steps
- [What the user should do -- e.g., manual verification, deploy, monitor]
```

## Rules
- Run the steps **sequentially** — each depends on the previous
- If Step 1 fails (no diagnosis created), stop and report the issue
- If Step 2 fails (fix could not be implemented), still run Step 3 to review what was attempted
- Always run Step 3 — never skip the review
- If the bug-fixer reports it could not write tests, note this in the final report
