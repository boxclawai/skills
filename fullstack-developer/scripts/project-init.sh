#!/usr/bin/env bash
# project-init.sh - Scaffold a full-stack project with opinionated defaults
# Usage: ./project-init.sh <project-name> [--stack next|nuxt|sveltekit]
#
# Creates:
#   - Monorepo project structure (pnpm workspaces)
#   - Frontend app with chosen framework
#   - Backend API directory with Express boilerplate
#   - Shared types package
#   - docker-compose.yml (PostgreSQL + Redis)
#   - .env.example with all required variables
#   - Basic authentication setup (JWT)
#   - ESLint + Prettier + TypeScript config
#   - GitHub Actions CI workflow

set -euo pipefail

# ── Color output ─────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ── Parse arguments ──────────────────────────────────────────────────────────
PROJECT_NAME="${1:?Usage: $0 <project-name> [--stack next|nuxt|sveltekit]}"
STACK="next"

shift
while [[ $# -gt 0 ]]; do
  case "$1" in
    --stack)
      STACK="${2:?--stack requires a value (next|nuxt|sveltekit)}"
      shift 2
      ;;
    --help|-h)
      echo "Usage: $0 <project-name> [--stack next|nuxt|sveltekit]"
      echo ""
      echo "Options:"
      echo "  --stack    Frontend framework (default: next)"
      echo "             next      - Next.js 14+ (App Router, React)"
      echo "             nuxt      - Nuxt 3 (Vue 3)"
      echo "             sveltekit - SvelteKit (Svelte)"
      echo ""
      echo "Creates a full-stack monorepo with:"
      echo "  - Frontend app with chosen framework"
      echo "  - Backend API (Express + TypeScript)"
      echo "  - Shared types package"
      echo "  - Docker Compose (PostgreSQL + Redis)"
      echo "  - Authentication boilerplate (JWT)"
      echo "  - CI/CD workflow (GitHub Actions)"
      exit 0
      ;;
    *)
      error "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Validate stack choice
case "$STACK" in
  next|nuxt|sveltekit) ;;
  *) error "Invalid stack: $STACK. Choose from: next, nuxt, sveltekit"; exit 1 ;;
esac

# ── Validate prerequisites ───────────────────────────────────────────────────
check_command() {
  if ! command -v "$1" &>/dev/null; then
    error "$1 is required but not installed."
    echo "  Install: $2"
    exit 1
  fi
}

check_command "node" "https://nodejs.org"
check_command "pnpm" "npm install -g pnpm"
check_command "git" "https://git-scm.com"

NODE_VERSION=$(node -v | cut -d'v' -f2 | cut -d'.' -f1)
if [[ "$NODE_VERSION" -lt 18 ]]; then
  error "Node.js 18+ required (found v${NODE_VERSION})"
  exit 1
fi

# ── Validate project name ───────────────────────────────────────────────────
if [[ ! "$PROJECT_NAME" =~ ^[a-z][a-z0-9-]*$ ]]; then
  error "Project name must be lowercase, start with a letter, and contain only [a-z0-9-]"
  exit 1
fi

if [[ -d "$PROJECT_NAME" ]]; then
  error "Directory '$PROJECT_NAME' already exists"
  exit 1
fi

# ── Create project structure ─────────────────────────────────────────────────
info "Creating project: $PROJECT_NAME (stack: $STACK)"
mkdir -p "$PROJECT_NAME"
cd "$PROJECT_NAME"

# ── Root config files ────────────────────────────────────────────────────────
info "Setting up monorepo root..."

cat > package.json << EOF
{
  "name": "${PROJECT_NAME}",
  "private": true,
  "scripts": {
    "dev": "turbo dev",
    "build": "turbo build",
    "lint": "turbo lint",
    "test": "turbo test",
    "typecheck": "turbo typecheck",
    "db:migrate": "cd apps/api && npx prisma migrate dev",
    "db:push": "cd apps/api && npx prisma db push",
    "db:studio": "cd apps/api && npx prisma studio",
    "docker:up": "docker compose up -d",
    "docker:down": "docker compose down",
    "clean": "turbo clean && rm -rf node_modules"
  },
  "devDependencies": {
    "turbo": "^2",
    "typescript": "^5",
    "prettier": "^3",
    "@typescript-eslint/eslint-plugin": "^7",
    "@typescript-eslint/parser": "^7"
  },
  "packageManager": "pnpm@9.0.0",
  "engines": {
    "node": ">=18"
  }
}
EOF

