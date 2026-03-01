#!/usr/bin/env bash
# migration-helper.sh - Safe database migration workflow
# Usage: ./migration-helper.sh <action> [args]
#
# Actions:
#   create <name>     Create new migration
#   status            Show migration status
#   up                Run pending migrations
#   down              Rollback last migration
#   check             Verify migration safety (pre-deploy check)
#   backup            Create DB backup before migration

set -euo pipefail

ACTION="${1:?Usage: $0 <create|status|up|down|check|backup> [args]}"
shift

DATABASE_URL="${DATABASE_URL:?DATABASE_URL environment variable required}"

# Detect ORM
detect_orm() {
  if [[ -f "prisma/schema.prisma" ]]; then
    echo "prisma"
  elif [[ -f "drizzle.config.ts" ]] || [[ -f "drizzle.config.js" ]]; then
    echo "drizzle"
  elif [[ -f "knexfile.js" ]] || [[ -f "knexfile.ts" ]]; then
    echo "knex"
  else
    echo "raw"
  fi
}

ORM=$(detect_orm)
echo "Detected ORM: $ORM"
echo ""

case "$ACTION" in
  create)
    NAME="${1:?Usage: $0 create <migration-name>}"
    case "$ORM" in
      prisma)
        npx prisma migrate dev --name "$NAME" --create-only
        echo ""
        echo "Migration created. Review the SQL before applying:"
        ls -la prisma/migrations/*"$NAME"*/migration.sql 2>/dev/null || true
        ;;
      drizzle)
        npx drizzle-kit generate --name "$NAME"
        ;;
      knex)
        npx knex migrate:make "$NAME" --knexfile knexfile.ts
        ;;
      raw)
        TIMESTAMP=$(date +%Y%m%d%H%M%S)
        DIR="migrations/${TIMESTAMP}_${NAME}"
        mkdir -p "$DIR"
        cat > "$DIR/up.sql" << 'SQL'
-- Migration: up
BEGIN;

-- Your migration SQL here

COMMIT;
SQL
        cat > "$DIR/down.sql" << 'SQL'
-- Migration: down (rollback)
BEGIN;

-- Your rollback SQL here

COMMIT;
SQL
        echo "Created: $DIR/up.sql and $DIR/down.sql"
        ;;
    esac
    ;;

  status)
    case "$ORM" in
      prisma)  npx prisma migrate status ;;
      drizzle) npx drizzle-kit check ;;
      knex)    npx knex migrate:status ;;
      raw)
        psql "$DATABASE_URL" -c "
          SELECT version, name, applied_at
          FROM schema_migrations
          ORDER BY version DESC
          LIMIT 20;" 2>/dev/null || echo "No migrations table found"
        ;;
    esac
    ;;

  up)
    echo "=== Pre-migration safety checks ==="

    # Check for pending transactions
    ACTIVE_CONNS=$(psql "$DATABASE_URL" -t -c "
      SELECT count(*) FROM pg_stat_activity
      WHERE state = 'active' AND query NOT LIKE '%pg_stat_activity%';" 2>/dev/null || echo "0")
    echo "Active connections: $ACTIVE_CONNS"

    if [[ "$ACTIVE_CONNS" -gt 10 ]]; then
      echo "WARNING: High number of active connections ($ACTIVE_CONNS)."
      echo "Consider running during low-traffic period."
      read -p "Continue? [y/N] " -n 1 -r
      echo
      [[ $REPLY =~ ^[Yy]$ ]] || exit 1
    fi

    echo ""
    echo "=== Running migrations ==="
    case "$ORM" in
      prisma)  npx prisma migrate deploy ;;
      drizzle) npx drizzle-kit migrate ;;
      knex)    npx knex migrate:latest ;;
      raw)
        for f in migrations/*/up.sql; do
          echo "Applying: $f"
          psql "$DATABASE_URL" -f "$f"
        done
        ;;
    esac
    echo ""
    echo "Migrations applied successfully."
    ;;

  down)
    echo "WARNING: Rolling back last migration."
    read -p "Are you sure? [y/N] " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]] || exit 1

    case "$ORM" in
      prisma)
        echo "Prisma doesn't support down migrations natively."
        echo "Use: npx prisma migrate resolve --rolled-back <migration-name>"
        ;;
      drizzle)
        echo "Drizzle doesn't support down migrations natively."
        echo "Options:"
        echo "  1. npx drizzle-kit drop   # Drop last migration file"
        echo "  2. Write a manual rollback SQL and apply with: psql \$DATABASE_URL -f rollback.sql"
        ;;
      knex)    npx knex migrate:rollback ;;
      raw)
        LAST=$(ls -d migrations/*/ | sort -r | head -1)
        echo "Rolling back: $LAST"
        psql "$DATABASE_URL" -f "${LAST}down.sql"
        ;;
    esac
    ;;

  check)
    echo "=== Migration Safety Check ==="

    # Check for dangerous patterns in migration files
    DANGEROUS_PATTERNS=(
      "DROP TABLE"
      "DROP COLUMN"
      "ALTER TABLE.*ALTER COLUMN.*TYPE"
      "TRUNCATE"
      "DELETE FROM.*WHERE 1=1"
      "NOT NULL" # Adding NOT NULL without DEFAULT is dangerous
    )

    FOUND_ISSUES=0

    for pattern in "${DANGEROUS_PATTERNS[@]}"; do
      MATCHES=$(grep -rn "$pattern" prisma/migrations/ migrations/ 2>/dev/null | grep -v "__ARCHIVE__" || true)
      if [[ -n "$MATCHES" ]]; then
        echo "WARNING: Found potentially dangerous pattern: $pattern"
        echo "$MATCHES"
        echo ""
        FOUND_ISSUES=$((FOUND_ISSUES + 1))
      fi
    done

    if [[ $FOUND_ISSUES -eq 0 ]]; then
      echo "No dangerous patterns found. Migration looks safe."
    else
      echo ""
      echo "Found $FOUND_ISSUES potential issues. Review carefully before applying."
    fi
    ;;

  backup)
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    BACKUP_FILE="backups/db_backup_${TIMESTAMP}.dump"
    mkdir -p backups

    echo "Creating database backup..."
    pg_dump "$DATABASE_URL" --format=custom --file="$BACKUP_FILE" --verbose 2>&1 | tail -5

    SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
    echo ""
    echo "Backup created: $BACKUP_FILE ($SIZE)"
    echo "Restore with: pg_restore -d \$DATABASE_URL $BACKUP_FILE"
    ;;

  *)
    echo "Unknown action: $ACTION"
    echo "Usage: $0 <create|status|up|down|check|backup> [args]"
    exit 1
    ;;
esac
