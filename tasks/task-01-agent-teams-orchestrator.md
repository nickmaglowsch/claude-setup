# Task 01: Create agent-teams-orchestrator.md

## Objective
Create a new Claude Code agent file `.claude/agents/agent-teams-orchestrator.md` that defines the Agent Teams orchestration protocol — the reference document that SKILL.md sessions follow when Agent Teams mode is selected.

## Context
The existing `parallel-task-orchestrator` agent (`.claude/agents/parallel-task-orchestrator.md`) spawns `task-implementer` sub-agents via the `Agent` tool in parallel waves. Agent Teams is Claude Code's native feature that allows a lead session to spawn "teammates" via a shared task list.

**Critical architecture decision**: This agent file is a REFERENCE/GUIDE, not something that gets spawned as a sub-agent. The SKILL.md session itself reads these instructions and executes them directly at the top level — because Agent Teams may only work from top-level sessions, not from within sub-agents.

The agent file still needs standard Claude Code frontmatter (name, description, model, color) so it appears in the agents list and can be referenced.

The output contract must match `parallel-task-orchestrator`: both orchestrators must produce `tasks/implementation-notes.md` and `tasks/execution-metrics.md` in the same format, so the downstream `code-reviewer` step works identically.

## Existing Code References
- `.claude/agents/parallel-task-orchestrator.md` — read this fully; mirror its structure, phase names, output formats, and CRITICAL RULES section. The new agent must be structurally parallel.
- `.claude/agents/task-implementer.md` — understand what it does; Agent Teams teammates will follow the same implementation protocol.

## Implementation Details

Create `.claude/agents/agent-teams-orchestrator.md` with:

### Frontmatter
```yaml
---
name: agent-teams-orchestrator
description: "Reference guide for Agent Teams orchestration mode. Defines how the /build and /refactor skills use Claude Code's native Agent Teams feature to implement tasks. NOT spawned as a sub-agent — the SKILL session executes these instructions directly."
model: sonnet
color: purple
---
```

### Content Structure (mirror parallel-task-orchestrator phases)

**Opening**: Explain this is a reference guide executed at skill level, not as a sub-agent. State the requirement for `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`.

**PHASE 1: DISCOVERY** — identical to parallel-task-orchestrator Phase 1: read all files in `tasks/`, build dependency lists, extract task IDs, file paths, and explicit dependencies.

**PHASE 2: DEPENDENCY ANALYSIS** — identical wave logic (file conflicts, explicit deps, implicit deps). Same visual execution plan output format. Use `TaskCreate`/`TaskUpdate` for visibility — call `TaskCreate` for each task file with subject, description, wave assignment. Use `TaskUpdate` with `addBlockedBy` to wire dependencies.

**PHASE 3: EXECUTION (Agent Teams)**

This phase differs from parallel-task-orchestrator. Instead of spawning sub-agents via the `Agent` tool, use Claude Code's Agent Teams API:

- For each wave, spawn teammates — one per task in the wave
- Each teammate's instruction should follow the same prompt template as parallel-task-orchestrator's sub-agent prompt (read the task file, implement it, report back with Implementation Notes)
- **Wave gate**: wait for all teammates in a wave to complete before starting the next wave — dependency ordering must be preserved
- Teammates report back via the shared task list; lead polls for completion
- After each wave: mark completed tasks via `TaskUpdate status: "completed"`
- **Retry logic**: same as parallel-task-orchestrator — retry failed tasks once with error context appended

Include a note: "The exact Agent Teams API (teammate spawn calls, status polling) is experimental and subject to change. Use the Claude Code Agent Teams documentation as the authoritative reference."

**PHASE 4: COMPLETION** — identical to parallel-task-orchestrator Phase 4:
- Verification step (read sample of modified files)
- Write `tasks/implementation-notes.md` — aggregate notes from teammate outputs (via task list notes field)
- Write `tasks/execution-metrics.md` — same table format as parallel-task-orchestrator
- Summary report to user
- Suggest code-reviewer

### Output Format Requirements
The `tasks/implementation-notes.md` and `tasks/execution-metrics.md` formats must be compatible with what `parallel-task-orchestrator` produces (same markdown tables, same headers). Copy the exact format templates from `.claude/agents/parallel-task-orchestrator.md` Phase 4.

### CRITICAL RULES section
Mirror parallel-task-orchestrator's CRITICAL RULES but replace sub-agent rule with Agent Teams equivalent:
1. NEVER run two teammates that modify the same file in the same wave
2. Read ALL tasks before executing ANY
3. Don't implement code yourself — coordinate only
4. On teammate failure, retry once with error context
5. ALWAYS use TaskCreate/TaskUpdate for visibility

## Acceptance Criteria
- [ ] `.claude/agents/agent-teams-orchestrator.md` exists with valid YAML frontmatter
- [ ] File describes all 4 phases mirroring parallel-task-orchestrator structure
- [ ] Phase 3 describes Agent Teams teammate spawning (not Agent tool sub-agents)
- [ ] Phase 4 output formats (implementation-notes.md, execution-metrics.md) match parallel-task-orchestrator exactly
- [ ] CRITICAL RULES section present with wave/file-conflict constraint preserved
- [ ] Opening clearly states this is a reference guide executed at skill level, not a spawnable sub-agent
- [ ] Note about experimental API status is included

## Dependencies
- Depends on: None
- Blocks: Task 02 (setup.sh references this file), Task 03 (build SKILL references this file), Task 04 (refactor SKILL references this file)
