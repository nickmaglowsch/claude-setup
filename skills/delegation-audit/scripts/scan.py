#!/usr/bin/env python3
"""Delegation audit scanner.

Stateless: walks Claude Code session transcripts, extracts agent-creation
tool calls (paseo create_agent + native Agent/Task tool) and downstream
friction signals that suggest the WRONG MODEL was chosen. Emits a plain-text
report; an LLM triages it afterwards. Zero LLM tokens spent here.

Also flags fan-out VOLUME, not just per-agent model choice: a quota blowup is
almost always too many agents (often recursive), not the wrong tier. So it
counts agent creations per session and quota/rate-limit deaths, including
re-spawns that fired after a death (circuit-breaker violations).

And it measures where the tokens ACTUALLY went, from the `usage` already in
every transcript line. Tier and agent count bound the price per agent; what
bounds the total is turns x context size, because context grows monotonically
and every turn re-reads all of it. Measured on a real 23-agent wave: cache
reads 56% of spend, cache writes 29%, output+thinking 15% — so the lever is
context hygiene, not effort. Subagent transcripts are included (that is where
most of the spend lives), which also makes recursive fan-out visible.

Still NOT counted (noisy — usually bad task packaging): raw retry counts, long
runtimes, test failures, generic permission errors.
"""

import argparse
import json
import os
import re
import sys
import time
from collections import Counter

CREATE_TOOLS = {"mcp__paseo__create_agent"}
NATIVE_AGENT_TOOLS = {"Agent", "Task"}
REUSE_TOOLS = {"mcp__paseo__send_agent_prompt", "SendMessage"}
# `subagents/` is deliberately NOT skipped: it holds most of the token spend,
# and it is the only place a recursive fan-out is visible.
SKIP_DIRS = {"tool-results", "memory"}

# Default transcript roots: native Claude sessions AND Paseo/ccs agent sessions.
# Paseo agents live outside ~/.claude/projects, so scanning only the former is
# blind to exactly the agents that fan out. A missing root yields nothing, so
# listing both is safe everywhere.
DEFAULT_ROOTS = [
    os.path.expanduser("~/.claude/projects"),
    os.path.expanduser("~/.ccs/shared/context-groups"),
]

# More than this many agent creations in one session is worth a look
# (DELEGATION.md caps a task at 8 agents total).
FANOUT_WARN = 8

# A session is worth flagging for deaths only if it re-spawned after one
# (circuit-breaker violation) or hit a real cluster. A single lone death with
# no re-spawn is correct behaviour — the agent stopped — so it's not reported.
DEATH_CLUSTER = 3

# Quota / rate-limit / API deaths — the actual symptom of a fan-out blowup.
# Matched against the raw line, so it catches task-notification text too.
# Kept deliberately specific to agent-death phrasing: bare "429"/"rate limit"/
# "overloaded" appear all over ordinary transcripts (code, logs, discussion)
# and would flag nearly every session.
QUOTA_DEATH_RE = re.compile(
    r"(hit your (session|usage|weekly) limit|terminated early due to an API error|"
    r"overloaded_error|Claude AI usage limit reached)",
    re.IGNORECASE,
)

# An agent past this many turns is carrying a context it re-reads every turn.
# Cost is ~quadratic in turn count, so this is the cap that actually bounds
# spend — one 240-turn agent costs ~4x four 60-turn agents doing the same work.
TURN_WARN = 80

# List $/Mtok (input, output), version-tolerant substrings checked in order —
# "haiku" before "opus"/"sonnet" so a compound id can't match the wrong row.
# Non-Claude families are left unpriced rather than guessed; their tokens are
# still counted and reported separately.
PRICES = [
    ("fable", 10.0, 50.0),
    ("mythos", 10.0, 50.0),
    ("haiku", 1.0, 5.0),
    ("opus", 5.0, 25.0),
    ("sonnet", 3.0, 15.0),
]
CACHE_WRITE_MULT = 1.25  # 5-minute TTL. 1h-TTL writes are 2x — cost is a floor.
CACHE_READ_MULT = 0.1

# Heuristic tier rank — version-tolerant substrings, checked in order.
TIER_RULES = [
    ("fable", 3), ("mythos", 3),
    ("gpt-5.5", 3), ("gpt-5.6", 3), ("gpt-6", 3),
    ("mini", 0), ("haiku", 0),
    ("opus", 2), ("gpt-", 2),
    ("sonnet", 1),
]
TIER_NAMES = {0: "cheap", 1: "light", 2: "workhorse", 3: "frontier"}

