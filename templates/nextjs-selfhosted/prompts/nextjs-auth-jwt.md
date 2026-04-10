# Next.js Custom JWT Auth Flow

## Variables
- None (complete auth setup)

## Prompt

Build a complete custom JWT authentication flow for this Next.js 16 self-hosted stack. No NextAuth, no Clerk, no Auth0.

**Produce ALL of these files:**

### 1. `src/lib/auth/jwt.ts` — token signing/verification

```ts
import jwt from 'jsonwebtoken';
import { env } from '@/lib/env';

export interface AccessTokenPayload {
  sub: string;       // user id
  role: 'user' | 'admin';
  type: 'access';
}

export interface RefreshTokenPayload {
  sub: string;
  jti: string;       // unique token id for revocation
  type: 'refresh';
}

const ACCESS_TTL = '15m';
const REFRESH_TTL = '7d';

export function signAccessToken(payload: Omit<AccessTokenPayload, 'type'>): string { /* ... */ }
export function signRefreshToken(payload: Omit<RefreshTokenPayload, 'type'>): string { /* ... */ }
export function verifyAccessToken(token: string): AccessTokenPayload { /* ... */ }
export function verifyRefreshToken(token: string): RefreshTokenPayload { /* ... */ }
```

### 2. `src/lib/auth/cookies.ts` — httpOnly cookie helpers

```ts
import { cookies } from 'next/headers';
import { env } from '@/lib/env';

const ACCESS_COOKIE = 'access_token';
const REFRESH_COOKIE = 'refresh_token';
const isProd = env.NODE_ENV === 'production';

export async function setAuthCookies(accessToken: string, refreshToken: string) {
  const store = await cookies();
  store.set(ACCESS_COOKIE, accessToken, {
    httpOnly: true, secure: isProd, sameSite: 'lax', path: '/',
    maxAge: 60 * 15,
  });
  store.set(REFRESH_COOKIE, refreshToken, {
    httpOnly: true, secure: isProd, sameSite: 'lax', path: '/api/auth',
    maxAge: 60 * 60 * 24 * 7,
  });
}

export async function clearAuthCookies() { /* delete both */ }
export async function getAccessTokenFromCookies(): Promise<string | null> { /* ... */ }
export async function getRefreshTokenFromCookies(): Promise<string | null> { /* ... */ }
```

### 3. `src/lib/auth/password.ts` — bcrypt wrappers

```ts
import bcrypt from 'bcrypt';
const COST = 12;
export const hashPassword = (pw: string) => bcrypt.hash(pw, COST);
export const verifyPassword = (pw: string, hash: string) => bcrypt.compare(pw, hash);
```

### 4. `src/lib/redis/token-blacklist.ts`

```ts
import { redis } from '@/lib/redis/client';

export async function blacklistToken(jti: string, expiresInSec: number) {
  await redis.setex(`blacklist:${jti}`, expiresInSec, '1');
}
export async function isBlacklisted(jti: string): Promise<boolean> {
  return (await redis.exists(`blacklist:${jti}`)) === 1;
}
export async function storeRefreshToken(jti: string, userId: string, expiresInSec: number) {
  await redis.setex(`refresh:${jti}`, expiresInSec, userId);
}
export async function validateRefreshToken(jti: string, userId: string): Promise<boolean> {
  const stored = await redis.get(`refresh:${jti}`);
  return stored === userId;
}
export async function revokeRefreshToken(jti: string) {
  await redis.del(`refresh:${jti}`);
}
```

### 5. `src/server/services/auth.service.ts`

Operations:
- `register({ email, password })` — checks uniqueness, hashes, creates user, returns tokens
- `login({ email, password })` — verifies, issues tokens, stores refresh in Redis
- `refresh(refreshToken)` — verifies, checks Redis, rotates refresh token, issues new access
- `logout(accessToken, refreshToken)` — blacklists access, revokes refresh
- `getCurrentUser(accessToken)` — verifies, checks blacklist, returns user

