# Project Instructions — Next.js Self-Hosted Stack

> Drop this file into any Next.js project root. Claude Code will auto-load it.

## Stack (NON-NEGOTIABLE)

- **Framework:** Next.js 16 (App Router only) + TypeScript strict
- **Styling:** Tailwind CSS + shadcn/ui
- **Client State:** Zustand (UI state only)
- **Server State:** TanStack Query (API data, caching)
- **Database:** MongoDB + Mongoose (never Prisma)
- **Cache/Queue:** Redis + ioredis
- **Auth:** Custom JWT (jsonwebtoken + bcrypt) — never NextAuth/Clerk
- **Jobs:** BullMQ
- **Storage:** Backblaze B2 (S3-compatible) with pre-signed URLs
- **Email:** Resend
- **Validation:** Zod (everywhere data crosses a boundary)
- **Hosting:** Docker → Nginx/Traefik → Hetzner VPS
- **Testing:** Vitest (unit) + Playwright (e2e)
- **i18n:** `next-intl` (App Router native) — **all user-facing strings MUST be translated**

## Folder Structure (MANDATORY)

```
src/
  app/                        # Next.js App Router (thin layer only)
    (auth)/                   # Route groups
    api/                      # Route Handlers — thin, delegate to controllers
      [resource]/route.ts     # imports from server/controllers
    layout.tsx
    page.tsx
    loading.tsx
    error.tsx
    not-found.tsx
  components/
    ui/                       # shadcn primitives (generated)
    shared/                   # reusable composite components
    [feature]/                # feature-specific components
  hooks/                      # custom React hooks (client)
  lib/
    db/
      mongoose.ts             # connection singleton
    redis/
      client.ts               # ioredis singleton
      cache.ts                # cache helpers
      rate-limit.ts
    storage/
      b2.ts                   # Backblaze S3 client
    email/
      resend.ts               # Resend client
    env.ts                    # Zod-validated env (IMPORT FROM HERE)
    logger.ts                 # structured logger
  server/                     # BACKEND LOGIC — never import from app/
    controllers/              # HTTP layer: parse req, call service, format res
      user.controller.ts
    services/                 # business logic (pure, testable)
      user.service.ts
    models/                   # Mongoose schemas + models
      user.model.ts
    middlewares/              # auth, rate-limit, cors
      auth.middleware.ts
    queues/                   # BullMQ queue definitions
      email.queue.ts
    workers/                  # BullMQ workers (run in separate process)
      email.worker.ts
    errors/                   # custom error classes
      app-error.ts
  store/                      # Zustand stores (client state)
  types/                      # shared TypeScript types
  utils/                      # pure utility functions
  queries/                    # TanStack Query hooks
proxy.ts                      # Next.js 16 edge proxy (replaces middleware.ts)
.env.example                  # document ALL env vars
Dockerfile
docker-compose.yml
docker-compose.prod.yml
```

**Rule:** `app/` and `server/` are two worlds. `app/` imports from `server/`, never the reverse. Server code must stay framework-agnostic where possible.

## Architecture — Layered (Route → Controller → Service → Model)

**Route Handlers are thin.** All business logic belongs in services.

```ts
// ❌ WRONG — logic in route
// app/api/users/route.ts
export async function GET(req: Request) {
  await connectDB();
  const users = await User.find({ active: true });
  return Response.json(users);
}

// ✅ RIGHT — thin route, delegates to controller → service
// app/api/users/route.ts
import { userController } from '@/server/controllers/user.controller';
export const GET = userController.list;

// server/controllers/user.controller.ts
import { userService } from '@/server/services/user.service';
import { handleError } from '@/server/errors/handle';

export const userController = {
  async list(req: Request) {
    try {
      const users = await userService.listActive();
      return Response.json({ data: users });
    } catch (err) {
      return handleError(err);
    }
  },
};

// server/services/user.service.ts
import { UserModel } from '@/server/models/user.model';

export const userService = {
  async listActive() {
    return UserModel.find({ active: true }).lean();
  },
};
```

**Benefits:** services are pure, testable without mocking Request/Response.

## TypeScript Rules

