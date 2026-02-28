#!/usr/bin/env bash
# setup.sh — Copy Claude Code template files into a target repository
#
# Usage: ./setup.sh <target-directory>            # First-time setup (interactive)
#        ./setup.sh --update <target-directory>    # Update existing setup from latest template

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# --- Parse flags ---
UPDATE_MODE=false
TARGET_DIR=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --update|-u)
      UPDATE_MODE=true
      shift
      ;;
    -h|--help)
      head -5 "$0" | tail -3
      exit 0
      ;;
    *)
      TARGET_DIR="$1"
      shift
      ;;
  esac
done

if [ -z "$TARGET_DIR" ]; then
  echo "Usage: $0 [--update] <target-directory>"
  exit 1
fi

if [ ! -d "$TARGET_DIR" ]; then
  echo "Error: '$TARGET_DIR' does not exist or is not a directory" >&2
  exit 1
fi

TARGET_DIR="$(cd "$TARGET_DIR" && pwd)"

if ! git -C "$TARGET_DIR" rev-parse --git-dir &>/dev/null; then
  echo "Warning: '$TARGET_DIR' is not a git repository."
  read -rp "Continue anyway? [y/N] " confirm
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
  fi
fi

# --- Core template files (agents, skills, settings) ---
CLAUDE_FILES=(
  ".claude/README.md"
  ".claude/settings.local.json"
  ".claude/agents/code-reviewer.md"
  ".claude/agents/parallel-task-orchestrator.md"
  ".claude/agents/prd-task-planner.md"
  ".claude/agents/task-implementer.md"
  ".claude/skills/build/SKILL.md"
  ".claude/skills/craft-pr/SKILL.md"
)

DEVCONTAINER_FILES=(
  ".devcontainer/Dockerfile"
  ".devcontainer/devcontainer.json"
  ".devcontainer/init-firewall.sh"
  ".devcontainer/README.md"
)

# --- Helper: copy file with overwrite prompt ---
copy_file() {
  local src="$1"
  local dest="$2"

  if [ -f "$dest" ]; then
    read -rp "  File exists: ${dest#"$TARGET_DIR"/} — overwrite? [y/N] " overwrite
    if [[ ! "$overwrite" =~ ^[Yy]$ ]]; then
      echo "  Skipped."
      return
    fi
  fi

  mkdir -p "$(dirname "$dest")"
  cp "$src" "$dest"
  echo "  Copied: ${dest#"$TARGET_DIR"/}"
}

# --- Helper: force-copy file (no prompt) ---
force_copy_file() {
  local src="$1"
  local dest="$2"

  mkdir -p "$(dirname "$dest")"
  cp "$src" "$dest"
  echo "  Updated: ${dest#"$TARGET_DIR"/}"
}

# ===========================================================================
# UPDATE MODE
# ===========================================================================
if [ "$UPDATE_MODE" = true ]; then
  # Verify target already has a Claude setup
  if [ ! -d "$TARGET_DIR/.claude/agents" ]; then
    echo "Error: '$TARGET_DIR' does not have an existing Claude setup (.claude/agents/ not found)." >&2
    echo "Run without --update for first-time setup." >&2
    exit 1
  fi

  echo "Updating Claude Code setup in: $TARGET_DIR"
  echo ""

  # Pull latest template if this is a git repo
  if git -C "$SCRIPT_DIR" rev-parse --git-dir &>/dev/null; then
    echo "=== Pulling latest template ==="
    git -C "$SCRIPT_DIR" pull --ff-only 2>&1 | sed 's/^/  /'
    echo ""
  else
    echo "Warning: Template directory is not a git repo, using files as-is."
    echo ""
  fi

  # Update core .claude/ files (skip settings.local.json to preserve user config)
  echo "=== Updating: .claude/ agents, skills ==="
  echo ""

  for file in "${CLAUDE_FILES[@]}"; do
    # Skip settings — the user has likely customized these
    if [[ "$file" == *"settings.local.json"* ]]; then
      echo "  Skipped: $file (preserving local settings)"
      continue
    fi

    if [ -f "$SCRIPT_DIR/$file" ]; then
      force_copy_file "$SCRIPT_DIR/$file" "$TARGET_DIR/$file"
    fi
  done

  echo ""

  # Update devcontainer if it already exists in target
  if [ -d "$TARGET_DIR/.devcontainer" ]; then
    echo "=== Updating: .devcontainer/ ==="
    echo ""

    for file in "${DEVCONTAINER_FILES[@]}"; do
      if [ -f "$SCRIPT_DIR/$file" ]; then
        force_copy_file "$SCRIPT_DIR/$file" "$TARGET_DIR/$file"
      fi
    done

    chmod +x "$TARGET_DIR/.devcontainer/init-firewall.sh" 2>/dev/null || true
    echo ""
  fi

  # Update run-claude.sh if it already exists in target
  if [ -f "$TARGET_DIR/run-claude.sh" ]; then
    echo "=== Updating: run-claude.sh ==="
    echo ""
    force_copy_file "$SCRIPT_DIR/run-claude.sh" "$TARGET_DIR/run-claude.sh"
    chmod +x "$TARGET_DIR/run-claude.sh" 2>/dev/null || true
    echo ""
  fi

  echo "=== Update complete! ==="
  echo ""
  echo "  Updated template files. Your settings.local.json and agent-memory/ were preserved."
  echo "  Review the changes with: cd $TARGET_DIR && git diff"
  echo ""
  exit 0
