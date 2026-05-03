-- ============================================================================
-- 14_pastel_teal.sql
--
-- 「雙北各行政區用電統計」(301 chart + metrotaipei_town map) 換成截圖那種
-- 低飽和 pastel teal 配色:
--   chart 柱(用電) = #7FB6B0  (跟截圖長條色幾乎一致)
--   chart 線(碳排) = #E8DC9E  (跟截圖折線色幾乎一致)
--   map 4-tier:
--     高 (11 區) → #4F8985  (最深)
--     中高(10 區) → #7FB6B0  ← 跟柱色一致
--     中低(10 區) → #A8C9C5
--     低 (10 區) → #D2E4E1  (最淺)
-- 舊 Material Amber vivid 系全 discard,opacity 也降到 0.7 對齊 muted 觀感。
--
-- Target: postgres-manager / dashboardmanager
-- 性質: idempotent
-- ============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. 301 power_by_district：pastel teal 柱 + pastel cream 線
-- ---------------------------------------------------------------------------
UPDATE component_charts
SET color = '{#7FB6B0,#E8DC9E}'
WHERE index = 'power_by_district';

-- ---------------------------------------------------------------------------
-- 2. metrotaipei_town fill：4 階 pastel teal (低飽和、層級緊密)
-- ---------------------------------------------------------------------------
UPDATE component_maps
SET paint = $${
  "fill-color": ["match", ["get", "TNAME"],
    "板橋區", "#4F8985", "中和區", "#4F8985", "三重區", "#4F8985",
    "新莊區", "#4F8985", "新店區", "#4F8985", "大安區", "#4F8985",
    "中山區", "#4F8985", "士林區", "#4F8985", "淡水區", "#4F8985",
    "內湖區", "#4F8985", "汐止區", "#4F8985",
    "北投區", "#7FB6B0", "文山區", "#7FB6B0", "土城區", "#7FB6B0",
    "永和區", "#7FB6B0", "信義區", "#7FB6B0", "松山區", "#7FB6B0",
    "蘆洲區", "#7FB6B0", "萬華區", "#7FB6B0", "樹林區", "#7FB6B0",
    "林口區", "#7FB6B0",
    "中正區", "#A8C9C5", "大同區", "#A8C9C5", "五股區", "#A8C9C5",
    "三峽區", "#A8C9C5", "南港區", "#A8C9C5", "鶯歌區", "#A8C9C5",
    "泰山區", "#A8C9C5", "八里區", "#A8C9C5", "瑞芳區", "#A8C9C5",
    "三芝區", "#A8C9C5",
    "深坑區", "#D2E4E1", "金山區", "#D2E4E1", "萬里區", "#D2E4E1",
    "貢寮區", "#D2E4E1", "石門區", "#D2E4E1", "石碇區", "#D2E4E1",
    "雙溪區", "#D2E4E1", "坪林區", "#D2E4E1", "平溪區", "#D2E4E1",
    "烏來區", "#D2E4E1",
    "#90A4AE"
  ],
  "fill-opacity": 0.7,
  "fill-outline-color": "#2D5C58"
}$$::json
WHERE title = '2025年雙北行政區用電量3D分布';

COMMIT;

-- ============================================================================
-- VERIFY
-- ============================================================================

\echo ''
\echo '=== power_by_district pastel palette ==='
SELECT index, color FROM component_charts WHERE index = 'power_by_district';

\echo ''
\echo '=== metrotaipei_town pastel teal 4-tier ==='
SELECT id, title,
       jsonb_path_query_array(paint::jsonb, '$."fill-color"[*] ? (@ like_regex "^#")') AS colors
FROM component_maps
WHERE title = '2025年雙北行政區用電量3D分布';
