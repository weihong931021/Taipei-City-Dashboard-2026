-- ============================================================================
-- 15_brightness_gradient.sql
--
-- 套用截圖的「single base + brightness gradient」原則:
--  • 多 series 的圖 → 統一 base hue,只調亮度
--  • 單 / 雙色的圖 → 不動 (501 / 701 / 504 chart / 301)
--
-- 改的項目:
--   302 power_vs_emission_taipei  6 系列 → 6 階 Amber  (碳排=warm 警示家族)
--   502 power_usage_ratio         5 系列 → 5 階 Teal   (用電結構=clean energy 家族)
--   505 green_park_type           4 系列 → 4 階 Green  (綠地=自然家族)
--   504 street_tree_tpe map       5 hue  → 5 階 Green  (按樹種仍區分,但全綠系)
--
-- Target: postgres-manager / dashboardmanager
-- 性質: idempotent
-- ============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. 302 碳排部門結構 (6 系列) → Material Amber 6 階
-- ---------------------------------------------------------------------------
UPDATE component_charts
SET color = '{#FF6F00,#FF8F00,#FFB300,#FFCA28,#FFE082,#FFECB3}'
WHERE index = 'power_vs_emission_taipei';

-- ---------------------------------------------------------------------------
-- 2. 502 用電結構 donut (5 系列) → Material Teal 5 階
-- ---------------------------------------------------------------------------
UPDATE component_charts
SET color = '{#004D40,#00695C,#00897B,#4DB6AC,#80CBC4}'
WHERE index = 'power_usage_ratio';

-- ---------------------------------------------------------------------------
-- 3. 505 綠地 treemap (4 系列) → Material Green 4 階,把混進去的 amber 拿掉
-- ---------------------------------------------------------------------------
UPDATE component_charts
SET color = '{#1B5E20,#43A047,#66BB6A,#A5D6A7}'
WHERE index = 'green_park_type';

-- ---------------------------------------------------------------------------
-- 4. 504 行道樹 map paint:5 hue 跳色 → 5 階綠系亮度
--    保留按樹種類別分桶,但同色族視覺一致
-- ---------------------------------------------------------------------------
UPDATE component_maps
SET paint = $${
  "circle-color": ["match", ["get", "s"],
    ["榕樹", "正榕", "印度橡膠樹", "樟樹", "本樟", "牛樟", "白千層", "黑板樹"],   "#1B5E20",
    ["茄苳", "重陽木"],                                                            "#2E7D32",
    ["桃花心木", "大葉桃花心木"],                                                  "#43A047",
    ["臺灣欒樹", "苦楝", "苦苓", "楓香", "青楓"],                                  "#66BB6A",
    ["木棉", "美人樹"],                                                            "#A5D6A7",
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

COMMIT;

-- ============================================================================
-- VERIFY
-- ============================================================================

\echo ''
\echo '=== brightness gradient palette (sustainability_newtpe) ==='
SELECT index, color, types
FROM component_charts
WHERE index IN ('power_vs_emission_taipei','power_usage_ratio','green_park_type')
ORDER BY index;

\echo ''
\echo '=== street_tree map: green-only 5-tier ==='
SELECT index, type,
       (paint::jsonb -> 'circle-color' ->> 0) AS color_expr_kind
FROM component_maps
WHERE index = 'street_tree_tpe';
