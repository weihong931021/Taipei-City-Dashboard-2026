-- ============================================================================
-- MIGRATION.sql — 永續環境組件整合包
--
-- 目標 DB: postgres-manager (dashboardmanager)
-- 前置條件: postgres-data 已執行 load_csv.sql + load_emission.sql
--
-- 本腳本 idempotent — 重複執行會先清乾淨再重新建立。
--
-- 內容:
--   1. components × 2  (id 由 sequence 動態分配)
--   2. component_maps × 1 (3D fill-extrusion 雙北行政區)
--   3. component_charts × 2 (圖表樣式)
--   4. query_charts × 4 (2 components × 2 cities = taipei/metrotaipei)
--   5. dashboards × 1 (新儀表板「永續環境」)
--   6. dashboard_groups × 1 (連結到 metrotaipei group)
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 0. CLEANUP — 移除任何先前安裝
-- ----------------------------------------------------------------------------

-- 從所有 dashboards 移除本套組件
UPDATE dashboards
SET components = (
    SELECT COALESCE(array_agg(c)::integer[], ARRAY[]::integer[])
    FROM unnest(components) c
    WHERE c NOT IN (
        SELECT id FROM components
        WHERE index IN ('power_by_district', 'power_vs_emission_taipei')
    )
);

-- 移除整個「永續環境」儀表板（含 dashboard_groups 關聯，靠 ON DELETE CASCADE 或手動）
DELETE FROM dashboard_groups WHERE dashboard_id IN (
    SELECT id FROM dashboards WHERE index = 'metrotaipei_sustainability'
);
DELETE FROM dashboards WHERE index = 'metrotaipei_sustainability';

-- 移除 query_charts / component_charts / components / component_maps
DELETE FROM query_charts     WHERE index IN ('power_by_district', 'power_vs_emission_taipei');
DELETE FROM component_charts WHERE index IN ('power_by_district', 'power_vs_emission_taipei');
DELETE FROM components       WHERE index IN ('power_by_district', 'power_vs_emission_taipei');
DELETE FROM component_maps   WHERE title IN (
    '2025年雙北行政區用電量3D分布',
    '2025年雙北行政區用電量分布',
    '2025年台北市行政區用電量分布'
);

-- ----------------------------------------------------------------------------
-- 1. components — 註冊兩個組件（id 自動分配）
-- ----------------------------------------------------------------------------
INSERT INTO components (index, name)
VALUES
    ('power_by_district',        '雙北各行政區用電統計'),
    ('power_vs_emission_taipei', '台北市歷年碳排部門結構');

-- ----------------------------------------------------------------------------
-- 2. component_maps — 3D fill-extrusion 雙北行政區地圖
--    高度 = 2025 年各區用電量（萬度 / 100 = 公尺）
--    顏色 = 4 級紅色排名
--    重用既有 public/mapData/metrotaipei_town.geojson (NLSC 行政區界)
-- ----------------------------------------------------------------------------
INSERT INTO component_maps (index, title, type, source, paint, property)
VALUES (
  'metrotaipei_town',
  '2025年雙北行政區用電量3D分布',
  'fill-extrusion',
  'geojson',
  $${
    "fill-extrusion-color": [
      "match", ["get", "TNAME"],
      "板橋區", "#CC0000", "中和區", "#CC0000", "三重區", "#CC0000",
      "新莊區", "#CC0000", "新店區", "#CC0000", "大安區", "#CC0000",
      "中山區", "#CC0000", "士林區", "#CC0000", "淡水區", "#CC0000",
      "內湖區", "#CC0000", "汐止區", "#CC0000",
      "北投區", "#FF6666", "文山區", "#FF6666", "土城區", "#FF6666",
      "永和區", "#FF6666", "信義區", "#FF6666", "松山區", "#FF6666",
      "蘆洲區", "#FF6666", "萬華區", "#FF6666", "樹林區", "#FF6666",
      "林口區", "#FF6666",
      "中正區", "#FFB3B3", "大同區", "#FFB3B3", "五股區", "#FFB3B3",
      "三峽區", "#FFB3B3", "南港區", "#FFB3B3", "鶯歌區", "#FFB3B3",
      "泰山區", "#FFB3B3", "八里區", "#FFB3B3", "瑞芳區", "#FFB3B3",
      "三芝區", "#FFB3B3",
      "深坑區", "#FFE5E5", "金山區", "#FFE5E5", "萬里區", "#FFE5E5",
      "貢寮區", "#FFE5E5", "石門區", "#FFE5E5", "石碇區", "#FFE5E5",
      "雙溪區", "#FFE5E5", "坪林區", "#FFE5E5", "平溪區", "#FFE5E5",
      "烏來區", "#FFE5E5",
      "#CCCCCC"
    ],
    "fill-extrusion-height": [
      "match", ["get", "TNAME"],
      "板橋區", 1071, "中和區", 917, "三重區", 910, "新莊區", 822,
      "新店區", 689, "大安區", 609, "中山區", 572, "士林區", 551,
      "淡水區", 549, "內湖區", 538, "汐止區", 528, "北投區", 479,
      "文山區", 466, "土城區", 443, "永和區", 423, "信義區", 411,
      "松山區", 399, "蘆洲區", 368, "萬華區", 346, "樹林區", 345,
      "林口區", 337, "中正區", 312, "大同區", 245, "五股區", 244,
      "三峽區", 241, "南港區", 198, "鶯歌區", 177, "泰山區", 135,
      "八里區", 103, "瑞芳區", 71, "三芝區", 53, "深坑區", 52,
      "金山區", 38, "萬里區", 32, "貢寮區", 20, "石門區", 17,
      "石碇區", 15, "雙溪區", 15, "坪林區", 10, "平溪區", 7,
      "烏來區", 7,
      0
    ],
    "fill-extrusion-base": 0,
    "fill-extrusion-opacity": 0.8
  }$$::json,
  $$[
    {"key":"TNAME","name":"行政區"},
    {"key":"PNAME","name":"城市"}
  ]$$::json
);

