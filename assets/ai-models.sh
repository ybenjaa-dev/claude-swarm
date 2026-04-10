#!/bin/bash
# ai-models.sh — shared model config loader for all bash scripts.
#
# On first load (or when capabilities.json changes), generates a cached
# shell-sourceable file at .models-cache.sh. Subsequent calls avoid
# spawning python3 entirely, making load_model effectively free.
#
# After calling load_model, these vars are set:
#   MODEL_ICON, MODEL_COLOR, MODEL_TIMEOUT, MODEL_CONTEXT_WINDOW,
#   MODEL_DISPLAY, MODEL_ID, MODEL_FALLBACK

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CAPABILITIES_FILE="$SCRIPT_DIR/capabilities.json"
CACHE_FILE="$SCRIPT_DIR/.models-cache.sh"

if [ ! -f "$CAPABILITIES_FILE" ]; then
  CAPABILITIES_FILE="$HOME/.claude/assets/capabilities.json"
  CACHE_FILE="$HOME/.claude/assets/.models-cache.sh"
fi

# Common ANSI codes
AI_RESET="\033[0m"
AI_BOLD="\033[1m"
AI_DIM="\033[2m"
AI_GREEN="\033[38;2;80;220;100m"
AI_RED="\033[38;2;240;80;80m"
AI_YELLOW="\033[38;2;255;200;50m"

# ── Cache generation ──────────────────────────────────────────────────────────

_regenerate_model_cache() {
  [ ! -f "$CAPABILITIES_FILE" ] && return 1
  command -v python3 >/dev/null 2>&1 || return 1

  python3 - "$CAPABILITIES_FILE" <<'PYEOF' > "${CACHE_FILE}.tmp" 2>/dev/null && mv "${CACHE_FILE}.tmp" "$CACHE_FILE"
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
models = data.get("models", {})
names = list(models.keys())

print("# Auto-generated from capabilities.json — do not edit manually")
print(f'_CACHED_MODEL_NAMES="{" ".join(names)}"')
print()
print("_load_model_from_cache() {")
print("  case \"$1\" in")
for name, cfg in models.items():
    c = cfg.get("color", "#888888").lstrip("#")
    r, g, b = int(c[0:2], 16), int(c[2:4], 16), int(c[4:6], 16)
    color = f"\\033[38;2;{r};{g};{b}m"
    icon = cfg.get("icon", "●")
    timeout = cfg.get("timeout_seconds", 300)
    ctx = cfg.get("context_window", 128000)
    display = cfg.get("display_name", name.upper()).replace('"', '\\"')
    model_id = cfg.get("model_id", name)
    fallback = cfg.get("fallback_model") or ""
    print(f"    {name})")
    print(f'      MODEL_ICON="{icon}"')
    print(f'      MODEL_COLOR="{color}"')
    print(f"      MODEL_TIMEOUT={timeout}")
    print(f"      MODEL_CONTEXT_WINDOW={ctx}")
    print(f'      MODEL_DISPLAY="{display}"')
    print(f'      MODEL_ID="{model_id}"')
    print(f'      MODEL_FALLBACK="{fallback}"')
    print(f"      return 0 ;;")
print("    *) return 1 ;;")
print("  esac")
print("}")
PYEOF
}

_ensure_model_cache() {
  # Regenerate if: cache missing, OR capabilities.json is newer than cache
  if [ ! -f "$CACHE_FILE" ] || [ "$CAPABILITIES_FILE" -nt "$CACHE_FILE" ]; then
    _regenerate_model_cache
  fi
}

# Build cache on first source, then load it into memory
_ensure_model_cache
[ -f "$CACHE_FILE" ] && source "$CACHE_FILE"

# ── Public API ────────────────────────────────────────────────────────────────

load_model() {
  local model="$1"

  # Fast path: cached function (no subprocess)
  if type _load_model_from_cache >/dev/null 2>&1; then
    _load_model_from_cache "$model" && return 0
  fi

  # Hardcoded fallback if cache generation failed
  case "$model" in
    gemini)
      MODEL_ICON="◆"; MODEL_COLOR="\033[38;2;26;188;156m"; MODEL_TIMEOUT=300
      MODEL_CONTEXT_WINDOW=1000000; MODEL_DISPLAY="Gemini 2.5 Pro"
      MODEL_ID="gemini-2.5-pro"; MODEL_FALLBACK="gemini-2.5-flash" ;;
    codex)
      MODEL_ICON="⬡"; MODEL_COLOR="\033[38;2;42;166;62m"; MODEL_TIMEOUT=600
      MODEL_CONTEXT_WINDOW=128000; MODEL_DISPLAY="GPT-5.4 (Codex)"
      MODEL_ID="gpt-5.4"; MODEL_FALLBACK="" ;;
    qwen)
      MODEL_ICON="◈"; MODEL_COLOR="\033[38;2;200;28;222m"; MODEL_TIMEOUT=180
      MODEL_CONTEXT_WINDOW=32768; MODEL_DISPLAY="Qwen Max"
      MODEL_ID="qwen-max"; MODEL_FALLBACK="" ;;
    *)
      MODEL_ICON="●"; MODEL_COLOR="\033[38;2;136;136;136m"; MODEL_TIMEOUT=300
      MODEL_CONTEXT_WINDOW=128000
      MODEL_DISPLAY="$(echo "$model" | tr '[:lower:]' '[:upper:]')"
      MODEL_ID="$model"; MODEL_FALLBACK="" ;;
  esac
}

list_models() {
  # Returns space-separated list of model names
  if [ -n "$_CACHED_MODEL_NAMES" ]; then
    echo "$_CACHED_MODEL_NAMES"
  else
    echo "gemini codex qwen"
  fi
}
