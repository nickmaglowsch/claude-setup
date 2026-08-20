---
name: ci-fix-loop
description: "Diagnose failing CI checks on the current branch's PR, reproduce them locally, fix the root cause, and verify locally before offering to push. Use when the user says any of: 'CI is red', 'PR CI is failing', 'check the PR CI', 'reviewer said tests are failing — rebase and fix', 'fix failing tests in CI', 'check why the PR is red'. Pulls failing-job logs via gh, isolates the failure, fixes with TDD when applicable, and reruns locally to confirm. Does NOT push by default — waits for explicit user confirmation."
---

# CI Fix Loop

The PR is red. Find out why, fix it, prove it locally, then hand control back to the user before pushing.

## Step 1: Identify the PR and failing checks

```bash
unset GITHUB_TOKEN
gh pr view --json number,title,headRefName,statusCheckRollup
```

If there's no PR for the current branch, stop and tell the user.

From `statusCheckRollup`, list every check with `conclusion` in (`FAILURE`, `TIMED_OUT`, `CANCELLED`). Ignore `SUCCESS`, `NEUTRAL`, `SKIPPED`, and anything still `IN_PROGRESS` / `PENDING` — unless the user explicitly asked about an in-progress check.

Report the failing checks back briefly before drilling in:

```
PR #<N> — failing checks:
- <check name> (<conclusion>)
- <check name> (<conclusion>)
```

## Step 2: Pull the failing logs

For each failing check, get the run ID and pull the failed-step logs:

```bash
gh run list --branch "$(git rev-parse --abbrev-ref HEAD)" --limit 5 --json databaseId,name,conclusion,headSha
gh run view <run-id> --log-failed
```

If the log is huge (>10k lines), narrow by job:
```bash
gh run view <run-id> --json jobs --jq '.jobs[] | select(.conclusion=="failure") | {name, databaseId}'
gh run view --job <job-id> --log-failed
```

Read enough log to identify the **first** real failure — not the cascade. CI logs usually have noise after the first failure (cleanup steps, summary failures, etc.); the root cause is at the top.

## Step 3: Classify the failure

- **Test failure** — an assertion failed or a test errored. Read the test, read the code under test.
- **Lint / type / format error** — usually mechanical to fix.
- **Build / dependency error** — missing dep, version mismatch, import error.
- **Environment / infra flake** — e.g., `connection refused`, `timeout`, `runner died`. If you suspect a flake, say so clearly — offer to rerun the job before fixing anything.
- **Stale base** — failure exists on develop too. Suggest running the `rebase-develop` skill first.

Before fixing, state your hypothesis in one line so the user can correct you if you're off track.

## Step 4: Reproduce locally

You must reproduce the failure locally before fixing. Otherwise you're guessing.

- **Python tests:** `pytest <path::test>` (or whatever the project uses — check `pytest.ini`, `pyproject.toml`, or a `Makefile`).
- **JS tests:** `npm test -- <path>` or `pnpm test <path>` or `vitest run <path>` depending on the project.
- **Lint/type:** run the exact command CI runs — look in the workflow file (`.github/workflows/*.yml`) if unsure.

If the test passes locally but fails in CI:
1. Check for environment differences (env vars, DB seed data, fixtures, timezone).
2. Check for ordering issues (does CI run tests in a different order? try `--randomly-seed=<seed>` from the CI log).
3. Check for develop drift — `git fetch origin develop && git log HEAD..origin/develop --oneline` may reveal a behind-base issue.
4. If still unreproducible after a reasonable effort, stop and report. Don't push a speculative fix.

## Step 5: Fix via TDD where it applies

- **Test failure with a real bug:** the failing test is already your TDD test. Fix the code, rerun the test, confirm green. Then run the surrounding test module to catch regressions.
- **Test failure where the test itself is wrong:** fix the test, but also add a positive test for the actual expected behavior so the next person knows the intent.
- **Lint / type / format:** apply the fix the tool suggests, then run the full lint/type command locally.
- **Build / dependency:** make the minimal change that resolves it. Don't bulk-upgrade dependencies.

## Step 6: Verify locally

Re-run **every** check you fixed, locally, and confirm green. If there were multiple failing checks, run each one's command.

If the project has a fast precommit / aggregate command (`make ci`, `pnpm check`, etc.), run that too.

## Step 7: Hand back the report — do NOT push

```
CI Fix Loop — PR #<N>

Failures diagnosed:
1. <check name> — <one-line root cause>
   Fix: <file>:<line> — <what changed>
   Verified locally: <command you ran>
2. ...

Files changed (uncommitted): <N>
- <file>
- <file>

Ready to commit & push when you say so.
```

Do **not** commit or push. Wait for the user.

## Push step (only when user explicitly says so)

When the user says "commit and push", "go push", "push it", etc., create a single focused commit and push. Use `--force-with-lease` only if you previously rebased; otherwise plain push.

Never push to `develop`, `main`, or `master`.

## Edge cases

- **Flake suspected:** don't fix code blindly. Rerun the failed job first: `gh run rerun <run-id> --failed`. If it goes green, tell the user the failure was a flake and stop.
- **Failure is in develop too:** the base branch is broken. Don't try to fix it from your branch — surface it and let the user decide.
- **Multiple unrelated failures:** fix them as separate steps, verify each one locally before moving on. If the diff is getting big, pause and check with the user.
- **`unset GITHUB_TOKEN`** before every `gh` call.
