#!/usr/bin/env bash
# run-claude.sh — Spawn an isolated Claude Code container on a specific branch
#
# Usage: ./run-claude.sh --branch <branch> --prompt "task description" [options]
#
#   --branch <name>       Git branch to work on (required)
#   --prompt <text>       Prompt/task for Claude (required)
#   --project-dir <path>  Target project directory (default: current dir)
#   --firewall            Enable network firewall
#   --name <name>         Container name (default: claude-<branch>)
#   --cleanup             Remove worktree after container exits

set -euo pipefail

# --- Defaults ---
BRANCH=""
PROMPT=""
PROJECT_DIR="$(pwd)"
FIREWALL=false
CONTAINER_NAME=""
CLEANUP=false
IMAGE_NAME="claude-dev"

# --- Parse arguments ---
while [[ $# -gt 0 ]]; do
  case $1 in
    --branch)
      BRANCH="$2"
      shift 2
      ;;
    --prompt)
      PROMPT="$2"
      shift 2
      ;;
    --project-dir)
      PROJECT_DIR="$2"
      shift 2
      ;;
    --firewall)
      FIREWALL=true
      shift
      ;;
    --name)
      CONTAINER_NAME="$2"
      shift 2
      ;;
    --cleanup)
      CLEANUP=true
      shift
      ;;
    -h|--help)
      head -12 "$0" | tail -10
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

# --- Validate required arguments ---
if [ -z "$BRANCH" ]; then
  echo "Error: --branch is required" >&2
  exit 1
fi

if [ -z "$PROMPT" ]; then
  echo "Error: --prompt is required" >&2
  exit 1
fi

if [ -z "$CONTAINER_NAME" ]; then
  # Sanitize branch name for container naming
  CONTAINER_NAME="claude-$(echo "$BRANCH" | tr '/' '-' | tr -cd '[:alnum:]-')"
fi

PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
WORKTREE_DIR="$PROJECT_DIR/.claude-worktrees/$BRANCH"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# --- Check prerequisites ---
if ! command -v docker &>/dev/null; then
  echo "Error: docker is not installed" >&2
  exit 1
fi

if ! git -C "$PROJECT_DIR" rev-parse --git-dir &>/dev/null; then
  echo "Error: $PROJECT_DIR is not a git repository" >&2
  exit 1
fi

# Resolve host Claude config directory (for mounting login credentials)
HOST_CLAUDE_DIR="${HOME}/.claude"
if [ ! -d "$HOST_CLAUDE_DIR" ]; then
  echo "Warning: ~/.claude not found. Run 'claude login' on the host first to authenticate." >&2
  echo "  (Or set ANTHROPIC_API_KEY env var as a fallback for CI/automation)" >&2
fi

# --- Create worktree ---
echo "Setting up worktree for branch '$BRANCH'..."
mkdir -p "$(dirname "$WORKTREE_DIR")"

if [ -d "$WORKTREE_DIR" ]; then
  echo "  Worktree already exists at $WORKTREE_DIR"
else
  # Check if branch exists remotely or locally
  if git -C "$PROJECT_DIR" show-ref --verify --quiet "refs/heads/$BRANCH" 2>/dev/null; then
    git -C "$PROJECT_DIR" worktree add "$WORKTREE_DIR" "$BRANCH"
  elif git -C "$PROJECT_DIR" show-ref --verify --quiet "refs/remotes/origin/$BRANCH" 2>/dev/null; then
    git -C "$PROJECT_DIR" worktree add "$WORKTREE_DIR" --track "origin/$BRANCH"
  else
    echo "  Branch '$BRANCH' does not exist, creating from HEAD..."
    git -C "$PROJECT_DIR" worktree add -b "$BRANCH" "$WORKTREE_DIR"
  fi
  echo "  Created worktree at $WORKTREE_DIR"
fi

# --- Build image (if needed) ---
DOCKERFILE_DIR="$SCRIPT_DIR/.devcontainer"
if [ ! -f "$DOCKERFILE_DIR/Dockerfile" ]; then
  # If running from a target repo that used setup.sh, look in standard location
  DOCKERFILE_DIR="$PROJECT_DIR/.devcontainer"
fi

if [ ! -f "$DOCKERFILE_DIR/Dockerfile" ]; then
  echo "Error: Cannot find .devcontainer/Dockerfile" >&2
  exit 1
fi

echo "Building container image '$IMAGE_NAME'..."
docker build -t "$IMAGE_NAME" "$DOCKERFILE_DIR" -q

# --- Run container ---
echo "Starting container '$CONTAINER_NAME'..."

DOCKER_ARGS=(
  run
  --rm
  --name "$CONTAINER_NAME"
  -v "$WORKTREE_DIR:/workspace"
  -w /workspace
)

# Mount host Claude credentials (login session from 'claude login')
if [ -d "$HOST_CLAUDE_DIR" ]; then
  DOCKER_ARGS+=(-v "$HOST_CLAUDE_DIR:/home/vscode/.claude:ro")
fi

# Pass API key if set (fallback for CI/automation)
if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
  DOCKER_ARGS+=(-e "ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY")
fi

if [ "$FIREWALL" = true ]; then
  DOCKER_ARGS+=(
    --cap-add=NET_ADMIN
    --cap-add=NET_RAW
  )
fi

# Build the command to run inside the container
INNER_CMD=""
if [ "$FIREWALL" = true ]; then
  INNER_CMD="/usr/local/bin/init-firewall.sh && "
fi
INNER_CMD+="claude --dangerously-skip-permissions \"$PROMPT\""

DOCKER_ARGS+=(
  "$IMAGE_NAME"
  bash -c "$INNER_CMD"
)

docker "${DOCKER_ARGS[@]}"

# --- Cleanup ---
if [ "$CLEANUP" = true ]; then
  echo "Cleaning up worktree..."
  git -C "$PROJECT_DIR" worktree remove "$WORKTREE_DIR" --force 2>/dev/null || true
  echo "  Removed worktree at $WORKTREE_DIR"
fi

echo "Done."
