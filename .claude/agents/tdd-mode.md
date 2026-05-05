# TDD Mode — shared reference

This file is loaded **only when needed** by `prd-task-planner` and `task-implementer` agents — when a task has (or is about to have) a `## TDD Mode` section. Agents that are not doing TDD work do not read this file.

The goal: keep TDD-specific instructions out of every agent's always-on context, since most builds run without TDD.

---

## Section A — Task file template (used by `prd-task-planner` GENERATE mode)

When TDD mode was requested by the user, every functional-code task file MUST include the following section verbatim (substitute the bracketed values with project-detected ones):

```markdown
## TDD Mode

This task uses Test-Driven Development. Write tests BEFORE implementation.

### Test Specifications
- **Test file**: `path/to/test-file` (following project conventions)
- **Test framework**: [detected framework]
- **Test command**: [detected command]

### Tests to Write
1. **[Test name]**: [What to test] — Expected: [expected behavior]
2. ...

### TDD Process
1. Write the tests above — they should FAIL (RED)
2. Implement the minimum code to make them pass (GREEN)
3. Run the full test suite to check for regressions
4. Refactor if needed while keeping tests green

### Mocking Discipline
- Mock only at the **system boundary**: paid/external APIs, network, wall clock & randomness, destructive side effects, filesystem I/O.
- Do NOT mock the code under test or internal modules it calls — that hides real regressions. Use real internal collaborators, in-memory instances, or lightweight fakes.
- Do NOT mock a layer above the real boundary (mock the HTTP client / SDK / DB driver, not a wrapper your code calls through).
- When mocking a boundary, the mock's shape and behavior must match the real dependency (shared types, recorded fixtures, or a reusable fake — not ad-hoc stubs).
```

Detect framework, command, and conventions during the codebase audit (Phase 1) and substitute them in. Project test infrastructure also lives in `$TASKS_DIR/shared-context.md` so the implementer doesn't have to re-derive it.

---

## Section B — Implementer workflow (used by `task-implementer` when a task has `## TDD Mode`)

Replace the standard implement-and-verify flow (Steps 4 + 5) with these four steps.

### Step 4a (TDD Mode): Write Failing Tests (RED)
- Read existing test files near the code being modified to understand test patterns and conventions
- Write the tests specified in the `## TDD Mode` section
- Run the tests using the specified test command via Bash
- Confirm they fail for the right reasons (not import errors or syntax errors — those must be fixed first)
- If tests unexpectedly pass, note this — the requirement may already be met or the test needs adjustment
- **If tests fail for wrong reasons** (import errors, missing modules, syntax errors): fix the test setup, not the test logic. Re-run. Max 3 fix-and-retry cycles before escalating as a blocker.

**Mocking discipline** (critical — prevents silent regressions):
- Mock only at the **system boundary**: paid/external APIs, network, wall clock & randomness, destructive side effects, filesystem I/O.
- Do NOT mock the code under test, or **internal modules it calls**. Using real internal collaborators is what makes the test catch real regressions. If an internal module is hard to set up, use an in-memory instance or a lightweight fake — not a mock.
- Do NOT mock a layer *above* the real boundary (mock the HTTP client / SDK / DB driver, not your own service wrapper around it — otherwise a regression in the wrapper is invisible).
- When mocking a real boundary, the mock's shape and behavior must match the real dependency. Prefer shared types / recorded fixtures / a reusable thin fake over ad-hoc stubs returning whatever a particular test happens to need.

**If TDD is not feasible**, document why and fall back to the standard implement-and-verify flow. Valid reasons:
- No test framework configured in the project **and** installing one is outside task scope
- The code is infrastructure/configuration (e.g., CI config, Docker, env vars) that has no testable interface
- Do NOT use "effort is disproportionate" as a reason if the project already has a working test framework — if the framework exists, write the test

### Step 4a.1 (TDD Mode): Test Adequacy Check
After writing tests but BEFORE implementing production code, verify test quality:
1. **Assertion check**: Re-read each test — does every test contain at least one meaningful assertion against the code under test? Reject trivial assertions (`expect(true).toBe(true)`, `expect(1).toBe(1)`, assertions that don't reference the function/module being tested)
2. **Behavior coverage**: Compare tests against the acceptance criteria in the task file — is each criterion exercised by at least one test?
3. **Failure specificity**: Each test should fail for a distinct reason. If two tests would fail with the same error, consolidate or differentiate them.
4. If any check fails, fix the tests and re-run the RED step before proceeding.

### Step 4b (TDD Mode): Implement (GREEN)
- Implement the minimum code needed to make all tests pass
- Follow the requirements and implementation details from the task file
- Follow the patterns observed when reading neighboring files
- Run the tests again to confirm they pass
- If they don't pass, iterate: adjust the implementation, re-run tests

### Step 4c (TDD Mode): Refactor
- Re-read the implementation code you just wrote
- Look for: duplication introduced, overly complex conditionals, naming that could be clearer, patterns that diverge from the rest of the codebase
- If improvements are possible: refactor while keeping tests green (run tests after each change)
- If the code is already clean and matches conventions: skip this step and note "No refactoring needed" in output
- Do NOT add features or change behavior — only improve structure

### Step 4d (TDD Mode): Verify (No Regressions)
- Run the full test suite if a test command is available (beyond just the new tests)
- Run build/lint commands if available
- If regressions are found, adjust the implementation and re-run
- Re-read modified files to confirm correctness
- Verify all acceptance criteria from the task are met

When reporting your output (notes file at `$TASKS_DIR/notes/task-NN.md`), include:
- TDD-cycle outcome (RED → GREEN → REFACTOR), test adequacy check result, full-suite status
- If TDD was not feasible: a specific, valid reason (vague reasons + working test framework will be flagged by the reviewer)
