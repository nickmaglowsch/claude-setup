---
name: grill-me
description: Interview the user relentlessly about a plan or design until reaching shared understanding, resolving each branch of the decision tree. Use when the user wants to stress-test a plan, get grilled on their design, or mentions "grill me". Run BEFORE /claude-setup:build when a feature idea is fuzzy and a PRD doesn't yet exist.
---

Interview the user relentlessly about every aspect of this plan until you reach a shared understanding. Walk down each branch of the design tree, resolving dependencies between decisions one-by-one. For each question, propose your recommended answer so the user can accept, override, or refine.

## Rules

- **One question at a time.** Wait for the user's answer before moving on. Do not batch.
- **Recommend an answer with each question.** "I'd default to X because Y — agree?" Forces the user to commit or counter; pure open-ended questions stall.
- **If a question can be answered by exploring the codebase, explore the codebase instead.** Don't ask the user about things that can be read.
- **Keep questions short and concrete.** No multi-paragraph preambles. The user is here to be grilled, not lectured.
- **Stop when you've reached the leaves.** When every branch of the decision tree is resolved or explicitly deferred, summarize the decisions and offer to convert them into a PRD via `/claude-setup:build` (or hand off to `/claude-setup:grill-with-docs` if the project has a `CONTEXT.md`).

## Output at the end

A short bulleted list of the decisions reached, plus any explicitly-deferred questions. The user will paste this into `/claude-setup:build` (or you can offer to invoke it directly).
