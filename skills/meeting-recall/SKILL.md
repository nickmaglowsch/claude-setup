---
name: meeting-recall
description: "Query the user's local Meetily meeting transcripts and summaries to answer questions about past meetings — decisions made, action items, ticket/feature discussions, or summaries of specific meetings. Use whenever the user says any of: 'what did we decide about X', 'what we will do on ticket X', 'what we will do on feature X', 'in the meeting about X', 'from last week's call', 'from the meeting on <date>', 'summarize the meeting on X', 'find the meeting where we discussed X', 'action items from <topic>', 'meeting notes on X', 'what was said about X', or any past-meeting recall question. Reads the local Meetily SQLite DB at ~/Library/Application Support/com.meetily.ai/meeting_minutes.sqlite. Do NOT use for live/upcoming meetings or to take notes — this is past-only and read-only. Do NOT invent speaker attributions; the data has no reliable speaker labels."
---

# Meeting Recall

Answer questions about the user's past meetings by querying their local Meetily database with `sqlite3`. Everything is local — no network calls. Pull the relevant excerpts, cite the source meeting (title + date), and be honest about gaps.

## Database

**Path:** `~/Library/Application Support/com.meetily.ai/meeting_minutes.sqlite`

| Table | Use for | Key columns |
|---|---|---|
| `meetings` | Identify meetings | `id`, `title`, `created_at` |
| `summary_processes` | Pre-extracted summaries (Decisions, Action Items, Key Points) | `meeting_id`, `result` (JSON with `.markdown`), `status` |
| `transcript_chunks` | Full searchable transcript per meeting | `meeting_id`, `transcript_text` (format: `[mm:ss] line\n...`) |
| `transcripts` | Per-segment rows when you need timestamps | `transcript`, `audio_start_time` |
| `meeting_notes` | User's own notes (often empty) | `notes_markdown` |

**Quirks:**

- `summary_processes.result` is JSON `{"markdown": "..."}`. The markdown blob is structured with sections like `**Summary**`, `**Key Decisions**`, `**Action Items**`, `**Key Points**`. Extract with `json_extract(result, '$.markdown')`.
- Not every meeting has a summary (a handful are unsummarized). Always be ready to fall back to `transcript_chunks`.
- Titles are mixed quality — some descriptive ("Porch Account Issues and Policy Rate Discrepancies"), some generic ("Meeting 2026-05-21_09-26-43"). Don't rely on title for search; search the transcript text.
- **No reliable speaker labels.** The `speaker` column exists but is almost always empty. Answer "what was said about X" — never "who said X".
- SQLite `LIKE` is case-sensitive by default — always `COLLATE NOCASE`.
- Total volume is small (~22 meetings, ~2MB). Plain LIKE search is instant; no need for FTS5 yet.

## SQL recipes

Always quote the path because of the space.

```bash
DB="$HOME/Library/Application Support/com.meetily.ai/meeting_minutes.sqlite"
```

### 1. List recent meetings (or by date range)

```bash
sqlite3 "$DB" "SELECT id, title, substr(created_at, 1, 10) AS date
FROM meetings ORDER BY created_at DESC LIMIT 10;"
```

```bash
sqlite3 "$DB" "SELECT id, title, substr(created_at, 1, 10) AS date
FROM meetings WHERE created_at >= '2026-05-01' ORDER BY created_at DESC;"
```

### 2. Search transcripts for a term (the main move)

```bash
TERM="porch"
sqlite3 -separator $'\t' "$DB" "
SELECT m.id, substr(m.created_at, 1, 10) AS date, m.title
FROM meetings m JOIN transcript_chunks tc ON tc.meeting_id = m.id
WHERE tc.transcript_text LIKE '%${TERM}%' COLLATE NOCASE
ORDER BY m.created_at DESC;"
```

For ticket IDs (e.g., `ABC-1234`), search literally — they're usually unique enough to identify the meeting in one shot.