-- ----------------------------------------------------------------------------
-- 3. component_charts — 圖表樣式
-- ----------------------------------------------------------------------------

-- 用電統計：藍綠柱(用電量) + 橘紅折線(成長率)
INSERT INTO component_charts (index, color, types, unit)
VALUES (
    'power_by_district',
    '{#5C9EAD,#E76F51}',
    '{ColumnLineChart}',
    '萬度'
);

-- 碳排部門：6 部門色
INSERT INTO component_charts (index, color, types, unit)
VALUES (
    'power_vs_emission_taipei',
    '{#2E7D32,#FFC107,#FF9800,#9C27B0,#FF5722,#1976D2}',
    '{ColumnChart,BarPercentChart}',
    '萬公噸'
);

-- ----------------------------------------------------------------------------
-- 4. query_charts — 4 筆 (2 components × 2 cities)
-- ----------------------------------------------------------------------------

-- 4.1 用電統計 (taipei) ----------------------------------------------------
INSERT INTO query_charts (
    index, query_type, query_chart, query_history, city,
    map_config_ids, map_filter,
    time_from, source, short_desc, long_desc, use_case,
    links, contributors, created_at, updated_at
)
SELECT
    'power_by_district', 'time',
    $$WITH yearly AS (
        SELECT year, SUM(kwh_sold) AS total_kwh
        FROM power_by_district
        WHERE category = '1表燈非營業用'
          AND city = '臺北市'
          AND year BETWEEN 2015 AND 2025
        GROUP BY year
      ),
      base AS (SELECT total_kwh AS base_kwh FROM yearly WHERE year = 2015),
      s1 AS (
        SELECT (year || '-01-01')::timestamptz AS x_axis,
               '用電量(萬度)' AS y_axis,
               ROUND(total_kwh / 10000.0)::bigint AS data,
               1 AS so
        FROM yearly
      ),
      s2 AS (
        SELECT (year || '-01-01')::timestamptz AS x_axis,
               '成長率(%)' AS y_axis,
               ROUND(100.0 * (total_kwh - base_kwh) / NULLIF(base_kwh, 0), 1)::bigint AS data,
               2 AS so
        FROM yearly, base
      )
      SELECT x_axis, y_axis, data
      FROM (SELECT * FROM s1 UNION ALL SELECT * FROM s2) c
      ORDER BY so, x_axis$$,
    $$SELECT (year || '-' || lpad(month::text, 2, '0') || '-01')::timestamptz AS x_axis,
             town AS y_axis,
             ROUND(SUM(kwh_sold)/10000.0)::bigint AS data
      FROM power_by_district
      WHERE category = '1表燈非營業用'
        AND city = '臺北市'
        AND year BETWEEN 2015 AND 2025
      GROUP BY year, month, town
      ORDER BY x_axis, y_axis$$,
    'taipei',
    ARRAY[(SELECT id FROM component_maps WHERE title = '2025年雙北行政區用電量3D分布')]::integer[],
    '{"mode":"byParam","byParam":{"xParam":"TNAME"}}'::json,
    'static', '台灣電力公司',
    '台北市民生用電歷年總量與成長率（2015-2025）',
    '資料來源為「台灣電力公司鄉鎮市(郵遞區)別用電統計資料」。主圖表呈現台北市民生（表燈非營業用）用電量的 11 年變化軌跡，柱狀為各年用電量（萬度），折線為相對 2015 基準的累計成長率（%）。',
    '主圖揭示台北市用電 10 年來的成長趨勢，地圖呈現 2025 年完整年度的各區用電強度排名，協助識別需要優先輔導節能或擴容的行政區。',
    ARRAY['https://data.gov.tw/dataset/14135']::varchar[],
    ARRAY[]::varchar[],
    NOW(), NOW();

