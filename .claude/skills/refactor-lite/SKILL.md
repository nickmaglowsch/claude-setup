---
name: refactor-lite
description: "Lightweight refactor: audit → plan → approve → implement in a single Opus context, no sub-agent fan-out. Behavior preservation is the goal — verifies tests still pass, optionally commits, and offers a separate /code-review pass at the end. Use by default; reach for /refactor only when the cleanup needs parallel fan-out or exceeds one context."
argument-hint: "<file, directory, or description of what to improve>"
---

# Refactor (Lite)

Single-context refactor: **audit → plan → approve → implement**, all in this Opus session with **no sub-agent fan-out, no intermediate task files**. Behavior preservation is the primary success criterion. Verifies tests still pass, optionally commits. Review is a separate pass — offered at the end via `/code-review`.

Use this by default. Reach for the heavier `/refactor` only when the cleanup spans many independent files that can be parallelized, or genuinely exceeds one context.

## Input

`$ARGUMENTS` — a file, directory, or description of what to improve.

## Step 1: Audit

- Read the target(s). Explore surrounding code and call sites **read-only**.
- Identify concrete issues with `file:line` specifics: duplication, complexity, dead code, poor naming, missing abstractions.
- Check the target's test coverage. If coverage is thin, flag it — a safety net (Step 3) may be warranted.

## Step 2: Plan

Present a concise plan:
- What's wrong now — the smells worth fixing.
- The incremental changes, in safe order (smallest behavior-preserving steps first).
- Whether to write a test safety net first (recommend it when coverage is thin and the code is non-trivial).
- What will prove behavior is preserved — which tests.

Ask via `AskUserQuestion`: "Proceed?" → **Proceed** / **Revise** (loop) / **Cancel**. Never edit before approval.

## Step 3: Safety net (optional)

If the plan calls for it, write characterization tests for the **current** behavior first and confirm they pass against the unmodified code. This is your regression guard.

## Step 4: Implement

Apply the refactor incrementally in this session. Preserve public APIs unless a breaking change was explicitly approved. **No feature changes — refactor only.** Keep context warm; no task files, no sub-agents.

## Step 5: Verify

- Run the build/lint command. Skip if none.
- Run the full test suite. All previously-passing tests **must** still pass — that is the success criterion.
- If anything regresses: report it and ask whether to fix, proceed, or revert (`git restore` / `git checkout --`).

## Step 6: Commit (optional)

Ask: "Commit these changes?"
- **No** → Step 7.
- **Yes**: if on `main`/`master`, branch to `refactor/<3-5-word-slug>` first; `git add -A && git commit -m "refactor: <summary>"`; then optionally push + open a PR (`git push -u origin <branch>` + `gh pr create`, or print the manual command).

## Step 7: Review handoff

End with `AskUserQuestion`: "Run an independent `/code-review` pass?"
- **"Yes"** → invoke the `code-review` skill, scoped to the diff.
- **"No"** → print "Done. Run `/code-review` when you want an independent pass." and stop.

## Rules
- Behavior preservation is the primary success criterion — a refactor that breaks tests is a failure.
- One context, no fan-out. If you want to spawn implementers, the job is big enough for `/refactor`.
- Never skip Step 2 approval before editing.
