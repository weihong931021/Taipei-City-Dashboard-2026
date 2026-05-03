#!/usr/bin/env python3
"""
Load 2 GeoJSONs (street trees + green parks) into PostGIS.
Connects via PG_DSN env. Mount /data with both .geojson files.

Re-run safe: TRUNCATEs both tables first.
"""

import json
import os
import sys
from pathlib import Path

import psycopg2
from psycopg2.extras import execute_values

DATA_DIR = Path(os.getenv("DATA_DIR", "/data"))
TREE_FILE = DATA_DIR / "street_tree_tpe.geojson"
PARK_FILE = DATA_DIR / "green_park_type_tpe.geojson"

PG_DSN = os.environ["PG_DSN"]


def load_trees(cur):
    print(f"→ Loading {TREE_FILE}")
    with open(TREE_FILE, encoding="utf-8") as f:
        data = json.load(f)
    rows = []
    for ft in data["features"]:
        p = ft["properties"] or {}
        g = ft["geometry"] or {}
        if g.get("type") != "Point":
            continue
        coords = g.get("coordinates")
        if not coords or len(coords) < 2:
            continue
        lng, lat = float(coords[0]), float(coords[1])
        rows.append((
            (p.get("d") or "").strip() or None,
            (p.get("s") or "").strip() or None,
            float(p["h"]) if p.get("h") not in (None, "") else None,
            lng, lat,
        ))
    print(f"  parsed {len(rows)} tree points")

    cur.execute("TRUNCATE street_trees RESTART IDENTITY")
    execute_values(
        cur,
        """
        INSERT INTO street_trees (district, species, height_m, location)
        VALUES %s
        """,
        rows,
        template="(%s, %s, %s, ST_SetSRID(ST_MakePoint(%s, %s), 4326)::geography)",
        page_size=2000,
    )
    print(f"  inserted {cur.rowcount} street_trees")


def load_parks(cur):
    print(f"→ Loading {PARK_FILE}")
    with open(PARK_FILE, encoding="utf-8") as f:
        data = json.load(f)
    rows = []
    for ft in data["features"]:
        p = ft["properties"] or {}
        g = ft["geometry"] or {}
        if g.get("type") not in ("MultiPolygon", "Polygon"):
            continue
        # Normalize Polygon -> MultiPolygon
        if g["type"] == "Polygon":
            g = {"type": "MultiPolygon", "coordinates": [g["coordinates"]]}
        rows.append((
            (p.get("name") or "").strip() or None,
            float(p["area"]) if p.get("area") not in (None, "") else None,
            json.dumps(g, ensure_ascii=False),
        ))
    print(f"  parsed {len(rows)} park polygons")

    cur.execute("TRUNCATE green_parks RESTART IDENTITY")
    execute_values(
        cur,
        """
        INSERT INTO green_parks (name, area_ha, location)
        VALUES %s
        """,
        rows,
        template="(%s, %s, ST_SetSRID(ST_GeomFromGeoJSON(%s), 4326)::geography)",
        page_size=200,
    )
    print(f"  inserted {cur.rowcount} green_parks")


def main():
    if not TREE_FILE.exists() or not PARK_FILE.exists():
        print(f"ERROR: missing {TREE_FILE} or {PARK_FILE}", file=sys.stderr)
        sys.exit(1)

    print(f"→ Connecting {PG_DSN.split('@')[-1]}")
    conn = psycopg2.connect(PG_DSN)
    conn.autocommit = False
    try:
        with conn.cursor() as cur:
            load_trees(cur)
            load_parks(cur)
        conn.commit()
        print("✓ Done")
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


if __name__ == "__main__":
    main()
