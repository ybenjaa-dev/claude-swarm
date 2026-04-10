#!/bin/bash
# ai-ping — health check AI delegate models in parallel
#
# Usage:
#   ai-ping           # check all models (parallel)
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

# Tmp dir for parallel results (preserves per-model ordering)
TMP_DIR=$(mktemp -d -t ai-ping-XXXXXX)
trap 'rm -rf "$TMP_DIR"' EXIT

# ── Worker: pings a single model, writes result to tmp file ───────────────────
ping_model() {
  local model="$1"
  local idx="$2"
  local result_file="$TMP_DIR/$idx-$model"

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

  local color_status status_tag
  if [ "$exit_code" -eq 0 ]; then
    color_status="${GREEN}${B}✓ healthy${R}"; status_tag="ok"
  elif [ "$exit_code" -eq 124 ]; then
    color_status="${RED}${B}✗ timeout${R}"; status_tag="fail"
  else
    color_status="${RED}${B}✗ error${R}"; status_tag="fail"
  fi

  local latency_str
  if [ "$elapsed" -lt 1000 ]; then latency_str="${elapsed}ms"
  else latency_str="$(( elapsed / 1000 )).$(( (elapsed % 1000) / 100 ))s"; fi

  # Write formatted output + status tag to per-model file
  {
    printf 'STATUS=%s\n' "$status_tag"
    printf '  %b %b  %b  %b%s%b\n' \
      "${MODEL_COLOR}${B}${MODEL_ICON} ${MODEL_UPPER}${R}" \
      "$color_status" "${D}${latency_str}${R}" \
      "${D}" "$(echo "$output" | head -1 | cut -c1-40)" "${R}"
    if [ "$exit_code" -ne 0 ] && [ -n "$output" ]; then
      printf '    %b%s%b\n' "${D}" "$(echo "$output" | head -3 | tr '\n' ' ' | cut -c1-70)" "${R}"
    fi
  } > "$result_file"
}

# ── Header ────────────────────────────────────────────────────────────────────
if [ "$QUIET" -eq 0 ]; then
  echo
  printf '  %b%bAI Model Health Check%b  %b%s%b\n' "$B" "" "$R" "$D" "$(date '+%H:%M:%S')" "$R"
  printf '  %s\n' "────────────────────────────────────────────────────"
fi

# ── Fan-out: fire all pings in parallel ──────────────────────────────────────
PIDS=()
for i in "${!MODELS[@]}"; do
  ping_model "${MODELS[$i]}" "$i" &
  PIDS+=($!)
done

# Wait for all pings to complete
for pid in "${PIDS[@]}"; do wait "$pid"; done

# ── Fan-in: print results in original model order ────────────────────────────
ALL_OK=1
for i in "${!MODELS[@]}"; do
  result_file="$TMP_DIR/$i-${MODELS[$i]}"
  if [ -f "$result_file" ]; then
    # First line is STATUS=ok/fail, rest is formatted output
    status=$(head -1 "$result_file")
    [ "$status" != "STATUS=ok" ] && ALL_OK=0
    [ "$QUIET" -eq 0 ] && tail -n +2 "$result_file"
  fi
done

if [ "$QUIET" -eq 0 ]; then
  printf '  %s\n' "────────────────────────────────────────────────────"
  if [ "$ALL_OK" -eq 1 ]; then printf '  %bAll models healthy%b\n' "$GREEN" "$R"
  else printf '  %bSome models unreachable%b\n' "$YELLOW" "$R"; fi
  echo
fi

[ "$ALL_OK" -eq 1 ] && exit 0 || exit 1
