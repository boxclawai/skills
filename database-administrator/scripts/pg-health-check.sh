#!/usr/bin/env bash
# pg-health-check.sh - PostgreSQL health check and diagnostics
# Usage: ./pg-health-check.sh [--url postgres://...] [--verbose]
#
# Checks:
#   - Connection count and pool usage
#   - Cache hit ratio
#   - Table bloat and dead tuples
#   - Slow queries (pg_stat_statements)
#   - Replication lag
#   - Lock contention
#   - Index usage and missing indexes

set -euo pipefail

DB_URL="${DATABASE_URL:-}"
VERBOSE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --url) DB_URL="$2"; shift 2 ;;
    --verbose) VERBOSE=true; shift ;;
    *) echo "Unknown: $1"; exit 1 ;;
  esac
done

if [[ -z "$DB_URL" ]]; then
  echo "Usage: $0 --url postgres://user:pass@host:5432/dbname"
  echo "Or set DATABASE_URL environment variable"
  exit 1
fi

run_query() {
  psql "$DB_URL" -t -A -c "$1" 2>/dev/null
}

run_query_formatted() {
  psql "$DB_URL" -c "$1" 2>/dev/null
}

echo "======================================"
echo "  PostgreSQL Health Check"
echo "======================================"
echo ""

# --- Connection Info ---
echo "=== Connection Info ==="
run_query_formatted "
SELECT
  version() AS server_version;
"

echo ""
echo "=== Connection Pool ==="
run_query_formatted "
SELECT
  count(*) AS total_connections,
  count(*) FILTER (WHERE state = 'active') AS active,
  count(*) FILTER (WHERE state = 'idle') AS idle,
  count(*) FILTER (WHERE state = 'idle in transaction') AS idle_in_transaction,
  count(*) FILTER (WHERE wait_event_type = 'Lock') AS waiting_on_lock,
  (SELECT setting::int FROM pg_settings WHERE name = 'max_connections') AS max_connections
FROM pg_stat_activity
WHERE backend_type = 'client backend';
"

# --- Cache Hit Ratio ---
echo ""
echo "=== Cache Hit Ratio (target: > 99%) ==="
run_query_formatted "
SELECT
  'index' AS type,
  ROUND(100.0 * sum(idx_blks_hit) / NULLIF(sum(idx_blks_hit + idx_blks_read), 0), 2) AS hit_ratio_pct
FROM pg_statio_user_indexes
UNION ALL
SELECT
  'table' AS type,
  ROUND(100.0 * sum(heap_blks_hit) / NULLIF(sum(heap_blks_hit + heap_blks_read), 0), 2) AS hit_ratio_pct
FROM pg_statio_user_tables;
"

# --- Database Size ---
echo ""
echo "=== Database Size ==="
run_query_formatted "
SELECT
  pg_database.datname AS database,
  pg_size_pretty(pg_database_size(pg_database.datname)) AS size
FROM pg_database
WHERE datistemplate = false
ORDER BY pg_database_size(pg_database.datname) DESC;
"

# --- Table Sizes (Top 10) ---
echo ""
echo "=== Largest Tables (Top 10) ==="
run_query_formatted "
SELECT
  schemaname || '.' || tablename AS table_name,
  pg_size_pretty(pg_total_relation_size(schemaname || '.' || tablename)) AS total_size,
  pg_size_pretty(pg_relation_size(schemaname || '.' || tablename)) AS table_size,
  pg_size_pretty(pg_indexes_size(schemaname || '.' || tablename)) AS index_size,
  n_live_tup AS live_rows,
  n_dead_tup AS dead_rows
FROM pg_stat_user_tables
JOIN pg_tables USING (schemaname, tablename)
ORDER BY pg_total_relation_size(schemaname || '.' || tablename) DESC
LIMIT 10;
"

