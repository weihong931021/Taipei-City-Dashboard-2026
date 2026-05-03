-- ============================================================================
-- 13_brighter_amber.sql
--
-- 1. 廢掉 12_power_district_tiffany 的 tiffany — 301 chart 柱回 #00897B
-- 2. metrotaipei_town fill 從「悶悶的 narrow amber」換成「亮 vivid Amber 4 階」
--    (Material Amber 600~900 系，比之前的 Orange 系更亮更跳)
--
-- Target: postgres-manager / dashboardmanager
-- 性質: idempotent
-- ============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. 301 power_by_district chart：柱(用電) 改回 teal #00897B
--    線(碳排) 順手換到更亮的 #FF6F00 (Material Amber 900) 跟 map 同調
-- ---------------------------------------------------------------------------
UPDATE component_charts
SET color = '{#00897B,#FF6F00}'
WHERE index = 'power_by_district';

-- ---------------------------------------------------------------------------
-- 2. metrotaipei_town 4 階 → bright vivid Amber 系 (Material Amber 600/700/800/900)
--    高用電 (11 區)  → #FF6F00  (Amber 900, 最亮最飽和)
--    高     (10 區)  → #FF8F00  (Amber 800)
--    中     (10 區)  → #FFA000  (Amber 700)
--    低     (10 區)  → #FFB300  (Amber 600)
--    fallback        → #90A4AE  (slate)
-- ---------------------------------------------------------------------------
UPDATE component_maps
SET paint = $${
  "fill-color": ["match", ["get", "TNAME"],
    "板橋區", "#FF6F00", "中和區", "#FF6F00", "三重區", "#FF6F00",
    "新莊區", "#FF6F00", "新店區", "#FF6F00", "大安區", "#FF6F00",
    "中山區", "#FF6F00", "士林區", "#FF6F00", "淡水區", "#FF6F00",
    "內湖區", "#FF6F00", "汐止區", "#FF6F00",
    "北投區", "#FF8F00", "文山區", "#FF8F00", "土城區", "#FF8F00",
    "永和區", "#FF8F00", "信義區", "#FF8F00", "松山區", "#FF8F00",
    "蘆洲區", "#FF8F00", "萬華區", "#FF8F00", "樹林區", "#FF8F00",
    "林口區", "#FF8F00",
    "中正區", "#FFA000", "大同區", "#FFA000", "五股區", "#FFA000",
    "三峽區", "#FFA000", "南港區", "#FFA000", "鶯歌區", "#FFA000",
    "泰山區", "#FFA000", "八里區", "#FFA000", "瑞芳區", "#FFA000",
    "三芝區", "#FFA000",
    "深坑區", "#FFB300", "金山區", "#FFB300", "萬里區", "#FFB300",
    "貢寮區", "#FFB300", "石門區", "#FFB300", "石碇區", "#FFB300",
    "雙溪區", "#FFB300", "坪林區", "#FFB300", "平溪區", "#FFB300",
    "烏來區", "#FFB300",
    "#90A4AE"
  ],
  "fill-opacity": 0.75,
  "fill-outline-color": "#3E2723"
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
\echo '=== metrotaipei_town bright Amber 4-tier ==='
SELECT id, title,
       jsonb_path_query_array(paint::jsonb, '$."fill-color"[*] ? (@ like_regex "^#")') AS colors
FROM component_maps
WHERE title = '2025年雙北行政區用電量3D分布';
