# Database Patterns Reference

## Table of Contents

1. [Repository Pattern](#repository-pattern)
2. [Unit of Work Pattern](#unit-of-work-pattern)
3. [Query Builder Patterns](#query-builder-patterns)
4. [Connection Management](#connection-management)
5. [Transaction Patterns](#transaction-patterns)
6. [Pagination Patterns](#pagination-patterns)
7. [Soft Delete Pattern](#soft-delete-pattern)
8. [Multi-Tenancy Patterns](#multi-tenancy-patterns)

---

## Repository Pattern

```typescript
// Generic repository interface
interface Repository<T, ID = string> {
  findById(id: ID): Promise<T | null>;
  findAll(filter?: Partial<T>): Promise<T[]>;
  create(entity: Omit<T, 'id' | 'createdAt' | 'updatedAt'>): Promise<T>;
  update(id: ID, data: Partial<T>): Promise<T>;
  delete(id: ID): Promise<void>;
}

// Concrete implementation with Prisma
class PrismaUserRepository implements Repository<User> {
  constructor(private prisma: PrismaClient) {}

  async findById(id: string): Promise<User | null> {
    return this.prisma.user.findUnique({ where: { id } });
  }

  async findAll(filter?: Partial<User>): Promise<User[]> {
    return this.prisma.user.findMany({
      where: filter,
      orderBy: { createdAt: 'desc' },
    });
  }

  async create(data: CreateUserInput): Promise<User> {
    return this.prisma.user.create({ data });
  }

  async update(id: string, data: Partial<User>): Promise<User> {
    return this.prisma.user.update({ where: { id }, data });
  }

  async delete(id: string): Promise<void> {
    await this.prisma.user.delete({ where: { id } });
  }

  // Domain-specific queries
  async findByEmail(email: string): Promise<User | null> {
    return this.prisma.user.findUnique({ where: { email } });
  }

  async findActiveWithOrders(): Promise<UserWithOrders[]> {
    return this.prisma.user.findMany({
      where: { status: 'active' },
      include: {
        orders: {
          where: { status: { not: 'cancelled' } },
          orderBy: { createdAt: 'desc' },
          take: 10,
        },
      },
    });
  }
}
```

---

## Unit of Work Pattern

```typescript
// Coordinate multiple repositories in a single transaction
class UnitOfWork {
  private prisma: PrismaClient;

  constructor(prisma: PrismaClient) {
    this.prisma = prisma;
  }

  async execute<T>(work: (repos: {
    users: PrismaUserRepository;
    orders: PrismaOrderRepository;
    payments: PrismaPaymentRepository;
  }, tx: PrismaTransaction) => Promise<T>): Promise<T> {
    return this.prisma.$transaction(async (tx) => {
      const repos = {
        users: new PrismaUserRepository(tx as any),
        orders: new PrismaOrderRepository(tx as any),
        payments: new PrismaPaymentRepository(tx as any),
      };
      return work(repos, tx);
    }, {
      maxWait: 5000,    // Max wait to acquire lock
      timeout: 10000,   // Max transaction duration
      isolationLevel: 'Serializable', // When needed
    });
  }
}

// Usage
const uow = new UnitOfWork(prisma);

await uow.execute(async ({ users, orders, payments }) => {
  const user = await users.findById(userId);
  if (!user) throw new NotFoundError('User not found');

  const order = await orders.create({
    userId: user.id,
    items: orderItems,
    total: calculateTotal(orderItems),
  });

  await payments.create({
    orderId: order.id,
    amount: order.total,
    method: paymentMethod,
    status: 'pending',
  });

  return order;
});
```

---

## Query Builder Patterns

### Dynamic Query Building with Prisma

```typescript
// Type-safe dynamic filtering — build where clauses conditionally
interface UserFilterParams {
  search?: string;
  status?: 'active' | 'inactive' | 'suspended';
  role?: string;
  createdAfter?: Date;
  createdBefore?: Date;
}

function buildUserWhereClause(filters: UserFilterParams): Prisma.UserWhereInput {
  const where: Prisma.UserWhereInput = {};

  if (filters.search) {
    where.OR = [
      { name: { contains: filters.search, mode: 'insensitive' } },
      { email: { contains: filters.search, mode: 'insensitive' } },
    ];
  }
  if (filters.status) where.status = filters.status;
  if (filters.role) where.role = filters.role;
  if (filters.createdAfter || filters.createdBefore) {
    where.createdAt = {
      ...(filters.createdAfter && { gte: filters.createdAfter }),
      ...(filters.createdBefore && { lte: filters.createdBefore }),
    };
  }

  return where;
}

// Usage in a service
async function listUsers(filters: UserFilterParams, cursor?: string) {
  const limit = 25;
  return prisma.user.findMany({
    where: buildUserWhereClause(filters),
    take: limit + 1,
    ...(cursor && { cursor: { id: cursor }, skip: 1 }),
    orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
  });
}
```

### Conditional Filtering with Drizzle ORM

```typescript
import { and, eq, ilike, gte, lte, or, SQL } from 'drizzle-orm';
import { users } from './schema';

function buildDrizzleFilters(filters: UserFilterParams): SQL | undefined {
  const conditions: SQL[] = [];

  if (filters.search) {
    conditions.push(
      or(
        ilike(users.name, `%${filters.search}%`),
        ilike(users.email, `%${filters.search}%`),
      )!,
    );
  }
  if (filters.status) conditions.push(eq(users.status, filters.status));
  if (filters.role) conditions.push(eq(users.role, filters.role));
  if (filters.createdAfter) conditions.push(gte(users.createdAt, filters.createdAfter));
  if (filters.createdBefore) conditions.push(lte(users.createdAt, filters.createdBefore));

  return conditions.length > 0 ? and(...conditions) : undefined;
}

// Cursor-based pagination with Drizzle
async function paginateUsers(db: DrizzleDB, filters: UserFilterParams, cursor?: string) {
  const limit = 25;
  const where = buildDrizzleFilters(filters);
  const cursorCondition = cursor
    ? and(where, lte(users.id, cursor))
    : where;

  const rows = await db.select()
    .from(users)
    .where(cursorCondition)
    .orderBy(desc(users.createdAt), desc(users.id))
    .limit(limit + 1);

  const hasMore = rows.length > limit;
  return { data: rows.slice(0, limit), hasNextPage: hasMore };
}
```

### Composable Queries with Knex

```typescript
import Knex from 'knex';

function applyUserFilters(qb: Knex.QueryBuilder, filters: UserFilterParams): Knex.QueryBuilder {
  if (filters.search) {
    qb.where(function () {
      this.whereILike('name', `%${filters.search}%`)
          .orWhereILike('email', `%${filters.search}%`);
    });
  }
  if (filters.status) qb.where('status', filters.status);
  if (filters.role) qb.where('role', filters.role);
  if (filters.createdAfter) qb.where('created_at', '>=', filters.createdAfter);
  if (filters.createdBefore) qb.where('created_at', '<=', filters.createdBefore);
  return qb;
}

// Cursor pagination + result mapping
async function queryUsers(knex: Knex, filters: UserFilterParams, cursor?: string) {
  const limit = 25;
  let qb = knex('users').select('*');
  qb = applyUserFilters(qb, filters);
  if (cursor) qb.where('id', '<', cursor);
  qb.orderBy([{ column: 'created_at', order: 'desc' }, { column: 'id', order: 'desc' }]);
  qb.limit(limit + 1);

  const rows = await qb;
  const hasMore = rows.length > limit;
  const data = rows.slice(0, limit).map(mapRowToUser);
  return { data, hasNextPage: hasMore };
}

// Query result mapping — snake_case DB rows to camelCase domain objects
function mapRowToUser(row: Record<string, unknown>): User {
  return {
    id: row.id as string,
    name: row.name as string,
    email: row.email as string,
    status: row.status as string,
    role: row.role as string,
    createdAt: new Date(row.created_at as string),
    updatedAt: new Date(row.updated_at as string),
  };
}
```

### Raw Queries for Complex Cases

```typescript
// Prisma — raw SQL for window functions, CTEs, or performance-critical paths
const activeUsersWithRank = await prisma.$queryRaw<UserWithRank[]>`
  WITH ranked AS (
    SELECT
      u.id, u.name, u.email,
      COUNT(o.id) AS order_count,
      SUM(o.total) AS lifetime_value,
      ROW_NUMBER() OVER (ORDER BY SUM(o.total) DESC) AS rank
    FROM users u
    LEFT JOIN orders o ON o.user_id = u.id AND o.status = 'completed'
    WHERE u.status = 'active'
      AND u.created_at >= ${startDate}
    GROUP BY u.id
  )
  SELECT * FROM ranked WHERE rank <= ${topN}
  ORDER BY rank ASC;
`;

// Drizzle — raw SQL escape hatch
const result = await db.execute<UserWithRank>(sql`
  SELECT u.id, u.name, COUNT(o.id)::int AS order_count
  FROM ${users} u
  LEFT JOIN orders o ON o.user_id = u.id
  GROUP BY u.id
  HAVING COUNT(o.id) > ${minOrders}
`);
```

---

## Connection Management

```typescript
// Production connection pool configuration (PostgreSQL + node-postgres)
import { Pool, PoolConfig } from 'pg';

const poolConfig: PoolConfig = {
  host: process.env.DB_HOST,
  port: Number(process.env.DB_PORT) || 5432,
  database: process.env.DB_NAME,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,

  // Pool sizing: (CPU cores * 2) + effective_spindle_count
  // For cloud: start with 10-20, increase based on monitoring
  min: 2,                    // Keep minimum connections warm
  max: 20,                   // Hard cap
  idleTimeoutMillis: 30000,  // Close idle connections after 30s
  connectionTimeoutMillis: 5000, // Fail fast if pool exhausted

  // SSL for production
  ssl: process.env.NODE_ENV === 'production'
    ? { rejectUnauthorized: true, ca: process.env.DB_CA_CERT }
    : false,

  // Application name for monitoring
  application_name: `myapp-${process.env.NODE_ENV}`,
};

const pool = new Pool(poolConfig);

// Monitor pool health
pool.on('error', (err) => {
  logger.error('Unexpected pool error', err);
});

pool.on('connect', () => {
  logger.debug('New client connected to pool');
});

// Graceful shutdown
process.on('SIGTERM', async () => {
  logger.info('Draining database pool...');
  await pool.end();
  process.exit(0);
});

// Health check endpoint
async function checkDbHealth(): Promise<{ ok: boolean; latencyMs: number }> {
  const start = performance.now();
  try {
    await pool.query('SELECT 1');
    return { ok: true, latencyMs: performance.now() - start };
  } catch {
    return { ok: false, latencyMs: performance.now() - start };
  }
}
```

---

## Transaction Patterns

### Optimistic Locking

```sql
-- Add version column
ALTER TABLE products ADD COLUMN version INT NOT NULL DEFAULT 1;

-- Read
SELECT id, name, stock, version FROM products WHERE id = $1;

-- Update with version check (optimistic lock)
UPDATE products
SET stock = stock - $1, version = version + 1, updated_at = NOW()
WHERE id = $2 AND version = $3
RETURNING *;

-- If 0 rows affected → concurrent modification → retry or error
```

```typescript
async function updateStock(productId: string, quantity: number, maxRetries = 3) {
  for (let attempt = 0; attempt < maxRetries; attempt++) {
    const product = await db.product.findUnique({ where: { id: productId } });
    if (!product) throw new NotFoundError('Product not found');
    if (product.stock < quantity) throw new InsufficientStockError();

    const updated = await db.$executeRaw`
      UPDATE products SET stock = stock - ${quantity}, version = version + 1
      WHERE id = ${productId} AND version = ${product.version}`;

    if (updated > 0) return; // Success
    // Retry on conflict
    await sleep(50 * (attempt + 1)); // Exponential backoff
  }
  throw new ConflictError('Concurrent modification, please retry');
}
```

### Saga Pattern (Distributed Transactions)

```typescript
// Orchestrator saga for order processing
class OrderSaga {
  async execute(orderData: CreateOrderInput): Promise<Order> {
    const compensations: Array<() => Promise<void>> = [];

    try {
      // Step 1: Reserve inventory
      const reservation = await inventoryService.reserve(orderData.items);
      compensations.push(() => inventoryService.release(reservation.id));

      // Step 2: Process payment
      const payment = await paymentService.charge({
        amount: orderData.total,
        method: orderData.paymentMethod,
      });
      compensations.push(() => paymentService.refund(payment.id));

      // Step 3: Create order
      const order = await orderService.create({
        ...orderData,
        reservationId: reservation.id,
        paymentId: payment.id,
        status: 'confirmed',
      });

      // Step 4: Send confirmation
      await notificationService.sendOrderConfirmation(order);

      return order;
    } catch (error) {
      // Compensate in reverse order
      for (const compensate of compensations.reverse()) {
        try {
          await compensate();
        } catch (compError) {
          logger.error('Compensation failed', compError);
          // Log to dead-letter queue for manual resolution
          await deadLetterQueue.add({ error: compError, saga: 'order' });
        }
      }
      throw error;
    }
  }
}
```

---

## Pagination Patterns

### Cursor-Based (Recommended for Production)

```typescript
interface CursorPaginationParams {
  cursor?: string;   // Opaque cursor (base64 encoded)
  limit?: number;    // Page size (default 20, max 100)
  direction?: 'forward' | 'backward';
}

interface PaginatedResult<T> {
  data: T[];
  pageInfo: {
    hasNextPage: boolean;
    hasPrevPage: boolean;
    startCursor: string | null;
    endCursor: string | null;
    totalCount?: number; // Optional, expensive for large tables
  };
}

async function findUsersPaginated(params: CursorPaginationParams): Promise<PaginatedResult<User>> {
  const limit = Math.min(params.limit || 20, 100);
  const fetchCount = limit + 1; // Fetch one extra to check hasMore

  let cursor: { id: string; createdAt: Date } | undefined;
  if (params.cursor) {
    cursor = JSON.parse(Buffer.from(params.cursor, 'base64url').toString());
  }

  const users = await prisma.user.findMany({
    take: fetchCount,
    ...(cursor && {
      cursor: { id: cursor.id },
      skip: 1, // Skip the cursor item itself
    }),
    orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
  });

  const hasMore = users.length > limit;
  const data = hasMore ? users.slice(0, limit) : users;

  const encodeCursor = (user: User) =>
    Buffer.from(JSON.stringify({ id: user.id, createdAt: user.createdAt }))
      .toString('base64url');

  return {
    data,
    pageInfo: {
      hasNextPage: hasMore,
      hasPrevPage: !!params.cursor,
      startCursor: data.length > 0 ? encodeCursor(data[0]) : null,
      endCursor: data.length > 0 ? encodeCursor(data[data.length - 1]) : null,
    },
  };
}
```

---

## Soft Delete Pattern

```sql
-- Schema
ALTER TABLE users ADD COLUMN deleted_at TIMESTAMPTZ DEFAULT NULL;
CREATE INDEX idx_users_active ON users (id) WHERE deleted_at IS NULL;

-- Queries automatically filter deleted
CREATE VIEW active_users AS
  SELECT * FROM users WHERE deleted_at IS NULL;

-- Soft delete
UPDATE users SET deleted_at = NOW() WHERE id = $1;

-- Restore
UPDATE users SET deleted_at = NULL WHERE id = $1;

-- Hard delete (data retention policy, e.g., after 90 days)
DELETE FROM users WHERE deleted_at < NOW() - INTERVAL '90 days';
```

---

## Multi-Tenancy Patterns

```
Row-Level (shared tables, tenant_id column):
  + Simple, cost-effective for many small tenants
  - Must ALWAYS filter by tenant_id (risk of data leaks)
  Use: SaaS with many similar tenants

Schema-Level (tenant per schema):
  + Good isolation, shared infrastructure
  - Schema migration across all tenants
  Use: Medium isolation needs, moderate tenant count

Database-Level (tenant per database):
  + Maximum isolation, independent scaling
  - Most expensive, complex management
  Use: Enterprise, compliance-heavy, few large tenants
```

```typescript
// Row-level multi-tenancy with Prisma middleware
prisma.$use(async (params, next) => {
  const tenantId = getCurrentTenantId(); // From request context

  // Auto-filter reads
  if (params.action === 'findMany' || params.action === 'findFirst') {
    params.args.where = { ...params.args.where, tenantId };
  }

  // Auto-inject on creates
  if (params.action === 'create') {
    params.args.data.tenantId = tenantId;
  }

  return next(params);
});
```
