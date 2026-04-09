#!/bin/bash
# ai-fan — fan-out the same task to all models in parallel, compare results
# Models are read from capabilities.json — adding a new model works automatically.
#
# Usage:
#   ai-fan "analyze this code for security issues" [context_file]
#   ai-fan --models gemini,qwen "review this code"

if [ $# -lt 1 ]; then
  echo "Usage: $0 [--models model1,model2,...] \"<prompt>\" [context_file]" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/ai-models.sh"

R="$AI_RESET"; B="$AI_BOLD"; D="$AI_DIM"
GREEN="$AI_GREEN"; RED="$AI_RED"

# Default to all models from capabilities.json
DEFAULT_MODELS=$(list_models | tr ' ' ',')
MODELS_CSV="$DEFAULT_MODELS"
PROMPT=""
CONTEXT_FILE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --models) MODELS_CSV="$2"; shift 2 ;;
    *) if [ -z "$PROMPT" ]; then PROMPT="$1"; else CONTEXT_FILE="$1"; fi; shift ;;
  esac
done

[ -z "$PROMPT" ] && { echo "Error: no prompt provided" >&2; exit 1; }

SESSION_ID="fan-$(date +%s)"
export AI_SESSION="$SESSION_ID"
OUT_DIR="/tmp/ai-fan-${SESSION_ID}"
mkdir -p "$OUT_DIR"

FULL_PROMPT="$PROMPT"
if [ -n "$CONTEXT_FILE" ] && [ -f "$CONTEXT_FILE" ]; then
  FULL_PROMPT="${PROMPT}

Code:
\`\`\`
$(cat "$CONTEXT_FILE")
\`\`\`"
fi

printf '\n  %b%bFan-Out%b  %b%s%b\n' "$B" "" "$R" "$D" "$(date '+%H:%M:%S')" "$R"
printf '  %s\n' "────────────────────────────────────────────────────"
printf '  %bPrompt:%b %s\n' "$B" "$R" "$(echo "$PROMPT" | head -1 | cut -c1-60)"
[ -n "$CONTEXT_FILE" ] && printf '  %bContext:%b %s\n' "$B" "$R" "$CONTEXT_FILE"
printf '  %bOutput:%b %s\n' "$B" "$R" "$OUT_DIR/"
printf '  %s\n\n' "────────────────────────────────────────────────────"

IFS=',' read -ra MODEL_LIST <<< "$MODELS_CSV"
PIDS=()

for model in "${MODEL_LIST[@]}"; do
  load_model "$model"
  out_file="${OUT_DIR}/${model}.txt"
  case "$model" in
    gemini)
      "$SCRIPT_DIR/ai-delegate.sh" gemini "$PROMPT" "$out_file" \
        gemini -m gemini-2.5-pro -p "$FULL_PROMPT" & ;;
    codex)
      "$SCRIPT_DIR/ai-delegate.sh" codex "$PROMPT" "$out_file" \
        codex exec --ephemeral --skip-git-repo-check --dangerously-bypass-approvals-and-sandbox "$FULL_PROMPT" -o "$out_file" & ;;
    qwen)
      "$SCRIPT_DIR/ai-delegate.sh" qwen "$PROMPT" "$out_file" \
        qwen -m qwen-max "$FULL_PROMPT" --approval-mode yolo --output-format text & ;;
    *)
      if command -v "$model" >/dev/null 2>&1; then
        "$SCRIPT_DIR/ai-delegate.sh" "$model" "$PROMPT" "$out_file" \
          "$model" -m "$MODEL_ID" "$FULL_PROMPT" &
      else
        echo "  Unknown model CLI: $model" >&2; continue
      fi ;;
  esac
  PIDS+=($!)
done

printf '  %bWaiting for %d models…%b\n\n' "$D" "${#PIDS[@]}" "$R"
EXITS=()
for pid in "${PIDS[@]}"; do wait "$pid"; EXITS+=($?); done

# Results
printf '\n  %b%bFan-Out Results%b  %b%s%b\n' "$B" "" "$R" "$D" "$(date '+%H:%M:%S')" "$R"
printf '  %s\n' "════════════════════════════════════════════════════════════════════"

idx=0
for model in "${MODEL_LIST[@]}"; do
  load_model "$model"
  out_file="${OUT_DIR}/${model}.txt"
  exit_code="${EXITS[$idx]}"
  MODEL_UPPER=$(echo "$model" | tr '[:lower:]' '[:upper:]')

  if [ "$exit_code" -eq 0 ] && [ -s "$out_file" ]; then
    sym="${GREEN}${B}✓${R}"; lines=$(wc -l < "$out_file" | tr -d ' '); size=$(wc -c < "$out_file" | tr -d ' ')
  else
    sym="${RED}${B}✗${R}"; lines=0; size=0
  fi

  printf '\n  %b%b%s %s%b  %b  %b%s lines, %s bytes%b\n' \
    "$MODEL_COLOR" "$B" "$MODEL_ICON" "$MODEL_UPPER" "$R" "$sym" "$D" "$lines" "$size" "$R"
  printf '  %b%s%b\n' "$MODEL_COLOR" "────────────────────────────────────────────────────────────────" "$R"

  if [ -s "$out_file" ]; then
    total_lines=$(wc -l < "$out_file" | tr -d ' ')
    if [ "$total_lines" -gt 30 ]; then
      head -30 "$out_file" | while IFS= read -r line; do printf '  %s\n' "$line"; done
      printf '\n  %b… %d more lines — full: %s%b\n' "$D" "$(( total_lines - 30 ))" "$out_file" "$R"
    else
      while IFS= read -r line; do printf '  %s\n' "$line"; done < "$out_file"
    fi
  else
    printf '  %b(no output)%b\n' "$D" "$R"
  fi
  idx=$(( idx + 1 ))
done

printf '\n  %s\n' "════════════════════════════════════════════════════════════════════"
success=0; failed=0
for ec in "${EXITS[@]}"; do [ "$ec" -eq 0 ] && success=$(( success + 1 )) || failed=$(( failed + 1 )); done
printf '  %b%d/%d succeeded%b' "$GREEN" "$success" "${#MODEL_LIST[@]}" "$R"
[ "$failed" -gt 0 ] && printf '  %b%d failed%b' "$RED" "$failed" "$R"
printf '  %bSession: %s%b\n\n' "$D" "$SESSION_ID" "$R"
