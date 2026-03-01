# Database Migration Patterns for Zero-Downtime Deployments

## Table of Contents

1. [Guiding Principles](#guiding-principles)
2. [Safe Column Operations](#safe-column-operations)
3. [Safe Index Creation](#safe-index-creation)
4. [Table Rename Strategy](#table-rename-strategy)
5. [Enum Type Modification](#enum-type-modification)
6. [Foreign Key Addition on Large Tables](#foreign-key-addition-on-large-tables)
7. [Column Type Change Without Lock](#column-type-change-without-lock)
8. [Large Data Migration in Batches](#large-data-migration-in-batches)
9. [Multi-Step Migration Workflow](#multi-step-migration-workflow)
10. [Blue-Green Database Deployment](#blue-green-database-deployment)
11. [Schema Versioning Strategy](#schema-versioning-strategy)
12. [Migration Testing Checklist](#migration-testing-checklist)
13. [Common Pitfalls](#common-pitfalls)

---

## Guiding Principles

1. **Never take exclusive locks on large tables during peak traffic.** Every DDL statement acquires some lock; know which lock level each operation requires.
2. **Make migrations backward-compatible.** The old application code must continue to work during and after each migration step until the next deployment.
3. **Deploy in multiple small steps** rather than one large migration. Each step should be independently safe to roll back.
4. **Test migrations against production-sized data.** A migration that runs in 50ms on a dev database with 100 rows may lock a 100M-row production table for hours.

### PostgreSQL Lock Levels Quick Reference

| Lock Level              | Blocks                    | Acquired By                                   |
|------------------------|---------------------------|-----------------------------------------------|
| ACCESS SHARE           | Nothing (except ACCESS EXCLUSIVE) | SELECT                                 |
| ROW SHARE              | EXCLUSIVE, ACCESS EXCLUSIVE | SELECT FOR UPDATE/SHARE                      |
| ROW EXCLUSIVE          | SHARE, SHARE ROW EXCLUSIVE, EXCLUSIVE, ACCESS EXCLUSIVE | INSERT, UPDATE, DELETE |
| SHARE UPDATE EXCLUSIVE | Same + SHARE UPDATE EXCLUSIVE | VACUUM, CREATE INDEX CONCURRENTLY, some ALTER TABLE |
| SHARE                  | ROW EXCLUSIVE and above   | CREATE INDEX (non-concurrent)                 |
| ACCESS EXCLUSIVE       | Everything                | DROP TABLE, ALTER TABLE (type change, NOT NULL), VACUUM FULL |

---

## Safe Column Operations

### Adding a New Column

Adding a nullable column with no default is instant in PostgreSQL 11+ (metadata-only change). It does NOT rewrite the table.

```sql
-- Step 1: Add nullable column (instant, takes ACCESS EXCLUSIVE lock very briefly).
ALTER TABLE orders ADD COLUMN discount_amount numeric;

-- This is safe. No table rewrite. Lock is held only for catalog update.
```

**WARNING:** In PostgreSQL 10 and earlier, adding a column with a DEFAULT value rewrites the entire table. In PostgreSQL 11+, adding a column with a non-volatile default is also instant.

```sql
-- PostgreSQL 11+: Also instant (no table rewrite).
ALTER TABLE orders ADD COLUMN discount_amount numeric DEFAULT 0;

-- PostgreSQL 10 and earlier: REWRITES ENTIRE TABLE. Avoid on large tables.
```

### Backfilling Data in a New Column

Never backfill in a single UPDATE statement on a large table. It creates a long-running transaction, generates massive WAL, and can cause replication lag.

```sql
-- BAD: Single statement updating 50 million rows.
UPDATE orders SET discount_amount = 0 WHERE discount_amount IS NULL;

-- GOOD: Batch update in chunks.
-- Use a script or DO block with batching:
DO $$
DECLARE
    batch_size INTEGER := 10000;
    updated INTEGER;
BEGIN
    LOOP
        UPDATE orders
        SET discount_amount = 0
        WHERE id IN (
            SELECT id FROM orders
            WHERE discount_amount IS NULL
            LIMIT batch_size
            FOR UPDATE SKIP LOCKED
        );

        GET DIAGNOSTICS updated = ROW_COUNT;
        RAISE NOTICE 'Updated % rows', updated;
        COMMIT;

        EXIT WHEN updated = 0;

        -- Optional: Sleep to reduce load.
        PERFORM pg_sleep(0.1);
    END LOOP;
END $$;
```

For very large tables, use a dedicated migration script with progress tracking:

```python
# Python example with psycopg2
import psycopg2
import time

conn = psycopg2.connect("dbname=myapp host=localhost")
conn.autocommit = True

BATCH_SIZE = 10000
total_updated = 0

while True:
    with conn.cursor() as cur:
        cur.execute("""
            UPDATE orders
            SET discount_amount = 0
            WHERE id IN (
                SELECT id FROM orders
                WHERE discount_amount IS NULL
                LIMIT %s
            )
        """, (BATCH_SIZE,))

        updated = cur.rowcount
        total_updated += updated
        print(f"Updated {updated} rows (total: {total_updated})")

        if updated == 0:
            break

    time.sleep(0.05)  # Small delay to reduce load

conn.close()
print(f"Backfill complete. Total rows updated: {total_updated}")
```

### Adding a NOT NULL Constraint

Never add NOT NULL directly on a large table. It requires scanning every row while holding an ACCESS EXCLUSIVE lock.

```sql
-- BAD: Scans entire table under ACCESS EXCLUSIVE lock.
ALTER TABLE orders ALTER COLUMN discount_amount SET NOT NULL;

-- GOOD: Use a CHECK constraint (validated in two steps).

-- Step 1: Add NOT VALID constraint (instant, no scan).
ALTER TABLE orders
    ADD CONSTRAINT orders_discount_amount_not_null
    CHECK (discount_amount IS NOT NULL) NOT VALID;

-- Step 2: Validate the constraint (scans table but only holds
-- SHARE UPDATE EXCLUSIVE lock, which does NOT block reads or writes).
ALTER TABLE orders
    VALIDATE CONSTRAINT orders_discount_amount_not_null;

-- Step 3 (PostgreSQL 12+): Now you can safely add the real NOT NULL.
-- PostgreSQL recognizes the validated CHECK and skips the full scan.
ALTER TABLE orders ALTER COLUMN discount_amount SET NOT NULL;

-- Step 4: Drop the now-redundant CHECK constraint.
ALTER TABLE orders DROP CONSTRAINT orders_discount_amount_not_null;
```

### Complete Multi-Step Column Addition Workflow

```
Deploy 1: Add column
  ALTER TABLE orders ADD COLUMN discount_amount numeric;

Deploy 2: Update application to write to new column
  - Application writes discount_amount on new orders.
  - Old orders still have NULL.

Deploy 3: Backfill old data
  - Run batch UPDATE script to set discount_amount = 0 for old rows.

Deploy 4: Add NOT NULL constraint
  - ALTER TABLE orders ADD CONSTRAINT ... CHECK (discount_amount IS NOT NULL) NOT VALID;
  - ALTER TABLE orders VALIDATE CONSTRAINT ...;
  - ALTER TABLE orders ALTER COLUMN discount_amount SET NOT NULL;
  - ALTER TABLE orders DROP CONSTRAINT ...;

Deploy 5: (Optional) Add default value
  ALTER TABLE orders ALTER COLUMN discount_amount SET DEFAULT 0;
```

---

## Safe Index Creation

### CREATE INDEX CONCURRENTLY

Standard `CREATE INDEX` takes a SHARE lock on the table, blocking all writes (INSERT, UPDATE, DELETE) for the duration of the index build. On large tables this can be minutes to hours.

`CREATE INDEX CONCURRENTLY` builds the index without blocking writes. It takes longer and requires two table scans, but the table remains fully operational.

```sql
-- SAFE: Non-blocking index creation.
CREATE INDEX CONCURRENTLY idx_orders_customer_id
    ON orders (customer_id);

-- With a partial index (useful for common query patterns):
CREATE INDEX CONCURRENTLY idx_orders_pending
    ON orders (created_at)
    WHERE status = 'pending';

-- With INCLUDE for covering index (PostgreSQL 11+):
CREATE INDEX CONCURRENTLY idx_orders_customer_covering
    ON orders (customer_id)
    INCLUDE (status, total_amount);

-- Unique index (also supports CONCURRENTLY):
CREATE UNIQUE INDEX CONCURRENTLY idx_users_email_unique
    ON users (lower(email));
```

### Handling Failed CONCURRENTLY Builds

If `CREATE INDEX CONCURRENTLY` fails or is canceled, it leaves an INVALID index that consumes space but is never used by the planner. Always check and clean up.

```sql
-- Check for invalid indexes:
SELECT indexrelid::regclass AS index_name,
       indrelid::regclass AS table_name,
       indisvalid
FROM pg_index
WHERE NOT indisvalid;

-- Drop invalid indexes:
DROP INDEX CONCURRENTLY idx_orders_customer_id;

-- Retry:
CREATE INDEX CONCURRENTLY idx_orders_customer_id
    ON orders (customer_id);
```

### Important Caveats

- `CREATE INDEX CONCURRENTLY` cannot run inside a transaction block.
- It requires two full table scans (slower than regular CREATE INDEX).
- It can fail if there are long-running transactions preventing it from acquiring its initial lock.
- Set `lock_timeout` to prevent indefinite waiting:

```sql
SET lock_timeout = '5s';
CREATE INDEX CONCURRENTLY idx_orders_customer_id ON orders (customer_id);
RESET lock_timeout;
```

---

## Table Rename Strategy

Renaming a table requires updating all application code simultaneously, which is risky. Use a multi-step approach with views.

```sql
-- Goal: Rename "orders" to "purchase_orders"

-- Step 1: Create the new table name as a view (application keeps using "orders").
-- Actually, we rename and create a view with the OLD name.

-- Deploy 1: Rename table and create compatibility view.
ALTER TABLE orders RENAME TO purchase_orders;
CREATE VIEW orders AS SELECT * FROM purchase_orders;

-- The view supports SELECT, INSERT, UPDATE, DELETE on simple views.
-- Application code continues to work unchanged.

-- Deploy 2: Update application code to use "purchase_orders".
-- All queries, ORMs, and references updated.

-- Deploy 3: Drop the compatibility view once old code is fully retired.
DROP VIEW orders;
```

### Column Rename Strategy

```sql
-- Goal: Rename "orders.qty" to "orders.quantity"

-- Deploy 1: Add new column.
ALTER TABLE orders ADD COLUMN quantity integer;

-- Deploy 2: Dual-write. Application writes to both columns.
-- Backfill existing data:
UPDATE orders SET quantity = qty WHERE quantity IS NULL;  -- In batches!

-- Deploy 3: Application reads from "quantity", writes to both.
-- Create a trigger for safety during transition:
CREATE OR REPLACE FUNCTION sync_quantity() RETURNS TRIGGER AS $$
BEGIN
    IF NEW.quantity IS NULL AND NEW.qty IS NOT NULL THEN
        NEW.quantity := NEW.qty;
    END IF;
    IF NEW.qty IS NULL AND NEW.quantity IS NOT NULL THEN
        NEW.qty := NEW.quantity;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_sync_quantity
    BEFORE INSERT OR UPDATE ON orders
    FOR EACH ROW EXECUTE FUNCTION sync_quantity();

-- Deploy 4: Application reads and writes only "quantity". Remove trigger.
DROP TRIGGER trg_sync_quantity ON orders;
DROP FUNCTION sync_quantity();

-- Deploy 5: Drop old column.
ALTER TABLE orders DROP COLUMN qty;
```

---

## Enum Type Modification

PostgreSQL enums are notoriously difficult to modify safely.

### Adding a New Enum Value

```sql
-- Adding a value is safe in PostgreSQL 9.1+ (no table rewrite).
-- However, it takes an ACCESS EXCLUSIVE lock on the enum type.
ALTER TYPE order_status ADD VALUE 'refunded';

-- Add at a specific position:
ALTER TYPE order_status ADD VALUE 'refunded' AFTER 'shipped';
ALTER TYPE order_status ADD VALUE 'processing' BEFORE 'shipped';

-- IF NOT EXISTS (PostgreSQL 9.3+):
ALTER TYPE order_status ADD VALUE IF NOT EXISTS 'refunded';

-- IMPORTANT: ALTER TYPE ADD VALUE cannot run inside a transaction block
-- in PostgreSQL < 12. In PG 12+ it can, but only if the new value is
-- not used in the same transaction.
```

### Removing or Renaming an Enum Value

PostgreSQL does not support `ALTER TYPE DROP VALUE` or `ALTER TYPE RENAME VALUE`. You must replace the entire type.

```sql
-- Strategy: Create new type, migrate column, drop old type.

-- Step 1: Create new enum type.
CREATE TYPE order_status_new AS ENUM (
    'pending', 'processing', 'shipped', 'delivered', 'cancelled'
    -- 'refunded' is removed; 'completed' renamed to 'delivered'
);

-- Step 2: Add new column with new type.
ALTER TABLE orders ADD COLUMN status_new order_status_new;

-- Step 3: Backfill (in batches for large tables).
UPDATE orders SET status_new = CASE
    WHEN status::text = 'completed' THEN 'delivered'::order_status_new
    ELSE status::text::order_status_new
END
WHERE status_new IS NULL;

-- Step 4: Application dual-writes to both columns.

-- Step 5: Swap columns.
ALTER TABLE orders ALTER COLUMN status_new SET NOT NULL;  -- After backfill
ALTER TABLE orders DROP COLUMN status;
ALTER TABLE orders RENAME COLUMN status_new TO status;

-- Step 6: Drop old type.
DROP TYPE order_status;
ALTER TYPE order_status_new RENAME TO order_status;
```

### Alternative: Use Text with CHECK Constraint

For frequently modified value sets, avoid enums entirely.

```sql
-- Instead of an enum:
ALTER TABLE orders ADD COLUMN status text NOT NULL DEFAULT 'pending';
ALTER TABLE orders ADD CONSTRAINT orders_status_check
    CHECK (status IN ('pending', 'processing', 'shipped', 'delivered', 'cancelled'));

-- To modify allowed values, just update the constraint:
ALTER TABLE orders DROP CONSTRAINT orders_status_check;
ALTER TABLE orders ADD CONSTRAINT orders_status_check
    CHECK (status IN ('pending', 'processing', 'shipped', 'delivered', 'cancelled', 'refunded'));
```

---

## Foreign Key Addition on Large Tables

Adding a foreign key on a large table requires validating every existing row, which takes an ACCESS EXCLUSIVE lock for the entire duration with the default approach.

```sql
-- BAD: Validates all rows under ACCESS EXCLUSIVE lock.
ALTER TABLE orders ADD CONSTRAINT fk_orders_customer
    FOREIGN KEY (customer_id) REFERENCES customers (id);

-- GOOD: Two-step approach (same pattern as NOT NULL).

-- Step 1: Add constraint NOT VALID (instant, no validation scan).
-- Takes ACCESS EXCLUSIVE lock very briefly (catalog update only).
ALTER TABLE orders
    ADD CONSTRAINT fk_orders_customer
    FOREIGN KEY (customer_id) REFERENCES customers (id)
    NOT VALID;

-- The constraint is enforced for NEW rows immediately.
-- Existing rows are not validated yet.

-- Step 2: Validate existing rows (holds SHARE UPDATE EXCLUSIVE lock,
-- does NOT block reads or writes).
ALTER TABLE orders VALIDATE CONSTRAINT fk_orders_customer;
```

### Pre-Validation Cleanup

Before validating, ensure there are no orphaned rows. Validation will fail if any row violates the constraint.

```sql
-- Find orphaned rows:
SELECT o.id, o.customer_id
FROM orders o
LEFT JOIN customers c ON c.id = o.customer_id
WHERE c.id IS NULL
    AND o.customer_id IS NOT NULL;

-- Fix orphaned rows (application-specific decision):
-- Option A: Set to NULL.
UPDATE orders SET customer_id = NULL
WHERE customer_id NOT IN (SELECT id FROM customers)
    AND customer_id IS NOT NULL;

-- Option B: Delete orphaned rows.
DELETE FROM orders
WHERE customer_id NOT IN (SELECT id FROM customers)
    AND customer_id IS NOT NULL;

-- Option C: Create placeholder customer records.
INSERT INTO customers (id, name)
SELECT DISTINCT o.customer_id, 'DELETED CUSTOMER'
FROM orders o
LEFT JOIN customers c ON c.id = o.customer_id
WHERE c.id IS NULL AND o.customer_id IS NOT NULL;
```

---

## Column Type Change Without Lock

Changing a column type typically rewrites the entire table under ACCESS EXCLUSIVE lock. For large tables, this is unacceptable.

### Strategy: Parallel Column with Trigger

```sql
-- Goal: Change orders.amount from INTEGER to NUMERIC(12,2)

-- Step 1: Add new column.
ALTER TABLE orders ADD COLUMN amount_new numeric(12,2);

-- Step 2: Create a trigger to keep columns in sync.
CREATE OR REPLACE FUNCTION sync_amount() RETURNS TRIGGER AS $$
BEGIN
    NEW.amount_new := NEW.amount;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_sync_amount
    BEFORE INSERT OR UPDATE ON orders
    FOR EACH ROW EXECUTE FUNCTION sync_amount();

-- Step 3: Backfill existing data (in batches).
DO $$
DECLARE
    batch_size INTEGER := 10000;
    updated INTEGER;
BEGIN
    LOOP
        UPDATE orders
        SET amount_new = amount
        WHERE id IN (
            SELECT id FROM orders
            WHERE amount_new IS NULL
            LIMIT batch_size
        );
        GET DIAGNOSTICS updated = ROW_COUNT;
        COMMIT;
        EXIT WHEN updated = 0;
        PERFORM pg_sleep(0.05);
    END LOOP;
END $$;

-- Step 4: Update application to read from amount_new.

-- Step 5: Swap columns.
DROP TRIGGER trg_sync_amount ON orders;
DROP FUNCTION sync_amount();
ALTER TABLE orders DROP COLUMN amount;
ALTER TABLE orders RENAME COLUMN amount_new TO amount;

-- Step 6: Recreate any indexes on the new column.
CREATE INDEX CONCURRENTLY idx_orders_amount ON orders (amount);
```

### Safe Type Changes (No Table Rewrite)

Some type changes are safe because they only update catalog metadata:

```sql
-- Safe: Increasing varchar length (no rewrite).
ALTER TABLE users ALTER COLUMN name TYPE varchar(500);  -- Was varchar(100)

-- Safe: varchar(n) to text (no rewrite).
ALTER TABLE users ALTER COLUMN name TYPE text;

-- Safe: Removing varchar limit (no rewrite).
ALTER TABLE users ALTER COLUMN name TYPE varchar;

-- UNSAFE (causes table rewrite):
-- - Changing numeric precision (e.g., numeric(10,2) to numeric(12,4))
-- - Changing integer to bigint
-- - Changing text to integer
-- - Changing timestamp to timestamptz
```

---

## Large Data Migration in Batches

### Pattern: Migrating Data Between Tables

```sql
-- Goal: Move orders older than 1 year to an archive table.

-- Create archive table with same structure:
CREATE TABLE orders_archive (LIKE orders INCLUDING ALL);

-- Batch migration script:
DO $$
DECLARE
    batch_size INTEGER := 5000;
    moved INTEGER;
    total_moved BIGINT := 0;
    cutoff_date TIMESTAMP := NOW() - INTERVAL '1 year';
BEGIN
    LOOP
        -- Move a batch using a CTE (atomic per batch).
        WITH to_archive AS (
            SELECT id FROM orders
            WHERE created_at < cutoff_date
            LIMIT batch_size
            FOR UPDATE SKIP LOCKED
        ),
        deleted AS (
            DELETE FROM orders
            WHERE id IN (SELECT id FROM to_archive)
            RETURNING *
        )
        INSERT INTO orders_archive
        SELECT * FROM deleted;

        GET DIAGNOSTICS moved = ROW_COUNT;
        total_moved := total_moved + moved;
        RAISE NOTICE 'Moved % rows (total: %)', moved, total_moved;
        COMMIT;

        EXIT WHEN moved = 0;
        PERFORM pg_sleep(0.1);
    END LOOP;
END $$;
```

### Pattern: Transforming Data In-Place

```sql
-- Goal: Normalize phone numbers in a 50M-row table.

-- Add processed tracking column:
ALTER TABLE contacts ADD COLUMN phone_normalized boolean DEFAULT false;

-- Batch process:
DO $$
DECLARE
    batch_size INTEGER := 10000;
    processed INTEGER;
BEGIN
    LOOP
        UPDATE contacts
        SET
            phone = regexp_replace(phone, '[^0-9+]', '', 'g'),
            phone_normalized = true
        WHERE id IN (
            SELECT id FROM contacts
            WHERE phone_normalized = false
            LIMIT batch_size
        );

        GET DIAGNOSTICS processed = ROW_COUNT;
        COMMIT;
        EXIT WHEN processed = 0;
        PERFORM pg_sleep(0.05);
    END LOOP;
END $$;

-- Clean up tracking column:
ALTER TABLE contacts DROP COLUMN phone_normalized;
```

---

## Multi-Step Migration Workflow

### Standard Migration Lifecycle

```
Phase 1: EXPAND (Additive changes only)
  - Add new columns (nullable, with defaults)
  - Add new tables
  - Add new indexes (CONCURRENTLY)
  - Add new constraints (NOT VALID)
  Goal: Database supports BOTH old and new application code.

Phase 2: MIGRATE (Application deployment)
  - Deploy new application code that writes to new schema
  - Old application code continues to work (backward compatible)
  - Run data backfill scripts for new columns

Phase 3: CONTRACT (Remove old schema)
  - Validate constraints (ALTER TABLE ... VALIDATE CONSTRAINT)
  - Add NOT NULL constraints
  - Drop old columns
  - Drop old tables
  - Drop compatibility views and triggers
  Goal: Database is clean; old schema is removed.
```

### Example: Adding an Address Normalization

```
Migration 1 (EXPAND):
  ALTER TABLE addresses ADD COLUMN street_normalized text;
  ALTER TABLE addresses ADD COLUMN city_normalized text;
  ALTER TABLE addresses ADD COLUMN geocoded boolean DEFAULT false;

Migration 2 (MIGRATE - Deploy App v2):
  - App v2 writes to both old and new columns.
  - Background job normalizes existing addresses in batches.

Migration 3 (CONTRACT - After backfill complete):
  ALTER TABLE addresses ADD CONSTRAINT chk_normalized
      CHECK (street_normalized IS NOT NULL) NOT VALID;
  ALTER TABLE addresses VALIDATE CONSTRAINT chk_normalized;
  ALTER TABLE addresses ALTER COLUMN street_normalized SET NOT NULL;
  ALTER TABLE addresses DROP CONSTRAINT chk_normalized;
```

---

## Blue-Green Database Deployment

Blue-green deployment for databases is significantly more complex than for stateless application servers because the database contains state.

### Approach 1: Shared Database, Schema Versioning

Both blue and green application versions point to the same database. Migrations must be backward-compatible.

```
                    ┌──────────────┐
                    │   Load       │
                    │   Balancer   │
                    └──────┬───────┘
                           │
              ┌────────────┴────────────┐
              │                         │
      ┌───────┴───────┐       ┌────────┴────────┐
      │  Blue (v1)    │       │  Green (v2)     │
      │  App Servers  │       │  App Servers    │
      └───────┬───────┘       └────────┬────────┘
              │                         │
              └────────────┬────────────┘
                           │
                   ┌───────┴───────┐
                   │  Shared DB    │
                   │  (versioned   │
                   │   schema)     │
                   └───────────────┘
```

Deployment steps:
1. Run EXPAND migrations (additive only).
2. Deploy Green (v2) application. Both Blue and Green work with the current schema.
3. Shift traffic from Blue to Green gradually.
4. Once Blue is fully drained, run CONTRACT migrations.
5. Decommission Blue.

### Approach 2: Database Replication with Cutover

Use logical replication to maintain two databases in sync during transition.

```
Step 1: Set up logical replication from Blue DB to Green DB.
  - Green DB has the new schema (additive changes applied).
  - Logical replication keeps data in sync.

Step 2: Deploy Green application pointing to Green DB (read-only traffic).

Step 3: Cutover:
  - Stop writes to Blue DB.
  - Wait for replication lag to reach zero.
  - Switch application to Green DB for writes.
  - Redirect all traffic to Green.

Step 4: Decommission Blue DB.
```

```sql
-- On Blue (source) database:
CREATE PUBLICATION blue_to_green FOR ALL TABLES;

-- On Green (target) database:
CREATE SUBSCRIPTION green_sub
    CONNECTION 'host=blue-db port=5432 dbname=myapp'
    PUBLICATION blue_to_green;

-- Monitor replication lag:
SELECT
    slot_name,
    confirmed_flush_lsn,
    pg_current_wal_lsn(),
    pg_wal_lsn_diff(pg_current_wal_lsn(), confirmed_flush_lsn) AS lag_bytes
FROM pg_replication_slots;
```

---

## Schema Versioning Strategy

### Migration File Naming Convention

```
migrations/
  V001__create_users_table.sql
  V002__create_orders_table.sql
  V003__add_orders_discount_column.sql
  V004__backfill_orders_discount.sql
  V005__add_orders_discount_not_null.sql
  V006__create_idx_orders_customer_id.sql
```

### Version Tracking Table

```sql
CREATE TABLE schema_migrations (
    version     integer PRIMARY KEY,
    name        text NOT NULL,
    applied_at  timestamptz NOT NULL DEFAULT NOW(),
    duration_ms integer,
    checksum    text NOT NULL,  -- MD5/SHA256 of migration file
    applied_by  text NOT NULL DEFAULT current_user
);

-- Query current version:
SELECT MAX(version) AS current_version FROM schema_migrations;
```

### Migration Framework Recommendations

| Framework       | Language   | Key Features                                      |
|----------------|-----------|---------------------------------------------------|
| Flyway          | Java/CLI  | SQL or Java migrations, checksum validation        |
| Liquibase       | Java/CLI  | XML/YAML/SQL, rollback support, diff generation    |
| Alembic         | Python    | SQLAlchemy integration, auto-generation, branching |
| golang-migrate  | Go        | CLI and library, many database drivers             |
| Sqitch          | Perl/CLI  | Dependency-based ordering, revert scripts          |
| dbmate          | Go        | Simple CLI, SQL-only, framework-agnostic           |

### Idempotent Migration Pattern

Write migrations that can safely be re-run without error.

```sql
-- Idempotent table creation:
CREATE TABLE IF NOT EXISTS users (
    id bigserial PRIMARY KEY,
    email text NOT NULL
);

-- Idempotent column addition:
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'users' AND column_name = 'phone'
    ) THEN
        ALTER TABLE users ADD COLUMN phone text;
    END IF;
END $$;

-- Idempotent index creation:
CREATE INDEX IF NOT EXISTS idx_users_email ON users (email);

-- Idempotent constraint addition:
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'chk_users_email_format'
    ) THEN
        ALTER TABLE users ADD CONSTRAINT chk_users_email_format
            CHECK (email ~ '^[^@]+@[^@]+\.[^@]+$');
    END IF;
END $$;
```

---

## Migration Testing Checklist

### Before Writing the Migration

- [ ] **Identify the lock level** required by each DDL statement.
- [ ] **Estimate table sizes** in production (row count, on-disk size).
- [ ] **Check for dependent objects** (views, functions, triggers, foreign keys, policies).
- [ ] **Determine if the migration is backward-compatible** with the current application version.
- [ ] **Plan the rollback strategy** for each step.

### During Development

- [ ] **Test on production-sized data.** Use `pg_dump --schema-only` plus synthetic data, or a production replica.
- [ ] **Measure execution time** of each statement against realistic data volumes.
- [ ] **Verify no exclusive locks** on hot tables during peak operations.
  ```sql
  -- Check what locks a migration acquires:
  BEGIN;
  SET lock_timeout = '100ms';
  -- Run your DDL here
  SELECT locktype, relation::regclass, mode, granted
  FROM pg_locks WHERE pid = pg_backend_pid();
  ROLLBACK;
  ```
- [ ] **Test with concurrent traffic.** Use pgbench or your load testing tool while running migrations.
- [ ] **Verify CONCURRENTLY indexes** are valid after creation.
- [ ] **Test idempotency.** Run the migration twice; the second run should be a no-op or succeed without error.

### Before Deploying to Production

- [ ] **Run on staging** with production-like data and traffic patterns.
- [ ] **Set `statement_timeout` and `lock_timeout`** to prevent runaway migrations.
  ```sql
  SET statement_timeout = '30min';
  SET lock_timeout = '5s';
  ```
- [ ] **Schedule during low-traffic windows** for CONTRACT migrations (even if they are non-blocking, reduced traffic means less WAL generation and faster completion).
- [ ] **Ensure sufficient disk space** for CONCURRENTLY index builds (requires ~2x the index size temporarily).
- [ ] **Notify the team.** Even zero-downtime migrations deserve a heads-up.
- [ ] **Have a rollback script ready.** Know exactly what to run if something goes wrong.

### After Deploying

- [ ] **Monitor replication lag** on replicas.
- [ ] **Check for lock contention** in `pg_stat_activity`.
  ```sql
  SELECT pid, wait_event_type, wait_event, state, query
  FROM pg_stat_activity
  WHERE wait_event_type = 'Lock';
  ```
- [ ] **Verify query performance** has not regressed (check pg_stat_statements).
- [ ] **Run ANALYZE** on affected tables if the migration changed data distribution.
  ```sql
  ANALYZE orders;
  ```
- [ ] **Confirm application health metrics** (error rates, latency, throughput) are stable.
- [ ] **Update schema documentation** and ER diagrams.

---

## Common Pitfalls

### 1. Adding a Default to an Existing Column (PG < 11)

```sql
-- PG 10 and earlier: REWRITES TABLE.
ALTER TABLE orders ALTER COLUMN status SET DEFAULT 'pending';
-- Use: UPDATE in batches + application-level default instead.
```

### 2. Running Migrations Inside a Single Transaction

```sql
-- Some tools wrap all migrations in one transaction.
-- CREATE INDEX CONCURRENTLY cannot run inside a transaction.
-- ALTER TYPE ... ADD VALUE cannot run inside a transaction (PG < 12).
-- Ensure your migration tool supports non-transactional migrations.
```

### 3. Not Setting lock_timeout

```sql
-- Without lock_timeout, ALTER TABLE waits indefinitely for the lock.
-- Meanwhile, all subsequent queries on the table queue behind it.
-- This cascading lock wait can bring down the application.
SET lock_timeout = '5s';
ALTER TABLE orders ADD COLUMN new_col text;
-- If lock not acquired in 5s, statement fails instead of blocking.
```

### 4. Dropping a Column That Application Still References

```sql
-- Always verify no application code references the column before dropping.
-- Use the EXPAND-MIGRATE-CONTRACT pattern. Drop is always the last step.
```

### 5. Forgetting to Update Indexes After Column Changes

```sql
-- If you rename or replace a column, existing indexes on the old column
-- are either dropped (if column is dropped) or become orphaned.
-- Always plan index recreation as part of the migration.
```
