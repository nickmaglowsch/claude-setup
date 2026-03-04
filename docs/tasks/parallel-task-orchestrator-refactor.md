# Task: Refactor parallel-task-orchestrator to use Claude Agent Teams

## Status
Deferred — pending Agent Teams feature stability (currently experimental)

## Background

Claude Code's native **Agent Teams** feature (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`) provides
built-in primitives that the `parallel-task-orchestrator` currently reimplements manually:

| What we do today | What Agent Teams provides natively |
|---|---|
| Spawn parallel subagents via multiple `Agent` tool calls | Teammates spawned and coordinated by the team lead |
| Coordinate via `tasks/*.md` files | Shared task list + direct inter-agent messaging |
| Blind parallel execution (no visibility) | Split panes or in-process view per teammate |
| Manual wave tracking + TaskCreate/TaskUpdate | Shared task list with native status |

The orchestrator is essentially a hand-rolled version of what Agent Teams does at the platform level.
Migrating would reduce complexity and add real-time visibility into parallel implementation.

## What changes

### `.claude/agents/parallel-task-orchestrator.md`

**Phase 3: Execution** is the main target. Today it does:
```
For each wave:
  - Spawn N Agent tool calls in a single message
  - Wait for all to return
  - Mark completed via TaskUpdate
```

With Agent Teams it would:
```
For each wave:
  - Create teammates via the Agent Teams API
  - Assign each teammate its task file
  - Teammates share the task list — status updates happen natively
  - Wait for all teammates to signal done via shared task list / messaging
```

**Phases 1, 2, and 4 are unchanged** — dependency graph analysis and the execution report stay the same.
The orchestrator's role as coordinator (not implementer) stays the same.

### `settings.json` (project-level or global)

Enable the feature:
```json
{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  }
}
```

This would be added to `.claude/settings.json` in the setup repo and copied to target projects via `setup.sh`.

## Benefits

- **Visibility**: Users see all parallel tasks executing in split panes instead of a black box
- **Native coordination**: Teammates can message each other if they hit a conflict (e.g., unexpected file overlap)
- **Less code**: Remove manual wave-loop logic and rely on platform primitives
- **Consistency with ecosystem**: Aligns with how the broader Claude Code ecosystem (e.g., overstory) does parallel work

## Risks / blockers

- **Experimental flag**: Feature is still opt-in and unstable. No session resumption for in-process teammates. Task status can lag.
- **No nested teams**: Teammates cannot spawn their own teams. Currently the orchestrator spawns `task-implementer` subagents — those subagents cannot themselves spawn teammates. This is fine as long as tasks stay atomic.
- **One team per session**: If a pipeline skill (e.g., `/build`) already uses Agent Teams elsewhere, the orchestrator can't create a second team. Need to verify this isn't a problem in practice.
- **Token cost**: Each teammate has its own context window. For large task sets this could be significantly more expensive than the current approach.

## Open questions

1. Does the Agent Teams API work the same when the orchestrator is itself a subagent (spawned by `/build`)? Or does Agent Teams only work at the top-level session?
2. Can we keep the `TaskCreate`/`TaskUpdate` progress tracking on top of native Agent Teams, or does it conflict?
3. What happens to the dependency wave logic — does Agent Teams have any concept of task ordering, or do we still manage waves manually and just use teammates within each wave?

## Suggested approach when ready

1. Enable `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` and manually test a small parallel run
2. Answer the open questions above through experimentation
3. Rewrite Phase 3 of the orchestrator to use teammates instead of `Agent` tool calls
4. Keep Phases 1, 2, and 4 unchanged
5. Test via `/build` with a multi-task PRD — verify the full pipeline still works end-to-end
6. Add `settings.json` to `CLAUDE_FILES` in `setup.sh` if it doesn't already exist

## Related

- [Claude Code Agent Teams docs](https://code.claude.com/docs/en/agent-teams)
- `.claude/agents/parallel-task-orchestrator.md` — current implementation
- `.claude/skills/build/SKILL.md` — main consumer of the orchestrator
- `docs/tasks/` — other deferred tasks
