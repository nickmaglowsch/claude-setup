# Task 02: Branch creation fix — refactor/SKILL.md

## Objective

Rewrite `Step 0.1` in `refactor/SKILL.md` so that when `BRANCH_ACTION=new`, the skill fetches from origin, detects the default remote branch, and asks the user which base branch to use before running `git checkout -b`.

## Context

This is the same fix as Task 01 applied to `refactor/SKILL.md`. The branch creation block in the refactor skill is structurally identical to the build skill's Step 0.1, with one difference: the auto-commit branch slug prefix is `refactor/` instead of `feat/`.

Everything else — the fetch, detection, user prompt, BASE_BRANCH selection, and retry logic — is identical to Task 01.

Do Task 01 first so you have a verified template to copy from, but these two tasks are technically independent.

## Target Files

- `/home/nick/claude-setup/.claude/skills/refactor/SKILL.md` — source repo (edit first)
- `/home/nick/.claude/skills/refactor/SKILL.md` — global install (edit to match after)

## Requirements

1. After confirming `BRANCH_ACTION=new`, run `git fetch origin` before doing anything else.
2. Detect the default remote branch: `git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||'`. Fall back to `main` if empty or error.
3. Get current branch: `git rev-parse --abbrev-ref HEAD`.
4. Ask the user which base branch to use, with three options (default branch / current branch / other).
5. Store the chosen base as `BASE_BRANCH`.
6. Run `git checkout -b <AUTO_COMMIT_BRANCH> <BASE_BRANCH>`. On failure, append `-2` and retry once.
7. The COMMIT_MODE question and slug generation are unchanged.

## Existing Code References

- `/home/nick/claude-setup/.claude/skills/refactor/SKILL.md` lines 17–26 — the current Step 0.1 block to replace
- `/home/nick/claude-setup/.claude/skills/build/SKILL.md` — the Task 01 result is the template; match it exactly, replacing `feat/` with `refactor/` in the slug prefix

## Implementation Details

Replace the current `Step 0.1` block (lines 17–26 of refactor/SKILL.md) with:

```markdown
## Step 0.1: Auto-commit opt-in

Ask: "Enable auto-commit and PR?" (Yes / No) → `AUTO_COMMIT`.

**If `AUTO_COMMIT=true`:**
1. Run `git rev-parse --abbrev-ref HEAD` to get `CURRENT_BRANCH`. If `CURRENT_BRANCH` is `main` or `master`: `BRANCH_ACTION=new`. Else ask: "Branch `<name>` exists — create new or commit here?" → `BRANCH_ACTION=new/current`.
2. Ask: "Single squash commit or one commit per task?" → `COMMIT_MODE=squash/per-task`.
3. Generate `refactor/<3-5-word-slug>` from `$ARGUMENTS` → `AUTO_COMMIT_BRANCH`.
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

Note: the only difference from the build SKILL.md version is `refactor/<3-5-word-slug>` on step 3 (vs `feat/<3-5-word-slug>`).

After editing the source file, copy the identical change into the global install path.

## Acceptance Criteria

- [ ] `git fetch origin` is the first git command run after `BRANCH_ACTION=new` is confirmed
- [ ] The skill detects the default remote branch via `git symbolic-ref` with a fallback to `main`
- [ ] The skill asks the user to choose a base branch with three options (default, current, other)
- [ ] `git checkout -b` uses the chosen `BASE_BRANCH` explicitly
- [ ] The retry-on-failure behavior is preserved
- [ ] The slug prefix is `refactor/` (not `feat/`)
- [ ] COMMIT_MODE question and slug generation are unchanged
- [ ] Source file and global install file are identical after the edit

## Dependencies

- Depends on: None (Task 01 is a useful reference but not a prerequisite)
- Blocks: Nothing
