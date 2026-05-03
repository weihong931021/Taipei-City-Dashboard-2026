#!/usr/bin/env bash
# Load 2 GeoJSONs (street trees + green parks) into PostGIS via the existing
# csv-ingest image (which already has psycopg2). Reuses the image so no rebuild
# unless docker/csv-ingest/load_geojson.py changes after image build.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_FILE="$REPO_ROOT/docker/.env"
[ -f "$ENV_FILE" ] && { set -a; source "$ENV_FILE"; set +a; }

: "${DB_DASHBOARD_USER:=postgres}"
: "${DB_DASHBOARD_PASSWORD:?DB_DASHBOARD_PASSWORD missing in docker/.env}"
: "${DB_DASHBOARD_DBNAME:=dashboard}"

PG_DSN="postgresql://${DB_DASHBOARD_USER}:${DB_DASHBOARD_PASSWORD}@postgres-data:5432/${DB_DASHBOARD_DBNAME}"

echo "→ Building/refreshing csv-ingest image (picks up load_geojson.py)"
docker build -q -t dashboard-csv-ingest:latest "$REPO_ROOT/docker/csv-ingest" >/dev/null

echo "→ Running geojson ETL"
MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' docker run --rm \
  --network br_dashboard_2026 \
  -e PG_DSN="$PG_DSN" \
  -e DATA_DIR=/data \
  -v "$REPO_ROOT/Taipei-City-Dashboard-FE/public/mapData:/data:ro" \
  dashboard-csv-ingest:latest \
  python load_geojson.py

echo "✓ Done. Verify counts:"
docker exec -e PGPASSWORD="$DB_DASHBOARD_PASSWORD" postgres-data \
  psql -U "$DB_DASHBOARD_USER" -d "$DB_DASHBOARD_DBNAME" \
  -c 'SELECT (SELECT count(*) FROM street_trees) AS trees,
              (SELECT count(*) FROM green_parks)  AS parks;'
