---
name: build-lite
description: "Lightweight build: explore → plan → approve → implement in a single Opus context, no sub-agent fan-out. Verifies build + tests, optionally commits, and offers a separate /code-review pass at the end. Use by default for everyday features; reach for /build only when the work needs parallel fan-out or exceeds one context."
argument-hint: "<feature description or path to a PRD/spec file>"
---

# Build (Lite)

Single-context build: **explore → plan → approve → implement**, all in this Opus session with **no sub-agent fan-out, no intermediate task files**. Verifies build + tests, optionally commits. Review is a separate pass — offered at the end via `/code-review`.

Use this by default. Reach for the heavier `/build` only when the work spans many independent files that can be implemented in parallel, or genuinely exceeds one context (large migrations, broad sweeps).

## Input

`$ARGUMENTS` — a feature description, or a path to a PRD/spec file.

## Step 1: Understand

- Read `$ARGUMENTS`. If it points to a file, read the file.
- Explore the relevant code **read-only** (Glob/Grep/Read) to ground the plan in the real files and conventions.
- If the request is underspecified (no clear user-facing behavior, scope, or success criteria), ask 1–3 sharp clarifying questions via `AskUserQuestion` before planning. Don't over-ask — fill obvious gaps with sensible defaults and state them in the plan.

## Step 2: Plan

Present a concise plan as text:
- One-line restatement of the goal.
- Numbered implementation steps.
- Files to create/modify, one-line reason each.
- Test approach — what will prove it works.
- Any assumptions or open questions.

Then ask via `AskUserQuestion`: "Proceed with this plan?"
- **"Proceed"** → Step 3.
- **"Revise"** → take feedback, re-present the plan, loop.
- **"Cancel"** → stop cleanly.

Never edit code before this approval.

## Step 3: Implement

Implement the plan directly in this session, in dependency order. Match existing conventions (naming, structure, comment density). Keep context warm — no cold sub-agent reads, no task files. If something forces a material deviation from the approved plan, note it to the user and keep going; don't silently expand scope.

## Step 4: Verify

- Detect and run the build/lint command (`package.json`, `Makefile`, `Cargo.toml`, etc.). Skip if none.
- Detect and run the test suite. If you added behavior, ensure a test covers it.
- If build or tests fail: report the actual output and ask whether to fix now, proceed, or stop. Never claim done on a red baseline.

## Step 5: Commit (optional)

Ask: "Commit these changes?"
- **No** → Step 6.
- **Yes**:
  - If on `main`/`master`, create a feature branch `feat/<3-5-word-slug>` first.
  - `git add -A && git commit -m "feat: <summary>"`.
  - Ask whether to push + open a PR. If yes and `gh` is available: `git push -u origin <branch>` then `gh pr create`. Otherwise print the ready-to-run command.

## Step 6: Review handoff

End with `AskUserQuestion`: "Run an independent `/code-review` pass on these changes?"
- **"Yes"** → invoke the `code-review` skill, scoped to the diff.
- **"No"** → print "Done. Run `/code-review` when you want an independent pass." and stop.

## Rules
- One context, no fan-out — that's the whole point. If you find yourself wanting to spawn implementers, the task is big enough for `/build`.
- Never skip Step 2 approval before editing.
- Report build/test failures honestly; don't claim done if it's red.