cat > pnpm-workspace.yaml << 'EOF'
packages:
  - "apps/*"
  - "packages/*"
EOF

cat > turbo.json << 'EOF'
{
  "$schema": "https://turbo.build/schema.json",
  "globalDependencies": ["**/.env.*local"],
  "tasks": {
    "build": {
      "dependsOn": ["^build"],
      "outputs": [".next/**", "!.next/cache/**", "dist/**"]
    },
    "dev": {
      "cache": false,
      "persistent": true
    },
    "lint": {
      "dependsOn": ["^build"]
    },
    "typecheck": {
      "dependsOn": ["^build"]
    },
    "test": {
      "cache": false
    },
    "clean": {
      "cache": false
    }
  }
}
EOF

cat > tsconfig.base.json << 'EOF'
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "bundler",
    "lib": ["ES2022"],
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "resolveJsonModule": true,
    "isolatedModules": true,
    "incremental": true,
    "declaration": true,
    "declarationMap": true,
    "sourceMap": true
  },
  "exclude": ["node_modules"]
}
EOF

cat > .prettierrc << 'EOF'
{
  "semi": true,
  "singleQuote": true,
  "trailingComma": "all",
  "printWidth": 100,
  "tabWidth": 2
}
EOF

cat > .prettierignore << 'EOF'
node_modules
.next
.nuxt
.svelte-kit
dist
build
coverage
*.lock
EOF

cat > .gitignore << 'EOF'
# Dependencies
node_modules/

# Build
.next/
.nuxt/
.svelte-kit/
dist/
build/
.turbo/

# Environment
.env
.env.local
.env.*.local

# IDE
.vscode/settings.json
.idea/

# OS
.DS_Store
Thumbs.db

# Logs
*.log
npm-debug.log*

# Testing
coverage/

# Database
*.db
*.sqlite
prisma/migrations/**/migration_lock.toml
EOF

# ── .env.example ─────────────────────────────────────────────────────────────
cat > .env.example << 'EOF'
# ── App ──────────────────────────────────────
NODE_ENV=development
PORT=4000
APP_URL=http://localhost:3000
API_URL=http://localhost:4000

# ── Database (Docker Compose) ────────────────
DATABASE_URL=postgresql://postgres:postgres@localhost:5432/myapp_dev
DB_NAME=myapp_dev
DB_USER=postgres
DB_PASSWORD=postgres

# ── Redis ────────────────────────────────────
REDIS_URL=redis://localhost:6379
REDIS_PASSWORD=redis_dev_password

# ── Auth (JWT) ───────────────────────────────
JWT_ACCESS_SECRET=dev-access-secret-change-in-production-min-32-chars
JWT_REFRESH_SECRET=dev-refresh-secret-change-in-production-min-32-chars

# ── Frontend (public) ───────────────────────
NEXT_PUBLIC_API_URL=http://localhost:4000
# NUXT_PUBLIC_API_URL=http://localhost:4000

# ── Optional ─────────────────────────────────
# GOOGLE_CLIENT_ID=
# GOOGLE_CLIENT_SECRET=
# S3_BUCKET=
# AWS_REGION=us-east-1
# SENTRY_DSN=
EOF

cp .env.example .env

# ── Docker Compose ───────────────────────────────────────────────────────────
info "Creating Docker Compose configuration..."

cat > docker-compose.yml << 'EOF'
version: "3.9"