-- 4.2 用電統計 (metrotaipei) ----------------------------------------------
INSERT INTO query_charts (
    index, query_type, query_chart, query_history, city,
    map_config_ids, map_filter,
    time_from, source, short_desc, long_desc, use_case,
    links, contributors, created_at, updated_at
)
SELECT
    'power_by_district', 'time',
    $$WITH yearly AS (
        SELECT year, SUM(kwh_sold) AS total_kwh
        FROM power_by_district
        WHERE category = '1表燈非營業用'
          AND year BETWEEN 2015 AND 2025
        GROUP BY year
      ),
      base AS (SELECT total_kwh AS base_kwh FROM yearly WHERE year = 2015),
      s1 AS (
        SELECT (year || '-01-01')::timestamptz AS x_axis,
               '用電量(萬度)' AS y_axis,
               ROUND(total_kwh / 10000.0)::bigint AS data,
               1 AS so
        FROM yearly
      ),
      s2 AS (
        SELECT (year || '-01-01')::timestamptz AS x_axis,
               '成長率(%)' AS y_axis,
               ROUND(100.0 * (total_kwh - base_kwh) / NULLIF(base_kwh, 0), 1)::bigint AS data,
               2 AS so
        FROM yearly, base
      )
      SELECT x_axis, y_axis, data
      FROM (SELECT * FROM s1 UNION ALL SELECT * FROM s2) c
      ORDER BY so, x_axis$$,
    $$SELECT (year || '-' || lpad(month::text, 2, '0') || '-01')::timestamptz AS x_axis,
             town AS y_axis,
             ROUND(SUM(kwh_sold)/10000.0)::bigint AS data
      FROM power_by_district
      WHERE category = '1表燈非營業用'
        AND year BETWEEN 2015 AND 2025
      GROUP BY year, month, town
      ORDER BY x_axis, y_axis$$,
    'metrotaipei',
    ARRAY[(SELECT id FROM component_maps WHERE title = '2025年雙北行政區用電量3D分布')]::integer[],
    '{"mode":"byParam","byParam":{"xParam":"TNAME"}}'::json,
    'static', '台灣電力公司',
    '雙北民生用電歷年總量與成長率（2015-2025）',
    '資料來源為「台灣電力公司鄉鎮市(郵遞區)別用電統計資料」。主圖表呈現雙北民生（表燈非營業用）用電量的 11 年變化軌跡，柱狀為各年用電量（萬度），折線為相對 2015 基準的累計成長率（%）。地圖則顯示 2025 年（最新完整年）各行政區累計用電量分布，採 3D 立體呈現（高度 = 用電量）。',
    '主圖揭示雙北用電 10 年來的成長趨勢與成長放緩節點。地圖呈現 2025 年完整年度的各區用電強度排名（板橋、中和、三重位居前三）。可作為雙北能源政策、節能補助對象、區域用電負載評估之依據。',
    ARRAY['https://data.gov.tw/dataset/14135']::varchar[],
    ARRAY[]::varchar[],
    NOW(), NOW();

