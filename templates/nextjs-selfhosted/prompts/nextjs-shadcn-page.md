# Next.js Page with shadcn/ui Template

## Variables
- `{{PAGE_NAME}}` — e.g. `Dashboard`, `Settings`, `Products`
- `{{ROUTE}}` — e.g. `/dashboard`, `/settings`
- `{{FEATURES}}` — what the page needs (data table, form, stats cards, etc.)
- `{{DATA_SOURCE}}` — Server Component fetch or TanStack Query hook

## Prompt

Create a Next.js 16 App Router page using shadcn/ui components, Tailwind CSS, and this stack's conventions.

**Page:** {{PAGE_NAME}}
**Route:** {{ROUTE}}
**Features:** {{FEATURES}}
**Data:** {{DATA_SOURCE}}

**Files to create:**

1. **`src/app/[locale]/{{route}}/page.tsx`** — Server Component by default
2. **`src/app/[locale]/{{route}}/loading.tsx`** — skeleton loader
3. **`src/app/[locale]/{{route}}/error.tsx`** — error boundary
4. **`src/app/[locale]/{{route}}/layout.tsx`** — only if the page needs special layout
5. **`src/components/{{feature}}/...`** — extracted client components

**Rules:**

1. **Default to Server Components.** Only add `'use client'` when you need hooks, event handlers, or browser APIs.

2. **Translations everywhere:**
   ```tsx
   import { getTranslations } from 'next-intl/server';
   export async function generateMetadata() {
     const t = await getTranslations('meta.{{feature}}');
     return { title: t('title'), description: t('description') };
   }
   export default async function Page() {
     const t = await getTranslations('{{feature}}');
     return <h1>{t('heading')}</h1>;
   }
   ```

3. **shadcn/ui components** — import from `@/components/ui/*`:
   - `Button`, `Card`, `Input`, `Label`, `Textarea`, `Select`, `Dialog`, `Sheet`, `Tabs`, `Table`, `Badge`, `Skeleton`, `Toast`, `DropdownMenu`, `Form`

4. **Tailwind:** mobile-first (`base` → `sm` → `md` → `lg` → `xl`). Use design tokens from `tailwind.config.ts`.

5. **Accessibility:**
   - `aria-label` on icon-only buttons
   - Semantic HTML (`<main>`, `<nav>`, `<section>`, `<article>`)
   - Focus rings on all interactive elements (shadcn handles this)
   - Keyboard navigation

6. **Loading state** (`loading.tsx`):
   ```tsx
   import { Skeleton } from '@/components/ui/skeleton';
   export default function Loading() {
     return (
       <div className="space-y-4 p-6">
         <Skeleton className="h-8 w-48" />
         <Skeleton className="h-64 w-full" />
       </div>
     );
   }
   ```

7. **Error boundary** (`error.tsx`) — Client Component with retry:
   ```tsx
   'use client';
   import { Button } from '@/components/ui/button';
   import { useTranslations } from 'next-intl';
   export default function Error({ error, reset }: { error: Error; reset: () => void }) {
     const t = useTranslations('errors');
     return (
       <div className="flex flex-col items-center justify-center p-12">
         <h2 className="text-xl font-semibold">{t('generic')}</h2>
         <Button onClick={reset} className="mt-4">{t('retry')}</Button>
       </div>
     );
   }
   ```

8. **Data fetching in Server Component:**
   ```tsx
   import { {{feature}}Service } from '@/server/services/{{feature}}.service';
   export default async function Page() {
     const items = await {{feature}}Service.listActive();
     return <ItemList items={items} />;
   }
   ```

9. **Client interactivity in extracted component:**
   ```tsx
   // components/{{feature}}/item-list.tsx
   'use client';
   import { useTranslations } from 'next-intl';
   import { use{{Feature}}s } from '@/queries/use-{{feature}}';
   // ...
   ```

10. **Empty states:** always design them. Show illustration + message + CTA when list is empty.

11. **Responsive:** test mental model on mobile, tablet, desktop. Cards stack on mobile, grid on desktop.

12. **Never:**
    - Use `<img>` — always `next/image` with width/height
    - Use `<a href>` for internal links — use `next/link`
    - Hardcode colors — use Tailwind tokens
    - Hardcode strings — use `t('key')`

**Output:** All files with complete implementations. No explanation text between files.
