# claude-setup

The Claude Code skills I actually use, so a new machine is one `git clone` away.

Everything here is generic — no BriteCore/work-specific skills, no skills I stopped
reaching for. Paseo-oriented ones are included since that's where most of my agent
work happens.

## Install

```sh
git clone git@github.com:nickmaglowsch/claude-setup.git
cd claude-setup
for d in skills/*/; do n=$(basename "$d"); ln -sfn "$PWD/skills/$n" "$HOME/.claude/skills/$n"; done
```

Symlinks so a `git pull` updates them in place. Swap `ln -sfn` for `cp -R` if you'd
rather have copies.

## Skills

### Paseo

| Skill | What it does | Needs |
|---|---|---|
| `paseo` | Reference for driving Paseo — workspaces, scripts, agents, schedules, heartbeats. | Paseo MCP |
| `paseo-advisor` | One agent as a second opinion on the current task, without delegating the work. | Paseo MCP |
| `paseo-committee` | Two high-reasoning agents do root-cause analysis and return a plan. | Paseo MCP |
| `paseo-handoff` | Hands the current task to another agent with full context. | Paseo MCP |
| `paseo-loop` | Runs an agent loop until an exit condition is met. | Paseo MCP |
| `paseo-help` | Answers questions about the Paseo app itself — setup, providers, troubleshooting. | — |

### Delegation / routing

| Skill | What it does | Needs |
|---|---|---|
| `delegation-setup` | Templates the think-before-handoff `DELEGATION.md` into `~/.claude` and generates `~/.paseo/orchestration-preferences.json` from the *live* model list. | Paseo (optional) |
| `delegation-audit` | Offline transcript scan for misroutes, turn-budget blowouts, and the costliest agents; proposes edits to the policy. | — |

Vendored from [nickmaglowsch/claude-delegation-routing](https://github.com/nickmaglowsch/claude-delegation-routing),
with `${CLAUDE_PLUGIN_ROOT}` paths repointed at `~/.claude/skills/...`. If you'd rather
track upstream, install the plugin instead and drop these two.

### Git & PRs

| Skill | What it does | Needs |
|---|---|---|
| `rebase-develop` | Rebases onto `origin/develop`, auto-resolves the trivial conflicts, summarises the rest. Never pushes unasked. | git |
| `ci-fix-loop` | Pulls failing CI logs, reproduces locally, fixes the root cause, verifies before offering to push. | `gh` |
| `pr-review-feedback` | Triages a reviewer's line-level comments and fixes the ones that hold up. No commits, no GitHub replies. | `gh` |

### Writing & output

| Skill | What it does | Needs |
|---|---|---|
| `human-reply` | Drafts replies in my voice — short, direct, no AI tells. | — |
| `visual-plan` | Turns an existing plan into a shareable HTML page with editable Excalidraw diagrams. | — |
| `web-artifacts-builder` | Multi-component claude.ai artifacts with React / Tailwind / shadcn. | — |
| `publish-artifact` | Publishes a local HTML file as a claude.ai artifact from a session with no Artifact tool. | Paseo, `claude` CLI |

### Recall & search

| Skill | What it does | Needs |
|---|---|---|
| `ccc` | Semantic code search over an indexed codebase. | `cocoindex-code` |
| `meeting-recall` | Answers questions about past meetings from the local Meetily transcript DB. | Meetily |

## Layout

Plain `skills/<name>/SKILL.md` — no installer, no plugin manifest. Skills are portable
across Claude Code, the Agent SDK, and anything else that reads `SKILL.md`.
