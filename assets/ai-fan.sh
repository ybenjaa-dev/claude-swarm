#!/bin/bash
# ai-fan — fan-out the same task to all 3 models in parallel, compare results
#
# Runs Gemini, Codex, and Qwen on the same prompt simultaneously,
# waits for all to finish, then shows a side-by-side comparison.
#
# Usage:
#   ai-fan "analyze this code for security issues" [context_file]
#   ai-fan "explain this function" src/auth.ts
#   ai-fan --models gemini,qwen "review this code"
#
# Output files: /tmp/ai-fan-{session}/{gemini,codex,qwen}.txt

if [ $# -lt 1 ]; then
  echo "Usage: $0 [--models model1,model2,...] \"<prompt>\" [context_file]" >&2
  exit 1
fi

# Parse arguments
MODELS="gemini,codex,qwen"
PROMPT=""
CONTEXT_FILE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --models) MODELS="$2"; shift 2 ;;
    *)
      if [ -z "$PROMPT" ]; then
        PROMPT="$1"
      else
        CONTEXT_FILE="$1"
      fi
      shift
      ;;
  esac
done

if [ -z "$PROMPT" ]; then
  echo "Error: no prompt provided" >&2
  exit 1
fi

# Setup
SESSION_ID="fan-$(date +%s)"
export AI_SESSION="$SESSION_ID"
OUT_DIR="/tmp/ai-fan-${SESSION_ID}"
mkdir -p "$OUT_DIR"

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

# Build full prompt with optional context
FULL_PROMPT="$PROMPT"
if [ -n "$CONTEXT_FILE" ] && [ -f "$CONTEXT_FILE" ]; then
  CONTEXT=$(cat "$CONTEXT_FILE")
  FULL_PROMPT="${PROMPT}

Code:
\`\`\`
${CONTEXT}
\`\`\`"
fi

# Header
printf '\n'
printf '  %b%bFan-Out: 3 Models, 1 Task%b  %b%s%b\n' "$B" "" "$R" "$D" "$(date '+%H:%M:%S')" "$R"
printf '  %s\n' "────────────────────────────────────────────────────"
printf '  %bPrompt:%b %s\n' "$B" "$R" "$(echo "$PROMPT" | head -1 | cut -c1-60)"
if [ -n "$CONTEXT_FILE" ]; then
  printf '  %bContext:%b %s\n' "$B" "$R" "$CONTEXT_FILE"
fi
printf '  %bOutput:%b %s\n' "$B" "$R" "$OUT_DIR/"
printf '  %s\n\n' "────────────────────────────────────────────────────"

# Fan-out: launch all models in parallel
IFS=',' read -ra MODEL_LIST <<< "$MODELS"
PIDS=()

for model in "${MODEL_LIST[@]}"; do
  out_file="${OUT_DIR}/${model}.txt"
  case "$model" in
    gemini)
      ~/.claude/assets/ai-delegate.sh gemini "$PROMPT" "$out_file" \
        gemini -m gemini-2.5-pro -p "$FULL_PROMPT" &
      ;;
    codex)
      ~/.claude/assets/ai-delegate.sh codex "$PROMPT" "$out_file" \
        codex exec --ephemeral --skip-git-repo-check --dangerously-bypass-approvals-and-sandbox "$FULL_PROMPT" -o "$out_file" &
      ;;
    qwen)
      ~/.claude/assets/ai-delegate.sh qwen "$PROMPT" "$out_file" \
        qwen -m qwen-max "$FULL_PROMPT" --approval-mode yolo --output-format text &
      ;;
    *)
      echo "Unknown model: $model" >&2
      continue
      ;;
  esac
  PIDS+=($!)
done

# Wait for all to finish
printf '  %bWaiting for %d models…%b\n\n' "$D" "${#PIDS[@]}" "$R"
EXITS=()
for pid in "${PIDS[@]}"; do
  wait "$pid"
  EXITS+=($?)
done

# ── Results comparison ────────────────────────────────────────────────────────

printf '\n'
printf '  %b%bFan-Out Results%b  %b%s%b\n' "$B" "" "$R" "$D" "$(date '+%H:%M:%S')" "$R"
printf '  %s\n' "════════════════════════════════════════════════════════════════════"

idx=0
for model in "${MODEL_LIST[@]}"; do
  out_file="${OUT_DIR}/${model}.txt"
  exit_code="${EXITS[$idx]}"
  eval "C=\$COLORS_${model}"
  eval "ICON=\$ICONS_${model}"
  MODEL_UPPER=$(echo "$model" | tr '[:lower:]' '[:upper:]')

  if [ "$exit_code" -eq 0 ] && [ -s "$out_file" ]; then
    sym="${GREEN}${B}✓${R}"
    lines=$(wc -l < "$out_file" | tr -d ' ')
    size=$(wc -c < "$out_file" | tr -d ' ')
  else
    sym="${RED}${B}✗${R}"
    lines=0
    size=0
  fi

  printf '\n  %b%b%s %s%b  %b  %b%s lines, %s bytes%b\n' \
    "$C" "$B" "$ICON" "$MODEL_UPPER" "$R" "$sym" "$D" "$lines" "$size" "$R"
  printf '  %b%s%b\n' "$C" "────────────────────────────────────────────────────────────────" "$R"

  if [ -s "$out_file" ]; then
    total_lines=$(wc -l < "$out_file" | tr -d ' ')
    if [ "$total_lines" -gt 30 ]; then
      head -30 "$out_file" | while IFS= read -r line; do
        printf '  %s\n' "$line"
      done
      printf '\n  %b… %d more lines — full: %s%b\n' "$D" "$(( total_lines - 30 ))" "$out_file" "$R"
    else
      while IFS= read -r line; do
        printf '  %s\n' "$line"
      done < "$out_file"
    fi
  else
    printf '  %b(no output)%b\n' "$D" "$R"
  fi

  idx=$(( idx + 1 ))
done

printf '\n  %s\n' "════════════════════════════════════════════════════════════════════"

# Summary
success=0
failed=0
for ec in "${EXITS[@]}"; do
  if [ "$ec" -eq 0 ]; then
    success=$(( success + 1 ))
  else
    failed=$(( failed + 1 ))
  fi
done

printf '  %b%d/%d succeeded%b' "$GREEN" "$success" "${#MODEL_LIST[@]}" "$R"
if [ "$failed" -gt 0 ]; then
  printf '  %b%d failed%b' "$RED" "$failed" "$R"
fi
printf '  %bSession: %s%b\n\n' "$D" "$SESSION_ID" "$R"
