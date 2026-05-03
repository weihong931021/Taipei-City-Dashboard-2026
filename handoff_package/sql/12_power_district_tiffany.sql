-- ============================================================================
-- 12_power_district_tiffany.sql
--
-- 「雙北各行政區用電統計」(component 301 power_by_district) 的柱色改成
-- tiffany #6EEBDE (RGB 110, 235, 222),同時把 metrotaipei_town 4 階 fill 也
-- 換成 tiffany 家族(高→深,低→#6EEBDE),讓 chart 跟 mapview 同色族對齊。
--
-- Target: postgres-manager / dashboardmanager
-- 性質: idempotent
-- ============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. ColumnLineChart：柱(用電) 改 #6EEBDE，線(碳排) 維持深琥珀
-- ---------------------------------------------------------------------------
UPDATE component_charts
SET color = '{#6EEBDE,#EF6C00}'
WHERE index = 'power_by_district';

-- ---------------------------------------------------------------------------
-- 2. metrotaipei_town 行政區 fill：amber 4 階 → tiffany 4 階
--    高用電 (11 區)  → #00695C (深 teal)
--    高     (10 區)  → #00897B
--    中     (10 區)  → #26A69A
--    低     (10 區)  → #6EEBDE  ← 跟柱色完全一致
--    其他            → #90A4AE (slate fallback)
-- ---------------------------------------------------------------------------
UPDATE component_maps
SET paint = $${
  "fill-color": ["match", ["get", "TNAME"],
    "板橋區", "#00695C", "中和區", "#00695C", "三重區", "#00695C",
    "新莊區", "#00695C", "新店區", "#00695C", "大安區", "#00695C",
    "中山區", "#00695C", "士林區", "#00695C", "淡水區", "#00695C",
    "內湖區", "#00695C", "汐止區", "#00695C",
    "北投區", "#00897B", "文山區", "#00897B", "土城區", "#00897B",
    "永和區", "#00897B", "信義區", "#00897B", "松山區", "#00897B",
    "蘆洲區", "#00897B", "萬華區", "#00897B", "樹林區", "#00897B",
    "林口區", "#00897B",
    "中正區", "#26A69A", "大同區", "#26A69A", "五股區", "#26A69A",
    "三峽區", "#26A69A", "南港區", "#26A69A", "鶯歌區", "#26A69A",
    "泰山區", "#26A69A", "八里區", "#26A69A", "瑞芳區", "#26A69A",
    "三芝區", "#26A69A",
    "深坑區", "#6EEBDE", "金山區", "#6EEBDE", "萬里區", "#6EEBDE",
    "貢寮區", "#6EEBDE", "石門區", "#6EEBDE", "石碇區", "#6EEBDE",
    "雙溪區", "#6EEBDE", "坪林區", "#6EEBDE", "平溪區", "#6EEBDE",
    "烏來區", "#6EEBDE",
    "#90A4AE"
  ],
  "fill-opacity": 0.6,
  "fill-outline-color": "#004D40"
}$$::json
WHERE title = '2025年雙北行政區用電量3D分布';

COMMIT;

-- ============================================================================
-- VERIFY
-- ============================================================================

\echo ''
\echo '=== power_by_district chart palette ==='
SELECT index, color FROM component_charts WHERE index = 'power_by_district';

\echo ''
\echo '=== metrotaipei_town tiffany 4-tier ==='
SELECT id, title,
       jsonb_path_query_array(paint::jsonb, '$."fill-color"[*] ? (@ like_regex "^#")') AS colors
FROM component_maps
WHERE title = '2025年雙北行政區用電量3D分布';
