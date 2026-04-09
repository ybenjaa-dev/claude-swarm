#!/bin/bash
# ai-delegate.sh — wrapper called by Claude before running a model delegate
#
# Features:
#   - Per-model timeouts (gemini=300s, codex=600s, qwen=180s)
#   - Auto-retry once on failure with error preview
#   - Empty output detection → treated as failure → retried
#   - Gemini Pro → Flash automatic fallback
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

SEP=$'\x1f'
LOG="$HOME/.claude/ai-tasks.log"
TASK_ID="${MODEL}-$$-$(date +%s)-${RANDOM}"
START_TS=$(date +%s)
START_TIME=$(date '+%H:%M:%S')
MODEL_UPPER=$(echo "$MODEL" | tr '[:lower:]' '[:upper:]')

# Per-model timeout (seconds)
case "$MODEL" in
  gemini) TIMEOUT=300 ;;
  codex)  TIMEOUT=600 ;;
  qwen)   TIMEOUT=180 ;;
  *)      TIMEOUT=300 ;;
esac

# macOS uses gtimeout (GNU coreutils), Linux uses timeout
if command -v gtimeout >/dev/null 2>&1; then
  TIMEOUT_CMD="gtimeout"
elif command -v timeout >/dev/null 2>&1; then
  TIMEOUT_CMD="timeout"
else
  TIMEOUT_CMD=""
fi

# Model icons
case "$MODEL" in
  gemini) ICON="◆" ;; codex) ICON="⬡" ;; qwen) ICON="◈" ;; *) ICON="●" ;;
esac

# Colors by model
case "$MODEL" in
  gemini) C="\033[38;2;26;188;156m"  ;;  # teal
  codex)  C="\033[38;2;42;166;62m"   ;;  # green
  qwen)   C="\033[38;2;200;28;222m"  ;;  # purple
  *)      C="\033[38;2;21;93;252m"   ;;  # blue
esac
R="\033[0m"
B="\033[1m"
D="\033[2m"
GREEN="\033[38;2;80;220;100m"
RED="\033[38;2;240;80;80m"
YELLOW="\033[38;2;255;200;50m"

# ── Helpers ───────────────────────────────────────────────────────────────────

log_line() {
  python3 -c "
import fcntl, sys
with open(sys.argv[1], 'a') as f:
    fcntl.flock(f.fileno(), fcntl.LOCK_EX)
    f.write(sys.argv[2] + '\n')
    fcntl.flock(f.fileno(), fcntl.LOCK_UN)
" "$LOG" "$1"
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
  # Play completion sound (macOS only, non-blocking)
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
  # Estimate tokens from command args (~4 chars per token for English)
  # Warn if likely to exceed model's context window
  local total_chars=0
  for arg in "$@"; do
    total_chars=$(( total_chars + ${#arg} ))
  done
  local est_tokens=$(( total_chars / 4 ))

  local max_tokens
  case "$MODEL" in
    gemini) max_tokens=1000000 ;;
    codex)  max_tokens=128000 ;;
    qwen)   max_tokens=32768 ;;
    *)      max_tokens=128000 ;;
  esac

  local usage_pct=$(( est_tokens * 100 / max_tokens ))

  if [ "$est_tokens" -gt "$max_tokens" ]; then
    printf '%b\n' "  ${C}▍${R}   ${RED}⚠ context ~${est_tokens} tokens exceeds ${MODEL_UPPER} limit (${max_tokens})${R}" >&2
    printf '%b\n' "  ${C}▍${R}   ${RED}  output may be truncated — consider using Gemini for large contexts${R}" >&2
  elif [ "$usage_pct" -gt 75 ]; then
    printf '%b\n' "  ${C}▍${R}   ${YELLOW}⚠ context ~${est_tokens} tokens (${usage_pct}% of ${MODEL_UPPER} window)${R}" >&2
  fi
}

write_to_blackboard() {
  if [ -n "$AI_SESSION" ] && [ -s "$OUTPUT_FILE" ]; then
    BOARD_DIR="$HOME/.claude/blackboard/$AI_SESSION"
    mkdir -p "$BOARD_DIR" 2>/dev/null
    cp "$OUTPUT_FILE" "$BOARD_DIR/${MODEL}_$(basename "$OUTPUT_FILE")" 2>/dev/null
    # Write metadata
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

# Ensure log directory exists
mkdir -p "$(dirname "$LOG")" 2>/dev/null

# Ensure output directory exists
OUTPUT_DIR=$(dirname "$OUTPUT_FILE")
if [ ! -d "$OUTPUT_DIR" ]; then
  mkdir -p "$OUTPUT_DIR" 2>/dev/null || {
    echo "[AI] Error: cannot create output directory: $OUTPUT_DIR" >&2
    exit 1
  }
fi

# Log task start
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

# First attempt
run_with_timeout "${CMD[@]}" > "$OUTPUT_FILE" 2>&1
EXIT_CODE=$?

# Empty output on success = treat as failure
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

  # Still empty on success?
  if [ "$EXIT_CODE" -eq 0 ] && check_empty_output; then
    EXIT_CODE=1
  fi
fi

# ── Gemini Pro → Flash fallback ───────────────────────────────────────────────

if [ "$EXIT_CODE" -ne 0 ] && [ "$MODEL" = "gemini" ]; then
  HAS_PRO=0
  FLASH_CMD=()
  for arg in "${CMD[@]}"; do
    case "$arg" in
      *gemini-2.5-pro*)
        FLASH_CMD+=("${arg/gemini-2.5-pro/gemini-2.5-flash}")
        HAS_PRO=1
        ;;
      *) FLASH_CMD+=("$arg") ;;
    esac
  done

  if [ "$HAS_PRO" -eq 1 ]; then
    printf '%b\n' "  ${C}▍${R}   ${YELLOW}⟳ Pro failed — falling back to Flash…${R}" >&2
    sleep 1
    run_with_timeout "${FLASH_CMD[@]}" > "$OUTPUT_FILE" 2>&1
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

# Log task end
log_line "${END_TS}${SEP}END${SEP}${MODEL}${SEP}${TASK_ID}${SEP}${TASK_DESC}${SEP}${END_TIME}${SEP}${EXIT_CODE}${SEP}${ELAPSED}s"

# Write to blackboard if session is active
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
