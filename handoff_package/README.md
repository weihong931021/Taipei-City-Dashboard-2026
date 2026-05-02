# 🌱 永續環境 Dashboard — 交棒包

**內容**：完整重建 Taipei-City-Dashboard-2026 永續環境儀表板所需的所有 SQL、CSV、ETL 腳本、設定範例、提案文件。

**前置**：需要 Taipei-City-Dashboard-2026 repo 的 docker 環境（postgres-data + postgres-manager 兩個 PostgreSQL container）已經跑起來。

---

## 📦 包裝結構

```text
handoff_package/
├── README.md                                ← 本檔
├── scripts/
│   ├── run_all.sh                           ← 一鍵跑完所有 SQL + ETL
│   ├── post_migration_patches.sql           ← 收尾用補丁
│   └── docker.env.example                   ← .env 範本（沒有實際 token）
│
├── sql/                                     ← hackathon SQL（12 份）
│   ├── 01_charging_station_schema.sql
│   ├── 02_charging_station_component.sql   ★ 註冊 EV 充電樁組件
│   ├── 03_env_restaurant_schema.sql
│   ├── 04_power_usage_schema.sql
│   ├── 05_power_usage_component.sql        ★ 註冊用電結構組件
│   ├── 06_restaurant_component.sql         ★ 註冊環保餐廳組件
│   ├── 07_export_geojson.sql
│   ├── 08_green_schema.sql
│   ├── 09_green_component.sql              ★ 註冊行道樹/綠地組件
│   ├── 99_verify.sql
│   └── snapshot_*.sql
│
├── data/
│   ├── hackathon/                          ← 行道樹/綠地原始 CSV
│   │   ├── street_tree.csv
│   │   ├── green_park.csv
│   │   └── geocode_cache.json
│   │
│   ├── hackathon_etl/                      ← 充電樁/綠地 Python ETL（選用）
│   │   ├── charging_station_etl.py
│   │   └── green_layer_etl.py
│   │
│   └── power_by_district/                  ← 用電 + 碳排整套
│       ├── README.md, MIGRATION.md         ← 該組件詳細說明
│       ├── MIGRATION.sql                   ★ 註冊用電/碳排組件
│       ├── load_csv.sql                    ★ 載入 12 年用電
│       ├── load_emission.sql               ★ 載入 20 年碳排
│       ├── uninstall.sql
│       ├── job_config.json, power_by_district.py
│       └── datasets/                       ← 13 份 CSV（76MB）
│           ├── dist_kwh_104.csv ~ 115.csv  (12 年用電，民國 104-115)
│           └── taipei_emission.csv         (20 年碳排，2005-2024)
│
├── seeds/                                   ← Docker init 自動載入的 DB seed
│   ├── dashboard-demo.sql                  (基礎 dashboard 資料 + 充電樁/餐廳)
│   └── dashboardmanager-demo.sql           (基礎組件 + Yuan + 永續 dashboard 殼)
│
└── proposals/                               ← Hackathon 提案文件（背景參考）
    ├── HACKATHON_proposal_1_accident.md
    ├── HACKATHON_proposal_2_disaster.md
    └── HACKATHON_proposal_3_heat.md
```

★ 標記 = `run_all.sh` 會跑的核心 SQL

---

## 🚀 部署步驟

### 0. 前置假設

Taipei-City-Dashboard-2026 repo 已經 clone、docker 已啟動：

```bash
cd Taipei-City-Dashboard-2026/docker
cp ../handoff_package/scripts/docker.env.example .env
# 編輯 .env：填 VITE_MAPBOXTOKEN + 改密碼
docker compose up -d
sleep 120  # 等所有 service ready
```

容器跑起來後，docker 會自動把 `seeds/` 兩個 SQL 載進對應的 DB（透過 `docker-compose-init.yaml` 掛 volume）。

### 1. 跑所有 SQL + ETL

進到 repo 根目錄，跑：

```bash
cd /path/to/Taipei-City-Dashboard-2026
bash handoff_package/scripts/run_all.sh
```

⚠️ `run_all.sh` 預設讀 repo 根目錄下的 `hackathon/` 跟 `power_by_district/` 路徑。如果你只有 handoff_package 沒整個 repo，改用下面的「手動模式」。

### 2. 完成驗證

```bash
docker exec postgres-manager psql -U postgres -d dashboardmanager -c \
  "SELECT id, components FROM dashboards WHERE id = 601;"
```

預期：`{300,501,502,503,504,505,301,302}` — 8 個 component 都掛上。

打開 <http://localhost:8080> → 雙北儀表板 → 永續環境，看到 8 個圖表。