- Strict mode ON. No `any`, no `@ts-ignore`, no `as` unless explicitly unavoidable
- Name things clearly: `getUserProfile()` not `getData()`
- Every function that crosses a boundary (API, DB, external service) has explicit return type
- Use Zod `z.infer<typeof schema>` for DTO types — don't duplicate types
- Prefer type narrowing over casts

## Server Actions vs Route Handlers — WHEN TO USE

**Server Actions** (`'use server'`): forms, simple mutations called from client components, progressive enhancement
- Always validate input with Zod at the top
- Call services directly — no HTTP layer
- Return `{ ok: true, data }` or `{ ok: false, error }` — never throw

**Route Handlers** (`app/api/*/route.ts`): public APIs, mobile app endpoints, webhooks, third-party integrations
- Always use the layered pattern above
- Proper HTTP status codes
- Typed error responses

## Data Fetching Rules

- **Server Components:** fetch data directly from services. No `useEffect`.
- **Client Components:** use TanStack Query via hooks in `src/queries/`
- **Mutations:** Server Actions for forms; Query `useMutation` for complex client flows
- Never fetch in `useEffect` — it's a bug

## State Management Rules

**Zustand = UI state only:**
- Modal open/close, sidebar collapsed, theme, temporary form state
- Never store server data in Zustand

**TanStack Query = all server state:**
- API responses, cache, refetch logic, optimistic updates
- Query keys: `['users', { filters }]` — always arrays with readable structure
- `staleTime` ≥ 30s by default — don't hammer the API

## Mongoose Rules

- One file per model in `server/models/`
- Always define TS interface + schema
- Use `lean()` for reads unless you need document methods
- Add indexes for every field you query
- Soft-delete with `deletedAt` — never hard delete user data
- Hooks (`pre('save')`) for transformations (e.g. password hashing)
- Connection singleton in `lib/db/mongoose.ts` — never connect per-request

```ts
// server/models/user.model.ts
import { Schema, model, models, type Model } from 'mongoose';

export interface IUser {
  _id: string;
  email: string;
  passwordHash: string;
  role: 'user' | 'admin';
  createdAt: Date;
  updatedAt: Date;
  deletedAt: Date | null;
}

const userSchema = new Schema<IUser>(
  {
    email: { type: String, required: true, unique: true, lowercase: true, index: true },
    passwordHash: { type: String, required: true, select: false },
    role: { type: String, enum: ['user', 'admin'], default: 'user' },
    deletedAt: { type: Date, default: null, index: true },
  },
  { timestamps: true }
);

userSchema.index({ email: 1, deletedAt: 1 });

export const UserModel: Model<IUser> =
  models.User || model<IUser>('User', userSchema);
```

## JWT Auth Flow (CUSTOM — no libraries)

- **Access token:** 15 min, stored in httpOnly cookie
- **Refresh token:** 7 days, stored in httpOnly cookie + Redis (for revocation)
- **Passwords:** bcrypt with cost 12
- **Logout:** blacklist access token in Redis until its expiry
- **Refresh flow:** client hits `/api/auth/refresh`, server validates refresh token against Redis, issues new access token
- **CSRF:** double-submit cookie pattern for state-changing requests
- Use `proxy.ts` (Next.js 16) to validate JWT on protected routes

## Redis Patterns

```ts
// lib/redis/client.ts — singleton
// lib/redis/cache.ts
export async function cached<T>(key: string, ttl: number, fn: () => Promise<T>): Promise<T> {
  const hit = await redis.get(key);
  if (hit) return JSON.parse(hit);
  const value = await fn();
  await redis.setex(key, ttl, JSON.stringify(value));
  return value;
}
// Usage: const users = await cached('users:active', 60, () => userService.listActive());
```

- Key naming: `<namespace>:<id>` — e.g. `user:123`, `session:abc`, `ratelimit:ip:1.2.3.4`
- TTLs in seconds, always explicit — never infinite
- Use pipelines for batch ops

## Security Rules (NEVER SKIP)

- **Every API input** validated with Zod at the boundary
- **Every response** has defined status code
- **Rate limit** every public endpoint via Redis
- **Helmet** or manual security headers in `proxy.ts`
- **CORS:** strict allow-list, never `*`
- **Passwords:** bcrypt cost 12, never log them
- **Env secrets:** never commit `.env`, always in `lib/env.ts` with Zod validation
- **SSRF:** validate/whitelist any URL you fetch
- **XSS:** never `dangerouslySetInnerHTML` without sanitization
- **Error responses:** never leak stack traces in production
- Run `codex exec review` on auth code before merging