MECHANICAL_RE = re.compile(
    r"\b(rename|typo|reformat|format.only|lint|boilerplate|scaffold|"
    r"fix imports|copy.paste|move (the )?file|bump (the )?version)\b",
    re.IGNORECASE,
)

# Strong = correction explicitly attacking depth/overkill/speed/cost or
# demanding a model switch. Medium = generic pushback near a handoff.
STRONG_PATTERNS = [
    (re.compile(r"\b(too (shallow|superficial|weak)|not (deep|thorough|smart) enough)\b", re.I), "depth"),
    (re.compile(r"\b(overkill|too expensive|wast\w* tokens|burn\w* tokens|too costly|cheaper model)\b", re.I), "cost"),
    (re.compile(r"\buse (a )?(bigger|smarter|better|stronger|smaller) model\b", re.I), "model-switch"),
    (re.compile(r"\b(switch|change) (it |this |the agent )?to (fable|opus|sonnet|haiku|gpt|codex|claude)\b", re.I), "model-switch"),
    (re.compile(r"\bshould have used (fable|opus|sonnet|haiku|gpt|codex|claude)\b", re.I), "model-switch"),
]
MEDIUM_PATTERNS = [
    (re.compile(r"^(no|wait|stop|hold on)\b", re.I), "pushback"),
    (re.compile(r"^actually\b", re.I), "pushback"),
    (re.compile(r"\b(redo|re-do|start over|try again|do it again)\b", re.I), "redo"),
    (re.compile(r"\bthat'?s (wrong|not (right|it|what))\b", re.I), "wrong"),
]

STOPWORDS = frozenset(
    "the a an and or of to in for on with this that is are be it as at by from".split()
)


def tier_of(model):
    m = (model or "").lower()
    for sub, rank in TIER_RULES:
        if sub in m:
            return rank
    return None


def family_of(provider_or_model):
    s = (provider_or_model or "").lower()
    if "claude" in s or s in {"haiku", "sonnet", "opus", "fable"}:
        return "claude"
    if "gpt" in s or "codex" in s:
        return "openai"
    return "unknown"


def price_of(model):
    m = (model or "").lower()
    for sub, pin, pout in PRICES:
        if sub in m:
            return pin, pout
    return None


def is_subagent(path):
    return "subagents" in path.split(os.sep)


def session_key(path):
    """Attribute a subagent transcript to the parent session that spawned it."""
    parts = path.split(os.sep)
    if "subagents" in parts:
        return os.sep.join(parts[: parts.index("subagents")]) + ".jsonl"
    return path


def usage_of(entry):
    """(model, usage) for a billed assistant turn, else None."""
    if entry.get("type") != "assistant":
        return None
    msg = entry.get("message") or {}
    usage = msg.get("usage")
    if not isinstance(usage, dict):
        return None
    return msg.get("model", ""), usage


def cost_of(spend):
    """Cost a {model: [fresh, write, read, out, msgs]} map at list prices.

    Returns (total_usd, unpriced_msgs, [fresh$, write$, read$, out$]) — the
    per-component split is what tells you which lever to pull, and it has to be
    summed per model because a mixed fleet has no single price.
    """
    parts = [0.0, 0.0, 0.0, 0.0]
    unpriced = 0
    for model, (fresh, write, read, out, msgs) in spend.items():
        price = price_of(model)
        if price is None:
            unpriced += msgs
            continue
        pin, pout = price
        parts[0] += fresh * pin / 1e6
        parts[1] += write * CACHE_WRITE_MULT * pin / 1e6
        parts[2] += read * CACHE_READ_MULT * pin / 1e6
        parts[3] += out * pout / 1e6
    return sum(parts), unpriced, parts


def merge_spend(into, other):
    for model, vals in other.items():
        acc = into.setdefault(model, [0, 0, 0, 0, 0])
        for i, v in enumerate(vals):
            acc[i] += v


def totals(spend):
    """(fresh, write, read, out, msgs) summed across models."""
    out = [0, 0, 0, 0, 0]
    for vals in spend.values():
        for i, v in enumerate(vals):
            out[i] += v
    return out


