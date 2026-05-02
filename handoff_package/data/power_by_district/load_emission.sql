-- ============================================================================
-- 載入台北市溫室氣體排放統計 → postgres-data.taipei_emission
-- Source: 行政院環保署/台北市環保局 (UTF-8 已轉換)
-- ============================================================================

DROP TABLE IF EXISTS taipei_emission_raw;
CREATE TABLE taipei_emission_raw (
  year                       text,
  residential_emission       text,
  residential_pct            text,
  transport_emission         text,
  transport_pct              text,
  waste_emission             text,
  waste_pct                  text,
  industry_emission          text,
  industry_pct               text,
  agriculture_emission       text,
  agriculture_pct            text,
  forest_emission            text,
  forest_pct                 text,
  total_emission             text,
  per_capita_emission        text
);

\copy taipei_emission_raw FROM '/tmp/taipei_emission.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');

DROP TABLE IF EXISTS taipei_emission;
CREATE TABLE taipei_emission AS
SELECT
  year::int                                             AS year,
  replace(residential_emission, ',', '')::numeric       AS residential_emission,
  replace(residential_pct,      ',', '')::numeric       AS residential_pct,
  replace(transport_emission,   ',', '')::numeric       AS transport_emission,
  replace(transport_pct,        ',', '')::numeric       AS transport_pct,
  replace(waste_emission,       ',', '')::numeric       AS waste_emission,
  replace(waste_pct,            ',', '')::numeric       AS waste_pct,
  replace(industry_emission,    ',', '')::numeric       AS industry_emission,
  replace(industry_pct,         ',', '')::numeric       AS industry_pct,
  replace(agriculture_emission, ',', '')::numeric       AS agriculture_emission,
  replace(agriculture_pct,      ',', '')::numeric       AS agriculture_pct,
  replace(forest_emission,      ',', '')::numeric       AS forest_emission,
  replace(forest_pct,           ',', '')::numeric       AS forest_pct,
  replace(total_emission,       ',', '')::numeric       AS total_emission,
  replace(per_capita_emission,  ',', '')::numeric       AS per_capita_emission
FROM taipei_emission_raw
WHERE year ~ '^\d+$';

DROP TABLE taipei_emission_raw;

CREATE INDEX idx_emission_year ON taipei_emission (year);
ANALYZE taipei_emission;

-- Sanity check
SELECT MIN(year) AS min, MAX(year) AS max, COUNT(*) AS rows FROM taipei_emission;
SELECT year, total_emission, per_capita_emission, residential_emission
FROM taipei_emission
WHERE year IN (2015, 2024)
ORDER BY year;
