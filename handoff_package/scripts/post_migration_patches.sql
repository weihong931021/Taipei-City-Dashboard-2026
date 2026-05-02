-- ============================================================================
-- post_migration_patches.sql
--
-- 目標 DB：postgres-manager:dashboardmanager
-- 跑時機：所有 hackathon/sql/*.sql + power_by_district/MIGRATION.sql 都跑完之後
-- 用途：補上 seed 跟 MIGRATION.sql 沒處理的 5 件事
-- 性質：idempotent，可重複執行
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. 行道樹 + 綠地 的地圖層 (component_maps)
-- ----------------------------------------------------------------------------
-- hackathon/09_green_component.sql 只註冊了 chart 跟 query，沒有註冊地圖層
-- 這裡補上 street_tree_tpe (按樹種上色的點圖) 跟 green_park_type_tpe (綠地填色多邊形)

DELETE FROM component_maps
WHERE index IN ('street_tree_tpe', 'green_park_type_tpe');

INSERT INTO component_maps (index, title, type, source, paint, property)
VALUES
  ('street_tree_tpe',
   '台北行道樹',
   'circle',
   'geojson',
   $${
     "circle-color": ["match", ["get", "s"],
       ["榕樹", "正榕", "印度橡膠樹"],   "#2E7D32",
       ["樟樹", "本樟", "牛樟"],          "#388E3C",
       ["茄苳", "重陽木"],                 "#43A047",
       ["臺灣欒樹", "苦楝", "苦苓"],     "#FBC02D",
       ["楓香", "青楓"],                    "#E64A19",
       ["白千層"],                          "#F57C00",
       ["黑板樹"],                          "#D84315",
       ["桃花心木", "大葉桃花心木"],     "#8E24AA",
       ["木棉", "美人樹"],                "#AD1457",
       "#66BB6A"
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
   }$$::json,
   $$[
     {"key": "d", "name": "行政區"},
     {"key": "s", "name": "樹種"},
     {"key": "h", "name": "樹高(m)"}
   ]$$::json
  ),
  ('green_park_type_tpe',
   '台北綠地',
   'fill',
   'geojson',
   $${
     "fill-color": "#27AE60",
     "fill-opacity": 0.4,
     "fill-outline-color": "#1e8449"
   }$$::json,
   $$[
     {"key": "name", "name": "類型"},
     {"key": "area", "name": "面積"}
   ]$$::json
  );

-- ----------------------------------------------------------------------------
-- 2. 把 map_config_ids 接到 query_charts
--    (street_tree_dist 跟 green_park_type 才知道地圖層用哪個 component_map)
-- ----------------------------------------------------------------------------

UPDATE query_charts
SET map_config_ids = ARRAY[(SELECT id FROM component_maps WHERE index = 'street_tree_tpe')]::integer[]
WHERE index = 'street_tree_dist';

UPDATE query_charts
SET map_config_ids = ARRAY[(SELECT id FROM component_maps WHERE index = 'green_park_type_tpe')]::integer[]
WHERE index = 'green_park_type';

-- ----------------------------------------------------------------------------
-- 3. metrotaipei_town 改 2D fill + muted 配色
--    (power_by_district MIGRATION.sql 預設是 fill-extrusion 3D 紅色刺眼版)
-- ----------------------------------------------------------------------------

UPDATE component_maps
SET type = 'fill',
    paint = $${
      "fill-color": ["match", ["get", "TNAME"],
        "板橋區", "#8B4747", "中和區", "#8B4747", "三重區", "#8B4747",
        "新莊區", "#8B4747", "新店區", "#8B4747", "大安區", "#8B4747",
        "中山區", "#8B4747", "士林區", "#8B4747", "淡水區", "#8B4747",
        "內湖區", "#8B4747", "汐止區", "#8B4747",
        "北投區", "#A87575", "文山區", "#A87575", "土城區", "#A87575",
        "永和區", "#A87575", "信義區", "#A87575", "松山區", "#A87575",
        "蘆洲區", "#A87575", "萬華區", "#A87575", "樹林區", "#A87575",
        "林口區", "#A87575",
        "中正區", "#BFA0A0", "大同區", "#BFA0A0", "五股區", "#BFA0A0",
        "三峽區", "#BFA0A0", "南港區", "#BFA0A0", "鶯歌區", "#BFA0A0",
        "泰山區", "#BFA0A0", "八里區", "#BFA0A0", "瑞芳區", "#BFA0A0",
        "三芝區", "#BFA0A0",
        "深坑區", "#D4C2C2", "金山區", "#D4C2C2", "萬里區", "#D4C2C2",
        "貢寮區", "#D4C2C2", "石門區", "#D4C2C2", "石碇區", "#D4C2C2",
        "雙溪區", "#D4C2C2", "坪林區", "#D4C2C2", "平溪區", "#D4C2C2",
        "烏來區", "#D4C2C2",
        "#888888"
      ],
      "fill-opacity": 0.55,
      "fill-outline-color": "#222222"
    }$$::json
WHERE title = '2025年雙北行政區用電量3D分布';

-- ----------------------------------------------------------------------------
-- 4. 把 power_by_district 的 components (301/302) 加到 sustainability_newtpe (601)
--    並刪掉 MIGRATION.sql 建的重複 dashboard (metrotaipei_sustainability)
-- ----------------------------------------------------------------------------

UPDATE dashboards
SET components = ARRAY(
      SELECT DISTINCT unnest(components || ARRAY[
        (SELECT id FROM components WHERE index = 'power_by_district'),
        (SELECT id FROM components WHERE index = 'power_vs_emission_taipei')
      ]::integer[])
    ),
    updated_at = NOW()
WHERE id = 601;

DELETE FROM dashboard_groups
WHERE dashboard_id IN (SELECT id FROM dashboards WHERE index = 'metrotaipei_sustainability');

DELETE FROM dashboards
WHERE index = 'metrotaipei_sustainability';

-- ----------------------------------------------------------------------------
-- 5. 確保 sustainability_newtpe 同時掛在台北 + 雙北兩個 group
--    (預設只有 group 3 = metrotaipei，補一個 group 2 = taipei)
-- ----------------------------------------------------------------------------

INSERT INTO dashboard_groups (dashboard_id, group_id)
SELECT 601, 2
WHERE NOT EXISTS (
  SELECT 1 FROM dashboard_groups WHERE dashboard_id = 601 AND group_id = 2
);

COMMIT;

-- ============================================================================
-- VERIFY
-- ============================================================================

\echo ''
\echo '=== Verify dashboard 601 ==='
SELECT id, index, name, components FROM dashboards WHERE id = 601;

\echo ''
\echo '=== Verify map_config_ids on new query_charts ==='
SELECT index, city, map_config_ids
FROM query_charts
WHERE index IN ('street_tree_dist', 'green_park_type')
ORDER BY index, city;

\echo ''
\echo '=== Verify metrotaipei_town is now 2D fill ==='
SELECT id, index, type, title FROM component_maps
WHERE title = '2025年雙北行政區用電量3D分布';

\echo ''
\echo '=== Dashboard 601 group memberships (should have both 2 + 3) ==='
SELECT * FROM dashboard_groups WHERE dashboard_id = 601;
