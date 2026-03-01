# Data Pipeline Design Patterns

Production-grade patterns for building reliable, scalable, and maintainable data pipelines.

---

## Table of Contents

1. [Idempotent Pipelines](#idempotent-pipelines)
2. [Backfill Strategies](#backfill-strategies)
3. [Schema Evolution Handling](#schema-evolution-handling)
4. [Dead Letter Queues](#dead-letter-queues)
5. [Data Lineage Tracking](#data-lineage-tracking)
6. [Pipeline Observability](#pipeline-observability)
7. [Partitioning Strategies](#partitioning-strategies)
8. [File Format Comparison](#file-format-comparison)
9. [Change Data Capture (CDC)](#change-data-capture-cdc)
10. [Data Contract Patterns](#data-contract-patterns)
11. [Cost Optimization for Cloud Pipelines](#cost-optimization-for-cloud-pipelines)

---

## Idempotent Pipelines

An idempotent pipeline produces the same result regardless of how many times it runs for the same input. This is the single most important property for reliable data pipelines.

### Core Principles

- **Deterministic outputs**: Same inputs must produce the same outputs.
- **No side effects on re-run**: Re-processing must not create duplicates or corrupt state.
- **Partition-based overwrite**: Write to discrete partitions and replace entirely on each run.

### Pattern 1: Delete-and-Replace (Partition Overwrite)

The simplest and most robust idempotency strategy.

```python
# Airflow task using partition-level idempotency
from airflow.decorators import task
from datetime import datetime

@task
def load_daily_orders(execution_date: datetime):
    """
    Idempotent daily load: delete the partition, then insert.
    Safe to re-run any number of times.
    """
    target_date = execution_date.strftime('%Y-%m-%d')

    engine.execute(f"""
        BEGIN;

        -- Step 1: Remove existing data for this partition
        DELETE FROM analytics.daily_orders
        WHERE order_date = '{target_date}';

        -- Step 2: Insert fresh data
        INSERT INTO analytics.daily_orders (
            order_date, customer_id, order_id, amount, region
        )
        SELECT
            order_date,
            customer_id,
            order_id,
            amount,
            region
        FROM staging.raw_orders
        WHERE order_date = '{target_date}';

        COMMIT;
    """)
```

### Pattern 2: Merge/Upsert with Deduplication

For pipelines where partition boundaries are not clean.

```python
@task
def upsert_customer_profiles(execution_date: datetime):
    """
    Idempotent upsert: uses natural key to merge.
    """
    engine.execute("""
        INSERT INTO analytics.customer_profiles (
            customer_id, name, email, segment, updated_at
        )
        SELECT
            customer_id,
            name,
            email,
            segment,
            updated_at
        FROM staging.customer_updates
        WHERE batch_id = :batch_id
        ON CONFLICT (customer_id) DO UPDATE SET
            name       = EXCLUDED.name,
            email      = EXCLUDED.email,
            segment    = EXCLUDED.segment,
            updated_at = EXCLUDED.updated_at
        WHERE customer_profiles.updated_at < EXCLUDED.updated_at
    """, {'batch_id': execution_date.isoformat()})
```

### Pattern 3: Staging Table Swap (Atomic Replace)

For full table refreshes where atomicity is critical.

```python
@task
def atomic_table_refresh():
    """
    Build a new table, then swap it in atomically.
    Zero downtime, fully idempotent.
    """
    engine.execute("""
        BEGIN;

        -- Build the replacement table
        DROP TABLE IF EXISTS analytics.dim_product_new;
        CREATE TABLE analytics.dim_product_new AS
        SELECT
            product_id,
            product_name,
            category,
            subcategory,
            price,
            is_active,
            NOW() AS loaded_at
        FROM staging.products;

        -- Add indexes before the swap
        CREATE UNIQUE INDEX idx_product_new_pk
            ON analytics.dim_product_new (product_id);

        -- Atomic swap
        ALTER TABLE analytics.dim_product RENAME TO dim_product_old;
        ALTER TABLE analytics.dim_product_new RENAME TO dim_product;
        DROP TABLE analytics.dim_product_old;

        COMMIT;
    """)
```

### Anti-Patterns to Avoid

| Anti-Pattern | Problem | Fix |
|---|---|---|
| INSERT without dedup check | Duplicates on retry | Use ON CONFLICT or delete-insert |
| Using auto-increment IDs as business keys | Non-deterministic across runs | Use natural keys or deterministic surrogates |
| Depending on processing order | Different results on re-run | Use explicit ordering or partition logic |
| Mixing append and overwrite in same table | Partial data on failure | One strategy per table |

---

## Backfill Strategies

### Strategy 1: Date-Partitioned Backfill

```python
# Airflow DAG with backfill support
from airflow import DAG
from airflow.decorators import task
from datetime import datetime, timedelta

default_args = {
    'owner': 'data-team',
    'retries': 3,
    'retry_delay': timedelta(minutes=5),
    # catchup=True enables backfill for missed runs
}

with DAG(
    dag_id='daily_order_pipeline',
    schedule_interval='@daily',
    start_date=datetime(2024, 1, 1),
    catchup=True,  # enables backfill
    max_active_runs=3,  # control parallelism during backfill
    default_args=default_args,
) as dag:

    @task
    def extract(ds=None):
        """Extract one day of data. ds is the logical execution date."""
        return extract_orders_for_date(ds)

    @task
    def transform(raw_data, ds=None):
        return transform_orders(raw_data, ds)

    @task
    def load(transformed_data, ds=None):
        """Idempotent load: delete-insert for the partition."""
        load_orders_partition(transformed_data, ds)

    raw = extract()
    cleaned = transform(raw)
    load(cleaned)
```

### Strategy 2: Parameterized Backfill with Range Support

```python
# CLI-driven backfill script
import click
from datetime import date, timedelta

@click.command()
@click.option('--start-date', type=click.DateTime(formats=['%Y-%m-%d']), required=True)
@click.option('--end-date', type=click.DateTime(formats=['%Y-%m-%d']), required=True)
@click.option('--parallelism', default=4, help='Max concurrent partitions')
@click.option('--dry-run', is_flag=True, help='Print plan without executing')
def backfill(start_date, end_date, parallelism, dry_run):
    """Backfill the daily pipeline for a date range."""
    dates = []
    current = start_date.date()
    while current <= end_date.date():
        dates.append(current)
        current += timedelta(days=1)

    click.echo(f"Backfilling {len(dates)} partitions from {dates[0]} to {dates[-1]}")

    if dry_run:
        for d in dates:
            click.echo(f"  [DRY RUN] Would process {d}")
        return

    from concurrent.futures import ThreadPoolExecutor, as_completed

    with ThreadPoolExecutor(max_workers=parallelism) as executor:
        futures = {
            executor.submit(process_partition, d): d for d in dates
        }
        for future in as_completed(futures):
            d = futures[future]
            try:
                result = future.result()
                click.echo(f"  Completed {d}: {result['rows']} rows")
            except Exception as e:
                click.echo(f"  FAILED {d}: {e}", err=True)

def process_partition(partition_date: date):
    """Idempotent single-partition processing."""
    raw = extract_for_date(partition_date)
    transformed = transform(raw)
    row_count = load_partition(transformed, partition_date)
    return {'rows': row_count, 'date': partition_date}
```

### Strategy 3: Snapshot-Based Backfill

For systems without reliable timestamp columns.

```python
def snapshot_backfill(snapshot_id: str):
    """
    Backfill from a full snapshot rather than incremental extracts.
    Useful when source system does not support time-range queries.
    """
    # Step 1: Load the full snapshot into a staging table
    load_snapshot_to_staging(snapshot_id)

    # Step 2: Diff against current state
    changes = engine.execute("""
        SELECT
            s.entity_id,
            CASE
                WHEN t.entity_id IS NULL THEN 'INSERT'
                WHEN s.row_hash <> t.row_hash THEN 'UPDATE'
                ELSE 'NO_CHANGE'
            END AS change_type
        FROM staging.snapshot s
        FULL OUTER JOIN target.entities t
            ON s.entity_id = t.entity_id
        WHERE t.entity_id IS NULL
           OR s.row_hash <> t.row_hash
           OR s.entity_id IS NULL
    """).fetchall()

    # Step 3: Apply changes
    apply_changes(changes, snapshot_id)
```

---

## Schema Evolution Handling

### Strategy 1: Additive-Only Schema Changes

The safest approach: only allow adding new columns, never remove or rename.

```python
# Schema evolution detector and handler
from dataclasses import dataclass
from typing import Dict, Set

@dataclass
class SchemaChange:
    added_columns: Set[str]
    removed_columns: Set[str]
    type_changes: Dict[str, tuple]  # col -> (old_type, new_type)

def detect_schema_changes(
    current_schema: dict,
    incoming_schema: dict
) -> SchemaChange:
    """Compare two schemas and classify changes."""
    current_cols = set(current_schema.keys())
    incoming_cols = set(incoming_schema.keys())

    added = incoming_cols - current_cols
    removed = current_cols - incoming_cols
    type_changes = {}

    for col in current_cols & incoming_cols:
        if current_schema[col] != incoming_schema[col]:
            type_changes[col] = (current_schema[col], incoming_schema[col])

    return SchemaChange(added, removed, type_changes)

def handle_schema_evolution(
    table_name: str,
    change: SchemaChange,
    engine,
    policy: str = 'additive_only'
):
    """Apply schema changes according to the specified policy."""
    if policy == 'additive_only':
        if change.removed_columns:
            raise SchemaEvolutionError(
                f"Column removal not allowed: {change.removed_columns}. "
                "Removed columns should be deprecated, not dropped."
            )
        if change.type_changes:
            raise SchemaEvolutionError(
                f"Type changes not allowed: {change.type_changes}. "
                "Create a new column with the desired type instead."
            )
        for col in change.added_columns:
            engine.execute(f"""
                ALTER TABLE {table_name}
                ADD COLUMN IF NOT EXISTS {col} TEXT DEFAULT NULL;
            """)

    elif policy == 'permissive':
        # Apply all changes with safety checks
        for col in change.added_columns:
            engine.execute(f"""
                ALTER TABLE {table_name}
                ADD COLUMN IF NOT EXISTS {col} TEXT DEFAULT NULL;
            """)
        for col in change.removed_columns:
            # Soft-deprecate: rename with prefix instead of dropping
            engine.execute(f"""
                ALTER TABLE {table_name}
                RENAME COLUMN {col} TO _deprecated_{col};
            """)
```

### Strategy 2: Schema Registry Integration

```python
# Schema registry pattern for Avro/Protobuf schemas
from confluent_kafka.schema_registry import SchemaRegistryClient
from confluent_kafka.schema_registry.avro import AvroSerializer

class SchemaEvolutionManager:
    """Manages schema versions through a central registry."""

    COMPATIBILITY_MODES = [
        'BACKWARD',           # new schema can read old data
        'FORWARD',            # old schema can read new data
        'FULL',               # both directions
        'BACKWARD_TRANSITIVE', # across all versions, not just latest
    ]

    def __init__(self, registry_url: str):
        self.registry = SchemaRegistryClient({'url': registry_url})

    def register_schema(
        self,
        subject: str,
        schema_str: str,
        compatibility: str = 'BACKWARD'
    ) -> int:
        """Register a new schema version with compatibility check."""
        # Set compatibility mode
        self.registry.set_compatibility(
            subject_name=subject,
            level=compatibility
        )

        # This will fail if incompatible
        schema_id = self.registry.register_schema(
            subject_name=subject,
            schema=Schema(schema_str, schema_type='AVRO')
        )
        return schema_id

    def get_latest_schema(self, subject: str) -> dict:
        """Retrieve the latest registered schema."""
        registered = self.registry.get_latest_version(subject)
        return {
            'schema_id': registered.schema_id,
            'version': registered.version,
            'schema': registered.schema.schema_str,
        }
```

### Strategy 3: Schema-on-Read with Parquet

```python
# Reading Parquet files with evolved schemas
import pyarrow.parquet as pq
import pyarrow as pa

def read_with_schema_evolution(file_paths: list, target_schema: pa.Schema):
    """
    Read multiple Parquet files that may have different schemas.
    Columns missing in older files are filled with nulls.
    """
    tables = []
    for path in file_paths:
        table = pq.read_table(path)
        # Align to the target schema: add missing columns as null
        for field in target_schema:
            if field.name not in table.column_names:
                null_array = pa.nulls(len(table), type=field.type)
                table = table.append_column(field, null_array)
        # Reorder columns to match target schema
        table = table.select([f.name for f in target_schema])
        tables.append(table)

    return pa.concat_tables(tables)
```

---

## Dead Letter Queues

A dead letter queue (DLQ) captures records that fail processing so the pipeline can continue without data loss.

### Pattern: DLQ with Classification

```python
import json
import traceback
from datetime import datetime, timezone
from enum import Enum
from dataclasses import dataclass, asdict
from typing import Optional

class FailureReason(Enum):
    SCHEMA_VALIDATION = "schema_validation"
    TRANSFORMATION_ERROR = "transformation_error"
    DUPLICATE_KEY = "duplicate_key"
    DATA_QUALITY = "data_quality"
    DOWNSTREAM_ERROR = "downstream_error"
    UNKNOWN = "unknown"

@dataclass
class DeadLetterRecord:
    record_id: str
    source_topic: str
    failure_reason: FailureReason
    error_message: str
    error_traceback: str
    original_payload: str
    pipeline_name: str
    pipeline_run_id: str
    failed_at: str
    retry_count: int = 0
    max_retries: int = 3

class DeadLetterQueue:
    """Production DLQ implementation with retry and alerting."""

    def __init__(self, engine, alert_client, table_name='etl.dead_letter_queue'):
        self.engine = engine
        self.alert_client = alert_client
        self.table_name = table_name

    def send_to_dlq(
        self,
        record: dict,
        error: Exception,
        pipeline_name: str,
        run_id: str,
        reason: FailureReason = FailureReason.UNKNOWN,
    ):
        """Send a failed record to the dead letter queue."""
        dlq_record = DeadLetterRecord(
            record_id=record.get('id', 'unknown'),
            source_topic=record.get('_source_topic', 'unknown'),
            failure_reason=reason,
            error_message=str(error),
            error_traceback=traceback.format_exc(),
            original_payload=json.dumps(record, default=str),
            pipeline_name=pipeline_name,
            pipeline_run_id=run_id,
            failed_at=datetime.now(timezone.utc).isoformat(),
        )

        self.engine.execute(f"""
            INSERT INTO {self.table_name} (
                record_id, source_topic, failure_reason, error_message,
                error_traceback, original_payload, pipeline_name,
                pipeline_run_id, failed_at, retry_count, max_retries
            ) VALUES (
                :record_id, :source_topic, :failure_reason, :error_message,
                :error_traceback, :original_payload, :pipeline_name,
                :pipeline_run_id, :failed_at, :retry_count, :max_retries
            )
        """, asdict(dlq_record))

    def get_retryable_records(self, pipeline_name: str, limit: int = 100):
        """Fetch records eligible for retry."""
        return self.engine.execute(f"""
            SELECT *
            FROM {self.table_name}
            WHERE pipeline_name = :pipeline_name
              AND retry_count < max_retries
              AND resolved_at IS NULL
            ORDER BY failed_at ASC
            LIMIT :limit
        """, {'pipeline_name': pipeline_name, 'limit': limit}).fetchall()

    def mark_resolved(self, record_ids: list):
        """Mark DLQ records as resolved after successful reprocessing."""
        self.engine.execute(f"""
            UPDATE {self.table_name}
            SET resolved_at = NOW()
            WHERE record_id = ANY(:ids)
        """, {'ids': record_ids})

    def check_alert_threshold(self, pipeline_name: str, threshold: int = 100):
        """Alert if DLQ records exceed threshold."""
        count = self.engine.execute(f"""
            SELECT COUNT(*)
            FROM {self.table_name}
            WHERE pipeline_name = :pipeline_name
              AND resolved_at IS NULL
              AND failed_at > NOW() - INTERVAL '1 hour'
        """, {'pipeline_name': pipeline_name}).scalar()

        if count >= threshold:
            self.alert_client.send_alert(
                severity='critical',
                title=f'DLQ threshold exceeded for {pipeline_name}',
                message=f'{count} unresolved records in the last hour',
            )
```

### Using the DLQ in a Pipeline

```python
def process_batch(records: list, pipeline_name: str, run_id: str):
    """Process a batch of records with DLQ support."""
    dlq = DeadLetterQueue(engine, alert_client)
    successful = []
    failed = 0

    for record in records:
        try:
            validated = validate_schema(record)
            transformed = transform(validated)
            successful.append(transformed)
        except SchemaValidationError as e:
            dlq.send_to_dlq(record, e, pipeline_name, run_id,
                            FailureReason.SCHEMA_VALIDATION)
            failed += 1
        except TransformationError as e:
            dlq.send_to_dlq(record, e, pipeline_name, run_id,
                            FailureReason.TRANSFORMATION_ERROR)
            failed += 1
        except Exception as e:
            dlq.send_to_dlq(record, e, pipeline_name, run_id,
                            FailureReason.UNKNOWN)
            failed += 1

    if successful:
        load_to_target(successful)

    # Alert if failure rate is too high
    failure_rate = failed / len(records) if records else 0
    if failure_rate > 0.05:  # more than 5% failures
        alert_client.send_alert(
            severity='warning',
            title=f'High failure rate in {pipeline_name}',
            message=f'{failure_rate:.1%} of records failed ({failed}/{len(records)})',
        )

    return {'processed': len(successful), 'failed': failed}
```

### DLQ Table Schema

```sql
CREATE TABLE etl.dead_letter_queue (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    record_id TEXT NOT NULL,
    source_topic TEXT NOT NULL,
    failure_reason TEXT NOT NULL,
    error_message TEXT NOT NULL,
    error_traceback TEXT,
    original_payload JSONB NOT NULL,
    pipeline_name TEXT NOT NULL,
    pipeline_run_id TEXT NOT NULL,
    failed_at TIMESTAMP WITH TIME ZONE NOT NULL,
    retry_count INT DEFAULT 0,
    max_retries INT DEFAULT 3,
    resolved_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_dlq_pipeline_unresolved
    ON etl.dead_letter_queue (pipeline_name, failed_at)
    WHERE resolved_at IS NULL;

CREATE INDEX idx_dlq_retryable
    ON etl.dead_letter_queue (pipeline_name, retry_count)
    WHERE resolved_at IS NULL AND retry_count < max_retries;
```

---

## Data Lineage Tracking

### Table-Level Lineage

```python
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import List, Optional
import json

@dataclass
class LineageNode:
    dataset: str              # e.g., "db.schema.table" or "s3://bucket/path"
    dataset_type: str         # "table", "file", "api", "stream"
    owner: str = ""
    tags: list = field(default_factory=list)

@dataclass
class LineageEdge:
    source: LineageNode
    target: LineageNode
    pipeline_name: str
    transformation: str       # description of the transform
    run_id: str
    timestamp: str = field(
        default_factory=lambda: datetime.now(timezone.utc).isoformat()
    )

class LineageTracker:
    """Track data lineage at the dataset and column level."""

    def __init__(self, engine):
        self.engine = engine
        self._ensure_tables()

    def _ensure_tables(self):
        self.engine.execute("""
            CREATE TABLE IF NOT EXISTS lineage.datasets (
                dataset_id TEXT PRIMARY KEY,
                dataset_type TEXT NOT NULL,
                owner TEXT,
                tags JSONB DEFAULT '[]',
                first_seen TIMESTAMP DEFAULT NOW(),
                last_seen TIMESTAMP DEFAULT NOW()
            );

            CREATE TABLE IF NOT EXISTS lineage.edges (
                edge_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
                source_dataset TEXT NOT NULL REFERENCES lineage.datasets(dataset_id),
                target_dataset TEXT NOT NULL REFERENCES lineage.datasets(dataset_id),
                pipeline_name TEXT NOT NULL,
                transformation TEXT,
                run_id TEXT NOT NULL,
                created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
            );

            CREATE TABLE IF NOT EXISTS lineage.column_lineage (
                id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
                source_dataset TEXT NOT NULL,
                source_column TEXT NOT NULL,
                target_dataset TEXT NOT NULL,
                target_column TEXT NOT NULL,
                transform_logic TEXT,
                pipeline_name TEXT NOT NULL,
                created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
            );
        """)

    def register_edge(self, edge: LineageEdge):
        """Register a lineage relationship between two datasets."""
        # Upsert source and target datasets
        for node in [edge.source, edge.target]:
            self.engine.execute("""
                INSERT INTO lineage.datasets (dataset_id, dataset_type, owner, tags)
                VALUES (:id, :type, :owner, :tags)
                ON CONFLICT (dataset_id) DO UPDATE SET
                    last_seen = NOW(),
                    owner = COALESCE(EXCLUDED.owner, lineage.datasets.owner)
            """, {
                'id': node.dataset,
                'type': node.dataset_type,
                'owner': node.owner,
                'tags': json.dumps(node.tags),
            })

        # Insert the edge
        self.engine.execute("""
            INSERT INTO lineage.edges (
                source_dataset, target_dataset, pipeline_name,
                transformation, run_id
            ) VALUES (:source, :target, :pipeline, :transform, :run_id)
        """, {
            'source': edge.source.dataset,
            'target': edge.target.dataset,
            'pipeline': edge.pipeline_name,
            'transform': edge.transformation,
            'run_id': edge.run_id,
        })

    def get_upstream(self, dataset: str, depth: int = 5) -> list:
        """Get all upstream dependencies of a dataset."""
        result = self.engine.execute("""
            WITH RECURSIVE upstream AS (
                SELECT source_dataset, target_dataset, pipeline_name, 1 AS depth
                FROM lineage.edges
                WHERE target_dataset = :dataset

                UNION ALL

                SELECT e.source_dataset, e.target_dataset, e.pipeline_name, u.depth + 1
                FROM lineage.edges e
                JOIN upstream u ON e.target_dataset = u.source_dataset
                WHERE u.depth < :max_depth
            )
            SELECT DISTINCT source_dataset, depth
            FROM upstream
            ORDER BY depth
        """, {'dataset': dataset, 'max_depth': depth})
        return result.fetchall()

    def get_downstream(self, dataset: str, depth: int = 5) -> list:
        """Get all downstream consumers of a dataset."""
        result = self.engine.execute("""
            WITH RECURSIVE downstream AS (
                SELECT source_dataset, target_dataset, pipeline_name, 1 AS depth
                FROM lineage.edges
                WHERE source_dataset = :dataset

                UNION ALL

                SELECT e.source_dataset, e.target_dataset, e.pipeline_name, d.depth + 1
                FROM lineage.edges e
                JOIN downstream d ON e.source_dataset = d.target_dataset
                WHERE d.depth < :max_depth
            )
            SELECT DISTINCT target_dataset, depth
            FROM downstream
            ORDER BY depth
        """, {'dataset': dataset, 'max_depth': depth})
        return result.fetchall()
```

### Column-Level Lineage Registration

```python
# Register column-level lineage during transformation definitions
lineage.register_column_lineage(
    pipeline_name='order_analytics',
    mappings=[
        {
            'source_dataset': 'raw.orders',
            'source_column': 'total_cents',
            'target_dataset': 'analytics.order_summary',
            'target_column': 'total_dollars',
            'transform_logic': 'total_cents / 100.0',
        },
        {
            'source_dataset': 'raw.orders',
            'source_column': 'created_at',
            'target_dataset': 'analytics.order_summary',
            'target_column': 'order_date',
            'transform_logic': 'CAST(created_at AS DATE)',
        },
        {
            'source_dataset': 'raw.customers',
            'source_column': 'segment',
            'target_dataset': 'analytics.order_summary',
            'target_column': 'customer_segment',
            'transform_logic': 'LEFT JOIN on customer_id',
        },
    ]
)
```

---

## Pipeline Observability

### Metrics, Alerts, and SLAs

```python
import time
from contextlib import contextmanager
from dataclasses import dataclass
from typing import Optional, Dict, Any

@dataclass
class PipelineMetrics:
    pipeline_name: str
    run_id: str
    started_at: float
    ended_at: Optional[float] = None
    status: str = 'running'
    rows_read: int = 0
    rows_written: int = 0
    rows_rejected: int = 0
    bytes_processed: int = 0
    error_message: Optional[str] = None
    custom_metrics: Dict[str, Any] = None

    @property
    def duration_seconds(self) -> float:
        end = self.ended_at or time.time()
        return end - self.started_at

    @property
    def throughput_rows_per_sec(self) -> float:
        duration = self.duration_seconds
        return self.rows_written / duration if duration > 0 else 0

class PipelineObserver:
    """Centralized observability for data pipelines."""

    def __init__(self, metrics_client, alert_client, engine):
        self.metrics = metrics_client   # StatsD / Datadog / CloudWatch
        self.alerts = alert_client      # PagerDuty / OpsGenie / Slack
        self.engine = engine

    @contextmanager
    def track_pipeline(self, pipeline_name: str, run_id: str):
        """Context manager that tracks pipeline execution metrics."""
        pm = PipelineMetrics(
            pipeline_name=pipeline_name,
            run_id=run_id,
            started_at=time.time(),
        )
        try:
            yield pm
            pm.status = 'success'
        except Exception as e:
            pm.status = 'failed'
            pm.error_message = str(e)
            self._send_failure_alert(pm, e)
            raise
        finally:
            pm.ended_at = time.time()
            self._emit_metrics(pm)
            self._store_run_log(pm)
            self._check_sla(pm)

    def _emit_metrics(self, pm: PipelineMetrics):
        """Emit metrics to monitoring system."""
        tags = [f'pipeline:{pm.pipeline_name}', f'status:{pm.status}']
        self.metrics.gauge('pipeline.duration_seconds', pm.duration_seconds, tags=tags)
        self.metrics.gauge('pipeline.rows_read', pm.rows_read, tags=tags)
        self.metrics.gauge('pipeline.rows_written', pm.rows_written, tags=tags)
        self.metrics.gauge('pipeline.rows_rejected', pm.rows_rejected, tags=tags)
        self.metrics.gauge('pipeline.throughput_rps', pm.throughput_rows_per_sec, tags=tags)
        self.metrics.increment(f'pipeline.runs.{pm.status}', tags=tags)

    def _store_run_log(self, pm: PipelineMetrics):
        """Persist run metadata for historical analysis."""
        self.engine.execute("""
            INSERT INTO observability.pipeline_runs (
                pipeline_name, run_id, status,
                started_at, ended_at, duration_seconds,
                rows_read, rows_written, rows_rejected,
                error_message, custom_metrics
            ) VALUES (
                :pipeline_name, :run_id, :status,
                to_timestamp(:started_at), to_timestamp(:ended_at),
                :duration, :rows_read, :rows_written, :rows_rejected,
                :error_message, :custom_metrics
            )
        """, {
            'pipeline_name': pm.pipeline_name,
            'run_id': pm.run_id,
            'status': pm.status,
            'started_at': pm.started_at,
            'ended_at': pm.ended_at,
            'duration': pm.duration_seconds,
            'rows_read': pm.rows_read,
            'rows_written': pm.rows_written,
            'rows_rejected': pm.rows_rejected,
            'error_message': pm.error_message,
            'custom_metrics': json.dumps(pm.custom_metrics or {}),
        })

    def _check_sla(self, pm: PipelineMetrics):
        """Check if pipeline met its SLA."""
        sla = self._get_sla(pm.pipeline_name)
        if sla and pm.duration_seconds > sla['max_duration_seconds']:
            self.alerts.send_alert(
                severity='warning',
                title=f'SLA breach: {pm.pipeline_name}',
                message=(
                    f'Pipeline took {pm.duration_seconds:.0f}s, '
                    f'SLA is {sla["max_duration_seconds"]}s'
                ),
            )

    def _send_failure_alert(self, pm: PipelineMetrics, error: Exception):
        """Send alert on pipeline failure."""
        self.alerts.send_alert(
            severity='critical',
            title=f'Pipeline failed: {pm.pipeline_name}',
            message=f'Run {pm.run_id} failed after {pm.duration_seconds:.0f}s: {error}',
        )
```

### Using the Observer

```python
observer = PipelineObserver(metrics_client, alert_client, engine)

with observer.track_pipeline('daily_orders', run_id='2024-03-15-001') as pm:
    # Extract
    raw_data = extract_from_source()
    pm.rows_read = len(raw_data)

    # Transform
    transformed = transform(raw_data)
    pm.rows_rejected = pm.rows_read - len(transformed)

    # Load
    load_to_target(transformed)
    pm.rows_written = len(transformed)

    # Custom metrics
    pm.custom_metrics = {
        'avg_order_value': sum(r['amount'] for r in transformed) / len(transformed),
        'unique_customers': len(set(r['customer_id'] for r in transformed)),
    }
```

### Data Freshness Monitoring

```sql
-- Monitor data freshness: alert if data is stale
CREATE TABLE observability.freshness_checks (
    table_name TEXT PRIMARY KEY,
    timestamp_column TEXT NOT NULL,
    max_delay_minutes INT NOT NULL DEFAULT 60,
    owner TEXT,
    alert_channel TEXT DEFAULT 'data-alerts'
);

-- Freshness check query (run on schedule)
SELECT
    fc.table_name,
    fc.max_delay_minutes,
    EXTRACT(EPOCH FROM (
        NOW() - MAX(t.ts)
    )) / 60.0 AS actual_delay_minutes,
    CASE
        WHEN MAX(t.ts) IS NULL THEN 'NO_DATA'
        WHEN EXTRACT(EPOCH FROM (NOW() - MAX(t.ts))) / 60.0 > fc.max_delay_minutes
        THEN 'STALE'
        ELSE 'FRESH'
    END AS status
FROM observability.freshness_checks fc
-- Dynamic SQL would be needed for each table; this is pseudocode
CROSS JOIN LATERAL (
    SELECT MAX(updated_at) AS ts
    FROM analytics.daily_orders  -- parameterized per table
) t
GROUP BY fc.table_name, fc.max_delay_minutes;
```

---

## Partitioning Strategies

### Time-Based Partitioning (PostgreSQL Declarative)

```sql
-- Create a partitioned table
CREATE TABLE events (
    event_id BIGINT GENERATED ALWAYS AS IDENTITY,
    event_type TEXT NOT NULL,
    user_id BIGINT,
    payload JSONB,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL
) PARTITION BY RANGE (created_at);

-- Create monthly partitions
CREATE TABLE events_2024_01 PARTITION OF events
    FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');
CREATE TABLE events_2024_02 PARTITION OF events
    FOR VALUES FROM ('2024-02-01') TO ('2024-03-01');
-- ... and so on

-- Automate partition creation
CREATE OR REPLACE FUNCTION create_monthly_partition(
    table_name TEXT,
    partition_date DATE
) RETURNS VOID AS $$
DECLARE
    partition_name TEXT;
    start_date DATE;
    end_date DATE;
BEGIN
    start_date := DATE_TRUNC('month', partition_date);
    end_date := start_date + INTERVAL '1 month';
    partition_name := table_name || '_' || TO_CHAR(start_date, 'YYYY_MM');

    EXECUTE format(
        'CREATE TABLE IF NOT EXISTS %I PARTITION OF %I
         FOR VALUES FROM (%L) TO (%L)',
        partition_name, table_name, start_date, end_date
    );

    -- Create indexes on the new partition
    EXECUTE format(
        'CREATE INDEX IF NOT EXISTS %I ON %I (user_id, created_at)',
        partition_name || '_user_idx', partition_name
    );
END;
$$ LANGUAGE plpgsql;
```

### Hive-Style Partitioning for Data Lakes

```python
# Writing Hive-style partitioned Parquet files
import pyarrow as pa
import pyarrow.parquet as pq
from datetime import datetime

def write_partitioned_parquet(
    df,
    base_path: str,
    partition_cols: list,
    compression: str = 'snappy',
    max_rows_per_file: int = 1_000_000,
):
    """
    Write a DataFrame as Hive-style partitioned Parquet.
    Output structure: base_path/year=2024/month=03/part-00000.parquet
    """
    table = pa.Table.from_pandas(df)

    pq.write_to_dataset(
        table,
        root_path=base_path,
        partition_cols=partition_cols,
        compression=compression,
        max_rows_per_file=max_rows_per_file,
        use_legacy_dataset=False,
        existing_data_behavior='overwrite_or_ignore',
    )

# Usage
write_partitioned_parquet(
    df=orders_df,
    base_path='s3://data-lake/orders/',
    partition_cols=['year', 'month'],
)
```

### Partition Pruning Verification

```sql
-- Verify that partition pruning is working
EXPLAIN (ANALYZE, COSTS)
SELECT COUNT(*)
FROM events
WHERE created_at >= '2024-03-01'
  AND created_at <  '2024-04-01';

-- Expected output should show:
--   -> Seq Scan on events_2024_03 (actual rows=...)
-- NOT a scan on all partitions
```

---

## File Format Comparison

### Feature Matrix

| Feature | Parquet | ORC | Avro | Delta Lake |
|---|---|---|---|---|
| **Type** | Columnar | Columnar | Row-based | Columnar (Parquet + log) |
| **Compression** | Snappy, Gzip, Zstd, LZ4 | Zlib, Snappy, LZO, Zstd | Snappy, Deflate | Same as Parquet |
| **Schema evolution** | Add columns only | Add columns only | Full (add, rename, reorder) | Full + enforcement |
| **Splittable** | Yes | Yes | Yes (with block sync) | Yes |
| **Nested data** | Excellent | Good | Good | Excellent |
| **Best for** | Analytics, data lakes | Hive ecosystem | Streaming, row-level | ACID on data lakes |
| **ACID transactions** | No | No | No | Yes |
| **Time travel** | No | No | No | Yes |
| **Predicate pushdown** | Yes (column stats) | Yes (stripe stats) | No | Yes + data skipping |
| **Typical compression ratio** | 5-10x | 5-10x | 2-5x | 5-10x |
| **Write speed** | Moderate | Moderate | Fast | Moderate |
| **Read speed (analytics)** | Fast | Fast | Slow | Fast |

### When to Use Each Format

```text
Use Parquet when:
  - Building a data lake for analytical queries
  - Working with Spark, Presto, Athena, BigQuery
  - Column pruning and predicate pushdown are important
  - Data is read much more often than written

Use ORC when:
  - Working primarily in the Hive ecosystem
  - Need ACID transactions in Hive 3+
  - Tight integration with Apache Hive

Use Avro when:
  - Schema evolution is a primary concern (Kafka schemas)
  - Row-level access patterns (full record reads)
  - Data serialization for messaging systems
  - Need both schema and data in the same file

Use Delta Lake when:
  - Need ACID transactions on a data lake
  - Require time travel / versioning
  - Running concurrent reads and writes
  - Need MERGE/UPDATE/DELETE on lake storage
  - Want schema enforcement + evolution
```

### Parquet Best Practices

```python
# Optimal Parquet writing configuration
import pyarrow.parquet as pq

pq.write_table(
    table,
    'output.parquet',
    compression='zstd',            # best compression ratio with good speed
    compression_level=3,           # zstd levels 1-22; 3 is a good balance
    row_group_size=128 * 1024,     # 128K rows per row group (tune based on data)
    use_dictionary=True,           # enable dictionary encoding for low-cardinality cols
    write_statistics=True,         # enable column statistics for predicate pushdown
    version='2.6',                 # Parquet format version
)

# Optimal row group size depends on:
# - Target file size: 128MB-1GB per file
# - Column count: more columns -> smaller row groups
# - Query patterns: larger row groups for full scans, smaller for filtered queries
```

---

## Change Data Capture (CDC)

### Pattern 1: Log-Based CDC with Debezium

```json
// Debezium connector configuration for PostgreSQL
{
    "name": "pg-cdc-connector",
    "config": {
        "connector.class": "io.debezium.connector.postgresql.PostgresConnector",
        "database.hostname": "db.example.com",
        "database.port": "5432",
        "database.user": "cdc_user",
        "database.password": "${secrets:db_password}",
        "database.dbname": "production",
        "database.server.name": "prod_pg",
        "schema.include.list": "public",
        "table.include.list": "public.orders,public.customers",
        "plugin.name": "pgoutput",
        "slot.name": "debezium_orders",
        "publication.name": "cdc_publication",
        "topic.prefix": "cdc",
        "transforms": "route",
        "transforms.route.type": "org.apache.kafka.connect.transforms.RegexRouter",
        "transforms.route.regex": "([^.]+)\\.([^.]+)\\.([^.]+)",
        "transforms.route.replacement": "cdc.$3",
        "snapshot.mode": "initial",
        "tombstones.on.delete": true,
        "decimal.handling.mode": "string",
        "time.precision.mode": "connect"
    }
}
```

### Pattern 2: CDC Event Processing

```python
# Process CDC events from Kafka and apply to target
from dataclasses import dataclass
from enum import Enum
from typing import Optional, Dict, Any

class CDCOperation(Enum):
    INSERT = 'c'   # create
    UPDATE = 'u'   # update
    DELETE = 'd'   # delete
    READ = 'r'     # snapshot read

@dataclass
class CDCEvent:
    operation: CDCOperation
    table: str
    key: dict
    before: Optional[dict]   # previous state (for updates/deletes)
    after: Optional[dict]    # new state (for inserts/updates)
    timestamp_ms: int
    source_lsn: str          # log sequence number

class CDCProcessor:
    """Process CDC events and apply to target database."""

    def __init__(self, target_engine):
        self.engine = target_engine
        self.batch = []
        self.batch_size = 1000

    def process_event(self, raw_event: dict):
        """Parse and buffer a CDC event."""
        event = CDCEvent(
            operation=CDCOperation(raw_event['op']),
            table=raw_event['source']['table'],
            key=raw_event['key'] if 'key' in raw_event else {},
            before=raw_event.get('before'),
            after=raw_event.get('after'),
            timestamp_ms=raw_event['ts_ms'],
            source_lsn=raw_event['source'].get('lsn', ''),
        )
        self.batch.append(event)

        if len(self.batch) >= self.batch_size:
            self.flush()

    def flush(self):
        """Apply buffered CDC events to the target."""
        if not self.batch:
            return

        # Deduplicate: keep only the latest event per key per table
        latest_events = {}
        for event in self.batch:
            key = (event.table, str(event.key))
            if key not in latest_events or event.timestamp_ms > latest_events[key].timestamp_ms:
                latest_events[key] = event

        # Group by table and apply
        by_table = {}
        for event in latest_events.values():
            by_table.setdefault(event.table, []).append(event)

        for table, events in by_table.items():
            self._apply_to_table(table, events)

        self.batch.clear()

    def _apply_to_table(self, table: str, events: list):
        """Apply a batch of CDC events to a single target table."""
        upserts = []
        deletes = []

        for event in events:
            if event.operation == CDCOperation.DELETE:
                deletes.append(event.key)
            else:  # INSERT, UPDATE, or READ (snapshot)
                upserts.append(event.after)

        # Batch upsert
        if upserts:
            columns = list(upserts[0].keys())
            # Build parameterized upsert (simplified)
            self.engine.execute(f"""
                INSERT INTO target.{table} ({', '.join(columns)})
                SELECT {', '.join(f':{c}' for c in columns)}
                ON CONFLICT (id) DO UPDATE SET
                    {', '.join(f'{c} = EXCLUDED.{c}' for c in columns if c != 'id')}
            """, upserts)

        # Batch delete (soft delete)
        if deletes:
            ids = [d['id'] for d in deletes]
            self.engine.execute(f"""
                UPDATE target.{table}
                SET _deleted = TRUE, _deleted_at = NOW()
                WHERE id = ANY(:ids)
            """, {'ids': ids})
```

### Pattern 3: Query-Based CDC (Fallback)

When log-based CDC is not available, use timestamp-based polling.

```python
class QueryBasedCDC:
    """Fallback CDC using polling with high watermark tracking."""

    def __init__(self, source_engine, target_engine, state_store):
        self.source = source_engine
        self.target = target_engine
        self.state = state_store

    def poll_changes(self, table: str, timestamp_col: str, key_col: str):
        """Poll for changes since last watermark."""
        watermark = self.state.get_watermark(table)

        # Extract changes
        changes = self.source.execute(f"""
            SELECT *
            FROM {table}
            WHERE {timestamp_col} > :watermark
            ORDER BY {timestamp_col}
            LIMIT 10000
        """, {'watermark': watermark}).fetchall()

        if not changes:
            return 0

        # Apply to target
        new_watermark = max(row[timestamp_col] for row in changes)
        self._apply_changes(table, changes, key_col)
        self.state.set_watermark(table, new_watermark)

        return len(changes)

    def detect_deletes(self, table: str, key_col: str):
        """
        Detect deletes by comparing source and target key sets.
        Expensive -- run periodically, not on every poll.
        """
        source_keys = set(
            row[0] for row in
            self.source.execute(f"SELECT {key_col} FROM {table}").fetchall()
        )
        target_keys = set(
            row[0] for row in
            self.target.execute(
                f"SELECT {key_col} FROM target.{table} WHERE NOT _deleted"
            ).fetchall()
        )

        deleted_keys = target_keys - source_keys
        if deleted_keys:
            self.target.execute(f"""
                UPDATE target.{table}
                SET _deleted = TRUE, _deleted_at = NOW()
                WHERE {key_col} = ANY(:keys)
            """, {'keys': list(deleted_keys)})

        return len(deleted_keys)
```

---

## Data Contract Patterns

### Contract Definition (YAML)

```yaml
# contracts/orders_v1.yaml
apiVersion: datacontract/v1
kind: DataContract
metadata:
  name: orders
  version: "1.0.0"
  owner: order-service-team
  domain: commerce
  description: "Order events from the order service"

schema:
  type: object
  properties:
    order_id:
      type: string
      format: uuid
      description: "Unique order identifier"
      required: true
      pii: false
    customer_id:
      type: integer
      description: "Customer identifier"
      required: true
    order_date:
      type: string
      format: date-time
      description: "When the order was placed (UTC)"
      required: true
    total_amount:
      type: number
      minimum: 0
      description: "Order total in USD"
      required: true
    status:
      type: string
      enum: ["pending", "confirmed", "shipped", "delivered", "cancelled"]
      required: true
    line_items:
      type: array
      items:
        type: object
        properties:
          product_id: { type: string, required: true }
          quantity: { type: integer, minimum: 1, required: true }
          unit_price: { type: number, minimum: 0, required: true }

quality:
  freshness:
    max_delay_minutes: 30
  completeness:
    required_fields_null_rate: 0.0
    optional_fields_null_rate: 0.1
  volume:
    min_daily_records: 1000
    max_daily_records: 1000000
  uniqueness:
    unique_columns: ["order_id"]

sla:
  availability: "99.9%"
  latency_p99_ms: 500
  support_channel: "#order-data-support"

consumers:
  - team: analytics
    use_case: "Revenue reporting"
  - team: ml-platform
    use_case: "Recommendation model training"
```

### Contract Validation Engine

```python
import yaml
import jsonschema
from dataclasses import dataclass
from typing import List, Optional

@dataclass
class ValidationResult:
    is_valid: bool
    errors: List[str]
    warnings: List[str]
    records_checked: int
    records_passed: int

class DataContractValidator:
    """Validate data against a data contract specification."""

    def __init__(self, contract_path: str):
        with open(contract_path) as f:
            self.contract = yaml.safe_load(f)
        self.schema = self.contract['schema']
        self.quality = self.contract.get('quality', {})

    def validate_batch(self, records: list) -> ValidationResult:
        """Validate a batch of records against the contract."""
        errors = []
        warnings = []
        passed = 0

        for i, record in enumerate(records):
            try:
                jsonschema.validate(record, self.schema)
                passed += 1
            except jsonschema.ValidationError as e:
                errors.append(f"Record {i}: {e.message}")

        # Quality checks
        quality_errors = self._check_quality(records)
        errors.extend(quality_errors)

        return ValidationResult(
            is_valid=len(errors) == 0,
            errors=errors,
            warnings=warnings,
            records_checked=len(records),
            records_passed=passed,
        )

    def _check_quality(self, records: list) -> list:
        """Run quality rule checks from the contract."""
        errors = []

        if not records:
            return errors

        # Uniqueness check
        uniqueness = self.quality.get('uniqueness', {})
        for col in uniqueness.get('unique_columns', []):
            values = [r.get(col) for r in records if r.get(col) is not None]
            if len(values) != len(set(values)):
                dup_count = len(values) - len(set(values))
                errors.append(
                    f"Uniqueness violation: {dup_count} duplicate values in '{col}'"
                )

        # Completeness check
        completeness = self.quality.get('completeness', {})
        max_null_rate = completeness.get('required_fields_null_rate', 0.0)
        required_fields = [
            k for k, v in self.schema.get('properties', {}).items()
            if v.get('required', False)
        ]
        for field in required_fields:
            null_count = sum(1 for r in records if r.get(field) is None)
            null_rate = null_count / len(records)
            if null_rate > max_null_rate:
                errors.append(
                    f"Completeness violation: '{field}' has {null_rate:.1%} null rate "
                    f"(max allowed: {max_null_rate:.1%})"
                )

        # Volume check
        volume = self.quality.get('volume', {})
        min_records = volume.get('min_daily_records', 0)
        max_records = volume.get('max_daily_records', float('inf'))
        if len(records) < min_records:
            errors.append(
                f"Volume violation: {len(records)} records "
                f"(minimum expected: {min_records})"
            )
        if len(records) > max_records:
            errors.append(
                f"Volume violation: {len(records)} records "
                f"(maximum expected: {max_records})"
            )

        return errors

    def validate_schema_compatibility(self, new_contract_path: str) -> list:
        """Check if a new contract version is backward compatible."""
        with open(new_contract_path) as f:
            new_contract = yaml.safe_load(f)

        issues = []
        old_props = self.schema.get('properties', {})
        new_props = new_contract['schema'].get('properties', {})

        # Check for removed required fields (breaking change)
        for field, spec in old_props.items():
            if spec.get('required') and field not in new_props:
                issues.append(f"BREAKING: Required field '{field}' was removed")

        # Check for type changes (breaking change)
        for field in set(old_props) & set(new_props):
            old_type = old_props[field].get('type')
            new_type = new_props[field].get('type')
            if old_type != new_type:
                issues.append(
                    f"BREAKING: Field '{field}' type changed "
                    f"from '{old_type}' to '{new_type}'"
                )

        # Check for new required fields without defaults (breaking change)
        for field, spec in new_props.items():
            if field not in old_props and spec.get('required'):
                issues.append(
                    f"BREAKING: New required field '{field}' added without default"
                )

        return issues
```

---

## Cost Optimization for Cloud Pipelines

### Strategy 1: Right-Size Compute

```python
# Dynamic cluster sizing based on data volume
class AdaptiveClusterConfig:
    """Automatically right-size compute clusters for pipeline jobs."""

    # Cluster size tiers based on data volume
    TIERS = [
        {'max_gb': 10,    'workers': 2,  'instance_type': 'm5.xlarge'},
        {'max_gb': 100,   'workers': 8,  'instance_type': 'm5.xlarge'},
        {'max_gb': 500,   'workers': 16, 'instance_type': 'm5.2xlarge'},
        {'max_gb': 2000,  'workers': 32, 'instance_type': 'm5.4xlarge'},
        {'max_gb': 10000, 'workers': 64, 'instance_type': 'r5.4xlarge'},
    ]

    @classmethod
    def get_config(cls, estimated_data_gb: float) -> dict:
        for tier in cls.TIERS:
            if estimated_data_gb <= tier['max_gb']:
                return {
                    'num_workers': tier['workers'],
                    'instance_type': tier['instance_type'],
                    'autoscaling': {
                        'min_workers': max(1, tier['workers'] // 4),
                        'max_workers': tier['workers'],
                    },
                    'spot_instances': True,  # use spot for batch workloads
                    'spot_fallback_on_demand': True,
                }
        # Largest tier for very large datasets
        return cls.TIERS[-1]
```

### Strategy 2: Storage Tiering and Lifecycle

```python
# S3 lifecycle policy for data lake cost optimization
LIFECYCLE_POLICY = {
    "Rules": [
        {
            "ID": "hot-to-warm",
            "Filter": {"Prefix": "data-lake/"},
            "Status": "Enabled",
            "Transitions": [
                {
                    "Days": 30,
                    "StorageClass": "STANDARD_IA"  # ~45% cheaper
                },
                {
                    "Days": 90,
                    "StorageClass": "GLACIER_IR"    # ~68% cheaper
                },
                {
                    "Days": 365,
                    "StorageClass": "DEEP_ARCHIVE"  # ~95% cheaper
                }
            ]
        },
        {
            "ID": "delete-staging",
            "Filter": {"Prefix": "staging/"},
            "Status": "Enabled",
            "Expiration": {"Days": 7}  # auto-delete staging after 7 days
        },
        {
            "ID": "cleanup-incomplete-uploads",
            "Filter": {"Prefix": ""},
            "Status": "Enabled",
            "AbortIncompleteMultipartUpload": {"DaysAfterInitiation": 1}
        }
    ]
}
```

### Strategy 3: Query Cost Optimization

```python
# BigQuery cost estimation before execution
def estimate_and_run_query(client, query: str, max_cost_usd: float = 5.0):
    """Estimate query cost and block if it exceeds the threshold."""
    COST_PER_TB = 6.25  # BigQuery on-demand pricing (USD per TB scanned)

    # Dry run to estimate bytes scanned
    job_config = bigquery.QueryJobConfig(dry_run=True, use_query_cache=False)
    dry_run_job = client.query(query, job_config=job_config)

    bytes_scanned = dry_run_job.total_bytes_processed
    gb_scanned = bytes_scanned / (1024 ** 3)
    tb_scanned = bytes_scanned / (1024 ** 4)
    estimated_cost = tb_scanned * COST_PER_TB

    print(f"Estimated: {gb_scanned:.2f} GB scanned, ${estimated_cost:.4f} USD")

    if estimated_cost > max_cost_usd:
        raise CostThresholdExceeded(
            f"Query would cost ${estimated_cost:.2f}, "
            f"which exceeds the ${max_cost_usd:.2f} limit. "
            f"Consider partitioning, clustering, or reducing the date range."
        )

    # Execute if within budget
    return client.query(query).result()
```

### Strategy 4: Incremental vs Full Refresh Cost Analysis

```python
# Decision framework for incremental vs full refresh
def recommend_load_strategy(
    table_size_gb: float,
    daily_change_rate: float,  # fraction of table that changes daily
    compute_cost_per_gb: float = 0.01,  # cost to process 1 GB
    storage_cost_per_gb_month: float = 0.023,
    pipeline_complexity_factor: float = 1.0,  # 1.0 = simple, 2.0+ = complex
) -> dict:
    """Recommend incremental vs full refresh based on cost analysis."""

    daily_change_gb = table_size_gb * daily_change_rate

    # Full refresh costs
    full_refresh_daily_cost = table_size_gb * compute_cost_per_gb
    full_refresh_monthly = full_refresh_daily_cost * 30

    # Incremental costs (processing + overhead for CDC tracking)
    incremental_processing = daily_change_gb * compute_cost_per_gb
    incremental_overhead = incremental_processing * 0.3 * pipeline_complexity_factor
    incremental_daily_cost = incremental_processing + incremental_overhead
    incremental_monthly = incremental_daily_cost * 30

    # Storage cost for maintaining CDC state / watermarks
    cdc_storage_monthly = daily_change_gb * 7 * storage_cost_per_gb_month

    savings_pct = (
        (full_refresh_monthly - incremental_monthly - cdc_storage_monthly)
        / full_refresh_monthly * 100
    ) if full_refresh_monthly > 0 else 0

    recommendation = 'incremental' if savings_pct > 20 else 'full_refresh'

    return {
        'recommendation': recommendation,
        'full_refresh_monthly_cost': round(full_refresh_monthly, 2),
        'incremental_monthly_cost': round(incremental_monthly + cdc_storage_monthly, 2),
        'monthly_savings_usd': round(full_refresh_monthly - incremental_monthly - cdc_storage_monthly, 2),
        'savings_percent': round(savings_pct, 1),
        'note': (
            'Incremental adds complexity. Use full refresh for tables under 10 GB '
            'or with change rates above 50%.'
        ),
    }
```

### Cost Optimization Checklist

| Area | Optimization | Typical Savings |
|---|---|---|
| **Storage** | Columnar format (Parquet/ORC) | 60-80% vs CSV |
| **Storage** | Compression (Zstd) | 40-60% on top of columnar |
| **Storage** | Lifecycle policies (IA/Glacier) | 45-95% for cold data |
| **Compute** | Spot/preemptible instances | 60-90% for batch jobs |
| **Compute** | Right-sizing clusters | 20-50% |
| **Compute** | Autoscaling | 30-60% for variable loads |
| **Query** | Partition pruning | 70-99% scan reduction |
| **Query** | Clustering/sorting | 30-70% scan reduction |
| **Query** | Materialized views | 50-90% for repeated queries |
| **Pipeline** | Incremental loads | 70-99% for low-change tables |
| **Pipeline** | Deduplication before load | Avoids reprocessing costs |
| **Network** | Same-region processing | Eliminates egress fees |

---

## Best Practices Summary

1. **Make every pipeline idempotent.** This is non-negotiable. Delete-and-replace or upsert, never blind append.
2. **Design for backfill from day one.** Every pipeline should accept a date range parameter.
3. **Schema evolution must be backward compatible.** Only add columns; never remove or rename without a migration plan.
4. **Dead letter queues are not optional.** Every pipeline that processes external data needs a DLQ.
5. **Track lineage automatically.** Instrument your pipelines to record what reads from what.
6. **Monitor data freshness, volume, and quality.** Not just pipeline success/failure.
7. **Partition everything by time.** It is the single most impactful optimization for analytical workloads.
8. **Use columnar formats with compression.** Parquet + Zstd is the default choice for data lakes.
9. **Prefer log-based CDC over polling.** It is more reliable, lower latency, and captures deletes.
10. **Data contracts are the interface between teams.** Define them, version them, validate against them.
11. **Measure cost per pipeline and per query.** You cannot optimize what you do not measure.
