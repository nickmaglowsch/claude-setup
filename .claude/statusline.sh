#!/usr/bin/env bash
# statusline.sh — Agnoster-style Claude Code status line.
# Reads session JSON on stdin, prints powerline segments:
#   model | project | folder | branch | ctx %
#
# Wired in ~/.claude/settings.json under "statusLine":
#   { "type": "command", "command": "bash ~/.claude/statusline.sh", "padding": 0 }
#
# Requires a Powerline / Nerd Font in the terminal for the segment arrows
# and branch glyph to render. Without one, glyphs appear as boxes/question marks.

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

# --- Project name + folder relative to project root ---
project_name=""
rel_dir=""
if [ -n "$project_dir" ]; then
  project_name=$(basename "$project_dir")
  if [ -n "$current_dir" ] && [ "$current_dir" != "$project_dir" ]; then
    if [[ "$current_dir" == "$project_dir"/* ]]; then
      rel_dir="${current_dir#"$project_dir"/}"
    else
      rel_dir=$(basename "$current_dir")
    fi
  fi
fi

# --- Git branch + dirty flag ---
branch=""
dirty=0
if [ -n "$current_dir" ] && [ -d "$current_dir" ]; then
  branch=$(git -C "$current_dir" branch --show-current 2>/dev/null || true)
  if [ -z "$branch" ]; then
    sha=$(git -C "$current_dir" rev-parse --short HEAD 2>/dev/null || true)
    [ -n "$sha" ] && branch="@$sha"
  fi
  if [ -n "$branch" ]; then
    if ! git -C "$current_dir" diff --quiet 2>/dev/null \
       || ! git -C "$current_dir" diff --cached --quiet 2>/dev/null; then
      dirty=1
    fi
  fi
fi

# --- Context window % from transcript ---
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

# --- Powerline glyphs (require Nerd Font / Powerline-patched font) ---
ARROW=$''   # right-pointing solid triangle
BRANCH=$''  # branch glyph
RESET=$'\033[0m'

# --- 256-color palette (agnoster-inspired) ---
BG_MODEL=54;       FG_MODEL=255    # purple bg, white text
BG_PROJ=31;        FG_PROJ=255     # teal bg, white text
BG_DIR=240;        FG_DIR=252      # gray bg, light gray text
BG_BRANCH_OK=64;   FG_BRANCH_OK=235    # green bg, near-black text
BG_BRANCH_DIRTY=166; FG_BRANCH_DIRTY=235 # orange bg, near-black text
BG_CTX_OK=236;     FG_CTX_OK=245   # near-black bg, mid-gray text
BG_CTX_WARN=178;   FG_CTX_WARN=235 # gold bg, near-black text
BG_CTX_DANGER=124; FG_CTX_DANGER=255 # red bg, white text

# --- Segment renderer: builds a continuous powerline strip ---
prev_bg=""
out=""
seg() {
  local bg=$1 fg=$2 text=$3
  [ -z "$text" ] && return
  if [ -n "$prev_bg" ]; then
    out+=$'\033[38;5;'"$prev_bg"$';48;5;'"$bg"$'m'"$ARROW"
  fi
  out+=$'\033[38;5;'"$fg"$';48;5;'"$bg"$'m '"$text"' '
  prev_bg=$bg
}

[ -n "$model" ]        && seg "$BG_MODEL" "$FG_MODEL" "$model"
[ -n "$project_name" ] && seg "$BG_PROJ"  "$FG_PROJ"  "$project_name"
[ -n "$rel_dir" ]      && seg "$BG_DIR"   "$FG_DIR"   "$rel_dir"

if [ -n "$branch" ]; then
  if [ "$dirty" -eq 1 ]; then
    seg "$BG_BRANCH_DIRTY" "$FG_BRANCH_DIRTY" "$BRANCH $branch *"
  else
    seg "$BG_BRANCH_OK" "$FG_BRANCH_OK" "$BRANCH $branch"
  fi
fi

if [ -n "$ctx_pct" ] && [ "$ctx_pct" -ge 0 ] 2>/dev/null; then
  if [ "$ctx_pct" -ge 90 ] 2>/dev/null; then
    seg "$BG_CTX_DANGER" "$FG_CTX_DANGER" "ctx ${ctx_pct}%"
  elif [ "$ctx_pct" -ge 70 ] 2>/dev/null; then
    seg "$BG_CTX_WARN" "$FG_CTX_WARN" "ctx ${ctx_pct}%"
  else
    seg "$BG_CTX_OK" "$FG_CTX_OK" "ctx ${ctx_pct}%"
  fi
fi

# Closing arrow: previous bg as fg, default bg.
if [ -n "$prev_bg" ]; then
  out+=$'\033[0m\033[38;5;'"$prev_bg"$'m'"$ARROW""$RESET"
fi

printf '%s' "$out"
