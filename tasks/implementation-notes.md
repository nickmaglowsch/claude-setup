# Implementation Notes

## Task 01: Branch creation fix — build/SKILL.md
- **Decisions**: Added `git fetch origin` before checkout; detect default branch via `git symbolic-ref` with `main` fallback; three-option base selection prompt.
- **Deviations**: None.
- **Trade-offs**: The base-branch question adds one extra step per auto-commit run, but this is explicitly what the user requested.
- **Risks**: None — purely additive instructions in a markdown skill file.

## Task 02: Branch creation fix — refactor/SKILL.md
- **Decisions**: Identical change to Task 01, adapted for `refactor/` slug prefix.
- **Deviations**: None.
- **Trade-offs**: None.
- **Risks**: None.

## Task 03: Branch creation fix — debug-workflow/SKILL.md
- **Decisions**: Same pattern; preserved the "(No commit granularity question — debug always uses a single commit.)" note on step 1.
- **Deviations**: None.
- **Trade-offs**: None.
- **Risks**: None.

## Task 04: Orchestration mode preference — build + refactor SKILL.md
- **Decisions**: Stored preference in `~/.claude/user-preferences.json`; used `python3 -c` for safe JSON merge to preserve future keys; included a code comment reminding the skill to substitute the actual value before running.
- **Deviations**: The python3 snippet in the skill file shows `'parallel'` as a placeholder with a comment — the skill is instructed to substitute the actual resolved value at runtime.
- **Trade-offs**: An inline comment was added to the bash snippet to make the substitution requirement explicit, avoiding a silent bug where the preference is always saved as `parallel`.
- **Risks**: None — `python3` is reliably present on all supported platforms; the `2>/dev/null` on the cat command handles missing file gracefully.
