# Task 03: Add Agent Teams Mode Selection to build/SKILL.md

## Objective
Add an orchestration mode selection prompt to `.claude/skills/build/SKILL.md` between the task planning step (Step 1) and the implementation step (Step 2). When Agent Teams mode is selected, the SKILL itself executes the agent-teams-orchestrator instructions directly, and dynamically enables the required env var in the user's settings.

## Context
The build pipeline (`/build` skill) currently does:
1. Step 1: Spawn `prd-task-planner` sub-agent (discovery Q&A → generate tasks)
2. Step 2: Spawn `parallel-task-orchestrator` sub-agent (implement all tasks)
3. Step 3: Spawn `code-reviewer` sub-agent (review result)

**Critical**: Because Agent Teams may only work at the top-level session (not from within sub-agents), the Agent Teams execution path must run WITHIN the SKILL.md session itself — not by spawning `agent-teams-orchestrator` as a sub-agent. Instead, the SKILL.md session reads `agent-teams-orchestrator.md` for instructions and executes them directly.

**Env var setup**: When the user picks Agent Teams mode, the SKILL.md must dynamically find and update `settings.json` (or `settings.local.json`) to add `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`, preserving existing settings. This is runtime behavior, similar to how auto-commit handles its own setup prompts.

The mode selection variable is stored as `ORCHESTRATION_MODE` (values: `parallel` or `agent-teams`).

## Existing Code References
- `.claude/skills/build/SKILL.md` (source in repo at same path) — the file to modify. Run `find /home/alcuri/projects/claude-setup -name "SKILL.md" -path "*/build/*"` to confirm location.
- `.claude/agents/parallel-task-orchestrator.md` — understand what the current Step 2 spawns
- `.claude/agents/agent-teams-orchestrator.md` — the reference guide for Agent Teams mode (Task 01)
- `.claude/skills/refactor/SKILL.md` — DO NOT modify in this task; observe its Step 2 pattern for consistency

## Implementation Details

### Step 1: Locate and read the file
Run the find command above to confirm the file path, then read the complete SKILL.md to understand its current structure (Step 0, Step 0.1, Step 1a/1b/1c/1d, Step 2, Step 3, Step 4) before making any edits.

### Step 2: Add Step 1.5 — Orchestration Mode Selection

Insert a new **Step 1.5: Orchestration Mode Selection** block after Step 1d (task review) and before Step 2 (implement):

```markdown
## Step 1.5: Orchestration Mode Selection

Ask the user which orchestration mode to use for implementation:

Use `AskUserQuestion` with:
- Question: "How should tasks be implemented?"
- Options:
  - **Default (Recommended)**: Use `parallel-task-orchestrator` — proven sub-agent approach with wave-based parallel execution
  - **Agent Teams (Beta)**: Use Claude Code's native Agent Teams feature — separate sessions coordinating via shared task list

Store the result as `ORCHESTRATION_MODE` (`parallel` or `agent-teams`).

**If `ORCHESTRATION_MODE=agent-teams`**: Enable the required env var by finding the user's `settings.json` or `settings.local.json` (check `~/.claude/settings.json`, then `.claude/settings.json`, then `.claude/settings.local.json`) and adding `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` to the `env` object, preserving all existing settings. If no settings file exists, create `.claude/settings.local.json` with the env var.
```

### Step 3: Modify Step 2 to branch on ORCHESTRATION_MODE

Replace the current Step 2 block with a branched version:

**If `ORCHESTRATION_MODE=parallel`** (default): behave exactly as today — launch `parallel-task-orchestrator` as a sub-agent via the Task tool with `subagent_type: "parallel-task-orchestrator"`. No behavioral change.

**If `ORCHESTRATION_MODE=agent-teams`**: Do NOT spawn a sub-agent. Instead:
1. Read `.claude/agents/agent-teams-orchestrator.md` (check `~/.claude/agents/` for global installs, `.claude/agents/` for local)
2. Follow those instructions directly in this session to orchestrate tasks using Agent Teams
3. Produce the same outputs: `tasks/implementation-notes.md` and `tasks/execution-metrics.md`

Auto-commit/branch handling (if AUTO_COMMIT=true) applies identically to both modes — add a note to that effect.

### Formatting
- Match the existing SKILL.md heading style exactly (`## Step N: Title` format)
- Keep the mode-selection step concise — 15 lines max
- The branched Step 2 should clearly delineate paths with `**If ORCHESTRATION_MODE=parallel:**` and `**If ORCHESTRATION_MODE=agent-teams:**` subheadings

## Acceptance Criteria
- [ ] `Step 1.5: Orchestration Mode Selection` block exists after Step 1d and before Step 2
- [ ] `AskUserQuestion` is used for mode selection with exactly two options
- [ ] Step 1.5 includes env var setup logic for `agent-teams` mode (find/update settings file)
- [ ] Step 2 has two explicit branches: `parallel` and `agent-teams`
- [ ] In `parallel` branch: `parallel-task-orchestrator` spawned as sub-agent exactly as before
- [ ] In `agent-teams` branch: SKILL session reads and executes `agent-teams-orchestrator.md` directly (no Task tool spawn)
- [ ] No other steps (Step 0, Step 0.1, Step 1a–1d, Step 3, Step 4) are modified

## Dependencies
- Depends on: Task 01 (agent-teams-orchestrator.md must exist to reference)
- Blocks: Task 04 (refactor SKILL uses this as template for consistent wording)