## Environment Variables

All env vars go through `lib/env.ts` with Zod validation:

```ts
// lib/env.ts
import { z } from 'zod';

const envSchema = z.object({
  NODE_ENV: z.enum(['development', 'production', 'test']),
  DATABASE_URL: z.string().url(),
  REDIS_URL: z.string().url(),
  JWT_ACCESS_SECRET: z.string().min(32),
  JWT_REFRESH_SECRET: z.string().min(32),
  B2_KEY_ID: z.string(),
  B2_APPLICATION_KEY: z.string(),
  B2_BUCKET: z.string(),
  B2_ENDPOINT: z.string().url(),
  RESEND_API_KEY: z.string(),
  // ...
});

export const env = envSchema.parse(process.env);
```

**Never** `process.env.X` directly. Always `import { env } from '@/lib/env'`.

## Internationalization (i18n) — NEVER HARDCODE STRINGS

**Every user-facing string MUST come from a translation file.** This is non-negotiable.

**Library:** `next-intl` (full App Router support, typesafe keys, server + client)

**Setup:**
```
src/
  i18n/
    locales/
      en.json
      ar.json
      fr.json
    config.ts            # supported locales + default
    request.ts           # next-intl request config
  messages.ts            # type-safe keys (generated from en.json)
```

**Rules:**

1. **Server Components:**
   ```tsx
   import { getTranslations } from 'next-intl/server';
   export default async function Page() {
     const t = await getTranslations('dashboard');
     return <h1>{t('title')}</h1>;
   }
   ```

2. **Client Components:**
   ```tsx
   'use client';
   import { useTranslations } from 'next-intl';
   export function MyButton() {
     const t = useTranslations('common');
     return <button>{t('save')}</button>;
   }
   ```

3. **Server Actions / API errors:**
   - Error messages returned from the server should be **translation keys**, not English strings
   - Example: `return { ok: false, error: 'errors.auth.invalidCredentials' }`
   - Client looks up the key via `t(error)`

4. **Zod validation messages:**
   - Set a custom error map that returns translation keys
   - Never hardcode "Required", "Invalid email", etc. in schemas

5. **Toast notifications:**
   ```tsx
   toast.success(t('toasts.saved'));  // ✅
   toast.success('Saved!');            // ❌ NEVER
   ```

6. **Metadata (page titles):**
   ```ts
   export async function generateMetadata() {
     const t = await getTranslations('meta.home');
     return { title: t('title'), description: t('description') };
   }
   ```

7. **Organize keys by feature:**
   ```json
   {
     "common": { "save": "Save", "cancel": "Cancel", "loading": "Loading…" },
     "auth": { "login": "Log in", "signup": "Sign up" },
     "errors": {
       "required": "This field is required",
       "invalidEmail": "Invalid email address",
       "auth": { "invalidCredentials": "Invalid email or password" }
     }
   }
   ```

8. **Default locale:** English. Always add new strings to `en.json` first, then other locales.

9. **When Claude generates any component, form, or UI text:**
   - NEVER write literal strings in JSX
   - NEVER write literal strings in `toast()`, `alert()`, error messages
   - ALWAYS use `t('key.path')`
   - If a key doesn't exist yet, **add it to `en.json` in the same change**

10. **Pluralization:** Use ICU format:
    ```json
    { "itemCount": "{count, plural, =0 {No items} one {# item} other {# items}}" }
    ```
    Usage: `t('itemCount', { count: 5 })`

11. **Date/number formatting:** Use `next-intl`'s `useFormatter()` — never toLocaleString directly:
    ```tsx
    const format = useFormatter();
    format.dateTime(date, 'short');
    format.number(1234.5, { style: 'currency', currency: 'USD' });
    ```

## UI/UX Rules (from global CLAUDE.md — non-negotiable)

