#!/bin/bash
# ai-delegate.sh — wrapper called by Claude before running a model delegate
#
# Features:
#   - Per-model timeouts, icons, colors from capabilities.json
#   - Auto-retry once on failure with error preview
#   - Empty output detection → treated as failure → retried
#   - Automatic fallback to fallback_model (e.g. Gemini Pro → Flash)
#   - Blackboard integration via AI_SESSION env var
#   - Completion sound (success/failure)
#   - Context size estimation with model window warnings
#
# Usage: ai-delegate.sh <model> <task_desc> <output_file> <command...>
#
# Environment:
#   AI_SESSION  — if set, copies output to ~/.claude/blackboard/$AI_SESSION/
#   AI_SILENT   — if set to 1, suppress completion sounds

if [ $# -lt 4 ]; then
  echo "Usage: $0 <model> <task_desc> <output_file> <command...>" >&2
  exit 1
fi

MODEL="$1"
TASK_DESC="$2"
OUTPUT_FILE="$3"
shift 3

# ── Load model config from capabilities.json ─────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/ai-models.sh"
load_model "$MODEL"

ICON="$MODEL_ICON"
C="$MODEL_COLOR"
TIMEOUT="$MODEL_TIMEOUT"
MAX_TOKENS="$MODEL_CONTEXT_WINDOW"
MODEL_UPPER=$(echo "$MODEL" | tr '[:lower:]' '[:upper:]')

R="$AI_RESET"
B="$AI_BOLD"
D="$AI_DIM"
GREEN="$AI_GREEN"
RED="$AI_RED"
YELLOW="$AI_YELLOW"

SEP=$'\x1f'
LOG="$HOME/.claude/ai-tasks.log"
TASK_ID="${MODEL}-$$-$(date +%s)-${RANDOM}"
START_TS=$(date +%s)
START_TIME=$(date '+%H:%M:%S')

# macOS uses gtimeout (GNU coreutils), Linux uses timeout
if command -v gtimeout >/dev/null 2>&1; then
  TIMEOUT_CMD="gtimeout"
elif command -v timeout >/dev/null 2>&1; then
  TIMEOUT_CMD="timeout"
else
  TIMEOUT_CMD=""
fi

# ── Helpers ───────────────────────────────────────────────────────────────────

log_line() {
  # POSIX guarantees O_APPEND writes <4KB are atomic — no flock needed.
  printf '%s\n' "$1" >> "$LOG"
}

check_empty_output() {
  [ ! -s "$OUTPUT_FILE" ]
}

run_with_timeout() {
  if [ -n "$TIMEOUT_CMD" ]; then
    "$TIMEOUT_CMD" "$TIMEOUT" "$@"
  else
    "$@"
  fi
}

play_sound() {
  [ "${AI_SILENT:-0}" = "1" ] && return
  local sound_file
  if [ "$1" = "success" ]; then
    sound_file="/System/Library/Sounds/Glass.aiff"
  else
    sound_file="/System/Library/Sounds/Basso.aiff"
  fi
  if [ -f "$sound_file" ]; then
    afplay "$sound_file" &>/dev/null &
  fi
}

estimate_context() {
  local total_chars=0
  for arg in "$@"; do
    total_chars=$(( total_chars + ${#arg} ))
  done
  local est_tokens=$(( total_chars / 4 ))
  local usage_pct=$(( est_tokens * 100 / MAX_TOKENS ))

  if [ "$est_tokens" -gt "$MAX_TOKENS" ]; then
    printf '%b\n' "  ${C}▍${R}   ${RED}⚠ context ~${est_tokens} tokens exceeds ${MODEL_UPPER} limit (${MAX_TOKENS})${R}" >&2
    printf '%b\n' "  ${C}▍${R}   ${RED}  consider using a model with a larger context window${R}" >&2
  elif [ "$usage_pct" -gt 75 ]; then
    printf '%b\n' "  ${C}▍${R}   ${YELLOW}⚠ context ~${est_tokens} tokens (${usage_pct}% of ${MODEL_UPPER} window)${R}" >&2
  fi
}

write_to_blackboard() {
  if [ -n "$AI_SESSION" ] && [ -s "$OUTPUT_FILE" ]; then
    BOARD_DIR="$HOME/.claude/blackboard/$AI_SESSION"
    mkdir -p "$BOARD_DIR" 2>/dev/null
    cp "$OUTPUT_FILE" "$BOARD_DIR/${MODEL}_$(basename "$OUTPUT_FILE")" 2>/dev/null
    python3 -c "
import json, sys, os
meta_path = os.path.join(sys.argv[1], '_manifest.json')
meta = {}
if os.path.exists(meta_path):
    try:
        with open(meta_path) as f: meta = json.load(f)
    except: pass
meta[sys.argv[2]] = {
    'model': sys.argv[3],
    'task': sys.argv[4],
    'file': sys.argv[5],
    'exit_code': int(sys.argv[6]),
    'elapsed': sys.argv[7]
}
with open(meta_path, 'w') as f: json.dump(meta, f, indent=2)
" "$BOARD_DIR" "$TASK_ID" "$MODEL" "$TASK_DESC" "$(basename "$OUTPUT_FILE")" "$1" "$2"
  fi
}

# ── Setup ─────────────────────────────────────────────────────────────────────

mkdir -p "$(dirname "$LOG")" 2>/dev/null

OUTPUT_DIR=$(dirname "$OUTPUT_FILE")
if [ ! -d "$OUTPUT_DIR" ]; then
  mkdir -p "$OUTPUT_DIR" 2>/dev/null || {
    echo "[AI] Error: cannot create output directory: $OUTPUT_DIR" >&2
    exit 1
  }
fi

log_line "${START_TS}${SEP}START${SEP}${MODEL}${SEP}${TASK_ID}${SEP}${TASK_DESC}${SEP}${START_TIME}${SEP}${OUTPUT_FILE}"

# ── Print start ───────────────────────────────────────────────────────────────
printf '%b\n' "" >&2
printf '%b\n' "  ${C}▍${R} ${C}${B}${ICON} ${MODEL_UPPER}${R}  ${D}⟳ started  timeout ${TIMEOUT}s${R}" >&2
printf '%b\n' "  ${C}▍${R}   ${TASK_DESC}" >&2
printf '%b\n' "  ${C}▍${R}   ${D}→ ${OUTPUT_FILE}${R}" >&2
if [ -n "$AI_SESSION" ]; then
  printf '%b\n' "  ${C}▍${R}   ${D}⊞ session: ${AI_SESSION}${R}" >&2
fi
printf '%b\n' "" >&2

# ── Context estimation ────────────────────────────────────────────────────────
estimate_context "$@"

# ── Execute ───────────────────────────────────────────────────────────────────
CMD=("$@")

run_with_timeout "${CMD[@]}" > "$OUTPUT_FILE" 2>&1
EXIT_CODE=$?

if [ "$EXIT_CODE" -eq 0 ] && check_empty_output; then
  printf '%b\n' "  ${C}▍${R}   ${YELLOW}⚠ empty output${R}" >&2
  EXIT_CODE=1
fi

# ── Retry once on failure ─────────────────────────────────────────────────────
if [ "$EXIT_CODE" -ne 0 ]; then
  FIRST_ERROR=""
  if [ -f "$OUTPUT_FILE" ]; then
    FIRST_ERROR=$(head -3 "$OUTPUT_FILE" 2>/dev/null | tr '\n' ' ' | cut -c1-80)
  fi
  if [ "$EXIT_CODE" -eq 124 ]; then
    printf '%b\n' "  ${C}▍${R}   ${YELLOW}⟳ timed out after ${TIMEOUT}s — retrying…${R}" >&2
  else
    printf '%b\n' "  ${C}▍${R}   ${YELLOW}⟳ failed (exit ${EXIT_CODE}) — retrying…${R}" >&2
    if [ -n "$FIRST_ERROR" ]; then
      printf '%b\n' "  ${C}▍${R}   ${D}${FIRST_ERROR}${R}" >&2
    fi
  fi

  sleep 2

  run_with_timeout "${CMD[@]}" > "$OUTPUT_FILE" 2>&1
  EXIT_CODE=$?

  if [ "$EXIT_CODE" -eq 0 ] && check_empty_output; then
    EXIT_CODE=1
  fi
fi

# ── Fallback model (generic — works for any model with fallback_model set) ───
if [ "$EXIT_CODE" -ne 0 ] && [ -n "$MODEL_FALLBACK" ]; then
  HAS_PRIMARY=0
  FALLBACK_CMD=()
  for arg in "${CMD[@]}"; do
    case "$arg" in
      *"$MODEL_ID"*)
        FALLBACK_CMD+=("${arg/$MODEL_ID/$MODEL_FALLBACK}")
        HAS_PRIMARY=1
        ;;
      *) FALLBACK_CMD+=("$arg") ;;
    esac
  done

  if [ "$HAS_PRIMARY" -eq 1 ]; then
    printf '%b\n' "  ${C}▍${R}   ${YELLOW}⟳ ${MODEL_ID} failed — falling back to ${MODEL_FALLBACK}…${R}" >&2
    sleep 1
    run_with_timeout "${FALLBACK_CMD[@]}" > "$OUTPUT_FILE" 2>&1
    EXIT_CODE=$?

    if [ "$EXIT_CODE" -eq 0 ] && check_empty_output; then
      EXIT_CODE=1
    fi
  fi
fi

# ── Finalize ──────────────────────────────────────────────────────────────────
END_TS=$(date +%s)
END_TIME=$(date '+%H:%M:%S')
ELAPSED=$(( END_TS - START_TS ))

log_line "${END_TS}${SEP}END${SEP}${MODEL}${SEP}${TASK_ID}${SEP}${TASK_DESC}${SEP}${END_TIME}${SEP}${EXIT_CODE}${SEP}${ELAPSED}s"

write_to_blackboard "$EXIT_CODE" "${ELAPSED}s"

# ── Completion sound ──────────────────────────────────────────────────────────
if [ "$EXIT_CODE" -eq 0 ]; then
  play_sound success
else
  play_sound failure
fi

# ── Print completion ──────────────────────────────────────────────────────────
printf '%b\n' "" >&2
if [ "$EXIT_CODE" -eq 0 ]; then
  printf '%b\n' "  ${C}▍${R} ${C}${B}${ICON} ${MODEL_UPPER}${R}  ${GREEN}${B}✓ done${R}  ${D}${ELAPSED}s${R}" >&2
elif [ "$EXIT_CODE" -eq 124 ]; then
  printf '%b\n' "  ${C}▍${R} ${C}${B}${ICON} ${MODEL_UPPER}${R}  ${RED}${B}✗ timeout${R}  ${D}${TIMEOUT}s limit${R}" >&2
else
  printf '%b\n' "  ${C}▍${R} ${C}${B}${ICON} ${MODEL_UPPER}${R}  ${RED}${B}✗ failed${R}  ${D}exit ${EXIT_CODE}${R}" >&2
fi
printf '%b\n' "  ${C}▍${R}   ${TASK_DESC}" >&2
if [ -n "$AI_SESSION" ] && [ "$EXIT_CODE" -eq 0 ]; then
  printf '%b\n' "  ${C}▍${R}   ${D}⊞ saved to blackboard${R}" >&2
fi
printf '%b\n' "" >&2

exit "${EXIT_CODE:-1}"
