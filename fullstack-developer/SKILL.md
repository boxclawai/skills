---
name: fullstack-developer
version: "1.0.0"
description: "Full-stack development expert: end-to-end application building spanning frontend (React/Next.js/Vue/Nuxt) and backend (Node.js/Python/Go), database design, API integration, authentication, deployment, and rapid prototyping. Use when: (1) building complete web applications from scratch, (2) connecting frontend to backend APIs, (3) implementing end-to-end features (UI + API + DB), (4) rapid prototyping with full-stack frameworks, (5) debugging cross-layer issues (client-server-database), (6) choosing tech stack for new projects. NOT for: deep infrastructure, ML pipelines, or mobile-native development."
tags: [nextjs, nuxt, react, vue, prisma, drizzle, monorepo, deployment, authentication, fullstack]
author: "boxclaw"
references:
  - references/fullstack-patterns.md
  - references/deployment.md
metadata:
  boxclaw:
    emoji: "🔮"
    category: "programming-role"
---

# Full-Stack Developer

Expert guidance for building complete web applications end-to-end.

## Core Competencies

### 1. Tech Stack Selection

```
Rapid MVP / Solo Developer:
  Next.js + Prisma + PostgreSQL + Vercel
  Nuxt.js + Drizzle + SQLite + Cloudflare

Team / Production:
  React + Node.js/Express + PostgreSQL + AWS/GCP
  Vue + Python/FastAPI + PostgreSQL + Docker

High Performance:
  SvelteKit + Go/Rust backend + PostgreSQL + bare metal
  Astro (static) + Edge functions + D1/Turso
```

### 2. Project Structure (Monorepo)

```
project/
├── apps/
│   ├── web/              # Frontend (Next.js/Nuxt)
│   │   ├── src/
│   │   │   ├── components/  # UI components
│   │   │   ├── pages/       # Route pages
│   │   │   ├── hooks/       # Custom hooks
│   │   │   ├── lib/         # Utilities
│   │   │   └── styles/      # Global styles
│   │   └── package.json
│   └── api/              # Backend
│       ├── src/
│       │   ├── routes/      # API endpoints
│       │   ├── services/    # Business logic
│       │   ├── models/      # Data models
│       │   ├── middleware/   # Auth, validation, etc.
│       │   └── lib/         # Shared utilities
│       └── package.json
├── packages/
│   ├── shared/           # Shared types, constants
│   └── ui/               # Shared UI components
├── docker-compose.yml
└── turbo.json / pnpm-workspace.yaml
```

### 3. End-to-End Feature Workflow

```
1. Database    → Design schema, write migration
2. API         → Create endpoint, validate input, write service
3. Types       → Share types between frontend and backend
4. Frontend    → Build UI, connect to API, handle loading/error
5. Auth guard  → Protect route + endpoint
6. Test        → Unit (service) + Integration (API) + E2E (flow)
7. Deploy      → Migration → Backend → Frontend
```

#### Example: User Registration Feature

```
DB:   CREATE TABLE users (id, email, password_hash, created_at)
API:  POST /api/auth/register → validate → hash password → insert → return JWT
Type: interface User { id: string; email: string; createdAt: Date }
UI:   RegisterForm → call API → redirect to dashboard
Auth: middleware checks JWT → attaches user to request
Test: register flow E2E → verify DB record → verify JWT works
```

### 4. Data Flow Patterns

```
Server-Side Rendering (SSR):
  Browser → Server → DB → Render HTML → Browser
  Use: SEO, first load performance

Client-Side Rendering (CSR):
  Browser → Static HTML → JS → API call → Render
  Use: Dashboards, authenticated apps

Static Site Generation (SSG):
  Build time: Fetch data → Generate HTML
  Use: Blogs, marketing, docs

Incremental Static Regeneration (ISR):
  Serve static → Revalidate in background on interval
  Use: E-commerce, frequently updated content

Server Components (RSC):
  Server renders component → Streams to client
  Use: Data-heavy pages, reduce client JS
```

### 5. Authentication Flow (Full-Stack)

```
Registration:
  Client → POST /auth/register { email, password }
  Server → validate → argon2.hash(password) → insert DB
  Server → generate JWT pair → set httpOnly cookie
  Server → return { user } (no token in body)

Login:
  Client → POST /auth/login { email, password }
  Server → find user → argon2.verify → generate JWT pair
  Server → set httpOnly cookie → return { user }

Protected Route:
  Client → GET /api/me (cookie sent automatically)
  Server → middleware extracts JWT → verify → attach user
  Server → proceed to handler with req.user

Token Refresh:
  Client → POST /auth/refresh (refresh cookie)
  Server → verify refresh token → check DB → rotate pair
```

### 6. Deployment Checklist

```
Pre-deploy:
  [ ] Environment variables configured
  [ ] Database migrations tested
  [ ] CORS origins whitelisted
  [ ] HTTPS enforced
  [ ] Error monitoring configured (Sentry)
  [ ] Log aggregation set up
  [ ] Health check endpoint (/api/health)

Deploy order:
  1. Run database migrations
  2. Deploy backend (blue-green or rolling)
  3. Deploy frontend (CDN invalidation)
  4. Verify health checks
  5. Monitor error rates for 15min
```

## Quick Commands

```bash
# Scaffold (Next.js full-stack)
npx create-next-app@latest myapp --typescript --tailwind --app
cd myapp && npm i prisma @prisma/client && npx prisma init

# Scaffold (Nuxt full-stack)
npx nuxi@latest init myapp && cd myapp
npm i drizzle-orm better-sqlite3

# Dev (monorepo)
pnpm dev --filter web --filter api

# DB
npx prisma migrate dev --name add_users
npx prisma studio  # Visual DB browser
```

## References

- **Full-stack patterns**: See [references/fullstack-patterns.md](references/fullstack-patterns.md)
- **Deployment guides**: See [references/deployment.md](references/deployment.md)
