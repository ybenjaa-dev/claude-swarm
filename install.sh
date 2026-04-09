#!/bin/bash
# claude-swarm installer — one-click setup for multi-AI delegation in Claude Code
#
# What it does:
#   1. Copies delegate scripts + prompt templates to ~/.claude/assets/
#   2. Installs GNU coreutils (for gtimeout on macOS)
#   3. Appends ai-* aliases and completions to ~/.zshrc
#   4. Optionally installs iTerm2 status bar components
#   5. Appends AI delegation config to your CLAUDE.md
#   6. Checks that Gemini, Codex, and Qwen CLIs are installed
#
# Usage: ./install.sh

set -e

R="\033[0m"
B="\033[1m"
D="\033[2m"
GREEN="\033[38;2;80;220;100m"
RED="\033[38;2;240;80;80m"
YELLOW="\033[38;2;255;200;50m"
CYAN="\033[38;2;26;188;156m"
PURPLE="\033[38;2;200;28;222m"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ASSETS_DIR="$HOME/.claude/assets"
PROMPTS_DIR="$ASSETS_DIR/prompts"
ZSHRC="$HOME/.zshrc"
CLAUDE_MD="$HOME/.claude/CLAUDE.md"
MARKER="# >>> claude-swarm >>>"
MARKER_END="# <<< claude-swarm <<<"

step=0
total=6

progress() {
  step=$((step + 1))
  printf '\n  %b[%d/%d]%b %b%s%b\n' "$CYAN" "$step" "$total" "$R" "$B" "$1" "$R"
}

ok()   { printf '    %b✓%b %s\n' "$GREEN" "$R" "$1"; }
warn() { printf '    %b⚠%b %s\n' "$YELLOW" "$R" "$1"; }
fail() { printf '    %b✗%b %s\n' "$RED" "$R" "$1"; }

# ── Header ────────────────────────────────────────────────────────────────────
printf '\n'
printf '  %b%b╔══════════════════════════════════════════════╗%b\n' "$CYAN" "$B" "$R"
printf '  %b%b║                                              ║%b\n' "$CYAN" "$B" "$R"
printf '  %b%b║   ◆ ⬡ ◈  claude-swarm  installer            ║%b\n' "$CYAN" "$B" "$R"
printf '  %b%b║   Give Claude Code 3 extra brains.           ║%b\n' "$CYAN" "$B" "$R"
printf '  %b%b║                                              ║%b\n' "$CYAN" "$B" "$R"
printf '  %b%b╚══════════════════════════════════════════════╝%b\n' "$CYAN" "$B" "$R"
printf '\n'

# ── Step 1: Copy assets ──────────────────────────────────────────────────────
progress "Installing scripts and templates"

mkdir -p "$ASSETS_DIR" "$PROMPTS_DIR" "$HOME/.claude/blackboard"

cp "$SCRIPT_DIR/assets/ai-delegate.sh"    "$ASSETS_DIR/"
cp "$SCRIPT_DIR/assets/ai-status.py"      "$ASSETS_DIR/"
cp "$SCRIPT_DIR/assets/ai-read.py"        "$ASSETS_DIR/"
cp "$SCRIPT_DIR/assets/ai-board.py"       "$ASSETS_DIR/"
cp "$SCRIPT_DIR/assets/ai-stats.py"       "$ASSETS_DIR/"
cp "$SCRIPT_DIR/assets/ai-ping.sh"        "$ASSETS_DIR/"
cp "$SCRIPT_DIR/assets/ai-fan.sh"         "$ASSETS_DIR/"
cp "$SCRIPT_DIR/assets/ai-badge.py"       "$ASSETS_DIR/"
cp "$SCRIPT_DIR/assets/capabilities.json" "$ASSETS_DIR/"

for f in "$SCRIPT_DIR/assets/prompts/"*.md; do
  cp "$f" "$PROMPTS_DIR/"
done

chmod +x "$ASSETS_DIR/ai-delegate.sh" "$ASSETS_DIR/ai-ping.sh" "$ASSETS_DIR/ai-fan.sh"
chmod +x "$ASSETS_DIR/ai-status.py" "$ASSETS_DIR/ai-read.py" "$ASSETS_DIR/ai-board.py" "$ASSETS_DIR/ai-stats.py"

ok "Scripts installed to $ASSETS_DIR/"
ok "$(ls "$SCRIPT_DIR/assets/prompts/"*.md | wc -l | tr -d ' ') prompt templates installed"

