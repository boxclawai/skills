# PostgreSQL Performance Tuning Reference

## Table of Contents

1. [postgresql.conf Key Settings](#postgresqlconf-key-settings)
2. [Connection Tuning with PgBouncer](#connection-tuning-with-pgbouncer)
3. [VACUUM and ANALYZE Strategies](#vacuum-and-analyze-strategies)
4. [Index Maintenance](#index-maintenance)
5. [pg_stat_statements Setup and Analysis](#pg_stat_statements-setup-and-analysis)
6. [Common Slow Query Patterns and Fixes](#common-slow-query-patterns-and-fixes)
7. [EXPLAIN ANALYZE Reading Guide](#explain-analyze-reading-guide)
8. [Table Bloat Detection and Remediation](#table-bloat-detection-and-remediation)
9. [WAL Configuration for Different Workloads](#wal-configuration-for-different-workloads)
10. [Quick Reference: Settings by Server RAM](#quick-reference-settings-by-server-ram)

---

## postgresql.conf Key Settings

### Memory Configuration

```ini
# ============================================================================
# MEMORY SETTINGS
# ============================================================================

# shared_buffers: Main shared memory area for caching table and index data.
# Recommendation: 25% of total system RAM, but rarely more than 8GB on
# dedicated database servers. Beyond 8GB, diminishing returns as the OS
# page cache handles the rest.
#
# For a 64GB server:
shared_buffers = 16GB

# effective_cache_size: Estimate of total memory available for disk caching
# (shared_buffers + OS page cache). Used by the query planner to estimate
# the cost of index scans vs sequential scans. Does NOT allocate memory.
# Recommendation: 50-75% of total system RAM.
#
# For a 64GB server:
effective_cache_size = 48GB

# work_mem: Memory per-operation (sort, hash join, etc.) per-connection.
# A single complex query can use multiple work_mem allocations.
# Be conservative: total_connections * avg_operations_per_query * work_mem
# should not exceed available RAM.
# Recommendation: (Total RAM - shared_buffers) / (max_connections * 3)
#
# For a 64GB server with 200 connections:
work_mem = 64MB

# maintenance_work_mem: Memory for maintenance operations (VACUUM, CREATE INDEX,
# ALTER TABLE ADD FOREIGN KEY). Only a few run at once so this can be larger.
# Recommendation: 1-2GB for servers with 64GB+ RAM.
maintenance_work_mem = 2GB

# huge_pages: Use Linux huge pages to reduce TLB misses. Requires OS-level
# configuration (vm.nr_hugepages in sysctl).
# Recommendation: 'try' or 'on' for production servers.
huge_pages = try
```

### WAL (Write-Ahead Log) Configuration

```ini
# ============================================================================
# WAL SETTINGS
# ============================================================================

# wal_buffers: Shared memory for WAL data not yet written to disk.
# Recommendation: 1/32 of shared_buffers, capped at 64MB. Setting to -1
# lets PostgreSQL auto-tune based on shared_buffers.
wal_buffers = -1

# wal_level: Determines how much information is written to WAL.
# 'replica' for streaming replication (default in PG 10+).
# 'logical' for logical replication / change data capture.
# 'minimal' for standalone servers with no replication (fastest writes).
wal_level = replica

# max_wal_size: Maximum WAL size before a checkpoint is forced.
# Larger values reduce checkpoint frequency but increase crash recovery time.
# Recommendation: 2-8GB for OLTP, 16-64GB for batch/ETL workloads.
max_wal_size = 4GB

# min_wal_size: Minimum WAL size to retain. Prevents excessive WAL recycling
# when write volume varies.
min_wal_size = 1GB

# wal_compression: Compress full-page writes in WAL. Reduces WAL volume
# at the cost of CPU. Usually beneficial on I/O-bound systems.
wal_compression = on
```

### Checkpoint Settings

```ini
# ============================================================================
# CHECKPOINT SETTINGS
# ============================================================================

# checkpoint_timeout: Maximum time between automatic checkpoints.
# Recommendation: 10-30 minutes. Longer intervals reduce I/O but
# increase crash recovery time.
checkpoint_timeout = 15min

# checkpoint_completion_target: Fraction of checkpoint_timeout over which
# checkpoint writes are spread. Higher values reduce I/O spikes.
# Recommendation: 0.9 (spread writes over 90% of the interval).
checkpoint_completion_target = 0.9

# checkpoint_warning: Log a warning if checkpoints happen more frequently
# than this interval due to WAL volume exceeding max_wal_size.
checkpoint_warning = 30s
```

### Planner Cost Settings

```ini
# ============================================================================
# PLANNER / COST SETTINGS
# ============================================================================

# random_page_cost: Estimated cost of a non-sequential disk page fetch.
# Default is 4.0 (spinning disk). For SSDs, set to 1.1-1.5.
# This heavily influences whether the planner chooses index scans vs seq scans.
random_page_cost = 1.1

# seq_page_cost: Cost of a sequential disk page fetch. Usually left at 1.0.
seq_page_cost = 1.0

# effective_io_concurrency: Number of concurrent I/O operations the disk
# subsystem can handle. For SSDs or RAID arrays, set higher.
# Recommendation: 200 for SSDs, 2-4 for spinning disks.
effective_io_concurrency = 200

# cpu_tuple_cost / cpu_index_tuple_cost / cpu_operator_cost:
# Usually left at defaults unless you have specific benchmarking data.
```

### Parallel Query Settings

```ini
# ============================================================================
# PARALLEL QUERY SETTINGS
# ============================================================================

# max_parallel_workers_per_gather: Maximum workers for a single Gather node.
# Recommendation: 2-4 for OLTP, up to number of cores for analytics.
max_parallel_workers_per_gather = 4

# max_parallel_workers: Total parallel workers across all queries.
# Recommendation: Number of CPU cores.
max_parallel_workers = 8

# max_parallel_maintenance_workers: Workers for parallel index builds and
# VACUUM operations. Recommendation: 2-4.
max_parallel_maintenance_workers = 4

# parallel_tuple_cost: Planner estimate for transferring a tuple from
# worker to leader. Lower values make the planner favor parallelism.
parallel_tuple_cost = 0.01

# min_parallel_table_scan_size: Minimum table size to consider parallel scan.
min_parallel_table_scan_size = 8MB
```

### Logging for Performance Analysis

```ini
# ============================================================================
# LOGGING SETTINGS (PERFORMANCE-RELEVANT)
# ============================================================================

# log_min_duration_statement: Log queries taking longer than this.
# Set to 0 to log all queries (high overhead). Set to a reasonable threshold.
log_min_duration_statement = 500ms

# log_checkpoints: Log checkpoint activity. Essential for tuning.
log_checkpoints = on

# log_lock_waits: Log when sessions wait longer than deadlock_timeout for a lock.
log_lock_waits = on

# log_temp_files: Log creation of temporary files above this size.
# 0 logs all temp files. Temp files indicate work_mem is too low.
log_temp_files = 0

# log_autovacuum_min_duration: Log autovacuum runs taking longer than this.
log_autovacuum_min_duration = 0

# track_io_timing: Enables per-query I/O timing in EXPLAIN and pg_stat_statements.
# Small overhead but extremely valuable for diagnosis.
track_io_timing = on

# track_functions: Track function call statistics.
track_functions = all
```

---

## Connection Tuning with PgBouncer

### Why PgBouncer

Each PostgreSQL backend process consumes approximately 5-10MB of RAM. With 500+ connections, memory pressure and context-switching overhead become significant. PgBouncer acts as a lightweight connection pooler sitting between applications and PostgreSQL.

### PgBouncer Configuration (pgbouncer.ini)

```ini
[databases]
# Map logical database names to PostgreSQL targets.
# You can route different apps to different databases or read replicas.
myapp = host=10.0.1.100 port=5432 dbname=myapp_production
myapp_readonly = host=10.0.1.101 port=5432 dbname=myapp_production

[pgbouncer]
# Listen address and port for client connections.
listen_addr = 0.0.0.0
listen_port = 6432

# Authentication type. 'md5' uses password from auth_file.
# 'hba' delegates to pg_hba.conf-style rules.
auth_type = md5
auth_file = /etc/pgbouncer/userlist.txt

# -----------------------------------------------------------------------
# Pool Mode: The most critical setting.
# -----------------------------------------------------------------------
# 'transaction': Connection returned to pool after each transaction.
#   Best throughput. Cannot use session-level features (prepared statements,
#   SET commands, advisory locks, LISTEN/NOTIFY, temp tables).
#
# 'session': Connection held until client disconnects.
#   Full compatibility. Least efficient pooling.
#
# 'statement': Connection returned after each statement.
#   Most aggressive pooling. Cannot use multi-statement transactions.
#
# Recommendation: 'transaction' for most applications.
pool_mode = transaction

# -----------------------------------------------------------------------
# Pool Size Settings
# -----------------------------------------------------------------------
# default_pool_size: Connections per user/database pair.
default_pool_size = 25

# min_pool_size: Keep at least this many connections open.
min_pool_size = 5

# reserve_pool_size: Extra connections for burst traffic.
reserve_pool_size = 5

# reserve_pool_timeout: Seconds to wait before using reserve pool.
reserve_pool_timeout = 3

# max_client_conn: Maximum client connections PgBouncer accepts.
max_client_conn = 1000

# max_db_connections: Total connections to a single database across all pools.
# Should not exceed PostgreSQL max_connections minus reserved connections.
max_db_connections = 100

# -----------------------------------------------------------------------
# Timeout Settings
# -----------------------------------------------------------------------
# server_idle_timeout: Close idle server connections after this duration.
server_idle_timeout = 600

# client_idle_timeout: Disconnect idle clients after this duration.
# 0 = disabled.
client_idle_timeout = 0

# query_timeout: Cancel queries running longer than this.
# 0 = disabled. Use application-level timeouts instead.
query_timeout = 0

# query_wait_timeout: Maximum time a client waits for a server connection.
query_wait_timeout = 120

# -----------------------------------------------------------------------
# Logging
# -----------------------------------------------------------------------
log_connections = 1
log_disconnections = 1
log_pooler_errors = 1
stats_period = 60
```

### PgBouncer Auth File Format

```
# /etc/pgbouncer/userlist.txt
# Format: "username" "password_or_md5hash"
"myapp_user" "md5abcdef1234567890abcdef12345678"
"readonly_user" "md5fedcba0987654321fedcba09876543"
```

### PostgreSQL max_connections with PgBouncer

```ini
# In postgresql.conf, set max_connections much lower when using PgBouncer.
# PgBouncer multiplexes hundreds of application connections onto fewer
# database connections.
#
# Formula: max_connections = (pgbouncer_pools * default_pool_size) + superuser_reserved + monitoring
# Example: (4 pools * 25) + 3 + 5 = 108
max_connections = 120
superuser_reserved_connections = 3
```

---

## VACUUM and ANALYZE Strategies

### How VACUUM Works

PostgreSQL uses MVCC (Multi-Version Concurrency Control). When a row is updated or deleted, the old version is not immediately removed. VACUUM reclaims space from dead tuples and prevents transaction ID wraparound.

### Autovacuum Configuration

```ini
# ============================================================================
# AUTOVACUUM SETTINGS
# ============================================================================

autovacuum = on

# autovacuum_max_workers: Number of concurrent autovacuum processes.
# Recommendation: 3-5 for most workloads.
autovacuum_max_workers = 5

# autovacuum_naptime: Delay between autovacuum runs on each database.
autovacuum_naptime = 30s

# -----------------------------------------------------------------------
# VACUUM Thresholds
# -----------------------------------------------------------------------
# A table is vacuumed when:
#   dead_tuples > autovacuum_vacuum_threshold +
#                 autovacuum_vacuum_scale_factor * table_rows
#
# Default: 50 + 0.2 * table_rows
# For a 10M row table: 50 + 2,000,000 = 2,000,050 dead tuples before vacuum
# This is too high for large tables.

# Global defaults:
autovacuum_vacuum_threshold = 50
autovacuum_vacuum_scale_factor = 0.02   # Lowered from default 0.2

# ANALYZE Thresholds (same formula pattern):
autovacuum_analyze_threshold = 50
autovacuum_analyze_scale_factor = 0.01  # Lowered from default 0.1

# -----------------------------------------------------------------------
# Cost-Based VACUUM Delay
# -----------------------------------------------------------------------
# Controls how aggressively VACUUM runs. Higher cost_limit = faster VACUUM
# but more I/O impact. Lower cost_delay = faster VACUUM.
autovacuum_vacuum_cost_delay = 2ms     # Default: 2ms (was 20ms before PG 12)
autovacuum_vacuum_cost_limit = 1000    # Default: -1 (uses vacuum_cost_limit = 200)
```

### Per-Table Autovacuum Tuning

```sql
-- For high-churn tables (e.g., session tables, job queues), be more aggressive:
ALTER TABLE sessions SET (
    autovacuum_vacuum_scale_factor = 0.01,
    autovacuum_vacuum_threshold = 100,
    autovacuum_analyze_scale_factor = 0.005,
    autovacuum_vacuum_cost_delay = 0,
    autovacuum_vacuum_cost_limit = 2000
);

-- For append-only tables (e.g., audit logs), VACUUM is less critical:
ALTER TABLE audit_logs SET (
    autovacuum_vacuum_scale_factor = 0.1,
    autovacuum_enabled = true
);

-- For tables approaching transaction ID wraparound, force aggressive vacuum:
-- Check wraparound risk:
SELECT
    schemaname,
    relname,
    age(relfrozenxid) AS xid_age,
    pg_size_pretty(pg_total_relation_size(oid)) AS total_size
FROM pg_stat_user_tables
JOIN pg_class USING (relname)
WHERE age(relfrozenxid) > 500000000  -- Warning threshold
ORDER BY age(relfrozenxid) DESC;
```

### Manual VACUUM Operations

```sql
-- Standard VACUUM: Reclaims space, does not return to OS. Non-blocking.
VACUUM VERBOSE my_table;

-- VACUUM FULL: Rewrites entire table, returns space to OS.
-- WARNING: Takes an ACCESS EXCLUSIVE lock. Blocks all reads and writes.
-- Use pg_repack instead for production tables.
VACUUM FULL VERBOSE my_table;

-- VACUUM ANALYZE: Vacuum and update planner statistics in one pass.
VACUUM ANALYZE my_table;

-- ANALYZE only: Update statistics without vacuuming.
-- Run after bulk inserts or significant data changes.
ANALYZE VERBOSE my_table;

-- Monitor VACUUM progress (PostgreSQL 9.6+):
SELECT
    p.pid,
    a.query,
    p.phase,
    p.heap_blks_total,
    p.heap_blks_scanned,
    p.heap_blks_vacuumed,
    round(100.0 * p.heap_blks_vacuumed / NULLIF(p.heap_blks_total, 0), 1) AS pct_complete
FROM pg_stat_progress_vacuum p
JOIN pg_stat_activity a USING (pid);
```

---

## Index Maintenance

### Monitoring Index Usage

```sql
-- Find unused indexes (candidates for removal):
SELECT
    schemaname,
    relname AS table_name,
    indexrelname AS index_name,
    idx_scan AS times_used,
    pg_size_pretty(pg_relation_size(indexrelid)) AS index_size,
    pg_size_pretty(pg_relation_size(indrelid)) AS table_size
FROM pg_stat_user_indexes
WHERE idx_scan = 0
    AND indexrelname NOT LIKE '%_pkey'  -- Keep primary keys
    AND schemaname = 'public'
ORDER BY pg_relation_size(indexrelid) DESC;

-- Find duplicate indexes:
SELECT
    indrelid::regclass AS table_name,
    array_agg(indexrelid::regclass) AS duplicate_indexes,
    array_agg(pg_size_pretty(pg_relation_size(indexrelid))) AS sizes
FROM pg_index
GROUP BY indrelid, indkey
HAVING COUNT(*) > 1;

-- Find indexes with low selectivity (often not useful):
SELECT
    schemaname,
    relname AS table_name,
    indexrelname AS index_name,
    idx_scan,
    idx_tup_read,
    idx_tup_fetch,
    CASE WHEN idx_tup_read > 0
        THEN round(idx_tup_fetch::numeric / idx_tup_read, 4)
        ELSE 0
    END AS fetch_ratio
FROM pg_stat_user_indexes
WHERE idx_scan > 0
ORDER BY fetch_ratio ASC
LIMIT 20;

-- Index bloat estimation:
SELECT
    current_database(),
    schemaname,
    tablename,
    indexname,
    pg_size_pretty(pg_relation_size(indexrelid)) AS index_size,
    round(100 * pg_relation_size(indexrelid) /
        NULLIF(pg_relation_size(indrelid), 0), 1) AS index_to_table_pct
FROM pg_stat_user_indexes
JOIN pg_index USING (indexrelid)
ORDER BY pg_relation_size(indexrelid) DESC
LIMIT 20;
```

### REINDEX Operations

```sql
-- REINDEX CONCURRENTLY: Rebuilds an index without blocking reads or writes.
-- Available in PostgreSQL 12+. Creates a new index, swaps, drops old one.
-- Requires extra disk space for the duration.
REINDEX INDEX CONCURRENTLY idx_orders_customer_id;

-- Reindex an entire table's indexes concurrently:
REINDEX TABLE CONCURRENTLY orders;

-- For PostgreSQL < 12, use CREATE INDEX CONCURRENTLY + DROP:
CREATE INDEX CONCURRENTLY idx_orders_customer_id_new
    ON orders (customer_id);
-- Verify the new index is valid:
SELECT indexrelid::regclass, indisvalid
FROM pg_index
WHERE indexrelid = 'idx_orders_customer_id_new'::regclass;
-- Drop the old index:
DROP INDEX CONCURRENTLY idx_orders_customer_id;
-- Rename:
ALTER INDEX idx_orders_customer_id_new RENAME TO idx_orders_customer_id;
```

---

## pg_stat_statements Setup and Analysis

### Installation

```sql
-- 1. Add to postgresql.conf:
-- shared_preload_libraries = 'pg_stat_statements'
-- pg_stat_statements.max = 10000
-- pg_stat_statements.track = top        -- 'top', 'all', or 'none'
-- pg_stat_statements.track_utility = on  -- Track DDL/utility statements
-- pg_stat_statements.track_planning = on -- PG 13+: Track planning time

-- 2. Restart PostgreSQL (required for shared_preload_libraries change).

-- 3. Create the extension in each database:
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
```

### Key Queries for Analysis

```sql
-- Top 20 queries by total execution time:
SELECT
    queryid,
    calls,
    round(total_exec_time::numeric, 2) AS total_ms,
    round(mean_exec_time::numeric, 2) AS mean_ms,
    round(stddev_exec_time::numeric, 2) AS stddev_ms,
    round((100 * total_exec_time / sum(total_exec_time) OVER())::numeric, 2) AS pct_total,
    rows,
    query
FROM pg_stat_statements
ORDER BY total_exec_time DESC
LIMIT 20;

-- Queries with highest I/O (shared buffer hits vs reads):
SELECT
    queryid,
    calls,
    shared_blks_hit,
    shared_blks_read,
    round(100.0 * shared_blks_hit /
        NULLIF(shared_blks_hit + shared_blks_read, 0), 2) AS cache_hit_pct,
    round(total_exec_time::numeric, 2) AS total_ms,
    query
FROM pg_stat_statements
WHERE shared_blks_read > 1000
ORDER BY shared_blks_read DESC
LIMIT 20;

-- Queries with most temporary file usage (work_mem too low):
SELECT
    queryid,
    calls,
    temp_blks_read,
    temp_blks_written,
    round(mean_exec_time::numeric, 2) AS mean_ms,
    query
FROM pg_stat_statements
WHERE temp_blks_written > 0
ORDER BY temp_blks_written DESC
LIMIT 20;

-- Queries with highest mean time (individually slow):
SELECT
    queryid,
    calls,
    round(mean_exec_time::numeric, 2) AS mean_ms,
    round(min_exec_time::numeric, 2) AS min_ms,
    round(max_exec_time::numeric, 2) AS max_ms,
    rows,
    query
FROM pg_stat_statements
WHERE calls > 10
ORDER BY mean_exec_time DESC
LIMIT 20;

-- Reset statistics (do periodically to get fresh data):
SELECT pg_stat_statements_reset();
```

---

## Common Slow Query Patterns and Fixes

### Pattern 1: Missing Index on WHERE Clause

```sql
-- SLOW: Full sequential scan on large table.
SELECT * FROM orders WHERE customer_id = 12345;

-- EXPLAIN output shows:
-- Seq Scan on orders  (cost=0.00..125000.00 rows=500 width=120)
--   Filter: (customer_id = 12345)
--   Rows Removed by Filter: 9999500

-- FIX: Add an index.
CREATE INDEX CONCURRENTLY idx_orders_customer_id ON orders (customer_id);
```

### Pattern 2: N+1 Query Problem

```sql
-- SLOW: Application loop issuing one query per row.
-- For each of 1000 customers:
SELECT * FROM orders WHERE customer_id = ?;  -- Executed 1000 times

-- FIX: Single query with IN clause or JOIN.
SELECT o.* FROM orders o
WHERE o.customer_id = ANY(ARRAY[1, 2, 3, ...]);

-- Or better, restructure as a JOIN in the application query:
SELECT c.name, o.*
FROM customers c
JOIN orders o ON o.customer_id = c.id
WHERE c.region = 'US';
```

### Pattern 3: SELECT * When Only Few Columns Needed

```sql
-- SLOW: Fetching all columns including large TEXT/BYTEA fields.
SELECT * FROM products WHERE category_id = 5;

-- FIX: Select only needed columns. Enables index-only scans.
SELECT id, name, price FROM products WHERE category_id = 5;

-- Even better with a covering index:
CREATE INDEX idx_products_category_covering
    ON products (category_id) INCLUDE (id, name, price);
```

### Pattern 4: Implicit Type Casting Preventing Index Use

```sql
-- SLOW: Column is integer but parameter is text. Index not used.
SELECT * FROM users WHERE phone_number = 5551234567;
-- If phone_number is VARCHAR, PostgreSQL casts every row for comparison.

-- FIX: Use the correct type.
SELECT * FROM users WHERE phone_number = '5551234567';
```

### Pattern 5: Functions on Indexed Columns

```sql
-- SLOW: Function call on column prevents index use.
SELECT * FROM events WHERE EXTRACT(YEAR FROM created_at) = 2025;

-- FIX Option A: Rewrite as range condition.
SELECT * FROM events
WHERE created_at >= '2025-01-01' AND created_at < '2026-01-01';

-- FIX Option B: Create a functional (expression) index.
CREATE INDEX idx_events_year ON events (EXTRACT(YEAR FROM created_at));
```

### Pattern 6: OR Conditions Defeating Indexes

```sql
-- SLOW: OR across different columns prevents single index use.
SELECT * FROM products WHERE name = 'Widget' OR sku = 'WDG-001';

-- FIX: Use UNION to leverage separate indexes.
SELECT * FROM products WHERE name = 'Widget'
UNION
SELECT * FROM products WHERE sku = 'WDG-001';
```

### Pattern 7: Large OFFSET for Pagination

```sql
-- SLOW: PostgreSQL must scan and discard offset rows.
SELECT * FROM posts ORDER BY created_at DESC LIMIT 20 OFFSET 100000;

-- FIX: Keyset (cursor-based) pagination.
SELECT * FROM posts
WHERE created_at < '2025-01-15T10:30:00Z'
ORDER BY created_at DESC
LIMIT 20;
```

### Pattern 8: Correlated Subquery Instead of JOIN

```sql
-- SLOW: Subquery executes once per outer row.
SELECT o.id,
    (SELECT c.name FROM customers c WHERE c.id = o.customer_id) AS customer_name
FROM orders o;

-- FIX: Use a JOIN.
SELECT o.id, c.name AS customer_name
FROM orders o
JOIN customers c ON c.id = o.customer_id;
```

---

## EXPLAIN ANALYZE Reading Guide

### Running EXPLAIN ANALYZE

```sql
-- Basic usage (executes the query and shows actual timings):
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT) SELECT ...;

-- With additional detail:
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, TIMING, FORMAT TEXT) SELECT ...;

-- WARNING: EXPLAIN ANALYZE actually executes the query.
-- For DML (INSERT/UPDATE/DELETE), wrap in a transaction and roll back:
BEGIN;
EXPLAIN (ANALYZE, BUFFERS) DELETE FROM old_records WHERE created_at < '2020-01-01';
ROLLBACK;
```

### Scan Types

```
Sequential Scan (Seq Scan)
--------------------------
Reads every row in the table. Used when:
  - No suitable index exists
  - The query selects a large fraction of rows (planner estimates it is cheaper)
  - Table is small enough that a seq scan is faster than index overhead

Example:
  Seq Scan on orders  (cost=0.00..1250.00 rows=50000 width=80) (actual time=0.012..15.234 rows=50000 loops=1)
    Filter: (status = 'pending')
    Rows Removed by Filter: 0
    Buffers: shared hit=500

Concern: On large tables with selective filters, this indicates a missing index.


Index Scan
----------
Uses a B-tree (or other) index to find matching rows, then fetches the actual
heap (table) row for each match. Two I/O operations per row: index + heap.

Example:
  Index Scan using idx_orders_customer_id on orders  (cost=0.43..8.45 rows=1 width=80) (actual time=0.023..0.025 rows=1 loops=1)
    Index Cond: (customer_id = 12345)
    Buffers: shared hit=4

Best for: Highly selective queries returning few rows.


Index Only Scan
---------------
Reads data entirely from the index without touching the heap table.
Requires a "covering" index that includes all selected columns.
Also requires that the visibility map is up to date (regular VACUUM).

Example:
  Index Only Scan using idx_orders_covering on orders  (cost=0.43..4.22 rows=1 width=12) (actual time=0.015..0.016 rows=1 loops=1)
    Index Cond: (customer_id = 12345)
    Heap Fetches: 0
    Buffers: shared hit=3

Note: "Heap Fetches: 0" is ideal. If this number is high, VACUUM the table.


Bitmap Index Scan + Bitmap Heap Scan
------------------------------------
Two-phase approach: first scans the index to build a bitmap of matching pages,
then reads those pages from the heap. Efficient for medium selectivity or
when combining multiple indexes via BitmapAnd / BitmapOr.

Example:
  Bitmap Heap Scan on orders  (cost=50.00..500.00 rows=2000 width=80) (actual time=1.234..5.678 rows=1950 loops=1)
    Recheck Cond: (customer_id = 12345)
    Heap Blocks: exact=120
    Buffers: shared hit=130
    ->  Bitmap Index Scan on idx_orders_customer_id  (cost=0.00..49.50 rows=2000 width=0) (actual time=0.500..0.500 rows=2000 loops=1)
          Index Cond: (customer_id = 12345)

Note: "Heap Blocks: exact" is good. "Heap Blocks: lossy" means work_mem was
too small to hold the full bitmap, causing recheck overhead.
```

### Join Types

```
Nested Loop
-----------
For each row in the outer table, scans the inner table.
Efficient when: outer table is small, inner table has an index.
Cost: O(outer_rows * inner_lookup_cost).

Example:
  Nested Loop  (cost=0.86..100.50 rows=10 width=160) (actual time=0.050..0.250 rows=10 loops=1)
    ->  Index Scan using idx_orders_id on orders  (cost=0.43..8.45 rows=10 width=80)
          Index Cond: (id = ANY('{1,2,3,4,5,6,7,8,9,10}'))
    ->  Index Scan using customers_pkey on customers  (cost=0.43..8.45 rows=1 width=80)
          Index Cond: (id = orders.customer_id)


Hash Join
---------
Builds a hash table from the smaller table, then probes it for each row
of the larger table. Efficient for larger result sets with equality joins.
Cost: O(outer_rows + inner_rows). Requires memory (work_mem).

Example:
  Hash Join  (cost=500.00..2500.00 rows=50000 width=160) (actual time=10.000..50.000 rows=50000 loops=1)
    Hash Cond: (orders.customer_id = customers.id)
    ->  Seq Scan on orders  (cost=0.00..1250.00 rows=50000 width=80)
    ->  Hash  (cost=300.00..300.00 rows=10000 width=80)
          Buckets: 16384  Batches: 1  Memory Usage: 800kB
          ->  Seq Scan on customers  (cost=0.00..300.00 rows=10000 width=80)

Note: "Batches: 1" is ideal. Multiple batches means work_mem is too small
and hash table spills to disk.


Merge Join
----------
Sorts both inputs on the join key, then merges them in order.
Efficient when: both inputs are already sorted (from indexes) or the
dataset is large and sorted merge is cheaper than hashing.
Cost: O(outer_rows * log(outer_rows) + inner_rows * log(inner_rows)) for sort.

Example:
  Merge Join  (cost=1000.00..3000.00 rows=50000 width=160) (actual time=20.000..80.000 rows=50000 loops=1)
    Merge Cond: (orders.customer_id = customers.id)
    ->  Sort  (cost=600.00..625.00 rows=50000 width=80)
          Sort Key: orders.customer_id
          Sort Method: external merge  Disk: 5000kB
          ->  Seq Scan on orders ...
    ->  Sort ...

Note: "Sort Method: external merge Disk: NkB" indicates work_mem is too small.
"Sort Method: quicksort Memory: NkB" is ideal (in-memory sort).
```

### Key EXPLAIN ANALYZE Metrics to Watch

```
1. actual time=START..END
   - START: Time to return first row (ms).
   - END: Time to return all rows (ms).
   - Large gap between start and end on sorts/hashes indicates memory pressure.

2. rows=N vs estimated rows=M
   - Large discrepancy (>10x) means stale statistics. Run ANALYZE.
   - Consistently bad estimates on a column: consider extended statistics.
     CREATE STATISTICS my_stats (dependencies) ON col1, col2 FROM my_table;

3. loops=N
   - Number of times this node was executed (e.g., inner side of nested loop).
   - Multiply actual time and rows by loops for true totals.

4. Buffers: shared hit=H read=R
   - hit: Pages found in shared_buffers (fast).
   - read: Pages read from OS / disk (slow).
   - High read count suggests shared_buffers is too small or working set exceeds cache.

5. Planning Time vs Execution Time
   - High planning time (>10ms) may indicate too many partitions, complex views,
     or excessive use of CTEs in older PostgreSQL versions.
```

---

## Table Bloat Detection and Remediation

### Detecting Bloat

```sql
-- Dead tuple ratio per table:
SELECT
    schemaname,
    relname,
    n_live_tup,
    n_dead_tup,
    round(100.0 * n_dead_tup / NULLIF(n_live_tup + n_dead_tup, 0), 2) AS dead_pct,
    last_vacuum,
    last_autovacuum,
    last_analyze
FROM pg_stat_user_tables
WHERE n_dead_tup > 1000
ORDER BY n_dead_tup DESC;

-- Table size vs estimated actual data size (bloat estimation):
-- This query uses pg_class and pg_statistic to estimate bloat.
SELECT
    current_database(),
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname || '.' || tablename)) AS total_size,
    pg_size_pretty(pg_relation_size(schemaname || '.' || tablename)) AS table_size,
    pg_size_pretty(
        pg_total_relation_size(schemaname || '.' || tablename) -
        pg_relation_size(schemaname || '.' || tablename)
    ) AS index_and_toast_size
FROM pg_stat_user_tables
ORDER BY pg_total_relation_size(schemaname || '.' || tablename) DESC
LIMIT 20;

-- Check if autovacuum is keeping up:
SELECT
    relname,
    n_dead_tup,
    last_autovacuum,
    autovacuum_count,
    CASE
        WHEN last_autovacuum IS NULL THEN 'NEVER vacuumed'
        WHEN last_autovacuum < NOW() - INTERVAL '1 day' THEN 'STALE'
        ELSE 'OK'
    END AS vacuum_status
FROM pg_stat_user_tables
WHERE n_dead_tup > 10000
ORDER BY n_dead_tup DESC;
```

### Remediation Options

```sql
-- Option 1: Let autovacuum catch up by making it more aggressive (no downtime).
ALTER TABLE bloated_table SET (
    autovacuum_vacuum_scale_factor = 0.01,
    autovacuum_vacuum_cost_delay = 0,
    autovacuum_vacuum_cost_limit = 5000
);

-- Option 2: VACUUM (no downtime, does not return space to OS).
VACUUM VERBOSE bloated_table;

-- Option 3: VACUUM FULL (returns space to OS, but LOCKS TABLE).
-- Only for maintenance windows.
VACUUM FULL VERBOSE bloated_table;

-- Option 4: pg_repack (no downtime, returns space to OS).
-- Requires installing the pg_repack extension.
-- Rebuilds the table and indexes without locking.
-- Install: CREATE EXTENSION pg_repack;
-- Run from command line:
-- pg_repack -d mydb -t bloated_table --no-superuser-check

-- Option 5: For indexes specifically, REINDEX CONCURRENTLY:
REINDEX INDEX CONCURRENTLY idx_bloated_table_col;
```

---

## WAL Configuration for Different Workloads

### OLTP (Online Transaction Processing)

High volume of short transactions, mostly single-row operations. Priority is low latency and crash safety.

```ini
wal_level = replica
max_wal_size = 4GB
min_wal_size = 1GB
checkpoint_timeout = 15min
checkpoint_completion_target = 0.9
wal_compression = on
wal_buffers = 64MB

# fsync must always be on in production. Never disable.
fsync = on

# synchronous_commit: Controls when the server reports success to the client.
# 'on': Wait for WAL flush to disk. Safest but slowest.
# 'off': Report success immediately. Risk of losing last few ms of transactions
#         on crash. No data corruption, but some committed transactions may vanish.
# For OLTP: Use 'on' unless you accept minor data loss for performance.
synchronous_commit = on

# For synchronous replication:
# synchronous_standby_names = 'replica1'
# synchronous_commit = remote_write  # or 'remote_apply' for strongest guarantee
```

### Batch/ETL (Extract, Transform, Load)

Large bulk inserts, data transformations. Priority is throughput, not per-transaction latency.

```ini
wal_level = minimal    # If no replication needed during load
max_wal_size = 16GB    # Reduce checkpoint frequency during bulk writes
min_wal_size = 4GB
checkpoint_timeout = 30min
checkpoint_completion_target = 0.9
wal_compression = on
wal_buffers = 256MB

# For bulk loads, temporarily relax synchronous_commit:
synchronous_commit = off

# Increase these for bulk operations:
maintenance_work_mem = 4GB
max_parallel_maintenance_workers = 4

# During bulk load, consider:
# - Dropping indexes, loading data, recreating indexes
# - Using COPY instead of INSERT
# - Disabling triggers temporarily
# - Using UNLOGGED tables for intermediate staging data
```

### Analytics/Data Warehouse

Large sequential scans, complex aggregations, few concurrent users.

```ini
wal_level = replica
max_wal_size = 8GB
min_wal_size = 2GB
checkpoint_timeout = 30min
checkpoint_completion_target = 0.9
wal_compression = on

# Prioritize large sequential reads and parallel queries:
effective_cache_size = 48GB          # Aggressive caching estimate
work_mem = 512MB                     # Large sort/hash memory (fewer connections)
max_parallel_workers_per_gather = 8  # Maximize parallelism
max_parallel_workers = 16
random_page_cost = 1.1               # SSD-appropriate
effective_io_concurrency = 200

# JIT compilation can help complex analytical queries (PG 11+):
jit = on
jit_above_cost = 100000
jit_inline_above_cost = 500000
jit_optimize_above_cost = 500000
```

### Streaming Replication

Primary server configured for synchronous or asynchronous replication to standby servers.

```ini
# Primary server:
wal_level = replica                  # Required for replication
max_wal_senders = 10                 # Maximum replication connections
wal_keep_size = 2GB                  # WAL retained for slow replicas (PG 13+)
max_replication_slots = 10           # Replication slots prevent WAL removal

# For synchronous replication (zero data loss, higher latency):
synchronous_standby_names = 'FIRST 1 (replica1, replica2)'
synchronous_commit = remote_apply    # Wait for replica to apply WAL

# For asynchronous replication (possible data loss, lower latency):
synchronous_commit = on              # Only wait for local WAL flush

# WAL archiving (for PITR - Point-in-Time Recovery):
archive_mode = on
archive_command = 'test ! -f /archive/%f && cp %p /archive/%f'
# Or use pgBackRest, barman, or wal-g for production archiving.
```

---

## Quick Reference: Settings by Server RAM

| Setting                 | 8GB Server | 32GB Server | 64GB Server | 128GB Server |
|-------------------------|------------|-------------|-------------|--------------|
| shared_buffers          | 2GB        | 8GB         | 16GB        | 32GB         |
| effective_cache_size    | 6GB        | 24GB        | 48GB        | 96GB         |
| work_mem                | 16MB       | 32MB        | 64MB        | 128MB        |
| maintenance_work_mem    | 512MB      | 1GB         | 2GB         | 4GB          |
| wal_buffers             | 64MB       | 64MB        | 64MB        | 64MB         |
| max_connections         | 200        | 300         | 400         | 500          |
| effective_io_concurrency| 200 (SSD)  | 200 (SSD)   | 200 (SSD)   | 200 (SSD)    |
| random_page_cost        | 1.1 (SSD)  | 1.1 (SSD)   | 1.1 (SSD)   | 1.1 (SSD)    |

> Note: These are starting points. Always benchmark with your specific workload using
> pgbench or your application's actual query patterns. Use tools like PGTune
> (https://pgtune.leopard.in.ua/) for initial calculations.
