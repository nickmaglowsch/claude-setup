---
name: rebase-develop
description: "Rebase the current branch onto origin/develop, auto-resolve trivial conflicts, and summarize non-trivial ones for the user. Use when the user says 'rebase develop', 'rebase with develop', 'rebase origin/develop', 'rebase develop to this branch', 'rebase develop here', or similar. Does NOT push by default — waits for an explicit 'go push' (or '--force-with-lease') from the user before pushing. Always runs git fetch first."
---

# Rebase onto origin/develop

Rebase the current branch on top of the latest `origin/develop`. Be helpful with conflicts but never push without explicit user confirmation.

## Step 1: Preflight

Run these in parallel:

```bash
git rev-parse --abbrev-ref HEAD                   # current branch name — fail if it's develop or main
git status --short                                # check for uncommitted/staged work
git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null || echo "NO_REMOTE_TRACKING"
```

Stop and ask the user if:
- The current branch is `develop`, `main`, or `master`.
- `git status` shows uncommitted changes (offer: stash first, or abort).

## Step 2: Fetch

```bash
git fetch origin develop
```

If fetch fails with credential/auth issues (common with AWS SSO), tell the user — they may need to run `aws sso login --profile bcp_engineer` themselves.

## Step 3: Rebase

```bash
git rebase origin/develop
```

If the rebase completes cleanly, jump to Step 5.

## Step 4: Handle conflicts

For each conflict reported:

1. Read both sides of the conflict using `git diff` and by opening the file.
2. Classify the conflict:
   - **Trivial** — import-order changes, whitespace, formatting, both sides added different items to the same list/dict without semantic overlap, lockfile changes where the develop side is newer. Resolve these yourself.
   - **Non-trivial** — both sides changed the same logic, schema, or behavior. **Do not guess.** Leave the conflict markers in place and summarize for the user.
3. After resolving trivial conflicts in a file:
   ```bash
   git add <file>
   ```
4. Once all *trivial* conflicts are staged, continue:
   ```bash
   git rebase --continue
   ```
   If non-trivial conflicts remain, **stop** and report them — do not call `--continue` with unresolved files.

If you get stuck or the rebase becomes a mess, offer the user `git rebase --abort` rather than thrashing.

## Step 5: Verify

```bash
git status                                        # working tree should be clean
git log --oneline origin/develop..HEAD            # commits now on top of develop
```

## Step 6: Hand back a summary — do NOT push

Report in this shape:

```
Rebase onto origin/develop: <success | conflicts pending | aborted>

Commits on top of develop: <N>
<short hash> <message>
<short hash> <message>
...

Conflicts auto-resolved (trivial): <N>
- <file>: <one-line description>

Conflicts needing your review (non-trivial): <N>
- <file>:<line range>: <description of the disagreement between your branch and develop>

Branch is <ahead | diverged> by <N> from origin/<branch>.
Ready to push with --force-with-lease when you say 'go push'.
```

Do **not** push. Wait for the user.

## Push step (only when user explicitly says so)

Trigger when the user says any of: "go push", "push it", "push with --force-with-lease", "push --force-with-lease", "yes push".

```bash
git push --force-with-lease
```

Never use plain `--force`. Never push to `develop`, `main`, or `master`. If the remote rejects `--force-with-lease` because someone else pushed, stop and tell the user — do not retry with `--force`.