# ── Step 2: Install dependencies ─────────────────────────────────────────────
progress "Checking dependencies"

# GNU coreutils (for gtimeout)
if command -v gtimeout >/dev/null 2>&1; then
  ok "gtimeout already installed"
elif command -v timeout >/dev/null 2>&1; then
  ok "timeout already available"
elif command -v brew >/dev/null 2>&1; then
  printf '    Installing GNU coreutils (for gtimeout)...\n'
  brew install coreutils 2>/dev/null
  ok "GNU coreutils installed"
else
  warn "No timeout command found. Install GNU coreutils: brew install coreutils"
fi

# Python 3
if command -v python3 >/dev/null 2>&1; then
  ok "Python 3 found: $(python3 --version 2>&1)"
else
  fail "Python 3 not found — required for monitoring scripts"
  exit 1
fi

# ── Step 3: Setup zshrc aliases ──────────────────────────────────────────────
progress "Configuring shell aliases"

if grep -q "$MARKER" "$ZSHRC" 2>/dev/null; then
  # Remove old block and re-add
  sed -i '' "/$MARKER/,/$MARKER_END/d" "$ZSHRC"
  warn "Replaced existing claude-swarm config in .zshrc"
fi

cat >> "$ZSHRC" << 'ZSHRC_BLOCK'

# >>> claude-swarm >>>
# AI Delegate Monitor — https://github.com/youssefbenjaa/claude-swarm
alias ai-status="python3 ~/.claude/assets/ai-status.py"
alias ai-watch="python3 ~/.claude/assets/ai-status.py --watch"
alias ai-all="python3 ~/.claude/assets/ai-status.py --all"
alias ai-read="python3 ~/.claude/assets/ai-read.py"
alias ai-board="python3 ~/.claude/assets/ai-board.py"
alias ai-stats="python3 ~/.claude/assets/ai-stats.py"
alias ai-ping="bash ~/.claude/assets/ai-ping.sh"
alias ai-fan="bash ~/.claude/assets/ai-fan.sh"
ai-clear() {
  local log="$HOME/.claude/ai-tasks.log"
  if [ -f "$log" ]; then
    local lines=$(wc -l < "$log" | tr -d ' ')
    if [ "$lines" -gt 200 ]; then
      tail -200 "$log" > "${log}.tmp" && mv "${log}.tmp" "$log"
      echo "AI task log rotated (kept last 200 of $lines lines)"
    else
      true > "$log"
      echo "AI task log cleared"
    fi
  fi
}
ai-follow() {
  local log="$HOME/.claude/ai-tasks.log"
  if [ ! -f "$log" ]; then echo "No task log found."; return 1; fi
  local out
  out=$(awk -F $'\x1f' '$2=="START" {file=$7} END {print file}' "$log")
  if [ -z "$out" ]; then echo "No delegate output file found."; return 1; fi
  echo "Following: $out"
  tail -f "$out"
}
# Auto log rotation (silent, on shell startup)
() {
  local log="$HOME/.claude/ai-tasks.log"
  if [ -f "$log" ]; then
    local lines=$(wc -l < "$log" | tr -d ' ')
    if [ "$lines" -gt 1000 ]; then
      tail -500 "$log" > "${log}.tmp" && mv "${log}.tmp" "$log"
    fi
  fi
} 2>/dev/null
# Zsh completions
_ai_read()  { if (( CURRENT == 2 )); then compadd gemini codex qwen claude; elif (( CURRENT == 3 )); then compadd 1 2 3 5 10; fi }
_ai_board() { if (( CURRENT == 2 )); then compadd clean wipe $(ls "$HOME/.claude/blackboard" 2>/dev/null); elif (( CURRENT == 3 )); then compadd gemini codex qwen; fi }
_ai_stats() { compadd gemini codex qwen claude --json }
_ai_ping()  { compadd gemini codex qwen --quiet }
_ai_fan()   { if [[ "$words[CURRENT-1]" == "--models" ]]; then compadd "gemini,codex,qwen" "gemini,qwen" "gemini,codex" "codex,qwen"; else compadd --models; fi }
compdef _ai_read ai-read; compdef _ai_board ai-board; compdef _ai_stats ai-stats; compdef _ai_ping ai-ping; compdef _ai_fan ai-fan
# <<< claude-swarm <<<
ZSHRC_BLOCK