def fmt_tok(n):
    return f"{n / 1e6:.2f}M" if n >= 1e6 else f"{n / 1e3:.0f}k"


def word_set(text):
    return {w for w in re.findall(r"[a-z0-9][a-z0-9_-]+", (text or "").lower()) if w not in STOPWORDS}


def similar(a, b, threshold=0.4):
    wa, wb = word_set(a), word_set(b)
    if not wa or not wb:
        return False
    return len(wa & wb) / len(wa | wb) >= threshold


def user_text(entry):
    """Real user text only — skip tool results, bash I/O, hook output."""
    if entry.get("type") != "user":
        return None
    content = (entry.get("message") or {}).get("content")
    if isinstance(content, list):
        parts = [b.get("text", "") for b in content if isinstance(b, dict) and b.get("type") == "text"]
        content = "\n".join(p for p in parts if p)
    if not isinstance(content, str) or not content.strip():
        return None
    if re.match(r"\s*<(bash-input|bash-stdout|local-command-stdout|task-notification)", content):
        return None
    # Machine notifications, not the human: paseo agent-finished blocks arrive
    # wrapped in "[Request interrupted by user]", so strip the marker and skip
    # anything that isn't leftover human text.
    if "<paseo-system>" in content or content.lstrip().startswith("[SYSTEM NOTIFICATION"):
        return None
    if re.match(r"\s*\S+( \S+)? hook (feedback|success|error|denied)", content):
        return None
    content = re.sub(r"\[Request interrupted by user[^\]]*\]", "", content)
    content = re.sub(r"<system-reminder>.*?</system-reminder>", "", content, flags=re.S).strip()
    return content or None


def creations_in(entry):
    """Yield (tool, model_or_provider, title, prompt_snippet, explicit, id) for agent-creation tool_use blocks."""
    if entry.get("type") != "assistant":
        return
    content = (entry.get("message") or {}).get("content")
    if not isinstance(content, list):
        return
    for block in content:
        if not isinstance(block, dict) or block.get("type") != "tool_use":
            continue
        name = block.get("name", "")
        inp = block.get("input") or {}
        bid = block.get("id", "")
        if name in CREATE_TOOLS:
            yield name, inp.get("provider", ""), inp.get("title", ""), str(inp.get("initialPrompt", ""))[:200], True, bid
        elif name in NATIVE_AGENT_TOOLS:
            model = inp.get("model")
            yield name, model or "(inherited)", inp.get("description", ""), str(inp.get("prompt", ""))[:200], bool(model), bid


def reuse_calls_in(entry):
    """Yield one marker per follow-up prompt sent to an already-running agent."""
    if entry.get("type") != "assistant":
        return
    content = (entry.get("message") or {}).get("content")
    if not isinstance(content, list):
        return
    for block in content:
        if isinstance(block, dict) and block.get("type") == "tool_use" and block.get("name") in REUSE_TOOLS:
            yield block.get("name")


def results_in(entry):
    """Yield (tool_use_id, is_error) for tool results carried on a user entry."""
    if entry.get("type") != "user":
        return
    content = (entry.get("message") or {}).get("content")
    if not isinstance(content, list):
        return
    for block in content:
        if isinstance(block, dict) and block.get("type") == "tool_result":
            yield block.get("tool_use_id", ""), bool(block.get("is_error"))


