---
name: qa
description: "QA pipeline: explores the running app like a real user using a browser, then produces a QA report and Playwright E2E tests for regression. Orchestrates app-scout → qa-agent."
argument-hint: "[--fresh] [scope or feature to test — leave empty to test everything]"
---

# QA Pipeline

You are orchestrating the QA pipeline. Follow these steps strictly in order.

## Input

The test scope (optional — empty means test everything):

$ARGUMENTS

## Step 0: Clean up — Remove stale QA artifacts

Remove leftover files from a previous QA run:
- Use Bash to run `rm -rf tasks/qa-report.md tasks/qa-screenshots/`
- Do NOT remove `tasks/` entirely — other pipelines may use it

## Step 0.5: App Recon — Discover how to interact with the app

**Parse flags:** If `$ARGUMENTS` starts with `--fresh`, set `FRESH=true` and strip `--fresh` to get the clean scope. Otherwise `FRESH=false`.

Check whether to run app-scout:
- Run via Bash: `find .claude/app-context.md -mmin -60 2>/dev/null`
- **If the file path is returned (exists and < 1 hour old) AND `FRESH=false`:** Use it directly — skip launching app-scout. Proceed to Step 1.
- **Otherwise (file missing, stale, or `--fresh` was passed):** Launch the `app-scout` agent using the Task tool with:
  - `subagent_type: "app-scout"`
  - Prompt: `Perform project recon. Write your findings to .claude/app-context.md.`

Wait for it to complete. If the agent fails or the file is not created, log a warning and proceed without it — this is a best-effort step.

## Step 1: QA — Test the app and generate outputs

Read `.claude/app-context.md` (from Step 0.5). If it exists, build the qa-agent prompt as follows — otherwise use just the scope:

```
Test scope: $ARGUMENTS (if empty: test all major flows)

## App Context (from pre-recon)

The following was pre-discovered about this project. Use the start command and
URL from this context. Re-check running status yourself.

<full content of .claude/app-context.md>
```

Launch the `qa-agent` using the Task tool with:
- `subagent_type: "qa-agent"`
- Provide the constructed prompt above

Wait for it to complete.

## Step 2: Report

Read `tasks/qa-report.md` and summarize to the user:

```
## QA Complete

**Scope:** <what was tested>

**Results:** N passed · N failed · N warnings

**Critical issues:**
- [list from report, or "None found"]

**Outputs:**
- Full report: tasks/qa-report.md
- E2E tests: <list files written>
- Run tests: npx playwright test
```

If `tasks/qa-report.md` does not exist, report that the QA agent failed to complete and show any error output.

## Rules

- Run steps **sequentially** — each depends on the previous
- If Step 0.5 fails (no app-context.md created), log a warning and continue
- If the app is not running, the qa-agent will report it — do not attempt to start the app here
- Always present the summary in Step 2, even if QA found no failures
