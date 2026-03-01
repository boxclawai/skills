# :file_cabinet: Database Administrator

> Database administration expert covering PostgreSQL, MySQL, MongoDB, Redis, query optimization, index design, schema migrations, replication, backup/recovery strategies, connection pooling, partitioning, and database monitoring.

## What's Included

### SKILL.md
Core expertise covering:
- **Core Competencies**
  - Schema Design Principles (normalization, denormalization, naming conventions)
  - Index Strategy (when to index, index types, composite index ordering)
  - Query Optimization (EXPLAIN ANALYZE, N+1 fixes, keyset pagination, SELECT optimization)
  - Partitioning (range partitioning, benefits, PostgreSQL declarative partitioning)
  - Replication & High Availability (streaming replicas, failover, connection pooling)
  - Backup & Recovery (physical/logical backups, WAL archiving, point-in-time recovery, retention)
  - Monitoring (key metrics, diagnostic queries, tools)
- **Quick Commands** -- PostgreSQL, MySQL, Redis, and MongoDB operational commands

### References
| File | Description | Lines |
|------|-------------|-------|
| [postgresql-tuning.md](references/postgresql-tuning.md) | PostgreSQL performance tuning reference covering postgresql.conf key settings and optimization strategies | 1086 |
| [migration-patterns.md](references/migration-patterns.md) | Database migration patterns for zero-downtime deployments with guiding principles and step-by-step approaches | 924 |

### Scripts
| Script | Description | Usage |
|--------|-------------|-------|
| [pg-health-check.sh](scripts/pg-health-check.sh) | PostgreSQL health check and diagnostics tool | `./scripts/pg-health-check.sh [--url postgres://...] [--verbose]` |

## Tags
`postgresql` `mysql` `mongodb` `redis` `query-optimization` `indexing` `replication` `backup` `migration` `monitoring`

## Quick Start

```bash
# Copy this skill to your project
cp -r database-administrator/ /path/to/project/.skills/

# Run a PostgreSQL health check
.skills/database-administrator/scripts/pg-health-check.sh --url postgres://user:pass@localhost:5432/mydb --verbose
```

## Part of [BoxClaw Skills](../)
