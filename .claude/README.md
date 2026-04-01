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
│   └── debug-workflow/SKILL.md  # /debug-workflow — investigate → diagnose → TDD fix → review
├── agent-memory/            # Persistent memory per agent (survives across sessions)
└── settings.local.json      # Local Claude Code settings
```

## The Build Pipeline (`/build`)

The `/build` skill orchestrates the full feature implementation lifecycle. Paste a PRD or feature spec and it handles everything.

### How it works

```
PRD → [Plan] → [User Q&A] → [Implement] → [Test] → [Review] → Done
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

### TDD Mode (opt-in)

The build pipeline supports optional Test-Driven Development. When TDD is active, tests are written before implementation code for every task.

#### How to enable

During the planning Q&A step (Step 1b), the planner will ask: "Do you want TDD mode for this build?" Answer yes to enable it.

#### What changes with TDD enabled

1. **Task files include test specifications**: Each task gets a `## TDD Mode` section with specific tests to write, expected behaviors, and the test framework/command to use
2. **Implementer follows RED->GREEN->REFACTOR->VERIFY**: The `task-implementer` writes failing tests first, validates test adequacy (no trivial assertions), implements code to make them pass, refactors for clarity, then checks for regressions
3. **Test adequacy check**: Before implementing, the implementer verifies each test has meaningful assertions, covers acceptance criteria, and fails for distinct reasons
4. **Code review includes TDD compliance**: The `code-reviewer` does a deep-check on every test (calls code under test, has specific assertions, catches real regressions) and validates TDD skip reasons
5. **Stricter TDD escape hatch**: "Effort is disproportionate" is not a valid skip reason when the project has a working test framework

#### Always-on test awareness (even without TDD)

Even when TDD mode is not enabled, the pipeline is test-aware:
- The `task-implementer` discovers and runs existing tests related to modified files
- The build pipeline runs the project's full test suite after implementation (Step 2c)
- The `code-reviewer` evaluates test coverage as a standard quality check

## The Debug Pipeline (`/debug-workflow`)

The `/debug-workflow` skill orchestrates an investigative debugging workflow. Describe a bug and it handles investigation, diagnosis, TDD fix, and review.

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
/debug-workflow Login fails with 500 error after upgrading auth library. Logs: 'docker logs app-api'. Tests: 'npm test -- --grep auth'
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

## Sprint Contracts (Implementation Notes)

When agents implement code, they produce structured **Implementation Notes** documenting non-obvious decisions, deviations from specs, trade-offs, and risks. This creates a "sprint contract" between implementers and reviewers.

- **Implementers** (task-implementer, bug-fixer): output an `## Implementation Notes` section with every task
- **Orchestrator**: consolidates all notes into `tasks/implementation-notes.md`
- **Reviewer**: reads the notes to understand intent before reviewing — flags incorrect reasoning rather than blindly enforcing conventions

This closes the gap where a reviewer might flag a deliberate architectural choice as an issue because they lack context about why it was made.

## Execution Metrics

Every pipeline run produces structured execution metrics in `tasks/execution-metrics.md`:

- **Task-level**: status, wave, retry count, TDD mode used, TDD skip reasons, files changed
- **Pipeline-level**: total/completed/failed tasks, wave count, TDD compliance rate
- **Failure log**: error summaries and retry outcomes

Metrics are included in the final pipeline report so you can see at a glance how the build went.

## Agent Memory

Each agent has persistent memory in `.claude/agent-memory/<agent-name>/`. Agents record codebase patterns, conventions, and insights they discover. This builds institutional knowledge across sessions — e.g., the planner remembers your project structure so future planning is faster.
