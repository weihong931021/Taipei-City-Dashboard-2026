"""
ETL: CSV files -> PostGIS tables for spatial chatbot tools.

Tables produced (in dashboard DB):
  restaurants(id, name, city, district, address, phone, eco_tags[], source, lat, lng, location)
  ev_stations(id, name, city, district, address, vehicle_type, service_type,
              operator, plug_type, connector_count, fee_required, source, lat, lng, location)

Geocoding via Mapbox; results cached on disk to avoid repeat API calls.
"""

import argparse
import json
import os
import sys
import time
from pathlib import Path
from typing import Optional

import pandas as pd
import requests
from sqlalchemy import create_engine, text

CACHE_FILE = Path(os.getenv("GEOCODE_CACHE", "/data/geocode_cache.json"))
MAPBOX_TOKEN = os.getenv("MAPBOX_TOKEN", "")
MAPBOX_ENDPOINT = "https://api.mapbox.com/geocoding/v5/mapbox.places/{}.json"

# ---------- CSV readers ----------

def read_csv_smart(path: Path) -> pd.DataFrame:
    """Read CSV trying UTF-8 with BOM first, then Big5 / cp950."""
    for enc in ("utf-8-sig", "utf-8", "cp950", "big5"):
        try:
            df = pd.read_csv(path, encoding=enc, dtype=str)
            df = df.fillna("")
            df.columns = [c.strip().lstrip("﻿") for c in df.columns]
            return df
        except UnicodeDecodeError:
            continue
    raise RuntimeError(f"could not decode {path}")


# ---------- restaurants normalizer ----------

def load_restaurants(csv_dir: Path) -> pd.DataFrame:
    rows = []

    # Taipei: 序號,餐廳類別,餐廳名稱,餐廳電話,分機,手機號碼,餐廳地址,額外環保作為
    f = csv_dir / "臺北市環保餐廳.csv"
    if f.exists():
        df = read_csv_smart(f)
        for _, r in df.iterrows():
            tags = [t.strip() for t in str(r.get("額外環保作為", "")).split(",") if t.strip()]
            rows.append({
                "name": r.get("餐廳名稱", "").strip(),
                "city": "臺北市",
                "district": extract_district(r.get("餐廳地址", "")),
                "address": r.get("餐廳地址", "").strip(),
                "phone": r.get("餐廳電話", "").strip(),
                "eco_tags": tags,
                "source": f.name,
            })

    # New Taipei: seqno,type,city,countycode,name,localcallservice,address
    f = csv_dir / "新北市環保餐廳.csv"
    if f.exists():
        df = read_csv_smart(f)
        for _, r in df.iterrows():
            rows.append({
                "name": r.get("name", "").strip(),
                "city": "新北市",
                "district": extract_district(r.get("address", "")),
                "address": r.get("address", "").strip(),
                "phone": r.get("localcallservice", "").strip(),
                "eco_tags": [r.get("type", "").strip()] if r.get("type") else [],
                "source": f.name,
            })

    df = pd.DataFrame(rows)
    df = df[(df["name"] != "") & (df["address"] != "")]
    df = df.drop_duplicates(subset=["name", "address"]).reset_index(drop=True)
    return df


# ---------- ev_stations normalizer ----------

