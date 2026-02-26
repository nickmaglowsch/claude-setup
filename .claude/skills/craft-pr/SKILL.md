---
name: craft-pr
description: "Reads task files from tasks/ and the diff against origin/main, then generates a polished PR description in markdown for the user to copy-paste."
argument-hint: "[optional: extra context or PR title]"
---

# Craft PR Description

You are generating a high-quality pull request description. Follow these steps strictly.

## Extra context from the user

$ARGUMENTS

## Step 1: Gather context

Run **all** of the following in parallel using the Bash tool:

1. **Current branch name**
   ```
   git rev-parse --abbrev-ref HEAD
   ```

2. **Diff summary (stat) against origin/main**
   ```
   git diff --stat origin/main...HEAD
   ```

3. **Full diff against origin/main**
   ```
   git diff origin/main...HEAD
   ```

4. **Commit log since diverging from origin/main**
   ```
   git log --oneline origin/main..HEAD
   ```

5. **Read all files in the `tasks/` directory** using the Read tool (read every `.md` file found via Glob `tasks/*.md`).

## Step 2: Analyze

From the gathered context, identify:

- **What** changed: features added, bugs fixed, refactors done
- **Why** it changed: map changes back to task files when possible
- **Scope**: which apps/packages were touched
- **Risk areas**: migrations, API changes, new dependencies, config changes
- **PR type**: determine if this is a **feature** PR (adds new user-facing functionality), a bug-fix PR, a refactor, etc.

## Step 2b: Feature discovery (feature PRs only)

If this is a feature PR, examine the diff and task files more deeply to identify every **new user-facing feature**. For each feature determine:

1. **What it does** — a plain-language description of the feature from the end-user's perspective.
2. **Where it lives in the app** — the route/page/section where the user can find it (e.g., "Sidebar → Outreach", "/intel/settings page", "new cron job at `/api/cron/...`").
3. **How to use it** — brief step-by-step or description of the interaction flow (e.g., "Click 'Generate Hook', fill in the form, and the AI will produce a hook for the deal").

Read any new page/component files from the diff if needed to accurately describe navigation and usage.

## Step 3: Generate the PR description

Output a single markdown block the user can copy-paste. Use this template:

````markdown
## Summary

<!-- 2-4 sentence high-level overview of what this PR does and why -->

## Features

<!-- INCLUDE THIS SECTION ONLY FOR FEATURE PRs. Remove it entirely for bug-fix / refactor PRs. -->
<!-- For each new user-facing feature, describe what it does, where to find it, and how to use it. -->

### <Feature Name>
**Where:** <route / page / sidebar section where the user accesses this>
**What it does:** <plain-language description>
**How to use it:**
1. Step one
2. Step two
3. ...

### <Feature Name 2>
...

## Changes

<!-- Bulleted list of meaningful changes, grouped by area if needed -->

### <Area 1>
- Change description

### <Area 2>
- Change description

## Related Tasks

<!-- Link each task file that is relevant to the changes -->
- `task-01-...md` — brief description of what it covers
- `task-02-...md` — brief description of what it covers

## Risk & Review Notes

<!-- Anything reviewers should pay extra attention to -->
- ...

## Test Plan

<!-- How to verify these changes work -->
- [ ] ...
- [ ] ...
````

## Rules

- Keep the summary concise — no more than 4 sentences.
- **Features section**: Only include for feature PRs. For each feature, always specify the concrete route/page/UI location and a clear usage flow. Read new page or component files if needed to get this right. Remove the section entirely for non-feature PRs.
- In the **Changes** section, focus on *what matters to a reviewer*, not every single line changed. Group logically.
- Only reference task files that are actually relevant to the diff. If a task has no matching changes, skip it.
- If there are database migrations, flag them prominently in Risk & Review Notes.
- If there are new environment variables or config changes, list them explicitly.
- Output the final markdown inside a single fenced code block so the user can copy it easily.
- Do NOT create a PR or push anything. Just output the description.
