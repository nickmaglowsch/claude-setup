---
name: init-claude-setup
description: "Initialize project-level Claude setup (gitignore entries, settings.local.json, optional Playwright MCP) without copying agent/skill files. Use this in projects where agents were installed globally via --global."
argument-hint: ""
---

# Init Claude Setup

You are initializing project-level Claude configuration for this repository. Follow the steps below strictly in order.

## Step 1 — Detect if already fully set up

Check whether `.claude/agents/` exists in the current working directory.

- If it does exist: inform the user that this project already has a full local Claude install and no initialization is needed. Stop here.

## Step 2 — Add .gitignore entries

1. Read `.gitignore` in the project root. If it does not exist, treat it as empty.
2. Ensure the following entries are present (add only the ones that are missing). Group them under a `# .claude` section comment if you are adding any:

```
# .claude
.devcontainer/.env
.claude/settings.local.json
.claude/auth.local.md
.claude-worktrees/
.DS_Store
tasks/
```

3. Do not duplicate any entry that already exists in the file (even if it appears outside a `# .claude` section).
4. If entries were already present, note that and skip.

## Step 3 — Create .claude/settings.local.json

1. Check if `.claude/settings.local.json` exists.
2. If it does not exist, create it with this content:
```json
{
  "permissions": {
    "allow": [],
    "deny": []
  }
}
```
3. If it already exists, skip this step and note it.

## Step 4 — Optional: Playwright MCP

1. Check if `.claude/settings.json` exists.
2. If it does not exist, ask the user:
   - Question: "Add Playwright MCP for browser-based QA (/qa skill)?"
   - Options: Yes / No (default No)
3. If the user answers Yes, create `.claude/settings.json` with:
```json
{
  "mcpServers": {
    "playwright": {
      "command": "npx",
      "args": ["@playwright/mcp@latest"]
    }
  }
}
```
4. If `.claude/settings.json` already exists, skip this step entirely (do not ask, do not overwrite).

## Step 5 — Summary

Print a clear summary of what was done:

```
## Claude project setup complete

- .gitignore: [added N entries / already up to date]
- .claude/settings.local.json: [created / already existed]
- .claude/settings.json (Playwright MCP): [created / skipped / already existed]

### Next steps
- Run `claude login` if you haven't already
- Edit `.claude/settings.local.json` to configure per-project tool permissions
- Agents and skills are available globally via your ~/.claude/ install
```

## Rules
- Never overwrite files that already exist (settings.local.json, settings.json) — only create them if missing
- Never remove existing .gitignore entries — only add missing ones
- Always complete Steps 2 and 3 even if Playwright is declined
