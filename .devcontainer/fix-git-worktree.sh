#!/usr/bin/env bash
# Fix git worktree .git file paths inside a devcontainer.
#
# When a git worktree is opened in a devcontainer, the .git file contains
# an absolute host path (e.g. /Users/nick/project/.git/worktrees/feature-a)
# that doesn't exist inside the container. This script rewrites it to the
# equivalent container path under /workspaces/.
#
# Called automatically via postCreateCommand in devcontainer.json.

set -euo pipefail

GIT_FILE=".git"

# Not a worktree — nothing to do
[ -f "$GIT_FILE" ] || exit 0

GITDIR=$(sed 's/^gitdir: //' "$GIT_FILE")

# Already accessible — nothing to do
[ -d "$GITDIR" ] && exit 0

# Derive the container path from the host path structure:
#   host:  /host/path/to/main-repo/.git/worktrees/<name>
#   cont:  /workspaces/main-repo/.git/worktrees/<name>
WORKTREE_NAME=$(basename "$GITDIR")
MAIN_REPO_NAME=$(basename "$(dirname "$(dirname "$(dirname "$GITDIR")")")")
CONTAINER_GITDIR="/workspaces/$MAIN_REPO_NAME/.git/worktrees/$WORKTREE_NAME"

if [ -d "$CONTAINER_GITDIR" ]; then
  echo "gitdir: $CONTAINER_GITDIR" > "$GIT_FILE"
  echo "Fixed git worktree reference -> $CONTAINER_GITDIR"
else
  cat >&2 <<EOF
Warning: could not fix git worktree reference.
  Expected container path: $CONTAINER_GITDIR
  Make sure your main repo and worktree share the same parent directory.
  See .devcontainer/README.md for multi-branch setup instructions.
EOF
fi