def scan_file(path):
    """Return (creations, user_turns, deaths, spend, signals); friction is attached later.

    deaths  = line indices where a quota/rate-limit/API death appears (any role).
    spend   = {model: [fresh, cache_write, cache_read, output, msgs]}.
    signals = what find_respawns needs, per file: line indexes of follow-up prompts
              and of conversation boundaries (a user entry that isn't just a tool
              result — a human turn or a paseo agent-finished notification), plus
              the ids of creations that errored out.
    """
    creations, user_turns, deaths, spend = [], [], [], {}
    signals = {"reuse": [], "boundaries": [], "errored": set()}
    depth = 1 if is_subagent(path) else 0
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            for idx, line in enumerate(fh):
                line = line.strip()
                if not line:
                    continue
                if QUOTA_DEATH_RE.search(line):
                    deaths.append(idx)
                try:
                    entry = json.loads(line)
                except ValueError:
                    continue
                billed = usage_of(entry)
                if billed:
                    model, usage = billed
                    acc = spend.setdefault(model, [0, 0, 0, 0, 0])
                    acc[0] += usage.get("input_tokens", 0) or 0
                    acc[1] += usage.get("cache_creation_input_tokens", 0) or 0
                    acc[2] += usage.get("cache_read_input_tokens", 0) or 0
                    acc[3] += usage.get("output_tokens", 0) or 0
                    acc[4] += 1
                ts = entry.get("timestamp", "")
                for tool, model, title, prompt, explicit, bid in creations_in(entry):
                    creations.append({
                        "idx": idx, "ts": ts, "tool": tool, "model": model, "id": bid,
                        "title": title, "prompt": prompt, "explicit": explicit,
                        "file": path, "depth": depth,
                        "cwd": entry.get("cwd", ""), "friction": [],
                    })
                for _ in reuse_calls_in(entry):
                    signals["reuse"].append(idx)
                saw_result = False
                for tool_use_id, is_error in results_in(entry):
                    saw_result = True
                    if is_error:
                        signals["errored"].add(tool_use_id)
                if entry.get("type") == "user" and not saw_result:
                    signals["boundaries"].append(idx)
                text = user_text(entry)
                if text:
                    user_turns.append((idx, text))
    except OSError:
        pass
    return creations, user_turns, deaths, spend, signals


def attach_friction(creations, user_turns):
    for c in creations:
        following = [t for i, t in user_turns if i > c["idx"]][:5]
        for text in following:
            head = text[:400]
            for pat, label in STRONG_PATTERNS:
                if pat.search(head):
                    c["friction"].append(("strong", label, head.splitlines()[0][:120]))
                    break
            else:
                for pat, label in MEDIUM_PATTERNS:
                    if pat.search(head):
                        c["friction"].append(("medium", label, head.splitlines()[0][:120]))
                        break


def find_escalations(creations):
    """Same-session re-launch of a similar task on a bigger tier or the other family."""
    out = []
    for i, a in enumerate(creations):
        for b in creations[i + 1:]:
            if b["file"] != a["file"]:
                continue
            if not similar(a["title"] + " " + a["prompt"], b["title"] + " " + b["prompt"]):
                continue
            ta, tb = tier_of(a["model"]), tier_of(b["model"])
            fa, fb = family_of(a["model"]), family_of(b["model"])
            fam_switch = fa != fb and "unknown" not in (fa, fb)
            if (ta is not None and tb is not None and tb > ta) or fam_switch:
                out.append((a, b, "tier-up" if (ta is not None and tb is not None and tb > ta) else "family-switch"))
    return out


