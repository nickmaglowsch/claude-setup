# Updated PRD: Agent Teams Orchestration Option for /build Pipeline

## Overview

Add a user-selectable orchestration mode to the `/build` (and `/refactor`) pipeline. After task planning completes, users can choose between the existing `parallel-task-orchestrator` sub-agent approach or a new Agent Teams mode that uses Claude Code's native teammates feature.

## Codebase Context

### Existing Architecture
- **Build pipeline**: `.claude/skills/build/SKILL.md` (source: `.claude/skills/build/SKILL.md` in repo; installed globally via `setup.sh`) orchestrates 3 steps: `prd-task-planner` → `parallel-task-orchestrator` → `code-reviewer`
- **Refactor pipeline**: `.claude/skills/refactor/SKILL.md` — mirrors build, Step 2 also uses `parallel-task-orchestrator`
- **Orchestrator**: `.claude/agents/parallel-task-orchestrator.md` — reads tasks, builds dependency waves, spawns `task-implementer` sub-agents in parallel, writes `tasks/implementation-notes.md` and `tasks/execution-metrics.md`
- **setup.sh**: Copies all files in `CLAUDE_FILES` array to `~/.claude/` (global) or `TARGET_DIR/.claude/` (local). No `settings.json` currently exists in the repo.

### What Does NOT Exist Yet
- `.claude/agents/agent-teams-orchestrator.md` — NEW
- Mode-selection prompt in build/refactor SKILLs — NEW (includes runtime env var setup)
- README documentation for Agent Teams mode — NEW

## Resolved Decisions

| Decision | Resolution |
|----------|-----------|
| Where mode-selection prompt lives | Shared helper pattern: both `build/SKILL.md` and `refactor/SKILL.md` get identical mode-selection block between Step 1 and Step 2 |
| Env var management | Runtime: when user picks Agent Teams mode, SKILL.md finds/updates existing `settings.json` or `settings.local.json` to add `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`. No pre-baked template file. |
| Architecture | New separate `agent-teams-orchestrator.md`; build SKILL spawns one or the other |
| Nesting risk | Agent Teams mode runs at the SKILL level (top-level session), NOT inside a sub-agent. The SKILL.md itself handles Agent Teams orchestration directly when that mode is chosen |
| Wave logic | Implementer decides based on Agent Teams native support |
| Notes collection | Teammates return structured output via shared task list notes field; lead aggregates |
| TDD | No TDD mode |

## Requirements

### R1: Mode Selection Prompt
Both `build/SKILL.md` and `refactor/SKILL.md` must present a mode-selection question to the user after task planning (after Step 1 / Step 1d) and before implementation (Step 2). The question uses `AskUserQuestion` with two options:
- **Default (Recommended)**: Spawns `parallel-task-orchestrator` as a sub-agent (current behavior)
- **Agent Teams (Beta)**: Runs Agent Teams orchestration directly in the SKILL.md session

### R2: Agent Teams Orchestrator Agent File
Create `.claude/agents/agent-teams-orchestrator.md` defining the Agent Teams orchestration protocol:
- Reads and parses all task files
- Builds dependency graph (same wave logic as parallel-task-orchestrator)
- Uses `TeamCreate` / `TeamAddMember` (or equivalent Agent Teams API) to spawn teammates
- Lead aggregates notes from shared task list and writes `tasks/implementation-notes.md` and `tasks/execution-metrics.md`
- Same output contract as `parallel-task-orchestrator` (both output files, same format)

### R3: Skill-Level Agent Teams Execution
When Agent Teams mode is selected, the SKILL.md itself (not a sub-agent) executes the Agent Teams logic by following the `agent-teams-orchestrator.md` instructions directly. This is because Agent Teams may only work at the top-level session.

### R4: Runtime Env Var Setup
When the user selects Agent Teams mode in Step 1.5, the SKILL.md must dynamically enable the env var by locating the user's settings file (`~/.claude/settings.json`, `.claude/settings.json`, or `.claude/settings.local.json`) and adding `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` to the `env` object, preserving all existing settings. If no settings file exists, create `.claude/settings.local.json`.

### R5: setup.sh Update
Add `.claude/agents/agent-teams-orchestrator.md` to the `CLAUDE_FILES` array so it is copied during global and local installs.

### R6: README Documentation
Add a section to `README.md` documenting the Agent Teams option: what it is, how to enable it, beta status, and the env var requirement.

## Risk Flags

- **Agent Teams nesting**: Confirmed decision is skill-level execution to avoid this risk entirely.
- **Agent Teams API**: The exact API (`TeamCreate`, `TeamAddMember`, etc.) should be documented in the agent file as best-known at time of writing, with a note that it's experimental.
- **Settings file merge**: The SKILL.md must merge `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` into existing settings without overwriting other keys. Read → merge → write pattern required.

## Out of Scope
- Modifying `parallel-task-orchestrator.md` behavior
- Agent Teams support in `debug-workflow` skill
- Auto-commit integration for Agent Teams mode (inherits from build/refactor SKILL existing logic)