services:
  postgres:
    image: postgres:16-alpine
    ports:
      - "5432:5432"
    environment:
      POSTGRES_DB: ${DB_NAME:-myapp_dev}
      POSTGRES_USER: ${DB_USER:-postgres}
      POSTGRES_PASSWORD: ${DB_PASSWORD:-postgres}
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${DB_USER:-postgres}"]
      interval: 10s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    command: redis-server --requirepass ${REDIS_PASSWORD:-redis_dev_password}
    volumes:
      - redis_data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "-a", "${REDIS_PASSWORD:-redis_dev_password}", "ping"]
      interval: 10s
      timeout: 5s
      retries: 3

volumes:
  postgres_data:
  redis_data:
EOF

# ── Shared Types Package ─────────────────────────────────────────────────────
info "Creating shared types package..."

mkdir -p packages/shared/src

cat > packages/shared/package.json << EOF
{
  "name": "@${PROJECT_NAME}/shared",
  "version": "0.0.1",
  "private": true,
  "main": "./src/index.ts",
  "types": "./src/index.ts",
  "scripts": {
    "typecheck": "tsc --noEmit",
    "lint": "eslint src/"
  }
}
EOF

cat > packages/shared/tsconfig.json << 'EOF'
{
  "extends": "../../tsconfig.base.json",
  "compilerOptions": {
    "outDir": "./dist"
  },
  "include": ["src"]
}
EOF

cat > packages/shared/src/index.ts << 'EOF'
// Shared types between frontend and backend
export type { User, UserRole, AuthTokens, ApiResponse, PaginatedResult } from './types';
export { USER_ROLES, API_ERRORS } from './constants';
EOF

cat > packages/shared/src/types.ts << 'EOF'
// ── User ────────────────────────────────────
export type UserRole = 'user' | 'admin';

export interface User {
  id: string;
  email: string;
  name: string;
  role: UserRole;
  avatar?: string | null;
  createdAt: string;
  updatedAt: string;
}

// ── Auth ────────────────────────────────────
export interface AuthTokens {
  accessToken: string;
  refreshToken: string;
}

// ── API ─────────────────────────────────────
export interface ApiResponse<T> {
  data: T;
  message?: string;
}

export interface ApiError {
  error: {
    message: string;
    code: string;
    details?: unknown;
  };
}

export interface PaginatedResult<T> {
  data: T[];
  pageInfo: {
    hasNextPage: boolean;
    hasPrevPage: boolean;
    endCursor: string | null;
    totalCount?: number;
  };
}
EOF

cat > packages/shared/src/constants.ts << 'EOF'
export const USER_ROLES = ['user', 'admin'] as const;

export const API_ERRORS = {
  UNAUTHORIZED: 'UNAUTHORIZED',
  FORBIDDEN: 'FORBIDDEN',
  NOT_FOUND: 'NOT_FOUND',
  VALIDATION: 'VALIDATION_ERROR',
  CONFLICT: 'CONFLICT',
  INTERNAL: 'INTERNAL_ERROR',
} as const;
EOF

# ── Backend API ──────────────────────────────────────────────────────────────
info "Creating backend API..."

mkdir -p apps/api/src/{routes,services,middleware,lib,schemas}
mkdir -p apps/api/prisma
mkdir -p apps/api/src/__tests__

cat > apps/api/package.json << EOF
{
  "name": "@${PROJECT_NAME}/api",
  "version": "0.0.1",
  "private": true,
  "scripts": {
    "dev": "tsx watch src/index.ts",
    "build": "tsc",
    "start": "node dist/index.js",
    "typecheck": "tsc --noEmit",
    "lint": "eslint src/",
    "test": "vitest run",
    "test:watch": "vitest"
  },
  "dependencies": {
    "@${PROJECT_NAME}/shared": "workspace:*",
    "@prisma/client": "^5",
    "argon2": "^0.40",
    "cors": "^2.8",
    "express": "^4.18",
    "jsonwebtoken": "^9",
    "zod": "^3.22"
  },
  "devDependencies": {
    "@types/cors": "^2.8",
    "@types/express": "^4.17",
    "@types/jsonwebtoken": "^9",
    "@types/node": "^20",
    "prisma": "^5",
    "tsx": "^4",
    "typescript": "^5",
    "vitest": "^2",
    "supertest": "^6",
    "@types/supertest": "^6"
  }
}
EOF

