#!/bin/bash
# ai-models.sh — shared model config loader for all bash scripts.
#
# Sources model metadata (icon, color, timeout) from capabilities.json.
# Source this file, then call: load_model <name>
#
# After calling load_model, these vars are set:
#   MODEL_ICON, MODEL_COLOR, MODEL_TIMEOUT, MODEL_CONTEXT_WINDOW,
#   MODEL_DISPLAY, MODEL_ID, MODEL_FALLBACK

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CAPABILITIES_FILE="$SCRIPT_DIR/capabilities.json"

if [ ! -f "$CAPABILITIES_FILE" ]; then
  CAPABILITIES_FILE="$HOME/.claude/assets/capabilities.json"
fi

# Common ANSI codes
AI_RESET="\033[0m"
AI_BOLD="\033[1m"
AI_DIM="\033[2m"
AI_GREEN="\033[38;2;80;220;100m"
AI_RED="\033[38;2;240;80;80m"
AI_YELLOW="\033[38;2;255;200;50m"

load_model() {
  local model="$1"

  if [ -f "$CAPABILITIES_FILE" ] && command -v python3 >/dev/null 2>&1; then
    local py_output
    py_output=$(python3 -c "
import json, sys
with open('$CAPABILITIES_FILE') as f:
    data = json.load(f)
m = data.get('models', {}).get('$model', {})
if m:
    c = m.get('color', '#888888').lstrip('#')
    r, g, b = int(c[0:2],16), int(c[2:4],16), int(c[4:6],16)
    print(f'MODEL_ICON=\"{m.get(\"icon\", \"●\")}\"')
    print(f'MODEL_COLOR=\"\\033[38;2;{r};{g};{b}m\"')
    print(f'MODEL_TIMEOUT={m.get(\"timeout_seconds\", 300)}')
    print(f'MODEL_CONTEXT_WINDOW={m.get(\"context_window\", 128000)}')
    print(f'MODEL_DISPLAY=\"{m.get(\"display_name\", \"$model\".upper())}\"')
    print(f'MODEL_ID=\"{m.get(\"model_id\", \"$model\")}\"')
    print(f'MODEL_FALLBACK=\"{m.get(\"fallback_model\", \"\") or \"\"}\"')
else:
    sys.exit(1)
" 2>/dev/null)
    if [ $? -eq 0 ] && [ -n "$py_output" ]; then
      eval "$py_output"
      return 0
    fi
  fi

  # Hardcoded fallback
  case "$model" in
    gemini) MODEL_ICON="◆"; MODEL_COLOR="\033[38;2;26;188;156m"; MODEL_TIMEOUT=300; MODEL_CONTEXT_WINDOW=1000000; MODEL_DISPLAY="Gemini 2.5 Pro"; MODEL_ID="gemini-2.5-pro"; MODEL_FALLBACK="gemini-2.5-flash" ;;
    codex)  MODEL_ICON="⬡"; MODEL_COLOR="\033[38;2;42;166;62m";  MODEL_TIMEOUT=600; MODEL_CONTEXT_WINDOW=128000;  MODEL_DISPLAY="GPT-5.4 (Codex)"; MODEL_ID="gpt-5.4"; MODEL_FALLBACK="" ;;
    qwen)   MODEL_ICON="◈"; MODEL_COLOR="\033[38;2;200;28;222m"; MODEL_TIMEOUT=180; MODEL_CONTEXT_WINDOW=32768;   MODEL_DISPLAY="Qwen Max"; MODEL_ID="qwen-max"; MODEL_FALLBACK="" ;;
    *)      MODEL_ICON="●"; MODEL_COLOR="\033[38;2;136;136;136m"; MODEL_TIMEOUT=300; MODEL_CONTEXT_WINDOW=128000;  MODEL_DISPLAY="$(echo "$model" | tr '[:lower:]' '[:upper:]')"; MODEL_ID="$model"; MODEL_FALLBACK="" ;;
  esac
}

list_models() {
  # Returns space-separated list of model names from capabilities.json
  if [ -f "$CAPABILITIES_FILE" ] && command -v python3 >/dev/null 2>&1; then
    python3 -c "
import json
with open('$CAPABILITIES_FILE') as f:
    data = json.load(f)
print(' '.join(data.get('models', {}).keys()))
" 2>/dev/null
  else
    echo "gemini codex qwen"
  fi
}
