---
name: build
description: "Full build pipeline: takes a PRD, breaks it into tasks, implements them in parallel, and reviews the result. Orchestrates prd-task-planner → parallel-task-orchestrator → code-reviewer."
argument-hint: "[--brainstorm] <PRD or path to PRD file>"
---

# Build Pipeline

You are orchestrating the full build pipeline. Follow these steps strictly in order.

## Input

The raw arguments (may include `--brainstorm` flag):

$ARGUMENTS

**Parse flags before proceeding:**
- If `$ARGUMENTS` starts with or contains `--brainstorm`, set `BRAINSTORM=true` and strip `--brainstorm` to get the clean PRD content.
- Otherwise, `BRAINSTORM=false` and the full arguments are the PRD content.

## Step 0.03: Cheap routing check — should this be `/build-lite`?

Before asking auto-commit, worktree, or orchestration questions, spend at most 2-3 minutes on a bounded read-only check:
- Read the PRD text, or the referenced PRD file if `$ARGUMENTS` is a path.
- Use targeted `Glob`/`Grep`/bounded `Read` only when needed to identify likely files and whether independent parallel work exists.
- Do not launch planner/reviewer/implementer agents in this step.

Route to `/build-lite` and stop this workflow if the feature appears to be any of:
- 1-2 likely implementation tasks.
- A single user-facing workflow or localized change.
- Mostly sequential work where later edits depend on earlier ones.
- Work concentrated in one module/package or touching overlapping files.
- A docs/config/UI copy/update task.

Proceed with full `/build` only when the work likely needs 3+ independent implementation tasks that can run in parallel, or when it genuinely exceeds a single warm context (large migrations, broad feature sweeps, multi-package changes with limited file overlap).

If routing to lite, tell the user: "This looks cheaper and equally safe as `/build-lite` because <reason>. Switching to the lite workflow." Then immediately follow `.claude/skills/build-lite/SKILL.md` from Step 1 using the same `$ARGUMENTS`, skipping all remaining full `/build` steps.

## Step 0.05: PRD adequacy check

**Skip if `--brainstorm` was passed** — brainstorm mode is itself a form of pre-planning sharpening.

Treat the PRD as underspecified if any of: shorter than ~3 sentences; expresses a desire without naming user-facing behavior/scope/success criteria; contains hedges ("not sure if...", "maybe..."); the chat session has no prior design context.

If underspecified, check the repo root for `CONTEXT.md` / `CONTEXT-MAP.md` and offer via `AskUserQuestion`:
- **"Run `/grill-with-docs` first"** (only when CONTEXT doc detected)
- **"Run `/grill-me` first"**
- **"Continue anyway"** — proceed; planner discovery picks up the slack
- **"Switch to `--brainstorm`"**

For grill/brainstorm choices, exit cleanly: "Stopping `/build`. Re-run after sharpening." Do not invoke the chosen skill yourself — the user re-invokes manually so the grilling session has a clean context. For "Continue anyway", proceed to Step 0.1.

## Step 0.1: Auto-commit opt-in

Ask: "Enable auto-commit and PR?" → `AUTO_COMMIT`. If false: set `BRANCH_ACTION=none`, `COMMIT_MODE=none`, skip to Step 0.1b.

If true:
1. `CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)`. If `main`/`master`: `BRANCH_ACTION=new`. Else ask: "Branch `<name>` exists — create new or commit here?" → `BRANCH_ACTION=new|current`.
2. Ask commit mode → `COMMIT_MODE=squash|per-wave|per-task-at-end`:
   - **squash** — single commit at the end
   - **per-wave** — one commit per parallel execution wave
   - **per-task-at-end** — parallel run, then one atomic commit per task in order
3. Generate `feat/<3-5-word-slug>` from PRD → `AUTO_COMMIT_BRANCH`.
4. If `BRANCH_ACTION=new`:
   - `git fetch origin`; `DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||')` (fallback `main`).
   - Ask which branch to base on: `DEFAULT_BRANCH` / `CURRENT_BRANCH` / Other → `BASE_BRANCH`.
   - **Do not create the branch yet** — Step 0.1b creates it via `git checkout -b` or `git worktree add -b` depending on the worktree choice.

