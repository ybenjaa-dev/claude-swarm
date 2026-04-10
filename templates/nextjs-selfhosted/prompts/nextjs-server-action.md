# Next.js Server Action Template

## Variables
- `{{ACTION_NAME}}` — e.g. `createPost`, `updateProfile`
- `{{INPUT_FIELDS}}` — form fields
- `{{AUTH}}` — public, user, admin

## Prompt

Create a Next.js 16 Server Action following this stack's conventions.

**Action:** {{ACTION_NAME}}
**Input fields:** {{INPUT_FIELDS}}
**Auth:** {{AUTH}}

**File location:** `src/app/(group)/.../_actions/{{action-name}}.action.ts`

**Rules:**

1. **First line:** `'use server';`
2. **Zod schema** defined inline or imported from `lib/schemas/`
3. **Auth check** via `getCurrentUser()` helper (reads JWT from cookies)
4. **Calls service** — no Mongoose/Redis directly
5. **Returns a typed result** — `{ ok: true, data }` or `{ ok: false, error: string, fieldErrors?: Record<string, string> }`
6. **Never throws** — all errors become returned results
7. **i18n:** error messages returned to the client must be **translation keys**, not English strings. Example: `error: 'errors.auth.invalidCredentials'`. The client looks up the key via `t(error)`.
7. **Calls `revalidatePath` or `revalidateTag`** after mutation
8. **Use `redirect()` only on success** after revalidation

**Template:**

```ts
'use server';

import { revalidatePath } from 'next/cache';
import { redirect } from 'next/navigation';
import { z } from 'zod';
import { {{feature}}Service } from '@/server/services/{{feature}}.service';
import { getCurrentUser } from '@/server/middlewares/auth.middleware';
import { AppError } from '@/server/errors/app-error';

const schema = z.object({
  // fields with validators
});

type ActionResult<T = void> =
  | { ok: true; data: T }
  | { ok: false; error: string; fieldErrors?: Record<string, string> };

export async function {{actionName}}(formData: FormData): Promise<ActionResult<void>> {
  const user = await getCurrentUser();
  if (!user) return { ok: false, error: 'Unauthorized' };

  const parsed = schema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) {
    return {
      ok: false,
      error: 'Validation failed',
      fieldErrors: parsed.error.flatten().fieldErrors as Record<string, string>,
    };
  }

  try {
    await {{feature}}Service.create({ ...parsed.data, userId: user.id });
  } catch (err) {
    if (err instanceof AppError) return { ok: false, error: err.message };
    console.error('{{actionName}} failed:', err);
    return { ok: false, error: 'Something went wrong' };
  }

  revalidatePath('/{{feature}}');
  redirect('/{{feature}}');
}
```

**Client usage pattern (React 19 / Next.js 16 — for reference, not output):**
```tsx
'use client';
import { useActionState } from 'react'; // ← React 19, NOT useFormState from react-dom
import { {{actionName}} } from './_actions/{{action-name}}.action';

export function {{ActionName}}Form() {
  const [state, formAction, isPending] = useActionState({{actionName}}, null);
  return (
    <form action={formAction}>
      {/* inputs */}
      <button type="submit" disabled={isPending}>
        {isPending ? 'Saving…' : 'Save'}
      </button>
      {state && !state.ok && <p className="text-red-500">{state.error}</p>}
    </form>
  );
}
```

**Note:** `useFormState` from `react-dom` is deprecated in React 19. Always use `useActionState` from `react`. It also exposes `isPending` which `useFormState` didn't.

**Output:** Just the action file. No explanation.
