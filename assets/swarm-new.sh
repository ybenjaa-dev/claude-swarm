#!/bin/bash
# swarm-new — bootstrap a new project with a stack template from claude-swarm
#
# Usage:
#   swarm-new nextjs <project-name>     # Next.js self-hosted stack
#   swarm-new nextjs                    # uses current directory
#
# What it does:
#   1. Runs create-next-app with strict defaults
#   2. Installs stack dependencies (mongoose, ioredis, next-intl, etc.)
#   3. Drops in CLAUDE.md, Dockerfile, docker-compose.yml, .env.example
#   4. Copies prompt templates to ~/.claude/assets/prompts/nextjs/
#   5. Initializes git (if needed)

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

R="\033[0m"; B="\033[1m"; D="\033[2m"
GREEN="\033[38;2;80;220;100m"
RED="\033[38;2;240;80;80m"
CYAN="\033[38;2;26;188;156m"
YELLOW="\033[38;2;255;200;50m"

ok()   { printf '  %b✓%b %s\n' "$GREEN" "$R" "$1"; }
warn() { printf '  %b⚠%b %s\n' "$YELLOW" "$R" "$1"; }
step() { printf '\n  %b▍%b %b%s%b\n' "$CYAN" "$R" "$B" "$1" "$R"; }
err()  { printf '  %b✗%b %s\n' "$RED" "$R" "$1"; }

usage() {
  cat <<EOF
Usage: swarm-new <template> [project-name]

Templates:
  nextjs    Next.js 16 self-hosted stack (App Router, MongoDB, Redis, JWT, i18n)

Examples:
  swarm-new nextjs my-app
  swarm-new nextjs                # uses current directory

EOF
}

if [ $# -lt 1 ]; then
  usage
  exit 1
fi

TEMPLATE="$1"
PROJECT_NAME="${2:-}"

case "$TEMPLATE" in
  nextjs)
    TEMPLATE_DIR="$REPO_ROOT/templates/nextjs-selfhosted"
    ;;
  *)
    err "Unknown template: $TEMPLATE"
    usage
    exit 1
    ;;
esac

if [ ! -d "$TEMPLATE_DIR" ]; then
  err "Template directory not found: $TEMPLATE_DIR"
  exit 1
fi

# ── Banner ───────────────────────────────────────────────────────────────────
printf '\n'
printf '  %b%b◆ ⬡ ◈  swarm-new  %b  %btemplate: %s%b\n' "$CYAN" "$B" "$R" "$D" "$TEMPLATE" "$R"
printf '\n'

# ── Step 1: Create or enter project directory ───────────────────────────────
if [ -n "$PROJECT_NAME" ]; then
  step "Scaffolding Next.js project: $PROJECT_NAME"
  if [ -d "$PROJECT_NAME" ]; then
    err "Directory '$PROJECT_NAME' already exists"
    exit 1
  fi

  # Use create-next-app with strict defaults
  npx --yes create-next-app@latest "$PROJECT_NAME" \
    --typescript \
    --tailwind \
    --app \
    --src-dir \
    --import-alias "@/*" \
    --eslint \
    --no-turbopack \
    --use-npm

  cd "$PROJECT_NAME"
else
  step "Using current directory: $(pwd)"
  if [ ! -f "package.json" ]; then
    err "No package.json found. Run 'npx create-next-app' first or provide a project name."
    exit 1
  fi
fi

PROJECT_DIR="$(pwd)"

# ── Step 2: Install stack dependencies ──────────────────────────────────────
step "Installing stack dependencies"

DEPS=(
  mongoose
  ioredis
  jsonwebtoken
  bcrypt
  zod
  next-intl
  "@tanstack/react-query"
  "@tanstack/react-query-devtools"
  zustand
  bullmq
  "@aws-sdk/client-s3"
  "@aws-sdk/s3-request-presigner"
  resend
  sonner
  "class-variance-authority"
  "clsx"
  "tailwind-merge"
  "lucide-react"
)

DEV_DEPS=(
  "@types/jsonwebtoken"
  "@types/bcrypt"
  vitest
  "@vitest/ui"
  "@playwright/test"
  "@testing-library/react"
  "@testing-library/jest-dom"
)

npm install "${DEPS[@]}" --silent 2>&1 | tail -5
ok "Runtime dependencies installed"

