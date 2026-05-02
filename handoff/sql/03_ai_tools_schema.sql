-- AI tool tables — schema only. Populate with `csv-ingest` ETL (see
-- ../scripts/2_load_csv_to_pg.sh or run docker/csv-ingest/etl.py directly).
--
-- Tables:
--   restaurants  — 環保餐廳 (台北 + 新北), AI tool: search_nearby_pois category=restaurant
--   ev_stations  — 電動車充電站 / 換電站, AI tool: search_nearby_pois category=charging_station|swap_station
--
-- Both have a PostGIS GEOGRAPHY(Point, 4326) `location` column; the AI tools
-- use ST_DWithin / ST_Distance for radius searches in metres.
--
-- Apply with:
--   psql -h <host> -U <user> -d dashboarddb -f 03_ai_tools_schema.sql

CREATE EXTENSION IF NOT EXISTS postgis;

-- ─────────── restaurants ───────────
DROP TABLE IF EXISTS restaurants CASCADE;
CREATE TABLE restaurants (
    id          SERIAL PRIMARY KEY,
    name        TEXT NOT NULL,
    city        TEXT,                                -- 臺北市 / 新北市
    district    TEXT,                                -- 信義區 / 板橋區 ...
    address     TEXT,
    phone       TEXT,
    eco_tags    TEXT[],                              -- 來源 CSV 的環保標籤陣列
    source      TEXT,                                -- 'taipei_eco_restaurants' | 'newtaipei_eco_restaurants'
    lat         DOUBLE PRECISION,
    lng         DOUBLE PRECISION,
    location    GEOGRAPHY(Point, 4326)               -- ST_MakePoint(lng, lat)
);
CREATE INDEX restaurants_loc_gix      ON restaurants USING GIST(location);
CREATE INDEX restaurants_city_idx     ON restaurants(city);
CREATE INDEX restaurants_district_idx ON restaurants(district);

-- ─────────── ev_stations ───────────
DROP TABLE IF EXISTS ev_stations CASCADE;
CREATE TABLE ev_stations (
    id              SERIAL PRIMARY KEY,
    name            TEXT NOT NULL,
    city            TEXT,                            -- 臺北市 / 新北市
    district        TEXT,
    address         TEXT,
    vehicle_type    TEXT,                            -- 'car' | 'scooter'
    service_type    TEXT,                            -- 'charging' | 'swap'
    operator        TEXT,                            -- 業者名稱 (中油 / 特斯拉 / Gogoro ...)
    plug_type       TEXT,                            -- 充電規格 (CCS1/CCS2/J1772/CHAdeMO/...)
    connector_count INTEGER,                         -- 槍/插座數
    fee_required    BOOLEAN,                         -- 是否需付費
    source          TEXT,                            -- 來源 CSV 名稱
    lat             DOUBLE PRECISION,
    lng             DOUBLE PRECISION,
    location        GEOGRAPHY(Point, 4326)
);
CREATE INDEX ev_stations_loc_gix     ON ev_stations USING GIST(location);
CREATE INDEX ev_stations_city_idx    ON ev_stations(city);
CREATE INDEX ev_stations_vehicle_idx ON ev_stations(vehicle_type);
CREATE INDEX ev_stations_service_idx ON ev_stations(service_type);
