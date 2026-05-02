"""Apply geocode cache to existing PG rows. Idempotent — safe to run multiple times."""
import json
import os
import sys
from sqlalchemy import create_engine, text

cache_path = os.getenv("GEOCODE_CACHE", "/data/geocode_cache.json")
dsn = os.getenv("PG_DSN")

cache = json.loads(open(cache_path, encoding="utf-8").read())
engine = create_engine(dsn)
hits = [(addr, v["lat"], v["lng"]) for addr, v in cache.items() if v.get("lat")]
print(f"Cache: {len(cache)} entries, {len(hits)} with coords")

n_rest, n_ev = 0, 0
with engine.begin() as conn:
    for addr, lat, lng in hits:
        r = conn.execute(text("""
            UPDATE restaurants SET lat=:lat, lng=:lng,
              location = ST_SetSRID(ST_MakePoint(:lng, :lat), 4326)::geography
            WHERE address = :addr AND location IS NULL
        """), {"addr": addr, "lat": lat, "lng": lng})
        n_rest += r.rowcount
        r = conn.execute(text("""
            UPDATE ev_stations SET lat=:lat, lng=:lng,
              location = ST_SetSRID(ST_MakePoint(:lng, :lat), 4326)::geography
            WHERE address = :addr AND location IS NULL
        """), {"addr": addr, "lat": lat, "lng": lng})
        n_ev += r.rowcount

print(f"Updated {n_rest} restaurants, {n_ev} ev_stations")
