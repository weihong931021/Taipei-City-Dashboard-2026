-- ============================================================================
-- 11_palette_tweaks.sql  (套在 10_unify_palette.sql 之後)
--
-- 1. 充電樁 chart 改回紫 + tiffany,跟 PNG icon (ev_charging.png 紫 / ev_motor.png 綠) 對齊
-- 2. metrotaipei_town 行政區 fill:把 4 階收窄,從跳色 (#FFE0B2 → #E65100,亮差 43pp)
--    收成同色族窄域 (#FFCC80 → #FB8C00,亮差 28pp),保留高/低區分但不刺眼
--
-- Target: postgres-manager / dashboardmanager
-- 性質: idempotent
-- ============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. EV 充電樁 chart：青系 → 紫 + tiffany（重新跟 PNG icon 對齊）
-- ---------------------------------------------------------------------------
UPDATE component_charts
SET color = '{#C866F2,#0ABAB5}'
WHERE index = 'ev_charging_station';

-- ---------------------------------------------------------------------------
-- 2. metrotaipei_town 4 階 amber：narrow gradient（同 hue 窄 lightness）
-- ---------------------------------------------------------------------------
UPDATE component_maps
SET paint = $${
  "fill-color": ["match", ["get", "TNAME"],
    "板橋區", "#FB8C00", "中和區", "#FB8C00", "三重區", "#FB8C00",
    "新莊區", "#FB8C00", "新店區", "#FB8C00", "大安區", "#FB8C00",
    "中山區", "#FB8C00", "士林區", "#FB8C00", "淡水區", "#FB8C00",
    "內湖區", "#FB8C00", "汐止區", "#FB8C00",
    "北投區", "#FFA726", "文山區", "#FFA726", "土城區", "#FFA726",
    "永和區", "#FFA726", "信義區", "#FFA726", "松山區", "#FFA726",
    "蘆洲區", "#FFA726", "萬華區", "#FFA726", "樹林區", "#FFA726",
    "林口區", "#FFA726",
    "中正區", "#FFB74D", "大同區", "#FFB74D", "五股區", "#FFB74D",
    "三峽區", "#FFB74D", "南港區", "#FFB74D", "鶯歌區", "#FFB74D",
    "泰山區", "#FFB74D", "八里區", "#FFB74D", "瑞芳區", "#FFB74D",
    "三芝區", "#FFB74D",
    "深坑區", "#FFCC80", "金山區", "#FFCC80", "萬里區", "#FFCC80",
    "貢寮區", "#FFCC80", "石門區", "#FFCC80", "石碇區", "#FFCC80",
    "雙溪區", "#FFCC80", "坪林區", "#FFCC80", "平溪區", "#FFCC80",
    "烏來區", "#FFCC80",
    "#90A4AE"
  ],
  "fill-opacity": 0.6,
  "fill-outline-color": "#5D4037"
}$$::json
WHERE title = '2025年雙北行政區用電量3D分布';

COMMIT;

-- ============================================================================
-- VERIFY
-- ============================================================================

\echo ''
\echo '=== EV charging chart palette ==='
SELECT index, color FROM component_charts WHERE index = 'ev_charging_station';

\echo ''
\echo '=== metrotaipei_town 4-tier amber range (lightness ~78→50) ==='
SELECT id, index, title,
       jsonb_path_query_array(paint::jsonb, '$."fill-color"[*] ? (@ like_regex "^#")') AS unique_colors_seen
FROM component_maps
WHERE title = '2025年雙北行政區用電量3D分布';
