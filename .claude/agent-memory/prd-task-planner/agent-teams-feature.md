---
name: Agent Teams Feature Architecture
description: Key architecture decisions for Agent Teams orchestration mode in /build and /refactor pipelines
type: project
---

Agent Teams mode runs at the SKILL session level (not as a sub-agent) to avoid nesting issues with Claude Code's experimental Agent Teams API.

**Why:** Agent Teams may only work from top-level sessions. Spawning agent-teams-orchestrator via Task tool would fail.

**How to apply:** When modifying build/refactor SKILLs for orchestration features, always consider whether the feature requires top-level session context.

Key files:
- `.claude/agents/agent-teams-orchestrator.md` — reference guide (not spawnable sub-agent)
- `.claude/skills/build/SKILL.md` and `.claude/skills/refactor/SKILL.md` — mode selection in Step 1.5
- `setup.sh` CLAUDE_FILES array — must include any new agent/skill files to distribute them

Env var (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`) is set at runtime by SKILL.md when user picks Agent Teams mode — no pre-baked settings.json template. SKILL finds/merges into existing settings file.
