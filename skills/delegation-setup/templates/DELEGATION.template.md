# DELEGATION — think before you hand off

Applies to EVERY agent creation: Paseo `mcp__paseo__create_agent`, the native Agent tool, and Workflow `agent()` calls.

## The rule

Before spawning any agent, classify the task and pick the model deliberately. Never inherit or default the model — always pass `provider` (Paseo) or `model` (native Agent/Workflow) explicitly. State the choice and a one-line reason before spawning (e.g. "normal impl → Claude workhorse").

Classify on two axes:

1. **Difficulty**: trivial / normal / hard / really-hard (resisted a first attempt, or clearly gnarly architecture).
2. **Role**: is this authoring work, or reviewing/challenging another agent's work?

## Tier ladder (stable names — no versioned IDs here)

| Tier | Use for |
|---|---|
| Claude frontier (`fable`) | Really-hard only: second attempts, gnarly architecture. Never routine work. |
| Claude workhorse (`opus`) | Default for implementation, UI, and authoring work. |
| Claude cheap (`sonnet` / `haiku`) | Research/search (`sonnet`); trivial mechanical work and tests (`haiku`). |
| OpenAI frontier (top Codex tier, thinking xhigh) | Hard contrarian analysis, high-stakes reviews, repeatedly inconclusive reviews. |
| OpenAI workhorse (default Codex tier) | Default contrarian reviewer and design challenger. |
| OpenAI cheap (mini Codex tier) | Trivial mechanical work when a Codex agent fits better. |

Native Agent/Workflow `model` values are the stable aliases: `haiku` / `sonnet` / `opus` / `fable`.

## Fan-out budget — how many, how deep

Picking the right *model* bounds the price per agent, not the total. Volume does that, and a quota blowup is almost always volume, not tier. Before fanning out, budget it:

- **Default caps:** ≤ 4 agents per wave, ≤ 8 per task total. Going wider needs an explicit "yes, go wide" from the user.
- **One level of fan-out.** A spawned agent does its own work — it does not spawn its own sub-agents unless you were told to go that deep. Recursive fan-out is how 4 agents silently become 40.
- **Fan out only if inline won't do.** A handful of web lookups or file reads is cheaper done inline than as a delegated fleet. First question: does this need sub-agents at all?
- **Scope to the deliverable, not the topic.** "One email with a pick and a price" is a couple of lookups, not a market study. Match width to what actually ships.
- **High stakes ≠ upgrade the whole fleet.** "This has to be accurate" justifies *one* workhorse/frontier verifier over cheap-tier gathered data — not the entire fleet on the frontier tier. Gather cheap, verify once.
- **Circuit-breaker.** If agents die on quota / rate-limit / API errors, STOP. Do not re-spawn into the same wall — surface the failure and wait for it to clear.
- **Use the smallest context window that fits.** A fleet of 1M-window agents multiplies cost independently of tier.

## Turn budget — the lever that actually bounds spend

Tier sets the price per token; **turns × context** sets the total. Context only grows, and every turn re-reads all of it, so cost is roughly quadratic in turn count: one 240-turn agent costs ~4× four 60-turn agents doing the same work. Measured on a real 23-agent wave, cache reads were 56% of spend, writes 29%, output+thinking 15% — the money is in re-reading context, not in thinking. Capping agent *count* does not cap spend; capping turns does.

- **~80 turns per agent.** Past that, have it write findings to a handoff file and spawn a successor that reads the file instead of inheriting the history.
- **Keep tool output out of context.** `head`/`tail`/`grep -c`/`--quiet` on build, test, and log output; read the line ranges you need, not whole files. Every dumped blob is re-read on every later turn of that agent.
- **Brief tight, scope narrow.** An agent forced to rediscover the codebase pays for that discovery on every subsequent turn.
- **Orchestrator hygiene.** The orchestrator pays its own full context every turn too. One session per wave, resuming from a committed scaffold plus a notes file, beats one session spanning every wave.
- **Spend is concentrated, so audit the tail.** In that wave the top 6 of 23 agents were half the cost. Fix the few fat agents, not the fleet average.

## Reuse before respawn

A finished agent is still alive and still holds its context. The next slice of the same work, a correction, or a review's fix-ups go back to *that* agent — a fresh one pays the context-rebuild cost again and throws away everything the first one learned.

- **Follow-up on the same thread → `mcp__paseo__send_agent_prompt`** (native equivalent: `SendMessage` to the existing agent). Review came back? Send it to the author. Don't spawn author #2.
- **Spawn new only when** the tier must change, the task is genuinely unrelated, the agent's context is poisoned and it can't back out, or it has hit the turn budget above.
- **Kill/archive only when done for good.** Killing an agent you're about to re-create at the same tier is pure loss.
- A respawn counts against the fan-out cap; a follow-up doesn't. But a follow-up isn't free either — it re-reads the whole thread, which is exactly what the turn budget prices. Check `get_agent_status` → `lastUsage.contextWindowUsedTokens` before piling on: reuse a small thread, hand off a big one.
- Workflow `agent()` calls are one-shot by design — this rule is about interactive fan-out.

## Contrarian pairing

Substantive work authored by a Claude agent gets its review from a Codex agent, and vice versa — cross-family review catches blind spots same-family review misses. Frontier-vs-frontier (Fable vs top Codex tier) only to settle hard disagreements.

The native Agent tool cannot select Codex/OpenAI models — it runs Claude models only. So it can be the cross-family reviewer for Codex-authored work, but never for Claude-authored work: route those through Paseo `create_agent`.

## Where the concrete bindings live

Versioned model IDs and the Paseo role→provider map live ONLY in `~/.paseo/orchestration-preferences.json` (read it before any Paseo agent creation — the paseo skills already require this). Keep them fresh with `/delegation-audit` (suggested cadence: every 2 weeks).
