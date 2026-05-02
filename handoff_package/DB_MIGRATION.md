# 🗄 DB Migration Spec — 永續環境 Dashboard

目標：把 weihong 在本地 `postgres-data` + `postgres-manager` 跑出來的 schema、資料、組件註冊、地圖層補丁 一次性套用到隊友的環境。

> 適用版本基準：Taipei-City-Dashboard-2026 develop 分支 commit `0f81d3b`（最後一個 `freetime007` 的 ETL 修復）之後。
>
> 若隊友的 develop 比這個 commit 新很多，先檢查 `dashboardmanager` 的 `dashboards` / `components` / `query_charts` 表是否有衝突 id（本批新增 id：components `301`/`302`/`501`/`502`/`701`，dashboard `601`）。

---

## A. 影響範圍

兩個 DB（皆 PostgreSQL，docker container）：

| Container | DB | 動作 |
|---|---|---|
| `postgres-data` | `dashboard` | **新增** 4 + 2 + 1 + 2 = 9 張表 + 載入 12 年用電 + 20 年碳排 CSV |
| `postgres-manager` | `dashboardmanager` | **新增** 5 個 component (501/502/701/301/302) + 1 個 dashboard (601 永續環境)，並 patch metrotaipei_town 地圖層 |

新增表（皆在 `dashboard` DB）：

```
charging_station_car_tpe / car_new_tpe / motor_tpe / motor_new_tpe   -- 充電樁 4 張
env_restaurant_tpe / env_restaurant_new_tpe                          -- 環保餐廳 2 張
power_usage_by_district                                              -- 用電 1 張
green_street_tree / green_park                                       -- 綠地 2 張
power_emission_taipei                                                -- 碳排 1 張
```

---

## B. 一鍵安裝（推薦）

```bash
# 1. 確認 docker 兩個 postgres 已 ready
docker ps | grep -E "postgres-data|postgres-manager"

# 2. 把 handoff_package 解壓到 repo root（若尚未解）
#    產出：./handoff_package/

# 3. 跑一鍵腳本（內容詳見 §C）
bash handoff_package/scripts/run_all.sh
```

跑完會印 `✓ 全部完成！` → 打開 `http://localhost:8080` → 雙北儀表板 → 永續環境，看到 5 個組件即成功。

---

## C. 執行順序（一鍵腳本內部展開，便於 cherry-pick / 局部重跑）

所有 SQL 皆 **idempotent**（開頭都先 `DELETE` 既有 row 或 `DROP TABLE IF EXISTS`），可重複跑。

### Step 1：建表 + 載資料（target = `postgres-data:dashboard`）

| 順序 | 檔案 | 說明 |
|---|---|---|
| 1.1 | `handoff_package/sql/01_charging_station_schema.sql` | 充電樁 4 張表 |
| 1.2 | `handoff_package/sql/03_env_restaurant_schema.sql`   | 環保餐廳 2 張表 |
| 1.3 | `handoff_package/sql/04_power_usage_schema.sql`      | 用電 1 張表 |
| 1.4 | `handoff_package/sql/08_green_schema.sql`            | 綠地（行道樹 + 公園）2 張表 |
| 1.5 | `handoff_package/data/power_by_district/load_csv.sql`      | 載入 12 年用電 CSV（民國 104-115） |
| 1.6 | `handoff_package/data/power_by_district/load_emission.sql` | 載入 20 年碳排 CSV（2005-2024） |

> Step 1.1–1.4 只是建表；實際塞資料的方式有兩種：
> - **(a) 直接吃 seed**：handoff_package/seeds 兩個 SQL 是完整 dump，會在 `docker compose up` 第一次 init 時自動載入（透過 `docker-compose-init.yaml` 掛 volume）。
> - **(b) 手動跑 ETL**：`handoff_package/data/hackathon_etl/charging_station_etl.py` + `green_layer_etl.py`（此路徑要 Python + requests + nominatim API key，**不推薦**，給 reference 用）。
>
> 推薦走 (a)。Step 1.1–1.4 在 (a) 模式下其實是「重置」用，正常情況不需要跑。

### Step 2：註冊 components（target = `postgres-manager:dashboardmanager`）

