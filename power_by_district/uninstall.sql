-- ============================================================================
-- uninstall.sql — 移除「永續環境」整合包所有設定
--
-- 目標 DB: postgres-manager (dashboardmanager)
--
-- 完整移除:
--   - dashboard「永續環境」+ dashboard_groups 關聯
--   - components × 2 (power_by_district, power_vs_emission_taipei)
--   - query_charts × 4
--   - component_charts × 2
--   - component_maps × 1 (3D 雙北用電地圖)
--
-- 不會動到:
--   - postgres-data 內的 power_by_district / taipei_emission table
--     (如要刪請手動到 postgres-data 跑: DROP TABLE ...)
-- ============================================================================

BEGIN;

-- 從所有 dashboards 的 components 陣列中移除本套組件 id
UPDATE dashboards
SET components = (
    SELECT COALESCE(array_agg(c)::integer[], ARRAY[]::integer[])
    FROM unnest(components) c
    WHERE c NOT IN (
        SELECT id FROM components
        WHERE index IN ('power_by_district', 'power_vs_emission_taipei')
    )
);

-- 移除整個「永續環境」儀表板與 group 關聯
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

COMMIT;

-- 驗證: 應該全部回傳 0 rows
SELECT '=== 確認清乾淨 ===' AS section;
SELECT COUNT(*) AS components_left
FROM components WHERE index IN ('power_by_district', 'power_vs_emission_taipei');

SELECT COUNT(*) AS query_charts_left
FROM query_charts WHERE index IN ('power_by_district', 'power_vs_emission_taipei');

SELECT COUNT(*) AS dashboards_left
FROM dashboards WHERE index = 'metrotaipei_sustainability';

-- 提醒: 若要也移除 data table，手動執行:
--   docker exec postgres-data psql -U postgres -d dashboard -c \
--     "DROP TABLE IF EXISTS power_by_district; DROP TABLE IF EXISTS taipei_emission;"
