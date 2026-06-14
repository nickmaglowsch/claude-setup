#!/usr/bin/env bash
# SessionStart self-heal: make sure the Codex CLI is available.
#
# Wired into ~/.claude/settings.json as a SessionStart hook so users who install
# claude-setup via the plugin marketplace (and never run setup.sh) still get Codex
# bootstrapped for the cross-model review / rescue steps.
#
# Runs on every session, so it must be a fast no-op when Codex is already present.
# All status output goes to stderr (SessionStart stdout is injected into context).
# Never blocks a session: always exits 0.

# --- Sync the review helper into ~/.claude/scripts/ (plugin-marketplace path) ---
# When run as a bundled plugin hook, $CLAUDE_PLUGIN_ROOT points at the plugin root.
# The skills look for the helper at ~/.claude/scripts/codex-review.sh, so copy it
# there if it's missing. Cheap + idempotent; setup.sh installs already have it and
# leave $CLAUDE_PLUGIN_ROOT unset, so this block is a no-op for them.
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/codex-review.sh" ] && [ ! -f "$HOME/.claude/scripts/codex-review.sh" ]; then
  mkdir -p "$HOME/.claude/scripts"
  cp "${CLAUDE_PLUGIN_ROOT}/scripts/codex-review.sh" "$HOME/.claude/scripts/codex-review.sh" 2>/dev/null \
    && chmod +x "$HOME/.claude/scripts/codex-review.sh" 2>/dev/null || true
fi

# Fast path: Codex already installed — exit immediately, no output.
if command -v codex >/dev/null 2>&1; then
  exit 0
fi

if command -v npm >/dev/null 2>&1; then
  echo "[ensure-codex] Codex CLI not found — installing @openai/codex globally..." >&2
  if npm install -g @openai/codex >/dev/null 2>&1; then
    echo "[ensure-codex] Codex installed. Run 'codex login' to authenticate with your ChatGPT subscription." >&2
  else
    echo "[ensure-codex] Codex install failed — install manually: npm install -g @openai/codex" >&2
  fi
else
  echo "[ensure-codex] Codex CLI missing and npm unavailable — install Node/npm, then run: npm install -g @openai/codex" >&2
fi

exit 0