-- 4.3 碳排部門 (taipei) ---------------------------------------------------
INSERT INTO query_charts (
    index, query_type, query_chart, city,
    map_config_ids, map_filter,
    time_from, source, short_desc, long_desc, use_case,
    links, contributors, created_at, updated_at
)
SELECT
    'power_vs_emission_taipei', 'three_d',
    $$WITH e AS (
        SELECT year, residential_emission, transport_emission, industry_emission,
               waste_emission, agriculture_emission, forest_emission
        FROM taipei_emission
        WHERE year BETWEEN 2015 AND 2024
      ),
      series AS (
        SELECT year::text AS x_axis, '森林(碳吸收)' AS y_axis,
               ROUND(forest_emission)::int AS data, 1 AS so FROM e
        UNION ALL
        SELECT year::text, '農業',
               ROUND(agriculture_emission)::int, 2 FROM e
        UNION ALL
        SELECT year::text, '廢棄物',
               ROUND(waste_emission)::int, 3 FROM e
        UNION ALL
        SELECT year::text, '工業',
               ROUND(industry_emission)::int, 4 FROM e
        UNION ALL
        SELECT year::text, '運輸',
               ROUND(transport_emission)::int, 5 FROM e
        UNION ALL
        SELECT year::text, '住商',
               ROUND(residential_emission)::int, 6 FROM e
      )
      SELECT x_axis, y_axis, data FROM series ORDER BY so, x_axis$$,
    'taipei',
    ARRAY[]::integer[],
    '{}'::json,
    'static',
    '台北市政府環保局',
    '台北市六大部門碳排放結構（2015-2024）',
    '依台北市政府環保局公開統計，呈現近 10 年六大部門（住商、運輸、工業、廢棄物、農業、森林）的碳排放結構變遷。住商部門始終佔最大宗（約 75%），運輸部門其次（約 20%）。森林部門為負值代表碳吸收。',
    '完整呈現六大部門逐年絕對排放量。住商 2015-2024 從 893 → 802 萬公噸（-10%），運輸 257 → 202（-21%），工業 29 → 19（-33%），均反映台北市能源轉型與運輸電動化政策的綜合成效。',
    ARRAY[]::varchar[],
    ARRAY[]::varchar[],
    NOW(), NOW();

-- 4.4 碳排部門 (metrotaipei) ----------------------------------------------
INSERT INTO query_charts (
    index, query_type, query_chart, city,
    map_config_ids, map_filter,
    time_from, source, short_desc, long_desc, use_case,
    links, contributors, created_at, updated_at
)
SELECT
    'power_vs_emission_taipei', query_type, query_chart, 'metrotaipei',
    map_config_ids, map_filter,
    time_from, source,
    short_desc || ' (僅台北市資料)',
    long_desc || E'\n\n注意：碳排放統計目前僅有台北市資料，本組件在雙北儀表板顯示的內容與台北市檢視相同。',
    use_case, links, contributors, NOW(), NOW()
FROM query_charts
WHERE index = 'power_vs_emission_taipei' AND city = 'taipei';

-- ----------------------------------------------------------------------------
-- 5. dashboards — 新建「永續環境」儀表板
-- ----------------------------------------------------------------------------
INSERT INTO dashboards (index, name, components, icon, created_at, updated_at)
VALUES (
    'metrotaipei_sustainability',
    '永續環境',
    ARRAY[
        (SELECT id FROM components WHERE index = 'power_by_district'),
        (SELECT id FROM components WHERE index = 'power_vs_emission_taipei')
    ]::integer[],
    'eco',
    NOW(), NOW()
);

-- ----------------------------------------------------------------------------
-- 6. dashboard_groups — 連結到雙北 group (group_id = 3)
-- ----------------------------------------------------------------------------
INSERT INTO dashboard_groups (dashboard_id, group_id)
SELECT
    (SELECT id FROM dashboards WHERE index = 'metrotaipei_sustainability'),
    3
ON CONFLICT DO NOTHING;

COMMIT;

-- ============================================================================
-- VERIFICATION
-- ============================================================================
SELECT '=== components ===' AS section;
SELECT id, index, name FROM components
WHERE index IN ('power_by_district', 'power_vs_emission_taipei')
ORDER BY id;

SELECT '=== query_charts ===' AS section;
SELECT index, city, query_type FROM query_charts
WHERE index IN ('power_by_district', 'power_vs_emission_taipei')
ORDER BY index, city;

SELECT '=== component_maps ===' AS section;
SELECT id, index, type, title FROM component_maps
WHERE title = '2025年雙北行政區用電量3D分布';

SELECT '=== dashboard ===' AS section;
SELECT id, index, name, components, icon FROM dashboards
WHERE index = 'metrotaipei_sustainability';

SELECT '=== dashboard_groups ===' AS section;
SELECT * FROM dashboard_groups WHERE dashboard_id = (
    SELECT id FROM dashboards WHERE index = 'metrotaipei_sustainability'
);