| 順序 | 檔案 | 註冊 component id | 註冊 dashboard id |
|---|---|---|---|
| 2.1 | `handoff_package/sql/02_charging_station_component.sql` | `501` (ev_charging_station) | `601` (sustainability_newtpe) |
| 2.2 | `handoff_package/sql/05_power_usage_component.sql`      | `502` (power_usage_district) | — |
| 2.3 | `handoff_package/sql/06_restaurant_component.sql`       | `701` (env_restaurant) | — |
| 2.4 | `handoff_package/sql/09_green_component.sql`            | (street_tree_dist + green_park_type，by index) | — |
| 2.5 | `handoff_package/data/power_by_district/MIGRATION.sql`  | `301` + `302` (power_by_district + power_vs_emission_taipei) | 暫時建一個 `metrotaipei_sustainability` dashboard，**會被 Step 3 刪掉** |

### Step 3：收尾補丁（target = `postgres-manager:dashboardmanager`）

| 檔案 | 補的事 |
|---|---|
| `handoff_package/scripts/post_migration_patches.sql` | 1) 補行道樹/綠地 component_maps 兩列<br>2) 把 map_config_ids 接到 query_charts<br>3) metrotaipei_town 改 2D fill + muted 配色（從 3D 紅色刺眼版改）<br>4) 把 components 301/302 加到 dashboard 601、刪掉重複的 `metrotaipei_sustainability` dashboard<br>5) 把 dashboard 601 同時掛在 group 2（taipei）+ group 3（metrotaipei） |

### Step 4：驗證

```bash
# 應該看到 components: {501,502,701,...,301,302}
docker exec postgres-manager psql -U postgres -d dashboardmanager \
  -c "SELECT id, index, name, components FROM dashboards WHERE id = 601;"

# 應該看到 group 2 + group 3 兩列
docker exec postgres-manager psql -U postgres -d dashboardmanager \
  -c "SELECT * FROM dashboard_groups WHERE dashboard_id = 601;"

# 完整驗證
docker exec postgres-manager psql -U postgres -d dashboardmanager \
  -f /tmp/99_verify.sql   # 先 docker cp handoff_package/sql/99_verify.sql ...
```

---

## D. Uncommitted patch（必納入）

weihong 本地有兩個尚未 commit 的小 patch，已寫進 handoff_package 對應檔。隊友環境若已跑過舊版，需 **重跑 02 + 06**（兩個 script 都會先 `DELETE` 舊 row，可直接覆蓋）：

```diff
# handoff_package/sql/02_charging_station_component.sql
- '{#7B1FA2,#0ABAB5}',          -- 汽車紫
- '{BarChart,MapLegend}',
+ '{#C866F2,#0ABAB5}',          -- 汽車亮紫
+ '{DistrictChart,BarChart,MapLegend}',  -- 加 DistrictChart

# handoff_package/sql/06_restaurant_component.sql
- '{BarChart,MapLegend}',
+ '{DistrictChart,BarChart,MapLegend}',
```

效果：充電樁/環保餐廳組件多一個 DistrictChart 視覺、充電樁紫色更亮。

---

## E. Rollback

每個 SQL 檔開頭的 `DELETE FROM ... WHERE id IN (...)` 就是 rollback。完整移除可跑：

```bash
docker exec postgres-manager psql -U postgres -d dashboardmanager -f \
  handoff_package/data/power_by_district/uninstall.sql
```

加上手動：

```sql
-- postgres-manager:dashboardmanager
DELETE FROM dashboards WHERE id = 601;
DELETE FROM components WHERE id IN (501, 502, 701);
DELETE FROM query_charts WHERE index IN (
  'ev_charging_station','power_usage_district','env_restaurant',
  'street_tree_dist','green_park_type'
);
DELETE FROM component_charts WHERE index IN (
  'ev_charging_station','power_usage_district','env_restaurant',
  'street_tree_dist','green_park_type'
);
DELETE FROM component_maps WHERE index LIKE 'ev_charging_%'
  OR index IN ('env_restaurant_tpe','env_restaurant_new_tpe',
               'street_tree_tpe','green_park_type_tpe');
```
