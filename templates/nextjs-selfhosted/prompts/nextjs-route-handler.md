# Next.js Route Handler Template

## Variables
- `{{FEATURE}}` — feature name
- `{{METHODS}}` — HTTP methods (GET, POST, PATCH, DELETE)
- `{{AUTH}}` — public, user, admin

## Prompt

Create route handlers following the layered pattern. Routes are THIN — they delegate immediately to controllers.

**Feature:** {{FEATURE}}
**Methods:** {{METHODS}}
**Auth:** {{AUTH}}

**File:** `src/app/api/{{FEATURE}}/route.ts` (and `[id]/route.ts` for item-level)

**Route handler file should be ~10 lines:**

```ts
// src/app/api/{{feature}}/route.ts
import { {{feature}}Controller } from '@/server/controllers/{{feature}}.controller';
import { withAuth } from '@/server/middlewares/auth.middleware';

export const GET = {{feature}}Controller.list;
export const POST = withAuth({{feature}}Controller.create, { role: 'user' });
```

**Controller file (`src/server/controllers/{{feature}}.controller.ts`):**

```ts
import { NextRequest } from 'next/server';
import { {{feature}}Service } from '@/server/services/{{feature}}.service';
import { handleError, ok, created, noContent } from '@/server/errors/handle';
import { create{{Feature}}Schema, update{{Feature}}Schema, list{{Feature}}Schema } from '@/lib/schemas/{{feature}}.schema';

export const {{feature}}Controller = {
  async list(req: NextRequest) {
    try {
      const searchParams = Object.fromEntries(req.nextUrl.searchParams);
      const filter = list{{Feature}}Schema.parse(searchParams);
      const data = await {{feature}}Service.list(filter);
      return ok(data);
    } catch (err) {
      return handleError(err);
    }
  },

  async create(req: NextRequest) {
    try {
      const body = await req.json();
      const data = create{{Feature}}Schema.parse(body);
      const item = await {{feature}}Service.create(data);
      return created(item);
    } catch (err) {
      return handleError(err);
    }
  },

  async getById(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
    try {
      const { id } = await params;
      const item = await {{feature}}Service.getById(id);
      return ok(item);
    } catch (err) {
      return handleError(err);
    }
  },

  // ... update, delete
};
```

**Rules:**

1. **Zod validation** happens in the controller. Always parse query/body.
2. **Wrap every handler in try/catch** → `handleError(err)` formats error response.
3. **Response helpers** (`ok`, `created`, `noContent`) return typed `NextResponse`.
4. **`withAuth`** middleware injects the authenticated user onto `req.user`.
5. **Never throw** from a controller — always return a Response.
6. **Never include business logic** — call services.

**Output:** The route file(s) + controller file, nothing else.