## Step 0.1b: Worktree opt-in and branch creation

Ask: "Run workflow in a new git worktree?" → `USE_WORKTREE`. Default `WORKTREE_PATH=""` (set only if a worktree is created).

**If `USE_WORKTREE=false`:**
- If `AUTO_COMMIT=true` AND `BRANCH_ACTION=new`: `git checkout -b <AUTO_COMMIT_BRANCH> <BASE_BRANCH>` (on failure append `-2` and retry once).
- Otherwise: no-op. Proceed to Step 0.2.

**If `USE_WORKTREE=true`:**

1. If `AUTO_COMMIT=true` AND `BRANCH_ACTION=current`: worktrees can't share a branch. Ask: "Switch to a new branch, or skip the worktree?"
   - "Create new branch" → set `BRANCH_ACTION=new`, generate `AUTO_COMMIT_BRANCH=feat/<slug>` if not already, repeat the base-branch Q&A from Step 0.1 step 4.
   - "Skip worktree" → set `USE_WORKTREE=false` and use the false branch above.

2. Resolve `WT_BRANCH` and `WT_BASE`:
   - If `AUTO_COMMIT=true`: `WT_BRANCH=$AUTO_COMMIT_BRANCH`, `WT_BASE=$BASE_BRANCH`.
   - Else: ask for branch name (suggest `feat/<slug>`), then run the same `git fetch origin` + base-branch Q&A.

3. Sanitize `$WT_BRANCH` to a filesystem-safe path segment (`/`→`-`, strip non-`[A-Za-z0-9._-]`, trim dashes) → `WT_PATH_SEG`.

4. `git worktree add -b "$WT_BRANCH" ".claude-worktrees/$WT_PATH_SEG" "$WT_BASE"`. On collision append `-2` to both and retry once; if still failing, abort. If the retry succeeded and `AUTO_COMMIT=true`, set `AUTO_COMMIT_BRANCH=$WT_BRANCH` so downstream steps target the renamed branch.

5. `cd ".claude-worktrees/$WT_PATH_SEG"`. Set `WORKTREE_PATH=".claude-worktrees/$WT_PATH_SEG"` for the final report. All subsequent steps run inside the worktree.

## Step 0.2: Orchestration Mode Selection

Check `~/.claude/user-preferences.json` for a saved orchestration mode preference:
- Parse the file safely. If it is missing, unreadable, or invalid JSON, continue to the prompt below.
- If `"orchestrationMode"` is `parallel` or `agent-teams`, log "Using saved orchestration mode: `<value>`", set `ORCHESTRATION_MODE` to that value, and skip the rest of this step.
- If `"orchestrationMode"` exists but has any other value, warn that the saved value is invalid and continue to the prompt below.

Otherwise ask via `AskUserQuestion` ("How should tasks be implemented?"):
- **Default (Recommended)**: `parallel` — sub-agent approach with wave-based parallel execution
- **Agent Teams (Beta)**: `agent-teams` — Claude Code's native Agent Teams feature

Then ask: "Save as default?" If yes, persist to `~/.claude/user-preferences.json`:
```bash
MODE=<ORCHESTRATION_MODE> python3 -c "
import json, os
p = os.path.expanduser('~/.claude/user-preferences.json')
prefs = json.load(open(p)) if os.path.exists(p) else {}
prefs['orchestrationMode'] = os.environ['MODE']
json.dump(prefs, open(p, 'w'), indent=2)
"
```

## Step 0: Resolve TASKS_DIR + clean up

### Step 0a: Resolve TASKS_DIR

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

### Step 0b: Clean up stale task files

Use Bash to run `rm -rf "$TASKS_DIR"` to clear only this branch's task directory.
This prevents stale task files from being picked up by the orchestrator.

## Step 0.5: Design brainstorm (only if BRAINSTORM=true)

Launch `prd-task-planner` with `subagent_type: "prd-task-planner"` and prompt `TASKS_DIR=$TASKS_DIR\nMODE: BRAINSTORM\n\n<clean PRD content>`. **Save the returned agent ID** — this same agent will be resumed in Step 1a.

Read `$TASKS_DIR/design-options.md`. Present each option via `AskUserQuestion` (option name → label, summary/trade-offs → description). Include a "Custom direction" option. Store the chosen option as `CHOSEN_DESIGN`.

