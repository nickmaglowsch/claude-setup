# Agent Teams Orchestration Option — Task Plan

## Summary
Add an Agent Teams orchestration mode to the `/build` and `/refactor` pipelines. Users will be prompted to choose between the existing `parallel-task-orchestrator` sub-agent approach (Default) and Claude Code's native Agent Teams feature (Beta). Agent Teams mode runs at the SKILL session level to avoid nesting issues. The required env var is set dynamically at runtime when the user picks Agent Teams mode — no pre-baked settings file is shipped.

## Total Tasks: 5 | Complexity: Medium

## Dependency Graph

```
Task 01: agent-teams-orchestrator.md ──────────────► Task 02: setup.sh update
Task 01: agent-teams-orchestrator.md ──────────────► Task 03: build SKILL
Task 01: agent-teams-orchestrator.md ──────────────► Task 04: refactor SKILL
Task 03: build SKILL (for wording) ────────────────► Task 04: refactor SKILL

Task 01, 02, 03, 04 ───────────────────────────────► Task 05: README (soft dep — can run in parallel)
```

## Task Order

| # | Task | Depends On | Status |
|---|------|-----------|--------|
| 01 | Create `agent-teams-orchestrator.md` | None | — |
| 02 | Update `setup.sh` CLAUDE_FILES array | 01 | — |
| 03 | Add mode selection to `build/SKILL.md` | 01 | — |
| 04 | Add mode selection to `refactor/SKILL.md` | 01, 03 | — |
| 05 | Update `README.md` | 01, 03, 04 (soft) | — |

## Parallel Execution Waves

- **Wave 1** (no deps): Task 01
- **Wave 2** (parallel after 01): Task 02, Task 03, Task 05
- **Wave 3** (after 03): Task 04

## Files Modified

| File | Task(s) |
|------|---------|
| `.claude/agents/agent-teams-orchestrator.md` | 01 (CREATE) |
| `setup.sh` | 02 |
| `.claude/skills/build/SKILL.md` | 03 |
| `.claude/skills/refactor/SKILL.md` | 04 |
| `README.md` | 05 |

## How to Use These Files

These task files are prompts for AI agents. Each file is self-contained with all context needed. Delete each file after the task is completed. When all task files are deleted, the feature is complete.

```bash
# After each task is done:
rm tasks/task-0N-<name>.md

# When all tasks are done, clean up:
rm -rf tasks/
```

## Open Questions / Decisions for Implementer

1. **Agent Teams API surface**: The exact Claude Code API for spawning teammates (function names, parameters) is experimental. Task 01 implementer should use best-known API and add a note about experimental status.

2. **SKILL.md location**: The source build/refactor SKILL.md files live at `.claude/skills/build/SKILL.md` and `.claude/skills/refactor/SKILL.md` in the repo. Run `find /home/alcuri/projects/claude-setup -name "SKILL.md"` to confirm paths before editing.

3. **Settings file detection**: When enabling the env var at runtime, check for settings files in this order: `~/.claude/settings.json`, `.claude/settings.json`, `.claude/settings.local.json`. Create `.claude/settings.local.json` if none exist.
