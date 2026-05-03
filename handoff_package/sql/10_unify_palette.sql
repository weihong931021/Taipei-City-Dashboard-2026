-- ============================================================================
-- 10_unify_palette.sql
--
-- 目標:把 sustainability_newtpe (dashboard 601) 底下 8 個組件的配色
--      收斂到「永續色族」三家族 + 中性灰:
--          🌳 GREEN  family   #1B5E20 / #43A047 / #A5D6A7
--          🌊 TEAL   family   #00695C / #00897B / #4DB6AC
--          🔥 AMBER  family   #FFA726 / #EF6C00
--          ⚪ SLATE             #607D8B
--
-- Target DB: postgres-manager / dashboardmanager
-- 性質: idempotent，可重複跑
-- 跑法: docker cp ... && docker exec postgres-manager psql -U postgres -d dashboardmanager -f /tmp/10_unify_palette.sql
-- Rollback: 重跑原本的 02 / 06 / 09 SQL + post_migration_patches.sql
-- ============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. 充電樁:亮紫 + tiffany 綠 → 深青 + 淺青(同 TEAL 家族區分汽機車)
-- ---------------------------------------------------------------------------
UPDATE component_charts
SET color = '{#00695C,#4DB6AC}'
WHERE index = 'ev_charging_station';

-- ---------------------------------------------------------------------------
-- 2. 環保餐廳:橘 → 深琥珀(融入 AMBER 家族)
-- ---------------------------------------------------------------------------
UPDATE component_charts
SET color = '{#EF6C00}'
WHERE index = 'env_restaurant';

-- ---------------------------------------------------------------------------
-- 3. 行道樹 chart 維持深綠
-- ---------------------------------------------------------------------------
UPDATE component_charts
SET color = '{#1B5E20}'
WHERE index = 'street_tree_dist';

-- ---------------------------------------------------------------------------
-- 4. 綠地 treemap:olive → 三綠 + amber 強調
-- ---------------------------------------------------------------------------
UPDATE component_charts
SET color = '{#1B5E20,#43A047,#A5D6A7,#FFA726}'
WHERE index = 'green_park_type';

-- ---------------------------------------------------------------------------
-- 5. 區用電 + 排碳 折柱混合:teal + coral → teal + amber
-- ---------------------------------------------------------------------------
UPDATE component_charts
SET color = '{#00897B,#EF6C00}'
WHERE index = 'power_by_district';

-- ---------------------------------------------------------------------------
-- 6. 電 vs 碳排 部門結構 6 系列:雜 6 色 → 統一家族
-- ---------------------------------------------------------------------------
UPDATE component_charts
SET color = '{#43A047,#00897B,#FFA726,#EF6C00,#607D8B,#1B5E20}'
WHERE index = 'power_vs_emission_taipei';

-- ---------------------------------------------------------------------------
-- 7. 用電結構 donut 5 系列
-- ---------------------------------------------------------------------------
UPDATE component_charts
SET color = '{#43A047,#00897B,#FFA726,#EF6C00,#607D8B}'
WHERE index = 'power_usage_ratio';

-- ---------------------------------------------------------------------------
-- 8. 行道樹 map paint:9 色亂跳 → 5 色按樹種類別(常綠/落葉/變色/開花)
-- ---------------------------------------------------------------------------
UPDATE component_maps
SET paint = $${
  "circle-color": ["match", ["get", "s"],
    ["榕樹", "正榕", "印度橡膠樹", "樟樹", "本樟", "牛樟", "白千層", "黑板樹"],   "#1B5E20",
    ["茄苳", "重陽木"],                                                            "#43A047",
    ["桃花心木", "大葉桃花心木"],                                                  "#A5D6A7",
    ["臺灣欒樹", "苦楝", "苦苓", "楓香", "青楓"],                                  "#FFA726",
    ["木棉", "美人樹"],                                                            "#EF6C00",
    "#43A047"
  ],
  "circle-radius": ["interpolate", ["linear"], ["zoom"],
    9, 0.5, 12, 1.0, 14, 2.0, 15, 3.0, 16, 4.0, 18, 5.0, 20, 7.0
  ],
  "circle-opacity": ["interpolate", ["linear"], ["zoom"],
    9, 0.4, 12, 0.6, 14, 0.8, 16, 0.95
  ],
  "circle-blur": 0.1,
  "circle-stroke-width": ["interpolate", ["linear"], ["zoom"], 14, 0, 16, 0.3, 20, 0.6],
  "circle-stroke-color": "#0a0a0a"
}$$::json
WHERE index = 'street_tree_tpe';

-- ---------------------------------------------------------------------------
-- 9. 綠地 polygon 維持單色綠(略深一點與 treemap 主綠一致)
-- ---------------------------------------------------------------------------
UPDATE component_maps
SET paint = $${
  "fill-color": "#43A047",
  "fill-opacity": 0.45,
  "fill-outline-color": "#1B5E20"
}$$::json
WHERE index = 'green_park_type_tpe';

-- ---------------------------------------------------------------------------
-- 10. metrotaipei_town 行政區底色:紅 4 階 → amber 4 階
--     (高用電區仍給「熱」感,但用 amber 不像 RED 那樣警報)
-- ---------------------------------------------------------------------------
UPDATE component_maps
SET paint = $${
  "fill-color": ["match", ["get", "TNAME"],
    "板橋區", "#E65100", "中和區", "#E65100", "三重區", "#E65100",
    "新莊區", "#E65100", "新店區", "#E65100", "大安區", "#E65100",
    "中山區", "#E65100", "士林區", "#E65100", "淡水區", "#E65100",
    "內湖區", "#E65100", "汐止區", "#E65100",
    "北投區", "#FB8C00", "文山區", "#FB8C00", "土城區", "#FB8C00",
    "永和區", "#FB8C00", "信義區", "#FB8C00", "松山區", "#FB8C00",
    "蘆洲區", "#FB8C00", "萬華區", "#FB8C00", "樹林區", "#FB8C00",
    "林口區", "#FB8C00",
    "中正區", "#FFA726", "大同區", "#FFA726", "五股區", "#FFA726",
    "三峽區", "#FFA726", "南港區", "#FFA726", "鶯歌區", "#FFA726",
    "泰山區", "#FFA726", "八里區", "#FFA726", "瑞芳區", "#FFA726",
    "三芝區", "#FFA726",
    "深坑區", "#FFE0B2", "金山區", "#FFE0B2", "萬里區", "#FFE0B2",
    "貢寮區", "#FFE0B2", "石門區", "#FFE0B2", "石碇區", "#FFE0B2",
    "雙溪區", "#FFE0B2", "坪林區", "#FFE0B2", "平溪區", "#FFE0B2",
    "烏來區", "#FFE0B2",
    "#90A4AE"
  ],
  "fill-opacity": 0.55,
  "fill-outline-color": "#222222"
}$$::json
WHERE title = '2025年雙北行政區用電量3D分布';

COMMIT;

-- ============================================================================
-- VERIFY
-- ============================================================================

\echo ''
\echo '=== component_charts (8 sustainability indices) ==='
SELECT index, color, types
FROM component_charts
WHERE index IN ('ev_charging_station','env_restaurant','street_tree_dist',
                'green_park_type','power_by_district','power_vs_emission_taipei',
                'power_usage_ratio')
ORDER BY index;

\echo ''
\echo '=== Map paints sanity check ==='
SELECT index, type,
       (paint::jsonb -> 'circle-color' ->> 0) AS color_expr_kind
FROM component_maps
WHERE index IN ('street_tree_tpe', 'green_park_type_tpe')
ORDER BY index;