npm install -D "${DEV_DEPS[@]}" --silent 2>&1 | tail -5
ok "Dev dependencies installed"

# ── Step 3: Drop in stack files ─────────────────────────────────────────────
step "Installing stack template files"

cp "$TEMPLATE_DIR/CLAUDE.md" ./CLAUDE.md
ok "CLAUDE.md"

if [ -f "$TEMPLATE_DIR/reference/env.example" ]; then
  cp "$TEMPLATE_DIR/reference/env.example" ./.env.example
  ok ".env.example"
fi

if [ -f "$TEMPLATE_DIR/reference/Dockerfile" ]; then
  cp "$TEMPLATE_DIR/reference/Dockerfile" ./Dockerfile
  ok "Dockerfile"
fi

if [ -f "$TEMPLATE_DIR/reference/docker-compose.yml" ]; then
  cp "$TEMPLATE_DIR/reference/docker-compose.yml" ./docker-compose.yml
  ok "docker-compose.yml"
fi

mkdir -p docs
cp "$TEMPLATE_DIR/reference/folder-structure.md" ./docs/folder-structure.md
ok "docs/folder-structure.md"

# ── Step 4: Create stack folder skeleton ────────────────────────────────────
step "Creating layered architecture folders"

mkdir -p \
  src/server/{controllers,services,models,middlewares,queues,workers,errors} \
  src/lib/{db,redis,storage,email,auth,api,schemas} \
  src/queries \
  src/store \
  src/i18n/locales \
  src/types \
  src/utils \
  src/components/{ui,shared}

# Create stub files so imports don't break immediately
touch src/server/controllers/.gitkeep
touch src/server/services/.gitkeep
touch src/server/models/.gitkeep
touch src/server/middlewares/.gitkeep
touch src/server/queues/.gitkeep
touch src/server/workers/.gitkeep
touch src/server/errors/.gitkeep
touch src/lib/db/.gitkeep
touch src/lib/redis/.gitkeep
touch src/lib/storage/.gitkeep
touch src/lib/email/.gitkeep
touch src/lib/auth/.gitkeep
touch src/lib/api/.gitkeep
touch src/lib/schemas/.gitkeep
touch src/queries/.gitkeep
touch src/store/.gitkeep
touch src/i18n/locales/.gitkeep
touch src/types/.gitkeep
touch src/utils/.gitkeep

ok "Folder structure created"

# ── Step 5: Install prompt templates ────────────────────────────────────────
step "Installing prompt templates"

PROMPTS_DIR="$HOME/.claude/assets/prompts/nextjs"
mkdir -p "$PROMPTS_DIR"
cp "$TEMPLATE_DIR/prompts/"*.md "$PROMPTS_DIR/" 2>/dev/null || warn "No prompt templates found"
ok "Prompts installed to $PROMPTS_DIR/"

# ── Step 6: Init git (if needed) ─────────────────────────────────────────────
if [ ! -d ".git" ]; then
  step "Initializing git"
  git init -q
  ok "Git initialized"
fi

# ── Done ─────────────────────────────────────────────────────────────────────
printf '\n'
printf '  %b%b✓ Project scaffolded successfully!%b\n' "$GREEN" "$B" "$R"
printf '\n'
printf '  %bNext steps:%b\n' "$B" "$R"
if [ -n "$PROJECT_NAME" ]; then
  printf '    1. %bcd %s%b\n' "$CYAN" "$PROJECT_NAME" "$R"
  printf '    2. %bcp .env.example .env%b and fill in values\n' "$CYAN" "$R"
  printf '    3. %bdocker-compose up -d mongo redis%b\n' "$CYAN" "$R"
  printf '    4. %bnpm run dev%b\n' "$CYAN" "$R"
else
  printf '    1. %bcp .env.example .env%b and fill in values\n' "$CYAN" "$R"
  printf '    2. %bdocker-compose up -d mongo redis%b\n' "$CYAN" "$R"
  printf '    3. %bnpm run dev%b\n' "$CYAN" "$R"
fi
printf '\n'
printf '  %bPrompt templates available at:%b\n' "$B" "$R"
printf '    %s%s%b\n' "$D" "$PROMPTS_DIR/" "$R"
printf '\n'
printf '  %bWhen asking Claude to build features, reference:%b\n' "$B" "$R"
printf '    %b"Use the nextjs-feature-scaffold template to build a Product feature"%b\n' "$D" "$R"
printf '\n'
