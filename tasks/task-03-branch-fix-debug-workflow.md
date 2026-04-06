# Task 03: Branch creation fix — debug-workflow/SKILL.md

## Objective

Rewrite the branch creation portion of `Step 0.1` in `debug-workflow/SKILL.md` so that when `BRANCH_ACTION=new`, the skill fetches from origin, detects the default remote branch, and asks the user which base branch to use before running `git checkout -b`.

## Context

`debug-workflow/SKILL.md` Step 0.1 has the same stale-branch problem as build and refactor, but its structure is slightly different:

- It has **no COMMIT_MODE question** — debug always produces a single commit.
- The auto-commit branch prefix is `fix/` (not `feat/` or `refactor/`).
- The current block runs three lines: detect HEAD → set BRANCH_ACTION → generate slug → checkout.

The fix inserts the same fetch-and-ask logic as Tasks 01/02, but adapted to this shorter block.

Read the current file carefully before editing — do not accidentally add a COMMIT_MODE question.

## Target Files

- `/home/nick/claude-setup/.claude/skills/debug-workflow/SKILL.md` — source repo (edit first)
- `/home/nick/.claude/skills/debug-workflow/SKILL.md` — global install (edit to match after)

## Requirements

1. After confirming `BRANCH_ACTION=new`, run `git fetch origin`.
2. Detect default remote branch: `git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||'`. Fall back to `main`.
3. Get current branch name.
4. Ask which base branch to use (three options: default / current / other).
5. Run `git checkout -b <AUTO_COMMIT_BRANCH> <BASE_BRANCH>`. Retry with `-2` on failure.
6. Do NOT add a COMMIT_MODE question — debug-workflow does not use one.
7. The `fix/` slug prefix is unchanged.

## Existing Code References

- `/home/nick/claude-setup/.claude/skills/debug-workflow/SKILL.md` lines 18–28 — the current Step 0.1 block
- `/home/nick/claude-setup/.claude/skills/build/SKILL.md` (after Task 01) — reference for the fetch/detection/prompt pattern

## Implementation Details

The current `Step 0.1` AUTO_COMMIT=true block in debug-workflow reads:

```
1. Run `git rev-parse --abbrev-ref HEAD`. If `main`/`master`: `BRANCH_ACTION=new`. Else ask: "Branch `<name>` exists — create new or commit here?" → `BRANCH_ACTION=new/current`. (No commit granularity question — debug always uses a single commit.)
2. Generate `fix/<3-5-word-slug>` from `BUG_DESCRIPTION` → `AUTO_COMMIT_BRANCH`.
3. `git checkout -b <AUTO_COMMIT_BRANCH>`. On failure append `-2`, retry once.
```

Replace it with:

```markdown
**If `AUTO_COMMIT=true`:**
1. Run `git rev-parse --abbrev-ref HEAD` to get `CURRENT_BRANCH`. If `CURRENT_BRANCH` is `main` or `master`: `BRANCH_ACTION=new`. Else ask: "Branch `<name>` exists — create new or commit here?" → `BRANCH_ACTION=new/current`. (No commit granularity question — debug always uses a single commit.)
2. Generate `fix/<3-5-word-slug>` from `BUG_DESCRIPTION` → `AUTO_COMMIT_BRANCH`.
3. **If `BRANCH_ACTION=new`:**
   - Run `git fetch origin` to get latest remote state.
   - Detect default branch: run `git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||'`. If empty or error, default to `main`. Store as `DEFAULT_BRANCH`.
   - Ask: "Which branch should `<AUTO_COMMIT_BRANCH>` be based on?"
     - Option 1: `<DEFAULT_BRANCH>` (remote default)
     - Option 2: `<CURRENT_BRANCH>` (current branch)
     - Option 3: Other (enter branch name)
   - Store chosen base as `BASE_BRANCH`.
   - Run `git checkout -b <AUTO_COMMIT_BRANCH> <BASE_BRANCH>`. On failure append `-2`, retry once.
```

After editing the source file, copy the identical change into the global install path.

## Acceptance Criteria

- [ ] `git fetch origin` runs after `BRANCH_ACTION=new` is confirmed
- [ ] Default remote branch is detected with fallback to `main`
- [ ] User is asked to choose a base branch with three options
- [ ] `git checkout -b` uses the chosen `BASE_BRANCH` explicitly
- [ ] Retry-on-failure behavior is preserved
- [ ] No COMMIT_MODE question is present (debug-workflow never had one — do not add it)
- [ ] The slug prefix is `fix/`
- [ ] Source file and global install file are identical after the edit

## Dependencies

- Depends on: None
- Blocks: Nothing
