# Claude Code Agent Setup

This directory contains the configuration for Claude Code's custom agents, skills, and memory.

## Directory Structure

```
.claude/
├── agents/                  # Custom agent definitions
│   ├── bug-fixer.md             # Fixes diagnosed bugs using adaptive TDD
│   ├── bug-investigator.md      # Investigates bugs, reads logs, produces diagnosis
│   ├── prd-task-planner.md      # Analyzes PRDs, explores codebase, generates task files
│   ├── task-implementer.md      # Implements a single task from a task file
│   ├── parallel-task-orchestrator.md  # Executes task files in parallel waves
│   └── code-reviewer.md        # Reviews changes against PRD/spec
├── skills/                  # User-invocable skills (slash commands)
│   ├── build/SKILL.md           # /build — full pipeline: plan → implement → review
│   ├── craft-pr/SKILL.md       # /craft-pr — generates PR description from tasks + diff
│   └── debug/SKILL.md          # /debug — investigate → diagnose → TDD fix → review
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

## The Debug Pipeline (`/debug`)

The `/debug` skill orchestrates an investigative debugging workflow. Describe a bug and it handles investigation, diagnosis, TDD fix, and review.

### How it works

```
Bug Report → [Investigate] → [User Q&A] → [Diagnose] → [TDD Fix] → [Review] → Done
```

#### Step 1: Two-Phase Investigation (with user input)

**Step 1a — Discovery**
The `bug-investigator` agent reads logs, searches the codebase, attempts to reproduce the issue, and writes `tasks/debug-questions.md` with:
- A summary of what it found (symptoms confirmed, code traced, hypotheses)
- 2-6 questions about environment, recent changes, reproduction conditions

**Step 1b — User Q&A**
The debug orchestrator reads the questions file and presents them to you interactively.

**Step 1c — Diagnosis**
The same investigator agent is **resumed** with your answers. It then produces:
- `tasks/bug-diagnosis.md` — root cause analysis, affected files, fix recommendations, test strategy

#### Step 2: TDD Fix

The `bug-fixer` agent reads the diagnosis, writes a failing test (when feasible), implements the fix, and verifies no regressions. If TDD is not feasible, it documents why and uses alternative verification.

#### Step 3: Code Review

The `code-reviewer` audits the fix against `tasks/bug-diagnosis.md` with debug-specific criteria (root cause addressed, regressions checked, test coverage).

### Usage

```
/debug Login fails with 500 error after upgrading auth library. Logs: 'docker logs app-api'. Tests: 'npm test -- --grep auth'
```

### Running agents individually

```
# Just investigate (discovery + diagnose in one shot, no Q&A pause)
Task: bug-investigator — "Investigate: Login fails with 500 error..."

# Just fix a diagnosed bug
Task: bug-fixer — "Fix the bug. Diagnosis: tasks/bug-diagnosis.md. Tests: npm test"

# Just review a bug fix
Task: code-reviewer — "Review changes against tasks/bug-diagnosis.md"
```

## Agent Memory

Each agent has persistent memory in `.claude/agent-memory/<agent-name>/`. Agents record codebase patterns, conventions, and insights they discover. This builds institutional knowledge across sessions — e.g., the planner remembers your project structure so future planning is faster.
