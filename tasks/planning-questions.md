# Planning Questions

## Codebase Summary

The `/build` pipeline is orchestrated by `.claude/skills/build/SKILL.md` (installed globally via `setup.sh` but not readable due to permissions). Based on the `refactor` skill (which mirrors the build pipeline pattern) and the agents, the pipeline is:

1. **Step 1**: `prd-task-planner` agent — discovery + Q&A + generate task files into `tasks/`
2. **Step 2**: `parallel-task-orchestrator` agent — reads tasks, builds dependency graph, spawns `task-implementer` sub-agents in parallel waves, writes `tasks/implementation-notes.md` and `tasks/execution-metrics.md`
3. **Step 3**: `code-reviewer` agent — reviews against the updated PRD

Key relevant files:
- `.claude/agents/parallel-task-orchestrator.md` — Phase 3 spawns `task-implementer` sub-agents via multiple `Agent` tool calls in a single message, organized into dependency waves
- `.claude/agents/task-implementer.md` — executes a single task file; supports TDD mode
- `docs/tasks/parallel-task-orchestrator-refactor.md` — a **deferred design doc** already written for this exact migration, with key open questions documented

The deferred design doc explicitly notes `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` as the env var needed, and calls out three unresolved questions about nested teams, TaskCreate/TaskUpdate compatibility, and whether wave logic survives.

There is **no `settings.json`** in the project repo (only `settings.local.json` and global `~/.claude/settings.json`), so enabling the env var would require adding one.

## Questions

### Q1: Where does the mode-selection prompt live?
**Context:** The build pipeline is orchestrated by `skills/build/SKILL.md`. The PRD says "add a user prompt after task planning, before implementation." The natural place is inside the build SKILL.md itself (between Steps 1 and 2). But `SKILL.md` can't be read due to permissions — only the installed global copy exists.
**Question:** Should the mode-selection prompt be added directly inside `skills/build/SKILL.md`, or should it be delegated to a wrapper/hook so the SKILL.md stays minimal? Also: do you want this same prompt in the `refactor` SKILL.md (which also uses `parallel-task-orchestrator`)?
**Options:**
- A) Add the prompt inline in `build/SKILL.md` only
- B) Add the prompt inline in both `build/SKILL.md` and `refactor/SKILL.md`
- C) Abstract it — create a new orchestration-mode helper that both skills call

### Q2: Agent Teams env var — how should it be enabled?
**Context:** Agent Teams requires `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`. The deferred design doc notes this would go in `settings.json`. There's no project-level `settings.json` in this repo currently (only `settings.local.json` for gitignored local config). Enabling it globally would affect all pipelines in all projects.
**Question:** How should the Agent Teams env var be managed?
**Options:**
- A) Add it to the global `~/.claude/settings.json` permanently (always on for all sessions)
- B) Add it to a new project-level `.claude/settings.json` in this repo (copied to projects via `setup.sh`)
- C) Have the build skill set it conditionally at runtime only when Agent Teams mode is selected (if Claude Code supports per-run env injection)
- D) Document it as a prerequisite — the user must enable it manually before choosing Agent Teams mode

### Q3: Where does Agent Teams logic live?
**Context:** The deferred design doc proposes rewriting Phase 3 of `parallel-task-orchestrator.md` to use teammates. The PRD alternatively suggests the build SKILL itself could create teams. These are architecturally different: (a) the orchestrator always uses teammates when spawned, vs (b) the skill spawns either the current orchestrator or a new agent-teams-aware orchestrator based on user choice.
**Question:** Which approach do you prefer?
**Options:**
- A) Modify `parallel-task-orchestrator.md` to accept a mode flag in its prompt, and internally switch between the current sub-agent approach and an Agent Teams approach (single agent, two modes)
- B) Create a new separate agent `agent-teams-orchestrator.md` — the build skill spawns one or the other based on user choice (two agents, clean separation)
- C) Put all Agent Teams logic in the build SKILL.md itself, bypassing the orchestrator for that mode

### Q4: Unresolved nested-team question
**Context:** The deferred design doc flags: "Does the Agent Teams API work the same when the orchestrator is itself a subagent (spawned by `/build`)? Or does Agent Teams only work at the top-level session?" This is still unresolved and could be a hard blocker — if teammates can only be created from the top-level session, the entire approach fails.
**Question:** Have you tested or confirmed that Agent Teams works when the orchestrator is a sub-agent (spawned by the build skill via `Task` tool)? Or should the task include a spike/validation step first?
**Options:**
- A) Include a validation spike as task-01 — confirm Agent Teams nesting works before writing the full implementation
- B) Assume it works and build it; if it fails at runtime the user will see the error
- C) Restructure: put Agent Teams orchestration at the skill level (top-level session) rather than inside a sub-agent

### Q5: Wave/dependency logic in Agent Teams mode
**Context:** The current orchestrator runs tasks in dependency-ordered waves. Agent Teams has no native concept of task ordering — it's a shared task list with statuses. The deferred design doc asks: "do we still manage waves manually and just use teammates within each wave?"
**Question:** In Agent Teams mode, should the lead session still compute dependency waves and only spawn teammates wave-by-wave (preserving current behavior), or should it attempt a flat parallel execution and rely on teammates to check task status before starting?
**Options:**
- A) Keep wave logic — lead computes waves, spawns a team per wave, waits for completion before next wave
- B) Flat parallel — spawn all tasks as teammates at once, teammates check `blockedBy` dependencies in the shared task list before starting work
- C) Your call — let the implementer decide based on what Agent Teams natively supports

### Q6: Output parity — implementation-notes.md and execution-metrics.md
**Context:** The orchestrator's Phase 4 writes `tasks/implementation-notes.md` and `tasks/execution-metrics.md`. The PRD says Agent Teams mode must also produce these. In Agent Teams mode, teammates report back via the shared task list rather than returning output to the lead. The synthesis step needs to aggregate their notes.
**Question:** How should implementation notes be collected from teammates in Agent Teams mode?
**Options:**
- A) Same as current — each teammate writes its implementation notes to a temp file (e.g., `tasks/.notes-task-01.md`), lead reads and consolidates at the end
- B) Teammates return structured output via the shared task list description/notes field, lead aggregates
- C) Implementation notes are best-effort in Agent Teams mode — document this as a known limitation

### Q7: TDD mode
**Question:** Do you want TDD mode for this build? If yes, the task implementer will write failing tests before implementation code for each task.
