# Refactoring Tasks: Skill Pipeline UX Improvements

## Summary

Four independent tasks improving two UX issues across three skill files.

**Issue 1 — Branch creation is stale:** When creating a new auto-commit branch, the skill always cuts from local HEAD without fetching from origin or asking which base to use.

**Issue 2 — Orchestration mode is asked every run:** No preference persistence means users see the same question on every invocation.

## Files being changed

| File | Tasks |
|---|---|
| `build/SKILL.md` (source + global) | Task 01, Task 04 |
| `refactor/SKILL.md` (source + global) | Task 02, Task 04 |
| `debug-workflow/SKILL.md` (source + global) | Task 03 |

Source repo: `/home/nick/claude-setup/.claude/skills/`
Global install: `/home/nick/.claude/skills/`

## Task order

All tasks are independent. Execute in any order, or in parallel.

```
task-01-branch-fix-build.md          — build Step 0.1 rewrite
task-02-branch-fix-refactor.md       — refactor Step 0.1 rewrite
task-03-branch-fix-debug-workflow.md — debug-workflow Step 0.1 rewrite
task-04-orchestration-mode-preference.md — build + refactor Step 0.2 rewrite
```

## Dependency graph

```
Task 01 ─┐
Task 02 ─┤  (all independent — no cross-dependencies)
Task 03 ─┤
Task 04 ─┘
```

## Detailed plan

See `tasks/refactor-plan.md` for issue descriptions, risk notes, and out-of-scope decisions.
