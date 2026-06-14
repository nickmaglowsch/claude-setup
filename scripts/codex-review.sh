#!/usr/bin/env bash
# Shared cross-model review helper.
#
# Usage: codex-review.sh <output-file> <prompt-file>
#
# Runs `codex exec` (read-only sandbox by default — reviews can never mutate code)
# with the contents of <prompt-file> and writes Codex's response to <output-file>.
#
# FAILS SOFT BY DESIGN: this script always exits 0 and always produces a readable
# <output-file>. If Codex is missing, unauthenticated, over quota, or errors for any
# reason, it writes a "SKIPPED: ..." marker instead. A GPT reviewer must never
# hard-block a pipeline.

set -u

OUTPUT_FILE="${1:-}"
PROMPT_FILE="${2:-}"

if [ -z "$OUTPUT_FILE" ] || [ -z "$PROMPT_FILE" ]; then
  echo "usage: codex-review.sh <output-file> <prompt-file>" >&2
  exit 0
fi

# Make sure the output directory exists (branch-scoped tasks/<branch>/ trees).
mkdir -p "$(dirname "$OUTPUT_FILE")" 2>/dev/null || true

if ! command -v codex >/dev/null 2>&1; then
  echo "SKIPPED: codex not installed" > "$OUTPUT_FILE"
  exit 0
fi

if [ ! -f "$PROMPT_FILE" ]; then
  echo "SKIPPED: codex review failed (prompt file not found: $PROMPT_FILE)" > "$OUTPUT_FILE"
  exit 0
fi

PROMPT_CONTENT="$(cat "$PROMPT_FILE")"

# `-s read-only` explicitly enforces the read-only sandbox (not just the default),
# so this call can never mutate the workspace even if config/defaults drift.
# `-o` writes Codex's result to the output file.
if codex exec -s read-only -o "$OUTPUT_FILE" "$PROMPT_CONTENT" >/dev/null 2>&1; then
  # Guard against a successful-but-empty result.
  if [ ! -s "$OUTPUT_FILE" ]; then
    echo "SKIPPED: codex review failed (empty result)" > "$OUTPUT_FILE"
  fi
  exit 0
fi

echo "SKIPPED: codex review failed" > "$OUTPUT_FILE"
exit 0
