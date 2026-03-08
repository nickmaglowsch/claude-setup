#!/usr/bin/env bash
# auto-update.sh — Background auto-updater for claude-setup.
#
# Installed at ~/.claude/auto-update.sh and run via cron every 5 minutes.
# Checks if the remote main branch has new commits; if so, pulls and applies
# the update silently, then sends a system notification.
#
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

# --- Save new SHA ---
echo "$remote_sha" > "$SHA_FILE"

# --- Notify ---
_notify "Agents and skills updated to ${remote_sha:0:7}"
