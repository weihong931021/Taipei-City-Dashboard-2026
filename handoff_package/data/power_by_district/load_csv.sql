-- ============================================================================
-- 多年版 CSV 載入：合併 104-115 (12 個檔案) 寫入 power_by_district
--
-- 處理兩種 schema:
--   舊版 (104-111): 9 欄, 用電種類, 千分位 "59,628", 類別有全形空白
--   新版 (112-115): 8 欄, 項目, 純數字
--
-- Run on postgres-data after CSVs copied to /tmp/.
-- ============================================================================

-- =================== 舊版 staging (9 欄) ===================
DROP TABLE IF EXISTS power_raw_old;
CREATE TABLE power_raw_old (
  roc_year     text,
  month        text,
  zipcode      text,
  town         text,
  category     text,
  users        text,
  contract_kw  text,
  kwh_sold     text,
  kwh_cumulative text   -- 舊版額外欄位 (售電度數當年累計)，我們不用
);

\copy power_raw_old FROM '/tmp/dist_kwh_104.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');
\copy power_raw_old FROM '/tmp/dist_kwh_105.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');
\copy power_raw_old FROM '/tmp/dist_kwh_106.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');
\copy power_raw_old FROM '/tmp/dist_kwh_107.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');
\copy power_raw_old FROM '/tmp/dist_kwh_108.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');
\copy power_raw_old FROM '/tmp/dist_kwh_109.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');
\copy power_raw_old FROM '/tmp/dist_kwh_110.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');
\copy power_raw_old FROM '/tmp/dist_kwh_111.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');

-- =================== 新版 staging (8 欄) ===================
DROP TABLE IF EXISTS power_raw_new;
CREATE TABLE power_raw_new (
  roc_year     text,
  month        text,
  zipcode      text,
  town         text,
  category     text,
  users        text,
  contract_kw  text,
  kwh_sold     text
);

\copy power_raw_new FROM '/tmp/dist_kwh_112.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');
\copy power_raw_new FROM '/tmp/dist_kwh_113.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');
\copy power_raw_new FROM '/tmp/dist_kwh_114.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');
\copy power_raw_new FROM '/tmp/dist_kwh_115.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');

-- =================== 合併清洗 ===================
DROP TABLE IF EXISTS power_by_district;
CREATE TABLE power_by_district AS
WITH unified AS (
  -- 舊版：去千分位逗號、去類別全形空白
  SELECT
    roc_year, month, zipcode, town,
    btrim(regexp_replace(category, '[　\s]+$', '')) AS category,
    replace(users,       ',', '') AS users,
    replace(contract_kw, ',', '') AS contract_kw,
    replace(kwh_sold,    ',', '') AS kwh_sold
  FROM power_raw_old
  UNION ALL
  -- 新版：直接用
  SELECT
    roc_year, month, zipcode, town,
    btrim(regexp_replace(category, '[　\s]+$', '')) AS category,
    users, contract_kw, kwh_sold
  FROM power_raw_new
)
SELECT
  (NOW() AT TIME ZONE 'Asia/Taipei')                 AS data_time,
  (roc_year::int + 1911)                             AS year,
  month::int                                         AS month,
  lpad(zipcode, 3, '0')                              AS zipcode,
  CASE
    WHEN substr(lpad(zipcode,3,'0'),1,1) = '1' THEN '臺北市'
    WHEN substr(lpad(zipcode,3,'0'),1,1) = '2' THEN '新北市'
  END                                                AS city,
  CASE
    WHEN substr(lpad(zipcode,3,'0'),1,1) = '2'
         AND right(town, 1) NOT IN ('區','市')
    THEN town || '區'
    ELSE town
  END                                                AS town,
  category,
  CASE WHEN users       ~ '^[\*＊]+$' OR users       = '' THEN NULL ELSE users::numeric       END AS users,
  CASE WHEN contract_kw ~ '^[\*＊]+$' OR contract_kw = '' THEN NULL ELSE contract_kw::numeric END AS contract_kw,
  CASE WHEN kwh_sold    ~ '^[\*＊]+$' OR kwh_sold    = '' THEN NULL ELSE kwh_sold::numeric    END AS kwh_sold
FROM unified
WHERE category !~ '小計|合計|總計'
  AND substr(lpad(zipcode,3,'0'),1,1) IN ('1','2')
  AND (
    (substr(lpad(zipcode,3,'0'),1,1) = '1'
     AND lpad(zipcode,3,'0') BETWEEN '100' AND '116')
    OR
    -- 新北市: 207(萬里), 208(金山), 220-253; 排除 200-206 基隆、209-212 連江
    (substr(lpad(zipcode,3,'0'),1,1) = '2'
     AND (
        lpad(zipcode,3,'0') IN ('207','208')
        OR lpad(zipcode,3,'0') BETWEEN '220' AND '253'
     ))
  );

DROP TABLE power_raw_old;
DROP TABLE power_raw_new;

CREATE INDEX idx_pbd_town_year_month ON power_by_district (town, year, month);
CREATE INDEX idx_pbd_category        ON power_by_district (category);
CREATE INDEX idx_pbd_year_month      ON power_by_district (year, month);

ANALYZE power_by_district;

-- Summary
SELECT
  MIN(year) AS min_year,
  MAX(year) AS max_year,
  COUNT(DISTINCT year) AS years_count,
  COUNT(DISTINCT (year, month)) AS year_months,
  COUNT(DISTINCT town) AS districts,
  COUNT(*) AS total_rows
FROM power_by_district;

-- Yearly breakdown
SELECT year, COUNT(DISTINCT month) AS months, COUNT(DISTINCT town) AS districts, COUNT(*) AS rows
FROM power_by_district
GROUP BY year
ORDER BY year;
