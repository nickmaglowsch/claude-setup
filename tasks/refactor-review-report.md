# Code Review Report

## Summary

The refactoring is well-executed and ready to ship. All four tasks from the plan are implemented correctly, source and global copies match exactly, changes are minimal and focused, and the python3 save snippet is safe. One important issue found: the hardcoded `'parallel'` placeholder in the python3 snippet is a trap for literal-minded executors and could be made more robust. One minor issue: when the user is already on `main`, two of the three base-branch options may be identical.

## PRD Compliance

| # | Requirement | Status | Notes |
|---|-------------|--------|-------|
| 1 | Task 01: build/SKILL.md Step 0.1 — fetch from origin before branch creation | Complete | `git fetch origin` added before checkout |
| 2 | Task 01: build/SKILL.md Step 0.1 — ask user which base branch | Complete | Three-option prompt with default branch detection and fallback |
| 3 | Task 01: build/SKILL.md — edit both source repo and global install | Complete | Both files identical (verified via diff) |
| 4 | Task 02: refactor/SKILL.md Step 0.1 — same branch fix | Complete | Identical pattern adapted for `refactor/` slug |
| 5 | Task 02: refactor/SKILL.md — edit both source and global | Complete | Both files identical |
| 6 | Task 03: debug-workflow/SKILL.md Step 0.1 — branch fix with `fix/` slug | Complete | Correct slug prefix, no COMMIT_MODE question preserved, step numbering adjusted (step 3 not step 4) |
| 7 | Task 03: debug-workflow/SKILL.md — edit both source and global | Complete | Both files identical |
| 8 | Task 03: debug-workflow structurally different — no COMMIT_MODE | Complete | Parenthetical note preserved: "(No commit granularity question -- debug always uses a single commit.)" |
| 9 | Task 04: build + refactor Step 0.2 — read `~/.claude/user-preferences.json` before asking | Complete | `cat ~/.claude/user-preferences.json 2>/dev/null` with key check |
| 10 | Task 04: Step 0.2 — skip question if saved preference exists | Complete | Log message, set var, skip rest of step |
| 11 | Task 04: Step 0.2 — ask "Save as default?" after user answers | Complete | Prompt added after mode selection |
| 12 | Task 04: Step 0.2 — write/update file preserving existing keys | Complete | python3 read-merge-write snippet with `os.path.exists` guard |
| 13 | Task 04: debug-workflow has no orchestration step | Complete | Correctly not modified |
| 14 | `git symbolic-ref` fallback if HEAD not set | Complete | `2>/dev/null` with "If empty or error, default to `main`" |
| 15 | Both source and global install edited for all three skills | Complete | All three pairs verified identical |
| 16 | No changes to files outside the three SKILL.md files | Complete | `git diff --stat` shows exactly 3 files changed |

**Compliance Score**: 16/16 requirements fully met

## Issues Found

### Critical (must fix before shipping)

None.

### Important (should fix)

- **`.claude/skills/build/SKILL.md:68`** and **`.claude/skills/refactor/SKILL.md:64`**: The python3 snippet hardcodes `'parallel'` as the value with a comment saying "replace with actual ORCHESTRATION_MODE value". While there is a parenthetical note after the code block instructing substitution, the skill executor (an LLM) must interpret a code comment and a prose instruction to modify the snippet before running it. This is fragile. A more robust approach would use a clear template variable like `$ORCHESTRATION_MODE` in the python3 string, or explicitly state in the prose "You MUST replace the string `'parallel'` in line N with the actual value before executing." The current formulation relies on two separate hints (inline comment + post-block note) which increases the chance one is overlooked, causing the preference to always save as `parallel`. The implementation notes acknowledge this risk and note the comment was added specifically to mitigate it, which is reasonable -- but a template variable would be safer.

### Minor (nice to fix)

