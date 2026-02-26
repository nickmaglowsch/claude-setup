---
name: build
description: "Full build pipeline: takes a PRD, breaks it into tasks, implements them in parallel, and reviews the result. Orchestrates prd-task-planner → parallel-task-orchestrator → code-reviewer."
argument-hint: "[paste PRD or path to PRD file]"
---

# Build Pipeline

You are orchestrating the full build pipeline. Follow these steps strictly in order.

## Input

The user's PRD or feature spec:

$ARGUMENTS

## Step 1: Plan — Two-phase planning with user Q&A

### Step 1a: Discovery — Explore codebase & surface questions

Launch the `prd-task-planner` agent using the Task tool with:
- `subagent_type: "prd-task-planner"`
- Provide the full PRD content above as the prompt
- Prepend `MODE: DISCOVERY` to the prompt
- Tell it to output questions to `tasks/planning-questions.md`

Wait for it to complete. **Save the returned agent ID** — you will resume this agent in Step 1c.

### Step 1b: User Q&A — Present questions and collect answers

1. Read `tasks/planning-questions.md`
2. Present each question to the user using `AskUserQuestion` — use the questions, context, and options from the file to construct clear choices
3. Collect all answers

### Step 1c: Generate — Resume planner with answers

Resume the **same** prd-task-planner agent (using the agent ID from Step 1a) with:
- `resume: "<agent-id-from-step-1a>"`
- Provide all user answers in the prompt, formatted clearly
- Prepend `MODE: GENERATE` to the prompt
- Tell it to generate the updated PRD and task files in `tasks/`

Wait for it to complete. Confirm that task files were created in `tasks/`.

## Step 2: Implement — Run parallel-task-orchestrator

Launch the `parallel-task-orchestrator` agent using the Task tool with:
- `subagent_type: "parallel-task-orchestrator"`
- Tell it to read and execute all tasks from `tasks/`

Wait for it to complete. Note any issues reported.

## Step 3: Review — Run code-reviewer

Launch the `code-reviewer` agent using the Task tool with:
- `subagent_type: "code-reviewer"`
- Tell it to review all changes against `tasks/updated-prd.md`

Wait for it to complete.

## Step 4: Report

Summarize the full pipeline run to the user:

```
## Build Complete

### Planning
- [X tasks created]

### Implementation
- [tasks completed / total]
- [any issues]

### Review
- [compliance score]
- [critical issues if any]

### Next Steps
- [what the user should do — e.g., run tests, fix issues, deploy]
```

## Rules
- Run the steps **sequentially** — each depends on the previous
- If Step 1 fails (no tasks created), stop and report the issue
- If Step 2 has partial failures, still run Step 3 to review what was completed
- Always run Step 3 — never skip the review
