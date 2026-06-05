# Claude Code Agent Setup

A template for setting up Claude Code (agents, skills, memory) in any project. Use it to bootstrap a new repo or add Claude to an existing one.

**What you get**: a set of specialized agents and slash-command pipelines for common software tasks:

| Pipeline | What it does |
|---|---|
| [`/grill-me`, `/grill-with-docs`](#pre-build-grilling-grill-me-grill-with-docs) | Fuzzy idea → relentless interview → sharpened plan (run before `/build`) |
| [`/build`](#the-build-pipeline-build) | PRD → cheap lite-routing → plan → parallel/direct implementation → diff-scoped code review |
| [`/build-lite`](#lightweight-pipelines-build-lite-refactor-lite) | Feature → plan → approve → implement in one context — no fan-out, review separated |
| [`/debug-workflow`](#the-debug-pipeline-debug-workflow) | Bug report → investigate → diagnose → TDD fix → review |
| [`/refactor`](#the-refactor-pipeline-refactor) | Target → audit → (write tests) → refactor → behavior-preservation review |
| [`/refactor-lite`](#lightweight-pipelines-build-lite-refactor-lite) | Target → audit → plan → approve → refactor in one context — no fan-out, review separated |
| [`/qa`](#the-qa-pipeline-qa) | Running app → exploratory browser testing → QA report + Playwright E2E tests |
| [`/craft-pr`](#craft-a-pr-craft-pr) | Branch's task files + diff → polished PR description |

Task/QA artifacts are [branch-scoped](#branch-scoped-work-directories) so you can run multiple pipelines in parallel across branches (including git worktrees) without collision.

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

By default the script installs agents and skills **globally** into `~/.claude/` — available across every project with no per-project setup needed:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/nickmaglowsch/claude-setup/main/setup.sh)
```

Re-run the same command to update. It auto-detects whether `~/.claude/agents/` already exists and updates in place (no prompts) or installs fresh (with overwrite prompts).

The template repo is auto-cloned to `/tmp/claude-setup` (or pulled if already there).

#### Per-project install

Use `--local` to install into a specific project directory instead:

```bash
cd /path/to/your/project
bash <(curl -fsSL https://raw.githubusercontent.com/nickmaglowsch/claude-setup/main/setup.sh) --local
```

The script auto-detects whether this is a first-time setup or an update:
- **New project** (no `.claude/agents/`): runs the interactive setup — copies agents, skills, settings, and optionally adds devcontainer + headless runner
- **Existing setup** (`.claude/agents/` found): updates all agent and skill files to the latest version while preserving your `settings.local.json` and `agent-memory/`

#### Updating an existing local setup

Same one-liner with `--local` — the script auto-detects the existing setup and runs in update mode:

```bash
cd /path/to/your/project
bash <(curl -fsSL https://raw.githubusercontent.com/nickmaglowsch/claude-setup/main/setup.sh) --local
```

To force update mode explicitly:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/nickmaglowsch/claude-setup/main/setup.sh) --local --update
```

Update mode pulls the latest template, overwrites all agent and skill files, and leaves your `settings.local.json` and `agent-memory/` untouched.

To add devcontainer support during an update (if you skipped it during initial setup):

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/nickmaglowsch/claude-setup/main/setup.sh) --update --add-devcontainer
```

#### Other coding agents (OpenCode, Gemini CLI, Codex CLI)

Add `--compatible` to generate native agent files for other tools alongside the Claude setup:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/nickmaglowsch/claude-setup/main/setup.sh) --compatible opencode,gemini,codex
```

For OpenCode and Gemini, you'll be prompted to choose models per agent system (heavy-tier and standard-tier). Generated files:

| Flag | Generated | Also creates |
|---|---|---|
| `opencode` | `.opencode/agents/*.md` | `AGENTS.md → CLAUDE.md` symlink |
| `gemini` | `.gemini/agents/*.toml` | `GEMINI.md → CLAUDE.md` symlink |
| `codex` | `~/plugins/claude-setup-codex/` | `~/.agents/plugins/marketplace.json` entry |

For OpenCode and Gemini, agents are transpiled from the `.claude/agents/` source files — same system prompts, same role split (heavy tier: `bug-investigator`, `code-reviewer`, `qa-agent`; standard tier: everything else). Defaults: `anthropic/claude-opus-4-6` / `anthropic/claude-sonnet-4-6` for OpenCode, `gemini-2.5-pro` / `gemini-2.5-flash` for Gemini CLI.

The `AGENTS.md` / `GEMINI.md` symlinks point to `CLAUDE.md` so project-level instructions are shared across all agents automatically. Commit these files so teammates using other agents benefit too.

##### Codex CLI compatibility

`--compatible codex` generates a home-local Codex plugin instead of forking this repo:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/nickmaglowsch/claude-setup/main/setup.sh) --compatible codex
```

Generated paths:

- `~/plugins/claude-setup-codex/.codex-plugin/plugin.json`
- `~/plugins/claude-setup-codex/skills/*/SKILL.md`
- `~/plugins/claude-setup-codex/references/agents/*.md`
- `~/.agents/plugins/marketplace.json`

The marketplace entry uses `source.path: "./plugins/claude-setup-codex"`, `installation: "AVAILABLE"`, `authentication: "ON_INSTALL"`, and category `Productivity`. Re-running the installer updates the plugin in place and keeps a single marketplace entry.

Use the generated workflows as Codex skills: `build`, `debug-workflow`, `refactor`, `qa`, `craft-pr`, `grill-me`, `grill-with-docs`, and `init-claude-setup`. Codex reads `AGENTS.md` for project instructions; when `CLAUDE.md` exists and `AGENTS.md` does not, the installer creates an `AGENTS.md → CLAUDE.md` symlink.

Codex compatibility is v1 and covers skills, shared agent-prompt references, and documentation only. It does not convert Token Reducer hooks, the Claude status line, Claude Agent Teams, `run-claude.sh`, or the devcontainer Claude install.

#### Token Reducer Pack

The installer includes an optional Token Reducer Pack that cuts token usage by 60-90% across all projects. It's offered during setup and can also be installed standalone:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/nickmaglowsch/claude-setup/main/setup.sh) --token-reducer
```

Three tiers — each builds on the previous:

**Tier 1 — Global file deny rules** (always-on, zero overhead)

Prevents Claude from reading irrelevant files across all projects. Build artifacts, lock files, caches, and generated code for all major stacks (Node, Python, Rust, Go, Java, Ruby, PHP) are blocked:

```
node_modules, dist, build, .next, .nuxt, out, .output,
*.lock, package-lock.json, yarn.lock, pnpm-lock.yaml, Cargo.lock, Gemfile.lock, poetry.lock, composer.lock,
target, __pycache__, .venv, venv, .gradle, .m2, vendor,
*.min.js, *.min.css, *.map, *.chunk.js,
.git, .DS_Store, coverage, .nyc_output, logs, *.log
```

Rules are merged into `~/.claude/settings.json` — existing settings (MCP servers, etc.) are preserved.

**Tier 2 — RTK (Rust Token Killer)** (recommended)

Compresses CLI command output before it reaches the context window. Git logs, test output, directory listings — all the noisy runtime output gets compressed, averaging 70-90% token reduction on Bash tool calls.

- Installed via Homebrew (macOS) or the official install script (Linux/WSL)
- Hooks into Claude Code automatically via `rtk init -g`
- Only intercepts Bash tool calls — built-in tools like Read, Grep, and Glob bypass it

RTK remains the shell-output safety net. The workflow prompts still prefer bounded commands, summarized failures, and compact review packets because RTK cannot remove duplicate cold reads across planner, implementer, orchestrator, and reviewer contexts.

**Tier 3 — [context-mode](https://github.com/mksglu/context-mode) MCP server** (power users)

An MCP server that optimizes context window usage through sandbox execution, an FTS5 knowledge base, and session continuity. Best for long/complex sessions where compaction is the bottleneck.

- **Sandbox execution**: runs code in isolated subprocesses — only stdout enters context (98% reduction on raw data like logs, API responses, browser snapshots)
- **FTS5 knowledge base**: chunks docs into SQLite, retrieves only relevant sections via BM25 search
- **Session continuity**: tracks file edits, git ops, tasks, and errors; rebuilds a priority-tiered 2KB snapshot on compaction instead of dumping full history
- Configured as an MCP server in `~/.claude/settings.json` — runs via `npx context-mode@latest`
- License: Elastic License v2 (source-available, not OSI open-source)

During setup you choose which tiers to enable:
- **Option 1** (default): Tier 1 + 2 — deny rules + RTK
- **Option 2**: Tier 1 only — deny rules
- **Option 3**: All tiers — deny rules + RTK + context-mode

If you skip the Token Reducer Pack during setup, you'll get a one-time reminder next time you open Claude Code.

**Upgrading existing installs**: If you already have Tier 1+2 (deny rules + RTK) and want to add Tier 3 (context-mode), re-run the token reducer installer and choose option 3:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/nickmaglowsch/claude-setup/main/setup.sh) --token-reducer
```

If auto-updates are enabled, you'll also get a one-time nudge about Tier 3 the next time you open Claude Code.

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

# Or debug a bug:
# /debug-workflow <describe the bug, include log commands and test commands>
```

Review `.claude/settings.local.json` to adjust permissions for your project.

## Directory Structure

```
.claude/
├── agents/                           # Custom agent definitions
│   ├── agent-teams-orchestrator.md       # Lead for Agent Teams mode (beta)
│   ├── app-scout.md                      # Fast read-only project recon
│   ├── bug-fixer.md                      # Fixes diagnosed bugs using adaptive TDD
│   ├── bug-investigator.md               # Investigates bugs, reads logs, produces diagnosis
│   ├── code-reviewer.md                  # Reviews diff-scoped code changes against PRD/spec
│   ├── parallel-task-orchestrator.md     # Executes task files in batched parallel waves
│   ├── prd-task-planner.md               # Analyzes PRDs, explores codebase, generates task files
│   ├── qa-agent.md                       # Tests running apps via playwright-cli, produces QA report + E2E tests
│   ├── refactor-planner.md               # Analyzes code smells and generates refactor tasks
│   ├── task-implementer.md               # Implements one task or a small related task batch
│   └── test-writer.md                    # Writes missing tests for existing code
├── skills/                           # User-invocable skills (slash commands)
│   ├── build/SKILL.md                    # /build — route-lite → plan → implement → diff-scoped review
│   ├── build-lite/SKILL.md               # /build-lite — plan → approve → implement in one context (no fan-out)
│   ├── craft-pr/SKILL.md                 # /craft-pr — generates PR description from tasks + diff
│   ├── debug-workflow/SKILL.md           # /debug-workflow — investigate → diagnose → TDD fix → review
│   ├── grill-me/SKILL.md                 # /grill-me — pre-PRD interview to align on a fuzzy plan
│   ├── grill-with-docs/                  # /grill-with-docs — grill + update CONTEXT.md/ADRs inline
│   ├── init-claude-setup/SKILL.md        # /init-claude-setup — project-level init (gitignore, settings)
│   ├── qa/SKILL.md                       # /qa — exploratory QA via browser + Playwright E2E tests
│   ├── refactor/SKILL.md                 # /refactor — audit → plan → (tests) → implement → review
│   └── refactor-lite/SKILL.md            # /refactor-lite — audit → approve → refactor in one context (no fan-out)
├── agent-memory/                     # Persistent memory per agent (survives across sessions)
└── settings.local.json               # Local Claude Code settings

tasks/<branch>/                       # Branch-scoped task/diagnosis/plan files (see below)
qa-output/<branch>/                   # Branch-scoped QA reports + screenshots
```

### Branch-scoped work directories

Both `tasks/` and `qa-output/` are **branch-scoped**: the pipelines write into `tasks/<sanitized-current-branch>/` and `qa-output/<sanitized-current-branch>/` respectively. Slashes become dashes (e.g. `feat/plan-review` → `feat-plan-review`).

Why: lets you run `/build`, `/debug-workflow`, `/refactor`, and `/qa` in parallel across branches (including git worktrees) without any of them clobbering each other's files. If you're not in a git repo or are in detached HEAD, there's a sensible fallback — no pipeline will silently write into a shared directory.

Both trees are gitignored by default (`tasks/**`, `qa-output/**`).

## The Build Pipeline (`/build`)

The `/build` skill orchestrates the full feature implementation lifecycle. Paste a PRD or feature spec and it handles everything.

### How it works

```
PRD → [Cheap lite-routing check] → [Adequacy check] → [Plan] → [User Q&A] → [Implement] → [Test] → [Diff-scoped review] → Done
```

All outputs land in `tasks/<branch>/` (see [Branch-scoped work directories](#branch-scoped-work-directories)).

Before any heavyweight setup, `/build` performs a bounded read-only routing check. If the work looks localized, sequential, or likely to be 1-2 implementation tasks, it switches into the `/build-lite` workflow in the same session. That avoids paying for auto-commit/worktree/orchestration questions and cold planner/implementer/reviewer contexts when a single warm context is cheaper and just as safe.

Before any planning, `/build` checks whether the input PRD has enough substance. If it's a one-liner or full of hedges, you're offered three escapes: run [`/grill-me`](#pre-build-grilling-grill-me-grill-with-docs) (or [`/grill-with-docs`](#pre-build-grilling-grill-me-grill-with-docs) if the repo has a `CONTEXT.md`) first, switch to `--brainstorm` mode, or continue anyway. Skipped automatically when `--brainstorm` is already passed.

#### Step 1: Two-Phase Planning (with user input)

The planning step is split into **discovery** and **generation** so the planner can ask you questions before committing to a plan.

**Step 1a — Discovery**
The `prd-task-planner` agent explores the codebase and writes `tasks/<branch>/planning-questions.md` with:
- A summary of what it found in the codebase (architecture, existing features, relevant code)
- 3-8 questions about architectural decisions, scope, and integration choices that would materially change the plan

**Step 1b — User Q&A**
The build orchestrator reads the questions file and presents them to you interactively. You answer each question.

**Step 1c — Generation**
The same planner agent is **resumed** (keeping all its codebase exploration context) with your answers. It then generates:
- `tasks/<branch>/updated-prd.md` — the PRD refined with codebase context
- `tasks/<branch>/task-01-*.md`, `task-02-*.md`, ... — ordered, self-contained task files

**Step 1d — Plan approval**
The build orchestrator presents the plan (task list + dependencies) to you. You can approve or regenerate with feedback.

**Step 1e — Fast-path detection**
The planner self-checks dependency soundness, PRD coverage, file conflicts, task sizing, and TDD consistency before returning. The build session then checks whether the generated task graph actually justifies orchestration. If the plan is small, sequential, or mostly touches overlapping files, it implements directly in the current warm context instead of spawning the orchestrator.

#### Step 2: Parallel Implementation

The `parallel-task-orchestrator` reads all task files, builds a dependency graph, creates one shared context summary, batches related same-wave tasks when safe, and spawns `task-implementer` agents in parallel waves. Implementers write detailed notes to `tasks/<branch>/notes/` and return only short status summaries so the orchestrator does not absorb N large sub-agent outputs.

#### Step 3: Code Review

The `code-reviewer` audits all changes against `tasks/<branch>/updated-prd.md` and produces a compliance report. It starts from a compact review packet (`git diff --stat`, changed file list, commit list, implementation notes, and build/test summaries), then expands to full files only when needed to verify requirements, behavior, contracts, or conventions.

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
Task: prd-task-planner — "Here's the PRD: ... Output tasks to tasks/<branch>/"

# Just implement
Task: parallel-task-orchestrator — "Execute all tasks from tasks/<branch>/"

# Just review
Task: code-reviewer — "Review changes against tasks/<branch>/updated-prd.md"
```

When invoked directly (outside `/build`), the `prd-task-planner` runs all phases end-to-end without the Q&A pause. The two-phase flow only activates when the prompt includes `MODE: DISCOVERY` or `MODE: GENERATE`. If no `TASKS_DIR=<path>` is provided in the prompt, the agent falls back to a flat `tasks/` directory.

### TDD Mode (opt-in)

The build pipeline supports optional Test-Driven Development. When TDD is active, tests are written before implementation code for every task.

#### How to enable

During the planning Q&A step (Step 1b), the planner will ask: "Do you want TDD mode for this build?" Answer yes to enable it.

#### What changes with TDD enabled

1. **Task files include test specifications**: Each task gets a `## TDD Mode` section with specific tests to write, expected behaviors, and the test framework/command to use
2. **Implementer follows RED->GREEN->verify**: The `task-implementer` writes failing tests first, then implements code to make them pass, then checks for regressions
3. **Code review includes TDD compliance**: The `code-reviewer` verifies that tests were written, are meaningful, and cover the acceptance criteria

#### Always-on test awareness (even without TDD)

Even when TDD mode is not enabled, the pipeline is test-aware:
- The `task-implementer` discovers and runs existing tests related to modified files
- The build pipeline runs the project's full test suite after implementation (Step 2c)
- The `code-reviewer` evaluates test coverage as a standard quality check

## Pre-build grilling (`/grill-me`, `/grill-with-docs`)

The most common reason a build goes sideways isn't bad code — it's that the PRD didn't say what the user actually wanted. These two skills sit *before* `/build` and force alignment up front.

- **`/grill-me`** — interview-style skill that walks down every branch of a plan one question at a time, recommending an answer for each. Use when you have a fuzzy idea and no PRD yet.
- **`/grill-with-docs`** — same shape, but also reads the project's `CONTEXT.md` (and `docs/adr/`) and challenges your terminology against the documented domain language. Updates `CONTEXT.md` and creates ADRs inline as decisions crystallise. Use when the project has (or should have) a domain glossary.

`CONTEXT.md` is a per-repo file capturing the domain language: bolded canonical terms, aliases to avoid, relationships, and an example dialogue. ADRs live in `docs/adr/` and capture the *why* of hard-to-reverse decisions. Both files are created lazily — the skill writes to them only when there's something to record. See [`CONTEXT-FORMAT.md`](.claude/skills/grill-with-docs/CONTEXT-FORMAT.md) and [`ADR-FORMAT.md`](.claude/skills/grill-with-docs/ADR-FORMAT.md) for the formats.

```bash
/grill-me                 # I want to add comment threading to the wiki
/grill-with-docs          # same, but also evolve CONTEXT.md/ADRs
```

When `/build` detects a sparse PRD it offers these as the recommended next step (Step 0.05 in `build/SKILL.md`).

Credit: adapted from [mattpocock/skills](https://github.com/mattpocock/skills).

## The Debug Pipeline (`/debug-workflow`)

The `/debug-workflow` skill orchestrates an investigative debugging workflow. Describe a bug and it handles investigation, diagnosis, TDD fix, and review.

### How it works

```
Bug Report → [Investigate] → [User Q&A] → [Diagnose] → [TDD Fix] → [Review] → Done
```

#### Step 1: Two-Phase Investigation (with user input)

**Step 1a — Discovery**
The `bug-investigator` agent reads logs, searches the codebase, attempts to reproduce the issue, and writes `tasks/<branch>/debug-questions.md` with:
- A summary of what it found (symptoms confirmed, code traced, hypotheses)
- 2-6 questions about environment, recent changes, reproduction conditions

**Step 1b — User Q&A**
The debug orchestrator reads the questions file and presents them to you interactively.

**Step 1c — Diagnosis**
The same investigator agent is **resumed** with your answers. It then produces:
- `tasks/<branch>/bug-diagnosis.md` — root cause analysis, affected files, fix recommendations, test strategy

#### Step 2: TDD Fix

The `bug-fixer` agent reads the diagnosis, writes a failing test (when feasible), implements the fix, and verifies no regressions. If TDD is not feasible, it documents why and uses alternative verification.

#### Step 3: Code Review

The `code-reviewer` audits the fix against `tasks/<branch>/bug-diagnosis.md` with debug-specific criteria (root cause addressed, regressions checked, test coverage).

### Usage

```
/debug-workflow Login fails with 500 error after upgrading auth library. Logs: 'docker logs app-api'. Tests: 'npm test -- --grep auth'
```

### Running agents individually

```
# Just investigate (discovery + diagnose in one shot, no Q&A pause)
Task: bug-investigator — "Investigate: Login fails with 500 error..."

# Just fix a diagnosed bug
Task: bug-fixer — "Fix the bug. Diagnosis: tasks/<branch>/bug-diagnosis.md. Tests: npm test"

# Just review a bug fix
Task: code-reviewer — "Review changes against tasks/<branch>/bug-diagnosis.md"
```

## The Refactor Pipeline (`/refactor`)

The `/refactor` skill improves code quality without adding features. It's the same shape as `/build` but the planner is focused on code smells, duplication, and complexity — and there's an optional safety-net step to write missing tests before any code is changed.

```
Target → [Audit + Q&A] → [Tests (optional)] → [Implement] → [Build check] → [Test verify] → [Review] → Done
```

Before heavyweight setup, `/refactor` also performs a cheap routing check. Single-file, localized, or linear refactors switch into `/refactor-lite` in the same session; full `/refactor` is reserved for broad cleanup with real parallelism. When the full pipeline is justified, the `refactor-planner` agent audits the target file/directory, surfaces clarifying questions (scope, API compatibility, whether to write tests first), then generates ordered refactor tasks in `tasks/<branch>/`. If you asked for tests first, the `test-writer` agent fills in coverage gaps *before* any refactoring starts — giving you a safety net against regressions. The `code-reviewer` then validates that behavior was preserved and the result is measurably cleaner using the same compact, diff-scoped review packet.

```bash
/refactor src/auth/
/refactor path/to/really-gnarly-file.ts
```

The pipeline supports auto-commit with three commit modes (squash / per-wave / per-task-at-end) and can open a PR via `gh`.

## The QA Pipeline (`/qa`)

The `/qa` skill runs exploratory QA against a running app — like a real user, via a browser. It produces a QA report **and** Playwright E2E tests you can keep as regression coverage.

```
App running → [Recon] → [Explore + test flows] → [Write report] → [Write E2E tests]
```

- `app-scout` detects the dev-server URL, test commands, and tech stack (cached for 1 hour, `--fresh` forces a re-scan)
- `qa-agent` navigates the app via `playwright-cli`, tests happy paths + edge cases + error handling, writes `qa-output/<branch>/qa-report.md` (with severity-tagged issues and screenshots of failures), then emits Playwright E2E tests to the project's test directory

```bash
/qa                                    # test every major flow
/qa checkout                           # scope to the checkout feature
/qa --fresh signup                     # force re-scan of app context
```

The agent never modifies production code — its writes are confined to `qa-output/<branch>/` and your `e2e/` (or equivalent) test directory.

## Craft a PR (`/craft-pr`)

Once work is done on a branch, `/craft-pr` reads `tasks/<branch>/*.md` plus the diff against `origin/main` and drafts a polished PR description (summary, changes, test plan) for you to copy into GitHub.

```bash
/craft-pr
```

## Lightweight Pipelines (`/build-lite`, `/refactor-lite`)

The heavy `/build` and `/refactor` pipelines spend tokens to buy **parallelism** and **context isolation**: a planner agent, a fan-out of implementer sub-agents, and a reviewer agent, each spawning cold and re-reading the same files, with task files serialized between them. That trade pays off for large, parallelizable work — and not much else.

For everyday features and cleanups, `/build-lite` and `/refactor-lite` do the same job in a **single warm context**:

```
explore (read-only) → plan → you approve → implement → verify build+tests → optional commit → offer /code-review
```

No sub-agent fan-out, no intermediate task files, no orchestration-mode/worktree/brainstorm prompts. Because nothing re-reads the codebase from a cold context, they typically cost **fewer tokens** than the full pipelines, not just less ceremony. Code review is deliberately **separated** — they finish by offering an independent [`/code-review`](https://docs.claude.com/en/docs/claude-code) pass rather than bundling it, so the reviewer sees the diff with fresh eyes.

**Just use `/build` or `/refactor` when you want automatic routing.** Both commands perform a cheap routing check and switch into the lite workflow when lite is the better fit. Invoke `/build-lite` or `/refactor-lite` directly when you explicitly want to skip the routing check and force the lightweight path. Use the heavy orchestrated path when the work spans many independent files worth implementing in parallel, or genuinely exceeds a single context (large migrations, broad sweeps).

| | Heavy (`/build`, `/refactor`) | Lite (`/build-lite`, `/refactor-lite`) |
|---|---|---|
| Implementation | Parallel sub-agent fan-out | Single warm context |
| Planning | `prd-task-planner` agent + task files | Inline plan, approved in chat |
| Review | Bundled, diff-scoped `code-reviewer` agent | Separated — offers `/code-review` |
| Git plumbing | Auto-commit / branch / PR / worktree opt-ins | Optional commit (+ optional push/PR) |
| Best for | Large, parallelizable work | Everyday features & cleanups |

## Agent Memory

Each agent has persistent memory in `.claude/agent-memory/<agent-name>/`. Agents record codebase patterns, conventions, and insights they discover. This builds institutional knowledge across sessions — e.g., the planner remembers your project structure so future planning is faster.

## Agent Teams Mode (Beta)

`/build` and `/refactor` support a second orchestration mode powered by Claude Code's native Agent Teams feature.

**Default (Recommended):** Uses `parallel-task-orchestrator` — a proven sub-agent approach with wave-based parallel execution. Best choice for most users.

**Agent Teams (Beta):** The skill session acts as lead and spawns teammates directly via Claude Code's native teammate API, coordinating via a shared task list. No sub-agent nesting required.

### How to use it

After task planning completes in `/build` or `/refactor`, you'll be asked to choose an orchestration mode. Select "Agent Teams (Beta)" — the skill automatically enables the required env var in your settings file:

```json
{ "env": { "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1" } }
```

It checks for settings in this order: `.claude/settings.local.json`, `.claude/settings.json`, `~/.claude/settings.json` (local first to avoid modifying global settings). If none exist, it creates `.claude/settings.local.json`. Existing settings are preserved. The env var is automatically removed after the run completes.

### Caveats

- The Agent Teams API is experimental and may change in future Claude Code versions
- `COMMIT_MODE=per-task` is not supported in Agent Teams mode — commits fall back to squash style
- May result in higher token usage than the default sub-agent approach
- `TaskCreate`/`TaskUpdate` progress tracking may conflict with the Agent Teams native task list — the system falls back to native-only tracking if duplicates are detected
- Only one team can be active per session — if team creation fails, the pipeline automatically falls back to Default mode
- If Agent Teams is unavailable in your Claude Code version, use Default mode

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
