-- ============================================================
-- 充電樁地圖組件 - dashboardmanager 設定
-- 把 4 張表變成一個雙北可切換的地圖組件
-- ============================================================
-- 跑在 dashboardmanager DB
-- 可重複執行（idempotent）
-- ============================================================

-- 0. 清掉舊資料（讓 script 可重跑）
DELETE FROM query_charts     WHERE index = 'ev_charging_station';
DELETE FROM component_charts WHERE index = 'ev_charging_station';
DELETE FROM component_maps   WHERE index LIKE 'ev_charging_%';
DELETE FROM dashboards       WHERE id = 601;
DELETE FROM components       WHERE id = 501;

-- 1. 註冊組件名稱
INSERT INTO components (id, index, name) VALUES
  (501, 'ev_charging_station', '雙北電動車充電樁');

-- 2. 視覺化設定
INSERT INTO component_charts (index, color, types, unit) VALUES
  ('ev_charging_station',
   '{#C866F2,#0ABAB5}',          -- 汽車亮紫 / 機車 Tiffany 綠
   '{DistrictChart,BarChart,MapLegend}', -- 行政區圖 + 長條圖 + 地圖圖例
   '個');

-- 3. 地圖層設定（symbol type + 自定義 icon）
INSERT INTO component_maps (index, title, type, source, icon, paint, property) VALUES
  ('ev_charging_car_tpe',
   '汽車',
   'symbol',
   'geojson',
   'ev_charging',
   '{}'::json,
   '[{"key":"station_name","name":"站名"},{"key":"district","name":"行政區"},{"key":"address","name":"地址"},{"key":"category","name":"類別"},{"key":"socket_type","name":"插座型式"},{"key":"plug_count","name":"插槍數"},{"key":"fee","name":"收費"}]'::json),
  ('ev_charging_car_new_tpe',
   '汽車',
   'symbol',
   'geojson',
   'ev_charging',
   '{}'::json,
   '[{"key":"station_name","name":"站名"},{"key":"district","name":"行政區"},{"key":"address","name":"地址"},{"key":"category","name":"類別"},{"key":"socket_type","name":"插座型式"},{"key":"plug_count","name":"插槍數"},{"key":"fee","name":"收費"}]'::json),
  ('ev_charging_motor_tpe',
   '機車',
   'symbol',
   'geojson',
   'ev_motor',
   '{}'::json,
   '[{"key":"station_name","name":"站名"},{"key":"district","name":"行政區"},{"key":"address","name":"地址"},{"key":"category","name":"類別"},{"key":"plug_type","name":"插座型式"},{"key":"plug_count","name":"插槍數"}]'::json),
  ('ev_charging_motor_new_tpe',
   '機車',
   'symbol',
   'geojson',
   'ev_motor',
   '{}'::json,
   '[{"key":"station_name","name":"站名"},{"key":"district","name":"行政區"},{"key":"address","name":"地址"},{"key":"category","name":"類別"},{"key":"plug_type","name":"插座型式"},{"key":"plug_count","name":"插槍數"}]'::json);

-- 4. query_charts (legend 統計 + 雙北各一筆)
INSERT INTO query_charts (
  index, source, short_desc, long_desc, use_case,
  query_type, query_chart, query_history, city,
  time_from,
  update_freq, update_freq_unit,
  links, contributors, map_config_ids,
  created_at, updated_at
) VALUES
  ('ev_charging_station',
   'data.taipei + data.ntpc',
   '雙北電動車充電樁分布（汽車 + 機車）',
   '整合臺北市與新北市政府開放資料，顯示電動車充電站位置、規格、收費資訊，地址透過 Nominatim 反查座標。',
   '電動車主找充電樁 / 想換電動車的人查家附近資源',
   'three_d',
   $$
WITH car AS (
  SELECT district, COUNT(*)::int AS cnt FROM charging_station_car_tpe
  WHERE district IS NOT NULL AND district <> '' GROUP BY district
),
motor AS (
  SELECT district, COUNT(*)::int AS cnt FROM charging_station_motor_tpe
  WHERE district IS NOT NULL AND district <> '' GROUP BY district
),
dists AS (
  SELECT d.district,
         COALESCE(c.cnt,0) AS car_cnt,
         COALESCE(m.cnt,0) AS motor_cnt,
         COALESCE(c.cnt,0)+COALESCE(m.cnt,0) AS total
  FROM (SELECT district FROM car UNION SELECT district FROM motor) d
  LEFT JOIN car c USING (district)
  LEFT JOIN motor m USING (district)
)
SELECT * FROM (
  SELECT district AS x_axis, '汽車' AS y_axis, car_cnt AS data, total, 1 AS so FROM dists
  UNION ALL
  SELECT district AS x_axis, '機車' AS y_axis, motor_cnt AS data, total, 2 AS so FROM dists
) z
ORDER BY total DESC, so;
   $$,
   NULL,
   'taipei',
   'static',
   1, 'day',
   '{https://data.taipei,https://data.ntpc.gov.tw}',
   '{Yuan}',
   NULL,
   NOW(), NOW()),
  ('ev_charging_station',
   'data.taipei + data.ntpc',
   '雙北電動車充電樁分布（汽車 + 機車）',
   '整合臺北市與新北市政府開放資料，顯示電動車充電站位置、規格、收費資訊，地址透過 Nominatim 反查座標。',
   '電動車主找充電樁 / 想換電動車的人查家附近資源',
   'three_d',
   $$
WITH car AS (
  SELECT district, COUNT(*)::int AS cnt FROM (
    SELECT district FROM charging_station_car_tpe
    UNION ALL SELECT district FROM charging_station_car_new_tpe
  ) c WHERE district IS NOT NULL AND district <> '' GROUP BY district
),
motor AS (
  SELECT district, COUNT(*)::int AS cnt FROM (
    SELECT district FROM charging_station_motor_tpe
    UNION ALL SELECT district FROM charging_station_motor_new_tpe
  ) m WHERE district IS NOT NULL AND district <> '' GROUP BY district
),
dists AS (
  SELECT d.district,
         COALESCE(c.cnt,0) AS car_cnt,
         COALESCE(mo.cnt,0) AS motor_cnt,
         COALESCE(c.cnt,0)+COALESCE(mo.cnt,0) AS total
  FROM (SELECT district FROM car UNION SELECT district FROM motor) d
  LEFT JOIN car c USING (district)
  LEFT JOIN motor mo USING (district)
)
SELECT * FROM (
  SELECT district AS x_axis, '汽車' AS y_axis, car_cnt AS data, total, 1 AS so FROM dists
  UNION ALL
  SELECT district AS x_axis, '機車' AS y_axis, motor_cnt AS data, total, 2 AS so FROM dists
) z
ORDER BY total DESC, so;
   $$,
   NULL,
   'metrotaipei',
   'static',
   1, 'day',
   '{https://data.taipei,https://data.ntpc.gov.tw}',
   '{Yuan}',
   NULL,
   NOW(), NOW());

-- 5. 把組件掛到「永續環境」儀表板（雙北版）
INSERT INTO dashboards (id, index, name, components, icon, created_at, updated_at) VALUES
  (601, 'sustainability_newtpe', '永續環境', '{501}', 'park', NOW(), NOW());

-- 6. 把 dashboard 掛到 metrotaipei 群組（這步是 BE 列表分類的關鍵）
INSERT INTO dashboard_groups (dashboard_id, group_id) VALUES (601, 3)
ON CONFLICT DO NOTHING;

-- ============================================================
-- 後續加組件只要再 INSERT components / component_charts /
-- query_charts，然後把新 component id 加進 dashboard.components
-- ============================================================