- Every interactive element: hover, active, focus, disabled states
- Every async op: loading → success → error states
- Forms: inline Zod errors, disabled submit while processing, toast on success
- Skeleton loaders for content, spinners only for actions
- 150-300ms transitions, ease-out for enters
- A11y: ARIA labels, keyboard nav, focus rings, 4.5:1 contrast
- Empty states always designed — never a blank screen
- Use `next/image`, `next/font`, `next/link` — never raw `<img>`/`<a>`
- `'use client'` only where interactivity is needed — default to Server Components
- Mobile-first Tailwind: base → sm → md → lg → xl

## Performance Rules

- Server Components by default — minimize client bundle
- `next/dynamic` for heavy client components
- `generateMetadata()` for every page — never hardcode `<title>`
- `generateStaticParams()` for known dynamic routes
- Images: always specify width/height, use `priority` for above-fold
- Redis cache layer for hot data
- Connection pooling for Mongoose (default is fine)
- `loading.tsx` + Suspense boundaries everywhere

## Commands

- `npm run dev` — local dev
- `npm run build` — production build
- `npm run start` — start production
- `npm run lint` — ESLint
- `npm run typecheck` — `tsc --noEmit`
- `npm run test` — Vitest
- `npm run test:e2e` — Playwright
- `docker-compose up` — local stack (app + mongo + redis)
- `docker-compose -f docker-compose.prod.yml up -d` — production

## Workflow Rules

- **Before editing any file:** read it first. Never edit from memory.
- **For features touching 3+ files:** plan the approach before coding. Claude should ask for confirmation on non-trivial features.
- **Never speculate about code you haven't read.**
- **Use `rg` and `fd` for searching** — never `grep -r`, `find`.
- **Before any rename:** search for ALL usages (imports, types, test mocks).
- **Run `npm run typecheck && npm run lint` after every change** — fail fast.
- **Never commit** `.env`, credentials, generated files, or dead code.
- **Every new feature:** add a Vitest test for the service layer.
- **Every new endpoint:** document in the route handler's JSDoc.

## Prompt Templates

When building common patterns, use these templates:

- **Full feature scaffold:** `~/.claude/assets/prompts/nextjs-feature-scaffold.md`
- **Mongoose model:** `~/.claude/assets/prompts/nextjs-mongoose-model.md`
- **Service layer:** `~/.claude/assets/prompts/nextjs-service-layer.md`
- **Server Action:** `~/.claude/assets/prompts/nextjs-server-action.md`
- **Route Handler:** `~/.claude/assets/prompts/nextjs-route-handler.md`
- **JWT auth flow:** `~/.claude/assets/prompts/nextjs-auth-jwt.md`
- **Zustand store:** `~/.claude/assets/prompts/nextjs-zustand-store.md`
- **TanStack Query hook:** `~/.claude/assets/prompts/nextjs-tanstack-query.md`
- **shadcn page:** `~/.claude/assets/prompts/nextjs-shadcn-page.md`
- **BullMQ job:** `~/.claude/assets/prompts/nextjs-bullmq-job.md`

## AI Delegation Tips (for this stack)

- **Gemini** → analyze existing code, trace dependencies across server/ layers, code review big PRs
- **Codex** → frontend pages (Tailwind + shadcn), complex form flows, UI polish
- **Qwen** → fix bugs, write tests, Mongoose query optimization, regex/data transforms
- **Claude (me)** → architecture decisions, auth flows, database schema changes, anything touching security

## Hard DON'Ts

- ❌ Never use Prisma in this project
- ❌ Never use NextAuth / Clerk / Auth0 — we do custom JWT
- ❌ Never put business logic in route handlers — use the layered pattern
- ❌ Never fetch data in `useEffect`
- ❌ Never use `process.env.X` directly — always `env.X` from `lib/env.ts`
- ❌ Never use Pages Router — App Router only
- ❌ Never use `middleware.ts` in Next.js 16 — use `proxy.ts`
- ❌ Never store server data in Zustand — that's TanStack Query's job
- ❌ Never use `@vercel/postgres` or `@vercel/kv` — we self-host MongoDB + Redis
- ❌ Never commit `.env` or credentials
- ❌ **Never hardcode user-facing strings** — always use `t('key')` from next-intl
- ❌ Never return hardcoded English error messages from Server Actions / APIs — return translation keys
