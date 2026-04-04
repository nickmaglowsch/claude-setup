# Task 05: Update README.md to Document Agent Teams Option

## Objective
Add a documentation section to `README.md` explaining the Agent Teams orchestration option — what it is, how to use it, its beta status, and how the env var gets configured at runtime.

## Context
The `README.md` documents the build pipeline (`/build`) and refactor pipeline (`/refactor`) but does not mention orchestration modes. Users who encounter the new "Agent Teams (Beta)" option in the mode-selection prompt need context. The README also serves as the onboarding document for new users running `setup.sh`.

**Important**: There is no pre-baked `settings.json` being shipped. The env var (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`) is set dynamically at runtime by the SKILL.md when the user picks Agent Teams mode — it finds and updates the user's existing settings file. The README should accurately reflect this runtime behavior, not imply a template file.

## Existing Code References
- `README.md` — file to modify; read it fully before editing to understand structure, tone, and where the new section fits
- `.claude/agents/agent-teams-orchestrator.md` — what you're documenting; read its opening for accurate description
- `.claude/skills/build/SKILL.md` — to reference the Step 1.5 mode selection accurately

## Implementation Details

### Placement
Add a new `## Agent Teams Mode (Beta)` section after the existing build/refactor pipeline documentation and before any "Contributing" or footer content.

### Section content

1. **What it is**: A second orchestration option in `/build` and `/refactor` that uses Claude Code's native Agent Teams feature instead of spawning a `parallel-task-orchestrator` sub-agent. In Agent Teams mode, the skill session itself acts as lead, spawning teammates directly via Claude Code's native teammate API.

2. **How to use it**: After task planning completes in `/build` or `/refactor`, you'll be asked to choose an orchestration mode. Select "Agent Teams (Beta)" to use this mode. The skill will automatically enable `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` in your settings file.

3. **Beta status and caveats**:
   - The Agent Teams API is experimental — behavior may change in future Claude Code versions
   - `COMMIT_MODE=per-task` in `/refactor` falls back to squash commit when using Agent Teams mode
   - Higher token usage than the default sub-agent approach
   - If Agent Teams is not available in your Claude Code version, use Default mode

4. **Default mode**: Clarify that Default (Recommended) uses `parallel-task-orchestrator` — the proven sub-agent approach — and remains the best choice for most users.

### Tone
Match the existing README tone: concise, practical, no fluff. Use code blocks for env vars. No emojis.

### Length
Aim for 20–30 lines — enough to be useful without burying the existing content.

## Acceptance Criteria
- [ ] `## Agent Teams Mode (Beta)` section exists in README.md
- [ ] Section explains what Agent Teams mode is and which pipelines support it (`/build` and `/refactor`)
- [ ] Section explains that the skill auto-enables `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` at runtime (not via a template settings.json)
- [ ] Beta caveats are documented (experimental API, per-task commit mode limitation, higher token usage)
- [ ] Default mode is mentioned as the recommended option for most users
- [ ] No existing README sections were modified or removed

## Dependencies
- Depends on: Task 01, Task 03, Task 04 — soft dependency (these should be complete so documentation is accurate, but this task can be written in parallel)
- Blocks: None
