# Deployment Reference Guide

## Table of Contents

1. [Vercel Deployment](#vercel-deployment)
2. [Railway Deployment](#railway-deployment)
3. [Fly.io Deployment](#flyio-deployment)
4. [AWS Deployment (ECS / Lambda)](#aws-deployment-ecs--lambda)
5. [Docker Compose for Production](#docker-compose-for-production)
6. [Environment Variable Management](#environment-variable-management)
7. [Database Deployment](#database-deployment)
8. [Domain and SSL Setup](#domain-and-ssl-setup)
9. [Zero-Downtime Deployment Strategies](#zero-downtime-deployment-strategies)

---

## Vercel Deployment

### Setup and Configuration

```bash
# Install Vercel CLI
npm i -g vercel

# Link project
vercel link

# Deploy preview
vercel

# Deploy production
vercel --prod
```

```json
// vercel.json - Production configuration
{
  "framework": "nextjs",
  "buildCommand": "pnpm build",
  "installCommand": "pnpm install",
  "outputDirectory": ".next",
  "regions": ["iad1", "sfo1"],
  "headers": [
    {
      "source": "/api/(.*)",
      "headers": [
        { "key": "Cache-Control", "value": "no-store, max-age=0" },
        { "key": "X-Content-Type-Options", "value": "nosniff" }
      ]
    },
    {
      "source": "/(.*)",
      "headers": [
        { "key": "X-Frame-Options", "value": "DENY" },
        { "key": "X-Content-Type-Options", "value": "nosniff" },
        { "key": "Referrer-Policy", "value": "strict-origin-when-cross-origin" },
        { "key": "Permissions-Policy", "value": "camera=(), microphone=(), geolocation=()" }
      ]
    }
  ],
  "rewrites": [
    { "source": "/api/:path*", "destination": "https://api.myapp.com/:path*" }
  ],
  "redirects": [
    { "source": "/blog/:slug", "destination": "/posts/:slug", "permanent": true }
  ],
  "crons": [
    { "path": "/api/cron/cleanup", "schedule": "0 2 * * *" }
  ]
}
```

### Environment Variables

```bash
# Add env vars
vercel env add DATABASE_URL production
vercel env add DATABASE_URL preview
vercel env add SESSION_SECRET production

# Pull env vars locally
vercel env pull .env.local

# List all env vars
vercel env ls
```

### Best Practices for Vercel

```
Frameworks:    Next.js, Nuxt, SvelteKit, Astro (first-class support)
Edge Runtime:  Use for low-latency APIs (middleware, auth checks, redirects)
Serverless:    Default for API routes; cold starts ~100-500ms
Static:        Pre-rendered pages served from CDN (fastest)

Limits:
  - Serverless function: 10s (Hobby), 60s (Pro), 900s (Enterprise)
  - Edge function: 30s, 128KB code size
  - Build: 45 min
  - Deploy: 100 per day (Hobby), unlimited (Pro)

Tips:
  - Use ISR/on-demand revalidation to reduce serverless invocations
  - Cache expensive DB queries with unstable_cache or external cache (Redis)
  - Use Vercel Blob/Postgres/KV for integrated storage
  - Set up preview deployments with separate DB for staging
```

---

## Railway Deployment

### Setup

```bash
# Install CLI
npm i -g @railway/cli

# Login and link
railway login
railway link

# Deploy
railway up

# Open dashboard
railway open
```

### railway.toml Configuration

```toml
# railway.toml
[build]
builder = "nixpacks"
buildCommand = "pnpm install && pnpm build"

[deploy]
startCommand = "pnpm start"
healthcheckPath = "/api/health"
healthcheckTimeout = 120
numReplicas = 2
restartPolicyType = "ON_FAILURE"
restartPolicyMaxRetries = 5

[deploy.envs]
NODE_ENV = "production"
PORT = "3000"
```

### Provisioning Services

```bash
# Add PostgreSQL
railway add --plugin postgresql

# Add Redis
railway add --plugin redis

# Environment variables are auto-injected:
#   DATABASE_URL, REDIS_URL, PGHOST, PGPORT, etc.

# Run migrations
railway run -- npx prisma migrate deploy

# Connect to DB locally
railway connect postgresql
```

### Railway with Docker

```dockerfile
# Dockerfile
FROM node:20-alpine AS base
WORKDIR /app

FROM base AS deps
COPY package.json pnpm-lock.yaml ./
RUN corepack enable && pnpm install --frozen-lockfile

FROM base AS build
COPY --from=deps /app/node_modules ./node_modules
COPY . .
RUN corepack enable && pnpm build

FROM base AS runner
ENV NODE_ENV=production
COPY --from=build /app/.next/standalone ./
COPY --from=build /app/.next/static ./.next/static
COPY --from=build /app/public ./public

EXPOSE 3000
CMD ["node", "server.js"]
```

---

## Fly.io Deployment

### Setup

```bash
# Install flyctl
curl -L https://fly.io/install.sh | sh

# Login
fly auth login

# Launch (creates fly.toml + Dockerfile)
fly launch

# Deploy
fly deploy

# Scale
fly scale count 3        # 3 instances
fly scale vm shared-cpu-2x  # Upgrade VM
```

### fly.toml Configuration

```toml
# fly.toml
app = "myapp-production"
primary_region = "iad"

[build]
  dockerfile = "Dockerfile"

[env]
  NODE_ENV = "production"
  PORT = "3000"

[http_service]
  internal_port = 3000
  force_https = true
  auto_stop_machines = true
  auto_start_machines = true
  min_machines_running = 1
  processes = ["app"]

  [http_service.concurrency]
    type = "requests"
    hard_limit = 250
    soft_limit = 200

[[http_service.checks]]
  grace_period = "10s"
  interval = "15s"
  method = "GET"
  path = "/api/health"
  timeout = "5s"

# Multi-region read replicas
[[services]]
  internal_port = 5432
  protocol = "tcp"

[[vm]]
  cpu_kind = "shared"
  cpus = 2
  memory_mb = 512

# Volumes for persistent data
[[mounts]]
  source = "data"
  destination = "/data"
```

### Fly.io Multi-Region

```bash
# Add regions
fly regions add lhr sin  # London, Singapore

# Create read-replica database
fly postgres create --region lhr --name myapp-db-lhr
fly postgres attach myapp-db-lhr --app myapp-production

# Automatic request routing based on region
# Use FLY_REGION env to route writes to primary
```

```typescript
// Automatic primary/replica routing
const isPrimaryRegion = process.env.FLY_REGION === process.env.PRIMARY_REGION;

function getDbUrl(): string {
  if (isPrimaryRegion) {
    return process.env.DATABASE_URL!; // Primary: read + write
  }
  return process.env.DATABASE_REPLICA_URL!; // Replica: read only
}

// For write operations, replay to primary region
app.use((req, res, next) => {
  if (req.method !== 'GET' && !isPrimaryRegion) {
    // Replay write request to primary region
    res.set('fly-replay', `region=${process.env.PRIMARY_REGION}`);
    return res.status(409).send();
  }
  next();
});
```

---

## AWS Deployment (ECS / Lambda)

### ECS Fargate (Containerized)

```yaml
# infrastructure/ecs-task-definition.json
{
  "family": "myapp-api",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "512",
  "memory": "1024",
  "executionRoleArn": "arn:aws:iam::ACCOUNT:role/ecsTaskExecutionRole",
  "taskRoleArn": "arn:aws:iam::ACCOUNT:role/myapp-task-role",
  "containerDefinitions": [
    {
      "name": "api",
      "image": "ACCOUNT.dkr.ecr.us-east-1.amazonaws.com/myapp-api:latest",
      "portMappings": [
        { "containerPort": 3000, "protocol": "tcp" }
      ],
      "environment": [
        { "name": "NODE_ENV", "value": "production" },
        { "name": "PORT", "value": "3000" }
      ],
      "secrets": [
        {
          "name": "DATABASE_URL",
          "valueFrom": "arn:aws:secretsmanager:us-east-1:ACCOUNT:secret:myapp/database-url"
        },
        {
          "name": "SESSION_SECRET",
          "valueFrom": "arn:aws:ssm:us-east-1:ACCOUNT:parameter/myapp/session-secret"
        }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/myapp-api",
          "awslogs-region": "us-east-1",
          "awslogs-stream-prefix": "api"
        }
      },
      "healthCheck": {
        "command": ["CMD-SHELL", "curl -f http://localhost:3000/api/health || exit 1"],
        "interval": 30,
        "timeout": 5,
        "retries": 3,
        "startPeriod": 60
      }
    }
  ]
}
```

```bash
# ECS deployment commands
# Build and push to ECR
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin ACCOUNT.dkr.ecr.us-east-1.amazonaws.com
docker build -t myapp-api .
docker tag myapp-api:latest ACCOUNT.dkr.ecr.us-east-1.amazonaws.com/myapp-api:latest
docker push ACCOUNT.dkr.ecr.us-east-1.amazonaws.com/myapp-api:latest

# Update service (triggers rolling deployment)
aws ecs update-service --cluster myapp-cluster --service myapp-api --force-new-deployment
```

### Lambda + API Gateway (Serverless)

```typescript
// serverless.yml (Serverless Framework)
// or SST (recommended for TypeScript projects)

// sst.config.ts - SST v3 configuration
export default {
  config() {
    return { name: 'myapp', region: 'us-east-1' };
  },
  stacks(app) {
    app.stack(function API({ stack }) {
      // Database
      const rds = new sst.aws.Postgres('Database', {
        scaling: { min: '0.5 ACU', max: '4 ACU' },
      });

      // API
      const api = new sst.aws.ApiGatewayV2('Api');

      api.route('GET /api/health', 'packages/functions/src/health.handler');
      api.route('POST /api/auth/login', 'packages/functions/src/auth/login.handler');
      api.route('GET /api/users/me', 'packages/functions/src/users/me.handler');
      api.route('GET /api/posts', 'packages/functions/src/posts/list.handler');
      api.route('POST /api/posts', 'packages/functions/src/posts/create.handler');

      // Frontend
      const web = new sst.aws.Nextjs('Web', {
        path: 'packages/web',
        environment: {
          NEXT_PUBLIC_API_URL: api.url,
        },
      });

      stack.addOutputs({
        ApiUrl: api.url,
        WebUrl: web.url,
      });
    });
  },
};
```

```typescript
// Lambda handler pattern
// packages/functions/src/posts/list.ts
import { APIGatewayProxyHandlerV2 } from 'aws-lambda';
import { db } from '@myapp/core/db';

export const handler: APIGatewayProxyHandlerV2 = async (event) => {
  try {
    const cursor = event.queryStringParameters?.cursor;
    const limit = Math.min(Number(event.queryStringParameters?.limit) || 20, 100);

    const posts = await db.post.findMany({
      take: limit + 1,
      ...(cursor && { cursor: { id: cursor }, skip: 1 }),
      orderBy: { createdAt: 'desc' },
    });

    const hasMore = posts.length > limit;
    const data = hasMore ? posts.slice(0, limit) : posts;

    return {
      statusCode: 200,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        data,
        pageInfo: {
          hasNextPage: hasMore,
          endCursor: data.at(-1)?.id ?? null,
        },
      }),
    };
  } catch (err) {
    console.error('Error listing posts:', err);
    return {
      statusCode: 500,
      body: JSON.stringify({ error: { message: 'Internal server error' } }),
    };
  }
};
```

---

## Docker Compose for Production

### Full-Stack Docker Compose

```yaml
# docker-compose.production.yml
version: "3.9"

services:
  app:
    build:
      context: .
      dockerfile: Dockerfile
      target: runner
    ports:
      - "${PORT:-3000}:3000"
    environment:
      - NODE_ENV=production
      - DATABASE_URL=postgresql://${DB_USER}:${DB_PASSWORD}@postgres:5432/${DB_NAME}
      - REDIS_URL=redis://redis:6379
      - SESSION_SECRET=${SESSION_SECRET}
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    restart: unless-stopped
    deploy:
      replicas: 2
      resources:
        limits:
          cpus: "1.0"
          memory: 512M
        reservations:
          cpus: "0.25"
          memory: 128M
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:3000/api/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  postgres:
    image: postgres:16-alpine
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./init-scripts:/docker-entrypoint-initdb.d
    environment:
      POSTGRES_DB: ${DB_NAME}
      POSTGRES_USER: ${DB_USER}
      POSTGRES_PASSWORD: ${DB_PASSWORD}
    ports:
      - "127.0.0.1:5432:5432"
    restart: unless-stopped
    deploy:
      resources:
        limits:
          cpus: "1.0"
          memory: 1G
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${DB_USER} -d ${DB_NAME}"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s
    shm_size: 256mb

  redis:
    image: redis:7-alpine
    command: redis-server --requirepass ${REDIS_PASSWORD} --maxmemory 256mb --maxmemory-policy allkeys-lru
    volumes:
      - redis_data:/data
    ports:
      - "127.0.0.1:6379:6379"
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "redis-cli", "-a", "${REDIS_PASSWORD}", "ping"]
      interval: 10s
      timeout: 5s
      retries: 3

  nginx:
    image: nginx:alpine
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./nginx/ssl:/etc/nginx/ssl:ro
      - certbot_certs:/etc/letsencrypt:ro
    depends_on:
      - app
    restart: unless-stopped

  # Database backup
  backup:
    image: postgres:16-alpine
    volumes:
      - ./backups:/backups
    environment:
      PGHOST: postgres
      PGUSER: ${DB_USER}
      PGPASSWORD: ${DB_PASSWORD}
      PGDATABASE: ${DB_NAME}
    entrypoint: |
      sh -c 'while true; do
        pg_dump --format=custom --compress=9 > /backups/backup-$$(date +%Y%m%d-%H%M%S).dump
        find /backups -name "*.dump" -mtime +7 -delete
        sleep 86400
      done'
    depends_on:
      postgres:
        condition: service_healthy
    restart: unless-stopped

volumes:
  postgres_data:
  redis_data:
  certbot_certs:
```

### Nginx Configuration for Production

```nginx
# nginx/nginx.conf
worker_processes auto;
worker_rlimit_nofile 65535;

events {
    worker_connections 4096;
    multi_accept on;
}

http {
    # Basic settings
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    client_max_body_size 20M;

    # Gzip
    gzip on;
    gzip_vary on;
    gzip_types text/plain application/json application/javascript text/css application/xml text/xml;
    gzip_min_length 1000;

    # Rate limiting
    limit_req_zone $binary_remote_addr zone=api:10m rate=30r/s;
    limit_req_zone $binary_remote_addr zone=auth:10m rate=5r/s;

    # Upstream (load balance across app replicas)
    upstream app {
        least_conn;
        server app:3000;
    }

    server {
        listen 80;
        server_name myapp.com www.myapp.com;
        return 301 https://$server_name$request_uri;
    }

    server {
        listen 443 ssl http2;
        server_name myapp.com;

        ssl_certificate /etc/letsencrypt/live/myapp.com/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/myapp.com/privkey.pem;
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers HIGH:!aNULL:!MD5;

        # Security headers
        add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
        add_header X-Frame-Options "DENY" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header Referrer-Policy "strict-origin-when-cross-origin" always;

        # API routes
        location /api/ {
            limit_req zone=api burst=50 nodelay;
            proxy_pass http://app;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header X-Request-ID $request_id;
        }

        # Auth routes (stricter rate limit)
        location /api/auth/ {
            limit_req zone=auth burst=10 nodelay;
            proxy_pass http://app;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }

        # WebSocket upgrade
        location /ws {
            proxy_pass http://app;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_set_header Host $host;
            proxy_read_timeout 86400;
        }

        # Static assets with long cache
        location /_next/static/ {
            proxy_pass http://app;
            add_header Cache-Control "public, max-age=31536000, immutable";
        }

        # Default
        location / {
            proxy_pass http://app;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }
    }
}
```

---

## Environment Variable Management

### .env.example Template

```bash
# .env.example - Document every required variable
# Copy to .env and fill in actual values
# NEVER commit .env files to version control

# ── App ──────────────────────────────────────
NODE_ENV=development
PORT=3000
APP_URL=http://localhost:3000

# ── Database ─────────────────────────────────
DATABASE_URL=postgresql://user:password@localhost:5432/myapp_dev
# DATABASE_REPLICA_URL=              # Optional: read replica

# ── Redis ────────────────────────────────────
REDIS_URL=redis://localhost:6379

# ── Auth ─────────────────────────────────────
SESSION_SECRET=generate-a-random-64-char-string
JWT_ACCESS_SECRET=generate-another-random-string
JWT_REFRESH_SECRET=generate-yet-another-random-string
# GOOGLE_CLIENT_ID=
# GOOGLE_CLIENT_SECRET=

# ── Storage ──────────────────────────────────
# S3_BUCKET=myapp-uploads
# AWS_REGION=us-east-1
# AWS_ACCESS_KEY_ID=
# AWS_SECRET_ACCESS_KEY=
# CDN_URL=https://cdn.myapp.com

# ── Email ────────────────────────────────────
# SMTP_HOST=smtp.resend.com
# SMTP_PORT=465
# SMTP_USER=resend
# SMTP_PASS=re_xxx
# FROM_EMAIL=noreply@myapp.com

# ── Monitoring ───────────────────────────────
# SENTRY_DSN=
# LOG_LEVEL=info
```

### Runtime Validation

```typescript
// lib/env.ts - Validate environment at startup
import { z } from 'zod';

const envSchema = z.object({
  NODE_ENV: z.enum(['development', 'production', 'test']).default('development'),
  PORT: z.coerce.number().default(3000),
  APP_URL: z.string().url(),

  DATABASE_URL: z.string().url().startsWith('postgresql://'),
  REDIS_URL: z.string().url().startsWith('redis://'),

  SESSION_SECRET: z.string().min(32),
  JWT_ACCESS_SECRET: z.string().min(32),
  JWT_REFRESH_SECRET: z.string().min(32),

  // Optional
  SENTRY_DSN: z.string().url().optional(),
  LOG_LEVEL: z.enum(['debug', 'info', 'warn', 'error']).default('info'),
  S3_BUCKET: z.string().optional(),
  CDN_URL: z.string().url().optional(),
});

export type Env = z.infer<typeof envSchema>;

function validateEnv(): Env {
  const result = envSchema.safeParse(process.env);

  if (!result.success) {
    console.error('Invalid environment variables:');
    for (const issue of result.error.issues) {
      console.error(`  ${issue.path.join('.')}: ${issue.message}`);
    }
    process.exit(1);
  }

  return result.data;
}

export const env = validateEnv();
```

### Secret Management by Platform

```
Platform       | Built-In Secrets          | External Integration
---------------|---------------------------|----------------------------
Vercel         | vercel env (encrypted)    | 1Password, Doppler, Vault
Railway        | Service variables (UI)    | Shared variables
Fly.io         | fly secrets set           | Vault
AWS ECS        | Secrets Manager + SSM     | AWS Secrets Manager (native)
Docker Compose | .env file + docker secrets| Vault, AWS SM via sidecar
Kubernetes     | k8s Secrets + sealed      | External Secrets Operator

Commands:
  vercel env add SECRET_NAME production
  railway variables set SECRET_NAME=value
  fly secrets set SECRET_NAME=value
  aws ssm put-parameter --name /myapp/secret --value xxx --type SecureString
```

---

## Database Deployment

### Managed vs Self-Hosted Decision

```
                  | Managed (Neon/Supabase/PlanetScale) | Self-Hosted (Docker/VM)
------------------|-------------------------------------|------------------------
Setup Time        | Minutes                             | Hours to days
Maintenance       | Zero (patches, backups handled)     | You handle everything
Cost (small)      | Free tier / $25-50/mo               | $5-20/mo (VPS)
Cost (large)      | $100-1000+/mo                       | $50-200/mo (but your time)
Scaling           | Automatic / toggle                  | Manual (replicas, sharding)
Backups           | Automatic PITR                      | You configure pg_dump/cron
High Availability | Built-in failover                   | You set up replication
Compliance        | Depends on provider (SOC2, etc.)    | Full control
Vendor Lock-in    | Moderate                            | None

Recommendation:
  - Solo / Startup / MVP → Managed (Neon, Supabase, PlanetScale)
  - Cost-conscious + DevOps skill → Self-hosted on VPS
  - Enterprise / Compliance → Managed (AWS RDS, GCP Cloud SQL)
  - Edge / Global → Turso (SQLite), PlanetScale, CockroachDB
```

### Managed Providers Quick Setup

```bash
# ── Neon (Serverless PostgreSQL) ─────────────
# Create project at console.neon.tech
# Connection string provided automatically
DATABASE_URL="postgresql://user:pass@ep-cool-name-123.us-east-2.aws.neon.tech/mydb?sslmode=require"

# Branch for preview deployments
neonctl branches create --name preview-pr-42
# Branching creates instant copy of production data

# ── Supabase ─────────────────────────────────
# Create project at app.supabase.com
npx supabase init
npx supabase db push         # Push migrations
npx supabase db pull         # Pull remote schema changes

# ── PlanetScale (MySQL) ─────────────────────
pscale auth login
pscale database create myapp --region us-east
pscale branch create myapp dev
pscale connect myapp dev --port 3309
# DATABASE_URL="mysql://root@127.0.0.1:3309/myapp"
pscale deploy-request create myapp dev  # Create deploy request (like PR for schema)
```

### Database Migration Strategy

```bash
# ── Prisma ───────────────────────────────────
# Development: generate and apply migration
npx prisma migrate dev --name add_posts_table

# Production: apply pending migrations (NO prompts, NO generation)
npx prisma migrate deploy

# CI/CD pipeline example
# 1. Run migrate deploy BEFORE deploying new code
# 2. Ensure migrations are backward-compatible

# ── Drizzle ──────────────────────────────────
npx drizzle-kit generate    # Generate SQL from schema changes
npx drizzle-kit push        # Push to dev DB (no migration files)
npx drizzle-kit migrate     # Apply migrations to production
```

```typescript
// Safe migration strategy for zero-downtime
// RULE: Never make breaking changes in a single deploy

// BAD: Rename column in one step (breaks running code)
// ALTER TABLE users RENAME COLUMN name TO full_name;

// GOOD: Three-step migration
// Deploy 1: Add new column
//   ALTER TABLE users ADD COLUMN full_name VARCHAR(200);
//   UPDATE users SET full_name = name;
//   -- Code reads from both, writes to both

// Deploy 2: Switch reads to new column
//   -- Code reads from full_name, writes to both

// Deploy 3: Drop old column (after all instances updated)
//   ALTER TABLE users DROP COLUMN name;
```

---

## Domain and SSL Setup

### DNS Configuration

```
Record Type | Name          | Value                           | Purpose
------------|---------------|---------------------------------|-------------------------
A           | @             | 76.76.21.21                     | Root domain (Vercel)
CNAME       | www           | cname.vercel-dns.com            | www subdomain
CNAME       | api           | myapp-api.fly.dev               | API subdomain
CNAME       | _acme-chall.. | dcv.digicert.com                | SSL verification
MX          | @             | mx1.emailprovider.com           | Email
TXT         | @             | v=spf1 include:_spf.google...   | SPF (email auth)
TXT         | _dmarc        | v=DMARC1; p=reject; ...         | DMARC (email auth)
```

### SSL Certificate Setup

```bash
# ── Let's Encrypt (Certbot) ─────────────────
# Install
sudo apt install certbot python3-certbot-nginx

# Obtain certificate
sudo certbot --nginx -d myapp.com -d www.myapp.com

# Auto-renew (crontab)
0 0 1 * * certbot renew --quiet --post-hook "systemctl reload nginx"

# ── Docker + Certbot ─────────────────────────
# Initial certificate
docker run --rm -v certbot_certs:/etc/letsencrypt \
  -v certbot_www:/var/www/certbot \
  certbot/certbot certonly --webroot \
  -w /var/www/certbot -d myapp.com -d www.myapp.com

# Renewal cron (add to docker-compose)
certbot:
  image: certbot/certbot
  volumes:
    - certbot_certs:/etc/letsencrypt
    - certbot_www:/var/www/certbot
  entrypoint: "/bin/sh -c 'while :; do certbot renew --quiet; sleep 12h; done'"
```

### Platform-Specific SSL

```
Platform     | SSL Setup
-------------|----------------------------------------------------------
Vercel       | Automatic (add domain in dashboard, DNS points to Vercel)
Railway      | Automatic (custom domain in settings)
Fly.io       | fly certs add myapp.com (auto Let's Encrypt)
AWS (ALB)    | AWS Certificate Manager (ACM) → attach to load balancer
Cloudflare   | Automatic with proxy enabled (orange cloud)
```

---

## Zero-Downtime Deployment Strategies

### Rolling Deployment

```
How it works:
  1. Have 3 instances running v1
  2. Start replacing one at a time: v1, v1, v1 → v2, v1, v1 → v2, v2, v1 → v2, v2, v2
  3. Health check each new instance before proceeding
  4. Rollback if health check fails

Pros: Simple, resource-efficient (no extra capacity needed)
Cons: Brief period with mixed versions running simultaneously

Best for: Stateless apps, backward-compatible changes
```

```yaml
# AWS ECS rolling update
{
  "deploymentConfiguration": {
    "maximumPercent": 200,
    "minimumHealthyPercent": 100,
    "deploymentCircuitBreaker": {
      "enable": true,
      "rollback": true
    }
  }
}
```

### Blue-Green Deployment

```
How it works:
  1. Blue (current) is serving traffic
  2. Deploy Green (new version) alongside Blue
  3. Run smoke tests on Green
  4. Switch load balancer / DNS from Blue → Green
  5. Keep Blue running for fast rollback
  6. Tear down Blue after confidence period

Pros: Instant rollback, no mixed versions
Cons: Requires double resources during deploy

Best for: Critical applications, major version changes
```

```bash
# Fly.io blue-green with machines
# Deploy new version to canary
fly deploy --strategy=bluegreen

# AWS: use weighted target groups
aws elbv2 modify-rule --rule-arn $RULE_ARN --actions \
  Type=forward,ForwardConfig='{
    "TargetGroups": [
      {"TargetGroupArn": "'$BLUE_TG'", "Weight": 0},
      {"TargetGroupArn": "'$GREEN_TG'", "Weight": 100}
    ]
  }'
```

### Canary Deployment

```
How it works:
  1. Deploy new version to small % of traffic (5%)
  2. Monitor error rates, latency, business metrics
  3. Gradually increase: 5% → 10% → 25% → 50% → 100%
  4. Automatic rollback if error threshold exceeded

Pros: Lowest risk, real user validation
Cons: Complex setup, mixed versions in production

Best for: High-traffic apps, risky changes
```

```yaml
# Kubernetes canary with Argo Rollouts
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: myapp
spec:
  strategy:
    canary:
      steps:
        - setWeight: 5
        - pause: { duration: 5m }
        - setWeight: 20
        - pause: { duration: 5m }
        - setWeight: 50
        - pause: { duration: 10m }
        - setWeight: 100
      analysis:
        templates:
          - templateName: success-rate
        startingStep: 1
        args:
          - name: service-name
            value: myapp

---
apiVersion: argoproj.io/v1alpha1
kind: AnalysisTemplate
metadata:
  name: success-rate
spec:
  metrics:
    - name: success-rate
      interval: 60s
      successCondition: result[0] > 0.99
      provider:
        prometheus:
          address: http://prometheus:9090
          query: |
            sum(rate(http_requests_total{service="{{args.service-name}}",status=~"2.."}[2m]))
            /
            sum(rate(http_requests_total{service="{{args.service-name}}"}[2m]))
```

### Deployment Checklist

```
Pre-Deploy:
  [ ] All tests passing (unit, integration, E2E)
  [ ] Database migrations are backward-compatible
  [ ] Environment variables configured for target environment
  [ ] Feature flags set for gradual rollout
  [ ] Rollback plan documented and tested
  [ ] On-call engineer notified

Deploy:
  [ ] Run database migrations first
  [ ] Deploy backend (rolling/blue-green/canary)
  [ ] Deploy frontend (CDN invalidation)
  [ ] Verify health check endpoints
  [ ] Run smoke tests against production

Post-Deploy:
  [ ] Monitor error rates (Sentry) for 15-30 min
  [ ] Monitor latency (P50, P95, P99)
  [ ] Check business metrics (signups, orders, etc.)
  [ ] Verify log aggregation working
  [ ] Update deployment log / changelog
```
