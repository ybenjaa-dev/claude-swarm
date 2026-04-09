#!/bin/bash
# ai-ping — health check all 3 AI delegate models
#
# Sends a minimal prompt to each model and reports latency + status.
# Use before complex multi-delegate tasks to catch dead keys, rate limits, etc.
#
# Usage:
#   ai-ping           # check all models
#   ai-ping gemini    # check single model
#   ai-ping --quiet   # exit code only (0 = all healthy)

set -o pipefail

R="\033[0m"
B="\033[1m"
D="\033[2m"
GREEN="\033[38;2;80;220;100m"
RED="\033[38;2;240;80;80m"
YELLOW="\033[38;2;255;200;50m"

COLORS_gemini="\033[38;2;26;188;156m"
COLORS_codex="\033[38;2;42;166;62m"
COLORS_qwen="\033[38;2;200;28;222m"

ICONS_gemini="◆"
ICONS_codex="⬡"
ICONS_qwen="◈"

PING_TIMEOUT=15

# macOS timeout
if command -v gtimeout >/dev/null 2>&1; then
  TCMD="gtimeout"
elif command -v timeout >/dev/null 2>&1; then
  TCMD="timeout"
else
  TCMD=""
fi

run_timed() {
  if [ -n "$TCMD" ]; then
    "$TCMD" "$PING_TIMEOUT" "$@"
  else
    "$@"
  fi
}

QUIET=0
MODELS=()

for arg in "$@"; do
  case "$arg" in
    --quiet|-q) QUIET=1 ;;
    gemini|codex|qwen) MODELS+=("$arg") ;;
  esac
done

if [ ${#MODELS[@]} -eq 0 ]; then
  MODELS=(gemini codex qwen)
fi

ALL_OK=1
RESULTS=""

ping_model() {
  local model="$1"
  local start end elapsed exit_code output

  start=$(python3 -c "import time; print(int(time.time()*1000))")

  case "$model" in
    gemini)
      output=$(run_timed gemini -m gemini-2.5-flash -p "Reply with only the word PONG" 2>&1)
      exit_code=$?
      ;;
    codex)
      output=$(run_timed codex exec --ephemeral --skip-git-repo-check --dangerously-bypass-approvals-and-sandbox "Reply with only the word PONG. Do not create or modify any files." 2>&1)
      exit_code=$?
      ;;
    qwen)
      output=$(run_timed qwen -m qwen-max "Reply with only the word PONG" --approval-mode yolo --output-format text 2>&1)
      exit_code=$?
      ;;
  esac

  end=$(python3 -c "import time; print(int(time.time()*1000))")
  elapsed=$(( (end - start) ))

  # Determine status
  local status color_status
  if [ "$exit_code" -eq 0 ]; then
    status="healthy"
    color_status="${GREEN}${B}✓ healthy${R}"
  elif [ "$exit_code" -eq 124 ]; then
    status="timeout"
    color_status="${RED}${B}✗ timeout${R}"
    ALL_OK=0
  else
    status="error"
    color_status="${RED}${B}✗ error${R}"
    ALL_OK=0
  fi

  # Format latency
  local latency_str
  if [ "$elapsed" -lt 1000 ]; then
    latency_str="${elapsed}ms"
  else
    latency_str="$(( elapsed / 1000 )).$(( (elapsed % 1000) / 100 ))s"
  fi

  # Get model color and icon
  local C ICON MODEL_UPPER
  eval "C=\$COLORS_${model}"
  eval "ICON=\$ICONS_${model}"
  MODEL_UPPER=$(echo "$model" | tr '[:lower:]' '[:upper:]')

  if [ "$QUIET" -eq 0 ]; then
    printf '  %b %b  %b  %b%s%b' \
      "${C}${B}${ICON} ${MODEL_UPPER}${R}" \
      "$color_status" \
      "${D}${latency_str}${R}" \
      "${D}" \
      "$(echo "$output" | head -1 | cut -c1-40)" \
      "${R}"
    echo

    # Show error detail on failure
    if [ "$exit_code" -ne 0 ] && [ -n "$output" ]; then
      local err_line
      err_line=$(echo "$output" | head -3 | tr '\n' ' ' | cut -c1-70)
      printf '    %b%s%b\n' "${D}" "$err_line" "${R}"
    fi
  fi
}

if [ "$QUIET" -eq 0 ]; then
  echo
  printf '  %b%bAI Model Health Check%b  %b%s%b\n' "$B" "" "$R" "$D" "$(date '+%H:%M:%S')" "$R"
  printf '  %s\n' "────────────────────────────────────────────────────"
fi

for model in "${MODELS[@]}"; do
  ping_model "$model"
done

if [ "$QUIET" -eq 0 ]; then
  printf '  %s\n' "────────────────────────────────────────────────────"
  if [ "$ALL_OK" -eq 1 ]; then
    printf '  %bAll models healthy%b\n' "${GREEN}" "${R}"
  else
    printf '  %bSome models unreachable%b\n' "${YELLOW}" "${R}"
  fi
  echo
fi

if [ "$ALL_OK" -eq 1 ]; then
  exit 0
else
  exit 1
fi
