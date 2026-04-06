# Refactor Plan: Skill Pipeline UX Improvements

## What this plan addresses

Two independent UX issues across three skill files:

1. **Auto-commit branch creation is stale and inflexible** — when creating a new branch, the skill always cuts from local HEAD without fetching from origin or asking the user which base branch to use.

2. **Orchestration mode is asked on every run** — users who always pick the same mode are interrupted by the same question every time, with no way to skip it.

---

## Issues and their locations

| Issue | Location | Severity |
|---|---|---|
| No `git fetch origin` before `git checkout -b` | `build/SKILL.md` Step 0.1, `refactor/SKILL.md` Step 0.1, `debug-workflow/SKILL.md` Step 0.1 | Medium |
| No base-branch selection when creating new branch | Same three files | Medium |
| Orchestration mode always asked, no saved preference | `build/SKILL.md` Step 0.2, `refactor/SKILL.md` Step 0.2 | Medium |
| No user preferences persistence mechanism | Global — no `~/.claude/user-preferences.json` exists | Medium |

---

## What each task does

### Task 01: Branch creation fix — build/SKILL.md
Rewrites `Step 0.1` in `build/SKILL.md` to fetch from origin and ask the user which base branch to use before creating the auto-commit branch. Edits both the source repo and the global install.

### Task 02: Branch creation fix — refactor/SKILL.md
Same change as Task 01 but for `refactor/SKILL.md`. Separated so each file edit is atomic and independently verifiable. Edits both the source repo and the global install.

### Task 03: Branch creation fix — debug-workflow/SKILL.md
Same branch creation fix for `debug-workflow/SKILL.md`. Note: this skill does not have a `COMMIT_MODE` question (it always uses a single commit), so the branching block is slightly shorter than build/refactor. Edits both the source repo and the global install.

### Task 04: Orchestration mode preference — build/SKILL.md and refactor/SKILL.md
Rewrites `Step 0.2` in both `build/SKILL.md` and `refactor/SKILL.md` to:
- Read `~/.claude/user-preferences.json` before asking
- Skip the question if a saved preference exists (log and proceed)
- Ask "Save as default?" after the user answers, and write/update the file if yes
Edits both the source repo and the global install for both files.

---

## What is intentionally out of scope

- No changes to agents, orchestrators, or any file other than the three SKILL.md files
- No changes to `~/.claude/settings.json` — preferences go in the new dedicated file
- No preference persistence for any question other than orchestration mode (could be extended later)
- No UI for viewing or clearing saved preferences (user can edit `~/.claude/user-preferences.json` directly)

---

## Dependency order

```
Task 01 (build branch fix)
Task 02 (refactor branch fix)     — independent of Task 01
Task 03 (debug-workflow branch fix) — independent of Task 01/02
Task 04 (orchestration preference) — independent of Tasks 01-03
```

All four tasks are independent of each other. They can be executed in any order or in parallel. Task 04 touches two files (build + refactor Step 0.2) but both edits are in the same task to keep the preference logic co-located.

---

## Risks to watch for

- **`git symbolic-ref refs/remotes/origin/HEAD`** may fail if origin has not been fetched yet or HEAD is not set. The branch detection must handle this gracefully — fall back to asking the user or defaulting to `main`.
- **`~/.claude/user-preferences.json` JSON merge**: when saving orchestration mode, any existing keys in the file must be preserved. The write must be a read-merge-write, not an overwrite.
- **Both source and global install must be edited** — changes in `/home/nick/claude-setup/.claude/skills/` do not auto-deploy to `/home/nick/.claude/skills/`. Each task edits both paths explicitly.
- **debug-workflow Step 0.1 is structurally slightly different** from build/refactor — it has no `COMMIT_MODE` question and the branch slug prefix is `fix/` not `feat/` or `refactor/`. Read it carefully before editing.
