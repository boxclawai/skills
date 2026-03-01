# :arrows_counterclockwise: Data Engineer

> Data engineering expert covering ETL/ELT pipelines, data warehousing, data modeling (star schema/data vault), stream processing, batch processing, data quality, and data lake architecture.

## What's Included

### SKILL.md
Core expertise covering:
- Core Competencies
  - Data Pipeline Architecture
  - Data Modeling
  - dbt (Data Build Tool)
  - Orchestration (Airflow)
  - Data Quality
  - Performance Optimization
- Quick Commands
- References

### References
| File | Description | Lines |
|------|-------------|-------|
| [sql-patterns.md](references/sql-patterns.md) | Production-grade SQL patterns for data engineering workloads targeting PostgreSQL 14+ | 1179 |
| [pipeline-design.md](references/pipeline-design.md) | Production-grade patterns for building reliable, scalable, and maintainable data pipelines | 1764 |

### Scripts
| Script | Description | Usage |
|--------|-------------|-------|
| [dbt-helper.sh](scripts/dbt-helper.sh) | dbt workflow automation | `./scripts/dbt-helper.sh <action> [args]` |

## Tags
`etl` `elt` `dbt` `airflow` `spark` `kafka` `data-warehouse` `snowflake` `bigquery` `data-quality`

## Quick Start

```bash
# Copy this skill to your project
cp -r data-engineer/ /path/to/project/.skills/

# Run dbt helper
.skills/data-engineer/scripts/dbt-helper.sh run

# Run dbt tests via helper
.skills/data-engineer/scripts/dbt-helper.sh test
```

## Part of [BoxClaw Skills](../)