cat > apps/api/tsconfig.json << 'EOF'
{
  "extends": "../../tsconfig.base.json",
  "compilerOptions": {
    "outDir": "./dist",
    "rootDir": "./src",
    "module": "ESNext",
    "moduleResolution": "bundler",
    "target": "ES2022"
  },
  "include": ["src"],
  "references": [
    { "path": "../../packages/shared" }
  ]
}
EOF

# Prisma schema
cat > apps/api/prisma/schema.prisma << 'EOF'
generator client {
  provider = "prisma-client-js"
}

datasource db {
  provider = "postgresql"
  url      = env("DATABASE_URL")
}

model User {
  id           String   @id @default(cuid())
  email        String   @unique
  passwordHash String   @map("password_hash")
  name         String
  role         String   @default("user")
  avatar       String?
  createdAt    DateTime @default(now()) @map("created_at")
  updatedAt    DateTime @updatedAt @map("updated_at")

  @@map("users")
}
EOF

# App entrypoint
cat > apps/api/src/index.ts << 'EOF'
import express from 'express';
import cors from 'cors';
import { env } from './lib/env.js';
import { errorHandler } from './middleware/error-handler.js';
import { authRouter } from './routes/auth.route.js';
import { usersRouter } from './routes/users.route.js';

const app = express();

// Middleware
app.use(cors({ origin: env.APP_URL, credentials: true }));
app.use(express.json({ limit: '10mb' }));