def find_respawns(creations, signals_by_file):
    """Same-session re-launch of a similar task at the SAME tier and family, after the
    first agent already reported back and with no follow-up prompt in between — the
    live agent should have been reused instead.

    ponytail: any reuse call in the window suppresses the pair, even one aimed at a
    different agent. Under-reporting is the safe direction for an audit signal.
    """
    out = []
    for i, a in enumerate(creations):
        sig = signals_by_file.get(a["file"])
        # Unknown tier ((inherited), unrecognized IDs) can't be compared — those
        # creations are already reported under inherited-defaults.
        tier = tier_of(a["model"])
        if sig is None or tier is None:
            continue
        # A create that errored out never produced an agent; the retry isn't a respawn.
        if a["id"] in sig["errored"]:
            continue
        for b in creations[i + 1:]:
            if b["file"] != a["file"] or tier_of(b["model"]) != tier:
                continue
            if family_of(a["model"]) != family_of(b["model"]):
                continue
            if not similar(a["title"] + " " + a["prompt"], b["title"] + " " + b["prompt"]):
                continue
            if any(a["idx"] < r < b["idx"] for r in sig["reuse"]):
                continue
            # Agent `a` has to have reported back before `b` was launched — otherwise
            # this is a parallel fan-out wave, not a respawn. Only a boundary proves
            # that: both paseo create_agent and backgrounded native agents return a
            # launch acknowledgement immediately, so their tool result proves nothing.
            if not any(a["idx"] < i < b["idx"] for i in sig["boundaries"]):
                continue
            out.append((a, b))
            break
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--days", type=int, default=30)
    ap.add_argument("--projects-dir", action="append", default=None,
                    help="Transcript root(s); repeatable. Defaults to Claude + Paseo/ccs roots.")
    ap.add_argument("--max-events", type=int, default=15)
    args = ap.parse_args()

    roots = args.projects_dir or DEFAULT_ROOTS
    cutoff = time.time() - args.days * 86400
    all_creations, files_scanned, file_deaths = [], 0, {}
    file_spend, grand_spend, signals_by_file = {}, {}, {}

    for base in roots:
        for root, dirs, files in os.walk(base):
            dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
            for fn in files:
                if not fn.endswith(".jsonl"):
                    continue
                path = os.path.join(root, fn)
                try:
                    if os.path.getmtime(path) < cutoff:
                        continue
                except OSError:
                    continue
                files_scanned += 1
                creations, user_turns, deaths, spend, signals = scan_file(path)
                attach_friction(creations, user_turns)
                all_creations.extend(creations)
                signals_by_file[path] = signals
                if deaths:
                    file_deaths[path] = deaths
                if spend:
                    file_spend[path] = spend
                    merge_spend(grand_spend, spend)

    all_creations.sort(key=lambda c: c["ts"])
    escalations = find_escalations(all_creations)
    respawns = find_respawns(all_creations, signals_by_file)
    reuse_total = sum(len(s["reuse"]) for s in signals_by_file.values())
    inherited = [c for c in all_creations if not c["explicit"]]
    frontier_mechanical = [
        c for c in all_creations
        if tier_of(c["model"]) == 3 and MECHANICAL_RE.search(c["title"] + " " + c["prompt"])
    ]
    frictioned = [c for c in all_creations if c["friction"]]

    recursive = [c for c in all_creations if c["depth"] > 0]

    # Fan-out volume per session, and quota-death / re-spawn-after-death.
    # Keyed on the parent session so a subagent's own creations count against
    # the wave that spawned it, not against a phantom extra "session".
    per_file = Counter(session_key(c["file"]) for c in all_creations)
    wide_sessions = [(p, n) for p, n in per_file.most_common() if n > FANOUT_WARN]
    death_respawns = []
    for path, deaths in file_deaths.items():
        first = min(deaths)
        after = sum(1 for c in all_creations if c["file"] == path and c["idx"] > first)
        if after > 0 or len(deaths) >= DEATH_CLUSTER:
            death_respawns.append((path, len(deaths), after))
    death_respawns.sort(key=lambda r: (r[2], r[1]), reverse=True)

    print(f"DELEGATION AUDIT — last {args.days} days")
    print(f"files scanned: {files_scanned} | agent creations: {len(all_creations)} "
          f"(paseo: {sum(1 for c in all_creations if c['tool'] in CREATE_TOOLS)}, "
          f"native: {sum(1 for c in all_creations if c['tool'] in NATIVE_AGENT_TOOLS)})")
    if reuse_total:
        print(f"follow-up prompts to existing agents: {reuse_total} "
              f"| creations per follow-up: {len(all_creations) / reuse_total:.1f}")
    else:
        print("follow-up prompts to existing agents: 0 — every handoff was a fresh agent")

    fresh, write, read, out, msgs = totals(grand_spend)
    total_cost, unpriced, parts = cost_of(grand_spend)
    print("\n== Token spend (the number that actually moves) ==")
    print(f"  billed turns  {msgs}")
    print(f"  fresh input   {fmt_tok(fresh)}")
    print(f"  cache WRITE   {fmt_tok(write)}   (billed x{CACHE_WRITE_MULT})")
    print(f"  cache READ    {fmt_tok(read)}   (billed x{CACHE_READ_MULT})")
    print(f"  output        {fmt_tok(out)}")
    if fresh + write + read:
        print(f"  cache hit     {read / (fresh + write + read) * 100:.1f}%  "
              f"(high is normal — it does NOT mean spend is fine)")
    if total_cost:
        # Where the money is decides which lever to pull: read-dominated means
        # trim context and turns; output-dominated means trim effort.
        pct = [p / total_cost * 100 for p in parts]
        print(f"  est. cost     ${total_cost:,.2f} at list prices"
              + (f"  ({unpriced} turns on unpriced models excluded)" if unpriced else ""))
        print(f"  split         reads {pct[2]:.0f}%  writes {pct[1]:.0f}%  "
              f"output {pct[3]:.0f}%  fresh {pct[0]:.0f}%")
        print("  lever         " + ("trim context and turns" if pct[1] + pct[2] >= 60
                                    else "trim effort and output length"))

    print("\n== Costliest agents (turns x context, not tier) ==")
    ranked = []
    for path, spend in file_spend.items():
        cost = cost_of(spend)[0]
        f, w, r, o, n = totals(spend)
        ranked.append((cost, n, (f + w + r) / n if n else 0, path))
    ranked.sort(reverse=True)
    for cost, n, avg_ctx, path in ranked[: args.max_events]:
        flag = f"  <-- over the {TURN_WARN}-turn budget" if n > TURN_WARN else ""
        kind = "subagent" if is_subagent(path) else "session "
        print(f"  ${cost:>8,.2f}  {n:>4} turns  avg ctx {fmt_tok(avg_ctx):>6}  "
              f"{kind} {os.path.basename(path)}{flag}")
    over = [r for r in ranked if r[1] > TURN_WARN]
    if over:
        print(f"  ({len(over)} agent(s) over the {TURN_WARN}-turn budget, "
              f"${sum(r[0] for r in over):,.2f} combined — split these into "
              f"successor agents that resume from a handoff file)")

    print(f"\n== Recursive fan-out (agents spawned BY an agent): {len(recursive)} ==")
    for c in recursive[-args.max_events:]:
        print(f"  {c['ts'][:10]} {c['model']}: {c['title'][:70]}")
        print(f"      inside: {os.path.basename(c['file'])}")
    if not recursive:
        print("  (none — fan-out stayed one level deep)")

    print("\n== Routing histogram (model -> count) ==")
    for model, n in Counter(c["model"] for c in all_creations).most_common():
        tier = tier_of(model)
        print(f"  {model:<32} {n:>4}  [{TIER_NAMES.get(tier, 'unknown-tier')}]")

    print(f"\n== Inherited/default model (native tool, no explicit model): {len(inherited)} ==")
    for c in inherited[-args.max_events:]:
        print(f"  {c['ts'][:10]} {c['tool']}: {c['title'][:80]}  ({c['cwd']})")

    print(f"\n== Escalations (similar task re-launched bigger/other-family): {len(escalations)} ==")
    for a, b, kind in escalations[-args.max_events:]:
        print(f"  [{kind}] {a['ts'][:10]} {a['model']} -> {b['model']}: {a['title'][:70]}")

    print(f"\n== Respawns (similar task, same tier, no follow-up in between): {len(respawns)} ==")
    for a, b in respawns[-args.max_events:]:
        print(f"  {a['ts'][:10]} {a['model']} x2: {a['title'][:70]}")
        print(f"      session: {os.path.basename(a['file'])}  cwd: {a['cwd']}")

    print(f"\n== Frontier model on mechanical-looking work: {len(frontier_mechanical)} ==")
    for c in frontier_mechanical[-args.max_events:]:
        print(f"  {c['ts'][:10]} {c['model']}: {c['title'][:80]}")

    print(f"\n== Fan-out volume (sessions with > {FANOUT_WARN} agent creations): {len(wide_sessions)} ==")
    for path, n in wide_sessions[:args.max_events]:
        print(f"  {n:>4} creations  {os.path.basename(path)}")
    if not wide_sessions and per_file:
        top = ", ".join(f"{n}x {os.path.basename(p)}" for p, n in per_file.most_common(3))
        print(f"  (none over threshold; widest: {top})")

    print(f"\n== Quota/rate-limit deaths & re-spawn-after-death: {len(death_respawns)} sessions ==")
    for path, ndeaths, after in death_respawns[:args.max_events]:
        flag = "  <-- re-spawned INTO the wall" if after else ""
        print(f"  deaths={ndeaths:>3}  creations-after-first-death={after:>3}  {os.path.basename(path)}{flag}")

    print(f"\n== Friction events (user pushback within 5 turns of a handoff): {len(frictioned)} ==")
    for c in list(reversed(frictioned))[:args.max_events]:
        strongest = sorted(c["friction"], key=lambda f: f[0] != "strong")[0]
        print(f"  [{strongest[0]}:{strongest[1]}] {c['ts'][:10]} {c['model']} — {c['title'][:60]}")
        print(f"      quote: {strongest[2]}")
        print(f"      session: {os.path.basename(c['file'])}  cwd: {c['cwd']}")

    if not (inherited or escalations or respawns or frontier_mechanical or frictioned
            or wide_sessions or death_respawns or over or recursive):
        print("\nALL CLEAN — no misroute, reuse, volume, or context-bloat signals in the window.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
