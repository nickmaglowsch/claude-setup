# Claude Code Agent Setup

A template for setting up Claude Code (agents, skills, memory) in any project. Use it to bootstrap a new repo or add Claude to an existing one.

## Creating a New Project

Use this repo as a GitHub template to start a new project with Claude Code pre-configured:

1. Click **"Use this template"** → **"Create a new repository"** on GitHub
2. Clone your new repo and start working:
   ```bash
   git clone git@github.com:you/your-new-project.git
   cd your-new-project
   claude login   # authenticate with your Max/Pro subscription
   claude          # start coding
   ```

Everything is ready out of the box — agents, skills, and settings are already in place. Add your project code and go.

## Adding Claude to an Existing Project

### Option A: One-liner (recommended)

No prior clone needed — just run:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/nickmaglowsch/claude-setup/main/setup.sh) /path/to/your/project
```

The script auto-clones the template repo to `/tmp/claude-setup` if needed, then runs the interactive setup.

The script will:
- Copy `.claude/` (agents, skills, settings) — always included
- Optionally add `.devcontainer/` for containerized development
- Optionally add `run-claude.sh` for headless/automation mode
- Update your `.gitignore` with the right entries

### Updating an existing setup

Pull the latest template improvements into a project that already has Claude set up:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/nickmaglowsch/claude-setup/main/setup.sh) --update /path/to/your/project
```

Or if you already have the repo cloned:

```bash
/tmp/claude-setup/setup.sh --update /path/to/your/project
```

This will:
- Pull the latest changes from the template repo
- Replace all agent and skill files with the latest versions
- Preserve your `settings.local.json` (your custom permissions stay intact)
- Preserve `agent-memory/` (accumulated project knowledge is kept)
- Only update `.devcontainer/` and `run-claude.sh` if they were previously installed

### Option B: Manual copy

If you just want the core Claude Code setup:

```bash
# Copy the .claude directory into your project
cp -r /tmp/claude-setup/.claude/ /path/to/your/project/.claude/

# Optionally copy dev container support
cp -r /tmp/claude-setup/.devcontainer/ /path/to/your/project/.devcontainer/
cp /tmp/claude-setup/run-claude.sh /path/to/your/project/
```

### After setup

```bash
cd /path/to/your/project
claude login    # authenticate with your Max/Pro subscription
claude           # start coding

# Or use the build pipeline with a PRD:
# /build <paste your PRD>
```

Review `.claude/settings.local.json` to adjust permissions for your project.

## Directory Structure

```
.claude/
├── agents/                  # Custom agent definitions
│   ├── prd-task-planner.md      # Analyzes PRDs, explores codebase, generates task files
│   ├── task-implementer.md      # Implements a single task from a task file
│   ├── parallel-task-orchestrator.md  # Executes task files in parallel waves
│   └── code-reviewer.md        # Reviews changes against PRD/spec
├── skills/                  # User-invocable skills (slash commands)
│   ├── build/SKILL.md           # /build — full pipeline: plan → implement → review
│   └── craft-pr/SKILL.md       # /craft-pr — generates PR description from tasks + diff
├── agent-memory/            # Persistent memory per agent (survives across sessions)
└── settings.local.json      # Local Claude Code settings
```

## The Build Pipeline (`/build`)

The `/build` skill orchestrates the full feature implementation lifecycle. Paste a PRD or feature spec and it handles everything.

### How it works

```
PRD → [Plan] → [User Q&A] → [Implement] → [Review] → Done
```

#### Step 1: Two-Phase Planning (with user input)

The planning step is split into **discovery** and **generation** so the planner can ask you questions before committing to a plan.

**Step 1a — Discovery**
The `prd-task-planner` agent explores the codebase and writes `tasks/planning-questions.md` with:
- A summary of what it found in the codebase (architecture, existing features, relevant code)
- 3-8 questions about architectural decisions, scope, and integration choices that would materially change the plan

**Step 1b — User Q&A**
The build orchestrator reads the questions file and presents them to you interactively. You answer each question.

**Step 1c — Generation**
The same planner agent is **resumed** (keeping all its codebase exploration context) with your answers. It then generates:
- `tasks/updated-prd.md` — the PRD refined with codebase context
- `tasks/task-01-*.md`, `task-02-*.md`, ... — ordered, self-contained task files

#### Step 2: Parallel Implementation

The `parallel-task-orchestrator` reads all task files, builds a dependency graph, and spawns `task-implementer` agents in parallel waves.

#### Step 3: Code Review

The `code-reviewer` audits all changes against `tasks/updated-prd.md` and produces a compliance report.

### Usage

```
/build <paste your PRD here>
```

Or reference a file:
```
/build $(cat path/to/prd.md)
```

### Running agents individually

You can also invoke agents directly via the Task tool:

```
# Just plan (discovery + generate in one shot, no Q&A pause)
Task: prd-task-planner — "Here's the PRD: ... Output tasks to tasks/"

# Just implement
Task: parallel-task-orchestrator — "Execute all tasks from tasks/"

# Just review
Task: code-reviewer — "Review changes against tasks/updated-prd.md"
```

When invoked directly (outside `/build`), the `prd-task-planner` runs all phases end-to-end without the Q&A pause. The two-phase flow only activates when the prompt includes `MODE: DISCOVERY` or `MODE: GENERATE`.

## Agent Memory

Each agent has persistent memory in `.claude/agent-memory/<agent-name>/`. Agents record codebase patterns, conventions, and insights they discover. This builds institutional knowledge across sessions — e.g., the planner remembers your project structure so future planning is faster.

## Dev Container (Optional)

Run Claude Code in an isolated Docker container — interactively via VS Code / Zed or headlessly via CLI. Supports running N containers on N branches simultaneously with no port collisions.

```bash
# VS Code / Zed: open the project, then reopen in container
# Authenticate inside the container:
claude login

# Headless: spawn a container on a branch
./run-claude.sh --branch feature-x --prompt "implement the feature"
```

See [`.devcontainer/README.md`](.devcontainer/README.md) for full documentation.
