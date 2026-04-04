# Implementation Notes

## Task 01: Create agent-teams-orchestrator.md
- **Decisions**: Used `color: purple` to distinguish from `parallel-task-orchestrator` (orange). Added prominent IMPORTANT callout block at top to reinforce that this is a reference guide, not a spawnable sub-agent. Persistent memory path uses agent name (`agent-teams-orchestrator`) matching convention.
- **Deviations**: None.
- **Trade-offs**: Kept Phase 3 intentionally brief on API specifics (teammate spawn calls) since the API is experimental — added a prominent note directing implementers to Claude Code Agent Teams docs as authoritative reference.
- **Risks**: Agent Teams API is experimental; the orchestration instructions may need updating as the API stabilizes.

## Task 02: Update setup.sh CLAUDE_FILES array
- **Decisions**: Placed `agent-teams-orchestrator.md` before `app-scout.md` (alphabetical: `agent` < `app`). The task file suggested placing it after `app-scout.md`, but strict alphabetical order puts `agent-teams` first.
- **Deviations**: Task said "after app-scout, before bug-fixer" but strict alphabetical order requires it before app-scout. Followed alphabetical convention over the task's suggested position.
- **Trade-offs**: None.
- **Risks**: None.

## Task 03: Add mode selection to build/SKILL.md
- **Decisions**: Inserted Step 1.5 between Step 1e and Step 2 (the fast-path detection step). Modified Step 2 heading from "Run parallel-task-orchestrator" to "Run orchestrator" to be mode-neutral. The fast-path (`FAST_PATH=true`) direct implementation path is unchanged and unaffected by ORCHESTRATION_MODE — it only applies to the full-path case.
- **Deviations**: None.
- **Trade-offs**: Fast-path direct implementation bypasses mode selection implicitly — this is intentional since fast-path doesn't use an orchestrator at all.
- **Risks**: None.

## Task 04: Add mode selection to refactor/SKILL.md
- **Decisions**: Used `## Step 1.6:` heading (instead of 1.5) because refactor/SKILL.md already has a `## Step 1.5:` (safety net / test-writer step). Content of the orchestration mode selection block is identical to Task 03. Modified Step 2 heading from "Run parallel-task-orchestrator" to "Run orchestrator".
- **Deviations**: Heading number changed from 1.5 (as specified in task) to 1.6 to avoid name collision with existing Step 1.5. The body content and option text are identical.
- **Trade-offs**: Step 1.6 numbering is slightly non-standard but avoids ambiguity with the existing Step 1.5 safety net step.
- **Risks**: None.

## Task 05: Update README.md
- **Decisions**: Inserted the new section before `## Dev Container (Optional)` — the last section before end of file — as the task said "after build/refactor pipeline documentation and before Contributing or footer content". Used a two-sub-section structure (How to use it / Caveats) to match README's existing style.
- **Deviations**: None.
- **Trade-offs**: None.
- **Risks**: None.
