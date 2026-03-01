# API Security Reference

## Table of Contents

1. [Authentication Implementation](#authentication-implementation)
2. [Rate Limiting](#rate-limiting)
3. [Input Validation](#input-validation)
4. [CORS Configuration](#cors-configuration)
5. [API Key Management](#api-key-management)
6. [Request Signing](#request-signing)
7. [Security Middleware Stack](#security-middleware-stack)

---

## Authentication Implementation

### JWT with Refresh Token Rotation

```typescript
import { SignJWT, jwtVerify, type JWTPayload } from 'jose';
import { randomBytes, createHash } from 'node:crypto';

const ACCESS_SECRET = new TextEncoder().encode(process.env.JWT_ACCESS_SECRET);
const REFRESH_SECRET = new TextEncoder().encode(process.env.JWT_REFRESH_SECRET);

interface TokenPair {
  accessToken: string;
  refreshToken: string;
}

async function generateTokenPair(userId: string, roles: string[]): Promise<TokenPair> {
  const tokenFamily = randomBytes(16).toString('hex');

  const accessToken = await new SignJWT({ sub: userId, roles })
    .setProtectedHeader({ alg: 'HS256' })
    .setIssuedAt()
    .setExpirationTime('15m')
    .setJti(randomBytes(16).toString('hex'))
    .sign(ACCESS_SECRET);

  const refreshToken = await new SignJWT({ sub: userId, family: tokenFamily })
    .setProtectedHeader({ alg: 'HS256' })
    .setIssuedAt()
    .setExpirationTime('7d')
    .setJti(randomBytes(16).toString('hex'))
    .sign(REFRESH_SECRET);

  // Store refresh token hash in DB (not the token itself)
  const tokenHash = createHash('sha256').update(refreshToken).digest('hex');
  await db.refreshToken.create({
    data: {
      userId,
      tokenHash,
      family: tokenFamily,
      expiresAt: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000),
    },
  });

  return { accessToken, refreshToken };
}

async function rotateRefreshToken(oldRefreshToken: string): Promise<TokenPair> {
  // Verify the old token
  const { payload } = await jwtVerify(oldRefreshToken, REFRESH_SECRET);
  const oldHash = createHash('sha256').update(oldRefreshToken).digest('hex');

  // Find and validate in DB
  const stored = await db.refreshToken.findUnique({ where: { tokenHash: oldHash } });

  if (!stored) {
    // Token reuse detected! Invalidate entire family
    await db.refreshToken.deleteMany({ where: { family: payload.family as string } });
    throw new AuthError('REFRESH_TOKEN_REUSE', 'Token reuse detected, all sessions revoked');
  }

  // Delete old token
  await db.refreshToken.delete({ where: { id: stored.id } });

  // Issue new pair (same family)
  const user = await db.user.findUnique({ where: { id: payload.sub } });
  if (!user) throw new AuthError('USER_NOT_FOUND');

  return generateTokenPair(user.id, user.roles);
}
```

### Cookie-Based Token Transport

```typescript
function setAuthCookies(res: Response, tokens: TokenPair) {
  // Access token - shorter lived, sent with every request
  res.cookie('access_token', tokens.accessToken, {
    httpOnly: true,
    secure: process.env.NODE_ENV === 'production',
    sameSite: 'strict',
    maxAge: 15 * 60 * 1000, // 15 minutes
    path: '/',
  });

  // Refresh token - only sent to refresh endpoint
  res.cookie('refresh_token', tokens.refreshToken, {
    httpOnly: true,
    secure: process.env.NODE_ENV === 'production',
    sameSite: 'strict',
    maxAge: 7 * 24 * 60 * 60 * 1000, // 7 days
    path: '/api/auth/refresh', // Only sent to refresh endpoint
  });
}
```

---

## Rate Limiting

### Sliding Window with Redis

```typescript
import { Redis } from 'ioredis';

interface RateLimitConfig {
  windowMs: number;   // Window size in milliseconds
  maxRequests: number; // Max requests per window
  keyPrefix?: string;
}

class SlidingWindowRateLimiter {
  constructor(
    private redis: Redis,
    private config: RateLimitConfig,
  ) {}

  async check(key: string): Promise<{
    allowed: boolean;
    remaining: number;
    resetAt: Date;
    retryAfter?: number;
  }> {
    const fullKey = `${this.config.keyPrefix ?? 'rl'}:${key}`;
    const now = Date.now();
    const windowStart = now - this.config.windowMs;

    // Atomic operation using Lua script
    const result = await this.redis.eval(`
      -- Remove expired entries
      redis.call('ZREMRANGEBYSCORE', KEYS[1], '-inf', ARGV[1])
      -- Count remaining in window
      local count = redis.call('ZCARD', KEYS[1])
      if count < tonumber(ARGV[3]) then
        -- Add new request
        redis.call('ZADD', KEYS[1], ARGV[2], ARGV[2] .. ':' .. math.random(1000000))
        redis.call('PEXPIRE', KEYS[1], ARGV[4])
        return {1, tonumber(ARGV[3]) - count - 1}
      end
      -- Get oldest entry to calculate retry-after
      local oldest = redis.call('ZRANGE', KEYS[1], 0, 0, 'WITHSCORES')
      return {0, 0, oldest[2]}
    `, 1, fullKey, windowStart, now, this.config.maxRequests, this.config.windowMs) as number[];

    const allowed = result[0] === 1;
    const remaining = result[1];
    const resetAt = new Date(now + this.config.windowMs);

    return {
      allowed,
      remaining,
      resetAt,
      retryAfter: allowed ? undefined : Math.ceil((Number(result[2]) + this.config.windowMs - now) / 1000),
    };
  }
}

// Express middleware
function rateLimitMiddleware(limiter: SlidingWindowRateLimiter, keyFn?: (req: Request) => string) {
  return async (req: Request, res: Response, next: NextFunction) => {
    const key = keyFn ? keyFn(req) : req.ip ?? 'unknown';
    const result = await limiter.check(key);

    res.setHeader('X-RateLimit-Limit', limiter.config.maxRequests);
    res.setHeader('X-RateLimit-Remaining', result.remaining);
    res.setHeader('X-RateLimit-Reset', result.resetAt.toISOString());

    if (!result.allowed) {
      res.setHeader('Retry-After', result.retryAfter ?? 60);
      return res.status(429).json({
        error: { code: 'RATE_LIMIT_EXCEEDED', retryAfter: result.retryAfter },
      });
    }
    next();
  };
}

// Usage: different limits for different endpoints
const authLimiter = new SlidingWindowRateLimiter(redis, {
  windowMs: 15 * 60 * 1000, // 15 minutes
  maxRequests: 5,             // 5 login attempts
  keyPrefix: 'rl:auth',
});

const apiLimiter = new SlidingWindowRateLimiter(redis, {
  windowMs: 60 * 1000,       // 1 minute
  maxRequests: 100,           // 100 requests
  keyPrefix: 'rl:api',
});

app.post('/api/auth/login', rateLimitMiddleware(authLimiter, req => req.body.email));
app.use('/api', rateLimitMiddleware(apiLimiter));
```

---

## Input Validation

### Zod Schema Patterns

```typescript
import { z } from 'zod';

// Reusable schemas
const emailSchema = z.string().email().max(254).toLowerCase().trim();
const passwordSchema = z.string()
  .min(12, 'Password must be at least 12 characters')
  .max(128)
  .regex(/[A-Z]/, 'Must contain uppercase letter')
  .regex(/[a-z]/, 'Must contain lowercase letter')
  .regex(/[0-9]/, 'Must contain number');

const paginationSchema = z.object({
  cursor: z.string().optional(),
  limit: z.coerce.number().int().min(1).max(100).default(20),
  sort: z.enum(['asc', 'desc']).default('desc'),
});

const dateRangeSchema = z.object({
  from: z.coerce.date(),
  to: z.coerce.date(),
}).refine(d => d.from <= d.to, 'from must be before to');

// API-specific schema
const createOrderSchema = z.object({
  items: z.array(z.object({
    productId: z.string().uuid(),
    quantity: z.number().int().min(1).max(999),
  })).min(1).max(100),
  shippingAddress: z.object({
    line1: z.string().min(1).max(200),
    line2: z.string().max(200).optional(),
    city: z.string().min(1).max(100),
    state: z.string().min(1).max(100),
    postalCode: z.string().regex(/^\d{5}(-\d{4})?$/),
    country: z.string().length(2), // ISO 3166-1 alpha-2
  }),
  couponCode: z.string().max(50).optional(),
});

// Validation middleware
function validate<T extends z.ZodSchema>(schema: T) {
  return (req: Request, res: Response, next: NextFunction) => {
    const result = schema.safeParse(req.body);
    if (!result.success) {
      return res.status(400).json({
        error: {
          code: 'VALIDATION_ERROR',
          details: result.error.flatten().fieldErrors,
        },
      });
    }
    req.body = result.data; // Replace with validated + transformed data
    next();
  };
}
```

---

## CORS Configuration

```typescript
import cors from 'cors';

// Production CORS configuration
const corsOptions: cors.CorsOptions = {
  // Explicit origin whitelist (never use '*' with credentials)
  origin: (origin, callback) => {
    const allowedOrigins = [
      'https://myapp.com',
      'https://admin.myapp.com',
      ...(process.env.NODE_ENV !== 'production'
        ? ['http://localhost:3000', 'http://localhost:5173']
        : []),
    ];

    // Allow requests with no origin (mobile apps, curl, server-to-server)
    if (!origin || allowedOrigins.includes(origin)) {
      callback(null, true);
    } else {
      callback(new Error(`CORS: origin ${origin} not allowed`));
    }
  },
  credentials: true,  // Allow cookies
  methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization', 'X-Request-ID'],
  exposedHeaders: ['X-RateLimit-Remaining', 'X-Request-ID'],
  maxAge: 86400, // Preflight cache: 24 hours
};

app.use(cors(corsOptions));
```

---

## API Key Management

### Key Generation and Hashing

```typescript
import { randomBytes, createHash, timingSafeEqual } from 'node:crypto';

interface ApiKey {
  id: string;
  prefix: string;       // Visible identifier (e.g., "sk_live_abc12")
  hash: string;          // SHA-256 hash of the full key
  scopes: string[];      // Permitted operations
  ownerId: string;       // User or service account
  revokedAt: Date | null;
  expiresAt: Date | null;
  rateLimitTier: string; // "free" | "standard" | "premium"
  createdAt: Date;
  lastUsedAt: Date | null;
}

/**
 * Generate a cryptographically secure API key with a human-readable prefix.
 * The raw key is returned ONCE at creation and never stored.
 */
function generateApiKey(environment: 'live' | 'test' = 'live'): {
  rawKey: string;
  prefix: string;
  hash: string;
} {
  // 32 bytes = 256 bits of entropy, Base64URL-encoded
  const secret = randomBytes(32).toString('base64url');
  const prefix = `sk_${environment}_${secret.slice(0, 5)}`;
  const rawKey = `sk_${environment}_${secret}`;

  // Store only the SHA-256 hash — raw key is never persisted
  const hash = createHash('sha256').update(rawKey).digest('hex');

  return { rawKey, prefix, hash };
}

/**
 * Verify a provided API key against the stored hash using
 * constant-time comparison to prevent timing attacks.
 */
function verifyApiKey(providedKey: string, storedHash: string): boolean {
  const providedHash = createHash('sha256').update(providedKey).digest('hex');
  const a = Buffer.from(providedHash, 'hex');
  const b = Buffer.from(storedHash, 'hex');
  return a.length === b.length && timingSafeEqual(a, b);
}
```

### Key Scoping, Rate Limiting, and Middleware

```typescript
// Scope definitions map API key permissions to route groups
const SCOPE_PERMISSIONS: Record<string, { methods: string[]; pathPattern: RegExp }[]> = {
  'read:orders':  [{ methods: ['GET'], pathPattern: /^\/api\/orders/ }],
  'write:orders': [{ methods: ['POST', 'PUT', 'PATCH'], pathPattern: /^\/api\/orders/ }],
  'read:users':   [{ methods: ['GET'], pathPattern: /^\/api\/users/ }],
  'admin':        [{ methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE'], pathPattern: /^\/api/ }],
};

const RATE_LIMIT_TIERS: Record<string, { windowMs: number; maxRequests: number }> = {
  free:     { windowMs: 60_000, maxRequests: 30 },
  standard: { windowMs: 60_000, maxRequests: 200 },
  premium:  { windowMs: 60_000, maxRequests: 1000 },
};

function apiKeyAuthMiddleware(redis: Redis) {
  return async (req: Request, res: Response, next: NextFunction) => {
    const authHeader = req.headers['authorization'];
    if (!authHeader?.startsWith('Bearer sk_')) {
      return res.status(401).json({ error: { code: 'MISSING_API_KEY' } });
    }

    const rawKey = authHeader.slice(7); // Strip "Bearer "
    const hash = createHash('sha256').update(rawKey).digest('hex');

    // Look up key by hash
    const apiKey = await db.apiKey.findUnique({ where: { hash } });

    if (!apiKey || apiKey.revokedAt) {
      return res.status(401).json({ error: { code: 'INVALID_API_KEY' } });
    }
    if (apiKey.expiresAt && apiKey.expiresAt < new Date()) {
      return res.status(401).json({ error: { code: 'API_KEY_EXPIRED' } });
    }

    // Enforce scoped permissions
    const hasPermission = apiKey.scopes.some((scope) => {
      const rules = SCOPE_PERMISSIONS[scope];
      return rules?.some(
        (rule) => rule.methods.includes(req.method) && rule.pathPattern.test(req.path),
      );
    });
    if (!hasPermission) {
      return res.status(403).json({ error: { code: 'INSUFFICIENT_SCOPE' } });
    }

    // Per-key rate limiting via Redis sliding window
    const tier = RATE_LIMIT_TIERS[apiKey.rateLimitTier] ?? RATE_LIMIT_TIERS.free;
    const limiter = new SlidingWindowRateLimiter(redis, {
      ...tier,
      keyPrefix: `rl:apikey:${apiKey.id}`,
    });
    const limitResult = await limiter.check(apiKey.id);

    res.setHeader('X-RateLimit-Limit', tier.maxRequests);
    res.setHeader('X-RateLimit-Remaining', limitResult.remaining);
    if (!limitResult.allowed) {
      res.setHeader('Retry-After', limitResult.retryAfter ?? 60);
      return res.status(429).json({ error: { code: 'RATE_LIMIT_EXCEEDED' } });
    }

    // Update last-used timestamp asynchronously (non-blocking)
    db.apiKey.update({ where: { id: apiKey.id }, data: { lastUsedAt: new Date() } }).catch(() => {});

    // Attach identity to request for downstream handlers
    (req as any).apiKey = apiKey;
    next();
  };
}
```

### Key Rotation and Revocation

```typescript
/**
 * Rotate an API key: create a new key, grant a grace period on the old one,
 * then revoke the old key automatically after the overlap window.
 */
async function rotateApiKey(
  oldKeyId: string,
  gracePeriodMs: number = 24 * 60 * 60 * 1000, // 24-hour overlap
): Promise<{ newRawKey: string; oldKeyExpiresAt: Date }> {
  const oldKey = await db.apiKey.findUniqueOrThrow({ where: { id: oldKeyId } });

  // Generate replacement key inheriting the same scopes and tier
  const { rawKey, prefix, hash } = generateApiKey('live');
  await db.apiKey.create({
    data: {
      prefix,
      hash,
      scopes: oldKey.scopes,
      ownerId: oldKey.ownerId,
      rateLimitTier: oldKey.rateLimitTier,
      revokedAt: null,
      expiresAt: oldKey.expiresAt, // Inherit original expiration policy
    },
  });

  // Set old key to expire after grace period instead of immediate revocation
  const oldKeyExpiresAt = new Date(Date.now() + gracePeriodMs);
  await db.apiKey.update({
    where: { id: oldKeyId },
    data: { expiresAt: oldKeyExpiresAt },
  });

  return { newRawKey: rawKey, oldKeyExpiresAt };
}

/**
 * Immediately revoke an API key (e.g., on suspected compromise).
 */
async function revokeApiKey(keyId: string, reason: string): Promise<void> {
  await db.apiKey.update({
    where: { id: keyId },
    data: { revokedAt: new Date() },
  });

  // Audit log for security review
  await db.auditLog.create({
    data: {
      action: 'API_KEY_REVOKED',
      targetId: keyId,
      reason,
      timestamp: new Date(),
    },
  });
}
```

---

## Request Signing

### HMAC-SHA256 Signing (Client-Side)

```typescript
import { createHmac } from 'node:crypto';

interface SignedRequestHeaders {
  'X-Signature': string;
  'X-Timestamp': string;
  'X-Nonce': string;
}

/**
 * Build a canonical string from the request components and sign it
 * with HMAC-SHA256. Follows an AWS Signature V4-inspired approach:
 *   CanonicalRequest = METHOD\nPATH\nQUERY\nTIMESTAMP\nNONCE\nBODY_HASH
 */
function signRequest(
  method: string,
  path: string,
  query: Record<string, string>,
  body: string | null,
  secretKey: string,
): SignedRequestHeaders {
  const timestamp = Math.floor(Date.now() / 1000).toString();
  const nonce = randomBytes(16).toString('hex');

  // Sort query parameters for deterministic ordering
  const sortedQuery = Object.keys(query)
    .sort()
    .map((k) => `${encodeURIComponent(k)}=${encodeURIComponent(query[k])}`)
    .join('&');

  // Hash the body (empty string if no body)
  const bodyHash = createHash('sha256')
    .update(body ?? '')
    .digest('hex');

  const canonicalRequest = [
    method.toUpperCase(),
    path,
    sortedQuery,
    timestamp,
    nonce,
    bodyHash,
  ].join('\n');

  const signature = createHmac('sha256', secretKey)
    .update(canonicalRequest)
    .digest('hex');

  return {
    'X-Signature': signature,
    'X-Timestamp': timestamp,
    'X-Nonce': nonce,
  };
}
```

### Signature Verification Middleware (Server-Side)

```typescript
import { Redis } from 'ioredis';

interface SignatureConfig {
  maxTimestampDriftSeconds: number; // Max allowed clock skew
  nonceExpirySeconds: number;      // How long to remember nonces
}

const DEFAULT_SIG_CONFIG: SignatureConfig = {
  maxTimestampDriftSeconds: 300, // 5-minute window
  nonceExpirySeconds: 600,      // 10-minute nonce TTL
};

/**
 * Middleware that verifies HMAC-SHA256 request signatures, validates
 * timestamps to prevent replay attacks, and tracks nonces in Redis.
 */
function signatureVerificationMiddleware(redis: Redis, config = DEFAULT_SIG_CONFIG) {
  return async (req: Request, res: Response, next: NextFunction) => {
    const signature = req.headers['x-signature'] as string;
    const timestamp = req.headers['x-timestamp'] as string;
    const nonce = req.headers['x-nonce'] as string;

    if (!signature || !timestamp || !nonce) {
      return res.status(401).json({
        error: { code: 'MISSING_SIGNATURE_HEADERS', message: 'X-Signature, X-Timestamp, and X-Nonce headers are required' },
      });
    }

    // --- Timestamp validation ---
    const requestTime = parseInt(timestamp, 10);
    const now = Math.floor(Date.now() / 1000);
    if (isNaN(requestTime) || Math.abs(now - requestTime) > config.maxTimestampDriftSeconds) {
      return res.status(401).json({
        error: { code: 'TIMESTAMP_OUT_OF_RANGE', message: `Timestamp must be within ${config.maxTimestampDriftSeconds}s of server time` },
      });
    }

    // --- Replay attack prevention via nonce ---
    const nonceKey = `nonce:${nonce}`;
    const nonceExists = await redis.set(nonceKey, '1', 'EX', config.nonceExpirySeconds, 'NX');
    if (nonceExists === null) {
      return res.status(401).json({
        error: { code: 'NONCE_REUSED', message: 'This nonce has already been used' },
      });
    }

    // --- Retrieve the signing secret for this API key ---
    const apiKey = (req as any).apiKey as ApiKey | undefined;
    if (!apiKey) {
      return res.status(401).json({ error: { code: 'API_KEY_REQUIRED' } });
    }
    const signingSecret = await db.signingSecret.findUnique({
      where: { apiKeyId: apiKey.id },
    });
    if (!signingSecret) {
      return res.status(401).json({ error: { code: 'SIGNING_SECRET_NOT_FOUND' } });
    }

    // --- Reconstruct canonical request and verify ---
    const sortedQuery = Object.keys(req.query as Record<string, string>)
      .sort()
      .map((k) => `${encodeURIComponent(k)}=${encodeURIComponent((req.query as any)[k])}`)
      .join('&');

    const bodyHash = createHash('sha256')
      .update(typeof req.body === 'string' ? req.body : JSON.stringify(req.body) ?? '')
      .digest('hex');

    const canonicalRequest = [
      req.method.toUpperCase(),
      req.path,
      sortedQuery,
      timestamp,
      nonce,
      bodyHash,
    ].join('\n');

    const expectedSignature = createHmac('sha256', signingSecret.secret)
      .update(canonicalRequest)
      .digest('hex');

    // Constant-time comparison prevents timing attacks on the signature
    const a = Buffer.from(signature, 'hex');
    const b = Buffer.from(expectedSignature, 'hex');
    if (a.length !== b.length || !timingSafeEqual(a, b)) {
      return res.status(401).json({
        error: { code: 'INVALID_SIGNATURE', message: 'Request signature verification failed' },
      });
    }

    next();
  };
}
```

### Webhook Delivery with Request Signing

```typescript
/**
 * Sign and deliver an outbound webhook, following the same canonical
 * signing scheme so recipients can verify authenticity.
 */
async function deliverSignedWebhook(
  url: string,
  event: string,
  payload: Record<string, unknown>,
  webhookSecret: string,
): Promise<{ success: boolean; statusCode?: number }> {
  const body = JSON.stringify(payload);
  const timestamp = Math.floor(Date.now() / 1000).toString();
  const nonce = randomBytes(16).toString('hex');

  const bodyHash = createHash('sha256').update(body).digest('hex');
  const signingContent = `${timestamp}.${nonce}.${bodyHash}`;
  const signature = createHmac('sha256', webhookSecret)
    .update(signingContent)
    .digest('hex');

  try {
    const response = await fetch(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Webhook-Event': event,
        'X-Webhook-Timestamp': timestamp,
        'X-Webhook-Nonce': nonce,
        'X-Webhook-Signature': `sha256=${signature}`,
      },
      body,
      signal: AbortSignal.timeout(10_000), // 10-second timeout
    });

    return { success: response.ok, statusCode: response.status };
  } catch (err) {
    return { success: false };
  }
}

/**
 * Recipient-side helper to verify an incoming webhook signature.
 */
function verifyWebhookSignature(
  rawBody: string,
  headers: Record<string, string>,
  secret: string,
): boolean {
  const timestamp = headers['x-webhook-timestamp'];
  const nonce = headers['x-webhook-nonce'];
  const receivedSig = headers['x-webhook-signature']?.replace('sha256=', '');

  if (!timestamp || !nonce || !receivedSig) return false;

  // Reject if timestamp is older than 5 minutes
  const age = Math.floor(Date.now() / 1000) - parseInt(timestamp, 10);
  if (isNaN(age) || age > 300) return false;

  const bodyHash = createHash('sha256').update(rawBody).digest('hex');
  const expected = createHmac('sha256', secret)
    .update(`${timestamp}.${nonce}.${bodyHash}`)
    .digest('hex');

  const a = Buffer.from(receivedSig, 'hex');
  const b = Buffer.from(expected, 'hex');
  return a.length === b.length && timingSafeEqual(a, b);
}
```

---

## Security Middleware Stack

```typescript
// Production security middleware in recommended order
import helmet from 'helmet';
import { randomUUID } from 'node:crypto';

// 1. Request ID for tracing
app.use((req, res, next) => {
  req.id = req.headers['x-request-id'] as string || randomUUID();
  res.setHeader('X-Request-ID', req.id);
  next();
});

// 2. Security headers
app.use(helmet({
  contentSecurityPolicy: {
    directives: {
      defaultSrc: ["'self'"],
      scriptSrc: ["'self'"],
      styleSrc: ["'self'", "'unsafe-inline'"],
      imgSrc: ["'self'", 'data:', 'https:'],
      connectSrc: ["'self'"],
      fontSrc: ["'self'"],
      objectSrc: ["'none'"],
      frameSrc: ["'none'"],
      baseUri: ["'self'"],
      formAction: ["'self'"],
      upgradeInsecureRequests: [],
    },
  },
  crossOriginEmbedderPolicy: false, // May break loading external images
}));

// 3. CORS
app.use(cors(corsOptions));

// 4. Body parsing with size limits
app.use(express.json({ limit: '1mb' }));
app.use(express.urlencoded({ extended: false, limit: '1mb' }));

// 5. Rate limiting
app.use('/api', rateLimitMiddleware(apiLimiter));
app.use('/api/auth', rateLimitMiddleware(authLimiter));

// 6. Request logging
app.use((req, res, next) => {
  const start = performance.now();
  res.on('finish', () => {
    logger.info({
      method: req.method,
      path: req.path,
      status: res.statusCode,
      duration: Math.round(performance.now() - start),
      requestId: req.id,
      ip: req.ip,
      userAgent: req.headers['user-agent'],
    });
  });
  next();
});

// 7. Authentication
app.use('/api', authMiddleware);

// 8. Routes
app.use('/api', router);

// 9. Global error handler (always last)
app.use(globalErrorHandler);
```
