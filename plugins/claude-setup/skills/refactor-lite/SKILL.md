---
name: refactor-lite
description: "Lightweight refactor: audit → plan → approve → implement in a single Opus context, no sub-agent fan-out. Behavior preservation is the goal — verifies tests still pass, optionally commits, and offers a separate /code-review pass at the end. Use by default; reach for /claude-setup:refactor only when the cleanup needs parallel fan-out or exceeds one context."
argument-hint: "[--cross-review] <file, directory, or description of what to improve>"
---

# Refactor (Lite)

Single-context refactor: **audit → plan → approve → implement**, all in this Opus session with **no sub-agent fan-out, no intermediate task files**. Behavior preservation is the primary success criterion. Verifies tests still pass, optionally commits. Review is a separate pass — offered at the end via `/code-review`.

Use this by default. Reach for the heavier `/claude-setup:refactor` only when the cleanup spans many independent files that can be parallelized, or genuinely exceeds one context.

## Input

`$ARGUMENTS` — a file, directory, or description of what to improve.

**Parse flags:** if `$ARGUMENTS` contains `--cross-review`, set `CROSS_REVIEW=true` and strip it (else `CROSS_REVIEW=false`) — adds an opt-in GPT/Codex second opinion on the diff at the review handoff (Step 7). The remainder is the target.

## Step 1: Audit

- Read the target(s). Explore surrounding code and call sites **read-only**.
- Identify concrete issues with `file:line` specifics: duplication, complexity, dead code, poor naming, missing abstractions.
- Check the target's test coverage. If coverage is thin, flag it — a safety net (Step 3) may be warranted.

## Step 2: Plan

Compose a concise plan:
- What's wrong now — the smells worth fixing.
- The incremental changes, in safe order (smallest behavior-preserving steps first).
- Whether to write a test safety net first (recommend it when coverage is thin and the code is non-trivial).
- What will prove behavior is preserved — which tests.

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
   > You are an adversarial refactoring reviewer with different training than the planner. Do NOT rewrite the plan or produce code. Challenge it specifically on: whether each step preserves observable behavior, the soundness of the decomposition and step ordering, and regression risk per step. Also flag missing safety nets and simpler/safer sequencing. Rank every finding as BLOCKER, MAJOR, or MINOR. If the plan is sound, say so explicitly. Be concise.
4. Run `bash "$CODEX_REVIEW" "$CODEX_DIR/codex-plan-review.md" "$CODEX_DIR/codex-plan-prompt.md"`. Read the result:
   - `SKIPPED:` → note it; present the plan as-is.
   - **BLOCKER/MAJOR** present → revise the plan to address the valid findings *before* presenting it; tell the user what changed (and any findings you deliberately reject, with why).
   - **MINOR** only / none → present the plan, noting any MINOR items as advisory.

   This is a single inline pass — converge once, then present. The user may always override and proceed with the plan as-is.

Then present the (possibly revised) plan and ask via `AskUserQuestion`: "Proceed?" → **Proceed** / **Revise** (loop) / **Cancel**. Never edit before approval.

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

**If `CROSS_REVIEW=true`, first run a cross-model second opinion on the diff** (read-only, fail-soft — GPT via the Codex CLI; never blocks):
1. Resolve the helper: `CODEX_REVIEW="$HOME/.claude/scripts/codex-review.sh"; [ -f "$CODEX_REVIEW" ] || CODEX_REVIEW="scripts/codex-review.sh"`. If neither exists, log "Cross-review skipped — codex-review.sh not installed" and continue to the handoff.
2. Resolve a branch-scoped artifact dir:
   ```bash
   RAW_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
   SANITIZED=$(echo "${RAW_BRANCH:-nobranch}" | tr '/' '-' | tr -cs 'A-Za-z0-9._-' '-' | sed 's/^-*//; s/-*$//')
   CODEX_DIR="tasks/${SANITIZED:-nobranch}"; mkdir -p "$CODEX_DIR"
   ```
3. Capture the diff: `git diff` plus, if you committed in Step 6, the branch diff against the base branch. If the combined diff is empty, log "Cross-review skipped — empty diff" and continue.
4. Write `$CODEX_DIR/codex-diff-prompt.md` = the diff text followed by this instruction verbatim:
   > You are a second reviewer of a refactor, with different training than the primary reviewer. Review ONLY the diff below. A refactor must preserve observable behavior — focus on any change in observable behavior, public API/contract changes, lost edge cases, and regression risk. Do NOT suggest cosmetic or stylistic changes. Rank each finding BLOCKER, MAJOR, or MINOR with a file:line reference. If behavior is preserved, say so explicitly. Be concise.
5. Run `bash "$CODEX_REVIEW" "$CODEX_DIR/codex-diff-review.md" "$CODEX_DIR/codex-diff-prompt.md"`. Read the result; unless it starts with `SKIPPED:`, surface the GPT findings to the user (BLOCKER/MAJOR prominently). Advisory only — it does not block.

Then end with `AskUserQuestion`: "Run an independent `/code-review` pass?"
- **"Yes"** → invoke the `code-review` skill, scoped to the diff.
- **"No"** → print "Done. Run `/code-review` when you want an independent pass." and stop.

## Rules
- Behavior preservation is the primary success criterion — a refactor that breaks tests is a failure.
- One context, no fan-out. If you want to spawn implementers, the job is big enough for `/claude-setup:refactor`.
- Never skip Step 2 approval before editing.
