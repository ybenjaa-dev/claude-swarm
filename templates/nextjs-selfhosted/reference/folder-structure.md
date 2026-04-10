# Folder Structure Reference

```
my-app/
├── src/
│   ├── app/                              # Next.js App Router (THIN layer)
│   │   ├── [locale]/                     # Locale-prefixed routes
│   │   │   ├── (marketing)/              # Public pages (route group)
│   │   │   │   ├── page.tsx              # Landing page
│   │   │   │   ├── pricing/page.tsx
│   │   │   │   └── layout.tsx
│   │   │   ├── (auth)/                   # Login/signup (route group)
│   │   │   │   ├── login/
│   │   │   │   │   ├── page.tsx
│   │   │   │   │   └── _components/
│   │   │   │   └── signup/page.tsx
│   │   │   ├── (dashboard)/              # Protected area (route group)
│   │   │   │   ├── dashboard/page.tsx
│   │   │   │   ├── settings/page.tsx
│   │   │   │   └── layout.tsx
│   │   │   ├── layout.tsx                # Root layout with i18n provider
│   │   │   └── not-found.tsx
│   │   ├── api/                          # Route handlers (thin)
│   │   │   ├── auth/
│   │   │   │   ├── login/route.ts
│   │   │   │   ├── logout/route.ts
│   │   │   │   ├── refresh/route.ts
│   │   │   │   └── me/route.ts
│   │   │   ├── users/
│   │   │   │   ├── route.ts
│   │   │   │   └── [id]/route.ts
│   │   │   └── health/route.ts
│   │   └── global.css                    # Tailwind imports
│   │
│   ├── components/
│   │   ├── ui/                           # shadcn primitives
│   │   │   ├── button.tsx
│   │   │   ├── input.tsx
│   │   │   ├── dialog.tsx
│   │   │   └── ...
│   │   ├── shared/                       # reusable composites
│   │   │   ├── header.tsx
│   │   │   ├── footer.tsx
│   │   │   └── language-switcher.tsx
│   │   └── [feature]/                    # feature-specific
│   │       ├── user-list.tsx
│   │       └── user-card.tsx
│   │
│   ├── hooks/                            # Custom React hooks (client)
│   │   ├── use-debounce.ts
│   │   └── use-media-query.ts
│   │
│   ├── i18n/                             # next-intl setup
│   │   ├── config.ts
│   │   ├── request.ts
│   │   └── locales/
│   │       ├── en.json
│   │       ├── ar.json
│   │       └── fr.json
│   │
│   ├── lib/                              # Shared library code
│   │   ├── env.ts                        # Zod-validated env (ALWAYS import from here)
│   │   ├── logger.ts                     # Pino/similar structured logger
│   │   ├── db/
│   │   │   └── mongoose.ts               # Connection singleton
│   │   ├── redis/
│   │   │   ├── client.ts                 # ioredis singleton
│   │   │   ├── cache.ts                  # cached() helper
│   │   │   ├── rate-limit.ts
│   │   │   └── token-blacklist.ts
│   │   ├── storage/
│   │   │   └── b2.ts                     # Backblaze S3 client + presigned URLs
│   │   ├── email/
│   │   │   ├── resend.ts
│   │   │   └── templates/                # React Email templates
│   │   ├── auth/
│   │   │   ├── jwt.ts                    # sign/verify
│   │   │   ├── cookies.ts                # httpOnly cookie helpers
│   │   │   └── password.ts               # bcrypt wrappers
│   │   ├── api/
│   │   │   └── client.ts                 # Typed fetch client for TanStack Query
│   │   └── schemas/                      # Zod schemas
│   │       ├── auth.schema.ts
│   │       ├── user.schema.ts
│   │       └── ...
│   │
│   ├── server/                           # BACKEND — never import from app/
│   │   ├── controllers/                  # HTTP layer
│   │   │   ├── auth.controller.ts
│   │   │   └── user.controller.ts
│   │   ├── services/                     # Business logic (pure)
│   │   │   ├── auth.service.ts
│   │   │   ├── user.service.ts
│   │   │   └── __tests__/                # Vitest tests
│   │   │       └── user.service.test.ts
│   │   ├── models/                       # Mongoose schemas
│   │   │   ├── user.model.ts
│   │   │   └── ...
│   │   ├── middlewares/
│   │   │   ├── auth.middleware.ts        # withAuth() HOC + getCurrentUser()
│   │   │   ├── rate-limit.middleware.ts
│   │   │   └── error.middleware.ts
│   │   ├── queues/                       # BullMQ queues
│   │   │   ├── email.queue.ts
│   │   │   └── upload.queue.ts
│   │   ├── workers/                      # BullMQ workers (separate process)
│   │   │   ├── index.ts
│   │   │   ├── email.worker.ts
│   │   │   └── upload.worker.ts
│   │   └── errors/
│   │       ├── app-error.ts              # NotFoundError, ConflictError, etc.
│   │       └── handle.ts                 # handleError() for controllers
│   │
│   ├── queries/                          # TanStack Query hooks
│   │   ├── use-auth.ts
│   │   └── use-users.ts
│   │
│   ├── store/                            # Zustand stores (UI state only)
│   │   ├── use-ui-store.ts
│   │   └── use-cart-store.ts
│   │
│   ├── types/                            # Shared TS types
│   │   ├── i18n.d.ts
│   │   └── api.d.ts
│   │
│   └── utils/                            # Pure utilities
│       ├── cn.ts                         # shadcn classname helper
│       ├── format-date.ts
│       └── slugify.ts
│
├── proxy.ts                              # Next.js 16 proxy (auth + i18n)
├── next.config.ts
├── tailwind.config.ts
├── tsconfig.json
├── vitest.config.ts
├── playwright.config.ts
├── Dockerfile
├── docker-compose.yml
├── docker-compose.prod.yml
├── worker.ts                             # Entry point for worker process
├── .env.example
├── .env                                  # gitignored
└── CLAUDE.md                             # project instructions for Claude
```

## Import Rules

- **`app/` can import from:** `components/`, `hooks/`, `lib/`, `server/services/*`, `queries/`, `store/`, `i18n/`
- **`server/` can import from:** `lib/`, other files in `server/`
- **`server/` MUST NOT import from:** `app/`, `components/`, `hooks/`, `store/`, `queries/`
- **`components/` can import from:** `lib/`, `hooks/`, `store/`, `queries/`, `i18n/`
- **Services MUST NOT import:** `next/*` (except `next/headers` in auth helpers), React, JSX

This keeps the business logic framework-agnostic and testable in isolation.
