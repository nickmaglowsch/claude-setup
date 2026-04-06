# Task 01: Branch creation fix — build/SKILL.md

## Objective

Rewrite `Step 0.1` in `build/SKILL.md` so that when `BRANCH_ACTION=new`, the skill fetches from origin, detects the default remote branch, and asks the user which base branch to use before running `git checkout -b`.

## Context

Currently `Step 0.1` runs `git checkout -b <AUTO_COMMIT_BRANCH>` from whatever local HEAD is at that moment — no fetch, no base selection. If local `main` is behind origin, the new branch starts from stale code. The user has no way to branch from a different base.

The fix adds two steps between "confirm BRANCH_ACTION=new" and "git checkout -b":
1. `git fetch origin` to pull down latest remote state
2. An interactive base-branch selection (main / current branch / other)

Then `git checkout -b <AUTO_COMMIT_BRANCH> <chosen-base>` uses the selected base explicitly.

This is a behavior addition (new steps inserted), not a logic change to anything that follows. The rest of Step 0.1 (COMMIT_MODE question, slug generation, retry logic) is unchanged.

There are no automated tests for SKILL.md files — behavior is verified by reading the resulting file and confirming it matches the spec below.

## Target Files

- `/home/nick/claude-setup/.claude/skills/build/SKILL.md` — source repo (edit first)
- `/home/nick/.claude/skills/build/SKILL.md` — global install (edit to match after)

## Requirements

1. After confirming `BRANCH_ACTION=new`, run `git fetch origin` before doing anything else.
2. Detect the default remote branch by running: `git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||'`. If this command fails or returns empty, fall back to `main`.
3. Get the current branch name by running: `git rev-parse --abbrev-ref HEAD`.
4. Ask the user: "Which branch should `<AUTO_COMMIT_BRANCH>` be based on?" with these options:
   - Option 1: `<default-branch>` (e.g. `main` — detected from origin/HEAD)
   - Option 2: `<current-branch-name>` (current HEAD)
   - Option 3: Other (user types a custom branch name)
5. Store the selected base in `BASE_BRANCH`.
6. Run `git checkout -b <AUTO_COMMIT_BRANCH> <BASE_BRANCH>`. On failure, append `-2` and retry once (existing retry behavior — preserve it).
7. The COMMIT_MODE question and slug generation are unchanged — they still come before the checkout step.

## Existing Code References

- `/home/nick/claude-setup/.claude/skills/build/SKILL.md` lines 22–31 — the current Step 0.1 block to replace

## Implementation Details

Replace the current `Step 0.1` block (lines 22–31) with the following:

```markdown
## Step 0.1: Auto-commit opt-in

Ask: "Enable auto-commit and PR?" (Yes / No) → `AUTO_COMMIT`.

**If `AUTO_COMMIT=true`:**
1. Run `git rev-parse --abbrev-ref HEAD` to get `CURRENT_BRANCH`. If `CURRENT_BRANCH` is `main` or `master`: `BRANCH_ACTION=new`. Else ask: "Branch `<name>` exists — create new or commit here?" → `BRANCH_ACTION=new/current`.
2. Ask: "Single squash commit or one commit per task?" → `COMMIT_MODE=squash/per-task`.
3. Generate `feat/<3-5-word-slug>` from PRD content → `AUTO_COMMIT_BRANCH`.
4. **If `BRANCH_ACTION=new`:**
   - Run `git fetch origin` to get latest remote state.
   - Detect default branch: run `git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||'`. If empty or error, default to `main`. Store as `DEFAULT_BRANCH`.
   - Ask: "Which branch should `<AUTO_COMMIT_BRANCH>` be based on?"
     - Option 1: `<DEFAULT_BRANCH>` (remote default)
     - Option 2: `<CURRENT_BRANCH>` (current branch)
     - Option 3: Other (enter branch name)
   - Store chosen base as `BASE_BRANCH`.
   - Run `git checkout -b <AUTO_COMMIT_BRANCH> <BASE_BRANCH>`. On failure append `-2`, retry once.

**If `AUTO_COMMIT=false`:** `BRANCH_ACTION=none`, `COMMIT_MODE=none`.
```

After editing the source file, copy the identical change into the global install path.

## Acceptance Criteria

- [ ] `git fetch origin` is the first git command run after `BRANCH_ACTION=new` is confirmed
- [ ] The skill detects the default remote branch via `git symbolic-ref` with a fallback to `main`
- [ ] The skill asks the user to choose a base branch with three options (default, current, other)
- [ ] `git checkout -b` uses the chosen `BASE_BRANCH` explicitly
- [ ] The retry-on-failure behavior (`-2` suffix) is preserved
- [ ] The COMMIT_MODE question and slug generation are unchanged
- [ ] Source file and global install file are identical after the edit

## Dependencies

- Depends on: None
- Blocks: Nothing (Tasks 02, 03, 04 are all independent)
