#!/usr/bin/env bash
# statusline.sh — Claude Code status line.
# Reads session JSON on stdin, prints one line: model | project | folder | branch | ctx%.
#
# Wired in ~/.claude/settings.json under "statusLine":
#   { "type": "command", "command": "bash ~/.claude/statusline.sh", "padding": 0 }

set -u

input=$(cat)

# --- JSON access (jq preferred, python3 fallback) ---
if command -v jq &>/dev/null; then
  _get() { printf '%s' "$input" | jq -r "$1 // empty" 2>/dev/null; }
else
  _get() {
    printf '%s' "$input" | python3 -c "
import sys, json
keys = sys.argv[1].lstrip('.').split('.')
try:
    d = json.load(sys.stdin)
    for k in keys:
        d = d.get(k) if isinstance(d, dict) else None
    if d not in (None, False):
        print(d)
except Exception:
    pass
" "$1" 2>/dev/null
  }
fi

model=$(_get '.model.display_name')
project_dir=$(_get '.workspace.project_dir')
current_dir=$(_get '.workspace.current_dir')
transcript=$(_get '.transcript_path')

# --- Project name + path relative to project root ---
project_name=""
rel_dir=""
if [ -n "$project_dir" ]; then
  project_name=$(basename "$project_dir")
  if [ -n "$current_dir" ] && [ "$current_dir" != "$project_dir" ]; then
    rel_dir="${current_dir#"$project_dir"/}"
  fi
fi

# --- Git branch ---
branch=""
if [ -n "$current_dir" ] && [ -d "$current_dir" ]; then
  branch=$(git -C "$current_dir" branch --show-current 2>/dev/null || true)
  if [ -z "$branch" ]; then
    # Detached HEAD — show short SHA
    branch=$(git -C "$current_dir" rev-parse --short HEAD 2>/dev/null || true)
    [ -n "$branch" ] && branch="@$branch"
  fi
fi

# --- Context window % (parses latest usage from transcript JSONL) ---
ctx_pct=""
if [ -n "$transcript" ] && [ -f "$transcript" ] && command -v python3 &>/dev/null; then
  ctx_pct=$(python3 - "$transcript" "${model:-}" <<'PYEOF' 2>/dev/null
import sys, json
path, model = sys.argv[1], sys.argv[2]
last = None
try:
    with open(path) as f:
        for line in f:
            try:
                obj = json.loads(line)
                u = obj.get("message", {}).get("usage")
                if u:
                    last = u
            except Exception:
                pass
except Exception:
    sys.exit(0)
if not last:
    sys.exit(0)
total = (last.get("input_tokens") or 0) \
      + (last.get("cache_read_input_tokens") or 0) \
      + (last.get("cache_creation_input_tokens") or 0)
ctx_max = 1_000_000 if "1M" in (model or "") else 200_000
print(total * 100 // ctx_max)
PYEOF
)
fi

# --- Colors (ANSI — Claude Code statuslines render these) ---
DIM=$'\033[2m'
RESET=$'\033[0m'
CYAN=$'\033[36m'
GREEN=$'\033[32m'
MAGENTA=$'\033[35m'
YELLOW=$'\033[33m'
RED=$'\033[31m'

# --- Assemble output ---
parts=()
[ -n "$model" ] && parts+=("${MAGENTA}${model}${RESET}")
[ -n "$project_name" ] && parts+=("${CYAN}${project_name}${RESET}")
[ -n "$rel_dir" ] && parts+=("${DIM}${rel_dir}${RESET}")
[ -n "$branch" ] && parts+=("${GREEN}(${branch})${RESET}")

if [ -n "$ctx_pct" ] && [ "$ctx_pct" -ge 0 ] 2>/dev/null; then
  if [ "$ctx_pct" -ge 90 ] 2>/dev/null; then
    parts+=("${RED}ctx ${ctx_pct}%${RESET}")
  elif [ "$ctx_pct" -ge 70 ] 2>/dev/null; then
    parts+=("${YELLOW}ctx ${ctx_pct}%${RESET}")
  else
    parts+=("${DIM}ctx ${ctx_pct}%${RESET}")
  fi
fi

sep=" ${DIM}|${RESET} "
out=""
for i in "${!parts[@]}"; do
  if [ "$i" -eq 0 ]; then
    out="${parts[$i]}"
  else
    out="${out}${sep}${parts[$i]}"
  fi
done
printf '%s' "$out"