---

## 手動模式（沒 run_all.sh / 想分步跑）

```bash
PG_DATA=postgres-data
PG_MGR=postgres-manager
PKG=handoff_package    # 改成你的 handoff_package 實際路徑

# Step 1: 註冊 5 個永續環境 component
for f in 02_charging_station_component 05_power_usage_component 06_restaurant_component 09_green_component; do
  docker cp ${PKG}/sql/${f}.sql ${PG_MGR}:/tmp/
  docker exec ${PG_MGR} psql -U postgres -d dashboardmanager -f /tmp/${f}.sql
done

# Step 2: 載入用電 12 年 CSV
for y in 104 105 106 107 108 109 110 111 112 113 114 115; do
  docker cp ${PKG}/data/power_by_district/datasets/dist_kwh_${y}.csv ${PG_DATA}:/tmp/
done
docker cp ${PKG}/data/power_by_district/load_csv.sql ${PG_DATA}:/tmp/
docker exec ${PG_DATA} psql -U postgres -d dashboard -f /tmp/load_csv.sql

# Step 3: 載入碳排
docker cp ${PKG}/data/power_by_district/datasets/taipei_emission.csv ${PG_DATA}:/tmp/
docker cp ${PKG}/data/power_by_district/load_emission.sql ${PG_DATA}:/tmp/
docker exec ${PG_DATA} psql -U postgres -d dashboard -f /tmp/load_emission.sql

# Step 4: 註冊用電 / 碳排 component
docker cp ${PKG}/data/power_by_district/MIGRATION.sql ${PG_MGR}:/tmp/
docker exec ${PG_MGR} psql -U postgres -d dashboardmanager -f /tmp/MIGRATION.sql

# Step 5: 補丁（接合到 dashboard 601、加地圖層、metrotaipei_town 改 2D）
docker cp ${PKG}/scripts/post_migration_patches.sql ${PG_MGR}:/tmp/
docker exec ${PG_MGR} psql -U postgres -d dashboardmanager -f /tmp/post_migration_patches.sql
```

---

## 各檔案做什麼

| 檔案 | 跑在 | 動作 |
|---|---|---|
| `sql/02_charging_station_component.sql` | manager | 建 EV 組件 (id 501)、4 個充電樁地圖層、雙北 BarChart query |
| `sql/05_power_usage_component.sql` | manager | 建用電結構組件 (id 502)、DonutChart query |
| `sql/06_restaurant_component.sql` | manager | 建餐廳組件 (id 503)、2 個餐廳地圖層、雙北 BarChart query |
| `sql/09_green_component.sql` | manager | 建行道樹 (id 504) + 綠地 (id 505) 組件 |
| `data/power_by_district/load_csv.sql` | data | 載入 12 年用電 → `power_by_district` 表（70233 筆） |
| `data/power_by_district/load_emission.sql` | data | 載入 20 年碳排 → `taipei_emission` 表（20 筆） |
| `data/power_by_district/MIGRATION.sql` | manager | 建用電 (id 301) + 碳排 (id 302) 組件、3D 用電地圖層 |
| `scripts/post_migration_patches.sql` | manager | **5 個收尾**：行道樹/綠地地圖層、map_config_ids 接合、用電 3D→2D + muted 配色、整合到 dashboard 601、taipei group 補掛 |

---

## 故障排除

| 症狀 | 原因 | 解法 |
|---|---|---|
| 永續環境 tab 看不到 / 只有 1-2 個圖 | dashboard 601 components 不齊 | 重跑 `post_migration_patches.sql` |
| 圖表回 200 但顯示空白 | query_chart `time_from` 是空字串而非 `'static'` | `UPDATE query_charts SET time_from='static' WHERE index='...';` |
| 「組件資訊」按鈕點下去無反應 | `contributors` 表沒對應 user_id | 檢查 `contributors` 是否有 'Yuan' / 'doit' / 'ntpc' |
| 地圖層 toggle 無作用 | `query_charts.map_config_ids` 是 NULL | 重跑 `post_migration_patches.sql` |
| 中文亂碼 | 透過 stdin pipe 編碼遺失 | 一律用 `docker cp` 進容器後用 `psql -f` |

---

## 來源

- Taipei City Dashboard upstream：[`taipei-doit/Taipei-City-Dashboard`](https://github.com/taipei-doit/Taipei-City-Dashboard)
- 本 fork：[`weihong931021/Taipei-City-Dashboard-2026`](https://github.com/weihong931021/Taipei-City-Dashboard-2026)
- 完整 repo 部署文件：repo 根目錄的 `HANDOFF.md`
