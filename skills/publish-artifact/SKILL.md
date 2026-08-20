---
name: publish-artifact
description: "Publish a local HTML file as a claude.ai artifact from a session that has no Artifact tool (headless / non-interactive / SDK / cron runs). Use when the user asks to 'publish this as an artifact', 'make it an artifact', 'give me an artifact link', 'artifact this', or asks for an artifact and the Artifact tool is absent from the tool list. Drives a real interactive `claude` inside a paseo terminal, since Artifact is gated to interactive TTY sessions."
argument-hint: "[path to the HTML file, or the content to build first]"
---

# Publish an artifact from a headless session

**First: is `Artifact` in your tool list?** If yes, just call it with the file path — stop reading. This skill is only the fallback for sessions where it's absent.

`Artifact` is gated to interactive TTY sessions. `claude -p` does not have it, and `--tools Artifact` does not add it. The only way through is a real interactive `claude` in a PTY, which paseo terminals provide.

## Steps

1. **Put the file in an already-trusted directory** — normally the repo you're working in. Do NOT use `/tmp`: interactive `claude` throws a "do you trust this folder" gate there, and that gate is not yours to accept on the user's behalf (`/tmp` is world-writable). If the file is already in `/tmp`, copy it into the repo.

2. **Reuse or create the terminal.** `mcp__paseo__list_terminals` with `all: true`, look for one named `artifact-publisher`. If absent, `mcp__paseo__create_terminal` with `cwd` = the repo root and `name: "artifact-publisher"`.

3. **Make sure interactive claude is running in it.** `mcp__paseo__capture_terminal` — if you see the `⏵⏵ auto mode` footer, a session is live, skip to step 4. Otherwise send (`literal: true`, trailing newline):
   ```
   cd <repo-root> && claude --allowedTools Artifact
   ```

4. **Send the prompt, then Enter as a separate call.** A positional prompt arg on interactive `claude` does not auto-submit — type it, then send the key.
   - `send_terminal_keys` `literal: true`: `Publish the file <abs-path> as an artifact. Reply with only the resulting URL.`
   - `send_terminal_keys` (not literal): `Enter`

5. **Poll for the URL.** `capture_terminal` every few seconds; ~15–30s is normal. Success looks like:
   ```
   ⏺ Artifact(/abs/path/file.html)
     ⎿  Published ⧉
        https://claude.ai/code/artifact/<uuid>
   ```
   To wait without blocking, run a background `for i in $(seq 1 12); do sleep 5; done` — foreground `sleep` is blocked.

6. **Report the URL** and say what you left behind: the terminal stays alive (good — next publish is one send away) and any file you copied into the repo. Ask before deleting either.

## Notes

- Subsequent publishes in the same session: skip to step 4. The live terminal is the whole point of keeping it.
- One file per artifact. Self-contained HTML — inline the CSS/JS, no local asset references.
- Publishing sends the file content to claude.ai. If the HTML contains tenant data, customer names, or credentials, confirm with the user before publishing.
- Building the HTML is a different job: use `web-artifacts-builder` or `visual-plan` for that, then this skill to publish the result.
