# Next.js Self-Hosted Stack Template

A battle-tested Next.js 16 stack for developers who want **full control** and **no vendor lock-in**. Deploy to any cheap VPS (Hetzner, DigitalOcean, Contabo).

## Stack

| Layer | Tech | Why |
|---|---|---|
| Framework | Next.js 16 App Router + TypeScript strict | Modern, fast, type-safe |
| UI | Tailwind CSS + shadcn/ui | Full control, no runtime cost |
| Client state | Zustand | Minimal, no boilerplate |
| Server state | TanStack Query | Caching, refetching, optimistic updates |
| Database | MongoDB + Mongoose | Full control over schemas |
| Cache/Queue | Redis + ioredis | Caching, rate limiting, BullMQ |
| Auth | Custom JWT (jsonwebtoken + bcrypt) | No vendor lock-in |
| Jobs | BullMQ | Reliable, Redis-backed |
| Storage | Backblaze B2 (S3-compatible) | Way cheaper than AWS S3 |
| Email | Resend | Best DX for transactional email |
| i18n | next-intl | App Router native, type-safe |
| Validation | Zod | Type inference + runtime safety |
| Testing | Vitest + Playwright | Fast unit + reliable e2e |
| DevOps | Docker + Nginx | Self-host on any VPS |

## What's In This Template

```
nextjs-selfhosted/
├── CLAUDE.md                    # Project instructions for Claude Code
├── prompts/                     # Reusable prompt templates
│   ├── nextjs-feature-scaffold.md
│   ├── nextjs-mongoose-model.md
│   ├── nextjs-service-layer.md
│   ├── nextjs-route-handler.md
│   ├── nextjs-server-action.md
│   ├── nextjs-auth-jwt.md
│   ├── nextjs-i18n-setup.md
│   ├── nextjs-shadcn-page.md
│   ├── nextjs-tanstack-query.md
│   ├── nextjs-zustand-store.md
│   └── nextjs-bullmq-job.md
└── reference/                   # Drop-in reference files
    ├── env.example
    ├── Dockerfile
    ├── docker-compose.yml
    └── folder-structure.md
```

## Usage

### Starting a new project

```bash
# Create the Next.js project
npx create-next-app@latest my-app --typescript --tailwind --app
cd my-app

# Drop in the stack template
cp ~/path/to/claude-swarm/templates/nextjs-selfhosted/CLAUDE.md ./CLAUDE.md
cp ~/path/to/claude-swarm/templates/nextjs-selfhosted/reference/env.example ./.env.example
cp ~/path/to/claude-swarm/templates/nextjs-selfhosted/reference/Dockerfile ./Dockerfile
cp ~/path/to/claude-swarm/templates/nextjs-selfhosted/reference/docker-compose.yml ./docker-compose.yml

# Install stack dependencies
npm i mongoose ioredis jsonwebtoken bcrypt zod next-intl \
      @tanstack/react-query zustand \
      bullmq @aws-sdk/client-s3 @aws-sdk/s3-request-presigner resend
npm i -D @types/jsonwebtoken @types/bcrypt vitest @playwright/test

# Claude Code is now configured — start building
```

### Using prompt templates

When you need to build something, reference the template in your prompt:

```
Use ~/path/to/claude-swarm/templates/nextjs-selfhosted/prompts/nextjs-feature-scaffold.md
Feature: Product
Fields: name (string, required), price (number), slug (unique string), description, images (array of urls)
Operations: full CRUD
```

Claude will generate the full layered implementation.

## Key Principles

1. **Layered architecture** — Route → Controller → Service → Model
2. **No hardcoded strings** — everything translated via next-intl
3. **Type safety everywhere** — Zod at boundaries, TS strict throughout
4. **Self-hostable** — no vendor lock-in anywhere
5. **Security first** — JWT with refresh rotation, Redis blacklist, bcrypt cost 12

## License

MIT — part of [claude-swarm](https://github.com/ybenjaa-dev/claude-swarm).
