# 🌱 永續環境 Dashboard — 從零部署指南

> **目標**：clone 這個 repo 之後，按照這份文件操作能完整重現「永續環境」儀表板（含 8 個 component、相關地圖層、ETL 資料）。
>
> **給未來的 Claude / 接手者**：每一步都列出對應的指令，照順序貼到 terminal 跑就好。卡關時看 [troubleshooting](#troubleshooting)。

---

## TL;DR（5 分鐘版）

```bash
# 1. clone + 設定 .env
git clone https://github.com/weihong931021/Taipei-City-Dashboard-2026.git
cd Taipei-City-Dashboard-2026
cp docker/.env.example docker/.env
# ⚠️ 編輯 docker/.env：填入 VITE_MAPBOXTOKEN（必要）+ 其他你的密碼

# 2. 啟動容器（會自動載入 seed db-sample-data/*.sql）
cd docker && docker compose up -d
# 等 ~2 分鐘讓所有 service ready

# 3. 跑 5 個 SQL 補齊永續環境組件（seed 沒有的部分）
cd ..
bash handoff/run_all.sh
```

打開 http://localhost:8080 → 切到「雙北儀表板 → 永續環境」，應該看到 8 個 component。

---

## 永續環境 dashboard 含什麼

| ID | Index | 名稱 | 圖表類型 | 資料來源 |
|---|---|---|---|---|
| 300 | `vehicle_fuel_registry_tpe` | 臺北市電動車輛成長趨勢 | EVTrendChart | 交通部公路局（已內建 seed） |
| 501 | `ev_charging_station` | 雙北電動車充電樁 | BarChart + MapLegend | data.taipei + data.ntpc |
| 502 | `power_usage_ratio` | 雙北用電結構 | DonutChart | 台電 d007019 |
| 503 | `env_restaurant` | 雙北環保餐廳 | BarChart + MapLegend | data.taipei + data.ntpc |
| 504 | `street_tree_dist` | 台北行道樹分布（各區）| BarChart + Circle map | data.taipei TaipeiTree |
| 505 | `green_park_type` | 台北綠地組成（公頃）| TreemapChart + Fill map | 台北市水綠地圖集 |
| 301 | `power_by_district` | 雙北各行政區用電統計 | ColumnLineChart + Fill map | dataset/14135 |
| 302 | `power_vs_emission_taipei` | 台北市歷年碳排部門結構 | ColumnChart + BarPercentChart | 台北市環保局 |

---

## 詳細步驟

### Step 0：前置條件

- macOS / Linux + Docker Desktop（Compose v2）
- [Mapbox token](https://account.mapbox.com/access-tokens/)（免費，免費額度足夠）
- 8GB RAM（postgis + qdrant 滿吃）

### Step 1：Clone + 設定 `.env`

```bash
git clone https://github.com/weihong931021/Taipei-City-Dashboard-2026.git
cd Taipei-City-Dashboard-2026
cp docker/.env.example docker/.env
```

編輯 `docker/.env`，**至少**改這幾個：
- `VITE_MAPBOXTOKEN=` 換成你自己的 mapbox token
- `JWT_SECRET=` / `IDNO_SALT=` / 三個 `*_PASSWORD=` 換成自訂強密碼
- `VITE_MAPBOXTILE=` 是 3D 建築用的私有 tileset，沒有的話保留空字串（mapStore 會自動跳過 3D 建築）

### Step 2：啟動容器

```bash
cd docker
docker compose up -d
docker compose logs -f postgres-data postgres-manager   # 等到看到 "database system is ready" 再 ctrl+C
```

容器 init 時會自動載入 `db-sample-data/dashboard-demo.sql` + `dashboardmanager-demo.sql` 當作 seed（含基礎組件 + Yuan contributor + 永續環境 dashboard 殼）。

### Step 3：跑 ETL + 註冊組件

```bash
cd ..   # 回到 repo root
bash handoff/run_all.sh
```

這個 script 做了什麼（如果你想拆開跑）：

```bash
PG_DATA=postgres-data
PG_MGR=postgres-manager

# 3a. 把行道樹/綠地/EV/餐廳/用電的 hackathon SQL 灌進 manager
for f in 02_charging_station_component 05_power_usage_component 06_restaurant_component 09_green_component; do
  docker cp hackathon/sql/${f}.sql ${PG_MGR}:/tmp/
  docker exec ${PG_MGR} psql -U postgres -d dashboardmanager -f /tmp/${f}.sql
done

# 3b. 載入 power_by_district 用電 + 碳排原始資料 (12 年 CSV + 1 個 emission CSV)
cd power_by_district
for y in 104 105 106 107 108 109 110 111 112 113 114 115; do
  docker cp datasets/dist_kwh_${y}.csv ${PG_DATA}:/tmp/dist_kwh_${y}.csv
done
docker cp datasets/taipei_emission.csv ${PG_DATA}:/tmp/taipei_emission.csv
docker cp load_csv.sql       ${PG_DATA}:/tmp/
docker cp load_emission.sql  ${PG_DATA}:/tmp/
docker exec ${PG_DATA} psql -U postgres -d dashboard -f /tmp/load_csv.sql
docker exec ${PG_DATA} psql -U postgres -d dashboard -f /tmp/load_emission.sql

# 3c. 註冊 power_by_district 組件
docker cp MIGRATION.sql ${PG_MGR}:/tmp/
docker exec ${PG_MGR} psql -U postgres -d dashboardmanager -f /tmp/MIGRATION.sql

# 3d. Post-migration patches（修正 seed/MIGRATION.sql 沒處理的 5 件事）
cd ..
docker cp handoff/post_migration_patches.sql ${PG_MGR}:/tmp/
docker exec ${PG_MGR} psql -U postgres -d dashboardmanager -f /tmp/post_migration_patches.sql
```

### Step 4：驗證

```bash
docker exec postgres-manager psql -U postgres -d dashboardmanager -c "
  SELECT id, components FROM dashboards WHERE id = 601;
"
```

預期輸出：`{300,501,502,503,504,505,301,302}` —— 表示 8 個 component 都掛上 dashboard 601（永續環境）。

打開瀏覽器 http://localhost:8080 → 左側「雙北儀表板」→ 永續環境，應該看到完整的 8 個圖表。

---

## 各 component 在哪修改

| 你想改的東西 | 動哪裡 |
|---|---|
| EV 充電樁顏色 / 圖示 | `hackathon/sql/02_charging_station_component.sql` `component_charts.color` + `Taipei-City-Dashboard-FE/public/images/map/ev_*.png` |
| 行道樹按樹種上色 | `handoff/post_migration_patches.sql` 的 `street_tree_tpe` paint |
| 綠地配色 | `hackathon/sql/09_green_component.sql` `component_charts.color` |
| 用電 3D / 2D / 顏色 | `handoff/post_migration_patches.sql` 的 `metrotaipei_town` paint |
| 環保餐廳 icon 透明度 | `Taipei-City-Dashboard-FE/src/assets/configs/mapbox/mapConfig.js` `symbol-restaurant` |
| 各區地圖 icon 大小 | `Taipei-City-Dashboard-FE/src/assets/configs/mapbox/mapConfig.js` `symbol-{ev_charging,ev_motor,restaurant}` `icon-size` |
| EVTrendChart 切換按鈕位置 | `Taipei-City-Dashboard-FE/src/dashboardComponent/components/EVTrendChart.vue` `.ev-controls` `top` 值 |

---

## Frontend 改動清單（fork 後比對 upstream 用）

相對於 `taipei-doit/Taipei-City-Dashboard:develop`：

| 檔案 | 改了什麼 |
|---|---|
| `src/assets/configs/mapbox/mapConfig.js` | 新增 `symbol-ev_charging` / `symbol-ev_motor` / `symbol-restaurant`（含 size + opacity）、`TaipeiBuilding` 改用本人 mapbox tileset 的 source-layer |
| `src/store/mapStore.js` | 載入 ev_charging/ev_motor/restaurant icon image、3D building 加 `VITE_MAPBOXTILE` 條件、setMapLayers Promise.all → allSettled |
| `src/store/contentStore.js` | 同上 Promise.allSettled 容錯 |
| `src/dashboardComponent/components/BarChart.vue` | 多 series 自動關 distributed、支援 `chart_config.categories`、tooltip 帶 series 名 |
| `src/dashboardComponent/components/MapLegend.vue` | import 新 3 個 icon、優先用 `map_config` 渲染 legend、dedup 同 title icon |
| `src/dashboardComponent/components/EVTrendChart.vue` | 移除內部 city dropdown、汽機車 toggle 改用 absolute 浮到卡片右上角 |
| `src/dashboardComponent/utilities/cityManager.ts` | （沿用 upstream） |
| `src/components/utilities/miscellaneous/ComponentTag.vue` | `<p>` 加 `white-space: nowrap` 修字被截斷 |
| `src/components/dialogs/admin/AdminComponentSettings.vue` + `Template.vue` | 新增 `ev_charging` icon 選項 |

---

## Troubleshooting

| 症狀 | 解法 |
|---|---|
| 永續環境 tab 看不到 / 只看到 1-2 個組件 | dashboard 601 components 不齊 → 重跑 `handoff/post_migration_patches.sql` |
| 圖表顯示空白但 BE 有回 200 | `time_from` 是空字串而非 `'static'` → 檢查 query_charts.time_from |
| 某個 component 點「組件資訊」沒反應 | contributors 找不到對應 user_id → check contributors 表有沒有 component 引用的 user |
| 地圖層 toggle 打開沒效果 | `query_charts.map_config_ids` 是 NULL → 重跑 patches |
| `/api/dev/dashboard/map-layers-newtaipei 404` | 已知無害（cityManager 有 newtaipei 但 BE 不支援）→ FE 已 catch |
| 3D 建築看不到 | `VITE_MAPBOXTILE` 沒設、或 tileset 範圍不含當前視角 → zoom 到中正/大同/萬華 |
| 行道樹 zoom out 看不到 | 80k 個點按 zoom 縮放，zoom < 12 會非常細小 → 屬正常 |

---

## 核心檔案地圖

```
Taipei-City-Dashboard-2026/
├── HANDOFF.md                        ← 本檔
├── handoff/
│   ├── run_all.sh                    ← 一鍵把所有 SQL 跑完
│   └── post_migration_patches.sql    ← 收尾用，補 seed/MIGRATION 沒處理的事
│
├── hackathon/
│   └── sql/
│       ├── 02_charging_station_component.sql   ← EV 註冊
│       ├── 05_power_usage_component.sql        ← 用電結構（DonutChart）
│       ├── 06_restaurant_component.sql         ← 環保餐廳註冊
│       └── 09_green_component.sql              ← 行道樹 + 綠地註冊
│
├── power_by_district/
│   ├── README.md, MIGRATION.md       ← 用電/碳排組件詳細說明
│   ├── MIGRATION.sql                 ← 註冊 component
│   ├── load_csv.sql                  ← 12 年用電 ETL
│   ├── load_emission.sql             ← 碳排 ETL
│   └── datasets/                     ← 13 份原始 CSV (76MB)
│
├── db-sample-data/
│   ├── dashboard-demo.sql            ← 資料 seed（dashboard DB）
│   └── dashboardmanager-demo.sql     ← 設定 seed（manager DB）
│
└── Taipei-City-Dashboard-FE/
    ├── public/
    │   ├── images/map/{ev_charging,ev_motor,restaurant}.png   ← 地圖 icon
    │   └── mapData/                                           ← geojson 圖層
    └── src/  (見上面 Frontend 改動清單)
```
