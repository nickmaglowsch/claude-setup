# Task 04: Orchestration mode preference — build/SKILL.md and refactor/SKILL.md

## Objective

Rewrite `Step 0.2` in both `build/SKILL.md` and `refactor/SKILL.md` to read a saved orchestration mode preference from `~/.claude/user-preferences.json` before asking the question, skip the question entirely if a preference exists, and offer to save the answer as a default after the user responds.

## Context

Currently Step 0.2 in both skills always presents an `AskUserQuestion` for orchestration mode — even if the user has picked the same option dozens of times. There is no persistence mechanism.

The fix adds a preference check at the start of the step. If `~/.claude/user-preferences.json` exists and contains an `orchestrationMode` key, the skill reads it, logs a one-line note ("Using saved orchestration mode: parallel"), sets `ORCHESTRATION_MODE`, and moves on. The question is skipped entirely.

If no preference is saved, the existing question runs as today. After the user answers, the skill asks: "Save this as your default orchestration mode?" (Yes/No). If yes, it writes/updates `~/.claude/user-preferences.json` — preserving any existing keys — with `{ "orchestrationMode": "<value>" }`.

The preferences file format is simple JSON: `{ "orchestrationMode": "parallel" }` or `{ "orchestrationMode": "agent-teams" }`.

The Step 0.2 body in build/SKILL.md and refactor/SKILL.md is **identical** — the same replacement text applies to both. Confirm this after editing.

## Target Files

- `/home/nick/claude-setup/.claude/skills/build/SKILL.md` — source repo
- `/home/nick/.claude/skills/build/SKILL.md` — global install
- `/home/nick/claude-setup/.claude/skills/refactor/SKILL.md` — source repo
- `/home/nick/.claude/skills/refactor/SKILL.md` — global install

## Requirements

1. At the start of Step 0.2, check whether `~/.claude/user-preferences.json` exists and contains an `orchestrationMode` key.
   - Use: `cat ~/.claude/user-preferences.json 2>/dev/null` and parse the result. If the file does not exist or the key is absent, treat as "no preference saved."
2. If a preference IS saved:
   - Do NOT ask the `AskUserQuestion`.
   - Log: "Using saved orchestration mode: `<value>`" (inline, not a separate user prompt).
   - Set `ORCHESTRATION_MODE` to the saved value (`parallel` or `agent-teams`).
   - Proceed to the next step.
3. If NO preference is saved:
   - Ask the existing `AskUserQuestion` as today (same question text, same two options).
   - Store the result as `ORCHESTRATION_MODE`.
   - Then ask: "Save this as your default orchestration mode?" (Yes / No).
   - If Yes: read `~/.claude/user-preferences.json` (or start with `{}`), merge in `{ "orchestrationMode": "<ORCHESTRATION_MODE>" }` preserving any existing keys, and write the result back. Use the bash command pattern:
     ```bash
     python3 -c "
     import json, os
     path = os.path.expanduser('~/.claude/user-preferences.json')
     prefs = json.load(open(path)) if os.path.exists(path) else {}
     prefs['orchestrationMode'] = '<ORCHESTRATION_MODE>'
     json.dump(prefs, open(path, 'w'), indent=2)
     "
     ```
   - If No: proceed without saving.

## Existing Code References

- `/home/nick/claude-setup/.claude/skills/build/SKILL.md` lines 33–43 — current Step 0.2 block (build)
- `/home/nick/claude-setup/.claude/skills/refactor/SKILL.md` lines 28–38 — current Step 0.2 block (refactor)

## Implementation Details

Replace the current `Step 0.2` section in **both** build/SKILL.md and refactor/SKILL.md with:

```markdown
## Step 0.2: Orchestration Mode Selection

Check for a saved orchestration mode preference:
- Run: `cat ~/.claude/user-preferences.json 2>/dev/null`
- If the file exists and contains an `"orchestrationMode"` key:
  - Log: "Using saved orchestration mode: `<value>`"
  - Set `ORCHESTRATION_MODE` to the saved value (`parallel` or `agent-teams`)
  - Skip the rest of this step and proceed to Step 0.

If no saved preference, ask the user which orchestration mode to use:

Use `AskUserQuestion` with:
- Question: "How should tasks be implemented?"
- Options:
  - **Default (Recommended)**: Use `parallel-task-orchestrator` — proven sub-agent approach with wave-based parallel execution
  - **Agent Teams (Beta)**: Use Claude Code's native Agent Teams feature — separate sessions coordinating via shared task list

Store the result as `ORCHESTRATION_MODE` (`parallel` or `agent-teams`).

Then ask: "Save this as your default orchestration mode?" (Yes / No).

If Yes: merge `{ "orchestrationMode": "<ORCHESTRATION_MODE>" }` into `~/.claude/user-preferences.json`, preserving any existing keys. Use:
```bash
python3 -c "
import json, os
path = os.path.expanduser('~/.claude/user-preferences.json')
prefs = json.load(open(path)) if os.path.exists(path) else {}
prefs['orchestrationMode'] = '<ORCHESTRATION_MODE>'
json.dump(prefs, open(path, 'w'), indent=2)
"
```
```

**Important:** The `ORCHESTRATION_MODE` value substituted into the python3 command must be the actual resolved value (`parallel` or `agent-teams`), not the literal string `<ORCHESTRATION_MODE>`.

After editing both source files, copy the identical changes into both global install paths.

## Acceptance Criteria

- [ ] If `~/.claude/user-preferences.json` exists with `"orchestrationMode"`, the `AskUserQuestion` is skipped
- [ ] The skipped-question case logs "Using saved orchestration mode: `<value>`"
- [ ] `ORCHESTRATION_MODE` is set correctly in both the saved-preference and the asked-question paths
- [ ] After the user answers the question, a "Save as default?" follow-up is offered
- [ ] Answering Yes writes/updates `~/.claude/user-preferences.json` without destroying other keys
- [ ] Answering No proceeds without touching the file
- [ ] The change is identical in build/SKILL.md and refactor/SKILL.md
- [ ] All four files (2 source + 2 global) are updated and consistent

## Dependencies

- Depends on: None (independent of Tasks 01–03)
- Blocks: Nothing
