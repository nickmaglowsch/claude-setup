#!/usr/bin/env bash
# auto-update.sh — Background auto-updater for claude-setup.
#
# Installed at ~/.claude/auto-update.sh and run via cron at a configurable
# interval (default: every 5 minutes). The interval is set during setup or
# with: ./setup.sh --interval <value>  (e.g. 5m, 30m, 1h, 6h, 1d)
# Config is stored in ~/.claude/auto-update.conf
#
# To change interval: re-run setup.sh --interval <value>
# To disable: crontab -e  →  remove the line containing auto-update.sh

set -euo pipefail

REPO_URL="https://github.com/nickmaglowsch/claude-setup.git"
CLONE_DIR="/tmp/claude-setup"
SHA_FILE="$HOME/.claude/.last-update-sha"
LOG_FILE="$HOME/.claude/auto-update.log"

# Keep log from growing unbounded (keep last 500 lines)
if [ -f "$LOG_FILE" ] && [ "$(wc -l < "$LOG_FILE")" -gt 500 ]; then
  tail -n 500 "$LOG_FILE" > "${LOG_FILE}.tmp" && mv "${LOG_FILE}.tmp" "$LOG_FILE"
fi

_log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE"
}

# --- Cross-platform notification ---
_notify() {
  local msg="$1"
  local title="claude-setup"

  if [[ "$(uname -s)" == "Darwin" ]]; then
    osascript -e "display notification \"$msg\" with title \"$title\"" 2>/dev/null || true
  elif grep -qi microsoft /proc/version 2>/dev/null; then
    # WSL — Windows balloon tip via PowerShell
    powershell.exe -WindowStyle Hidden -Command "
      Add-Type -AssemblyName System.Windows.Forms
      \$n = New-Object System.Windows.Forms.NotifyIcon
      \$n.Icon = [System.Drawing.SystemIcons]::Information
      \$n.BalloonTipTitle = '$title'
      \$n.BalloonTipText = '$msg'
      \$n.Visible = \$true
      \$n.ShowBalloonTip(5000)
      Start-Sleep -Seconds 6
      \$n.Dispose()
    " 2>/dev/null || true
  elif command -v notify-send &>/dev/null; then
    notify-send "$title" "$msg" 2>/dev/null || true
  fi
  # Always write to log regardless of notification support
  _log "[UPDATE] $msg"
}

# --- Check remote SHA (lightweight — no clone needed) ---
remote_sha=$(git ls-remote "$REPO_URL" HEAD 2>/dev/null | cut -f1) || true
if [ -z "$remote_sha" ]; then
  _log "[SKIP] Could not reach remote (no network?)"
  exit 0
fi

# --- Compare to last applied SHA ---
last_sha=$(cat "$SHA_FILE" 2>/dev/null || echo "")
if [ "$remote_sha" = "$last_sha" ]; then
  exit 0  # already up to date, exit silently
fi

_log "[START] New commit detected: ${remote_sha:0:7} (was ${last_sha:0:7})"

# --- Pull or clone ---
if [ -d "$CLONE_DIR/.git" ]; then
  git -C "$CLONE_DIR" fetch --depth 1 origin main 2>>"$LOG_FILE"
  git -C "$CLONE_DIR" reset --hard origin/main 2>>"$LOG_FILE"
else
  git clone --depth 1 "$REPO_URL" "$CLONE_DIR" 2>>"$LOG_FILE"
fi

# --- Copy agent and skill files ---
CLAUDE_FILES=(
  ".claude/README.md"
  ".claude/agents/app-scout.md"
  ".claude/agents/bug-fixer.md"
  ".claude/agents/bug-investigator.md"
  ".claude/agents/code-reviewer.md"
  ".claude/agents/parallel-task-orchestrator.md"
  ".claude/agents/prd-task-planner.md"
  ".claude/agents/qa-agent.md"
  ".claude/agents/refactor-planner.md"
  ".claude/agents/task-implementer.md"
  ".claude/agents/test-writer.md"
  ".claude/skills/build/SKILL.md"
  ".claude/skills/craft-pr/SKILL.md"
  ".claude/skills/debug-workflow/SKILL.md"
  ".claude/skills/init-claude-setup/SKILL.md"
  ".claude/skills/qa/SKILL.md"
  ".claude/skills/refactor/SKILL.md"
)