# --- Table Bloat (Dead Tuples) ---
echo ""
echo "=== Tables with High Bloat (dead tuples > 10000) ==="
run_query_formatted "
SELECT
  schemaname || '.' || relname AS table_name,
  n_live_tup AS live_rows,
  n_dead_tup AS dead_rows,
  ROUND(100.0 * n_dead_tup / NULLIF(n_live_tup + n_dead_tup, 0), 1) AS dead_pct,
  last_autovacuum,
  last_autoanalyze
FROM pg_stat_user_tables
WHERE n_dead_tup > 10000
ORDER BY n_dead_tup DESC
LIMIT 10;
"

# --- Index Usage ---
echo ""
echo "=== Unused Indexes (0 scans, > 1MB) ==="
run_query_formatted "
SELECT
  schemaname || '.' || relname AS table_name,
  indexrelname AS index_name,
  pg_size_pretty(pg_relation_size(indexrelid)) AS index_size,
  idx_scan AS scans
FROM pg_stat_user_indexes
WHERE idx_scan = 0
  AND pg_relation_size(indexrelid) > 1048576
ORDER BY pg_relation_size(indexrelid) DESC
LIMIT 10;
"

# --- Slow Queries ---
echo ""
echo "=== Top 10 Slowest Queries (avg time) ==="
run_query_formatted "
SELECT
  ROUND(mean_exec_time::numeric, 2) AS avg_ms,
  calls,
  ROUND(total_exec_time::numeric, 0) AS total_ms,
  ROUND((100 * total_exec_time / NULLIF(sum(total_exec_time) OVER(), 0))::numeric, 1) AS pct_total,
  LEFT(query, 80) AS query_preview
FROM pg_stat_statements
WHERE userid = (SELECT usesysid FROM pg_user WHERE usename = current_user)
ORDER BY mean_exec_time DESC
LIMIT 10;
" 2>/dev/null || echo "pg_stat_statements not enabled. Add to shared_preload_libraries."

# --- Lock Contention ---
echo ""
echo "=== Current Lock Waits ==="
LOCKS=$(run_query "
SELECT count(*)
FROM pg_locks l
JOIN pg_stat_activity a ON l.pid = a.pid
WHERE NOT l.granted;" 2>/dev/null || echo "0")

if [[ "${LOCKS:-0}" -gt 0 ]]; then
  echo "WARNING: $LOCKS queries waiting on locks!"
  run_query_formatted "
  SELECT
    blocked_activity.pid AS blocked_pid,
    blocked_activity.query AS blocked_query,
    blocking_activity.pid AS blocking_pid,
    blocking_activity.query AS blocking_query,
    age(clock_timestamp(), blocked_activity.query_start) AS wait_duration
  FROM pg_catalog.pg_locks blocked_locks
  JOIN pg_catalog.pg_stat_activity blocked_activity ON blocked_activity.pid = blocked_locks.pid
  JOIN pg_catalog.pg_locks blocking_locks ON blocking_locks.locktype = blocked_locks.locktype
    AND blocking_locks.relation = blocked_locks.relation
    AND blocking_locks.pid != blocked_locks.pid
  JOIN pg_catalog.pg_stat_activity blocking_activity ON blocking_activity.pid = blocking_locks.pid
  WHERE NOT blocked_locks.granted
  LIMIT 5;
  " 2>/dev/null
else
  echo "No lock contention detected."
fi

# --- Replication ---
echo ""
echo "=== Replication Status ==="
REPLICAS=$(run_query "SELECT count(*) FROM pg_stat_replication;" 2>/dev/null || echo "0")

if [[ "${REPLICAS:-0}" -gt 0 ]]; then
  run_query_formatted "
  SELECT
    client_addr,
    state,
    sent_lsn,
    write_lsn,
    flush_lsn,
    replay_lsn,
    pg_size_pretty(pg_wal_lsn_diff(sent_lsn, replay_lsn)) AS replication_lag
  FROM pg_stat_replication;
  " 2>/dev/null
else
  echo "No replicas connected (or this is a replica)."
fi

echo ""
echo "======================================"
echo "  Health Check Complete"
echo "======================================"