fi

# ===========================================================================
# FIRST-TIME SETUP (original behavior)
# ===========================================================================
echo "Setting up Claude Code in: $TARGET_DIR"
echo ""

# --- Step 1: Core .claude/ files (always) ---
echo "=== Core: .claude/ agents, skills, settings ==="
echo ""

for file in "${CLAUDE_FILES[@]}"; do
  copy_file "$SCRIPT_DIR/$file" "$TARGET_DIR/$file"
done

echo ""

# --- Step 2: Dev container (optional) ---
read -rp "Do you want dev container support? [y/N] " install_devcontainer
echo ""

if [[ "$install_devcontainer" =~ ^[Yy]$ ]]; then
  echo "=== Dev Container: .devcontainer/ ==="
  echo ""

  for file in "${DEVCONTAINER_FILES[@]}"; do
    copy_file "$SCRIPT_DIR/$file" "$TARGET_DIR/$file"
  done

  # Make firewall script executable
  chmod +x "$TARGET_DIR/.devcontainer/init-firewall.sh" 2>/dev/null || true

  echo ""

  # --- Step 3: Headless runner (optional, only if devcontainer selected) ---
  read -rp "Include headless runner script (run-claude.sh)? [y/N] " install_runner
  echo ""

  if [[ "$install_runner" =~ ^[Yy]$ ]]; then
    echo "=== Headless Runner: run-claude.sh ==="
    echo ""
    copy_file "$SCRIPT_DIR/run-claude.sh" "$TARGET_DIR/run-claude.sh"
    chmod +x "$TARGET_DIR/run-claude.sh" 2>/dev/null || true
    echo ""
  fi
fi

# --- Step 4: Update .gitignore ---
echo "=== Updating .gitignore ==="
echo ""

GITIGNORE_ENTRIES=(
  ".devcontainer/.env"
  ".claude-worktrees/"
  ".DS_Store"
)

GITIGNORE_FILE="$TARGET_DIR/.gitignore"
touch "$GITIGNORE_FILE"

for entry in "${GITIGNORE_ENTRIES[@]}"; do
  if ! grep -qxF "$entry" "$GITIGNORE_FILE" 2>/dev/null; then
    echo "$entry" >> "$GITIGNORE_FILE"
    echo "  Added to .gitignore: $entry"
  else
    echo "  Already in .gitignore: $entry"
  fi
done

echo ""

# --- Done ---
echo "=== Setup complete! ==="
echo ""
echo "Next steps:"
echo "  1. Authenticate:      claude login  (uses your Max/Pro subscription)"
echo "  2. Review .claude/settings.local.json and adjust permissions"
echo "  3. Run Claude Code:   claude"
echo ""
if [[ "${install_devcontainer:-}" =~ ^[Yy]$ ]]; then
  echo "  Dev container:"
  echo "    - VS Code: open the project, then 'Reopen in Container'"
  echo "    - Zed: open the project, you'll be prompted to launch in a container"
  echo "    - Run 'claude login' inside the container to authenticate"
  echo "    - See .devcontainer/README.md for full documentation"
  echo ""
fi
if [[ "${install_runner:-}" =~ ^[Yy]$ ]]; then
  echo "  Headless mode:"
  echo "    ./run-claude.sh --branch feature-x --prompt 'implement the feature'"
  echo ""
fi
