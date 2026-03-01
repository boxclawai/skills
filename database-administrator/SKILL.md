---
name: database-administrator
version: "1.0.0"
description: "Database administration expert: PostgreSQL, MySQL, MongoDB, Redis, query optimization (EXPLAIN ANALYZE), index design, schema migrations, replication (primary-replica, multi-master), backup/recovery strategies, connection pooling, partitioning, and database monitoring. Use when: (1) optimizing slow queries, (2) designing database schemas or indexes, (3) planning migrations or upgrades, (4) setting up replication or high availability, (5) troubleshooting database performance, (6) configuring backups and recovery procedures. NOT for: application business logic, frontend, or infrastructure outside databases."
tags: [postgresql, mysql, mongodb, redis, query-optimization, indexing, replication, backup, migration, monitoring]
author: "boxclaw"
references:
  - references/postgresql-tuning.md
  - references/migration-patterns.md
metadata:
  boxclaw:
    emoji: "🗄️"
    category: "programming-role"
---

# Database Administrator

Expert guidance for database design, optimization, and operations.

## Core Competencies

### 1. Schema Design Principles

```
Normalization (eliminate redundancy):
  1NF: Atomic values, no repeating groups
  2NF: No partial dependencies on composite keys
  3NF: No transitive dependencies
  BCNF: Every determinant is a candidate key

When to denormalize:
  - Read-heavy workloads (pre-join for performance)
  - Reporting/analytics (materialized views)
  - Caching layer (Redis denormalized structures)
  - Document stores (embed for single-query access)

Naming Conventions:
  Tables:  plural, snake_case (users, order_items)
  Columns: snake_case, descriptive (created_at, user_id)
  PKs:     id (BIGINT or UUID)
  FKs:     referenced_table_singular_id (user_id, order_id)
  Indexes: idx_table_columns (idx_users_email)
  Constraints: chk_table_rule (chk_orders_amount_positive)
```

### 2. Index Strategy

```
When to index:
  ✓ WHERE clause columns (frequent filters)
  ✓ JOIN columns (foreign keys)
  ✓ ORDER BY / GROUP BY columns
  ✓ Unique constraints
  ✓ Columns in partial indexes (filtered queries)

When NOT to index:
  ✗ Small tables (< 1000 rows, seq scan is faster)
  ✗ Write-heavy columns (index maintenance cost)
  ✗ Low cardinality (boolean, status with 3 values)
  ✗ Columns rarely queried

Index Types (PostgreSQL):
  B-tree:    Default. Equality + range (=, <, >, BETWEEN)
  Hash:      Equality only (faster for = comparisons)
  GIN:       Full-text search, JSONB, arrays
  GiST:      Geometry, range types, proximity
  BRIN:      Large ordered datasets (time series, logs)
```

#### Composite Index Ordering

```sql
-- Rule: Equality first, then range, then sort
-- Query: WHERE status = 'active' AND created_at > '2025-01-01' ORDER BY name

CREATE INDEX idx_orders_status_created_name
ON orders (status, created_at, name);

-- The "left prefix" rule: index on (a, b, c) helps:
--   WHERE a = ?                    ✓
--   WHERE a = ? AND b = ?          ✓
--   WHERE a = ? AND b = ? AND c = ? ✓
--   WHERE b = ?                    ✗ (a not in query)
--   WHERE a = ? AND c = ?          Partial (only a used)
```

### 3. Query Optimization

```sql
-- Step 1: EXPLAIN ANALYZE
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT u.name, COUNT(o.id) AS order_count
FROM users u
JOIN orders o ON o.user_id = u.id
WHERE u.status = 'active'
  AND o.created_at > '2025-01-01'
GROUP BY u.name
ORDER BY order_count DESC
LIMIT 20;

-- What to look for:
--   Seq Scan on large tables → needs index
--   Nested Loop with large sets → consider Hash Join
--   Sort with high memory → add index for ordering
--   Rows estimated vs actual → stale statistics (ANALYZE)
```

#### Common Optimization Patterns

```sql
-- N+1 problem: replace loop queries with JOIN
-- BAD:  for each user: SELECT * FROM orders WHERE user_id = ?
-- GOOD: SELECT u.*, o.* FROM users u JOIN orders o ON o.user_id = u.id

-- Pagination: use keyset (cursor) instead of OFFSET
-- BAD:  SELECT * FROM orders ORDER BY id LIMIT 20 OFFSET 10000
-- GOOD: SELECT * FROM orders WHERE id > $last_id ORDER BY id LIMIT 20

-- Count optimization
-- BAD:  SELECT COUNT(*) FROM huge_table WHERE status = 'active'
-- GOOD: Use partial index or materialized count table

-- Avoid SELECT *
-- BAD:  SELECT * FROM users (loads all columns including BLOBs)
-- GOOD: SELECT id, name, email FROM users (only needed columns)
```

