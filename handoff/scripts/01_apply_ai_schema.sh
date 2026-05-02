#!/usr/bin/env bash
# Apply 03_ai_tools_schema.sql (restaurants + ev_stations) to dashboard via
# docker exec — no host-side psql needed.
#
# Prereq: postgres-data container is up (docker compose -f docker/docker-compose-db.yaml up -d)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SQL="$REPO_ROOT/handoff/sql/03_ai_tools_schema.sql"

# Read DB creds from docker/.env if present
ENV_FILE="$REPO_ROOT/docker/.env"
if [ -f "$ENV_FILE" ]; then
  set -a; source "$ENV_FILE"; set +a
fi

DB_USER="${DB_DASHBOARD_USER:-postgres}"
DB_NAME="${DB_DASHBOARD_DBNAME:-dashboard}"
DB_PASS="${DB_DASHBOARD_PASSWORD:-}"
CONTAINER="${POSTGRES_DATA_CONTAINER:-postgres-data}"

if ! docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
  echo "ERROR: container '$CONTAINER' not running" >&2
  echo "Run first: docker compose -f docker/docker-compose-db.yaml up -d" >&2
  exit 1
fi

echo "→ Applying $SQL to $CONTAINER:$DB_NAME"
docker exec -i -e PGPASSWORD="$DB_PASS" "$CONTAINER" \
  psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$DB_NAME" < "$SQL"

echo "✓ Done. Verify:"
docker exec -e PGPASSWORD="$DB_PASS" "$CONTAINER" \
  psql -U "$DB_USER" -d "$DB_NAME" -c \
  "SELECT tablename FROM pg_tables WHERE tablename IN ('restaurants','ev_stations') ORDER BY tablename;"
