#!/bin/bash
# ai-verify — quality gate for AI-generated code
#
# Runs lint + typecheck + test + build in parallel, auto-detects the stack
# (Next.js/TypeScript, Flutter, Python, etc.), fails fast on first error.
#
# Use after Claude makes changes to catch AI hallucinations before they ship.
#
# Usage:
#   ai-verify              # auto-detect stack, run all checks
#   ai-verify --no-build   # skip build (faster — just lint + typecheck + test)
#   ai-verify --quick      # just lint + typecheck (fastest)
#   ai-verify lint         # run only a specific check

set -o pipefail

R="\033[0m"; B="\033[1m"; D="\033[2m"
GREEN="\033[38;2;80;220;100m"
RED="\033[38;2;240;80;80m"
YELLOW="\033[38;2;255;200;50m"
CYAN="\033[38;2;26;188;156m"

# ── Parse args ───────────────────────────────────────────────────────────────
MODE="full"
SINGLE_CHECK=""
for arg in "$@"; do
  case "$arg" in
    --quick)    MODE="quick" ;;
    --no-build) MODE="nobuild" ;;
    lint|typecheck|test|build) SINGLE_CHECK="$arg" ;;
  esac
done

# ── Detect stack ─────────────────────────────────────────────────────────────
STACK=""
if [ -f "package.json" ]; then
  if grep -q '"next"' package.json 2>/dev/null; then
    STACK="nextjs"
  else
    STACK="node"
  fi
elif [ -f "pubspec.yaml" ]; then
  STACK="flutter"
elif [ -f "pyproject.toml" ] || [ -f "requirements.txt" ]; then
  STACK="python"
else
  printf '  %b✗ No recognized project detected in %s%b\n' "$RED" "$(pwd)" "$R" >&2
  exit 1
fi

# ── Helpers ──────────────────────────────────────────────────────────────────
TMP_DIR=$(mktemp -d -t ai-verify-XXXXXX)
trap 'rm -rf "$TMP_DIR"' EXIT

run_check() {
  local name="$1"; local cmd="$2"; local icon="$3"
  local log="$TMP_DIR/$name.log"
  local start=$(python3 -c "import time; print(int(time.time()*1000))")
  printf '  %b%s %-12s%b %b⟳ running…%b\n' "$CYAN" "$icon" "$name" "$R" "$D" "$R"
  local exit_code=0
  bash -c "$cmd" > "$log" 2>&1 || exit_code=$?
  local end=$(python3 -c "import time; print(int(time.time()*1000))")
  local elapsed=$(( (end - start) / 1000 ))
  if [ "$exit_code" -eq 0 ]; then
    printf '\033[1A\033[K  %b%s %-12s%b %b✓ passed%b  %b%ds%b\n' "$CYAN" "$icon" "$name" "$R" "${GREEN}${B}" "$R" "$D" "$elapsed" "$R"
    return 0
  else
    printf '\033[1A\033[K  %b%s %-12s%b %b✗ failed%b  %b%ds%b\n' "$CYAN" "$icon" "$name" "$R" "${RED}${B}" "$R" "$D" "$elapsed" "$R"
    printf '\n  %b%s error output:%b\n' "$RED" "$name" "$R"
    tail -30 "$log" | sed 's/^/    /'
    printf '\n  %bFull log: %s%b\n\n' "$D" "$log" "$R"
    return $exit_code
  fi
}

