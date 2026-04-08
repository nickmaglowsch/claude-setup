#!/usr/bin/env bash
# token-reducer-nudge.sh — One-time nudges for Token Reducer Pack tiers.
# Installed as a UserPromptSubmit hook. Each nudge fires once via separate markers.

MARKER="$HOME/.claude/.token-reducer-nudged"
TIER3_MARKER="$HOME/.claude/.context-mode-nudged"
SETTINGS="$HOME/.claude/settings.json"
CLAUDE_JSON="$HOME/.claude.json"

has_deny_rules() {
  [ -f "$SETTINGS" ] && grep -q 'Read(\*\*/node_modules/\*\*)' "$SETTINGS" 2>/dev/null
}
has_rtk() { command -v rtk &>/dev/null; }
has_context_mode() {
  { [ -f "$CLAUDE_JSON" ] && grep -q '"context-mode"' "$CLAUDE_JSON" 2>/dev/null; } || \
  { [ -f "$SETTINGS" ] && grep -q '"context-mode"' "$SETTINGS" 2>/dev/null; }
}

# --- Nudge 1: No token reducer at all → show full 3-tier overview ---
if [ ! -f "$MARKER" ]; then
  # Already have RTK + deny rules — mark as done, skip to Tier 3 check
  if has_rtk && has_deny_rules; then
    touch "$MARKER"
  else
    touch "$MARKER"
    echo "Tip: The Token Reducer Pack can cut your token usage by 60-90%."
    echo "Three tiers available:"
    echo "  Tier 1 — Deny rules: blocks build artifacts, lock files, caches (zero overhead)"
    echo "  Tier 2 — RTK: compresses Bash tool output (70-90% savings)"
    echo "  Tier 3 — context-mode: sandbox execution + FTS5 knowledge base (98% on large outputs)"
    echo ""
    echo "Install it with:"
    echo "  bash <(curl -fsSL https://raw.githubusercontent.com/nickmaglowsch/claude-setup/main/setup.sh) --token-reducer"
    exit 0
  fi
fi

# --- Nudge 2: Has Tier 1+2 but not Tier 3 → suggest context-mode ---
if [ ! -f "$TIER3_MARKER" ]; then
  if has_context_mode; then
    # Already configured — mark as done silently
    touch "$TIER3_MARKER"
    exit 0
  fi
  if has_rtk || has_deny_rules; then
    touch "$TIER3_MARKER"
    echo "Tip: Tier 3 of the Token Reducer Pack is now available — context-mode."
    echo "  Sandbox execution, FTS5 knowledge base, and session continuity."
    echo "  Keeps raw data out of context — 98% reduction on large outputs."
    echo ""
    echo "Add it with:"
    echo "  bash <(curl -fsSL https://raw.githubusercontent.com/nickmaglowsch/claude-setup/main/setup.sh) --token-reducer"
    echo "  (choose option 3 for all tiers)"
    exit 0
  fi
  touch "$TIER3_MARKER"
fi
