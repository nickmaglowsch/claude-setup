---
name: build-lite
description: "Lightweight build: explore → plan → approve → implement in a single Opus context, no sub-agent fan-out. Verifies build + tests, optionally commits, and offers a separate /code-review pass at the end. Use by default for everyday features; reach for /build only when the work needs parallel fan-out or exceeds one context."
argument-hint: "[--cross-review] <feature description or path to a PRD/spec file>"
---

# Build (Lite)

Single-context build: **explore → plan → approve → implement**, all in this Opus session with **no sub-agent fan-out, no intermediate task files**. Verifies build + tests, optionally commits. Review is a separate pass — offered at the end via `/code-review`.

Use this by default. Reach for the heavier `/build` only when the work spans many independent files that can be implemented in parallel, or genuinely exceeds one context (large migrations, broad sweeps).

## Input

`$ARGUMENTS` — a feature description, or a path to a PRD/spec file.

**Parse flags:** if `$ARGUMENTS` contains `--cross-review`, set `CROSS_REVIEW=true` and strip it (else `CROSS_REVIEW=false`) — adds an opt-in GPT/Codex second opinion on the diff at the review handoff (Step 6). The remainder is the feature description / path.

## Step 1: Understand

- Read `$ARGUMENTS`. If it points to a file, read the file.
- Explore the relevant code **read-only** (Glob/Grep/Read) to ground the plan in the real files and conventions.
- If the request is underspecified (no clear user-facing behavior, scope, or success criteria), ask 1–3 sharp clarifying questions via `AskUserQuestion` before planning. Don't over-ask — fill obvious gaps with sensible defaults and state them in the plan.

## Step 2: Plan

Compose a concise plan:
- One-line restatement of the goal.
- Numbered implementation steps.
- Files to create/modify, one-line reason each.
- Test approach — what will prove it works.
- Any assumptions or open questions.

### Step 2a: Plan convergence — Codex adversarial cross-check (always-on)

Before presenting the plan for approval, run a **read-only, fail-soft** second opinion on it from a decorrelated model (GPT via the Codex CLI). It never blocks — if Codex is unavailable it logs SKIPPED and you present the plan as-is.

1. Resolve the helper: `CODEX_REVIEW="$HOME/.claude/scripts/codex-review.sh"; [ -f "$CODEX_REVIEW" ] || CODEX_REVIEW="scripts/codex-review.sh"`. If neither exists, log "Plan convergence skipped — codex-review.sh not installed" and present the plan as-is.
2. Resolve a branch-scoped artifact dir:
   ```bash
   RAW_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
   SANITIZED=$(echo "${RAW_BRANCH:-nobranch}" | tr '/' '-' | tr -cs 'A-Za-z0-9._-' '-' | sed 's/^-*//; s/-*$//')
   CODEX_DIR="tasks/${SANITIZED:-nobranch}"; mkdir -p "$CODEX_DIR"
   ```
3. Write `$CODEX_DIR/codex-plan-prompt.md` = the plan text followed by this instruction verbatim:
   > You are an adversarial plan reviewer with different training than the planner. Do NOT rewrite the plan or produce code. Challenge it: the overall approach, hidden or unstated assumptions, step ordering, missing edge cases, and simpler or safer alternatives. Rank every finding as BLOCKER, MAJOR, or MINOR. If the plan is sound, say so explicitly. Be concise.
4. Run `bash "$CODEX_REVIEW" "$CODEX_DIR/codex-plan-review.md" "$CODEX_DIR/codex-plan-prompt.md"`. Read the result:
   - `SKIPPED:` → note it; present the plan as-is.
   - **BLOCKER/MAJOR** present → revise the plan to address the valid findings *before* presenting it; tell the user what changed (and any findings you deliberately reject, with why).
   - **MINOR** only / none → present the plan, noting any MINOR items as advisory.

   This is a single inline pass — converge once, then present. The user may always override and proceed with the plan as-is.

Then present the (possibly revised) plan and ask via `AskUserQuestion`: "Proceed with this plan?"
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

**If `CROSS_REVIEW=true`, first run a cross-model second opinion on the diff** (read-only, fail-soft — GPT via the Codex CLI; never blocks):
1. Resolve the helper: `CODEX_REVIEW="$HOME/.claude/scripts/codex-review.sh"; [ -f "$CODEX_REVIEW" ] || CODEX_REVIEW="scripts/codex-review.sh"`. If neither exists, log "Cross-review skipped — codex-review.sh not installed" and continue to the handoff.
2. Resolve a branch-scoped artifact dir:
   ```bash
   RAW_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
   SANITIZED=$(echo "${RAW_BRANCH:-nobranch}" | tr '/' '-' | tr -cs 'A-Za-z0-9._-' '-' | sed 's/^-*//; s/-*$//')
   CODEX_DIR="tasks/${SANITIZED:-nobranch}"; mkdir -p "$CODEX_DIR"
   ```
3. Capture the diff: `git diff` plus, if you committed in Step 5, the branch diff against the base branch. If the combined diff is empty, log "Cross-review skipped — empty diff" and continue.
4. Write `$CODEX_DIR/codex-diff-prompt.md` = the diff text followed by this instruction verbatim:
   > You are a second code reviewer with different training than the primary reviewer. Review ONLY the diff below. Focus on correctness bugs, security issues, race conditions, and missed edge cases. Do NOT restyle or suggest cosmetic changes. Rank each finding BLOCKER, MAJOR, or MINOR with a file:line reference. If you find nothing substantive, say so. Be concise.
5. Run `bash "$CODEX_REVIEW" "$CODEX_DIR/codex-diff-review.md" "$CODEX_DIR/codex-diff-prompt.md"`. Read the result; unless it starts with `SKIPPED:`, surface the GPT findings to the user (BLOCKER/MAJOR prominently). Advisory only — it does not block.

Then end with `AskUserQuestion`: "Run an independent `/code-review` pass on these changes?"
- **"Yes"** → invoke the `code-review` skill, scoped to the diff.
- **"No"** → print "Done. Run `/code-review` when you want an independent pass." and stop.

## Rules
- One context, no fan-out — that's the whole point. If you find yourself wanting to spawn implementers, the task is big enough for `/build`.
- Never skip Step 2 approval before editing.
- Report build/test failures honestly; don't claim done if it's red.
