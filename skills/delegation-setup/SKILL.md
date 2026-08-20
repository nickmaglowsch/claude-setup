---
name: delegation-setup
description: One-time setup for deliberate model routing — template a think-before-handoff DELEGATION.md into ~/.claude (with the global CLAUDE.md @-include) and, if Paseo is available, generate ~/.paseo/orchestration-preferences.json from the LIVE model list instead of hardcoded IDs. Use when the user says "set up delegation routing", "install the delegation policy", "delegation setup", or right after installing the delegation-routing plugin.
---

# Delegation Setup

Templates the routing policy into place. Nothing here ships frozen model IDs — bindings are generated from what your providers expose right now. Ask before overwriting anything that already exists.

## Step 1: Install the policy file

Copy `~/.claude/skills/delegation-setup/templates/DELEGATION.template.md` to `~/.claude/DELEGATION.md`. If the destination already exists and differs, show a diff and ask before replacing.

Then ensure `~/.claude/CLAUDE.md` contains a line `@DELEGATION.md` (append it if missing; create the file if absent). This puts the think-before-handoff rule in context every session.

## Step 2: Generate Paseo bindings (skip cleanly if no Paseo)

Check whether the Paseo MCP server is available (ToolSearch for `mcp__paseo__list_models`). If not, say so — the DELEGATION.md policy still governs native Agent/Workflow fan-out — and go to Step 4.

If available:

1. Call `mcp__paseo__list_providers`, then `mcp__paseo__list_models` for each enabled provider.
2. Map tiers per family from the live list (do NOT invent IDs):
   - frontier = the top/most-capable model, workhorse = the default/everyday strong model, cheap = the smallest.
3. Ask the user (AskUserQuestion) only what genuinely varies: which family is the implementation workhorse, and which is the contrarian reviewer. Default suggestion: Claude implements, OpenAI-family reviews/challenges.
4. Fill every `<placeholder>` in `~/.claude/skills/delegation-setup/templates/orchestration-preferences.template.json` with the chosen live IDs, drop the `_comment` key, and write `~/.paseo/orchestration-preferences.json`. If the file already exists, show a diff and ask before replacing.
5. Validate: `python3 -m json.tool ~/.paseo/orchestration-preferences.json`.

## Step 3: Smoke-test (optional, ask first)

Offer to create one throwaway Paseo agent with a bound provider string to prove the format is accepted, then archive it immediately.

## Step 4: Wrap up

Tell the user: open a NEW session (the @-include loads at startup), and schedule the refinement loop — `/loop 2w /delegation-audit`. Bindings drift as models ship; the audit's drift check proposes rebindings.

## Rules

- Never overwrite an existing file without showing a diff and getting an explicit OK.
- Never write a model ID that didn't come from `list_models` output.
- If a provider family is missing (e.g. no Codex), bind all roles within the available family and note that cross-family review is unavailable.
