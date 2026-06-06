#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PLUGIN_DIR="$REPO_ROOT/plugins/claude-setup"

if [ ! -d "$REPO_ROOT/.claude/skills" ] || [ ! -d "$REPO_ROOT/.claude/agents" ]; then
  echo "Expected .claude/skills and .claude/agents under $REPO_ROOT" >&2
  exit 1
fi

mkdir -p "$PLUGIN_DIR/.claude-plugin"
rm -rf "$PLUGIN_DIR/skills" "$PLUGIN_DIR/agents" "$PLUGIN_DIR/references"
mkdir -p "$PLUGIN_DIR/skills" "$PLUGIN_DIR/agents" "$PLUGIN_DIR/references/agents"

cp -R "$REPO_ROOT/.claude/skills/." "$PLUGIN_DIR/skills/"
for agent in "$REPO_ROOT"/.claude/agents/*.md; do
  if [ "$(basename "$agent")" = "tdd-mode.md" ]; then
    cp "$agent" "$PLUGIN_DIR/references/agents/"
  else
    cp "$agent" "$PLUGIN_DIR/agents/"
  fi
done

find "$PLUGIN_DIR/skills" "$PLUGIN_DIR/agents" "$PLUGIN_DIR/references" -type f \( -name '*.md' -o -name '*.json' \) -print0 |
  xargs -0 perl -0pi -e '
    s#\.claude/skills/#skills/#g;
    s#\.claude/agents/#agents/#g;
    s#agents/tdd-mode\.md#references/agents/tdd-mode.md#g;
    s# \(check `~/agents/` for global installs, `agents/` for local\)##g;
    s#check `~/\.claude/agents/` for global installs, `agents/` for local#use the packaged plugin `agents/` directory#g;
    s#Agents and skills are available globally via your ~/\.claude/ install#Agents and skills are available through the installed `claude-setup` plugin#g;
    s#The /qa skill uses#The /claude-setup:qa skill uses#g;
    s#/debug-workflow(?![A-Za-z0-9_/-])#/claude-setup:debug-workflow#g;
    s#/grill-with-docs(?![A-Za-z0-9_/-])#/claude-setup:grill-with-docs#g;
    s#/init-claude-setup(?![A-Za-z0-9_/-])#/claude-setup:init-claude-setup#g;
    s#/refactor-lite(?![A-Za-z0-9_/-])#/claude-setup:refactor-lite#g;
    s#/build-lite(?![A-Za-z0-9_/-])#/claude-setup:build-lite#g;
    s#/craft-pr(?![A-Za-z0-9_/-])#/claude-setup:craft-pr#g;
    s#/grill-me(?![A-Za-z0-9_/-])#/claude-setup:grill-me#g;
    s#/refactor(?![A-Za-z0-9_/-])#/claude-setup:refactor#g;
    s#/build(?![A-Za-z0-9_/-])#/claude-setup:build#g;
    s#/qa(?![A-Za-z0-9_/-])#/claude-setup:qa#g;
  '

echo "Rebuilt $PLUGIN_DIR from .claude sources"
