# Refactor Questions

## Code Audit Summary

### What was examined

- `/home/nick/.claude/skills/build/SKILL.md` — the `/build` orchestration skill
- `/home/nick/.claude/skills/refactor/SKILL.md` — the `/refactor` orchestration skill
- `/home/nick/.claude/skills/debug-workflow/SKILL.md` — the `/debug-workflow` skill (same branch creation pattern)
- `/home/nick/.claude/agents/agent-teams-orchestrator.md` — agent teams reference guide
- `/home/nick/.claude/settings.json` — global Claude settings (currently `{ "skipDangerousModePermissionPrompt": true }`)
- `/home/nick/claude-setup/.claude/` — the repo's local copies of all skills and agents

The repo at `/home/nick/claude-setup/` contains source copies of all skills that are installed globally under `/home/nick/.claude/`. Both locations appear to be in sync (same content). Changes need to be made in both places, or in the source repo and then re-deployed.

### Issue 1: Auto-commit branch creation is stale

**Location:** `Step 0.1` in both `build/SKILL.md` and `refactor/SKILL.md` (also `debug-workflow/SKILL.md`).

Current logic (identical in all three skills):
```
1. Run `git rev-parse --abbrev-ref HEAD`. If `main`/`master`: BRANCH_ACTION=new.
2. Ask "Single squash commit or one commit per task?" → COMMIT_MODE
3. Generate feat/<3-5-word-slug> from PRD → AUTO_COMMIT_BRANCH
4. `git checkout -b <AUTO_COMMIT_BRANCH>`. On failure append `-2`, retry once.
```

**Two missing behaviors:**
- No `git fetch origin` before branching — the new branch is cut from whatever local HEAD is, which may be behind origin.
- No question about which branch to base the new branch on — always uses the current local HEAD without asking.

### Issue 2: Orchestration mode is asked every run

**Location:** `Step 0.2` in both `build/SKILL.md` and `refactor/SKILL.md`.

Current logic: always asks `AskUserQuestion` with two options (Default parallel / Agent Teams Beta). There is no mechanism to read a saved user preference or skip the question if a default is already set. No user preferences file of any kind exists — no `~/.claude/user-preferences.json`, no `preferences` key in `settings.json`.

### No existing preferences/settings persistence mechanism

There is no existing user preferences file, no shared config that skills read before asking questions, and no pattern in the codebase for "ask once, save answer" behavior. The `~/.claude/settings.json` is used only for Claude Code env vars and permission flags — it is not currently used for skill-level preferences. The `.claude/agent-memory/` directories exist per-agent, but no skill currently uses them to persist user answers.

### Scope

Three skill files share the same branch creation pattern. Two skills share the orchestration mode question. The agent files (orchestrator, etc.) do not need changes — this is purely a skill-orchestrator concern.

---

## Issues Found

- **Issue 1a** [missing behavior, build/SKILL.md Step 0.1, medium severity]: No `git fetch origin` before `git checkout -b`. Branch is cut from potentially stale local HEAD.
- **Issue 1b** [missing behavior, build/SKILL.md Step 0.1, medium severity]: No question about which base branch to branch from. Always uses current HEAD without letting the user choose.
- **Issue 1c** [duplication, debug-workflow/SKILL.md Step 0.1, low severity]: Same branch creation block exists in `debug-workflow/SKILL.md` — the same fixes would need to apply there too if scope includes it.
- **Issue 2a** [UX friction, build/SKILL.md Step 0.2, medium severity]: Orchestration mode question is asked every single run with no way to save a default.
- **Issue 2b** [duplication, refactor/SKILL.md Step 0.2, medium severity]: Identical orchestration mode question block duplicated in refactor skill — any fix needs to apply to both.
- **Issue 3** [no persistence mechanism, medium severity]: No user preferences file or pattern exists. A storage mechanism needs to be designed and agreed on before either fix can be implemented.

---

## Questions

### Q1: Preferred storage location for user preferences

**Context:** There is no existing preferences file. The two candidate locations are `~/.claude/settings.json` (global, already used by Claude Code for env vars) and a new dedicated file like `~/.claude/user-preferences.json` or `~/.claude/skills/preferences.json`. A third option is storing preferences inside the agent memory system (`.claude/agent-memory/`), but those are per-agent and not currently read by skills. The skills themselves run in the user's project directory, not in `~/.claude/`, so whichever file is chosen must use an absolute path.

