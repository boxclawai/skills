---
name: backend-developer
version: "1.0.0"
description: "Backend development expert: API design (REST/GraphQL/gRPC), database integration (SQL/NoSQL), authentication/authorization (JWT/OAuth/RBAC), server architecture (Node.js/Python/Go/Java/Rust), caching (Redis), message queues (RabbitMQ/Kafka), and microservices patterns. Use when: (1) designing or building APIs, (2) implementing auth flows, (3) writing database queries or migrations, (4) setting up caching or queue systems, (5) structuring backend services, (6) reviewing server-side code for security or performance. NOT for: frontend UI, CSS styling, or infrastructure provisioning."
tags: [api, rest, graphql, grpc, nodejs, python, go, authentication, database, redis, microservices]
author: "boxclaw"
references:
  - references/database-patterns.md
  - references/api-security.md
metadata:
  boxclaw:
    emoji: "🔧"
    category: "programming-role"
---

# Backend Developer

Expert guidance for building robust, scalable, secure server-side systems.

## Core Competencies

### 1. API Design

#### REST API Standards

```
Resource naming: plural nouns, kebab-case
  GET    /api/v1/users          → List
  GET    /api/v1/users/:id      → Read
  POST   /api/v1/users          → Create
  PUT    /api/v1/users/:id      → Full update
  PATCH  /api/v1/users/:id      → Partial update
  DELETE /api/v1/users/:id      → Delete

Nested resources: /api/v1/users/:id/orders
Filtering: ?status=active&sort=-created_at&page=2&limit=20
Versioning: URL path (/v1/) or Accept header
```

#### Response Format

```json
{
  "data": { "id": "123", "name": "..." },
  "meta": { "page": 1, "total": 42 },
  "errors": [
    { "code": "VALIDATION_ERROR", "field": "email", "message": "Invalid format" }
  ]
}
```

#### HTTP Status Codes

```
200 OK            → Successful read/update
201 Created       → Successful creation (+ Location header)
204 No Content    → Successful deletion
400 Bad Request   → Validation error
401 Unauthorized  → Missing/invalid auth
403 Forbidden     → Insufficient permissions
404 Not Found     → Resource doesn't exist
409 Conflict      → Duplicate/state conflict
422 Unprocessable → Semantic validation failure
429 Too Many      → Rate limit exceeded
500 Internal      → Server error (never expose internals)
```

### 2. Authentication & Authorization

```
Auth Flow Decision:
  Session-based → Traditional web apps, server-rendered
  JWT           → SPAs, mobile apps, microservices
  OAuth 2.0     → Third-party integrations
  API Keys      → Machine-to-machine, simple auth

RBAC Pattern:
  User → Role(s) → Permission(s) → Resource + Action

Token Strategy:
  Access token:  Short-lived (15min), stateless JWT
  Refresh token: Long-lived (7d), stored in DB, rotatable
  Never store tokens in localStorage (XSS vulnerable)
  Use httpOnly secure cookies for web apps
```

### 3. Database Strategy

#### SQL vs NoSQL Decision

```
SQL (PostgreSQL/MySQL):
  - Complex queries, joins, aggregations
  - ACID transactions required
  - Structured, relational data
  - Strong consistency needed

NoSQL (MongoDB/DynamoDB/Redis):
  - Flexible schema, rapid iteration
  - High write throughput
  - Document or key-value access patterns
  - Eventual consistency acceptable
```

#### Migration Best Practices

```
- Always reversible (up + down)
- Never modify production data in migrations
- Add columns as nullable first, backfill, then add NOT NULL
- Index creation: CREATE INDEX CONCURRENTLY (PostgreSQL)
- Test migrations against production-sized data
```

### 4. Caching Strategy

```
Cache Layers:
  L1: In-process (LRU Map)         → <1ms, per-instance
  L2: Distributed (Redis/Memcached) → 1-5ms, shared
  L3: CDN (Cloudflare/CloudFront)   → Edge, static assets

Patterns:
  Cache-Aside:  App checks cache → miss → DB → write cache
  Write-Through: App writes DB + cache atomically
  Write-Behind:  App writes cache → async flush to DB

Invalidation:
  TTL-based:    Simple, eventual consistency
  Event-based:  Publish invalidation on DB write
  Tag-based:    Group related keys, invalidate by tag
```

### 5. Error Handling

```javascript
// Structured error hierarchy
class AppError extends Error {
  constructor(message, code, statusCode, details) {
    super(message);
    this.code = code;           // Machine-readable: "USER_NOT_FOUND"
    this.statusCode = statusCode; // HTTP status
    this.details = details;     // Additional context
    this.isOperational = true;  // Expected error (vs programming bug)
  }
}

// Global error handler (Express example)
app.use((err, req, res, next) => {
  if (err.isOperational) {
    return res.status(err.statusCode).json({
      error: { code: err.code, message: err.message }
    });
  }
  // Programming error: log full stack, return generic 500
  logger.error(err);
  res.status(500).json({ error: { code: "INTERNAL_ERROR" } });
});
```

### 6. Security Checklist

```
Input:    Validate + sanitize all input (zod/joi/class-validator)
SQL:      Parameterized queries only, never string concatenation
Auth:     bcrypt/argon2 for passwords, constant-time comparison
Headers:  Helmet.js (X-Frame-Options, CSP, HSTS, etc.)
CORS:     Whitelist origins, never wildcard in production
Rate:     Rate limit by IP + user, sliding window algorithm
Logging:  Never log passwords, tokens, or PII
Secrets:  Env vars or vault, never in code/config files
HTTPS:    Always, redirect HTTP → HTTPS
Deps:     npm audit / snyk regularly
```

## Quick Commands

```bash
# Dev server
npm run dev                          # Start with hot reload
npm run dev -- --inspect             # Start with debugger

# Database
npx prisma migrate dev               # Run migrations (dev)
npx prisma studio                    # Visual DB browser
npx drizzle-kit push                 # Push schema changes

# Testing
npx vitest run                       # Unit tests
npx vitest run --coverage            # With coverage report
npm run test:e2e                     # Integration/E2E tests

# Code quality
npx eslint . --fix                   # Lint + autofix
npx tsc --noEmit                     # Type check
npm audit --audit-level=high         # Dependency audit
```

## Architecture Patterns

```
Monolith     → Start here. Split when pain exceeds cost.
Modular Mono → Domain modules with clear boundaries + interfaces
Microservice → When teams/domains need independent deployment
Serverless   → Event-driven, low-traffic, or bursty workloads

Communication:
  Sync:  REST / gRPC (request-response)
  Async: Message queue (fire-and-forget, eventual consistency)
  Event: Event bus / event sourcing (audit trail, replay)
```

## References

- **Database patterns**: See [references/database-patterns.md](references/database-patterns.md)
- **API security**: See [references/api-security.md](references/api-security.md)
