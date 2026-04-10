# Next.js Service Layer Template

## Variables
- `{{FEATURE}}` — feature name (lowercase)
- `{{MODEL}}` — PascalCase model name
- `{{OPERATIONS}}` — list of service methods needed

## Prompt

Write a service layer file following the layered architecture: Route → Controller → **Service** → Model.

**Feature:** {{FEATURE}}
**Model:** {{MODEL}}
**Operations:** {{OPERATIONS}}

**File location:** `src/server/services/{{FEATURE}}.service.ts`

**Rules:**

1. **Pure business logic.** No `Request`/`Response` types. No HTTP status codes. No `NextResponse`.

2. **Import the model and any other services needed:**
   ```ts
   import { {{MODEL}}Model, type I{{MODEL}} } from '@/server/models/{{feature}}.model';
   import { NotFoundError, ConflictError, ValidationError } from '@/server/errors/app-error';
   import { cached } from '@/lib/redis/cache';
   ```

3. **Export as a const object:**
   ```ts
   export const {{feature}}Service = {
     async list(filter: ListFilter): Promise<I{{MODEL}}[]> { ... },
     async getById(id: string): Promise<I{{MODEL}}> { ... },
     async create(data: CreateDTO): Promise<I{{MODEL}}> { ... },
     async update(id: string, data: UpdateDTO): Promise<I{{MODEL}}> { ... },
     async softDelete(id: string): Promise<void> { ... },
   };
   ```

4. **Patterns:**
   - Always `.lean()` on reads unless you need hooks/methods
   - Filter by `deletedAt: null` on all queries
   - Throw typed errors (`NotFoundError`, `ValidationError`, `ConflictError`) — never generic `Error`
   - For hot reads, wrap in `cached('key', 60, async () => ...)`
   - For pagination: `{ page, limit }` → skip/limit with sensible defaults (max 100)
   - For sorting: whitelist allowed sort fields
   - Explicit return types on every method

5. **Testability:** No side effects except DB/cache. Inject dependencies if needed.

6. **Example create:**
   ```ts
   async create(data: CreateDTO): Promise<I{{MODEL}}> {
     const existing = await {{MODEL}}Model.findOne({ slug: data.slug, deletedAt: null }).lean();
     if (existing) throw new ConflictError(`{{MODEL}} with slug ${data.slug} already exists`);
     const doc = await {{MODEL}}Model.create(data);
     return doc.toObject();
   },
   ```

**Output:** Just the service file. No explanation.
