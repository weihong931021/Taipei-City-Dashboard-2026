-- ============================================================================
-- 04_greenness_schema.sql
--
-- 「環保行程」沿路綠化分析用 — 2 張 PostGIS 表
--   street_trees: ~92,882 棵行道樹 (Point)，給 ST_DWithin 做半徑/buffer 查詢
--   green_parks:  ~880 個公園/綠地 (MultiPolygon)
--
-- 與既有的 ev_stations / restaurants 完全獨立，不影響任何現有 tool。
--
-- Target DB: postgres-data / dashboard
-- 性質: idempotent
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS postgis;

DROP TABLE IF EXISTS street_trees CASCADE;
CREATE TABLE street_trees (
    id          SERIAL PRIMARY KEY,
    district    TEXT,
    species     TEXT,
    height_m    NUMERIC(6,2),
    location    GEOGRAPHY(Point, 4326)
);
CREATE INDEX street_trees_loc_gix     ON street_trees USING GIST(location);
CREATE INDEX street_trees_species_idx ON street_trees(species);
CREATE INDEX street_trees_district_idx ON street_trees(district);

DROP TABLE IF EXISTS green_parks CASCADE;
CREATE TABLE green_parks (
    id        SERIAL PRIMARY KEY,
    name      TEXT,
    area_ha   NUMERIC(10,4),
    location  GEOGRAPHY(MultiPolygon, 4326)
);
CREATE INDEX green_parks_loc_gix ON green_parks USING GIST(location);
CREATE INDEX green_parks_name_idx ON green_parks(name);