for file in "${CLAUDE_FILES[@]}"; do
  src="$CLONE_DIR/$file"
  dest="$HOME/$file"
  if [ -f "$src" ]; then
    mkdir -p "$(dirname "$dest")"
    cp "$src" "$dest"
  fi
done

# Self-update: refresh this script too
if [ -f "$CLONE_DIR/auto-update.sh" ]; then
  cp "$CLONE_DIR/auto-update.sh" "$HOME/.claude/auto-update.sh"
  chmod +x "$HOME/.claude/auto-update.sh"
fi

# --- Token Reducer ---
# Tier 2: RTK
if command -v rtk &>/dev/null; then
  # RTK installed: refresh hook, mark as nudged (no need to nudge)
  rtk init -g --auto-patch >>"$LOG_FILE" 2>&1 || true
  touch "$HOME/.claude/.token-reducer-nudged"
elif [ ! -f "$HOME/.claude/.token-reducer-nudged" ]; then
  # RTK not installed and not yet nudged: register the one-time nudge hook
  hook_src="$CLONE_DIR/.claude/hooks/token-reducer-nudge.sh"
  hook_dest="$HOME/.claude/hooks/token-reducer-nudge.sh"
  settings_file="$HOME/.claude/settings.json"
  if [ -f "$hook_src" ]; then
    mkdir -p "$HOME/.claude/hooks"
    cp "$hook_src" "$hook_dest"
    chmod +x "$hook_dest"
  fi
  # Register the UserPromptSubmit hook if not already present
  if [ -f "$settings_file" ] && ! grep -q 'token-reducer-nudge' "$settings_file" 2>/dev/null; then
    merged=$(python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
hooks = data.setdefault('hooks', {})
ups = hooks.setdefault('UserPromptSubmit', [])
for entry in ups:
    for h in entry.get('hooks', []):
        if 'token-reducer-nudge' in h.get('command', ''):
            print(json.dumps(data, indent=2))
            sys.exit(0)
ups.append({
    'matcher': '',
    'hooks': [{'type': 'command', 'command': 'bash ~/.claude/hooks/token-reducer-nudge.sh'}]
})
print(json.dumps(data, indent=2))
" "$settings_file" 2>/dev/null) && echo "$merged" > "$settings_file"
  elif [ ! -f "$settings_file" ]; then
    mkdir -p "$HOME/.claude"
    cat > "$settings_file" <<'HOOK_EOF'
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/token-reducer-nudge.sh"
          }
        ]
      }
    ]
  }
}
HOOK_EOF
  fi
fi

# Tier 3: context-mode
if [ -f "$HOME/.claude/settings.json" ] && grep -q '"context-mode"' "$HOME/.claude/settings.json" 2>/dev/null; then
  # Already configured — just log, npx @latest is self-updating
  _log "[INFO] context-mode MCP server configured (npx @latest — self-updating)"
  touch "$HOME/.claude/.context-mode-nudged"
elif [ ! -f "$HOME/.claude/.context-mode-nudged" ]; then
  # Has RTK or deny rules but no context-mode — register nudge hook for Tier 3
  hook_src="$CLONE_DIR/.claude/hooks/token-reducer-nudge.sh"
  hook_dest="$HOME/.claude/hooks/token-reducer-nudge.sh"
  if [ -f "$hook_src" ]; then
    mkdir -p "$HOME/.claude/hooks"
    cp "$hook_src" "$hook_dest"
    chmod +x "$hook_dest"
  fi
  # Ensure the hook is registered in settings.json (may already be there)
  settings_file="$HOME/.claude/settings.json"
  if [ -f "$settings_file" ] && ! grep -q 'token-reducer-nudge' "$settings_file" 2>/dev/null; then
    merged=$(python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
hooks = data.setdefault('hooks', {})
ups = hooks.setdefault('UserPromptSubmit', [])
for entry in ups:
    for h in entry.get('hooks', []):
        if 'token-reducer-nudge' in h.get('command', ''):
            print(json.dumps(data, indent=2))
            sys.exit(0)
ups.append({
    'matcher': '',
    'hooks': [{'type': 'command', 'command': 'bash ~/.claude/hooks/token-reducer-nudge.sh'}]
})
print(json.dumps(data, indent=2))
" "$settings_file" 2>/dev/null) && echo "$merged" > "$settings_file"
  fi
fi

# --- Save new SHA ---
echo "$remote_sha" > "$SHA_FILE"

# --- Notify ---
_notify "Agents and skills updated to ${remote_sha:0:7}"
