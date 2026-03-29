#!/usr/bin/env bash
# token-reducer-nudge.sh — One-time nudge for users who haven't installed the Token Reducer Pack.
# Installed as a UserPromptSubmit hook. Shows a message once, then never again.

MARKER="$HOME/.claude/.token-reducer-nudged"

# Already nudged — exit silently
[ -f "$MARKER" ] && exit 0

# Already have RTK + deny rules — mark as done, exit silently
if command -v rtk &>/dev/null && [ -f "$HOME/.claude/settings.json" ] && grep -q 'Read(\*\*/node_modules/\*\*)' "$HOME/.claude/settings.json" 2>/dev/null; then
  touch "$MARKER"
  exit 0
fi

# Show nudge and mark as done (one-time only)
touch "$MARKER"

echo "Tip: The Token Reducer Pack can cut your token usage by 60-90%."
echo "It installs RTK (compresses Bash output) and global deny rules (blocks build artifacts, lock files, caches)."
echo ""
echo "Install it with:"
echo "  bash <(curl -fsSL https://raw.githubusercontent.com/nickmaglowsch/claude-setup/main/setup.sh) --token-reducer"
