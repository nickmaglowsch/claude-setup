---
name: pr-review-feedback
description: "Triage line-level PR review comments from a specific reviewer and fix the ones that make sense — TDD-first, never commit, never reply on GitHub. Use when the user says any of: 'check <reviewer>'s comments', 'check latest comments of <reviewer>', 'fix what <reviewer> said', 'check kiawin/hilde/sian/calcacuervo/kawin comments', 'review feedback from X'. Defaults that always apply: only line-level comments (ones pointing to specific code lines), evaluate against PR description/goals before acting, TDD when fixing, no git commits, no GitHub replies — return everything to the user for review."
argument-hint: "<reviewer> [PR#]"
---

# PR Review Feedback Triage

You are processing line-level review comments from a specific reviewer on a PR. The user wants thoughtful triage — not blind compliance. The user posts review comments and pushes commits themselves; your job is to do the analysis and the code work, then hand back a report.

## Hard rules (these never change)

1. **Only line-level review comments** — the kind tied to a file:line. Ignore general PR comments, conversation comments, and review summaries.
2. **No commits.** Do not run `git commit`, `git push`, `gh pr merge`, or anything that writes to the remote.
3. **No GitHub replies.** Do not run `gh pr review`, `gh pr comment`, or post anything to the PR. Return your responses in chat for the user to copy or paste themselves.
4. **TDD when fixing.** For each comment you decide to act on, write a failing test that proves the bug/issue first, then implement the fix, then re-run the test.
5. **Judge against the PR description and goals**, not against the reviewer's authority. A reviewer can be wrong, off-topic, or asking for scope creep. Say so when that's the case.

## Inputs

Parse `$ARGUMENTS` for:
- `<reviewer>` — required. The GitHub login (or unique prefix) of the reviewer.
- `[PR#]` — optional. If absent, use the PR for the current branch.

## Step 1: Fetch the line-level comments

Use the bundled script — it filters for line-level comments by that user, newest first:

```bash
~/.claude/skills/pr-review-feedback/scripts/gh-line-comments-by <reviewer> [PR#]
```

For machine-readable output (preferred when there are many comments):

```bash
~/.claude/skills/pr-review-feedback/scripts/gh-line-comments-by <reviewer> [PR#] --json
```

Also fetch PR description and goals for context:

```bash
unset GITHUB_TOKEN && gh pr view <PR#> --json title,body,baseRefName,headRefName
```

If no PR# was given and the current branch has no PR, stop and tell the user.

## Step 2: Read each comment in context

For each comment:
1. Open the file at the line the comment points to. Read enough surrounding code to understand the comment.
2. If the comment references other files or symbols, read those too.
3. Note: a single reviewer thread may have follow-up comments — read them all before judging.

## Step 3: Triage each comment

Classify each comment into one of three buckets:

- **AGREE / WILL FIX** — the comment is correct and within scope of the PR. You will fix it via TDD.
- **DISAGREE / WON'T FIX** — the comment is wrong, off-topic, or out of scope. You will explain why in the report so the user can paste a reasoned response.
- **CLARIFY** — the comment is ambiguous or you need more info before deciding. Note what would unblock you.

Decide **per comment**, not in aggregate. A "won't fix" is just as valid as a "will fix" if backed by evidence from the code or PR description.

## Step 4: Implement AGREE fixes via TDD

For each AGREE comment:

1. Write a failing test that demonstrates the issue the reviewer raised (or the bug their suggestion would prevent). Run it — confirm it fails.
2. Implement the fix.
3. Re-run the test — confirm it passes.
4. Run any nearby related tests to check for regressions.
5. Do **not** commit. Leave the working tree dirty for the user to review.

If a fix turns out to be larger or riskier than expected mid-implementation, stop, mark the comment as CLARIFY in the final report, and surface the issue rather than charging ahead.

## Step 5: Hand back the report

Print a single report to chat in this shape:

```
PR #<N> — Review feedback from <reviewer> (<count> line-level comments)

[1] <file>:<line> — AGREE / WILL FIX
> <short quote of the comment>
Fix: <one-line summary of what you changed>
Test: <test name/file you added>

[2] <file>:<line> — DISAGREE / WON'T FIX
> <short quote of the comment>
Reasoning: <why — cite code, PR description, or existing conventions>
Draft reply (for the user to post if they agree):
    <2-3 sentences the user can paste back to the reviewer>

[3] <file>:<line> — CLARIFY
> <short quote of the comment>
Question: <what you need from the user or the reviewer>

Summary
- Fixed: <N> (uncommitted, ready for your review)
- Declined: <N>
- Needs clarification: <N>

Nothing was committed or posted to GitHub.
```

## Edge cases

- **Comment is on code you didn't touch in this PR.** Note it explicitly — it may be a drive-by request unrelated to the PR's goal. Default to DISAGREE with the rationale "out of scope for this PR" unless the user signals otherwise.
- **Comment is a question, not a request.** Treat it as CLARIFY and draft an answer for the user to post.
- **Comment is a suggestion (GitHub "suggested change" block).** Read the suggestion; treat it the same as any other comment — agree/disagree based on merit, not because it's pre-formatted.
- **The reviewer has multiple comments on the same line.** Group them into one entry in the report, but evaluate each point.
- **The reviewer is the PR author.** Rare, but happens with self-reviews. Same workflow — judge on merit.
- **`unset GITHUB_TOKEN`** before every `gh` call. The user's environment has a token that conflicts with `gh`'s auth.
