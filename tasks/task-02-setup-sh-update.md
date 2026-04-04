# Task 02: Update setup.sh — Add agent-teams-orchestrator.md to CLAUDE_FILES

## Objective
Add `.claude/agents/agent-teams-orchestrator.md` to the `CLAUDE_FILES` array in `setup.sh` so the new agent file is copied during global and local installs.

## Context
`setup.sh` maintains a `CLAUDE_FILES` array (around line 157) listing all files that get copied to `~/.claude/` (global install) or `TARGET_DIR/.claude/` (local install). Every new agent or skill file must be added here to be distributed.

The current agents in the array are in alphabetical order within their section. The new entry should follow that convention.

No `settings.json` file is being added to CLAUDE_FILES — the env var is handled at runtime by the SKILL.md (Task 03), not as a pre-baked template file.

## Existing Code References
- `setup.sh` — file to modify; the `CLAUDE_FILES` array starts at line 157. Read lines 156–177 to see the current array contents before editing.

## Implementation Details

In the `CLAUDE_FILES` array, add the new agent entry in alphabetical order among the other `.claude/agents/` entries. The current agents list is:

```
.claude/agents/app-scout.md
.claude/agents/bug-fixer.md
.claude/agents/bug-investigator.md
.claude/agents/code-reviewer.md
.claude/agents/parallel-task-orchestrator.md
.claude/agents/prd-task-planner.md
.claude/agents/qa-agent.md
.claude/agents/refactor-planner.md
.claude/agents/task-implementer.md
.claude/agents/test-writer.md
```

Add `".claude/agents/agent-teams-orchestrator.md"` after `app-scout.md` and before `bug-fixer.md` (alphabetical: `agen` sorts before `bug`).

The resulting agents section should read:
```bash
  ".claude/agents/app-scout.md"
  ".claude/agents/agent-teams-orchestrator.md"
  ".claude/agents/bug-fixer.md"
```

## Acceptance Criteria
- [ ] `.claude/agents/agent-teams-orchestrator.md` appears in the `CLAUDE_FILES` array
- [ ] Entry is placed in alphabetical order among the agents entries
- [ ] No other entries in `CLAUDE_FILES` were added, removed, or reordered
- [ ] `setup.sh` is syntactically valid bash — `bash -n setup.sh` exits 0

## Dependencies
- Depends on: Task 01 (agent-teams-orchestrator.md must exist in the repo before setup.sh references it)
- Blocks: None
