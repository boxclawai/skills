---
name: data-engineer
version: "1.0.0"
description: "Data engineering expert: ETL/ELT pipelines (Airflow/Dagster/Prefect), data warehousing (BigQuery/Snowflake/Redshift), data modeling (star schema/data vault), stream processing (Kafka/Flink), batch processing (Spark/dbt), data quality (Great Expectations), and data lake architecture (Delta Lake/Iceberg). Use when: (1) designing data pipelines, (2) writing SQL transformations or dbt models, (3) setting up data orchestration, (4) optimizing query performance, (5) implementing data quality checks, (6) designing data warehouse schemas. NOT for: ML model training, frontend UI, or application development."
tags: [etl, elt, dbt, airflow, spark, kafka, data-warehouse, snowflake, bigquery, data-quality]
author: "boxclaw"
references:
  - references/sql-patterns.md
  - references/pipeline-design.md
metadata:
  boxclaw:
    emoji: "🔄"
    category: "programming-role"
---

# Data Engineer

Expert guidance for building reliable, scalable data pipelines and warehouses.

## Core Competencies

### 1. Data Pipeline Architecture

```
Sources → Ingestion → Transformation → Storage → Serving

Batch (hourly/daily):
  Sources → Airflow/Dagster → Spark/dbt → Warehouse → BI Dashboard

Stream (real-time):
  Sources → Kafka → Flink/Spark Streaming → Lake → Real-time Dashboard

ELT (modern):
  Sources → Fivetran/Airbyte → Raw Layer → dbt transforms → Warehouse

Hybrid:
  Batch for historical + Stream for real-time = Lambda Architecture
  OR unified with Delta Lake / Iceberg (Lakehouse)
```

### 2. Data Modeling

#### Dimensional Modeling (Star Schema)

```sql
-- Fact table: measurable events
CREATE TABLE fact_orders (
  order_id       BIGINT PRIMARY KEY,
  customer_key   INT REFERENCES dim_customer,
  product_key    INT REFERENCES dim_product,
  date_key       INT REFERENCES dim_date,
  quantity        INT,
  amount         DECIMAL(12,2),
  discount       DECIMAL(12,2)
);

-- Dimension table: descriptive context
CREATE TABLE dim_customer (
  customer_key   INT PRIMARY KEY,  -- Surrogate key
  customer_id    VARCHAR(50),      -- Natural key
  name           VARCHAR(200),
  segment        VARCHAR(50),
  region         VARCHAR(50),
  valid_from     DATE,             -- SCD Type 2
  valid_to       DATE,
  is_current     BOOLEAN
);

-- Date dimension (pre-populated)
CREATE TABLE dim_date (
  date_key       INT PRIMARY KEY,  -- YYYYMMDD
  full_date      DATE,
  year           INT,
  quarter        INT,
  month          INT,
  week           INT,
  day_of_week    VARCHAR(10),
  is_weekend     BOOLEAN,
  is_holiday     BOOLEAN
);
```

### 3. dbt (Data Build Tool)

```sql
-- models/staging/stg_orders.sql
WITH source AS (
  SELECT * FROM {{ source('raw', 'orders') }}
)
SELECT
  id AS order_id,
  customer_id,
  CAST(created_at AS TIMESTAMP) AS ordered_at,
  status,
  total_amount
FROM source
WHERE status != 'cancelled'

-- models/marts/fct_daily_revenue.sql
SELECT
  DATE_TRUNC('day', o.ordered_at) AS order_date,
  c.segment AS customer_segment,
  COUNT(DISTINCT o.order_id) AS total_orders,
  SUM(o.total_amount) AS revenue
FROM {{ ref('stg_orders') }} o
JOIN {{ ref('stg_customers') }} c ON o.customer_id = c.customer_id
GROUP BY 1, 2
```

#### dbt Project Structure

```
dbt_project/
├── models/
│   ├── staging/        # 1:1 with source tables, light cleaning
│   │   ├── stg_orders.sql
│   │   └── _stg_sources.yml
│   ├── intermediate/   # Business logic joins
│   │   └── int_order_items.sql
│   └── marts/          # Final consumption tables
│       ├── fct_daily_revenue.sql
│       └── dim_customers.sql
├── tests/              # Custom data tests
├── macros/             # Reusable SQL functions
├── seeds/              # Static reference data (CSV)
└── dbt_project.yml
```

### 4. Orchestration (Airflow)

```python
from airflow.decorators import dag, task
from datetime import datetime

@dag(
    schedule='@daily',
    start_date=datetime(2025, 1, 1),
    catchup=False,
    tags=['etl', 'orders'],
)
def orders_etl():

    @task()
    def extract():
        """Extract from source API/DB"""
        return fetch_orders(execution_date)

    @task()
    def transform(raw_data):
        """Clean, validate, enrich"""
        return clean_and_enrich(raw_data)

    @task()
    def load(transformed):
        """Load to warehouse"""
        write_to_warehouse(transformed, table='fct_orders')

    @task()
    def quality_check():
        """Run data quality assertions"""
        assert_row_count('fct_orders', min_rows=100)
        assert_no_nulls('fct_orders', columns=['order_id', 'amount'])

    raw = extract()
    clean = transform(raw)
    load(clean) >> quality_check()

orders_etl()
```

### 5. Data Quality

```
Checks to implement:
  Freshness:     Data arrived within expected window
  Volume:        Row count within expected range
  Uniqueness:    Primary keys are unique
  Completeness:  Required fields not null
  Validity:      Values within expected ranges/formats
  Consistency:   Cross-table relationships hold

Tools:
  dbt tests:           Built-in unique, not_null, accepted_values
  Great Expectations:   Rich assertion library
  Soda:                 SQL-based quality checks
  Monte Carlo:          Automated anomaly detection

Pattern:
  1. Define expectations per table/column
  2. Run after every pipeline execution
  3. Alert on failures (don't serve bad data)
  4. Track data quality score over time
```

### 6. Performance Optimization

```
SQL:
  - Partition tables by date (reduce scan size)
  - Cluster/sort by frequently filtered columns
  - Avoid SELECT * (specify columns)
  - Use approximate functions for big aggregations
  - Materialize expensive CTEs as intermediate tables

Spark:
  - Partition data files (Parquet by date)
  - Broadcast small tables in joins
  - Avoid shuffle: colocate join keys
  - Cache intermediate DataFrames if reused
  - Monitor skew: repartition uneven keys

Storage:
  - Columnar formats (Parquet/ORC) for analytics
  - Compress: Snappy (fast) or Zstd (smaller)
  - Lifecycle policies: hot → warm → cold → archive
  - Compaction: merge small files periodically
```

## Quick Commands

```bash
# dbt
dbt run                    # Run all models
dbt run --select marts.*   # Run specific models
dbt test                   # Run tests
dbt docs generate && dbt docs serve  # Documentation

# Airflow
airflow dags list
airflow dags trigger orders_etl
airflow tasks test orders_etl extract 2025-01-01

# Spark
spark-submit --master yarn etl_job.py
pyspark --packages io.delta:delta-spark_2.13:3.0.0
```

## References

- **SQL patterns**: See [references/sql-patterns.md](references/sql-patterns.md)
- **Pipeline design**: See [references/pipeline-design.md](references/pipeline-design.md)