- **`.claude/skills/build/SKILL.md:33-34`** (and equivalent in refactor/debug-workflow): When the user is already on `main` and `DEFAULT_BRANCH` is also `main`, Option 1 and Option 2 in the base-branch prompt will be identical (`main (remote default)` and `main (current branch)`). This is not a bug -- the user can pick either -- but it is slightly confusing UX. Consider collapsing to two options when `CURRENT_BRANCH == DEFAULT_BRANCH`.

- **`.claude/skills/build/SKILL.md:26`**: The old step 4 would run `git checkout -b` even when `BRANCH_ACTION=current`, which was arguably a latent bug (creating a new branch after the user said "commit here"). The new version correctly guards checkout behind `BRANCH_ACTION=new`. This is a behavior fix, not purely a refactor. It is the right fix, but worth noting for changelog accuracy -- it is not a "no behavior change" refactor.

## What Looks Good

- **Consistency across files**: The branch creation block is structurally identical in build, refactor, and debug-workflow (with appropriate adjustments for slug prefix and step numbering). This makes future maintenance straightforward.
- **Graceful fallback chain**: `git symbolic-ref` with `2>/dev/null` piped through `sed`, falling back to `main` if empty. This handles the common failure mode (no origin HEAD ref) cleanly.
- **python3 JSON merge is safe**: `json.load(open(path)) if os.path.exists(path) else {}` correctly handles missing file. `json.dump` with `indent=2` produces readable output. Existing keys in the file are preserved because only `orchestrationMode` is set.
- **Minimal diff**: 74 insertions, 8 deletions across 3 files. No unrelated changes anywhere. Every modified line serves one of the four tasks.
- **debug-workflow correctly differs**: No COMMIT_MODE question, `fix/` slug, step numbered 3 instead of 4 -- all structural differences from the original are preserved.
- **Source and global copies are byte-identical** for all three skills.
- **Implementation notes are clear and complete**: Each task has documented decisions, deviations (none), trade-offs, and risks.

## Test Coverage

| Area | Tests Exist | Coverage Notes |
|------|-------------|----------------|
| SKILL.md files (markdown instructions) | N/A | These are natural-language skill files, not executable code -- unit tests are not applicable |

**Test Coverage Assessment**: Not applicable. The changed files are markdown-based skill instructions that are interpreted by an LLM at runtime. There is no executable code to test in the traditional sense.

## Test Execution

| Check | Result | Details |
|-------|--------|---------|
| Test command discovered | No | No package.json, Makefile, pytest.ini, pyproject.toml, or go.mod found |
| Test suite run | Skipped | No test infrastructure detected |
| TDD evidence in implementation notes | N/A | TDD mode was not specified for this refactoring |

**Test Execution Assessment**: No test infrastructure exists in this project. The changes are to markdown skill files, so automated testing is not applicable.

## Implementation Decision Review

| Task | Decisions Documented | Decisions Sound | Flags |
|------|---------------------|----------------|-------|
| Task 01: build branch fix | Yes | Yes | None |
| Task 02: refactor branch fix | Yes | Yes | None |
| Task 03: debug-workflow branch fix | Yes | Yes | Correctly preserved structural differences |
| Task 04: orchestration preference | Yes | Mostly | python3 placeholder approach works but is fragile (see Important issue above) |

**Decision Assessment**: The implementer made sound decisions throughout. The choice to use `python3 -c` for JSON merge is pragmatic and handles the missing-file case correctly. The inline comment in the python3 snippet is a reasonable mitigation for the hardcoded placeholder, though a template variable would be more robust. All four tasks were implemented with appropriate attention to the structural differences between the three skill files.

## Recommendations

1. **Consider replacing the hardcoded `'parallel'` in the python3 snippet** with a template variable like `$ORCHESTRATION_MODE` or at minimum strengthen the substitution instruction to be more directive (e.g., "You MUST replace `'parallel'` with the actual value before running").
2. **Note in any changelog** that the `BRANCH_ACTION=current` path now correctly skips branch creation -- this is a behavior fix, not a pure refactor.
3. **Optionally** collapse the base-branch prompt to two options when `CURRENT_BRANCH` equals `DEFAULT_BRANCH` to avoid presenting duplicate choices.