### 3. Pull the structured summary (Decisions / Action Items / Key Points)

```bash
MID="meeting-5fab246c-..."
sqlite3 "$DB" "SELECT json_extract(result, '\$.markdown')
FROM summary_processes WHERE meeting_id = '${MID}';"
```

The returned markdown has the sections already. Scan it for `**Key Decisions**`, `**Action Items**`, `**Key Points**` and return only the section the user asked about — don't dump the whole thing.

### 4. Pull transcript context around a keyword (when the summary isn't enough)

```bash
MID="meeting-5fab246c-..."
TERM="porch"
sqlite3 "$DB" "SELECT transcript_text FROM transcript_chunks WHERE meeting_id = '${MID}';" \
  | grep -i -B 2 -A 4 "$TERM"
```

The `[mm:ss]` prefix on each line lets you cite a timestamp if the user wants to find that part in the recording.

### 5. Find meetings missing a summary (fallback path)

```bash
sqlite3 "$DB" "SELECT m.id, m.title FROM meetings m
LEFT JOIN summary_processes sp ON sp.meeting_id = m.id
WHERE sp.meeting_id IS NULL OR sp.status != 'completed';"
```

For these, only the raw transcript exists — say so explicitly when answering.

## Routing — map intent to a query plan

| User says... | Plan |
|---|---|
| "what did we decide about X" | (2) search for X → (3) pull `**Key Decisions**` section of each match |
| "what we'll do on ticket Y / feature Z" | (2) search for Y/Z → (3) pull `**Action Items**`; fall back to (4) transcript context |
| "summarize last meeting" / "the meeting on \<date\>" | (1) find by date → (3) extract `**Summary**` section |
| "find the meeting where we discussed X" | (2) search — return titles + dates with a one-line snippet from (4) |
| "action items from this week" | (1) filter by date → (3) extract `**Action Items**` from each |
| "what was said about X" (verbatim) | (2) search → (4) transcript excerpts with timestamps |

If a search returns 0 hits, try one obvious synonym before giving up (e.g., "policy rate" → "rating"). If still empty, say so plainly — don't fabricate.

## Answer format

1. **Lead with the answer**, not the methodology. "We decided X, Y, Z" — not "I searched the database and found…"
2. **Cite the source.** Each fact references the meeting by title + date: *(from "Porch Account Issues and Policy Rate Discrepancies", 2026-05-18)*. Never use the UUID in user-facing text.
3. **Quote sparingly.** Pull the relevant 1–3 lines from the transcript when the user wants verbatim; otherwise paraphrase from the summary.
4. **Be honest about gaps.** If a meeting has no summary, say so and offer to search the raw transcript. If a topic only got a passing mention, say it was brief — don't overstate.
5. **No speakers.** Never attribute a quote to a named person — the data doesn't have reliable speaker labels.
6. **Multiple meetings.** If the term appears in several meetings, group findings by meeting rather than mashing them together. Most recent first.

## Worked example

User: *"what did we decide about porch accounts?"*

1. Search: `WHERE transcript_text LIKE '%porch%' COLLATE NOCASE` → e.g., meeting `82b44859...` titled "Porch Account Issues and Policy Rate Discrepancies", 2026-05-18.
2. Pull that meeting's summary; locate `**Key Decisions**` section.
3. Reply with the decisions, cited.
4. If the **Key Decisions** section is empty/missing, fall back to transcript excerpts around "porch" and tell the user the meeting didn't record explicit decisions.

## What this skill does NOT do

- Take notes, schedule meetings, or modify the DB. Read-only.
- Transcribe live audio (Meetily handles that — this just queries the result).
- Identify speakers (column is mostly empty).
- Semantic search. Keyword/LIKE only. Fine for ~22 meetings; revisit with FTS5 or embeddings if the corpus grows past ~500.
- Cross-reference with calendar/email/ticket systems. If the user wants that, point at the relevant MCP integration or skill.