// Health check
app.get('/api/health', (_req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

// Routes
app.use('/api/auth', authRouter);
app.use('/api/users', usersRouter);

// Error handler (must be last)
app.use(errorHandler);

app.listen(env.PORT, () => {
  console.log(`API running on http://localhost:${env.PORT}`);
});

export { app };
EOF

# Environment validation
cat > apps/api/src/lib/env.ts << 'EOF'
import { z } from 'zod';

const envSchema = z.object({
  NODE_ENV: z.enum(['development', 'production', 'test']).default('development'),
  PORT: z.coerce.number().default(4000),
  APP_URL: z.string().default('http://localhost:3000'),
  DATABASE_URL: z.string(),
  JWT_ACCESS_SECRET: z.string().min(16),
  JWT_REFRESH_SECRET: z.string().min(16),
});

const result = envSchema.safeParse(process.env);

if (!result.success) {
  console.error('Invalid environment variables:');
  for (const issue of result.error.issues) {
    console.error(`  ${issue.path.join('.')}: ${issue.message}`);
  }
  process.exit(1);
}

export const env = result.data;
EOF

# Prisma client singleton
cat > apps/api/src/lib/prisma.ts << 'EOF'
import { PrismaClient } from '@prisma/client';

const globalForPrisma = globalThis as unknown as { prisma: PrismaClient };

export const prisma =
  globalForPrisma.prisma ||
  new PrismaClient({
    log: process.env.NODE_ENV === 'development' ? ['query', 'error', 'warn'] : ['error'],
  });

if (process.env.NODE_ENV !== 'production') globalForPrisma.prisma = prisma;
EOF

# JWT utilities
cat > apps/api/src/lib/jwt.ts << 'EOF'
import jwt from 'jsonwebtoken';
import { env } from './env.js';

interface TokenPayload {
  sub: string;
  role: string;
  type: 'access' | 'refresh';
}

export function generateTokenPair(userId: string, role: string) {
  const accessToken = jwt.sign(
    { sub: userId, role, type: 'access' } satisfies TokenPayload,
    env.JWT_ACCESS_SECRET,
    { expiresIn: '15m' },
  );

  const refreshToken = jwt.sign(
    { sub: userId, role, type: 'refresh' } satisfies TokenPayload,
    env.JWT_REFRESH_SECRET,
    { expiresIn: '7d' },
  );

  return { accessToken, refreshToken };
}

export function verifyAccessToken(token: string): TokenPayload {
  return jwt.verify(token, env.JWT_ACCESS_SECRET) as TokenPayload;
}

export function verifyRefreshToken(token: string): TokenPayload {
  return jwt.verify(token, env.JWT_REFRESH_SECRET) as TokenPayload;
}
EOF

# Error classes
cat > apps/api/src/lib/errors.ts << 'EOF'
export class AppError extends Error {
  constructor(
    public statusCode: number,
    message: string,
    public code: string = 'ERROR',
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

export class UnauthorizedError extends AppError {
  constructor(message = 'Authentication required') {
    super(401, message, 'UNAUTHORIZED');
  }
}

export class ForbiddenError extends AppError {
  constructor(message = 'Insufficient permissions') {
    super(403, message, 'FORBIDDEN');
  }
}

export class ConflictError extends AppError {
  constructor(message: string) {
    super(409, message, 'CONFLICT');
  }
}
EOF

# Async handler
cat > apps/api/src/lib/async-handler.ts << 'EOF'
import { Request, Response, NextFunction, RequestHandler } from 'express';

export function asyncHandler(
  fn: (req: Request, res: Response, next: NextFunction) => Promise<any>,
): RequestHandler {
  return (req, res, next) => {
    Promise.resolve(fn(req, res, next)).catch(next);
  };
}
EOF

# Auth middleware
cat > apps/api/src/middleware/auth.ts << 'EOF'
import { Request, Response, NextFunction } from 'express';
import { verifyAccessToken } from '../lib/jwt.js';

declare global {
  namespace Express {
    interface Request {
      user?: { id: string; role: string };
    }
  }
}

export function requireAuth(req: Request, res: Response, next: NextFunction) {
  const header = req.headers.authorization;
  if (!header?.startsWith('Bearer ')) {
    return res.status(401).json({ error: { message: 'Missing token', code: 'UNAUTHORIZED' } });
  }

  try {
    const payload = verifyAccessToken(header.slice(7));
    req.user = { id: payload.sub, role: payload.role };
    next();
  } catch {
    return res.status(401).json({ error: { message: 'Invalid or expired token', code: 'UNAUTHORIZED' } });
  }
}
EOF

# Error handler middleware
cat > apps/api/src/middleware/error-handler.ts << 'EOF'
import { Request, Response, NextFunction } from 'express';
import { ZodError } from 'zod';
import { AppError } from '../lib/errors.js';

export function errorHandler(err: Error, _req: Request, res: Response, _next: NextFunction) {
  if (err instanceof AppError) {
    return res.status(err.statusCode).json({
      error: { message: err.message, code: err.code },
    });
  }

  if (err instanceof ZodError) {
    return res.status(422).json({
      error: {
        message: 'Validation failed',
        code: 'VALIDATION_ERROR',
        details: err.issues.map((i) => ({ path: i.path.join('.'), message: i.message })),
      },
    });
  }

  console.error('Unhandled error:', err);
  res.status(500).json({
    error: { message: 'Internal server error', code: 'INTERNAL_ERROR' },
  });
}
EOF

# Auth schemas
cat > apps/api/src/schemas/auth.schema.ts << 'EOF'
import { z } from 'zod';

export const registerSchema = z.object({
  name: z.string().min(2).max(100),
  email: z.string().email(),
  password: z.string().min(8).max(128),
});

export const loginSchema = z.object({
  email: z.string().email(),
  password: z.string().min(1),
});

export type RegisterInput = z.infer<typeof registerSchema>;
export type LoginInput = z.infer<typeof loginSchema>;
EOF

# Auth route
cat > apps/api/src/routes/auth.route.ts << 'EOF'
import { Router } from 'express';
import argon2 from 'argon2';
import { prisma } from '../lib/prisma.js';
import { generateTokenPair, verifyRefreshToken } from '../lib/jwt.js';
import { registerSchema, loginSchema } from '../schemas/auth.schema.js';
import { asyncHandler } from '../lib/async-handler.js';
import { ConflictError, UnauthorizedError } from '../lib/errors.js';

const router = Router();

// POST /api/auth/register
router.post('/register', asyncHandler(async (req, res) => {
  const { name, email, password } = registerSchema.parse(req.body);

  const existing = await prisma.user.findUnique({ where: { email } });
  if (existing) throw new ConflictError('Email already registered');

  const passwordHash = await argon2.hash(password);
  const user = await prisma.user.create({
    data: { name, email, passwordHash },
  });

  const tokens = generateTokenPair(user.id, user.role);

  res.status(201).json({
    data: {
      user: { id: user.id, email: user.email, name: user.name, role: user.role },
      ...tokens,
    },
  });
}));

// POST /api/auth/login
router.post('/login', asyncHandler(async (req, res) => {
  const { email, password } = loginSchema.parse(req.body);

  const user = await prisma.user.findUnique({ where: { email } });
  if (!user) throw new UnauthorizedError('Invalid credentials');

  const valid = await argon2.verify(user.passwordHash, password);
  if (!valid) throw new UnauthorizedError('Invalid credentials');

  const tokens = generateTokenPair(user.id, user.role);

  res.json({
    data: {
      user: { id: user.id, email: user.email, name: user.name, role: user.role },
      ...tokens,
    },
  });
}));

// POST /api/auth/refresh
router.post('/refresh', asyncHandler(async (req, res) => {
  const { refreshToken } = req.body;
  if (!refreshToken) throw new UnauthorizedError('Refresh token required');

  const payload = verifyRefreshToken(refreshToken);
  const user = await prisma.user.findUnique({ where: { id: payload.sub } });
  if (!user) throw new UnauthorizedError('User not found');

  const tokens = generateTokenPair(user.id, user.role);
  res.json({ data: tokens });
}));

export { router as authRouter };
EOF

# Users route
cat > apps/api/src/routes/users.route.ts << 'EOF'
import { Router } from 'express';
import { prisma } from '../lib/prisma.js';
import { requireAuth } from '../middleware/auth.js';
import { asyncHandler } from '../lib/async-handler.js';
import { NotFoundError } from '../lib/errors.js';

const router = Router();

// GET /api/users/me
router.get('/me', requireAuth, asyncHandler(async (req, res) => {
  const user = await prisma.user.findUnique({
    where: { id: req.user!.id },
    select: { id: true, email: true, name: true, role: true, avatar: true, createdAt: true },
  });
  if (!user) throw new NotFoundError('User');
  res.json({ data: user });
}));

export { router as usersRouter };
EOF

success "Backend API created"

# ── Frontend App ─────────────────────────────────────────────────────────────
info "Creating frontend app (${STACK})..."

mkdir -p apps/web

case "$STACK" in
  next)
    cat > apps/web/package.json << EOF
{
  "name": "@${PROJECT_NAME}/web",
  "version": "0.0.1",
  "private": true,
  "scripts": {
    "dev": "next dev",
    "build": "next build",
    "start": "next start",
    "lint": "next lint",
    "typecheck": "tsc --noEmit"
  },
  "dependencies": {
    "@${PROJECT_NAME}/shared": "workspace:*",
    "next": "^14",
    "react": "^18",
    "react-dom": "^18"
  },
  "devDependencies": {
    "@types/node": "^20",
    "@types/react": "^18",
    "@types/react-dom": "^18",
    "autoprefixer": "^10",
    "postcss": "^8",
    "tailwindcss": "^3",
    "typescript": "^5"
  }
}
EOF

    cat > apps/web/tsconfig.json << 'EOF'
{
  "extends": "../../tsconfig.base.json",
  "compilerOptions": {
    "jsx": "preserve",
    "lib": ["dom", "dom.iterable", "ES2022"],
    "module": "ESNext",
    "moduleResolution": "bundler",
    "plugins": [{ "name": "next" }],
    "paths": { "@/*": ["./src/*"] }
  },
  "include": ["src", "next-env.d.ts", ".next/types/**/*.ts"],
  "exclude": ["node_modules"]
}
EOF

    cat > apps/web/next.config.js << 'EOF'
/** @type {import('next').NextConfig} */
const nextConfig = {
  transpilePackages: ['@${PROJECT_NAME}/shared'],
  output: 'standalone',
};

module.exports = nextConfig;
EOF

    cat > apps/web/tailwind.config.ts << 'EOF'
import type { Config } from 'tailwindcss';

const config: Config = {
  content: ['./src/**/*.{js,ts,jsx,tsx,mdx}'],
  theme: { extend: {} },
  plugins: [],
};

export default config;
EOF

    cat > apps/web/postcss.config.js << 'EOF'
module.exports = {
  plugins: {
    tailwindcss: {},
    autoprefixer: {},
  },
};
EOF

    mkdir -p apps/web/src/app

    cat > apps/web/src/app/layout.tsx << 'EOF'
import type { Metadata } from 'next';
import './globals.css';

export const metadata: Metadata = {
  title: 'My App',
  description: 'Full-stack application',
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
EOF

    cat > apps/web/src/app/page.tsx << 'EOF'
export default function Home() {
  return (
    <main className="flex min-h-screen flex-col items-center justify-center p-24">
      <h1 className="text-4xl font-bold">Welcome</h1>
      <p className="mt-4 text-lg text-gray-600">Your full-stack app is ready.</p>
    </main>
  );
}
EOF

    cat > apps/web/src/app/globals.css << 'EOF'
@tailwind base;
@tailwind components;
@tailwind utilities;
EOF
    ;;

  nuxt)
    cat > apps/web/package.json << EOF
{
  "name": "@${PROJECT_NAME}/web",
  "version": "0.0.1",
  "private": true,
  "scripts": {
    "dev": "nuxt dev",
    "build": "nuxt build",
    "start": "nuxt preview",
    "lint": "eslint .",
    "typecheck": "nuxt typecheck"
  },
  "dependencies": {
    "@${PROJECT_NAME}/shared": "workspace:*",
    "nuxt": "^3"
  },
  "devDependencies": {
    "@nuxt/eslint-config": "^0.3",
    "typescript": "^5"
  }
}
EOF

    cat > apps/web/nuxt.config.ts << 'EOF'
export default defineNuxtConfig({
  devtools: { enabled: true },
  modules: [],
  runtimeConfig: {
    public: {
      apiUrl: process.env.NUXT_PUBLIC_API_URL || 'http://localhost:4000',
    },
  },
  typescript: { strict: true },
});
EOF

    cat > apps/web/tsconfig.json << 'EOF'
{
  "extends": "./.nuxt/tsconfig.json"
}
EOF

    mkdir -p apps/web/pages apps/web/components apps/web/composables

    cat > apps/web/pages/index.vue << 'EOF'
<template>
  <main class="flex min-h-screen flex-col items-center justify-center p-24">
    <h1 class="text-4xl font-bold">Welcome</h1>
    <p class="mt-4 text-lg text-gray-600">Your full-stack app is ready.</p>
  </main>
</template>
EOF

    cat > apps/web/app.vue << 'EOF'
<template>
  <NuxtLayout>
    <NuxtPage />
  </NuxtLayout>
</template>
EOF
    ;;

  sveltekit)
    cat > apps/web/package.json << EOF
{
  "name": "@${PROJECT_NAME}/web",
  "version": "0.0.1",
  "private": true,
  "scripts": {
    "dev": "vite dev",
    "build": "vite build",
    "start": "vite preview",
    "lint": "eslint .",
    "typecheck": "svelte-check --tsconfig ./tsconfig.json"
  },
  "dependencies": {
    "@${PROJECT_NAME}/shared": "workspace:*"
  },
  "devDependencies": {
    "@sveltejs/adapter-auto": "^3",
    "@sveltejs/kit": "^2",
    "svelte": "^4",
    "svelte-check": "^3",
    "typescript": "^5",
    "vite": "^5"
  }
}
EOF

    cat > apps/web/tsconfig.json << 'EOF'
{
  "extends": "./.svelte-kit/tsconfig.json",
  "compilerOptions": {
    "strict": true
  }
}
EOF

    cat > apps/web/svelte.config.js << 'EOF'
import adapter from '@sveltejs/adapter-auto';
import { vitePreprocess } from '@sveltejs/vite-plugin-svelte';

/** @type {import('@sveltejs/kit').Config} */
const config = {
  preprocess: vitePreprocess(),
  kit: {
    adapter: adapter(),
  },
};

export default config;
EOF

    cat > apps/web/vite.config.ts << 'EOF'
import { sveltekit } from '@sveltejs/kit/vite';
import { defineConfig } from 'vite';

export default defineConfig({
  plugins: [sveltekit()],
});
EOF

    mkdir -p apps/web/src/routes apps/web/src/lib

    cat > apps/web/src/routes/+page.svelte << 'EOF'
<main class="flex min-h-screen flex-col items-center justify-center p-24">
  <h1 class="text-4xl font-bold">Welcome</h1>
  <p class="mt-4 text-lg text-gray-600">Your full-stack app is ready.</p>
</main>
EOF

    cat > apps/web/src/app.html << 'EOF'
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    %sveltekit.head%
  </head>
  <body data-sveltekit-preload-data="hover">
    <div style="display: contents">%sveltekit.body%</div>
  </body>
</html>
EOF
    ;;
esac

success "Frontend app created (${STACK})"

# ── GitHub Actions CI ────────────────────────────────────────────────────────
info "Creating CI workflow..."

mkdir -p .github/workflows

cat > .github/workflows/ci.yml << 'EOF'
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

env:
  DATABASE_URL: postgresql://postgres:postgres@localhost:5432/test
  JWT_ACCESS_SECRET: ci-test-access-secret-32-chars-long
  JWT_REFRESH_SECRET: ci-test-refresh-secret-32-chars-long
  NODE_ENV: test

jobs:
  lint-and-typecheck:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: pnpm/action-setup@v3
      - uses: actions/setup-node@v4
        with:
          node-version: 20
          cache: pnpm
      - run: pnpm install --frozen-lockfile
      - run: pnpm lint
      - run: pnpm typecheck

  test:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:16-alpine
        env:
          POSTGRES_DB: test
          POSTGRES_USER: postgres
          POSTGRES_PASSWORD: postgres
        ports:
          - 5432:5432
        options: >-
          --health-cmd "pg_isready -U postgres"
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
    steps:
      - uses: actions/checkout@v4
      - uses: pnpm/action-setup@v3
      - uses: actions/setup-node@v4
        with:
          node-version: 20
          cache: pnpm
      - run: pnpm install --frozen-lockfile
      - run: cd apps/api && npx prisma migrate deploy
      - run: pnpm test

  build:
    runs-on: ubuntu-latest
    needs: [lint-and-typecheck]
    steps:
      - uses: actions/checkout@v4
      - uses: pnpm/action-setup@v3
      - uses: actions/setup-node@v4
        with:
          node-version: 20
          cache: pnpm
      - run: pnpm install --frozen-lockfile
      - run: pnpm build
EOF

# ── Initialize Git ───────────────────────────────────────────────────────────
info "Initializing Git repository..."
git init -q
git add -A
git commit -q -m "Initial project setup: ${STACK} + Express + Prisma + Docker"

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN} Project created successfully!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "  Project:   ${PROJECT_NAME}"
echo "  Stack:     ${STACK} + Express + PostgreSQL"
echo "  Location:  $(pwd)"
echo ""
echo -e "  ${BLUE}Structure:${NC}"
echo "  ├── apps/"
echo "  │   ├── web/          Frontend (${STACK})"
echo "  │   └── api/          Backend (Express + Prisma)"
echo "  ├── packages/"
echo "  │   └── shared/       Shared types + constants"
echo "  ├── docker-compose.yml"
echo "  └── .github/workflows/ci.yml"
echo ""
echo -e "  ${YELLOW}Next steps:${NC}"
echo ""
echo "  1. Start infrastructure:"
echo "     docker compose up -d"
echo ""
echo "  2. Install dependencies:"
echo "     pnpm install"
echo ""
echo "  3. Set up database:"
echo "     cd apps/api && npx prisma migrate dev --name init"
echo ""
echo "  4. Start development:"
echo "     pnpm dev"
echo ""
echo "  5. Open in browser:"
echo "     Frontend: http://localhost:3000"
echo "     API:      http://localhost:4000/api/health"
echo ""
