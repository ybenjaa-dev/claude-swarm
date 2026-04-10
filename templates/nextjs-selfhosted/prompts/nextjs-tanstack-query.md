# TanStack Query Hook Template

## Variables
- `{{FEATURE}}` — feature name (lowercase)
- `{{OPERATIONS}}` — list, get, create, update, delete

## Prompt

Create TanStack Query hooks for this feature following the stack's conventions.

**Feature:** {{FEATURE}}
**Operations:** {{OPERATIONS}}

**File:** `src/queries/use-{{feature}}.ts`

**Rules:**

1. **Query keys** are arrays with structured content:
   ```ts
   export const {{feature}}Keys = {
     all: ['{{feature}}'] as const,
     lists: () => [...{{feature}}Keys.all, 'list'] as const,
     list: (filters: Filters) => [...{{feature}}Keys.lists(), filters] as const,
     details: () => [...{{feature}}Keys.all, 'detail'] as const,
     detail: (id: string) => [...{{feature}}Keys.details(), id] as const,
   };
   ```

2. **Use a typed fetcher** (`src/lib/api/client.ts` — should exist) that handles errors:
   ```ts
   import { apiClient } from '@/lib/api/client';
   ```

3. **Default options:**
   - `staleTime: 30_000` (30s) minimum — never hammer the API
   - `gcTime: 5 * 60_000` (5min)
   - `retry: 2` on reads, `retry: 0` on writes

4. **Mutations** invalidate related queries:
   ```ts
   export function useCreate{{Feature}}() {
     const qc = useQueryClient();
     const t = useTranslations('toasts');
     return useMutation({
       mutationFn: (data: CreateDto) => apiClient.post<{{Feature}}>('/api/{{feature}}', data),
       onSuccess: () => {
         qc.invalidateQueries({ queryKey: {{feature}}Keys.lists() });
         toast.success(t('created'));
       },
       onError: (err) => toast.error(err.message),
     });
   }
   ```

5. **Optimistic updates** for UX-sensitive operations:
   ```ts
   onMutate: async (vars) => {
     await qc.cancelQueries({ queryKey: {{feature}}Keys.all });
     const prev = qc.getQueryData({{feature}}Keys.list(filters));
     qc.setQueryData({{feature}}Keys.list(filters), (old: any) => [...old, { ...vars, _id: 'temp' }]);
     return { prev };
   },
   onError: (_err, _vars, ctx) => {
     if (ctx?.prev) qc.setQueryData({{feature}}Keys.list(filters), ctx.prev);
   },
   onSettled: () => qc.invalidateQueries({ queryKey: {{feature}}Keys.lists() }),
   ```

6. **Type everything** — `useQuery<{{Feature}}[], Error>` etc.

7. **Toast notifications** use `t('toasts.key')` — never hardcoded strings.

**Output:** Just the `use-{{feature}}.ts` file. Complete, type-safe.
