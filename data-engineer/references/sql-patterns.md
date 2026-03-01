# Advanced SQL Patterns Reference

Production-grade SQL patterns for data engineering workloads. All examples target PostgreSQL 14+ unless otherwise noted.

---

## Table of Contents

1. [Window Functions](#window-functions)
2. [CTEs and Recursive CTEs](#ctes-and-recursive-ctes)
3. [LATERAL Joins](#lateral-joins)
4. [UPSERT / MERGE Patterns](#upsert--merge-patterns)
5. [JSON Operations in PostgreSQL](#json-operations-in-postgresql)
6. [Pivoting and Unpivoting](#pivoting-and-unpivoting)
7. [Gap-and-Island Problems](#gap-and-island-problems)
8. [Date Spine Generation](#date-spine-generation)
9. [Performance-Optimized Aggregation](#performance-optimized-aggregation)
10. [Incremental Load Patterns](#incremental-load-patterns)
11. [SCD Type 2 Implementation](#scd-type-2-implementation)

---

## Window Functions

### ROW_NUMBER -- Deduplicate Rows

Use `ROW_NUMBER()` to keep only the latest record per entity when ingesting duplicates.

```sql
-- Keep the most recent event per user from a raw events table
WITH ranked AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY user_id
            ORDER BY event_timestamp DESC
        ) AS rn
    FROM raw_events
)
SELECT *
FROM ranked
WHERE rn = 1;
```

### RANK and DENSE_RANK -- Top-N Per Group

```sql
-- Top 3 products by revenue per category (ties share rank)
SELECT
    category_id,
    product_id,
    revenue,
    RANK() OVER (
        PARTITION BY category_id
        ORDER BY revenue DESC
    ) AS revenue_rank
FROM product_sales
QUALIFY revenue_rank <= 3;  -- DuckDB/Snowflake syntax

-- PostgreSQL equivalent (no QUALIFY)
WITH ranked AS (
    SELECT
        category_id,
        product_id,
        revenue,
        RANK() OVER (
            PARTITION BY category_id
            ORDER BY revenue DESC
        ) AS revenue_rank
    FROM product_sales
)
SELECT * FROM ranked WHERE revenue_rank <= 3;
```

### LEAD / LAG -- Comparing Adjacent Rows

```sql
-- Calculate time between consecutive user sessions
SELECT
    user_id,
    session_start,
    LAG(session_start) OVER (
        PARTITION BY user_id
        ORDER BY session_start
    ) AS previous_session_start,
    session_start - LAG(session_start) OVER (
        PARTITION BY user_id
        ORDER BY session_start
    ) AS time_between_sessions,
    LEAD(session_start) OVER (
        PARTITION BY user_id
        ORDER BY session_start
    ) AS next_session_start
FROM user_sessions;
```

### Running Totals and Moving Averages

```sql
-- Running total of revenue by day, with 7-day moving average
SELECT
    order_date,
    daily_revenue,
    SUM(daily_revenue) OVER (
        ORDER BY order_date
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS cumulative_revenue,
    AVG(daily_revenue) OVER (
        ORDER BY order_date
        ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ) AS moving_avg_7d,
    -- Percentage of total
    daily_revenue::NUMERIC / SUM(daily_revenue) OVER () AS pct_of_total
FROM daily_revenue_summary
ORDER BY order_date;
```

### FIRST_VALUE / LAST_VALUE / NTH_VALUE

```sql
-- For each order, show the first and most recent order amount per customer
SELECT
    customer_id,
    order_id,
    order_date,
    amount,
    FIRST_VALUE(amount) OVER w AS first_order_amount,
    LAST_VALUE(amount) OVER (
        PARTITION BY customer_id
        ORDER BY order_date
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ) AS latest_order_amount,
    NTH_VALUE(amount, 2) OVER w AS second_order_amount
FROM orders
WINDOW w AS (
    PARTITION BY customer_id
    ORDER BY order_date
    ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
);
```

### Percent Rank and Percentiles

```sql
-- Assign percentile buckets to customers by lifetime value
SELECT
    customer_id,
    lifetime_value,
    PERCENT_RANK() OVER (ORDER BY lifetime_value) AS pct_rank,
    NTILE(100) OVER (ORDER BY lifetime_value) AS percentile_bucket,
    NTILE(10) OVER (ORDER BY lifetime_value) AS decile
FROM customer_ltv;
```

---

## CTEs and Recursive CTEs

### Multi-Step Transformation Pipeline

```sql
-- Staged transformation: raw -> cleaned -> enriched -> aggregated
WITH cleaned AS (
    SELECT
        TRIM(LOWER(email)) AS email,
        COALESCE(country, 'UNKNOWN') AS country,
        created_at::DATE AS signup_date,
        amount_cents / 100.0 AS amount
    FROM raw_transactions
    WHERE amount_cents > 0
      AND email IS NOT NULL
),
enriched AS (
    SELECT
        c.*,
        r.region,
        r.currency,
        CASE
            WHEN c.amount >= 1000 THEN 'enterprise'
            WHEN c.amount >= 100  THEN 'mid_market'
            ELSE 'smb'
        END AS segment
    FROM cleaned c
    LEFT JOIN region_mapping r ON c.country = r.country_code
),
aggregated AS (
    SELECT
        signup_date,
        segment,
        region,
        COUNT(*) AS tx_count,
        SUM(amount) AS total_amount,
        AVG(amount) AS avg_amount,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY amount) AS median_amount
    FROM enriched
    GROUP BY signup_date, segment, region
)
SELECT * FROM aggregated
ORDER BY signup_date DESC, total_amount DESC;
```

### Recursive CTE -- Hierarchy Traversal

```sql
-- Flatten an organizational hierarchy (employee -> manager chain)
WITH RECURSIVE org_tree AS (
    -- Base case: top-level managers (no manager_id)
    SELECT
        employee_id,
        employee_name,
        manager_id,
        1 AS depth,
        employee_name::TEXT AS path,
        ARRAY[employee_id] AS id_path
    FROM employees
    WHERE manager_id IS NULL

    UNION ALL

    -- Recursive step: join children to their parents
    SELECT
        e.employee_id,
        e.employee_name,
        e.manager_id,
        ot.depth + 1,
        ot.path || ' > ' || e.employee_name,
        ot.id_path || e.employee_id
    FROM employees e
    INNER JOIN org_tree ot ON e.manager_id = ot.employee_id
    WHERE ot.depth < 20  -- safety limit to prevent infinite loops
)
SELECT
    employee_id,
    employee_name,
    depth,
    path,
    id_path[1] AS root_manager_id
FROM org_tree
ORDER BY path;
```

### Recursive CTE -- Graph Traversal (Shortest Path)

```sql
-- Find all reachable nodes from a starting node in a graph
WITH RECURSIVE reachable AS (
    SELECT
        target_node AS node,
        1 AS hops,
        ARRAY[source_node, target_node] AS path
    FROM edges
    WHERE source_node = 'node_A'

    UNION

    SELECT
        e.target_node,
        r.hops + 1,
        r.path || e.target_node
    FROM edges e
    INNER JOIN reachable r ON e.source_node = r.node
    WHERE e.target_node <> ALL(r.path)  -- prevent cycles
      AND r.hops < 10                    -- depth limit
)
SELECT DISTINCT ON (node)
    node,
    hops,
    path
FROM reachable
ORDER BY node, hops;
```

### Recursive CTE -- Series Generation

```sql
-- Generate a date series (useful when generate_series is not available)
WITH RECURSIVE date_series AS (
    SELECT DATE '2024-01-01' AS dt
    UNION ALL
    SELECT dt + INTERVAL '1 day'
    FROM date_series
    WHERE dt < DATE '2024-12-31'
)
SELECT dt FROM date_series;
```

---

## LATERAL Joins

### Top-N Per Group (Correlated Subquery Alternative)

```sql
-- Get the 3 most recent orders per customer
-- LATERAL is often faster than window functions for top-N queries
SELECT
    c.customer_id,
    c.customer_name,
    recent_orders.*
FROM customers c
CROSS JOIN LATERAL (
    SELECT
        o.order_id,
        o.order_date,
        o.total_amount
    FROM orders o
    WHERE o.customer_id = c.customer_id
    ORDER BY o.order_date DESC
    LIMIT 3
) AS recent_orders;
```

### LATERAL with Aggregations

```sql
-- For each product, compute stats from the last 30 days of sales
SELECT
    p.product_id,
    p.product_name,
    stats.*
FROM products p
CROSS JOIN LATERAL (
    SELECT
        COUNT(*) AS sale_count,
        SUM(quantity) AS total_units,
        AVG(unit_price * quantity) AS avg_order_value,
        MAX(sale_date) AS last_sale_date
    FROM sales s
    WHERE s.product_id = p.product_id
      AND s.sale_date >= CURRENT_DATE - INTERVAL '30 days'
) AS stats
WHERE stats.sale_count > 0;
```

### LATERAL for Unnesting and Expanding

```sql
-- Parse a comma-separated tags column into rows
SELECT
    article_id,
    tag.value AS tag
FROM articles a
CROSS JOIN LATERAL unnest(string_to_array(a.tags_csv, ',')) AS tag(value);
```

---

## UPSERT / MERGE Patterns

### PostgreSQL ON CONFLICT (Upsert)

```sql
-- Upsert: insert new rows, update existing ones
INSERT INTO dim_customer (customer_id, name, email, updated_at)
SELECT customer_id, name, email, NOW()
FROM staging_customers
ON CONFLICT (customer_id) DO UPDATE SET
    name       = EXCLUDED.name,
    email      = EXCLUDED.email,
    updated_at = EXCLUDED.updated_at
WHERE (
    dim_customer.name  IS DISTINCT FROM EXCLUDED.name
    OR dim_customer.email IS DISTINCT FROM EXCLUDED.email
);
-- The WHERE clause avoids unnecessary updates when nothing changed
```

### Conditional Upsert with Returning

```sql
-- Upsert and track what happened (inserted vs updated)
WITH upserted AS (
    INSERT INTO inventory (sku, quantity, warehouse_id, last_seen_at)
    SELECT sku, quantity, warehouse_id, NOW()
    FROM staging_inventory
    ON CONFLICT (sku, warehouse_id) DO UPDATE SET
        quantity     = EXCLUDED.quantity,
        last_seen_at = EXCLUDED.last_seen_at
    WHERE inventory.quantity <> EXCLUDED.quantity
    RETURNING sku, warehouse_id,
        (xmax = 0) AS was_inserted  -- xmax=0 means new row
)
SELECT
    COUNT(*) FILTER (WHERE was_inserted) AS inserted_count,
    COUNT(*) FILTER (WHERE NOT was_inserted) AS updated_count
FROM upserted;
```

### MERGE (SQL:2003 Standard -- Supported in PostgreSQL 15+)

```sql
-- Full MERGE statement for dimensional loading
MERGE INTO dim_product AS target
USING staging_product AS source
ON target.product_id = source.product_id

WHEN MATCHED AND (
    target.product_name <> source.product_name
    OR target.category <> source.category
    OR target.price <> source.price
) THEN UPDATE SET
    product_name = source.product_name,
    category     = source.category,
    price        = source.price,
    updated_at   = NOW()

WHEN NOT MATCHED THEN INSERT (
    product_id, product_name, category, price, created_at, updated_at
) VALUES (
    source.product_id, source.product_name, source.category,
    source.price, NOW(), NOW()
);
```

### Soft-Delete Merge Pattern

```sql
-- Mark records as deleted if they no longer appear in the source
WITH source_keys AS (
    SELECT DISTINCT product_id FROM staging_product
)
UPDATE dim_product
SET
    is_deleted  = TRUE,
    deleted_at  = NOW()
WHERE product_id NOT IN (SELECT product_id FROM source_keys)
  AND is_deleted = FALSE;
```

---

## JSON Operations in PostgreSQL

### Querying JSONB Columns

```sql
-- Extract nested fields from a JSONB event payload
SELECT
    event_id,
    payload->>'event_type' AS event_type,
    (payload->'user'->>'id')::BIGINT AS user_id,
    payload->'user'->>'email' AS user_email,
    (payload->'metadata'->>'amount')::NUMERIC AS amount,
    payload->'items' AS items_array,
    jsonb_array_length(payload->'items') AS item_count,
    created_at
FROM events
WHERE payload->>'event_type' = 'purchase'
  AND (payload->'metadata'->>'amount')::NUMERIC > 100;
```

### Expanding JSON Arrays into Rows

```sql
-- Flatten a JSON array of line items into individual rows
SELECT
    o.order_id,
    o.order_date,
    item->>'product_id' AS product_id,
    (item->>'quantity')::INT AS quantity,
    (item->>'unit_price')::NUMERIC(10,2) AS unit_price
FROM orders o
CROSS JOIN LATERAL jsonb_array_elements(o.line_items) AS item;
```

### Building JSON from Relational Data

```sql
-- Aggregate relational data into a JSON document
SELECT
    c.customer_id,
    c.customer_name,
    jsonb_build_object(
        'customer_id', c.customer_id,
        'name', c.customer_name,
        'total_orders', COUNT(o.order_id),
        'lifetime_value', SUM(o.total_amount),
        'recent_orders', jsonb_agg(
            jsonb_build_object(
                'order_id', o.order_id,
                'date', o.order_date,
                'amount', o.total_amount
            ) ORDER BY o.order_date DESC
        ) FILTER (WHERE o.rn <= 5)
    ) AS customer_json
FROM customers c
LEFT JOIN (
    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY customer_id ORDER BY order_date DESC
        ) AS rn
    FROM orders
) o ON c.customer_id = o.customer_id
GROUP BY c.customer_id, c.customer_name;
```

### JSONB Path Queries (PostgreSQL 12+)

```sql
-- Use jsonpath for complex JSON queries
SELECT
    event_id,
    payload
FROM events
WHERE payload @? '$.items[*] ? (@.price > 50 && @.category == "electronics")';

-- Extract matching elements with jsonb_path_query
SELECT
    event_id,
    jsonb_path_query(payload, '$.items[*] ? (@.price > 50)') AS expensive_items
FROM events;
```

### JSONB Indexing

```sql
-- GIN index for containment queries (@>, ?, ?|, ?&)
CREATE INDEX idx_events_payload ON events USING GIN (payload);

-- Expression index for frequently queried paths
CREATE INDEX idx_events_type ON events ((payload->>'event_type'));
CREATE INDEX idx_events_user_id ON events (((payload->'user'->>'id')::BIGINT));

-- Partial GIN index for a specific event type
CREATE INDEX idx_purchase_items ON events USING GIN ((payload->'items'))
WHERE payload->>'event_type' = 'purchase';
```

---

## Pivoting and Unpivoting

### Pivot with FILTER (PostgreSQL)

```sql
-- Pivot monthly revenue by category (known categories)
SELECT
    DATE_TRUNC('month', order_date)::DATE AS month,
    SUM(amount) FILTER (WHERE category = 'electronics') AS electronics,
    SUM(amount) FILTER (WHERE category = 'clothing') AS clothing,
    SUM(amount) FILTER (WHERE category = 'groceries') AS groceries,
    SUM(amount) FILTER (WHERE category = 'furniture') AS furniture,
    SUM(amount) AS total
FROM orders
GROUP BY 1
ORDER BY 1;
```

### Pivot with CASE (Portable)

```sql
-- Same pivot using CASE expressions (works in all SQL dialects)
SELECT
    DATE_TRUNC('month', order_date)::DATE AS month,
    SUM(CASE WHEN category = 'electronics' THEN amount ELSE 0 END) AS electronics,
    SUM(CASE WHEN category = 'clothing'    THEN amount ELSE 0 END) AS clothing,
    SUM(CASE WHEN category = 'groceries'   THEN amount ELSE 0 END) AS groceries,
    SUM(CASE WHEN category = 'furniture'   THEN amount ELSE 0 END) AS furniture,
    SUM(amount) AS total
FROM orders
GROUP BY 1
ORDER BY 1;
```

### Dynamic Pivot with crosstab (tablefunc)

```sql
-- Enable the extension
CREATE EXTENSION IF NOT EXISTS tablefunc;

-- Dynamic pivot using crosstab
SELECT *
FROM crosstab(
    $$
    SELECT
        DATE_TRUNC('month', order_date)::DATE AS month,
        category,
        SUM(amount) AS total
    FROM orders
    GROUP BY 1, 2
    ORDER BY 1, 2
    $$,
    $$ SELECT DISTINCT category FROM orders ORDER BY 1 $$
) AS ct(
    month DATE,
    clothing NUMERIC,
    electronics NUMERIC,
    furniture NUMERIC,
    groceries NUMERIC
);
```

### Unpivot (Columns to Rows)

```sql
-- Unpivot a wide table into long format
-- Given: metrics_wide(date, cpu_usage, memory_usage, disk_usage)
SELECT
    date,
    metric_name,
    metric_value
FROM metrics_wide
CROSS JOIN LATERAL (
    VALUES
        ('cpu_usage',    cpu_usage),
        ('memory_usage', memory_usage),
        ('disk_usage',   disk_usage)
) AS unpivoted(metric_name, metric_value)
WHERE metric_value IS NOT NULL;
```

---

## Gap-and-Island Problems

### Identify Consecutive Groups (Islands)

```sql
-- Find consecutive date ranges where a user was active
-- "Islands" = groups of consecutive active days
WITH active_days AS (
    SELECT DISTINCT
        user_id,
        activity_date
    FROM user_activity
),
grouped AS (
    SELECT
        user_id,
        activity_date,
        activity_date - (
            ROW_NUMBER() OVER (
                PARTITION BY user_id
                ORDER BY activity_date
            )
        )::INT AS grp
    FROM active_days
)
SELECT
    user_id,
    MIN(activity_date) AS streak_start,
    MAX(activity_date) AS streak_end,
    COUNT(*) AS streak_length
FROM grouped
GROUP BY user_id, grp
HAVING COUNT(*) >= 3  -- only streaks of 3+ days
ORDER BY user_id, streak_start;
```

### Gap Detection

```sql
-- Find gaps in sequential invoice numbers
WITH invoice_bounds AS (
    SELECT
        invoice_number,
        LEAD(invoice_number) OVER (ORDER BY invoice_number) AS next_invoice
    FROM invoices
)
SELECT
    invoice_number AS gap_starts_after,
    next_invoice AS gap_ends_before,
    next_invoice - invoice_number - 1 AS missing_count
FROM invoice_bounds
WHERE next_invoice - invoice_number > 1
ORDER BY invoice_number;
```

### Session Detection from Events

```sql
-- Group clickstream events into sessions (30-min inactivity = new session)
WITH time_diffs AS (
    SELECT
        user_id,
        event_timestamp,
        event_type,
        EXTRACT(EPOCH FROM (
            event_timestamp - LAG(event_timestamp) OVER (
                PARTITION BY user_id
                ORDER BY event_timestamp
            )
        )) / 60.0 AS minutes_since_last
    FROM clickstream
),
session_markers AS (
    SELECT
        *,
        SUM(
            CASE WHEN minutes_since_last > 30 OR minutes_since_last IS NULL
                 THEN 1 ELSE 0 END
        ) OVER (
            PARTITION BY user_id
            ORDER BY event_timestamp
        ) AS session_id
    FROM time_diffs
)
SELECT
    user_id,
    session_id,
    MIN(event_timestamp) AS session_start,
    MAX(event_timestamp) AS session_end,
    COUNT(*) AS event_count,
    EXTRACT(EPOCH FROM MAX(event_timestamp) - MIN(event_timestamp)) / 60.0 AS duration_minutes
FROM session_markers
GROUP BY user_id, session_id;
```

### Status Change Islands

```sql
-- Track status change periods: when did each status start and end?
WITH status_changes AS (
    SELECT
        entity_id,
        status,
        recorded_at,
        LAG(status) OVER (
            PARTITION BY entity_id ORDER BY recorded_at
        ) AS prev_status
    FROM entity_status_log
),
change_points AS (
    SELECT
        entity_id,
        status,
        recorded_at,
        SUM(CASE WHEN status <> prev_status OR prev_status IS NULL THEN 1 ELSE 0 END)
            OVER (PARTITION BY entity_id ORDER BY recorded_at) AS status_group
    FROM status_changes
)
SELECT
    entity_id,
    status,
    MIN(recorded_at) AS status_started,
    MAX(recorded_at) AS status_ended,
    COUNT(*) AS observation_count
FROM change_points
GROUP BY entity_id, status, status_group
ORDER BY entity_id, status_started;
```

---

## Date Spine Generation

### Using generate_series (PostgreSQL)

```sql
-- Generate a complete date spine
CREATE TABLE date_spine AS
SELECT
    d::DATE AS date_day,
    EXTRACT(YEAR FROM d)::INT AS year,
    EXTRACT(QUARTER FROM d)::INT AS quarter,
    EXTRACT(MONTH FROM d)::INT AS month,
    EXTRACT(DOW FROM d)::INT AS day_of_week,  -- 0=Sunday
    EXTRACT(DOY FROM d)::INT AS day_of_year,
    TO_CHAR(d, 'YYYY-MM') AS year_month,
    TO_CHAR(d, 'Day') AS day_name,
    TO_CHAR(d, 'Month') AS month_name,
    (EXTRACT(DOW FROM d) IN (0, 6)) AS is_weekend,
    DATE_TRUNC('week', d)::DATE AS week_start,
    (DATE_TRUNC('month', d) + INTERVAL '1 month - 1 day')::DATE AS month_end,
    -- Fiscal year (assuming FY starts in April)
    CASE
        WHEN EXTRACT(MONTH FROM d) >= 4
        THEN EXTRACT(YEAR FROM d)::INT
        ELSE EXTRACT(YEAR FROM d)::INT - 1
    END AS fiscal_year
FROM generate_series(
    DATE '2020-01-01',
    DATE '2030-12-31',
    INTERVAL '1 day'
) AS d;

-- Index for fast lookups
CREATE UNIQUE INDEX idx_date_spine ON date_spine (date_day);
```

### Fill Gaps Using the Date Spine

```sql
-- Ensure every date has a row, filling zeros for missing days
SELECT
    ds.date_day,
    COALESCE(m.revenue, 0) AS revenue,
    COALESCE(m.order_count, 0) AS order_count
FROM date_spine ds
LEFT JOIN daily_metrics m ON ds.date_day = m.metric_date
WHERE ds.date_day BETWEEN '2024-01-01' AND '2024-12-31'
ORDER BY ds.date_day;
```

### Hour-of-Day Spine for Detailed Analysis

```sql
-- Generate an hourly spine for a given date range
WITH hour_spine AS (
    SELECT
        ts AS hour_start,
        ts + INTERVAL '1 hour' AS hour_end
    FROM generate_series(
        TIMESTAMP '2024-01-01 00:00:00',
        TIMESTAMP '2024-01-31 23:00:00',
        INTERVAL '1 hour'
    ) AS ts
)
SELECT
    hs.hour_start,
    COALESCE(COUNT(e.event_id), 0) AS event_count
FROM hour_spine hs
LEFT JOIN events e
    ON e.event_timestamp >= hs.hour_start
    AND e.event_timestamp < hs.hour_end
GROUP BY hs.hour_start
ORDER BY hs.hour_start;
```

---

## Performance-Optimized Aggregation

### Pre-Aggregation with Materialized Views

```sql
-- Materialized view for daily aggregates (refresh on schedule)
CREATE MATERIALIZED VIEW mv_daily_sales AS
SELECT
    order_date,
    product_id,
    region,
    COUNT(*) AS order_count,
    SUM(quantity) AS total_quantity,
    SUM(amount) AS total_revenue,
    AVG(amount) AS avg_order_value,
    MIN(amount) AS min_order_value,
    MAX(amount) AS max_order_value
FROM orders
GROUP BY order_date, product_id, region
WITH DATA;

CREATE UNIQUE INDEX idx_mv_daily_sales
    ON mv_daily_sales (order_date, product_id, region);

-- Refresh concurrently (no read lock, requires unique index)
REFRESH MATERIALIZED VIEW CONCURRENTLY mv_daily_sales;
```

### Approximate Count with HyperLogLog

```sql
-- For cardinality estimation where exact counts are not needed
-- Native PostgreSQL (no extension)
SELECT
    DATE_TRUNC('day', event_timestamp) AS event_day,
    COUNT(DISTINCT user_id) AS exact_unique_users  -- expensive
FROM events
GROUP BY 1;

-- With pg_hll extension (much faster for large datasets)
-- CREATE EXTENSION hll;
-- SELECT
--     DATE_TRUNC('day', event_timestamp) AS event_day,
--     hll_cardinality(hll_add_agg(hll_hash_text(user_id::TEXT))) AS approx_unique_users
-- FROM events
-- GROUP BY 1;
```

### Partial Aggregation (Two-Phase)

```sql
-- Phase 1: Aggregate into hourly partitions (run hourly)
INSERT INTO hourly_aggregates (hour, dimension_a, dimension_b, cnt, total, min_val, max_val)
SELECT
    DATE_TRUNC('hour', event_timestamp) AS hour,
    dimension_a,
    dimension_b,
    COUNT(*) AS cnt,
    SUM(value) AS total,
    MIN(value) AS min_val,
    MAX(value) AS max_val
FROM raw_events
WHERE event_timestamp >= :last_processed_hour
  AND event_timestamp <  :current_hour
GROUP BY 1, 2, 3
ON CONFLICT (hour, dimension_a, dimension_b) DO UPDATE SET
    cnt     = hourly_aggregates.cnt + EXCLUDED.cnt,
    total   = hourly_aggregates.total + EXCLUDED.total,
    min_val = LEAST(hourly_aggregates.min_val, EXCLUDED.min_val),
    max_val = GREATEST(hourly_aggregates.max_val, EXCLUDED.max_val);

-- Phase 2: Roll up to daily (run daily)
SELECT
    hour::DATE AS day,
    dimension_a,
    dimension_b,
    SUM(cnt) AS total_count,
    SUM(total) AS total_value,
    MIN(min_val) AS min_value,
    MAX(max_val) AS max_value,
    SUM(total) / NULLIF(SUM(cnt), 0) AS avg_value
FROM hourly_aggregates
WHERE hour::DATE = :target_date
GROUP BY 1, 2, 3;
```

### GROUPING SETS for Multi-Level Aggregation

```sql
-- Compute subtotals and grand total in a single pass
SELECT
    COALESCE(region, '(All Regions)') AS region,
    COALESCE(category, '(All Categories)') AS category,
    SUM(revenue) AS total_revenue,
    COUNT(*) AS order_count,
    GROUPING(region) AS is_region_total,
    GROUPING(category) AS is_category_total
FROM orders
GROUP BY GROUPING SETS (
    (region, category),  -- detail level
    (region),            -- subtotal by region
    (category),          -- subtotal by category
    ()                   -- grand total
)
ORDER BY
    GROUPING(region),
    GROUPING(category),
    region,
    category;
```

---

## Incremental Load Patterns

### Timestamp-Based Incremental Load

```sql
-- Track high watermark in a metadata table
CREATE TABLE etl_watermarks (
    table_name TEXT PRIMARY KEY,
    last_loaded_at TIMESTAMP NOT NULL,
    rows_loaded BIGINT,
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Incremental extract using watermark
WITH watermark AS (
    SELECT last_loaded_at
    FROM etl_watermarks
    WHERE table_name = 'orders'
),
new_data AS (
    SELECT *
    FROM source_orders
    WHERE updated_at > (SELECT last_loaded_at FROM watermark)
      AND updated_at <= :batch_end_timestamp
)
INSERT INTO staging_orders
SELECT * FROM new_data;

-- Update watermark after successful load
UPDATE etl_watermarks
SET
    last_loaded_at = :batch_end_timestamp,
    rows_loaded = :rows_inserted,
    updated_at = NOW()
WHERE table_name = 'orders';
```

### Merge-Based Incremental (Full Pattern)

```sql
-- Complete incremental merge: stage -> validate -> merge -> audit
BEGIN;

-- Step 1: Load incremental data into staging
TRUNCATE staging_orders;
INSERT INTO staging_orders
SELECT * FROM source_orders
WHERE updated_at > :watermark_ts;

-- Step 2: Data quality checks
DO $$
DECLARE
    null_count INT;
    dup_count INT;
BEGIN
    SELECT COUNT(*) INTO null_count
    FROM staging_orders WHERE order_id IS NULL;

    SELECT COUNT(*) - COUNT(DISTINCT order_id) INTO dup_count
    FROM staging_orders;

    IF null_count > 0 THEN
        RAISE EXCEPTION 'Found % null order_ids in staging', null_count;
    END IF;

    IF dup_count > 0 THEN
        RAISE EXCEPTION 'Found % duplicate order_ids in staging', dup_count;
    END IF;
END $$;

-- Step 3: Merge into target
INSERT INTO dim_orders (order_id, customer_id, amount, status, updated_at)
SELECT order_id, customer_id, amount, status, updated_at
FROM staging_orders
ON CONFLICT (order_id) DO UPDATE SET
    customer_id = EXCLUDED.customer_id,
    amount      = EXCLUDED.amount,
    status      = EXCLUDED.status,
    updated_at  = EXCLUDED.updated_at
WHERE dim_orders.updated_at < EXCLUDED.updated_at;  -- only apply newer updates

-- Step 4: Audit log
INSERT INTO etl_audit_log (table_name, batch_ts, rows_staged, rows_merged, completed_at)
SELECT
    'dim_orders',
    :watermark_ts,
    (SELECT COUNT(*) FROM staging_orders),
    (SELECT COUNT(*) FROM dim_orders WHERE updated_at > :watermark_ts),
    NOW();

COMMIT;
```

---

## SCD Type 2 Implementation

### Table Structure

```sql
-- SCD Type 2 dimension table
CREATE TABLE dim_customer_scd2 (
    surrogate_key BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id BIGINT NOT NULL,           -- natural/business key
    customer_name TEXT NOT NULL,
    email TEXT,
    segment TEXT,
    region TEXT,
    -- SCD Type 2 metadata columns
    effective_from TIMESTAMP NOT NULL,
    effective_to TIMESTAMP NOT NULL DEFAULT '9999-12-31'::TIMESTAMP,
    is_current BOOLEAN NOT NULL DEFAULT TRUE,
    row_hash TEXT NOT NULL,                 -- hash of tracked columns
    created_at TIMESTAMP DEFAULT NOW(),
    -- Useful for fact table joins
    UNIQUE (customer_id, effective_from)
);

CREATE INDEX idx_scd2_current
    ON dim_customer_scd2 (customer_id) WHERE is_current = TRUE;
CREATE INDEX idx_scd2_lookup
    ON dim_customer_scd2 (customer_id, effective_from, effective_to);
```

### Full SCD Type 2 Merge Process

```sql
-- SCD Type 2 load: detect changes, expire old rows, insert new versions
BEGIN;

-- Step 1: Compute hashes for change detection
CREATE TEMP TABLE staged_customers AS
SELECT
    customer_id,
    customer_name,
    email,
    segment,
    region,
    MD5(
        COALESCE(customer_name, '') || '|' ||
        COALESCE(email, '') || '|' ||
        COALESCE(segment, '') || '|' ||
        COALESCE(region, '')
    ) AS row_hash,
    :batch_timestamp AS load_timestamp
FROM staging_customers;

-- Step 2: Identify changed and new records
CREATE TEMP TABLE changes AS
SELECT s.*
FROM staged_customers s
LEFT JOIN dim_customer_scd2 d
    ON s.customer_id = d.customer_id
    AND d.is_current = TRUE
WHERE d.surrogate_key IS NULL           -- new customer
   OR d.row_hash <> s.row_hash;        -- changed customer

-- Step 3: Expire current rows for changed records
UPDATE dim_customer_scd2
SET
    effective_to = c.load_timestamp,
    is_current = FALSE
FROM changes c
WHERE dim_customer_scd2.customer_id = c.customer_id
  AND dim_customer_scd2.is_current = TRUE;

-- Step 4: Insert new versions
INSERT INTO dim_customer_scd2 (
    customer_id, customer_name, email, segment, region,
    effective_from, effective_to, is_current, row_hash
)
SELECT
    customer_id,
    customer_name,
    email,
    segment,
    region,
    load_timestamp,
    '9999-12-31'::TIMESTAMP,
    TRUE,
    row_hash
FROM changes;

-- Step 5: Log the operation
INSERT INTO etl_audit_log (table_name, operation, row_count, batch_ts)
SELECT 'dim_customer_scd2', 'scd2_merge', COUNT(*), :batch_timestamp
FROM changes;

DROP TABLE staged_customers;
DROP TABLE changes;

COMMIT;
```

### Point-in-Time Query

```sql
-- Join fact table to SCD2 dimension at the time the fact occurred
SELECT
    f.order_id,
    f.order_date,
    f.amount,
    d.customer_name,
    d.segment,
    d.region
FROM fact_orders f
INNER JOIN dim_customer_scd2 d
    ON f.customer_id = d.customer_id
    AND f.order_date >= d.effective_from
    AND f.order_date <  d.effective_to;
```

### SCD Type 2 with Type 1 Overwrite Columns

```sql
-- Some columns update in place (Type 1), others are historized (Type 2)
-- Type 1 columns: phone_number, last_login (always overwrite)
-- Type 2 columns: segment, region, email (track history)

-- Update Type 1 columns on ALL versions
UPDATE dim_customer_scd2
SET
    phone_number = s.phone_number,
    last_login = s.last_login
FROM staging_customers s
WHERE dim_customer_scd2.customer_id = s.customer_id;

-- Then run the normal SCD Type 2 process for Type 2 columns
-- (using only segment, region, email in the hash comparison)
```

---

## Tips and Best Practices

1. **Always use explicit column lists** in INSERT statements to survive schema changes.
2. **Use `IS DISTINCT FROM`** instead of `<>` when comparing nullable columns.
3. **Prefer `FILTER (WHERE ...)` over CASE** for conditional aggregation in PostgreSQL -- it is clearer and marginally faster.
4. **Use `ROWS BETWEEN`** not `RANGE BETWEEN` for window frames unless you specifically need range semantics (which group ties together).
5. **Hash-based change detection** (MD5/SHA256 of concatenated columns) is much cheaper than comparing every column individually.
6. **Index your staging tables** on join keys before running large merge operations.
7. **Use `EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)`** to verify query plans for complex patterns.
8. **Wrap multi-statement ETL in transactions** to maintain consistency on failure.
9. **Partition large fact tables** by date to speed up incremental loads and time-range queries.
10. **Use `pg_stat_statements`** to identify your most expensive queries in production.