### 4. Partitioning

```sql
-- PostgreSQL declarative partitioning
-- Use when: table > 100M rows, time-series data, archival needs

-- Range partitioning (by date)
CREATE TABLE events (
  id          BIGINT GENERATED ALWAYS AS IDENTITY,
  event_type  VARCHAR(50),
  payload     JSONB,
  created_at  TIMESTAMPTZ NOT NULL
) PARTITION BY RANGE (created_at);

CREATE TABLE events_2025_q1 PARTITION OF events
  FOR VALUES FROM ('2025-01-01') TO ('2025-04-01');
CREATE TABLE events_2025_q2 PARTITION OF events
  FOR VALUES FROM ('2025-04-01') TO ('2025-07-01');

-- Benefits:
--   Partition pruning: queries hitting one partition skip others
--   Easy archival: DROP PARTITION instead of DELETE
--   Parallel scans across partitions
--   Independent VACUUM per partition
```

### 5. Replication & High Availability

```
PostgreSQL HA:
  Primary → Streaming Replica(s)
  Sync:   synchronous_commit = on (zero data loss)
  Async:  Faster writes, slight lag risk

Failover:
  Patroni + etcd:     Automatic leader election
  PgBouncer:          Connection pooling + routing
  HAProxy:            Load balance read replicas

Read Scaling:
  Primary:  All writes + critical reads
  Replica:  Read-only queries, reporting, analytics
  App:      Route by query type (write → primary, read → replica)

Connection Pooling:
  PgBouncer:
    Transaction mode:  Best for most apps (conn per txn)
    Session mode:      For session-level features (LISTEN/NOTIFY)
    Pool size:         cores * 2 + effective_spindle_count
                       Typical: 20-50 connections per pool
```

### 6. Backup & Recovery

```
Strategy:
  Full backup:        Daily (pg_basebackup or pg_dump)
  WAL archiving:      Continuous (Point-in-Time Recovery)
  Logical backup:     Weekly (pg_dump for schema + portability)
  Test restores:      Monthly (verify backup actually works!)

PostgreSQL:
  # Physical backup (fastest restore)
  pg_basebackup -D /backups/base -Fp -Xs -P

  # Logical backup (portable, selective)
  pg_dump -Fc -f backup.dump mydb
  pg_restore -d mydb_restored backup.dump

  # Point-in-Time Recovery
  recovery_target_time = '2025-03-01 14:30:00'

Retention:
  Daily backups:   Keep 7 days
  Weekly backups:  Keep 4 weeks
  Monthly backups: Keep 12 months
  WAL segments:    Keep 7 days minimum
```

### 7. Monitoring

```
Key Metrics:
  Connections:      Active / idle / waiting / max
  Query Performance: p50, p95, p99 latency
  Cache Hit Ratio:  shared_buffers hit rate (target > 99%)
  Replication Lag:  Bytes/seconds behind primary
  Disk I/O:         Read/write IOPS, throughput
  Lock Waits:       Blocked queries, deadlocks
  Table Bloat:      Dead tuples, autovacuum activity

Queries:
  -- Active queries
  SELECT pid, age(clock_timestamp(), query_start), query
  FROM pg_stat_activity WHERE state = 'active';

  -- Cache hit ratio
  SELECT sum(heap_blks_hit) / sum(heap_blks_hit + heap_blks_read)
  FROM pg_statio_user_tables;

  -- Table bloat
  SELECT relname, n_dead_tup, last_autovacuum
  FROM pg_stat_user_tables ORDER BY n_dead_tup DESC;

  -- Slow queries (pg_stat_statements)
  SELECT query, calls, mean_exec_time, total_exec_time
  FROM pg_stat_statements ORDER BY mean_exec_time DESC LIMIT 20;

Tools:
  pg_stat_statements:  Query performance tracking
  pgHero:              Dashboard for PostgreSQL
  Prometheus + Grafana: Alerting + visualization
  pgBadger:            Log analysis and reports
```

## Quick Commands

```bash
# PostgreSQL
psql -h localhost -U admin -d mydb
pg_dump -Fc mydb > backup.dump
pg_restore -d mydb backup.dump
vacuumdb --analyze --verbose mydb

# MySQL
mysql -h localhost -u root -p mydb
mysqldump --single-transaction mydb > backup.sql
mysqlcheck --optimize mydb

# Redis
redis-cli INFO memory
redis-cli --bigkeys
redis-cli SLOWLOG GET 10

# MongoDB
mongosh --eval "db.stats()"
mongodump --db mydb --out /backups/
mongorestore --db mydb /backups/mydb/
```

## References

- **PostgreSQL tuning**: See [references/postgresql-tuning.md](references/postgresql-tuning.md)
- **Migration patterns**: See [references/migration-patterns.md](references/migration-patterns.md)
