# Next.js Feature Scaffold — Full Stack

## Variables
- `{{FEATURE}}` — feature name, e.g. `product`, `order`, `comment`
- `{{OPERATIONS}}` — CRUD operations needed (default: full CRUD)
- `{{FIELDS}}` — resource fields with types

## Prompt

You are scaffolding a new feature in a Next.js 16 self-hosted stack that uses MongoDB + Mongoose + custom JWT auth + layered architecture (Route → Controller → Service → Model).

**Feature:** {{FEATURE}}
**Operations:** {{OPERATIONS}}
**Fields:** {{FIELDS}}

**Generate all of these files with full, production-ready code:**

1. **`src/server/models/{{FEATURE}}.model.ts`** — Mongoose schema with:
   - TypeScript interface
   - Required/optional fields with proper types
   - Indexes on queryable fields
   - `timestamps: true`
   - `deletedAt` soft-delete field
   - Hooks where needed

2. **`src/server/services/{{FEATURE}}.service.ts`** — pure business logic:
   - `list(filter, pagination)` with `.lean()`
   - `getById(id)` throws NotFoundError if missing
   - `create(data)` with server-side validation
   - `update(id, data)`
   - `softDelete(id)` sets `deletedAt`
   - No Request/Response types — pure functions only

3. **`src/server/controllers/{{FEATURE}}.controller.ts`** — thin HTTP layer:
   - Parse params/body with Zod
   - Call service
   - Return typed JSON with proper status codes
   - Catch errors via `handleError` helper

4. **`src/app/api/{{FEATURE}}/route.ts`** — GET (list) + POST (create)
5. **`src/app/api/{{FEATURE}}/[id]/route.ts`** — GET + PATCH + DELETE

6. **`src/lib/schemas/{{FEATURE}}.schema.ts`** — Zod schemas for create/update/query

7. **`src/queries/use-{{FEATURE}}.ts`** — TanStack Query hooks:
   - `use{{FEATURE}}s(filters)` — list
   - `use{{FEATURE}}(id)` — single
   - `useCreate{{FEATURE}}()` — mutation with optimistic update + toast
   - `useUpdate{{FEATURE}}()`
   - `useDelete{{FEATURE}}()`

8. **`src/server/services/{{FEATURE}}.service.test.ts`** — Vitest tests for service layer (mock the model)

**Rules:**
- TypeScript strict. No `any`. Use `z.infer` for DTO types.
- Every service method returns a Promise with explicit return type.
- Route handlers are ONE line each that delegates to the controller.
- Controllers handle ALL error cases — never let raw errors leak.
- Add `JSDoc` on each public service method explaining what it does.
- Follow the existing folder structure exactly.
- **i18n: NEVER hardcode user-facing strings.** Use `t('key')` from next-intl in all client/server components. Error messages returned from services/actions must be translation keys (e.g. `'errors.{{feature}}.notFound'`), not English strings. Add any new keys to `src/i18n/locales/en.json` in the same change.

**Output:** all files in a single response, clearly labeled with their paths. No explanatory text between files.
