#!/bin/bash
# claude-swarm uninstaller — cleanly removes everything

set -e

R="\033[0m"
B="\033[1m"
GREEN="\033[38;2;80;220;100m"
RED="\033[38;2;240;80;80m"
YELLOW="\033[38;2;255;200;50m"

ZSHRC="$HOME/.zshrc"
MARKER="# >>> claude-swarm >>>"
MARKER_END="# <<< claude-swarm <<<"

ok()   { printf '  %b✓%b %s\n' "$GREEN" "$R" "$1"; }
warn() { printf '  %b⚠%b %s\n' "$YELLOW" "$R" "$1"; }

printf '\n  %b%bUninstalling claude-swarm…%b\n\n' "$B" "" "$R"

# Remove assets
FILES=(
  ai-delegate.sh ai-status.py ai-read.py ai-board.py
  ai-stats.py ai-ping.sh ai-fan.sh ai-badge.py capabilities.json
)
for f in "${FILES[@]}"; do
  rm -f "$HOME/.claude/assets/$f"
done
rm -rf "$HOME/.claude/assets/prompts"
ok "Removed scripts and templates"

# Remove task log
rm -f "$HOME/.claude/ai-tasks.log"
ok "Removed task log"

# Remove blackboard
rm -rf "$HOME/.claude/blackboard"
ok "Removed blackboard directory"

# Remove zshrc block
if grep -q "$MARKER" "$ZSHRC" 2>/dev/null; then
  sed -i '' "/$MARKER/,/$MARKER_END/d" "$ZSHRC"
  ok "Removed aliases from .zshrc"
else
  warn "No claude-swarm block found in .zshrc"
fi

# Remove iTerm2 script
for dir in "$HOME/.config/iterm2/AppSupport/Scripts/AutoLaunch" "$HOME/Library/Application Support/iTerm2/Scripts/AutoLaunch"; do
  if [ -f "$dir/claude_usage.py" ]; then
    rm -f "$dir/claude_usage.py"
    ok "Removed iTerm2 status bar script"
  fi
done

printf '\n  %b%b✓ claude-swarm uninstalled.%b Run %bsource ~/.zshrc%b to apply.\n\n' "$GREEN" "$B" "$R" "$B" "$R"
