# Task: Refactor parallel-task-orchestrator to use Claude Agent Teams

## Status
**Implemented** — see [nickmaglowsch/claude-setup#21](https://github.com/nickmaglowsch/claude-setup/pull/21), 2026-04-03

## What was implemented

Instead of replacing the `parallel-task-orchestrator`, we took a **dual-mode approach**: users choose between the existing sub-agent orchestrator (default, recommended) and a new Agent Teams mode (beta) at the start of `/build` or `/refactor`.

### Architecture decisions

| Original proposal | What we did instead | Why |
|---|---|---|
| Rewrite Phase 3 of `parallel-task-orchestrator` | Created a separate `agent-teams-orchestrator.md` reference guide | Clean separation — existing orchestrator untouched, no risk to current users |
| Orchestrator spawns teammates as a sub-agent | SKILL.md executes Agent Teams at top level | Agent Teams may only work from top-level sessions — nesting risk |
| Pre-bake env var in `settings.json` template | Set env var dynamically at runtime when user selects Agent Teams | User preference, not a global setting — only touches settings when needed |
| Always use Agent Teams | User chooses per-run via prompt (Step 0.2) | Beta feature — default remains the proven sub-agent approach |

### Files added/modified

- **`.claude/agents/agent-teams-orchestrator.md`** (NEW) — reference guide with 4-phase protocol, cost optimizations, known limitations
- **`.claude/skills/build/SKILL.md`** — Step 0.2 mode selection + branched Step 2
- **`.claude/skills/refactor/SKILL.md`** — same Step 0.2 + branched Step 2
- **`setup.sh`** — `agent-teams-orchestrator.md` added to `CLAUDE_FILES`
- **`README.md`** — "Agent Teams Mode (Beta)" documentation section

## Open questions — resolved

| # | Question | Resolution |
|---|----------|------------|
| 1 | Does Agent Teams work from a sub-agent? | Avoided entirely — Agent Teams runs at skill level (top-level session), not inside a sub-agent |
| 2 | TaskCreate/TaskUpdate conflict with Agent Teams task list? | Documented as known limitation with safeguard: fall back to native-only tracking if duplicates detected |
| 3 | Wave logic in Agent Teams? | Kept wave logic — lead computes dependency waves and manages execution order. Teammates self-claim within waves |

## Risks — addressed

| Risk | How addressed |
|------|--------------|
| Experimental flag | Env var set dynamically at runtime, only when user opts in |
| No nested teams | Teammates use `task-implementer` subagent type, not teams — no nesting |
| One team per session | Pre-flight check before spawning; automatic fallback to default orchestrator if team creation fails |
| Token cost | 4 cost optimizations: smart threshold (lead handles simple tasks), task batching, shared context pre-loading, teammate reuse across waves |

## Cost optimizations

The Agent Teams orchestrator includes built-in cost efficiency measures:

1. **Smart threshold**: Tasks classified as simple (single-file, config, docs) are handled by the lead directly — no teammate session overhead
2. **Task batching**: Related small tasks in the same wave grouped into a single teammate (max 3 per batch)
3. **Shared context**: Lead pre-reads common files once and includes a summary in teammate prompts, eliminating N redundant reads
4. **Teammate reuse**: Idle teammates reassigned to next-wave tasks instead of being replaced, keeping project context warm

## Remaining work

- **Real-world testing**: The implementation is based on Agent Teams documentation — needs end-to-end testing with actual Agent Teams sessions once the feature stabilizes
- **Model selection per teammate**: Agent Teams supports specifying models per teammate. Using Sonnet for implementation tasks could further reduce costs (~5x cheaper than Opus). Not yet implemented.
- **Metrics validation**: The execution metrics now track cost optimization data (lead-handled tasks, batches, reuses) but need real runs to verify accuracy

## Related

- [Claude Code Agent Teams docs](https://code.claude.com/docs/en/agent-teams)
- `.claude/agents/agent-teams-orchestrator.md` — Agent Teams orchestration protocol
- `.claude/agents/parallel-task-orchestrator.md` — default sub-agent orchestrator (unchanged)
- `.claude/skills/build/SKILL.md` — main consumer, Step 0.2 + branched Step 2
- `.claude/skills/refactor/SKILL.md` — same pattern
