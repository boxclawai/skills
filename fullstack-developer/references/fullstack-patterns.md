# Full-Stack Development Patterns Reference

## Table of Contents

1. [Rendering Strategy Decision Matrix](#rendering-strategy-decision-matrix)
2. [API Layer Patterns](#api-layer-patterns)
3. [Authentication Flows](#authentication-flows)
4. [Form Handling Patterns](#form-handling-patterns)
5. [Real-Time Patterns](#real-time-patterns)
6. [File Upload Patterns](#file-upload-patterns)
7. [Optimistic Update Patterns](#optimistic-update-patterns)

---

## Rendering Strategy Decision Matrix

### SSR vs CSR vs SSG vs ISR

```
Criteria           | SSR              | CSR              | SSG              | ISR
-------------------|------------------|------------------|------------------|------------------
SEO Required?      | Yes              | No (or prerender)| Yes              | Yes
Data Freshness     | Every request    | Client fetch     | Build time only  | Timed revalidate
TTFB               | Slower (compute) | Fast (static)    | Fastest (CDN)    | Fast (cached)
Interactivity      | Hydration needed | Immediate        | Hydration needed | Hydration needed
Server Cost        | Higher           | Lowest           | Low (build only) | Low
Personalized?      | Yes              | Yes              | No               | Partial
Scales to Pages    | Unlimited        | Unlimited        | Build time grows | Unlimited
Offline Capable    | With SW          | Yes (SW + cache) | Yes (SW + cache) | Yes (SW + cache)

Decision Flow:
  1. Is the page public + SEO critical + rarely changes?   → SSG
  2. Is it public + SEO critical + changes often?          → ISR (revalidate 60-300s)
  3. Is it personalized + SEO needed (e.g., profile)?      → SSR
  4. Is it behind auth + no SEO needed (dashboard)?        → CSR (SPA)
  5. Mix of both?                                          → SSR shell + CSR islands
```

### Framework Implementation

```typescript
// Next.js App Router -------------------------------------------------------

// SSG - Static at build time
// app/blog/[slug]/page.tsx
export async function generateStaticParams() {
  const posts = await db.post.findMany({ select: { slug: true } });
  return posts.map((post) => ({ slug: post.slug }));
}

export default async function BlogPost({ params }: { params: { slug: string } }) {
  const post = await db.post.findUnique({ where: { slug: params.slug } });
  if (!post) notFound();
  return <Article post={post} />;
}

// ISR - Revalidate every 60 seconds
export const revalidate = 60;

export default async function ProductPage({ params }: { params: { id: string } }) {
  const product = await db.product.findUnique({ where: { id: params.id } });
  return <ProductDetail product={product} />;
}

// SSR - Fresh data every request (opt out of caching)
export const dynamic = 'force-dynamic';

export default async function DashboardPage() {
  const user = await getCurrentUser();
  const stats = await db.stats.findUnique({ where: { userId: user.id } });
  return <Dashboard stats={stats} />;
}

// CSR - Client component with data fetching
'use client';
export default function LiveFeed() {
  const { data, isLoading } = useSWR('/api/feed', fetcher, {
    refreshInterval: 5000,
  });
  if (isLoading) return <Skeleton />;
  return <FeedList items={data} />;
}
```

```typescript
// Nuxt 3 -------------------------------------------------------------------

// SSG - Pre-render at build time (nuxt.config.ts: routeRules)
// nuxt.config.ts
export default defineNuxtConfig({
  routeRules: {
    '/blog/**': { prerender: true },
    '/products/**': { swr: 3600 },        // ISR: stale-while-revalidate 1hr
    '/dashboard/**': { ssr: true },        // SSR: always server-render
    '/app/**': { ssr: false },             // CSR: client-only SPA
  },
});

// Page with server-side data fetching
// pages/products/[id].vue
<script setup lang="ts">
const route = useRoute();
const { data: product } = await useFetch(`/api/products/${route.params.id}`);
if (!product.value) throw createError({ statusCode: 404, message: 'Not found' });
</script>
```

```typescript
// SvelteKit ----------------------------------------------------------------

// SSG
// +page.ts
export const prerender = true;

export async function load({ params }) {
  const post = await getPost(params.slug);
  return { post };
}

// SSR (default)
// +page.server.ts
export async function load({ locals }) {
  const user = locals.user;
  const dashboard = await getDashboard(user.id);
  return { dashboard };
}

// CSR-only
// +page.ts
export const ssr = false;
```

---

## API Layer Patterns

### tRPC (End-to-End Type Safety)

```typescript
// server/trpc/router.ts
import { initTRPC, TRPCError } from '@trpc/server';
import { z } from 'zod';

const t = initTRPC.context<Context>().create({
  errorFormatter({ shape, error }) {
    return {
      ...shape,
      data: {
        ...shape.data,
        zodError: error.cause instanceof z.ZodError ? error.cause.flatten() : null,
      },
    };
  },
});

// Middleware
const isAuthed = t.middleware(({ ctx, next }) => {
  if (!ctx.user) throw new TRPCError({ code: 'UNAUTHORIZED' });
  return next({ ctx: { user: ctx.user } });
});

const protectedProcedure = t.procedure.use(isAuthed);

// Router
export const appRouter = t.router({
  user: t.router({
    me: protectedProcedure.query(async ({ ctx }) => {
      return db.user.findUnique({ where: { id: ctx.user.id } });
    }),

    update: protectedProcedure
      .input(z.object({
        name: z.string().min(1).max(100).optional(),
        email: z.string().email().optional(),
        avatar: z.string().url().optional(),
      }))
      .mutation(async ({ ctx, input }) => {
        return db.user.update({
          where: { id: ctx.user.id },
          data: input,
        });
      }),
  }),

  post: t.router({
    list: t.procedure
      .input(z.object({
        cursor: z.string().nullish(),
        limit: z.number().min(1).max(100).default(20),
        status: z.enum(['draft', 'published']).optional(),
      }))
      .query(async ({ input }) => {
        const items = await db.post.findMany({
          take: input.limit + 1,
          ...(input.cursor && { cursor: { id: input.cursor }, skip: 1 }),
          where: input.status ? { status: input.status } : undefined,
          orderBy: { createdAt: 'desc' },
        });

        const hasMore = items.length > input.limit;
        return {
          items: hasMore ? items.slice(0, -1) : items,
          nextCursor: hasMore ? items[input.limit - 1].id : null,
        };
      }),

    create: protectedProcedure
      .input(z.object({
        title: z.string().min(1).max(200),
        content: z.string().min(1),
        tags: z.array(z.string()).max(10).default([]),
      }))
      .mutation(async ({ ctx, input }) => {
        return db.post.create({
          data: { ...input, authorId: ctx.user.id },
        });
      }),
  }),
});

export type AppRouter = typeof appRouter;
```

```typescript
// Client usage (fully typed, no codegen)
// utils/trpc.ts
import { createTRPCReact } from '@trpc/react-query';
import type { AppRouter } from '~/server/trpc/router';

export const trpc = createTRPCReact<AppRouter>();

// In component
function PostList() {
  const { data, fetchNextPage, hasNextPage } = trpc.post.list.useInfiniteQuery(
    { limit: 20 },
    { getNextPageParam: (lastPage) => lastPage.nextCursor },
  );

  const createPost = trpc.post.create.useMutation({
    onSuccess: () => utils.post.list.invalidate(),
  });

  // Full autocomplete + type safety on data.pages[n].items[n].title
}
```

### REST Client Abstraction

```typescript
// lib/api-client.ts - Production REST client with retry, auth, and error handling
interface ApiClientConfig {
  baseURL: string;
  getToken?: () => string | null;
  onUnauthorized?: () => void;
  timeout?: number;
  retries?: number;
}

class ApiError extends Error {
  constructor(
    public status: number,
    public statusText: string,
    public data: unknown,
    public requestId?: string,
  ) {
    super(`API Error ${status}: ${statusText}`);
    this.name = 'ApiError';
  }

  get isNotFound() { return this.status === 404; }
  get isValidation() { return this.status === 422; }
  get isUnauthorized() { return this.status === 401; }
  get isRateLimit() { return this.status === 429; }
  get isServerError() { return this.status >= 500; }
}

class ApiClient {
  constructor(private config: ApiClientConfig) {}

  private async request<T>(path: string, init: RequestInit = {}): Promise<T> {
    const url = `${this.config.baseURL}${path}`;
    const token = this.config.getToken?.();

    const headers: HeadersInit = {
      'Content-Type': 'application/json',
      ...(token && { Authorization: `Bearer ${token}` }),
      ...init.headers,
    };

    let lastError: Error | null = null;
    const maxAttempts = (this.config.retries ?? 2) + 1;

    for (let attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        const controller = new AbortController();
        const timeout = setTimeout(
          () => controller.abort(),
          this.config.timeout ?? 10000,
        );

        const response = await fetch(url, {
          ...init,
          headers,
          signal: controller.signal,
        });

        clearTimeout(timeout);

        if (response.status === 401) {
          this.config.onUnauthorized?.();
        }

        if (!response.ok) {
          const data = await response.json().catch(() => null);
          throw new ApiError(
            response.status,
            response.statusText,
            data,
            response.headers.get('x-request-id') ?? undefined,
          );
        }

        if (response.status === 204) return undefined as T;
        return response.json();
      } catch (error) {
        lastError = error as Error;

        // Only retry on network errors or 5xx, not on 4xx
        const isRetryable = !(error instanceof ApiError) || error.isServerError;
        if (!isRetryable || attempt === maxAttempts) throw error;

        // Exponential backoff: 200ms, 400ms, 800ms...
        await new Promise(r => setTimeout(r, 200 * Math.pow(2, attempt - 1)));
      }
    }

    throw lastError;
  }

  get<T>(path: string)                       { return this.request<T>(path); }
  post<T>(path: string, body: unknown)       { return this.request<T>(path, { method: 'POST', body: JSON.stringify(body) }); }
  put<T>(path: string, body: unknown)        { return this.request<T>(path, { method: 'PUT', body: JSON.stringify(body) }); }
  patch<T>(path: string, body: unknown)      { return this.request<T>(path, { method: 'PATCH', body: JSON.stringify(body) }); }
  delete<T>(path: string)                    { return this.request<T>(path, { method: 'DELETE' }); }
}

// Usage
const api = new ApiClient({
  baseURL: process.env.NEXT_PUBLIC_API_URL!,
  getToken: () => localStorage.getItem('token'),
  onUnauthorized: () => { window.location.href = '/login'; },
  timeout: 15000,
  retries: 2,
});

// Typed endpoints
export const usersApi = {
  me: ()                           => api.get<User>('/api/users/me'),
  update: (data: UpdateUserInput)  => api.patch<User>('/api/users/me', data),
};

export const postsApi = {
  list: (params?: PostQuery)       => api.get<PaginatedResult<Post>>(`/api/posts?${qs(params)}`),
  get: (id: string)                => api.get<Post>(`/api/posts/${id}`),
  create: (data: CreatePostInput)  => api.post<Post>('/api/posts', data),
  update: (id: string, data: Partial<CreatePostInput>) => api.patch<Post>(`/api/posts/${id}`, data),
  delete: (id: string)             => api.delete<void>(`/api/posts/${id}`),
};
```

### API Error Handling (Express/Fastify)

```typescript
// middleware/error-handler.ts
import { Request, Response, NextFunction } from 'express';
import { ZodError } from 'zod';
import { Prisma } from '@prisma/client';

// Custom error classes
export class AppError extends Error {
  constructor(
    public statusCode: number,
    message: string,
    public code?: string,
    public details?: unknown,
  ) {
    super(message);
    this.name = 'AppError';
  }
}

export class NotFoundError extends AppError {
  constructor(resource: string) {
    super(404, `${resource} not found`, 'NOT_FOUND');
  }
}

export class ConflictError extends AppError {
  constructor(message: string) {
    super(409, message, 'CONFLICT');
  }
}

export class ForbiddenError extends AppError {
  constructor(message = 'Insufficient permissions') {
    super(403, message, 'FORBIDDEN');
  }
}

// Global error handler
export function errorHandler(err: Error, req: Request, res: Response, _next: NextFunction) {
  // Structured logging
  const requestId = req.headers['x-request-id'] as string;
  const logContext = {
    requestId,
    method: req.method,
    path: req.path,
    userId: (req as any).user?.id,
  };

  // Known application errors
  if (err instanceof AppError) {
    logger.warn('Application error', { ...logContext, error: err.message, code: err.code });
    return res.status(err.statusCode).json({
      error: {
        message: err.message,
        code: err.code,
        ...(err.details && { details: err.details }),
      },
    });
  }

  // Zod validation errors
  if (err instanceof ZodError) {
    logger.warn('Validation error', { ...logContext, issues: err.issues });
    return res.status(422).json({
      error: {
        message: 'Validation failed',
        code: 'VALIDATION_ERROR',
        details: err.issues.map(i => ({
          path: i.path.join('.'),
          message: i.message,
        })),
      },
    });
  }

  // Prisma errors
  if (err instanceof Prisma.PrismaClientKnownRequestError) {
    if (err.code === 'P2002') {
      const fields = (err.meta?.target as string[])?.join(', ');
      return res.status(409).json({
        error: {
          message: `Duplicate value for: ${fields}`,
          code: 'DUPLICATE',
        },
      });
    }
    if (err.code === 'P2025') {
      return res.status(404).json({
        error: { message: 'Record not found', code: 'NOT_FOUND' },
      });
    }
  }

  // Unexpected errors - do NOT leak internal details
  logger.error('Unhandled error', { ...logContext, error: err.message, stack: err.stack });
  reportToSentry(err, logContext);

  res.status(500).json({
    error: {
      message: 'Internal server error',
      code: 'INTERNAL_ERROR',
      ...(process.env.NODE_ENV !== 'production' && { debug: err.message }),
    },
  });
}
```

---

## Authentication Flows

### Session-Based Authentication (Cookie)

```typescript
// Server: Express + express-session + connect-redis
import session from 'express-session';
import RedisStore from 'connect-redis';
import { createClient } from 'redis';

const redisClient = createClient({ url: process.env.REDIS_URL });
await redisClient.connect();

app.use(session({
  store: new RedisStore({ client: redisClient, prefix: 'sess:' }),
  secret: process.env.SESSION_SECRET!,
  name: '__session',
  resave: false,
  saveUninitialized: false,
  cookie: {
    httpOnly: true,                          // Not accessible via JS
    secure: process.env.NODE_ENV === 'production',
    sameSite: 'lax',                         // CSRF protection
    maxAge: 7 * 24 * 60 * 60 * 1000,        // 7 days
    domain: process.env.COOKIE_DOMAIN,
  },
}));

// Login endpoint
app.post('/auth/login', async (req, res) => {
  const { email, password } = loginSchema.parse(req.body);

  const user = await db.user.findUnique({ where: { email } });
  if (!user || !(await argon2.verify(user.passwordHash, password))) {
    return res.status(401).json({ error: { message: 'Invalid credentials' } });
  }

  // Regenerate session to prevent fixation
  req.session.regenerate((err) => {
    if (err) throw err;
    req.session.userId = user.id;
    req.session.role = user.role;
    res.json({ data: { id: user.id, email: user.email, name: user.name } });
  });
});

// Middleware
function requireAuth(req: Request, res: Response, next: NextFunction) {
  if (!req.session.userId) {
    return res.status(401).json({ error: { message: 'Authentication required' } });
  }
  next();
}

// Logout
app.post('/auth/logout', (req, res) => {
  req.session.destroy((err) => {
    if (err) throw err;
    res.clearCookie('__session');
    res.json({ message: 'Logged out' });
  });
});
```

### JWT Authentication (Access + Refresh Tokens)

```typescript
// lib/jwt.ts
import jwt from 'jsonwebtoken';

interface TokenPayload {
  sub: string;    // userId
  role: string;
  type: 'access' | 'refresh';
}

const ACCESS_SECRET  = process.env.JWT_ACCESS_SECRET!;
const REFRESH_SECRET = process.env.JWT_REFRESH_SECRET!;

export function generateTokenPair(userId: string, role: string) {
  const accessToken = jwt.sign(
    { sub: userId, role, type: 'access' } satisfies TokenPayload,
    ACCESS_SECRET,
    { expiresIn: '15m', issuer: 'myapp' },
  );

  const refreshToken = jwt.sign(
    { sub: userId, role, type: 'refresh' } satisfies TokenPayload,
    REFRESH_SECRET,
    { expiresIn: '7d', issuer: 'myapp' },
  );

  return { accessToken, refreshToken };
}

export function verifyAccessToken(token: string): TokenPayload {
  return jwt.verify(token, ACCESS_SECRET, { issuer: 'myapp' }) as TokenPayload;
}

export function verifyRefreshToken(token: string): TokenPayload {
  return jwt.verify(token, REFRESH_SECRET, { issuer: 'myapp' }) as TokenPayload;
}

// Middleware
export function authMiddleware(req: Request, res: Response, next: NextFunction) {
  const header = req.headers.authorization;
  if (!header?.startsWith('Bearer ')) {
    return res.status(401).json({ error: { message: 'Missing token' } });
  }

  try {
    const payload = verifyAccessToken(header.slice(7));
    req.user = { id: payload.sub, role: payload.role };
    next();
  } catch (err) {
    if (err instanceof jwt.TokenExpiredError) {
      return res.status(401).json({ error: { message: 'Token expired', code: 'TOKEN_EXPIRED' } });
    }
    return res.status(401).json({ error: { message: 'Invalid token' } });
  }
}

// Token refresh endpoint
app.post('/auth/refresh', async (req, res) => {
  const { refreshToken } = req.body;
  if (!refreshToken) return res.status(400).json({ error: { message: 'Refresh token required' } });

  try {
    const payload = verifyRefreshToken(refreshToken);

    // Check if token is revoked (stored in DB or Redis)
    const isRevoked = await redisClient.get(`revoked:${refreshToken}`);
    if (isRevoked) return res.status(401).json({ error: { message: 'Token revoked' } });

    // Revoke old refresh token (rotation)
    await redisClient.set(`revoked:${refreshToken}`, '1', { EX: 7 * 24 * 3600 });

    // Issue new pair
    const tokens = generateTokenPair(payload.sub, payload.role);
    res.json({ data: tokens });
  } catch {
    return res.status(401).json({ error: { message: 'Invalid refresh token' } });
  }
});
```

### OAuth 2.0 / OpenID Connect (Google Example)

```typescript
// Using Passport.js + Google Strategy
// auth/google.ts
import passport from 'passport';
import { Strategy as GoogleStrategy } from 'passport-google-oauth20';

passport.use(new GoogleStrategy({
  clientID: process.env.GOOGLE_CLIENT_ID!,
  clientSecret: process.env.GOOGLE_CLIENT_SECRET!,
  callbackURL: `${process.env.APP_URL}/auth/google/callback`,
  scope: ['profile', 'email'],
}, async (accessToken, refreshToken, profile, done) => {
  try {
    // Find or create user
    let user = await db.user.findUnique({
      where: { oauthProviderId: profile.id },
    });

    if (!user) {
      user = await db.user.create({
        data: {
          email: profile.emails![0].value,
          name: profile.displayName,
          avatar: profile.photos?.[0]?.value,
          oauthProvider: 'google',
          oauthProviderId: profile.id,
          emailVerified: true,
        },
      });
    }

    done(null, user);
  } catch (err) {
    done(err as Error);
  }
}));

// Routes
app.get('/auth/google', passport.authenticate('google'));

app.get('/auth/google/callback',
  passport.authenticate('google', { failureRedirect: '/login?error=oauth_failed' }),
  (req, res) => {
    // Generate JWT pair for SPA, or set session cookie
    const tokens = generateTokenPair(req.user!.id, req.user!.role);
    // Redirect with token (use short-lived code exchange in production)
    res.redirect(`${process.env.FRONTEND_URL}/auth/callback?token=${tokens.accessToken}`);
  },
);
```

### NextAuth.js / Auth.js (Full-Stack Framework)

```typescript
// app/api/auth/[...nextauth]/route.ts (Next.js App Router)
import NextAuth from 'next-auth';
import GoogleProvider from 'next-auth/providers/google';
import CredentialsProvider from 'next-auth/providers/credentials';
import { PrismaAdapter } from '@auth/prisma-adapter';

const handler = NextAuth({
  adapter: PrismaAdapter(prisma),
  providers: [
    GoogleProvider({
      clientId: process.env.GOOGLE_CLIENT_ID!,
      clientSecret: process.env.GOOGLE_CLIENT_SECRET!,
    }),
    CredentialsProvider({
      name: 'Email',
      credentials: {
        email: { label: 'Email', type: 'email' },
        password: { label: 'Password', type: 'password' },
      },
      async authorize(credentials) {
        if (!credentials?.email || !credentials?.password) return null;
        const user = await db.user.findUnique({ where: { email: credentials.email } });
        if (!user?.passwordHash) return null;
        const valid = await argon2.verify(user.passwordHash, credentials.password);
        return valid ? user : null;
      },
    }),
  ],
  session: { strategy: 'jwt' },
  callbacks: {
    async jwt({ token, user }) {
      if (user) { token.role = user.role; }
      return token;
    },
    async session({ session, token }) {
      session.user.id = token.sub!;
      session.user.role = token.role as string;
      return session;
    },
  },
  pages: {
    signIn: '/login',
    error: '/login',
  },
});

export { handler as GET, handler as POST };

// Client usage
'use client';
import { useSession, signIn, signOut } from 'next-auth/react';

function AuthButton() {
  const { data: session, status } = useSession();
  if (status === 'loading') return <Skeleton />;
  if (session) return <button onClick={() => signOut()}>Sign out</button>;
  return <button onClick={() => signIn('google')}>Sign in</button>;
}
```

---

## Form Handling Patterns

### React Hook Form + Zod

```typescript
// Shared schema (used by both frontend and backend)
// schemas/user.ts
import { z } from 'zod';

export const registerSchema = z.object({
  name: z.string().min(2, 'Name must be at least 2 characters').max(100),
  email: z.string().email('Invalid email address'),
  password: z
    .string()
    .min(8, 'Password must be at least 8 characters')
    .regex(/[A-Z]/, 'Must contain an uppercase letter')
    .regex(/[0-9]/, 'Must contain a number'),
  confirmPassword: z.string(),
}).refine(data => data.password === data.confirmPassword, {
  message: 'Passwords do not match',
  path: ['confirmPassword'],
});

export type RegisterInput = z.infer<typeof registerSchema>;
```

```tsx
// RegisterForm.tsx
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { registerSchema, type RegisterInput } from '~/schemas/user';

export function RegisterForm() {
  const {
    register,
    handleSubmit,
    formState: { errors, isSubmitting },
    setError,
    reset,
  } = useForm<RegisterInput>({
    resolver: zodResolver(registerSchema),
    defaultValues: { name: '', email: '', password: '', confirmPassword: '' },
  });

  const onSubmit = async (data: RegisterInput) => {
    try {
      const response = await fetch('/api/auth/register', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data),
      });

      if (!response.ok) {
        const error = await response.json();
        // Map server errors to form fields
        if (error.code === 'DUPLICATE_EMAIL') {
          setError('email', { message: 'Email already registered' });
          return;
        }
        setError('root', { message: error.message || 'Registration failed' });
        return;
      }

      reset();
      // Redirect or update auth state
    } catch {
      setError('root', { message: 'Network error. Please try again.' });
    }
  };

  return (
    <form onSubmit={handleSubmit(onSubmit)} noValidate>
      {errors.root && (
        <div role="alert" className="error-banner">{errors.root.message}</div>
      )}

      <div>
        <label htmlFor="name">Name</label>
        <input id="name" {...register('name')} aria-invalid={!!errors.name} />
        {errors.name && <span role="alert">{errors.name.message}</span>}
      </div>

      <div>
        <label htmlFor="email">Email</label>
        <input id="email" type="email" {...register('email')} aria-invalid={!!errors.email} />
        {errors.email && <span role="alert">{errors.email.message}</span>}
      </div>

      <div>
        <label htmlFor="password">Password</label>
        <input id="password" type="password" {...register('password')} aria-invalid={!!errors.password} />
        {errors.password && <span role="alert">{errors.password.message}</span>}
      </div>

      <div>
        <label htmlFor="confirmPassword">Confirm Password</label>
        <input
          id="confirmPassword"
          type="password"
          {...register('confirmPassword')}
          aria-invalid={!!errors.confirmPassword}
        />
        {errors.confirmPassword && <span role="alert">{errors.confirmPassword.message}</span>}
      </div>

      <button type="submit" disabled={isSubmitting}>
        {isSubmitting ? 'Registering...' : 'Register'}
      </button>
    </form>
  );
}
```

### VeeValidate + Zod (Vue 3)

```vue
<!-- RegisterForm.vue -->
<script setup lang="ts">
import { useForm } from 'vee-validate';
import { toTypedSchema } from '@vee-validate/zod';
import { registerSchema, type RegisterInput } from '~/schemas/user';

const { handleSubmit, errors, isSubmitting, setFieldError, setErrors } = useForm<RegisterInput>({
  validationSchema: toTypedSchema(registerSchema),
  initialValues: { name: '', email: '', password: '', confirmPassword: '' },
});

const onSubmit = handleSubmit(async (values) => {
  try {
    const response = await $fetch('/api/auth/register', {
      method: 'POST',
      body: values,
    });
    navigateTo('/dashboard');
  } catch (error: any) {
    if (error.data?.code === 'DUPLICATE_EMAIL') {
      setFieldError('email', 'Email already registered');
      return;
    }
    setErrors({ root: error.data?.message || 'Registration failed' });
  }
});
</script>

<template>
  <form @submit="onSubmit" novalidate>
    <div v-if="errors.root" role="alert" class="error-banner">
      {{ errors.root }}
    </div>

    <FormField name="name" label="Name" />
    <FormField name="email" label="Email" type="email" />
    <FormField name="password" label="Password" type="password" />
    <FormField name="confirmPassword" label="Confirm Password" type="password" />

    <button type="submit" :disabled="isSubmitting">
      {{ isSubmitting ? 'Registering...' : 'Register' }}
    </button>
  </form>
</template>
```

### Multi-Step Form (Wizard) Pattern

```tsx
// Multi-step form with React Hook Form
import { useForm, FormProvider, useFormContext } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { z } from 'zod';

// Step schemas
const step1Schema = z.object({
  name: z.string().min(1),
  email: z.string().email(),
});

const step2Schema = z.object({
  company: z.string().min(1),
  role: z.enum(['developer', 'designer', 'manager', 'other']),
});

const step3Schema = z.object({
  plan: z.enum(['free', 'pro', 'enterprise']),
  agreeToTerms: z.literal(true, {
    errorMap: () => ({ message: 'You must accept the terms' }),
  }),
});

const fullSchema = step1Schema.merge(step2Schema).merge(step3Schema);
type FormData = z.infer<typeof fullSchema>;

const stepSchemas = [step1Schema, step2Schema, step3Schema] as const;

function MultiStepForm() {
  const [step, setStep] = useState(0);
  const methods = useForm<FormData>({
    resolver: zodResolver(fullSchema),
    mode: 'onChange',
  });

  const nextStep = async () => {
    // Validate only current step fields
    const fields = Object.keys(stepSchemas[step].shape) as (keyof FormData)[];
    const isValid = await methods.trigger(fields);
    if (isValid) setStep(s => Math.min(s + 1, 2));
  };

  const prevStep = () => setStep(s => Math.max(s - 1, 0));

  const onSubmit = async (data: FormData) => {
    await fetch('/api/onboard', { method: 'POST', body: JSON.stringify(data) });
  };

  return (
    <FormProvider {...methods}>
      <form onSubmit={methods.handleSubmit(onSubmit)}>
        {/* Progress indicator */}
        <div role="progressbar" aria-valuenow={step + 1} aria-valuemax={3}>
          Step {step + 1} of 3
        </div>

        {step === 0 && <Step1 />}
        {step === 1 && <Step2 />}
        {step === 2 && <Step3 />}

        <div className="flex gap-2">
          {step > 0 && <button type="button" onClick={prevStep}>Back</button>}
          {step < 2 && <button type="button" onClick={nextStep}>Next</button>}
          {step === 2 && <button type="submit">Complete Setup</button>}
        </div>
      </form>
    </FormProvider>
  );
}
```

---

## Real-Time Patterns

### WebSocket (Socket.IO)

```typescript
// server/websocket.ts
import { Server } from 'socket.io';
import { createAdapter } from '@socket.io/redis-adapter';
import { createClient } from 'redis';

export function initWebSocket(httpServer: HttpServer) {
  const io = new Server(httpServer, {
    cors: { origin: process.env.FRONTEND_URL, credentials: true },
    transports: ['websocket', 'polling'],
    pingInterval: 25000,
    pingTimeout: 20000,
  });

  // Redis adapter for horizontal scaling (multiple server instances)
  const pubClient = createClient({ url: process.env.REDIS_URL });
  const subClient = pubClient.duplicate();
  Promise.all([pubClient.connect(), subClient.connect()]).then(() => {
    io.adapter(createAdapter(pubClient, subClient));
  });

  // Authentication middleware
  io.use(async (socket, next) => {
    const token = socket.handshake.auth.token;
    if (!token) return next(new Error('Authentication required'));
    try {
      const payload = verifyAccessToken(token);
      socket.data.userId = payload.sub;
      socket.data.role = payload.role;
      next();
    } catch {
      next(new Error('Invalid token'));
    }
  });

  io.on('connection', (socket) => {
    const userId = socket.data.userId;
    logger.info('User connected', { userId, socketId: socket.id });

    // Join user's personal room
    socket.join(`user:${userId}`);

    // Chat room example
    socket.on('join:room', async (roomId: string) => {
      const hasAccess = await checkRoomAccess(userId, roomId);
      if (!hasAccess) return socket.emit('error', { message: 'Access denied' });
      socket.join(`room:${roomId}`);
      socket.to(`room:${roomId}`).emit('user:joined', { userId });
    });

    socket.on('message:send', async (data: { roomId: string; content: string }) => {
      const message = await db.message.create({
        data: { roomId: data.roomId, authorId: userId, content: data.content },
        include: { author: { select: { id: true, name: true, avatar: true } } },
      });
      io.to(`room:${data.roomId}`).emit('message:new', message);
    });

    socket.on('typing:start', (roomId: string) => {
      socket.to(`room:${roomId}`).emit('typing', { userId, isTyping: true });
    });

    socket.on('typing:stop', (roomId: string) => {
      socket.to(`room:${roomId}`).emit('typing', { userId, isTyping: false });
    });

    socket.on('disconnect', (reason) => {
      logger.info('User disconnected', { userId, reason });
    });
  });

  return io;
}
```

```typescript
// Client: React hook for WebSocket
// hooks/useSocket.ts
import { io, Socket } from 'socket.io-client';

let socket: Socket | null = null;

function getSocket(token: string): Socket {
  if (!socket) {
    socket = io(process.env.NEXT_PUBLIC_WS_URL!, {
      auth: { token },
      transports: ['websocket', 'polling'],
      reconnection: true,
      reconnectionDelay: 1000,
      reconnectionDelayMax: 10000,
      reconnectionAttempts: 10,
    });
  }
  return socket;
}

export function useChat(roomId: string) {
  const { data: session } = useSession();
  const [messages, setMessages] = useState<Message[]>([]);
  const [typingUsers, setTypingUsers] = useState<Set<string>>(new Set());

  useEffect(() => {
    if (!session?.token) return;
    const ws = getSocket(session.token);

    ws.emit('join:room', roomId);

    ws.on('message:new', (message: Message) => {
      setMessages(prev => [...prev, message]);
    });

    ws.on('typing', ({ userId, isTyping }) => {
      setTypingUsers(prev => {
        const next = new Set(prev);
        isTyping ? next.add(userId) : next.delete(userId);
        return next;
      });
    });

    return () => {
      ws.off('message:new');
      ws.off('typing');
      ws.emit('leave:room', roomId);
    };
  }, [roomId, session?.token]);

  const sendMessage = useCallback((content: string) => {
    getSocket(session!.token).emit('message:send', { roomId, content });
  }, [roomId, session]);

  return { messages, typingUsers, sendMessage };
}
```

### Server-Sent Events (SSE)

```typescript
// server/routes/events.ts - SSE endpoint
app.get('/api/events', authMiddleware, (req, res) => {
  const userId = req.user!.id;

  // SSE headers
  res.writeHead(200, {
    'Content-Type': 'text/event-stream',
    'Cache-Control': 'no-cache',
    'Connection': 'keep-alive',
    'X-Accel-Buffering': 'no', // Disable Nginx buffering
  });

  // Heartbeat to keep connection alive
  const heartbeat = setInterval(() => {
    res.write(': heartbeat\n\n');
  }, 30000);

  // Subscribe to user events (using Redis pub/sub or EventEmitter)
  const channel = `events:${userId}`;

  function onEvent(data: string) {
    res.write(`data: ${data}\n\n`);
  }

  // With event types and IDs for reconnection
  function sendEvent(type: string, data: unknown, id?: string) {
    if (id) res.write(`id: ${id}\n`);
    res.write(`event: ${type}\n`);
    res.write(`data: ${JSON.stringify(data)}\n\n`);
  }

  eventBus.subscribe(channel, onEvent);

  // Send any missed events (using Last-Event-ID header)
  const lastEventId = req.headers['last-event-id'];
  if (lastEventId) {
    replayEventsSince(userId, lastEventId).then(events => {
      events.forEach(e => sendEvent(e.type, e.data, e.id));
    });
  }

  // Cleanup on disconnect
  req.on('close', () => {
    clearInterval(heartbeat);
    eventBus.unsubscribe(channel, onEvent);
  });
});
```

```typescript
// Client: React hook for SSE
export function useSSE<T>(url: string) {
  const [data, setData] = useState<T | null>(null);
  const [error, setError] = useState<Error | null>(null);
  const [status, setStatus] = useState<'connecting' | 'open' | 'closed'>('connecting');

  useEffect(() => {
    const eventSource = new EventSource(url, { withCredentials: true });

    eventSource.onopen = () => setStatus('open');

    eventSource.onmessage = (event) => {
      try {
        const parsed = JSON.parse(event.data) as T;
        setData(parsed);
      } catch (err) {
        setError(new Error('Failed to parse SSE data'));
      }
    };

    // Typed events
    eventSource.addEventListener('notification', (event) => {
      const notification = JSON.parse(event.data);
      showToast(notification);
    });

    eventSource.addEventListener('update', (event) => {
      const update = JSON.parse(event.data);
      queryClient.invalidateQueries({ queryKey: [update.resource] });
    });

    eventSource.onerror = () => {
      setStatus('closed');
      setError(new Error('SSE connection lost'));
      // EventSource auto-reconnects with Last-Event-ID
    };

    return () => eventSource.close();
  }, [url]);

  return { data, error, status };
}
```

### Smart Polling Pattern

```typescript
// hooks/usePolling.ts - Adaptive polling with visibility awareness
export function usePolling<T>(
  fetcher: () => Promise<T>,
  options: {
    interval: number;          // Base interval in ms
    maxInterval?: number;      // Max interval when idle (adaptive)
    enabled?: boolean;
    onData?: (data: T) => void;
    onError?: (error: Error) => void;
  },
) {
  const [data, setData] = useState<T | null>(null);
  const [error, setError] = useState<Error | null>(null);
  const intervalRef = useRef(options.interval);

  useEffect(() => {
    if (options.enabled === false) return;

    let timeoutId: NodeJS.Timeout;
    let isVisible = !document.hidden;

    const poll = async () => {
      try {
        const result = await fetcher();
        setData(prev => {
          // Only update if data changed (reduce re-renders)
          if (JSON.stringify(prev) === JSON.stringify(result)) return prev;
          options.onData?.(result);
          // Reset interval on change (something is happening)
          intervalRef.current = options.interval;
          return result;
        });
        setError(null);
      } catch (err) {
        const error = err instanceof Error ? err : new Error(String(err));
        setError(error);
        options.onError?.(error);
      }

      // Adaptive: increase interval if nothing changes, up to max
      if (options.maxInterval) {
        intervalRef.current = Math.min(intervalRef.current * 1.5, options.maxInterval);
      }

      // Only schedule next poll if page is visible
      if (isVisible) {
        timeoutId = setTimeout(poll, intervalRef.current);
      }
    };

    // Pause/resume based on page visibility
    const handleVisibility = () => {
      isVisible = !document.hidden;
      if (isVisible) {
        intervalRef.current = options.interval; // Reset on focus
        poll();
      } else {
        clearTimeout(timeoutId);
      }
    };

    document.addEventListener('visibilitychange', handleVisibility);
    poll(); // Initial fetch

    return () => {
      clearTimeout(timeoutId);
      document.removeEventListener('visibilitychange', handleVisibility);
    };
  }, [options.enabled, options.interval]);

  return { data, error };
}

// Usage
const { data: status } = usePolling(
  () => fetch('/api/deploy/status').then(r => r.json()),
  { interval: 2000, maxInterval: 30000, enabled: isDeploying },
);
```

### Choosing the Right Real-Time Pattern

```
Pattern      | Latency    | Complexity | Scalability     | Use Case
-------------|------------|------------|-----------------|-------------------------
WebSocket    | Lowest     | High       | Needs Redis/etc | Chat, gaming, collab edit
SSE          | Low        | Medium     | Good (stateless)| Notifications, live feeds
Polling      | Medium     | Low        | Best            | Status checks, dashboards
Long Polling | Low-Medium | Medium     | Moderate        | Legacy, fallback

Decision:
  - Need bidirectional? → WebSocket
  - Server-to-client only? → SSE
  - Simple, infrequent updates? → Polling
  - Behind strict firewalls? → Long Polling / SSE (HTTP-based)
  - > 10K concurrent connections? → SSE or WebSocket + Redis pub/sub
```

---

## File Upload Patterns

### Direct Upload to Cloud Storage (Presigned URLs)

```typescript
// server/routes/upload.ts - Generate presigned URL
import { S3Client, PutObjectCommand } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { nanoid } from 'nanoid';

const s3 = new S3Client({ region: process.env.AWS_REGION });

app.post('/api/uploads/presign', authMiddleware, async (req, res) => {
  const { filename, contentType, size } = presignSchema.parse(req.body);

  // Validate
  const maxSize = 10 * 1024 * 1024; // 10MB
  if (size > maxSize) {
    return res.status(400).json({ error: { message: 'File too large (max 10MB)' } });
  }

  const allowedTypes = ['image/jpeg', 'image/png', 'image/webp', 'application/pdf'];
  if (!allowedTypes.includes(contentType)) {
    return res.status(400).json({ error: { message: 'File type not allowed' } });
  }

  // Generate unique key
  const ext = filename.split('.').pop();
  const key = `uploads/${req.user!.id}/${nanoid()}.${ext}`;

  const command = new PutObjectCommand({
    Bucket: process.env.S3_BUCKET!,
    Key: key,
    ContentType: contentType,
    ContentLength: size,
    Metadata: { userId: req.user!.id, originalName: filename },
  });

  const presignedUrl = await getSignedUrl(s3, command, { expiresIn: 300 }); // 5min

  // Store upload record
  const upload = await db.upload.create({
    data: {
      key,
      filename,
      contentType,
      size,
      status: 'pending',
      userId: req.user!.id,
    },
  });

  res.json({
    data: {
      uploadId: upload.id,
      presignedUrl,
      key,
      publicUrl: `${process.env.CDN_URL}/${key}`,
    },
  });
});

// Confirm upload completion
app.post('/api/uploads/:id/confirm', authMiddleware, async (req, res) => {
  const upload = await db.upload.update({
    where: { id: req.params.id, userId: req.user!.id },
    data: { status: 'confirmed' },
  });
  res.json({ data: upload });
});
```

```typescript
// Client: Upload component with progress
export function useFileUpload() {
  const [progress, setProgress] = useState(0);
  const [status, setStatus] = useState<'idle' | 'uploading' | 'done' | 'error'>('idle');

  const upload = async (file: File): Promise<string> => {
    setStatus('uploading');
    setProgress(0);

    try {
      // Step 1: Get presigned URL
      const { data } = await api.post<PresignResponse>('/api/uploads/presign', {
        filename: file.name,
        contentType: file.type,
        size: file.size,
      });

      // Step 2: Upload directly to S3 with progress
      await new Promise<void>((resolve, reject) => {
        const xhr = new XMLHttpRequest();
        xhr.upload.onprogress = (e) => {
          if (e.lengthComputable) setProgress(Math.round((e.loaded / e.total) * 100));
        };
        xhr.onload = () => (xhr.status === 200 ? resolve() : reject(new Error('Upload failed')));
        xhr.onerror = () => reject(new Error('Network error'));
        xhr.open('PUT', data.presignedUrl);
        xhr.setRequestHeader('Content-Type', file.type);
        xhr.send(file);
      });

      // Step 3: Confirm upload
      await api.post(`/api/uploads/${data.uploadId}/confirm`, {});

      setStatus('done');
      return data.publicUrl;
    } catch (err) {
      setStatus('error');
      throw err;
    }
  };

  return { upload, progress, status };
}
```

### Multipart Upload (Server-Side Processing)

```typescript
// server/routes/upload.ts - Multer-based with processing
import multer from 'multer';
import sharp from 'sharp';

const upload = multer({
  storage: multer.memoryStorage(),
  limits: {
    fileSize: 10 * 1024 * 1024,  // 10MB
    files: 5,                     // Max 5 files per request
  },
  fileFilter: (_req, file, cb) => {
    const allowed = /^image\/(jpeg|png|webp|gif)$/;
    cb(null, allowed.test(file.mimetype));
  },
});

app.post('/api/images', authMiddleware, upload.array('images', 5), async (req, res) => {
  const files = req.files as Express.Multer.File[];
  if (!files?.length) {
    return res.status(400).json({ error: { message: 'No files provided' } });
  }

  const results = await Promise.all(
    files.map(async (file) => {
      // Process image variants
      const id = nanoid();
      const variants = [
        { suffix: 'thumb', width: 200, height: 200, fit: 'cover' as const },
        { suffix: 'medium', width: 800, height: 600, fit: 'inside' as const },
        { suffix: 'large', width: 1920, height: 1080, fit: 'inside' as const },
      ];

      const uploads = await Promise.all(
        variants.map(async (variant) => {
          const buffer = await sharp(file.buffer)
            .resize(variant.width, variant.height, { fit: variant.fit })
            .webp({ quality: 80 })
            .toBuffer();

          const key = `images/${id}-${variant.suffix}.webp`;
          await s3.send(new PutObjectCommand({
            Bucket: process.env.S3_BUCKET!,
            Key: key,
            Body: buffer,
            ContentType: 'image/webp',
            CacheControl: 'public, max-age=31536000',
          }));

          return { variant: variant.suffix, url: `${process.env.CDN_URL}/${key}` };
        }),
      );

      return { id, originalName: file.originalname, variants: Object.fromEntries(
        uploads.map(u => [u.variant, u.url]),
      )};
    }),
  );

  res.json({ data: results });
});
```

---

## Optimistic Update Patterns

### React Query / TanStack Query

```typescript
// hooks/useTodos.ts - Optimistic CRUD
import { useMutation, useQueryClient } from '@tanstack/react-query';

export function useToggleTodo() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (todoId: string) => api.patch<Todo>(`/api/todos/${todoId}/toggle`, {}),

    onMutate: async (todoId) => {
      // Cancel outgoing queries to prevent overwriting optimistic update
      await queryClient.cancelQueries({ queryKey: ['todos'] });

      // Snapshot previous value for rollback
      const previousTodos = queryClient.getQueryData<Todo[]>(['todos']);

      // Optimistically update
      queryClient.setQueryData<Todo[]>(['todos'], (old) =>
        old?.map(todo =>
          todo.id === todoId ? { ...todo, completed: !todo.completed } : todo,
        ),
      );

      return { previousTodos };
    },

    onError: (_err, _todoId, context) => {
      // Rollback on error
      if (context?.previousTodos) {
        queryClient.setQueryData(['todos'], context.previousTodos);
      }
      toast.error('Failed to update todo');
    },

    onSettled: () => {
      // Always refetch to ensure consistency
      queryClient.invalidateQueries({ queryKey: ['todos'] });
    },
  });
}

// Optimistic create with temporary ID
export function useCreateTodo() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (input: CreateTodoInput) => api.post<Todo>('/api/todos', input),

    onMutate: async (input) => {
      await queryClient.cancelQueries({ queryKey: ['todos'] });
      const previousTodos = queryClient.getQueryData<Todo[]>(['todos']);

      // Add with temporary ID
      const optimisticTodo: Todo = {
        id: `temp-${Date.now()}`,
        ...input,
        completed: false,
        createdAt: new Date().toISOString(),
        _optimistic: true, // Flag for UI styling
      };

      queryClient.setQueryData<Todo[]>(['todos'], (old) =>
        old ? [optimisticTodo, ...old] : [optimisticTodo],
      );

      return { previousTodos };
    },

    onError: (_err, _input, context) => {
      if (context?.previousTodos) {
        queryClient.setQueryData(['todos'], context.previousTodos);
      }
      toast.error('Failed to create todo');
    },

    onSettled: () => {
      queryClient.invalidateQueries({ queryKey: ['todos'] });
    },
  });
}
```

### Optimistic Delete with Undo

```typescript
// hooks/useDeleteTodo.ts
export function useDeleteTodo() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (todoId: string) => api.delete<void>(`/api/todos/${todoId}`),

    onMutate: async (todoId) => {
      await queryClient.cancelQueries({ queryKey: ['todos'] });
      const previousTodos = queryClient.getQueryData<Todo[]>(['todos']);

      // Optimistically remove
      queryClient.setQueryData<Todo[]>(['todos'], (old) =>
        old?.filter(todo => todo.id !== todoId),
      );

      // Show undo toast
      const deletedTodo = previousTodos?.find(t => t.id === todoId);
      if (deletedTodo) {
        toast('Todo deleted', {
          action: {
            label: 'Undo',
            onClick: () => {
              // Restore to cache and cancel the mutation
              queryClient.setQueryData(['todos'], previousTodos);
              // Note: the actual API delete may have already happened
              // In production, use a "soft delete" endpoint with undo window
            },
          },
          duration: 5000,
        });
      }

      return { previousTodos };
    },

    onError: (_err, _todoId, context) => {
      if (context?.previousTodos) {
        queryClient.setQueryData(['todos'], context.previousTodos);
      }
      toast.error('Failed to delete todo');
    },

    onSettled: () => {
      queryClient.invalidateQueries({ queryKey: ['todos'] });
    },
  });
}
```

### Server Actions Optimistic Updates (Next.js)

```tsx
// app/actions/todos.ts
'use server';
import { revalidatePath } from 'next/cache';

export async function toggleTodo(todoId: string) {
  const todo = await db.todo.findUnique({ where: { id: todoId } });
  if (!todo) throw new Error('Todo not found');

  await db.todo.update({
    where: { id: todoId },
    data: { completed: !todo.completed },
  });

  revalidatePath('/todos');
}

// app/todos/page.tsx
'use client';
import { useOptimistic, useTransition } from 'react';
import { toggleTodo } from '~/app/actions/todos';

function TodoList({ todos }: { todos: Todo[] }) {
  const [isPending, startTransition] = useTransition();
  const [optimisticTodos, setOptimisticTodos] = useOptimistic(
    todos,
    (state: Todo[], toggledId: string) =>
      state.map(todo =>
        todo.id === toggledId ? { ...todo, completed: !todo.completed } : todo,
      ),
  );

  const handleToggle = (todoId: string) => {
    startTransition(async () => {
      setOptimisticTodos(todoId);
      await toggleTodo(todoId);
    });
  };

  return (
    <ul>
      {optimisticTodos.map(todo => (
        <li
          key={todo.id}
          onClick={() => handleToggle(todo.id)}
          style={{ opacity: isPending ? 0.7 : 1 }}
        >
          <input type="checkbox" checked={todo.completed} readOnly />
          {todo.title}
        </li>
      ))}
    </ul>
  );
}
```
