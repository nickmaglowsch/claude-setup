---
name: visual-plan
description: "Turn an EXISTING plan into a single self-contained HTML page with editable Excalidraw diagrams, side-by-side options, and open questions — built to be screen-shared in a meeting. Decisions picked and diagrams redrawn during the meeting export back as JSON to hand to any implementer. The input is a plan that already exists: a PRD or spec file, notes from a design or grilling session, or just the plan that emerged in the current conversation (pass no arguments for that). Use when the user wants to present, visualise, or get sign-off on an architectural or business decision, asks for a decision doc / one-pager / diagram of a plan, or says to turn what we just worked out into something showable."
argument-hint: "<plan description, path to a PRD/notes file, or nothing to use the current conversation>"
---

# Visual plan

Produces `visual-plan.html`: one self-contained file, opens in any browser, no build step, no project setup. Diagrams are **live Excalidraw canvases** — anyone in the meeting can drag boxes, draw a new arrow, or scribble a note on them. Decisions are side-by-side option cards with radios; open questions have answer fields.

In the meeting people pick and redraw; **Export decisions** dumps JSON — the settled choices *and* the diagram as it ended up — to hand to whoever (or whatever) implements it.

Tool-agnostic on purpose: the output is a plain HTML file and a plain JSON blob. No dependency on any particular agent, repo layout, or workflow.

## Step 1: Gather

This skill **presents thinking that already happened** — it is the last step before the meeting, not the first step of the design. `$ARGUMENTS` is one of:

- **Nothing** → use the plan that emerged in the current conversation. This is the common case: you just worked something out together and the user wants it showable.
- **A file path** → a PRD, spec, ADR draft, or the notes from a design/grilling session. Read it.
- **A description** → a paragraph of what the decision is about.

If it names a codebase concern, explore read-only first (Glob/Grep/Read) so the diagrams show the **real** modules and the options are grounded in what's actually there. A diagram of imagined components is worse than no diagram.

Don't interview the user here — no discovery questions, no requirements gathering. If the input is too thin to have any real decisions in it, say exactly what's missing and ask for it, rather than inventing choices to fill the page.

## Step 2: Fill the template

Read `template.html` from this skill's directory. Replace exactly two placeholders:

- `PLAN_TITLE` → the title text
- `PLAN_JSON` → the plan object below

Change nothing else. The template renders whatever the JSON contains; every key is optional except `title`.

```json
{
  "title": "Session storage for the new auth service",
  "subtitle": "Platform team · decision review",
  "date": "2026-07-25",
  "context": "One paragraph a newcomer can read cold: what forced this decision, and what happens if we don't make it.",
  "diagrams": [
    { "title": "Today", "mermaid": "flowchart LR\n  A[Client] --> B[API]\n  B --> C[(Postgres)]",
      "caption": "One line on what the diagram is showing." }
  ],
  "decisions": [
    {
      "id": "session-store",
      "question": "Where do sessions live?",
      "why": "Drives failover behaviour and the on-call story.",
      "status": "open",
      "recommended": "redis",
      "options": [
        { "id": "redis", "label": "Redis", "pros": ["Sub-ms reads", "Ops already run one"],
          "cons": ["New failure domain"], "effort": "3d", "risk": "low" },
        { "id": "pg", "label": "Postgres table", "pros": ["Zero new infra"],
          "cons": ["Write amplification on every request"], "effort": "1d", "risk": "med" }
      ]
    }
  ],
  "openQuestions": [
    { "id": "gdpr", "q": "Does legal need session data in the EU region?",
      "why": "Changes the deploy topology.", "blocking": true, "owner": "Ana" }
  ],
  "nextSteps": ["Spike Redis failover — 2 days", "Draft the migration ticket"]
}
```

Field rules:
- `risk`: `low` | `med` | `high` (colours the label). `effort`: free text, keep it to a couple of words.
- `status`: `open` | `decided` | `deferred`.
- `recommended` is an option `id` — always set one. A page that just lists options makes the room argue from zero; a recommendation gives them something to attack, which is faster.
- Every option needs at least one **con**. An option with no downside is a decision you already made, so cut it and say so in `context`.
- `mermaid` is raw Mermaid source with `\n` newlines — it is only the *seed* for the drawing.

## Step 3: Diagrams

You author Mermaid; the page converts it to an Excalidraw scene on load, so the room gets a hand-drawn, directly editable diagram without you placing a single coordinate.

- **`flowchart`, `sequenceDiagram`, and `classDiagram` convert to editable shapes.** Other Mermaid types render as a flat image inside the canvas — usable, but nobody can restructure them, so prefer the three above for anything the meeting will argue about.
- **1–3 diagrams, max.** Each must carry the decision — a before/after pair, or the one flow the argument is actually about. Nothing decorative.
- **Under 8 nodes per diagram.** A box-per-class diagram is unreadable on a shared screen, and unusable to edit live. Collapse detail until only the contested part has resolution.
- Leave room. People will add boxes during the call — that's the point.
- Each diagram has a **Full screen** button. When the argument turns into a whiteboard session, that's the button; Esc comes back to the page with the edits kept.

To reuse a drawing instead of re-deriving it, pass a saved scene rather than Mermaid:

```json
{ "title": "Proposed", "scene": { "elements": [ … ] } }
```

`scene` wins over `mermaid` when both are present. Get one from the editor's hamburger menu → **Save to disk**, which writes a `.excalidraw` file; paste its `elements` array in.

## Step 4: The rest of the page

- **3–6 decisions.** More than that and it's a document, not a meeting. Split it or fold the small ones into `context`.
- **2–3 options per decision.** Include the honest do-nothing option when it's real.
- Write for someone reading it cold at 40% attention on a call: short sentences, concrete numbers, no internal shorthand.
- Business framing goes in `why` (cost, risk, who's blocked); technical framing goes in the option pros/cons.

## Step 5: Write and open

Write to the path the user asked for. Otherwise `./visual-plan.html` in the working directory — one file, no directory scaffolding.

Offer to open it: `xdg-open <path>` (Linux) / `open <path>` (macOS) / `start <path>` (Windows).

Report the path and a one-line inventory: *"3 decisions, 2 diagrams, 1 blocking question."*

React, Excalidraw and the Mermaid converter load from CDNs, so the first render needs a network connection. Say so if the meeting might be offline — the page degrades to the Mermaid source as readable text, and the decisions still work.

## Step 6: Round trip back

Tell the user, in one line: after the meeting, hit **Export decisions** and paste the JSON back to whoever implements the plan.

The export looks like this:

```json
{
  "title": "…",
  "diagrams": [
    { "title": "Proposed", "edited": true,
      "nodes": ["Clients", "nginx", "rate limiter", "api service"],
      "edges": ["Clients -> nginx", "nginx -> rate limiter", "rate limiter -> api service [under limit]"],
      "notes": ["put the limiter behind the LB, not in front"] }
  ],
  "decisions": [{ "id": "session-store", "chosen": "redis", "note": "ops agreed to own it" }],
  "answers": [{ "id": "gdpr", "answer": null }]
}
```

When you receive it:
- `decisions[].chosen` + `note` → settled constraints. Treat them as decided; don't re-litigate.
- `diagrams[]` with `edited: true` → **the room changed the architecture.** `edges` and `notes` are the authority; where they contradict the prose in the original plan, the drawing wins, because it's the newer decision. Reconcile before writing code, and say what changed.
- `answers[]` with a non-null answer → resolved. `null` on a `blocking` question → **stop and ask**; that one blocks implementation.

To revise the page instead, edit the `PLAN_JSON` blob in place — the markup below it never needs to change.
