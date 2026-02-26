# Dev Container for Claude Code

Run Claude Code in an isolated Docker container — interactively via VS Code / Zed or headlessly via CLI.

## Quick Start

1. Install dev container support:
   - **VS Code**: Install the [Dev Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers)
   - **Zed**: Built-in since [v0.218](https://zed.dev/docs/dev-containers) — no extension needed
2. Open this project in your editor
3. Reopen in container:
   - **VS Code**: `Ctrl+Shift+P` → **Dev Containers: Reopen in Container**
   - **Zed**: You'll be prompted automatically when the project has a `devcontainer.json`
4. Open a terminal inside the container and authenticate:
   ```bash
   claude login
   ```
   This opens your browser — log in with your Claude Max (or Pro/Team) subscription. Credentials are persisted in a Docker volume so you only need to do this once per workspace.
5. Start using Claude: `claude`

## Authentication

Claude Code authenticates via your Claude subscription (Max, Pro, Team, or Enterprise) — **no API key needed**.

### Interactive mode (VS Code / Zed)

Run `claude login` inside the container terminal. It opens a browser on your host for OAuth. Credentials are stored in the `~/.claude` volume and persist across container rebuilds.

### Headless mode (run-claude.sh)

The headless script mounts your host's `~/.claude` directory (read-only) into the container, so it inherits your login session automatically. Just make sure you've run `claude login` on the host at least once.

```bash
# Authenticate on host first (one-time)
claude login

# Then run headless containers — they inherit the session
./run-claude.sh --branch feature-x --prompt "implement the feature"
```

### CI / Automation fallback

For CI pipelines where browser login isn't possible, set the `ANTHROPIC_API_KEY` environment variable. The headless script will pass it to the container if present.

## Multi-Instance Workflows

You can run multiple Claude containers simultaneously with no port collisions.

### Using git worktrees
```bash
# Create worktrees for different branches
git worktree add ../my-project-feature-a feature-a
git worktree add ../my-project-feature-b feature-b

# Open each worktree in your editor → "Reopen in Container"
# Each gets isolated volumes (scoped by devcontainerId)
```

### Using multiple clones
```bash
git clone repo my-project-1
git clone repo my-project-2
# Open each in your editor → "Reopen in Container"
```

### VS Code "Clone in Container Volume"
`Ctrl+Shift+P` → **Dev Containers: Clone Repository in Container Volume** — each clone gets a fully isolated Docker volume.

Port collisions are impossible because:
- VS Code/Zed auto-detect listening ports and map them to available host ports
- Each container has its own network namespace
- Claude config/history volumes are scoped per instance via `${devcontainerId}`

## Headless Mode

Use `run-claude.sh` to spawn containers from the command line for batch/automation work:

```bash
# Basic usage
./run-claude.sh --branch feature-x --prompt "implement user authentication"

# With firewall and cleanup
./run-claude.sh --branch fix-bug-42 --prompt "fix the login bug" --firewall --cleanup

# Custom container name
./run-claude.sh --branch main --prompt "run tests" --name claude-test-runner

# Different project directory
./run-claude.sh --branch main --prompt "refactor API" --project-dir /path/to/project
```

### Options
| Flag | Description | Default |
|------|-------------|---------|
| `--branch <name>` | Git branch to work on | *required* |
| `--prompt <text>` | Task for Claude | *required* |
| `--project-dir <path>` | Target project | current dir |
| `--firewall` | Enable network firewall | off |
| `--name <name>` | Container name | `claude-<branch>` |
| `--cleanup` | Remove worktree after exit | off |

### Running multiple tasks in parallel
```bash
./run-claude.sh --branch feature-a --prompt "implement feature A" &
./run-claude.sh --branch feature-b --prompt "implement feature B" &
./run-claude.sh --branch fix-bug --prompt "fix the login bug" &
wait
```

Each container runs in its own worktree and network namespace — zero conflicts.

## Enabling the Firewall

The firewall restricts outbound network to only the services Claude needs (API, GitHub, npm, VS Code marketplace). This is useful when running `claude --dangerously-skip-permissions` for unattended operation.

### Interactive mode
Edit `.devcontainer/devcontainer.json` and uncomment:
```jsonc
"postStartCommand": "sudo /usr/local/bin/init-firewall.sh"
```
Then rebuild the container:
- **VS Code**: `Ctrl+Shift+P` → **Dev Containers: Rebuild Container**
- **Zed**: Re-open the project to trigger a rebuild

### Headless mode
```bash
./run-claude.sh --branch main --prompt "task" --firewall
```

### Allowed destinations
- `api.anthropic.com` — Claude API
- `statsig.anthropic.com`, `statsig.com` — telemetry
- `registry.npmjs.org` — npm packages
- GitHub IP ranges — git operations
- `marketplace.visualstudio.com`, `vscode.blob.core.windows.net` — VS Code extensions
- Localhost, DNS — internal communication

## Customizing for Your Project

The base image is a minimal Ubuntu with Claude Code. To add project-specific tools, edit the `Dockerfile`:

### Node.js project
```dockerfile
FROM mcr.microsoft.com/devcontainers/base:ubuntu

# Install Node.js
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs

# ... rest of Dockerfile
```

### Python project
```dockerfile
FROM mcr.microsoft.com/devcontainers/base:ubuntu

RUN apt-get update && apt-get install -y python3 python3-pip python3-venv

# ... rest of Dockerfile
```

Or use dev container Features in `devcontainer.json`:
```jsonc
"features": {
  "ghcr.io/devcontainers/features/git:1": {},
  "ghcr.io/devcontainers/features/node:1": { "version": "20" },
  "ghcr.io/devcontainers/features/python:1": { "version": "3.12" }
}
```

## Integrating with an Existing Dev Container

If your project already has a `.devcontainer/`, merge these key pieces:

```jsonc
// Add to your existing devcontainer.json:
{
  "mounts": [
    "source=claude-config-${devcontainerId},target=/home/vscode/.claude,type=volume",
    "source=claude-history-${devcontainerId},target=/home/vscode/.claude.history,type=volume"
  ],
  "customizations": {
    "vscode": {
      "extensions": [
        "anthropic.claude-code"
      ]
    }
  }
}
```

And add Claude Code to your Dockerfile:
```dockerfile
RUN curl -fsSL https://claude.ai/install.sh | bash
```