**Question:** Where should skill-level user preferences be stored?

**Options:**
- A) New dedicated file: `~/.claude/user-preferences.json` — clean separation, skills read it at startup, easy to inspect/edit manually
- B) Inside `~/.claude/settings.json` under a `skillPreferences` key — keeps everything in one file, but mixes skill config with Claude Code system config
- C) Project-local file (`.claude/preferences.json` in each project) — scoped per-project, allows different defaults per codebase, but doesn't persist across projects

### Q2: Orchestration mode preference — skip question or show with default?

**Context:** The orchestration mode question currently always interrupts the run before any work starts. The goal is to let users avoid this prompt on subsequent runs. There are two ways to accomplish this once a preference is saved.

**Question:** When a saved orchestration mode preference exists, should the skill:

**Options:**
- A) **Skip the question entirely** — read the preference silently, log "Using saved orchestration mode: parallel", proceed immediately (fastest, least friction)
- B) **Show the question but pre-select the saved default** — user still sees the prompt but can change it in this run without changing their saved preference (more discoverable, slightly more friction)

### Q3: Should saving a preference require an explicit action, or auto-save on first answer?

**Context:** The user will answer the orchestration mode question (or any other persistent prompt) during a run. The skill could either auto-save that answer as the new default, or ask "Save this as your default?" after the user answers.

**Question:** How should the preference get saved?

**Options:**
- A) **Auto-save on every answer** — the last answer always becomes the new default, no extra prompt needed
- B) **Ask once: "Save as default?"** — after the user answers, a follow-up offers to save it (opt-in, explicit, more steps)
- C) **Only save if explicitly asked** — the default is never auto-set; the user must run a separate command or edit the file to set a preference

### Q4: Branch base selection — what should the user be asked?

**Context:** Currently, when `AUTO_COMMIT=true` and `BRANCH_ACTION=new`, the skill runs `git checkout -b <branch>` from whatever the local HEAD is. The fix has two parts: (1) fetch from origin before branching to get the latest, and (2) optionally ask which branch to base the new branch on.

For part 2, the key question is what options to offer. `main`/`master` is the most common base. But in some workflows, the user might want to branch from `develop` or from a feature branch they just checked out.

**Question:** When creating a new auto-commit branch, what should happen?

**Options:**
- A) **Always fetch + branch from origin/main (or origin/master)** — no question, just fetch and branch from the canonical base; simplest and safest for most workflows
- B) **Fetch, then ask: "Branch from: (1) main, (2) current branch `<name>`, (3) other"** — gives full control, minimal extra friction
- C) **Fetch + branch from current HEAD** — only adds the fetch (fixes staleness), but does not add a base-branch question; simplest code change

### Q5: Scope — does debug-workflow need the same branch fixes?

**Context:** `debug-workflow/SKILL.md` has the exact same branch creation block (Step 0.1) as `/build` and `/refactor`. It has the same stale-branch problem. However, the user's bug report only mentioned `/build` and `/refactor` explicitly.

**Question:** Should the branch creation fix also be applied to `debug-workflow/SKILL.md`?

**Options:**
- A) Yes — fix all three skills consistently
- B) No — only fix `/build` and `/refactor` as stated, leave debug-workflow for a future pass

### Q6: Deployment — source repo vs. global install

**Context:** The skill files exist in two places: `/home/nick/claude-setup/.claude/skills/` (the source repo) and `/home/nick/.claude/skills/` (the global install that Claude Code actually reads). Currently both are in sync. Any changes need to land in both locations, or a deployment step (`setup.sh` or `auto-update.sh`) needs to be run after editing the source.

**Question:** Should the implementation edit the source repo files only (and the user re-runs setup.sh to deploy), or should it edit both the source and the global install directly?

**Options:**
- A) **Source only** — edit files in `/home/nick/claude-setup/.claude/`, then user runs `setup.sh` or `auto-update.sh` to deploy globally
- B) **Both locations** — edit source repo AND global install in one pass so changes take effect immediately without a separate deploy step
