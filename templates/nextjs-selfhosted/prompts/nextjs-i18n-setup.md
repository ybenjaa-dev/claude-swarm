# Next.js i18n Setup (next-intl)

## Variables
- `{{LOCALES}}` — supported locales, e.g. `en, ar, fr`
- `{{DEFAULT}}` — default locale

## Prompt

Set up full internationalization for this Next.js 16 App Router project using `next-intl`. Enforce the rule that **no user-facing string is ever hardcoded**.

**Locales:** {{LOCALES}}
**Default:** {{DEFAULT}}

**Produce all files:**

### 1. Install

```bash
npm i next-intl
```

### 2. `src/i18n/config.ts`

```ts
export const locales = ['{{LOCALES split on comma}}'] as const;
export const defaultLocale = '{{DEFAULT}}' as const;
export type Locale = (typeof locales)[number];
```

### 3. `src/i18n/request.ts`

```ts
import { getRequestConfig } from 'next-intl/server';
import { notFound } from 'next/navigation';
import { locales, defaultLocale, type Locale } from './config';

export default getRequestConfig(async ({ requestLocale }) => {
  const requested = await requestLocale;
  const locale = locales.includes(requested as Locale) ? requested! : defaultLocale;
  return {
    locale,
    messages: (await import(`./locales/${locale}.json`)).default,
  };
});
```

### 4. `src/i18n/locales/en.json` — seed with common keys

```json
{
  "common": {
    "save": "Save",
    "cancel": "Cancel",
    "delete": "Delete",
    "edit": "Edit",
    "loading": "Loading…",
    "search": "Search",
    "back": "Back",
    "next": "Next",
    "previous": "Previous",
    "yes": "Yes",
    "no": "No",
    "confirm": "Confirm"
  },
  "nav": {
    "home": "Home",
    "dashboard": "Dashboard",
    "settings": "Settings",
    "profile": "Profile",
    "logout": "Log out"
  },
  "auth": {
    "login": "Log in",
    "signup": "Sign up",
    "logout": "Log out",
    "email": "Email",
    "password": "Password",
    "forgotPassword": "Forgot your password?",
    "noAccount": "Don't have an account?",
    "hasAccount": "Already have an account?"
  },
  "errors": {
    "required": "This field is required",
    "invalidEmail": "Invalid email address",
    "passwordTooShort": "Password must be at least 8 characters",
    "generic": "Something went wrong. Please try again.",
    "networkError": "Network error. Check your connection.",
    "unauthorized": "You must be logged in to access this.",
    "forbidden": "You don't have permission to do this.",
    "notFound": "Not found",
    "auth": {
      "invalidCredentials": "Invalid email or password",
      "emailTaken": "An account with this email already exists",
      "sessionExpired": "Your session has expired. Please log in again."
    }
  },
  "toasts": {
    "saved": "Saved successfully",
    "deleted": "Deleted successfully",
    "copied": "Copied to clipboard",
    "updateFailed": "Update failed"
  },
  "meta": {
    "home": {
      "title": "Home",
      "description": "Welcome"
    }
  }
}
```

Create the same structure for every locale in {{LOCALES}} — translated values.

### 5. `next.config.ts`

```ts
import type { NextConfig } from 'next';
import createNextIntlPlugin from 'next-intl/plugin';

const withNextIntl = createNextIntlPlugin('./src/i18n/request.ts');

const nextConfig: NextConfig = {
  // ...
};

export default withNextIntl(nextConfig);
```

### 6. `src/app/[locale]/layout.tsx` — root layout with locale

```tsx
import { NextIntlClientProvider } from 'next-intl';
import { getMessages } from 'next-intl/server';
import { notFound } from 'next/navigation';
import { locales, type Locale } from '@/i18n/config';

export function generateStaticParams() {
  return locales.map((locale) => ({ locale }));
}

export default async function LocaleLayout({
  children,
  params,
}: {
  children: React.ReactNode;
  params: Promise<{ locale: string }>;
}) {
  const { locale } = await params;
  if (!locales.includes(locale as Locale)) notFound();
  const messages = await getMessages();

  return (
    <html lang={locale} dir={locale === 'ar' ? 'rtl' : 'ltr'}>
      <body>
        <NextIntlClientProvider locale={locale} messages={messages}>
          {children}
        </NextIntlClientProvider>
      </body>
    </html>
  );
}
```

### 7. `proxy.ts` — locale-aware routing

```ts
import createIntlMiddleware from 'next-intl/middleware';
import { locales, defaultLocale } from '@/i18n/config';

export const proxy = createIntlMiddleware({
  locales,
  defaultLocale,
  localePrefix: 'as-needed',
});

export const config = {
  matcher: ['/((?!api|_next|_vercel|.*\\..*).*)'],
};
```

> If you also need auth protection in `proxy.ts`, compose both middlewares — run locale first, then auth check.

### 8. `src/lib/i18n/zod-error-map.ts` — translated Zod errors

```ts
import { z, type ZodErrorMap } from 'zod';
import { getTranslations } from 'next-intl/server';

export async function getZodErrorMap(): Promise<ZodErrorMap> {
  const t = await getTranslations('errors');
  return (issue, ctx) => {
    switch (issue.code) {
      case 'invalid_type':
        if (issue.received === 'undefined') return { message: t('required') };
        return { message: ctx.defaultError };
      case 'invalid_string':
        if (issue.validation === 'email') return { message: t('invalidEmail') };
        return { message: ctx.defaultError };
      case 'too_small':
        if (issue.type === 'string') return { message: t('passwordTooShort') };
        return { message: ctx.defaultError };
      default:
        return { message: ctx.defaultError };
    }
  };
}

// Call once in your server layout:
// z.setErrorMap(await getZodErrorMap());
```

### 9. `src/types/i18n.d.ts` — type-safe keys

```ts
import type en from '@/i18n/locales/en.json';

type Messages = typeof en;

declare global {
  interface IntlMessages extends Messages {}
}
```

### 10. Usage examples (for reference):

**Server Component:**
```tsx
import { getTranslations } from 'next-intl/server';
export default async function Page() {
  const t = await getTranslations('nav');
  return <h1>{t('dashboard')}</h1>;
}
```

**Client Component:**
```tsx
'use client';
import { useTranslations } from 'next-intl';
export function LogoutButton() {
  const t = useTranslations('auth');
  return <button>{t('logout')}</button>;
}
```

**Server Action returning translation keys:**
```ts
'use server';
export async function loginAction(formData: FormData) {
  // ...
  if (!valid) return { ok: false, error: 'errors.auth.invalidCredentials' };
  return { ok: true };
}
```

**Client consuming the key:**
```tsx
const t = useTranslations();
// ...
{state && !state.ok && <p>{t(state.error)}</p>}
```

**Pluralization:**
```tsx
t('itemCount', { count: items.length });
// JSON: "itemCount": "{count, plural, =0 {No items} one {# item} other {# items}}"
```

**Formatting:**
```tsx
const format = useFormatter();
format.dateTime(order.createdAt, 'short');
format.number(order.total, { style: 'currency', currency: 'USD' });
format.relativeTime(lastSeen);
```

**Rules:**
- Every new string goes into `en.json` FIRST, then other locales
- Organize keys by feature namespace (`auth.`, `dashboard.`, `errors.`)
- Never use literal strings in JSX, toasts, alerts, or error messages
- For RTL locales (Arabic, Hebrew), set `dir="rtl"` on `<html>`
- Use type-safe keys via the `IntlMessages` interface

**Output:** All files listed above. Complete implementations. No explanation.