def load_ev_stations(csv_dir: Path) -> pd.DataFrame:
    rows = []

    # 1. Taipei 機車充電站: 編號,單位,縣市,行政區,行政區域代碼,地址,備註
    f = csv_dir / "臺北市電動機車充電站.csv"
    if f.exists():
        df = read_csv_smart(f)
        for _, r in df.iterrows():
            rows.append({
                "name": r.get("單位", "").strip(),
                "city": r.get("縣市", "臺北市").strip(),
                "district": r.get("行政區", "").strip(),
                "address": r.get("地址", "").strip(),
                "vehicle_type": "scooter",
                "service_type": "charging",
                "operator": r.get("備註", "").strip(),
                "plug_type": "",
                "connector_count": None,
                "fee_required": None,
                "source": f.name,
            })

    # 2. New Taipei 機車充電站: 編號,單位,縣市,行政區,行政區域代碼,地址,備註
    f = csv_dir / "新北市電動機車充電站.csv"
    if f.exists():
        df = read_csv_smart(f)
        for _, r in df.iterrows():
            rows.append({
                "name": r.get("單位", "").strip(),
                "city": r.get("縣市", "新北市").strip(),
                "district": r.get("行政區", "").strip(),
                "address": r.get("地址", "").strip(),
                "vehicle_type": "scooter",
                "service_type": "charging",
                "operator": r.get("備註", "").strip(),
                "plug_type": "",
                "connector_count": None,
                "fee_required": None,
                "source": f.name,
            })

    # 3. New Taipei 電動汽車充電站:
    #    administrative district,charging station name,location address,station type,
    #    operational status,fee applicable,open to public,plug type,connector count
    f = csv_dir / "新北市電動汽車充電站.csv"
    if f.exists():
        df = read_csv_smart(f)
        for _, r in df.iterrows():
            try:
                cnt = int(float(r.get("connector count", "0") or 0))
            except (ValueError, TypeError):
                cnt = None
            rows.append({
                "name": r.get("charging station name", "").strip(),
                "city": "新北市",
                "district": r.get("administrative district", "").strip(),
                "address": r.get("location address", "").strip(),
                "vehicle_type": "car",
                "service_type": "charging",
                "operator": r.get("station type", "").strip(),
                "plug_type": r.get("plug type", "").strip(),
                "connector_count": cnt,
                "fee_required": _yn(r.get("fee applicable （yes/no）") or r.get("fee applicable", "")),
                "source": f.name,
            })

    # 4-6: Big5 encoded ones — header schema (after decode):
    #    序號,廠商,名稱,地址,公私,行政區域代碼
    for fname, vtype, stype in [
        ("臺北市營利型電動車充換電站資訊.csv", "car", "charging"),
        ("臺北市營利電動機車充電站.csv", "scooter", "charging"),
        ("臺北市營利電動機車換電站.csv", "scooter", "swap"),
    ]:
        f = csv_dir / fname
        if not f.exists():
            continue
        df = read_csv_smart(f)
        for _, r in df.iterrows():
            rows.append({
                "name": r.get("名稱", "").strip(),
                "city": "臺北市",
                "district": extract_district(r.get("地址", "")),
                "address": r.get("地址", "").strip(),
                "vehicle_type": vtype,
                "service_type": stype,
                "operator": r.get("廠商", "").strip(),
                "plug_type": "",
                "connector_count": None,
                "fee_required": None,
                "source": f.name,
            })

    df = pd.DataFrame(rows)
    df = df[(df["name"] != "") & (df["address"] != "")]
    df = df.drop_duplicates(subset=["name", "address"]).reset_index(drop=True)
    return df


def _yn(v: str) -> Optional[bool]:
    if not v:
        return None
    v = v.strip().lower()
    if v in ("y", "yes", "true", "是"):
        return True
    if v in ("n", "no", "false", "否"):
        return False
    return None


def extract_district(address: str) -> str:
    """臺北市松山區xxx -> 松山區. Best-effort."""
    if not address:
        return ""
    import re
    m = re.search(r"(\S{1,3}區)", address)
    return m.group(1) if m else ""


# ---------- geocoding ----------