ok "Aliases and completions added to $ZSHRC"

# ── Step 4: CLAUDE.md config ─────────────────────────────────────────────────
progress "Configuring Claude Code"

if [ -f "$CLAUDE_MD" ]; then
  if grep -q "ai-delegate.sh" "$CLAUDE_MD"; then
    ok "CLAUDE.md already has AI delegation config"
  else
    printf '\n' >> "$CLAUDE_MD"
    cat "$SCRIPT_DIR/claude-swarm.md" >> "$CLAUDE_MD"
    ok "AI delegation config appended to CLAUDE.md"
  fi
else
  mkdir -p "$(dirname "$CLAUDE_MD")"
  cp "$SCRIPT_DIR/claude-swarm.md" "$CLAUDE_MD"
  ok "Created CLAUDE.md with AI delegation config"
fi

# ── Step 5: iTerm2 (optional) ────────────────────────────────────────────────
progress "iTerm2 status bar (optional)"

ITERM_DIR="$HOME/.config/iterm2/AppSupport/Scripts/AutoLaunch"
ITERM_DIR_ALT="$HOME/Library/Application Support/iTerm2/Scripts/AutoLaunch"

if [ -d "$ITERM_DIR" ] || [ -d "$ITERM_DIR_ALT" ]; then
  printf '    Install Claude usage + AI delegates status bar? [Y/n] '
  read -r reply
  if [[ "$reply" =~ ^[Nn]$ ]]; then
    warn "Skipped iTerm2 status bar"
  else
    TARGET_DIR="$ITERM_DIR"
    [ ! -d "$TARGET_DIR" ] && TARGET_DIR="$ITERM_DIR_ALT"
    mkdir -p "$TARGET_DIR"
    cp "$SCRIPT_DIR/iterm2/claude_usage.py" "$TARGET_DIR/"
    ok "iTerm2 status bar installed — restart iTerm2 to activate"
    ok "Then: Profiles → Session → Configure Status Bar → add 'Claude Usage' and 'AI Delegates'"
  fi
else
  warn "iTerm2 not detected — skipping status bar. Install iTerm2 and re-run to enable."
fi

# ── Step 6: Check AI CLIs ────────────────────────────────────────────────────
progress "Checking AI model CLIs"

check_cli() {
  local name="$1" cmd="$2" install="$3"
  if command -v "$cmd" >/dev/null 2>&1; then
    ok "$name CLI found: $(which "$cmd")"
  else
    warn "$name CLI not found. Install: $install"
  fi
}

check_cli "Gemini" "gemini" "npm i -g @anthropic-ai/claude-code  # then: gemini auth"
check_cli "Codex" "codex" "npm i -g @openai/codex"
check_cli "Qwen" "qwen" "pip install qwen-cli  # or see Qwen docs"

# ── Done ──────────────────────────────────────────────────────────────────────
printf '\n'
printf '  %b%b╔══════════════════════════════════════════════╗%b\n' "$GREEN" "$B" "$R"
printf '  %b%b║                                              ║%b\n' "$GREEN" "$B" "$R"
printf '  %b%b║   ✓  claude-swarm installed successfully!    ║%b\n' "$GREEN" "$B" "$R"
printf '  %b%b║                                              ║%b\n' "$GREEN" "$B" "$R"
printf '  %b%b╚══════════════════════════════════════════════╝%b\n' "$GREEN" "$B" "$R"
printf '\n'
printf '  %bNext steps:%b\n' "$B" "$R"
printf '    1. Run %bsource ~/.zshrc%b to activate\n' "$CYAN" "$R"
printf '    2. Run %bai-ping%b to verify all models are reachable\n' "$CYAN" "$R"
printf '    3. Start Claude Code and ask it to delegate tasks!\n'
printf '\n'
printf '  %bCommands:%b\n' "$B" "$R"
printf '    ai-status   — delegate task dashboard\n'
printf '    ai-watch    — live-updating dashboard\n'
printf '    ai-stats    — per-model analytics\n'
printf '    ai-ping     — health check all models\n'
printf '    ai-fan      — same task → 3 models → compare\n'
printf '    ai-read     — view delegate outputs\n'
printf '    ai-board    — view blackboard sessions\n'
printf '    ai-follow   — tail running delegate\n'
printf '    ai-clear    — rotate task log\n'
printf '\n'
