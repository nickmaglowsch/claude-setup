# Task 04: Add Agent Teams Mode Selection to refactor/SKILL.md

## Objective
Add the same orchestration mode selection prompt to `.claude/skills/refactor/SKILL.md` between Step 1d (plan approval) and Step 2 (implementation), mirroring the change made to the build skill in Task 03.

## Context
The refactor pipeline mirrors the build pipeline's Step 2: it spawns `parallel-task-orchestrator` as a sub-agent. The refactor SKILL has additional complexity — it has a `COMMIT_MODE` variable that changes how the orchestrator is spawned (per-task vs squash). Both commit mode variants must be preserved in the parallel branch.

The `ORCHESTRATION_MODE` variable naming, option text, and env var setup logic must be IDENTICAL to what was added in Task 03 so the user experience is consistent across `/build` and `/refactor`.

**Note on per-task commit mode**: `COMMIT_MODE=per-task` sequential commits are not supported in Agent Teams mode (teammates run in parallel). When `ORCHESTRATION_MODE=agent-teams`, fall back to squash-style commit (commit once at end).

## Existing Code References
- `.claude/skills/refactor/SKILL.md` — file to modify; read it fully before editing. Pay attention to where Step 1d ends, the two COMMIT_MODE variants in Step 2, and Steps 2b/2c/2.5/Step 3.
- `.claude/skills/build/SKILL.md` — the equivalent change from Task 03; use as the exact template for the Step 1.5 block (word-for-word identical).
- `.claude/agents/agent-teams-orchestrator.md` — what the Agent Teams path reads and executes.

## Implementation Details

### Step 1: Read the full file
Read `.claude/skills/refactor/SKILL.md` completely before making any edits.

### Step 2: Insert Step 1.5

After Step 1d's closing content and before the `## Step 2:` header, insert the following block (must be word-for-word identical to Task 03's version):

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

### Step 3: Modify Step 2

Wrap the existing Step 2 content in a top-level `ORCHESTRATION_MODE` branch:

**If `ORCHESTRATION_MODE=parallel`**: keep the EXACT existing Step 2 content (both COMMIT_MODE variants) unchanged.

**If `ORCHESTRATION_MODE=agent-teams`**:
1. Read `.claude/agents/agent-teams-orchestrator.md` (check `~/.claude/agents/` for global installs, `.claude/agents/` for local)
2. Execute those instructions directly in this session using Agent Teams
3. Note: `COMMIT_MODE=per-task` is not supported in Agent Teams mode — commits will be applied squash-style at end of implementation (Step 2.5b)

Steps 2b (build check), 2c (test verification), 2.5 (auto-commit/PR), and Step 3 (review) are unchanged — they run after implementation regardless of mode.

### Formatting
- Match the existing SKILL.md heading style exactly
- The Step 1.5 block must be word-for-word identical to the one added in Task 03

## Acceptance Criteria
- [ ] `Step 1.5: Orchestration Mode Selection` block exists in the file, identical text to Task 03's version
- [ ] `AskUserQuestion` used with same two options as Task 03
- [ ] Step 1.5 includes env var setup logic identical to Task 03
- [ ] Step 2 has two explicit branches for `parallel` and `agent-teams`
- [ ] In `parallel` branch: both `COMMIT_MODE=per-task` and `COMMIT_MODE=squash` variants preserved exactly as before
- [ ] In `agent-teams` branch: SKILL session reads and executes `agent-teams-orchestrator.md` directly
- [ ] Note about per-task commit fallback is included in the agent-teams branch
- [ ] Steps 2b, 2c, 2.5, Step 3 are NOT modified

## Dependencies
- Depends on: Task 01 (agent-teams-orchestrator.md), Task 03 (use as template for consistent wording)
- Blocks: None