class Geocoder:
    def __init__(self, token: str, cache_path: Path):
        if not token:
            raise RuntimeError("MAPBOX_TOKEN env required")
        self.token = token
        self.cache_path = cache_path
        cache_path.parent.mkdir(parents=True, exist_ok=True)
        if cache_path.exists():
            self.cache = json.loads(cache_path.read_text(encoding="utf-8"))
        else:
            self.cache = {}
        self.dirty_count = 0

    def save(self):
        self.cache_path.write_text(json.dumps(self.cache, ensure_ascii=False), encoding="utf-8")
        self.dirty_count = 0

    def lookup(self, address: str) -> tuple[Optional[float], Optional[float]]:
        if not address:
            return None, None
        if address in self.cache:
            v = self.cache[address]
            return v.get("lng"), v.get("lat")

        url = MAPBOX_ENDPOINT.format(requests.utils.quote(address, safe=""))
        params = {
            "access_token": self.token,
            "country": "tw",
            "language": "zh-TW",
            "limit": 1,
        }
        for attempt in range(3):
            try:
                r = requests.get(url, params=params, timeout=10)
                if r.status_code == 429:
                    time.sleep(2 ** attempt)
                    continue
                r.raise_for_status()
                data = r.json()
                feats = data.get("features", [])
                if feats:
                    lng, lat = feats[0]["center"]
                    self.cache[address] = {"lng": lng, "lat": lat}
                else:
                    self.cache[address] = {"lng": None, "lat": None}
                self.dirty_count += 1
                if self.dirty_count >= 50:
                    self.save()
                return self.cache[address]["lng"], self.cache[address]["lat"]
            except requests.RequestException as e:
                if attempt == 2:
                    print(f"  geocode FAIL {address!r}: {e}", file=sys.stderr)
                    return None, None
                time.sleep(1)
        return None, None


def geocode_df(df: pd.DataFrame, geocoder: Geocoder, label: str) -> pd.DataFrame:
    lats, lngs = [], []
    n = len(df)
    for i, addr in enumerate(df["address"]):
        lng, lat = geocoder.lookup(addr)
        lats.append(lat)
        lngs.append(lng)
        if (i + 1) % 50 == 0:
            print(f"  [{label}] geocoded {i+1}/{n}")
    geocoder.save()
    df = df.copy()
    df["lat"] = lats
    df["lng"] = lngs
    hits = df[df["lat"].notna()]
    print(f"  [{label}] geocoded {len(hits)}/{n} ({100*len(hits)/n:.1f}%)")
    return df


# ---------- DB write ----------

DDL = """
CREATE EXTENSION IF NOT EXISTS postgis;

DROP TABLE IF EXISTS restaurants CASCADE;
CREATE TABLE restaurants (
    id          SERIAL PRIMARY KEY,
    name        TEXT NOT NULL,
    city        TEXT,
    district    TEXT,
    address     TEXT,
    phone       TEXT,
    eco_tags    TEXT[],
    source      TEXT,
    lat         DOUBLE PRECISION,
    lng         DOUBLE PRECISION,
    location    GEOGRAPHY(Point, 4326)
);
CREATE INDEX restaurants_loc_gix ON restaurants USING GIST(location);
CREATE INDEX restaurants_city_idx ON restaurants(city);
CREATE INDEX restaurants_district_idx ON restaurants(district);

DROP TABLE IF EXISTS ev_stations CASCADE;
CREATE TABLE ev_stations (
    id              SERIAL PRIMARY KEY,
    name            TEXT NOT NULL,
    city            TEXT,
    district        TEXT,
    address         TEXT,
    vehicle_type    TEXT,
    service_type    TEXT,
    operator        TEXT,
    plug_type       TEXT,
    connector_count INTEGER,
    fee_required    BOOLEAN,
    source          TEXT,
    lat             DOUBLE PRECISION,
    lng             DOUBLE PRECISION,
    location        GEOGRAPHY(Point, 4326)
);
CREATE INDEX ev_stations_loc_gix ON ev_stations USING GIST(location);
CREATE INDEX ev_stations_city_idx ON ev_stations(city);
CREATE INDEX ev_stations_vehicle_idx ON ev_stations(vehicle_type);
CREATE INDEX ev_stations_service_idx ON ev_stations(service_type);
"""


