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

## Step 0: Resolve QA_OUTPUT_DIR + clean up

### Step 0a: Resolve QA_OUTPUT_DIR

Run the following in Bash to determine the branch-scoped QA output directory:

```bash
RAW_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
if [ -z "$RAW_BRANCH" ] || [ "$RAW_BRANCH" = "HEAD" ]; then
  SHORT_SHA=$(git rev-parse --short HEAD 2>/dev/null || echo "")
  RAW_BRANCH=${SHORT_SHA:+detached-$SHORT_SHA}
fi
if [ -z "$RAW_BRANCH" ]; then
  echo "Warning: not a git repo — using qa-output/ as QA output directory" >&2
  QA_OUTPUT_DIR="qa-output"
else
  SANITIZED=$(echo "$RAW_BRANCH" | tr '/' '-' | tr -cs 'A-Za-z0-9._-' '-' | sed 's/^-*//; s/-*$//')
  [ -z "$SANITIZED" ] && SANITIZED="unknown-branch"
  QA_OUTPUT_DIR="qa-output/$SANITIZED"
fi
```

Store `QA_OUTPUT_DIR` as a session variable — use it everywhere below.

### Step 0b: Clean up stale QA artifacts

Use Bash to run `rm -rf "$QA_OUTPUT_DIR"` to clear only this branch's QA artifacts from a previous run.

## Step 0.5: App Recon — Discover how to interact with the app

**Parse flags:** If `$ARGUMENTS` starts with `--fresh`, set `FRESH=true` and strip `--fresh` to get the clean scope. Otherwise `FRESH=false`. Store the cleaned scope as `QA_SCOPE`; use `QA_SCOPE` everywhere below instead of raw `$ARGUMENTS`.

Check whether to run app-scout:
- Run via Bash: `find .claude/app-context.md -mmin -60 2>/dev/null`
- **If the file path is returned (exists and < 1 hour old) AND `FRESH=false`:** Use it directly — skip launching app-scout. Proceed to Step 1.
- **Otherwise (file missing, stale, or `--fresh` was passed):** Launch the `app-scout` agent using the Task tool with:
  - `subagent_type: "app-scout"`
  - Prompt: `Perform project recon. Write your findings to .claude/app-context.md.`

Wait for it to complete. If the agent fails or the file is not created, log a warning and proceed without it — this is a best-effort step.

## Step 1: QA — Test the app and generate outputs

Read `.claude/app-context.md` (from Step 0.5). Build the qa-agent prompt as follows (if `.claude/app-context.md` does not exist, omit the App Context section but always include `QA_OUTPUT_DIR`):

```
Test scope: $QA_SCOPE (if empty: test all major flows)

QA_OUTPUT_DIR=$QA_OUTPUT_DIR

Write all outputs (report, screenshots, etc.) under this branch-scoped directory.

## App Context (from pre-recon)

The following was pre-discovered about this project. Use the start command and
URL from this context. Re-check running status yourself.

<full content of .claude/app-context.md>
```

Launch the `qa-agent` using the Task tool with:
- `subagent_type: "qa-agent"`
- Provide the constructed prompt above (with `$QA_OUTPUT_DIR` expanded)

Wait for it to complete.

## Step 2: Report

Read `$QA_OUTPUT_DIR/qa-report.md` and summarize to the user:

```
## QA Complete

**Scope:** <what was tested>

**Results:** N passed · N failed · N warnings

**Critical issues:**
- [list from report, or "None found"]

**Outputs:**
- Full report: $QA_OUTPUT_DIR/qa-report.md
- E2E tests: <list files written>
- Run tests: playwright test
```

If `$QA_OUTPUT_DIR/qa-report.md` does not exist, report that the QA agent failed to complete and show any error output.

## Rules

- Run steps **sequentially** — each depends on the previous
- If Step 0.5 fails (no app-context.md created), log a warning and continue to Step 1 anyway — qa-agent will discover the app independently; this is non-fatal
- If the app is not running, the qa-agent will report it — do not attempt to start the app here
- Always present the summary in Step 2, even if QA found no failures
