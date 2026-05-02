#!/usr/bin/env bash
# ============================================================================
# run_all.sh — 一鍵把永續環境 dashboard 所有 SQL / ETL 跑完
#
# 前置：docker compose up -d 已執行、postgres-data + postgres-manager 已 ready
# 執行：在 repo root 跑 `bash handoff/run_all.sh`
# ============================================================================

set -e
cd "$(dirname "$0")/.."

PG_DATA="${PG_DATA:-postgres-data}"
PG_MGR="${PG_MGR:-postgres-manager}"

echo "▶ 確認容器在線..."
docker exec ${PG_DATA} pg_isready -U postgres -d dashboard >/dev/null
docker exec ${PG_MGR}  pg_isready -U postgres -d dashboardmanager >/dev/null
echo "  ✓ 兩個 postgres 都 ready"
echo ""

# ============================================================================
# Step 1：hackathon SQL — 註冊 EV / 餐廳 / 用電結構 / 行道樹 / 綠地組件
# ============================================================================
echo "▶ Step 1：hackathon SQL（註冊 5 個組件）"
for f in 02_charging_station_component 05_power_usage_component 06_restaurant_component 09_green_component; do
  echo "  → ${f}.sql"
  docker cp hackathon/sql/${f}.sql ${PG_MGR}:/tmp/
  docker exec ${PG_MGR} psql -U postgres -d dashboardmanager -f /tmp/${f}.sql > /dev/null
done
echo "  ✓ 5 個組件已註冊"
echo ""

# ============================================================================
# Step 2：power_by_district ETL — 載入 12 年用電 + 1 份碳排
# ============================================================================
echo "▶ Step 2a：載入用電 CSV (12 年)"
for y in 104 105 106 107 108 109 110 111 112 113 114 115; do
  docker cp power_by_district/datasets/dist_kwh_${y}.csv ${PG_DATA}:/tmp/dist_kwh_${y}.csv > /dev/null
done
docker cp power_by_district/load_csv.sql ${PG_DATA}:/tmp/
docker exec ${PG_DATA} psql -U postgres -d dashboard -f /tmp/load_csv.sql | tail -3
echo ""

echo "▶ Step 2b：載入碳排 CSV"
docker cp power_by_district/datasets/taipei_emission.csv ${PG_DATA}:/tmp/
docker cp power_by_district/load_emission.sql ${PG_DATA}:/tmp/
docker exec ${PG_DATA} psql -U postgres -d dashboard -f /tmp/load_emission.sql | tail -3
echo ""

# ============================================================================
# Step 3：power_by_district MIGRATION — 註冊 component 301/302
# ============================================================================
echo "▶ Step 3：power_by_district MIGRATION"
docker cp power_by_district/MIGRATION.sql ${PG_MGR}:/tmp/
docker exec ${PG_MGR} psql -U postgres -d dashboardmanager -f /tmp/MIGRATION.sql > /dev/null
echo "  ✓ component 301 (power_by_district) + 302 (power_vs_emission_taipei) 已註冊"
echo ""

# ============================================================================
# Step 4：post-migration patches
# ============================================================================
echo "▶ Step 4：post-migration patches（補 seed/MIGRATION 沒處理的事）"
docker cp handoff/post_migration_patches.sql ${PG_MGR}:/tmp/
docker exec ${PG_MGR} psql -U postgres -d dashboardmanager -f /tmp/post_migration_patches.sql
echo ""

# ============================================================================
# 完成
# ============================================================================
echo "════════════════════════════════════════════════════════════════════"
echo "✓ 全部完成！打開 http://localhost:8080 → 雙北儀表板 → 永續環境"
echo "════════════════════════════════════════════════════════════════════"
