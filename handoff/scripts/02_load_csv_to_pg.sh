#!/usr/bin/env bash
# CSV → Postgres ETL via Docker (no host Python needed).
#
# Builds docker/csv-ingest/Dockerfile, then runs the resulting image with the
# csv_files/ + cache/ folders mounted in. Inserts into dashboard.restaurants
# + dashboard.ev_stations.
#
# Prereqs:
#   - postgres-data container up (docker compose -f docker-compose-db.yaml up -d)
#   - 03_ai_tools_schema.sql applied (handoff/scripts/01_apply_ai_schema.sh)
#   - docker/.env has MAPBOX_TOKEN set (else rows missing lat/lng can't be geocoded)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_FILE="$REPO_ROOT/docker/.env"

if [ -f "$ENV_FILE" ]; then
  set -a; source "$ENV_FILE"; set +a
fi

: "${DB_DASHBOARD_USER:=postgres}"
: "${DB_DASHBOARD_PASSWORD:?DB_DASHBOARD_PASSWORD missing in docker/.env}"
: "${DB_DASHBOARD_DBNAME:=dashboard}"

PG_DSN="postgresql://${DB_DASHBOARD_USER}:${DB_DASHBOARD_PASSWORD}@postgres-data:5432/${DB_DASHBOARD_DBNAME}"

echo "→ Building csv-ingest image"
docker build -t dashboard-csv-ingest:latest "$REPO_ROOT/docker/csv-ingest"

echo "→ Running ETL"
# MSYS_NO_PATHCONV=1: stop Git Bash on Windows from translating the in-container
# paths (/data/csv_files, /app/cache) into host paths inside the docker run args.
MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' docker run --rm \
  --network br_dashboard_2026 \
  -e PG_DSN="$PG_DSN" \
  -e MAPBOX_TOKEN="${MAPBOX_TOKEN:-}" \
  -e CSV_DIR=/data/csv_files \
  -v "$REPO_ROOT/csv_files:/data/csv_files:ro" \
  -v "$REPO_ROOT/docker/csv-ingest/cache:/app/cache" \
  dashboard-csv-ingest:latest \
  python etl.py --csv-dir /data/csv_files --cache /app/cache/geocode_cache.json

echo "✓ Done. Verify counts:"
docker exec -e PGPASSWORD="$DB_DASHBOARD_PASSWORD" postgres-data \
  psql -U "$DB_DASHBOARD_USER" -d "$DB_DASHBOARD_DBNAME" \
  -c 'SELECT (SELECT count(*) FROM restaurants) AS restaurants,
              (SELECT count(*) FROM ev_stations)  AS ev_stations;'
