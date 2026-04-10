# Zustand Store Template

## Variables
- `{{STORE_NAME}}` — e.g. `ui`, `cart`, `filters`
- `{{STATE_SHAPE}}` — fields and types

## Prompt

Create a Zustand store for **UI state only** (not server data — use TanStack Query for that).

**Store:** {{STORE_NAME}}
**State:** {{STATE_SHAPE}}

**File:** `src/store/use-{{store-name}}-store.ts`

**Rules:**

1. **UI state only:** modal open/close, sidebar collapsed, theme, temporary form state, filter selections. **Never** store API data.

2. **Use `create` with TypeScript generics:**
   ```ts
   import { create } from 'zustand';
   import { persist, createJSONStorage } from 'zustand/middleware';

   interface {{StoreName}}State {
     // state fields
     // action fields
   }

   export const use{{StoreName}}Store = create<{{StoreName}}State>()(
     persist(
       (set, get) => ({
         // state
         // actions (functions)
       }),
       {
         name: '{{store-name}}-storage',
         storage: createJSONStorage(() => localStorage),
         partialize: (state) => ({ /* only fields to persist */ }),
       }
     )
   );
   ```

3. **Actions are typed** and modify state with `set`:
   ```ts
   setOpen: (open: boolean) => set({ open }),
   toggle: () => set((state) => ({ open: !state.open })),
   reset: () => set(initialState),
   ```

4. **Selectors** to avoid unnecessary re-renders:
   ```tsx
   // In component: use specific selector, not the whole store
   const open = useUiStore((s) => s.open);      // ✅
   const { open } = useUiStore();               // ❌ rerenders on every change
   ```

5. **`persist` middleware** ONLY for state that should survive reload (theme, sidebar state). Use `partialize` to control what persists.

6. **Never store:**
   - Server data (use TanStack Query)
   - Derived values (compute in selectors or components)
   - Sensitive data (tokens, passwords)

7. **Keep stores small** — one focused store per concern. Don't build a god store.

**Output:** Just the store file. Type-safe. No explanation.