def write_to_pg(restaurants: pd.DataFrame, stations: pd.DataFrame, dsn: str):
    engine = create_engine(dsn)
    with engine.begin() as conn:
        for stmt in DDL.split(";"):
            s = stmt.strip()
            if s:
                conn.execute(text(s))

    # Insert restaurants
    with engine.begin() as conn:
        for _, r in restaurants.iterrows():
            conn.execute(text("""
                INSERT INTO restaurants (name, city, district, address, phone, eco_tags, source, lat, lng, location)
                VALUES (:name, :city, :district, :address, :phone, :tags, :source, :lat, :lng,
                        CASE WHEN :lat IS NOT NULL AND :lng IS NOT NULL
                             THEN ST_SetSRID(ST_MakePoint(:lng, :lat), 4326)::geography
                             ELSE NULL END)
            """), {
                "name": r["name"], "city": r["city"], "district": r["district"],
                "address": r["address"], "phone": r["phone"],
                "tags": r["eco_tags"], "source": r["source"],
                "lat": _none_if_nan(r["lat"]),
                "lng": _none_if_nan(r["lng"]),
            })
    print(f"Inserted {len(restaurants)} restaurants")

    with engine.begin() as conn:
        for _, r in stations.iterrows():
            conn.execute(text("""
                INSERT INTO ev_stations
                  (name, city, district, address, vehicle_type, service_type, operator,
                   plug_type, connector_count, fee_required, source, lat, lng, location)
                VALUES (:name, :city, :district, :address, :vehicle_type, :service_type, :operator,
                        :plug_type, :connector_count, :fee_required, :source, :lat, :lng,
                        CASE WHEN :lat IS NOT NULL AND :lng IS NOT NULL
                             THEN ST_SetSRID(ST_MakePoint(:lng, :lat), 4326)::geography
                             ELSE NULL END)
            """), {
                "name": r["name"], "city": r["city"], "district": r["district"],
                "address": r["address"], "vehicle_type": r["vehicle_type"],
                "service_type": r["service_type"], "operator": r["operator"],
                "plug_type": r["plug_type"],
                "connector_count": _none_if_nan(r["connector_count"]),
                "fee_required": _none_if_nan(r["fee_required"]),
                "source": r["source"],
                "lat": _none_if_nan(r["lat"]),
                "lng": _none_if_nan(r["lng"]),
            })
    print(f"Inserted {len(stations)} ev_stations")


def _none_if_nan(v):
    """Convert pandas NaN/NA to Python None for psycopg2."""
    if v is None:
        return None
    if isinstance(v, bool):
        return v
    try:
        if pd.isna(v):
            return None
    except (TypeError, ValueError):
        pass
    return v


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--csv-dir", default=os.getenv("CSV_DIR", "/data/csv_files"))
    ap.add_argument("--dsn", default=os.getenv("PG_DSN", ""))
    ap.add_argument("--mapbox-token", default=MAPBOX_TOKEN)
    ap.add_argument("--cache", default=str(CACHE_FILE))
    ap.add_argument("--no-geocode", action="store_true")
    args = ap.parse_args()

    csv_dir = Path(args.csv_dir)
    if not csv_dir.is_dir():
        print(f"ERROR: {csv_dir} not found", file=sys.stderr)
        sys.exit(1)
    if not args.dsn:
        print("ERROR: PG_DSN required", file=sys.stderr)
        sys.exit(1)

    print("Loading restaurants CSVs...")
    restaurants = load_restaurants(csv_dir)
    print(f"  -> {len(restaurants)} rows")

    print("Loading ev_stations CSVs...")
    stations = load_ev_stations(csv_dir)
    print(f"  -> {len(stations)} rows")

    if args.no_geocode:
        restaurants["lat"] = None
        restaurants["lng"] = None
        stations["lat"] = None
        stations["lng"] = None
    else:
        if not args.mapbox_token:
            print("ERROR: --mapbox-token or MAPBOX_TOKEN required (or use --no-geocode)", file=sys.stderr)
            sys.exit(1)
        geocoder = Geocoder(args.mapbox_token, Path(args.cache))
        print(f"Geocoding restaurants ({len(restaurants)})...")
        restaurants = geocode_df(restaurants, geocoder, "restaurants")
        print(f"Geocoding ev_stations ({len(stations)})...")
        stations = geocode_df(stations, geocoder, "ev_stations")

    print(f"Writing to PostgreSQL...")
    write_to_pg(restaurants, stations, args.dsn)
    print("Done.")


if __name__ == "__main__":
    main()