## Step 1: Plan — Two-phase planning with user Q&A

### Step 1a: Discovery — Explore codebase & surface questions

If `BRAINSTORM=true`: resume the agent from Step 0.5 with `MODE: DISCOVERY\nChosen design direction: <CHOSEN_DESIGN>\n\n<clean PRD content>`. The agent already has codebase context and will skip re-exploration.

If `BRAINSTORM=false`: launch fresh with `subagent_type: "prd-task-planner"` and `TASKS_DIR=$TASKS_DIR\nMODE: DISCOVERY\n\n<PRD content>`.

Either way, tell it to output questions to `$TASKS_DIR/planning-questions.md`. **Save the returned agent ID** — you will resume this same agent in Step 1c.

### Step 1b: User Q&A

Read `$TASKS_DIR/planning-questions.md`. Present each question to the user via `AskUserQuestion` (use the file's questions, context, and options). Collect all answers.

### Step 1c: Generate — Resume planner with answers

Resume the **same** agent from Step 1a with `MODE: GENERATE` prepended, the formatted user answers, and instruction to generate `$TASKS_DIR/updated-prd.md` and the task files. Wait, then confirm task files were created.

### Step 1d: Task review — Present plan and get approval

Always runs. Read all `task-*.md` files; for each, extract task number, title, `## Objective` first line, and `## Dependencies`. Present as:

```
## Task Plan (N tasks)

1. task-01-name — [Objective]
   Dependencies: None
2. task-02-name — [Objective]
   Dependencies: task-01
...
```

Add: "You can also open and edit any file in `$TASKS_DIR/` directly before proceeding."

Use `AskUserQuestion`: "How would you like to proceed?"
- **"Looks good — start implementation"** → Step 1e
- **"Regenerate with feedback"** → resume the same `prd-task-planner` agent (ID from Step 1a) with `MODE: GENERATE\n\nUser feedback on the task plan:\n<feedback>\n\nPlease regenerate the task files incorporating this feedback.`, wait, then loop back to the top of Step 1d.

## Step 1e: Fast-path detection — Should we skip the orchestrator?

Read all `$TASKS_DIR/task-*.md` files and classify `FAST_PATH=true` if ANY of:
- 2 or fewer tasks (regardless of dependencies)
- All tasks are sequential: linear dependency chain OR all tasks touch overlapping files (no parallelism possible)
- Only 1 task out of 3+ could run in parallel (orchestrator adds overhead for negligible parallelism)

Otherwise `FAST_PATH=false` (3+ tasks with real parallelism opportunities).

The planner already self-checked dependency soundness, file conflicts, PRD coverage, sizing, and TDD consistency before returning — no separate plan-review pass is needed. Unresolved ambiguities (if any) appear in `$TASKS_DIR/updated-prd.md` under `## Open Questions`, which the user saw in Step 1d.

## Step 2: Implement

### Fast path (`FAST_PATH=true`) — Direct implementation

If `ORCHESTRATION_MODE=agent-teams`: inform the user "Fast-path detected — using direct implementation instead of Agent Teams; orchestration overhead is not justified." Skip the env-var setup from Step 0.2.

Implement tasks yourself, sequentially, in the current session. For each task file in order: (1) read the task file fully, (2) read referenced context files, (3) implement, (4) if `## TDD Mode` is present, follow Section B of `.claude/agents/tdd-mode.md` (RED → adequacy check → GREEN → REFACTOR → VERIFY). (5) write `$TASKS_DIR/notes/task-NN.md` with Implementation Notes — same template the `task-implementer` agent uses (Decisions / Deviations / Trade-offs / Risks; one bullet per category, or a single `No non-obvious decisions.` line if all choices were obvious). After all tasks: concatenate `$TASKS_DIR/notes/task-*.md` (sorted) into `$TASKS_DIR/implementation-notes.md` with a `# Implementation Notes` header.

Commit handling: if `COMMIT_MODE=per-wave`, after each task run `git add -A && git diff --staged --quiet || git commit -m "feat: <task-objective>"`. If `COMMIT_MODE=per-task-at-end`, skip — commits happen in Step 2.5b.

Fast path keeps continuous session context across tasks (no cold reads) and avoids the orchestrator overhead.

### Full path (`FAST_PATH=false`) — Run orchestrator

**If `ORCHESTRATION_MODE=parallel`** (default):

Launch the `parallel-task-orchestrator` agent using the Task tool with:
- `subagent_type: "parallel-task-orchestrator"`
- Prompt:
  ```
  TASKS_DIR=$TASKS_DIR
  Read and execute all tasks from `$TASKS_DIR/`
  Batch same-wave tasks that share module/directory context when safe.
  Keep sub-agent returns short; detailed decisions must go in `$TASKS_DIR/notes/`.
  ```
- **If `COMMIT_MODE=per-wave`**: Include `COMMIT_MODE=per-wave` in the launch prompt so the orchestrator commits after each wave. Also include: `Use commit subject prefix 'feat:' instead of 'refactor:' for per-wave commits.`
- **If `COMMIT_MODE=squash`, `per-task-at-end`, or `AUTO_COMMIT=false`**: Launch normally with no additional commit instructions.

Wait for it to complete. Note any issues reported.

**If `ORCHESTRATION_MODE=agent-teams`** (Beta):

> **Before starting**: Verify no Agent Teams team is already active in this session. If team creation fails, inform the user and fall back to the default `parallel-task-orchestrator` approach automatically. See `agent-teams-orchestrator.md` → Known Limitations for details.

First, enable the required env var by finding the user's settings file (check `.claude/settings.local.json`, then `.claude/settings.json`, then `~/.claude/settings.json`) and adding `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` to the `env` object, preserving all existing settings. If no settings file exists, create `.claude/settings.local.json` with the env var.

Do NOT spawn a sub-agent. Instead, execute Agent Teams orchestration directly in this session:
1. Read `.claude/agents/agent-teams-orchestrator.md` (check `~/.claude/agents/` for global installs, `.claude/agents/` for local)
2. Follow those instructions directly in this session to orchestrate tasks using Agent Teams teammates, passing `TASKS_DIR=$TASKS_DIR` so teammates know where to read and write task files
3. Produce the same outputs: `$TASKS_DIR/implementation-notes.md` and `$TASKS_DIR/execution-metrics.md`

Note: Per-wave commits in Agent Teams mode are handled by the agent-teams-orchestrator when `COMMIT_MODE=per-wave` is passed in the session context. Per-task-at-end commits are handled by the skill layer in Step 2.5b (runs after Agent Teams execution completes). Auto-commit/branch handling (if `AUTO_COMMIT=true`) applies identically to both modes.

After Agent Teams execution completes (whether successful or not), **clean up the env var**: read the settings file that was modified above, remove `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` from the `env` object, and write it back. If the `env` object is now empty, remove it entirely. This prevents the beta env var from persisting across future sessions.

## Step 2b: Build check — Verify the project compiles

Before reviewing, run a quick build/lint check to catch obvious breakage:
- Look for a `package.json`, `Makefile`, `Cargo.toml`, or similar build config in the project root
- Run the appropriate build command (e.g., `npm run build`, `pnpm build`, `make`, `cargo check`)
- If the build fails, report the errors to the user and ask whether to proceed with the review or fix first
- If no build system is detected, skip this step

## Step 2c: Test verification — Run the project's test suite

After the build check, run the project's full test suite to catch regressions and verify implementation:
- Look for test configuration: `package.json` (check for "test" script), `pytest.ini`/`pyproject.toml`, `go.mod`, `Cargo.toml`, or other test framework config
- Run the appropriate test command (e.g., `npm test`, `pnpm test`, `pytest`, `go test ./...`, `cargo test`)
- If tests fail: report the failures and ask whether to proceed, fix, or skip
- If no test infrastructure is detected, skip this step

## Step 2d: Simplify — Quality cleanup pass (opt-in, one pass)

A `/simplify` pass applies reuse/simplification/efficiency/altitude cleanups to the changes. It **mutates code**, so it must run against a verified-green baseline and re-verify afterward.

**Guard:** Only offer this step if Step 2c passed (or was skipped with no detected failures). If Step 2c reported failures the user chose to proceed past, **skip this step entirely** — never simplify on a red baseline. Set `SIMPLIFY_RAN=false`.

1. Use `AskUserQuestion`: "Run a `/simplify` quality cleanup pass on the changes before review?"
   - **"Yes — simplify"** — run the cleanup pass
   - **"No — skip"** → set `SIMPLIFY_RAN=false` and proceed to Step 2.5

2. **If "Yes"**: invoke the `simplify` skill via the Skill tool. Tell it to scope to the full branch diff against the base branch, so changes already committed in `per-wave`/`per-task-at-end` modes are covered — not just uncommitted edits. Wait for it to finish.

3. **Re-verify behavior**: re-run the Step 2b build check command and the Step 2c test command.
   - If something that passed before now fails, the cleanup broke behavior: report the failing checks and ask whether to (a) keep simplify's changes and continue, (b) revert the simplify changes (`git checkout -- <files>` / `git restore`) and continue, or (c) stop. Do not silently proceed.
   - If green, set `SIMPLIFY_RAN=true`.

Simplify's edits are left uncommitted and flow into the existing Step 2.5b commit logic: included in the squash commit, swept into the `per-wave` post-run cleanup commit, or caught by the `per-task-at-end` miscellaneous-changes commit.

## Step 2.5: Auto-commit and PR

**Skip if `AUTO_COMMIT=false`.**

**2.5a Safety:** Run `git rev-parse --abbrev-ref HEAD`. If `main`/`master`: abort ("Auto-commit aborted: on main/master. Commit manually.") → proceed to Step 3.

**2.5b Commit:** behavior depends on `COMMIT_MODE`.

- **squash**: read all `$TASKS_DIR/task-*.md` `## Objective` lines, then `git add -A && git commit -m "feat: <PRD summary>"` with body `-m` containing one bullet per task objective (no cap). Subject ≤72 chars.

- **per-wave**: commits already made by the orchestrator (or fast-path). `git add -A`; if anything's still staged, `git commit -m "feat: post-run cleanup"`; otherwise skip.

- **per-task-at-end**: parallel run is complete. For each `task-NN-*.md` in numerical order:
  1. `git restore --staged .` to clear staging
  2. Read the task's `## Target Files` section for its file list
  3. `git add <file1> <file2> ...` (only that task's files), then `git commit -m "feat: <task objective>"`
  After all per-task commits: `git add -A && git diff --staged --quiet || git commit -m "feat: miscellaneous changes"` to catch files not covered by any task's manifest.

**2.5d Push:** `git push -u origin <branch-name>`. On failure, show manual command and continue.

**2.5e PR:** Run `gh auth status 2>/dev/null && echo GH_OK || echo GH_UNAVAILABLE`.
- `GH_OK`: Create PR body (1-2 sentence summary + "## Changes" task objectives + "## Review Notes" placeholder). Run `gh pr create --title "feat: <desc>" --body "<body>" --base main`. Display URL.
- `GH_UNAVAILABLE`: Display ready-to-copy `gh pr create` command.

**2.5f Report:** `Branch: <name> | Commits: <N> | Push: ok/failed | PR: <url or manual>`

## Step 3: Review — Run code-reviewer

Detect TDD usage by grepping any `task-*.md` for `## TDD Mode`. Note whether `$TASKS_DIR/implementation-notes.md` exists.

Before launching the reviewer, gather a compact review packet:
- If `DEFAULT_BRANCH` is not set, resolve it: `DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||')` (fallback `main` if empty or error).
- Capture `git diff --stat "$DEFAULT_BRANCH"...HEAD`, `git diff --name-only "$DEFAULT_BRANCH"...HEAD`, and `git log --oneline "$DEFAULT_BRANCH"..HEAD`.
- Capture build/test commands run in Steps 2b/2c and their pass/fail summaries. Do not paste full logs unless failures need specific excerpts.

Launch `code-reviewer` with:
- `subagent_type: "code-reviewer"`
- Base prompt: `TASKS_DIR=$TASKS_DIR\nReview all changes against $TASKS_DIR/updated-prd.md and write the review report to $TASKS_DIR/review-report.md.\nStart from this compact review packet: <diff stat, changed file list, commit list, build/test summaries>. Review diff-scoped changes first. Read changed files and requirement files as needed; only expand to unchanged files when required to verify behavior, contracts, or conventions.`
- If `implementation-notes.md` exists: tell it to read this file for implementer decision context.
- If TDD was used: tell it to apply TDD-specific review criteria (test adequacy, mocking discipline, validity of any "TDD not feasible" declarations) — the reviewer agent has those checks built in.
- If TDD was not used: tell it to check general test coverage as part of the standard review.
- **If `SIMPLIFY_RAN=true`**: append `A /simplify cleanup pass already ran on these changes — do NOT re-flag reuse, simplification, efficiency, or altitude items as Minor issues. Focus on correctness, PRD compliance, security, and test adequacy.` so the report stays signal-dense.

Wait for it to complete.

## Step 3b: Auto-fix — Address critical review issues (opt-in, one pass)

Read `$TASKS_DIR/review-report.md`. Check if the `### Critical` section contains any items.

**If no critical issues:** proceed directly to Step 4.

**If critical issues are found:**

1. Present the list of critical issues to the user — one bullet per issue, with `file:line` references.

2. Use `AskUserQuestion`: "How should we handle the N critical issues?"
   - **"Auto-fix"** — spawn task-implementers to fix all critical issues in parallel, then re-review once
   - **"Skip — I'll fix them"** — proceed to Step 4 with issues unfixed; the user takes them on manually
   - **"Stop here"** — halt the pipeline at this point; user reviews state before deciding next move

3. **If "Auto-fix"**:
   - For each distinct file affected (index them as `01`, `02`, ...), launch a `task-implementer` sub-agent in parallel with:
     - `TASKS_DIR=$TASKS_DIR` so it can find shared-context
     - The specific critical issue(s) for that file verbatim from the report
     - Instruction to fix only these specific issues, touching no other code
     - **Notes file path override**: tell the implementer to write its Implementation Notes to `$TASKS_DIR/notes/autofix-<idx>.md` (e.g., `notes/autofix-01.md`) instead of the standard `task-NN.md` path — there is no task file for auto-fix runs, so the standard NN-derivation rule does not apply.
   - Wait for all task-implementers to complete.
   - Re-run the code-reviewer (same criteria as Step 3) **once** against `$TASKS_DIR/updated-prd.md`. Write the updated report to `$TASKS_DIR/review-report.md` (overwrite).
   - Do not loop — the auto-fix runs at most once. If critical issues persist after the retry, report them in Step 4.

4. **If "Skip — I'll fix them"**: proceed to Step 4 with issues unfixed. Do not spawn any sub-agents. The Step 4 report will list the open critical issues so the user has them in writing.

5. **If "Stop here"**: halt the pipeline. Print a short state summary (branch name, tasks completed, critical-issue count, path to `$TASKS_DIR/review-report.md`) and exit cleanly. Do **not** run Step 4. Do not spawn any sub-agents. Do not commit or push.

## Step 4: Report

Check if `$TASKS_DIR/execution-metrics.md` exists (produced by the orchestrator in full-path mode). If not (fast-path mode), generate equivalent metrics from your own execution.

Summarize the full pipeline run to the user:

```
## Build Complete

### Planning
- [X tasks created]

### Implementation
- [tasks completed / total]
- [any issues]

### Build Check
- [passed / failed / skipped]

### Testing
- [test suite status: all passed / X failed / not detected]
- [if TDD: TDD compliance summary]

### Simplify
- [ran — behavior re-verified green / ran — broke X, user chose Y / skipped / not offered (red baseline)]

### Execution Metrics
- Tasks: [completed/total] | Waves: [N] | Retries: [N]
- TDD: [N/M tasks used TDD] | TDD skipped: [N (reasons)]
- Implementation notes: [see $TASKS_DIR/implementation-notes.md or "inline above"]

### Review
- [compliance score]
- [critical issues if any]
- [if implementation notes reviewed: decision assessment summary]

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
- [what the user should do — e.g., run tests, fix issues, deploy]
```

## Rules
- Run the steps **sequentially** — each depends on the previous
- If Step 1 fails (no tasks created), stop and report the issue
- If Step 2 has partial failures, still run Step 3 to review what was completed
- Always run Step 3 — never skip the review