run_parallel() {
  local -a names=()
  local -a cmds=()
  local -a pids=()
  local -a results=()

  while [ $# -gt 0 ]; do
    names+=("$1"); cmds+=("$2"); shift 2
  done

  # Start all in background, capturing each one's output + exit code
  for i in "${!names[@]}"; do
    (
      local log="$TMP_DIR/${names[$i]}.log"
      local start=$(python3 -c "import time; print(int(time.time()*1000))")
      bash -c "${cmds[$i]}" > "$log" 2>&1
      local ec=$?
      local end=$(python3 -c "import time; print(int(time.time()*1000))")
      echo "$ec $(( (end - start) / 1000 ))" > "$TMP_DIR/${names[$i]}.status"
    ) &
    pids+=($!)
  done

  # Wait for all, then report in order
  for pid in "${pids[@]}"; do wait "$pid"; done

  local all_ok=1
  for i in "${!names[@]}"; do
    local name="${names[$i]}"
    local status_file="$TMP_DIR/$name.status"
    local ec elapsed
    read -r ec elapsed < "$status_file"
    local icon="${ICONS[$name]:-●}"
    if [ "$ec" -eq 0 ]; then
      printf '  %b%s %-12s%b %b✓ passed%b  %b%ds%b\n' "$CYAN" "$icon" "$name" "$R" "${GREEN}${B}" "$R" "$D" "$elapsed" "$R"
    else
      printf '  %b%s %-12s%b %b✗ failed%b  %b%ds%b\n' "$CYAN" "$icon" "$name" "$R" "${RED}${B}" "$R" "$D" "$elapsed" "$R"
      all_ok=0
    fi
  done

  # Print error output for any failures
  if [ "$all_ok" -eq 0 ]; then
    printf '\n'
    for i in "${!names[@]}"; do
      local name="${names[$i]}"
      local ec
      read -r ec _ < "$TMP_DIR/$name.status"
      if [ "$ec" -ne 0 ]; then
        printf '  %b─── %s error output ───%b\n' "$RED" "$name" "$R"
        tail -30 "$TMP_DIR/$name.log" | sed 's/^/    /'
        printf '\n'
      fi
    done
  fi

  return $(( 1 - all_ok ))
}

declare -A ICONS=(
  [lint]="◆" [typecheck]="⬡" [test]="◈" [build]="●" [analyze]="◆" [format]="⬡"
)

# ── Header ───────────────────────────────────────────────────────────────────
printf '\n  %b%bai-verify%b  %bstack: %s%b  %bmode: %s%b\n\n' \
  "$CYAN" "$B" "$R" "$D" "$STACK" "$R" "$D" "$MODE" "$R"

# ── Run checks per stack ─────────────────────────────────────────────────────
OVERALL_START=$(python3 -c "import time; print(int(time.time()*1000))")

case "$STACK" in
  nextjs|node)
    # Figure out package manager
    if [ -f "pnpm-lock.yaml" ]; then PM="pnpm"
    elif [ -f "yarn.lock" ]; then PM="yarn"
    else PM="npm"; fi

    # Detect available scripts
    has_script() {
      grep -q "\"$1\":" package.json 2>/dev/null
    }

    CHECKS=()
    if [ -n "$SINGLE_CHECK" ]; then
      case "$SINGLE_CHECK" in
        lint)      CHECKS=("lint" "$PM run lint") ;;
        typecheck) CHECKS=("typecheck" "npx tsc --noEmit") ;;
        test)      CHECKS=("test" "$PM test -- --run 2>/dev/null || $PM test") ;;
        build)     CHECKS=("build" "$PM run build") ;;
      esac
    else
      # Always lint + typecheck
      if has_script "lint"; then CHECKS+=("lint" "$PM run lint"); fi
      CHECKS+=("typecheck" "npx tsc --noEmit")
      # Test unless quick mode
      if [ "$MODE" != "quick" ] && has_script "test"; then
        CHECKS+=("test" "$PM test -- --run 2>/dev/null || $PM test 2>&1 | head -100")
      fi
      # Build only in full mode
      if [ "$MODE" = "full" ] && has_script "build"; then
        CHECKS+=("build" "$PM run build")
      fi
    fi
    ;;

  flutter)
    CHECKS=()
    if [ -n "$SINGLE_CHECK" ]; then
      case "$SINGLE_CHECK" in
        lint|analyze) CHECKS=("analyze" "flutter analyze") ;;
        format)       CHECKS=("format" "dart format --set-exit-if-changed lib test") ;;
        test)         CHECKS=("test" "flutter test") ;;
        build)        CHECKS=("build" "flutter build apk --debug") ;;
      esac
    else
      CHECKS+=("analyze" "flutter analyze")
      CHECKS+=("format" "dart format --set-exit-if-changed lib test")
      if [ "$MODE" != "quick" ]; then
        CHECKS+=("test" "flutter test")
      fi
      if [ "$MODE" = "full" ]; then
        CHECKS+=("build" "flutter build apk --debug")
      fi
    fi
    ;;

  python)
    CHECKS=()
    if command -v ruff >/dev/null 2>&1; then
      CHECKS+=("lint" "ruff check .")
    fi
    if command -v mypy >/dev/null 2>&1; then
      CHECKS+=("typecheck" "mypy .")
    fi
    if [ "$MODE" != "quick" ] && command -v pytest >/dev/null 2>&1; then
      CHECKS+=("test" "pytest --tb=short")
    fi
    ;;
esac

if [ ${#CHECKS[@]} -eq 0 ]; then
  printf '  %b⚠ No checks to run (no matching scripts or tools found)%b\n\n' "$YELLOW" "$R"
  exit 0
fi

# ── Run all checks in parallel ───────────────────────────────────────────────
run_parallel "${CHECKS[@]}"
OVERALL_EC=$?

OVERALL_END=$(python3 -c "import time; print(int(time.time()*1000))")
TOTAL_S=$(( (OVERALL_END - OVERALL_START) / 1000 ))

printf '\n'
if [ "$OVERALL_EC" -eq 0 ]; then
  printf '  %b✓ All checks passed%b  %b%ds total%b\n\n' "${GREEN}${B}" "$R" "$D" "$TOTAL_S" "$R"
  # Play success sound if not silent
  if [ "${AI_SILENT:-0}" != "1" ] && [ -f /System/Library/Sounds/Glass.aiff ]; then
    afplay /System/Library/Sounds/Glass.aiff &>/dev/null &
  fi
else
  printf '  %b✗ Verification failed%b  %b%ds total%b\n\n' "${RED}${B}" "$R" "$D" "$TOTAL_S" "$R"
  if [ "${AI_SILENT:-0}" != "1" ] && [ -f /System/Library/Sounds/Basso.aiff ]; then
    afplay /System/Library/Sounds/Basso.aiff &>/dev/null &
  fi
fi

exit $OVERALL_EC