All throw typed errors (`UnauthorizedError`, `ConflictError`).

### 6. `src/server/controllers/auth.controller.ts`

Endpoints:
- `POST /api/auth/register`
- `POST /api/auth/login`
- `POST /api/auth/refresh`
- `POST /api/auth/logout`
- `GET /api/auth/me`

Sets/clears cookies via `cookies.ts` helpers.

### 7. `src/app/api/auth/[action]/route.ts` — route files

### 8. `src/server/middlewares/auth.middleware.ts` — `withAuth` HOC + `getCurrentUser()` helper

```ts
import { NextRequest, NextResponse } from 'next/server';
import { verifyAccessToken } from '@/lib/auth/jwt';
import { getAccessTokenFromCookies } from '@/lib/auth/cookies';
import { isBlacklisted } from '@/lib/redis/token-blacklist';
import { UserModel, type IUser } from '@/server/models/user.model';

export async function getCurrentUser(): Promise<IUser | null> { /* ... */ }

export function withAuth<T extends NextRequest>(
  handler: (req: T & { user: IUser }) => Promise<Response>,
  opts: { role?: 'user' | 'admin' } = {}
) {
  return async (req: T) => {
    const token = await getAccessTokenFromCookies();
    if (!token) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
    try {
      const payload = verifyAccessToken(token);
      if (await isBlacklisted(payload.sub)) {
        return NextResponse.json({ error: 'Token revoked' }, { status: 401 });
      }
      const user = await UserModel.findById(payload.sub).lean();
      if (!user) return NextResponse.json({ error: 'User not found' }, { status: 401 });
      if (opts.role === 'admin' && user.role !== 'admin') {
        return NextResponse.json({ error: 'Forbidden' }, { status: 403 });
      }
      (req as any).user = user;
      return handler(req as T & { user: IUser });
    } catch {
      return NextResponse.json({ error: 'Invalid token' }, { status: 401 });
    }
  };
}
```

### 9. `proxy.ts` (Next.js 16 — replaces middleware.ts)

Protects routes by redirecting unauthenticated users to `/login`:

```ts
import { NextRequest, NextResponse } from 'next/server';
import { verifyAccessToken } from '@/lib/auth/jwt';

const PROTECTED = ['/dashboard', '/settings', '/admin'];
const ADMIN_ONLY = ['/admin'];

export function proxy(req: NextRequest) {
  const { pathname } = req.nextUrl;
  const isProtected = PROTECTED.some((p) => pathname.startsWith(p));
  if (!isProtected) return NextResponse.next();

  const token = req.cookies.get('access_token')?.value;
  if (!token) return NextResponse.redirect(new URL('/login', req.url));

  try {
    const payload = verifyAccessToken(token);
    if (ADMIN_ONLY.some((p) => pathname.startsWith(p)) && payload.role !== 'admin') {
      return NextResponse.redirect(new URL('/', req.url));
    }
    return NextResponse.next();
  } catch {
    return NextResponse.redirect(new URL('/login', req.url));
  }
}

export const config = {
  matcher: ['/dashboard/:path*', '/settings/:path*', '/admin/:path*'],
};
```

### 10. `src/lib/schemas/auth.schema.ts` — Zod schemas for register/login

### 11. Env vars needed (document in `.env.example`):
```
JWT_ACCESS_SECRET=   # min 32 chars
JWT_REFRESH_SECRET=  # min 32 chars, DIFFERENT from access
```

**Rules:**
- Never expose password hashes in API responses
- Use `select: false` on passwordHash in User model
- Access tokens: 15 min; Refresh tokens: 7 days
- Rotate refresh tokens on every use (delete old, issue new)
- Rate limit `/api/auth/login` via Redis (5 attempts per 15 min per IP)
- Log auth events (login, logout, refresh) but NEVER log tokens or passwords

**Output:** All files with complete implementations. No explanatory text.
