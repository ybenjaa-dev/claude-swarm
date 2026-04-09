#!/bin/bash
# ai-ping — health check AI delegate models (reads models from capabilities.json)
#
# Usage:
#   ai-ping           # check all models
#   ai-ping gemini    # check single model
#   ai-ping --quiet   # exit code only (0 = all healthy)

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/ai-models.sh"

R="$AI_RESET"; B="$AI_BOLD"; D="$AI_DIM"
GREEN="$AI_GREEN"; RED="$AI_RED"; YELLOW="$AI_YELLOW"
PING_TIMEOUT=15

if command -v gtimeout >/dev/null 2>&1; then TCMD="gtimeout"
elif command -v timeout >/dev/null 2>&1; then TCMD="timeout"
else TCMD=""; fi

run_timed() { if [ -n "$TCMD" ]; then "$TCMD" "$PING_TIMEOUT" "$@"; else "$@"; fi; }

QUIET=0
MODELS=()
for arg in "$@"; do
  case "$arg" in --quiet|-q) QUIET=1 ;; *) MODELS+=("$arg") ;; esac
done
[ ${#MODELS[@]} -eq 0 ] && IFS=' ' read -ra MODELS <<< "$(list_models)"

ALL_OK=1

ping_model() {
  local model="$1"
  load_model "$model"
  local ping_id="$MODEL_ID"
  [ -n "$MODEL_FALLBACK" ] && ping_id="$MODEL_FALLBACK"
  local MODEL_UPPER
  MODEL_UPPER=$(echo "$model" | tr '[:lower:]' '[:upper:]')

  local start end elapsed exit_code output
  start=$(python3 -c "import time; print(int(time.time()*1000))")

  case "$model" in
    gemini) output=$(run_timed gemini -m "$ping_id" -p "Reply with only the word PONG" 2>&1); exit_code=$? ;;
    codex)  output=$(run_timed codex exec --ephemeral --skip-git-repo-check --dangerously-bypass-approvals-and-sandbox "Reply with only the word PONG. Do not create or modify any files." 2>&1); exit_code=$? ;;
    qwen)   output=$(run_timed qwen -m "$ping_id" "Reply with only the word PONG" --approval-mode yolo --output-format text 2>&1); exit_code=$? ;;
    *)
      if command -v "$model" >/dev/null 2>&1; then
        output=$(run_timed "$model" -m "$ping_id" "Reply with only the word PONG" 2>&1); exit_code=$?
      else output="CLI '$model' not found"; exit_code=127; fi ;;
  esac

  end=$(python3 -c "import time; print(int(time.time()*1000))")
  elapsed=$(( end - start ))

  local color_status
  if [ "$exit_code" -eq 0 ]; then color_status="${GREEN}${B}✓ healthy${R}"
  elif [ "$exit_code" -eq 124 ]; then color_status="${RED}${B}✗ timeout${R}"; ALL_OK=0
  else color_status="${RED}${B}✗ error${R}"; ALL_OK=0; fi

  local latency_str
  if [ "$elapsed" -lt 1000 ]; then latency_str="${elapsed}ms"
  else latency_str="$(( elapsed / 1000 )).$(( (elapsed % 1000) / 100 ))s"; fi

  if [ "$QUIET" -eq 0 ]; then
    printf '  %b %b  %b  %b%s%b\n' \
      "${MODEL_COLOR}${B}${MODEL_ICON} ${MODEL_UPPER}${R}" \
      "$color_status" "${D}${latency_str}${R}" \
      "${D}" "$(echo "$output" | head -1 | cut -c1-40)" "${R}"
    if [ "$exit_code" -ne 0 ] && [ -n "$output" ]; then
      printf '    %b%s%b\n' "${D}" "$(echo "$output" | head -3 | tr '\n' ' ' | cut -c1-70)" "${R}"
    fi
  fi
}

if [ "$QUIET" -eq 0 ]; then
  echo; printf '  %b%bAI Model Health Check%b  %b%s%b\n' "$B" "" "$R" "$D" "$(date '+%H:%M:%S')" "$R"
  printf '  %s\n' "────────────────────────────────────────────────────"
fi

for model in "${MODELS[@]}"; do ping_model "$model"; done

if [ "$QUIET" -eq 0 ]; then
  printf '  %s\n' "────────────────────────────────────────────────────"
  if [ "$ALL_OK" -eq 1 ]; then printf '  %bAll models healthy%b\n' "$GREEN" "$R"
  else printf '  %bSome models unreachable%b\n' "$YELLOW" "$R"; fi
  echo
fi
[ "$ALL_OK" -eq 1 ] && exit 0 || exit 1
