#!/usr/bin/env bash
# md_files/ → Qdrant `documents` collection via Docker.
#
# Each .md → split by headings → chunk (500 chars, 100 overlap) →
# embedding (intfloat/multilingual-e5-base, 768d) → upsert.
#
# Prereqs:
#   - qdrant container up (docker compose -f docker-compose-db.yaml up -d)
#   - docker/.env has QDRANT_API_KEY set (matches docker-compose-db.yaml)
#
# First build downloads the embedding model (~1.1 GB) into the image. Initial
# build: ~10 min on a decent connection.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_FILE="$REPO_ROOT/docker/.env"

if [ -f "$ENV_FILE" ]; then
  set -a; source "$ENV_FILE"; set +a
fi

: "${QDRANT_API_KEY:?QDRANT_API_KEY missing in docker/.env}"
: "${QDRANT_DOC_COLLECTION:=documents}"

echo "→ Building md-ingest image"
docker build -t dashboard-md-ingest:latest "$REPO_ROOT/docker/md-ingest"

echo "→ Embedding md_files/ → Qdrant collection '$QDRANT_DOC_COLLECTION'"
# MSYS_NO_PATHCONV=1: stop Git Bash on Windows from rewriting /data/md_files
# inside docker run args.
MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' docker run --rm \
  --network br_dashboard_2026 \
  -e QDRANT_URL="http://qdrant:6333" \
  -e QDRANT_API_KEY="$QDRANT_API_KEY" \
  -e QDRANT_DOC_COLLECTION="$QDRANT_DOC_COLLECTION" \
  -v "$REPO_ROOT/md_files:/data/md_files:ro" \
  dashboard-md-ingest:latest \
  python ingest_md.py --md-dir /data/md_files

echo "✓ Done. Verify:"
echo "  curl -H \"api-key: \$QDRANT_API_KEY\" http://localhost:6333/collections/$QDRANT_DOC_COLLECTION"
