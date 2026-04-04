# Code Review Report

## Summary

The implementation is solid and nearly complete. All six PRD requirements are addressed with consistent, well-structured changes across all five files. One Important issue (fast-path bypassing Agent Teams mode silently) and a few Minor issues need attention, but nothing blocks shipping.

## PRD Compliance

| # | Requirement | Status | Notes |
|---|-------------|--------|-------|
| R1 | Mode Selection Prompt in both SKILLs | ✅ Complete | Identical block in build (Step 1.5) and refactor (Step 1.6). Uses `AskUserQuestion`, two options, stores `ORCHESTRATION_MODE`. |
| R2 | Agent Teams Orchestrator Agent File | ✅ Complete | `.claude/agents/agent-teams-orchestrator.md` — 202 lines covering all 4 phases (Discovery, Dependency Analysis, Execution, Completion). Includes dependency graph, wave logic, teammate prompt template, retry logic, implementation-notes.md and execution-metrics.md output. |
| R3 | Skill-Level Agent Teams Execution | ✅ Complete | Both SKILLs explicitly say "Do NOT spawn a sub-agent. Instead, execute Agent Teams orchestration directly in this session." Agent file has prominent IMPORTANT callout reinforcing it is a reference guide, not a spawnable sub-agent. |
| R4 | Runtime Env Var Setup | ✅ Complete | Both SKILLs include the settings file lookup chain (`~/.claude/settings.json` -> `.claude/settings.json` -> `.claude/settings.local.json`) with merge-preserving semantics and fallback creation. |
| R5 | setup.sh Update | ✅ Complete | `agent-teams-orchestrator.md` added to `CLAUDE_FILES` array in alphabetical position (before `app-scout.md`). |
| R6 | README Documentation | ✅ Complete | New "Agent Teams Mode (Beta)" section with How-to and Caveats sub-sections. Documents env var, settings file lookup, beta status, and per-task commit fallback. |

**Compliance Score**: 6/6 requirements fully met

## Issues Found

### Critical (must fix before shipping)

None.

### Important (should fix)

- **`.claude/skills/build/SKILL.md:133-149` (Step 1e fast-path)**: The mode selection (Step 1.5) happens *before* fast-path detection (Step 1e). If the user selects Agent Teams mode but fast-path is triggered (`FAST_PATH=true`), the fast-path direct implementation section makes no mention of `ORCHESTRATION_MODE` — it always executes tasks directly in the current session. This means:
  1. The user explicitly chose Agent Teams but gets direct implementation instead, with no indication their choice was overridden.
  2. The env var was already set in settings.json (Step 1.5 side-effect) but is never used, leaving a stale config artifact.

  **Recommendation**: Either (a) move mode selection after fast-path detection so it only triggers on the full path, or (b) add a note in the fast-path section: "If `ORCHESTRATION_MODE=agent-teams` was selected, inform the user that fast-path direct implementation is being used instead (Agent Teams orchestration adds overhead for simple tasks)." Option (a) is cleaner since it avoids the stale env var issue entirely.

  Note: The refactor SKILL does NOT have a fast-path step, so this issue is build-only.

### Minor (nice to fix)

- **`.claude/agents/agent-teams-orchestrator.md:5`**: The frontmatter specifies `model: sonnet` but this file is documented as a reference guide, not a spawnable agent. The `model` field is irrelevant for a reference guide and could be misleading — someone might think it can be spawned. Consider removing it, or adding a comment that it is ignored.

- **`.claude/agents/agent-teams-orchestrator.md:68-97`**: Phase 3 uses `TaskCreate`/`TaskUpdate`/`TaskUpdate` for progress tracking but does not mention how teammates are actually spawned. The PRD mentions `TeamCreate`/`TeamAddMember` as the expected API. The note about experimental API is appropriate, but naming the expected API calls (even as examples) would make this more actionable. Currently the only guidance is "Use Claude Code's Agent Teams API to spawn one teammate per task."

- **`README.md:319`**: The env var is shown as a bare `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` without clarifying it goes inside a JSON `"env"` object in settings files. A user reading only the README might try to export it in their shell. Consider showing the JSON structure:
  ```json
  { "env": { "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1" } }
  ```

- **`README.md:328`**: The caveat "Higher token usage than the default sub-agent approach" is stated without qualification. This may or may not be true depending on the workload. Consider softening to "May result in higher token usage" or removing if not verified.

## What Looks Good

- **Consistent mode selection block**: The AskUserQuestion prompt text, option descriptions, variable name, and env var setup logic are identical between build and refactor SKILLs. Good discipline.
- **Implementation notes are thorough**: The implementer documented the Step 1.6 numbering deviation (refactor has existing Step 1.5) and the alphabetical ordering decision in setup.sh. Both are reasonable.
- **Agent Teams orchestrator is comprehensive**: Covers all four phases, includes retry logic with a one-retry limit, has the per-task commit fallback note, and maintains the same output contract (implementation-notes.md + execution-metrics.md) as the existing parallel-task-orchestrator.
- **Prominent "not a sub-agent" callout**: The blockquote at the top of agent-teams-orchestrator.md is clear and well-placed — reduces risk of misuse.
- **Per-task commit fallback**: Both SKILLs and the orchestrator file consistently document that per-task commits fall back to squash in Agent Teams mode. No contradictions across files.
- **Settings file merge semantics**: The instructions correctly specify read-merge-write with preservation of existing settings, matching the PRD's risk flag.

## Test Coverage

| Area | Tests Exist | Coverage Notes |
|------|-------------|----------------|
| Mode selection prompt | N/A | SKILL.md files are declarative agent instructions, not executable code — no test framework applies |
| Agent Teams orchestrator | N/A | Reference guide document — not testable in the traditional sense |
| setup.sh array update | No | Could be tested with a shell script that sources setup.sh and checks the array, but this is a one-line change |

**Test Coverage Assessment**: PRD explicitly states "TDD: No TDD mode" — no tests are expected or applicable. The changes are all to declarative markdown instruction files and a shell script array entry. Standard test coverage is not applicable here.

## Implementation Decision Review

| Task | Decisions Documented | Decisions Sound | Flags |
|------|---------------------|----------------|-------|
| Task 01: agent-teams-orchestrator.md | Yes | Yes | Phase 3 API vagueness is intentional given experimental status |
| Task 02: setup.sh | Yes | Yes | Alphabetical ordering over task-suggested position is correct |
| Task 03: build/SKILL.md Step 1.5 | Yes | Partially | Fast-path interaction not addressed (see Important issue above) |
| Task 04: refactor/SKILL.md Step 1.6 | Yes | Yes | Step 1.6 numbering to avoid collision is the right call |
| Task 05: README.md | Yes | Yes | Placement and structure match existing README style |

**Decision Assessment**: Implementers made sound decisions overall. The alphabetical ordering and step-number collision avoidance show good attention to existing conventions. The one gap is the fast-path/Agent-Teams interaction in the build SKILL, which is not documented in the implementation notes — likely an oversight rather than a deliberate choice.

## Recommendations

1. **(Important)** Address the fast-path + Agent Teams interaction in build/SKILL.md — either reorder the steps or add explicit handling. See the detailed recommendation in Issues above.
2. **(Minor)** Consider showing the JSON settings structure in the README so users understand the env var format.
3. **(Minor)** Remove or comment the `model: sonnet` frontmatter field from agent-teams-orchestrator.md since it is a reference guide.
4. **(Minor)** Add example Agent Teams API call names in Phase 3 of the orchestrator, even if marked as experimental placeholders.
