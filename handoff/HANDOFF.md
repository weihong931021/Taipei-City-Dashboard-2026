# Taipei-City-Dashboard 交接文件

這份文件給接手這個專案的人看。**從零部署到能跑路徑規劃 + RAG 問答**所需的全部內容都在 repo 裡,本資料夾把 SQL / 資料 / 腳本 / 規格集中起來。

> **TL;DR**: clone → 填 `.env` → 跑 `handoff/scripts/` 三支 script → BE/FE 跑起來 → 開 chatbot 問問題。

---

## 1. 專案概覽

### 1.1 這個專案做什麼

- **核心**:Taipei 市政府開源的 City Dashboard,顯示城市儀表板 + 地圖圖層。
- **這次新加的東西** (`feature/ai-rag-route-panel` branch):
  - 城市生活 AI 助手 (chatbot)
  - 文件問答 (RAG, knowledge base = `md_files/`)
  - 路線規劃 + 自訂路徑面板 (取代 mapbox-gl-directions)
  - 碳排計算
  - 環保餐廳 / 電動車充電站 POI 搜尋

### 1.2 Repo 結構

```
.
├── Taipei-City-Dashboard-FE/      # Vue 3 + Pinia 前端
├── Taipei-City-Dashboard-BE/      # Go (Gin) 後端
├── Taipei-City-Dashboard-DE/      # Airflow ETL (城市資料)
├── csv_files/                     # 環保餐廳 / 充電站 / 碳排係數 等 15 支 CSV
├── md_files/                      # RAG 知識庫 13 份 (永續政策/補助/循環經濟)
├── docker/
│   ├── docker-compose.yaml        # FE + BE + nginx
│   ├── docker-compose-db.yaml     # postgres-data + postgres-manager + redis + qdrant
│   ├── csv-ingest/                # CSV → Postgres ETL (Python)
│   ├── md-ingest/                 # MD → Qdrant ETL (Python)
│   └── nginx/, qdrant-upgrade/
├── db-sample-data/                # 原專案的 demo SQL dumps
└── handoff/                       # ← 你現在在看的這個資料夾
```

---

## 2. 系統架構

```
            ┌─────────────────────────────────────────────────────┐
            │ Taipei-City-Dashboard-FE  (Vue 3, Vite, Pinia)      │
            │   - MapContainer + RoutePanel.vue (自訂路徑面板)    │
            │   - ChatBox.vue + aiChatStore (CoT chatbot)         │
            └──────────────┬──────────────────────────────────────┘
                           │ /api/v1/...  /ai/chat/twai
                           ▼
            ┌─────────────────────────────────────────────────────┐
            │ Taipei-City-Dashboard-BE  (Go, Gin)                 │
            │   ai_service.go  →  tool calling                    │
            │   tools/                                            │
            │     ├ search_documents      (Qdrant 語意搜尋)       │
            │     ├ resolve_location      (Mapbox geocode)        │
            │     ├ search_nearby_pois    (PostGIS ST_DWithin)    │
            │     ├ compute_route         (Mapbox Directions)     │
            │     └ compute_carbon_emission (CSV 係數表)          │
            └──┬───────────────┬──────────────┬──────────────┬────┘
               │               │              │              │
               ▼               ▼              ▼              ▼
        ┌──────────┐    ┌────────────┐  ┌──────────┐  ┌──────────┐
        │ Postgres │    │  Qdrant    │  │  Mapbox  │  │   TWCC   │
        │ (PostGIS)│    │  documents │  │   API    │  │  (LLM)   │
        │ + redis  │    │ collection │  │          │  │ Llama 70B│
        └──────────┘    └────────────┘  └──────────┘  └──────────┘
        dashboarddb     向量 768d (e5)   geocoding +   tool calling
        + manager db                      directions
```

### 2.1 外部依賴 (你要申請帳號的)

| 服務 | 用途 | 需要 |
|---|---|---|
| **Mapbox** | 地圖底圖、地址 geocoding、路徑規劃 | API token (`pk....`),免費額度足夠開發 |
| **TWCC (台灣 AI 雲)** | LLM 推論 (Llama 3.3-70B) | API key,要去台灣 AI Cloud 申請 |
| **Qdrant** | 向量資料庫 (RAG) | 自己 docker run 一個就好,不必雲服務 |

---

## 3. 資料庫規格

### 3.1 用到的 Postgres 資料庫

| DB 名稱 | 用途 | Schema 來源 |
|---|---|---|
| `dashboarddb` | 元件 / 圖表 / dashboard 設定 + AI 工具表 (restaurants, ev_stations) | `handoff/sql/01_dashboard.sql` + `handoff/sql/03_ai_tools_schema.sql` |
| `dashboardmanagerdb` | 帳號 / 權限 | `handoff/sql/02_dashboardmanager.sql` |

兩個 DB 在 docker-compose 裡跑成兩個獨立 container (`postgres-data` 和 `postgres-manager`)。

### 3.2 AI 工具用到的資料表

兩張都在 `dashboarddb` 裡,**必須裝 PostGIS**(`CREATE EXTENSION postgis;`)。

#### `restaurants`(環保餐廳)
| 欄位 | 型別 | 說明 |
|---|---|---|
| id | SERIAL PK | |
| name | TEXT NOT NULL | 餐廳名稱 |
| city | TEXT | 臺北市 / 新北市 |
| district | TEXT | 行政區 |
| address | TEXT | 完整地址 |
| phone | TEXT | |
| eco_tags | TEXT[] | 環保標籤陣列 |
| source | TEXT | 來源 CSV (`taipei_eco_restaurants` / `newtaipei_eco_restaurants`) |
| lat, lng | DOUBLE PRECISION | |
| location | GEOGRAPHY(Point, 4326) | PostGIS 點,給 ST_DWithin 用 |

索引: `restaurants_loc_gix` (GIST), `restaurants_city_idx`, `restaurants_district_idx`

#### `ev_stations`(充電/換電站)
| 欄位 | 型別 | 說明 |
|---|---|---|
| id | SERIAL PK | |
| name | TEXT NOT NULL | 站點名 |
| city | TEXT | 臺北市 / 新北市 |
| district | TEXT | |
| address | TEXT | |
| vehicle_type | TEXT | `car` / `scooter` |
| service_type | TEXT | `charging` (充電) / `swap` (換電) |
| operator | TEXT | 業者 (中油 / 特斯拉 / Gogoro …) |
| plug_type | TEXT | 充電規格 (CCS1, CCS2, J1772, CHAdeMO, …) |
| connector_count | INTEGER | 槍/插座數 |
| fee_required | BOOLEAN | 需付費? |
| source | TEXT | 來源 CSV |
| lat, lng | DOUBLE PRECISION | |
| location | GEOGRAPHY(Point, 4326) | |

索引: `ev_stations_loc_gix` (GIST), `ev_stations_city_idx`, `ev_stations_vehicle_idx`, `ev_stations_service_idx`

### 3.3 Qdrant collections

| collection | 用途 | 維度 | 模型 |
|---|---|---|---|
| `query_charts` | 既有功能 — chart 描述語意搜尋 | (沿用原專案設定) | |
| `documents` | **本次新增** — `md_files/` 語意檢索 (RAG) | 768 | `intfloat/multilingual-e5-base` |

`documents` collection 的每個 point payload:
```json
{
  "source_file": "taipei_eco_restaurants_details.md",
  "heading_path": "餐廳一覽 > 環保餐廳",
  "chunk_idx": 3,
  "text": "...",
  "char_start": 1500
}
```

---

## 4. 資料內容

### 4.1 `csv_files/`(15 支 CSV)

| 檔名 | 用途 | 進到哪張表 |
|---|---|---|
| 臺北市環保餐廳.csv | RAG / POI | `restaurants` |
| 新北市環保餐廳.csv | RAG / POI | `restaurants` |
| 臺北市電動機車充電站.csv | POI | `ev_stations` (scooter, charging) |
| 臺北市營利電動機車充電站.csv | POI | `ev_stations` (scooter, charging) |
| 臺北市營利電動機車換電站.csv | POI | `ev_stations` (scooter, swap) |
| 臺北市營利型電動車充換電站資訊.csv | POI | `ev_stations` (car) |
| 臺北市電動車充電停車位概況.csv | 統計 | (僅查詢用) |
| 新北市電動機車充電站.csv | POI | `ev_stations` |
| 新北市電動汽車充電站.csv | POI | `ev_stations` |
| 小客車動態能耗與碳排放係數.csv | 碳排計算 | `compute_carbon_emission` 工具讀 |
| 大客車動態能耗與碳排放係數.csv | 碳排計算 | 同上 |
| 機車動態能耗與碳排放係數.csv | 碳排計算 | 同上 |
| 歷年電車成長趨勢.csv | 統計 | (參考) |
| 空氣品質指標(AQI).csv | 統計 | (參考) |
| 臺北市溫室氣體排放統計—本市總排放量及人均排放量.csv | 統計 | (參考) |

### 4.2 `md_files/`(13 份 RAG 知識庫)

被 `docker/md-ingest/ingest_md.py` 切 chunk → embedding → 進 Qdrant `documents` collection。

| 檔名 | 主題 |
|---|---|
| 2020_resource_recycling_annual_report.md | 2020 資源回收年報 |
| 2023_resource_circulation_interagency_report_v6_1.md | 跨部會循環經濟報告 |
| 2025_government_plan_performance_report.md | 2025 政府施政績效 |
| 2025_new_taipei_vlr_zh_251204.md | 新北市永續發展自願檢視報告 (VLR) |
| 20080916_economic_stimulus_plan_appendix_2.md | 振興經濟方案附錄 |
| AC8FB4B99BB74AD.md | 政策文件 |
| circular_economy_trends_and_key_issues.md | 循環經濟趨勢與議題 |
| residential_appliance_replacement_energy_subsidy_guidelines.md | 家電汰換補助辦法 |
| resource_recycling_handbook.md | 資源回收手冊 |
| subsidize2g_3.md | 二行程補助 |
| taipei_eco_restaurants_details.md | 台北環保餐廳細節 |
| taipei_food_fun_tourism_handbook_2025.md | 台北食宿旅遊手冊 2025 |
| undiscovered_taipei_map.md | 台北秘境地圖 |

### 4.3 `docker/csv-ingest/cache/geocode_cache.json`

ETL 過程中 Mapbox 地址 → 座標的快取。**重要**:接手者不要刪掉,跑 `2_load_csv_to_pg.sh` 時會大幅減少 Mapbox API 用量。

---

## 5. 完整部署步驟

### 5.1 先決條件

- Docker Desktop (推薦)
- Postgres 14+ (with PostGIS) — Docker compose 會處理
- Python 3.10+ (跑 ETL 腳本要)
- Node 20+ (跑 FE 要)
- Go 1.22+ (跑 BE 要)
- 一個 Mapbox token、一個 TWCC API key

### 5.2 步驟

```bash
# 1. clone
git clone https://github.com/frank931023/dashboard-26.git
cd dashboard-26

# 2. 設 env
cp handoff/env.example docker/.env
cp handoff/env.example Taipei-City-Dashboard-FE/.env.development
# 編輯這兩個 .env,填入 Mapbox token / TWCC key / Postgres 密碼

# 3. 把後端服務拉起來 (Postgres + Qdrant + Redis)
cd docker
docker network create --driver=bridge --subnet=192.168.128.0/24 \
    --gateway=192.168.128.1 br_dashboard
docker compose -f docker-compose-db.yaml up -d
cd ..

# 4. 套用 SQL (建 DB + schema + demo 資料)
bash handoff/scripts/1_setup_databases.sh

# 5. 把 CSV 灌進 Postgres (restaurants + ev_stations)
bash handoff/scripts/2_load_csv_to_pg.sh

# 6. 把 MD 灌進 Qdrant (RAG knowledge base)
bash handoff/scripts/3_ingest_md_to_qdrant.sh

# 7. 跑 BE
cd docker
docker compose up -d dashboard-be
# 或本機:cd Taipei-City-Dashboard-BE && go run main.go

# 8. 跑 FE
docker compose up -d dashboard-fe
# 或本機:cd Taipei-City-Dashboard-FE && npm install && npm run dev

# 9. 開瀏覽器到 http://localhost:8080 (docker) 或 http://localhost:5173 (本機 vite)
```

---

## 6. 用法 / 怎麼測

### 6.1 RAG 文件問答

開 chatbot 問:
- 「台北市環保餐廳補助有哪些?」
- 「家電汰換補助怎麼申請?」
- 「2025 年台北的循環經濟目標」

AI 會呼叫 `search_documents` 工具去 Qdrant 撈最相關的 chunks,回答時會在句尾標註 `[來源: 檔名]`。

### 6.2 路線規劃

開 chatbot 問:
- 「我要從信義區去台北 101」
- 「從台北車站騎車到象山」
- 「從西門町走路到龍山寺,中間經過華西街夜市」(會把「華西街夜市」當 waypoint)

AI 會用 CoT 反問 (出發地?交通方式?),收齊資訊後依序呼叫:
1. `resolve_location` 把地名轉座標
2. `compute_route` 算路徑(支援 waypoints)
3. `compute_carbon_emission` 算碳排

地圖左上會出現「路徑規劃」面板:
- A / 停靠點 / B 直欄 inline 編輯,`+` 加停靠點 / `−` 移除
- 開車 / 走路 / 騎車 切換 (即時重算)
- 同一面板下方的「行程」section 列出每段 turn-by-turn 中文指示
- 路徑線**按段染色**(7 色循環),A/編號/B 端點 marker
- 整個面板右上角有 ◀ 收起,收起後變成左邊一個小 handle

### 6.3 找附近 POI

開 chatbot 問:
- 「附近有哪些環保餐廳?」(會反問你目前位置)
- 「最近的特斯拉充電站」
- 「信義區附近的換電站」

AI 用 `resolve_location` 拿你提供的位置座標,再用 PostGIS `ST_DWithin` 半徑搜尋(預設 1500 m)。

---

## 7. 重要程式碼導覽

### 7.1 後端 AI tools (`Taipei-City-Dashboard-BE/app/services/ai/tools/`)

| 檔 | 說明 |
|---|---|
| `registry.go` | 工具註冊;`search_documents` 在這(Qdrant 查詢) |
| `location.go` | `resolve_location` + `search_nearby_pois` + `compute_route` |
| `carbon.go` | `compute_carbon_emission`,讀 `csv_files/*碳排放係數*` |
| `../ai_service.go` | tool-calling loop;呼叫 TWCC LLM 後解析 tool_calls 執行 |

### 7.2 前端 AI / 路徑面板

| 檔 | 說明 |
|---|---|
| `Taipei-City-Dashboard-FE/src/store/aiChatStore.js` | Pinia store, system prompt + CoT 澄清流程 + tool 結果套用 |
| `Taipei-City-Dashboard-FE/src/store/mapStore.js` | 加了 `aiRoute` state, `setRoute`/`recomputeRoute`/分段渲染 |
| `Taipei-City-Dashboard-FE/src/components/map/RoutePanel.vue` | 自訂面板 (路徑+行程合併) |
| `Taipei-City-Dashboard-FE/src/components/dialogs/ChatBox.vue` | 聊天視窗 + 快速回覆按鈕 |

### 7.3 ETL 腳本

| 檔 | 說明 |
|---|---|
| `docker/csv-ingest/etl.py` | CSV → Postgres,含 Mapbox 地理編碼 |
| `docker/csv-ingest/apply_cache.py` | 把 geocode_cache.json 套用到既有資料表 (沒重新 geocode 的話用) |
| `docker/md-ingest/ingest_md.py` | MD 切 chunk + e5-base embedding → Qdrant |

---

## 8. 常見問題

### Q1. AI 不會反問,直接亂答
- 看 `aiChatStore.js` 的 `SYSTEM_PROMPT`,確認 LLM 真的有讀到。
- TWCC 模型若改成更小的 (像 8B),可能不會嚴格依 prompt 執行,建議用 70B 以上。

### Q2. 地圖路徑線沒畫出來
- F12 看 console 有無 `setRoute failed`、`renderRoute`、`recomputeRoute` 的 warning。
- 確認 `VITE_MAPBOXTOKEN` 有填,沒填的話路徑沒辦法重算。
- 檢查 BE log,`compute_route` 工具有沒有成功回 geometry。

### Q3. RAG 查不到東西
- 確認 Qdrant 的 `documents` collection 真的有資料 (`curl <QDRANT_URL>/collections/documents` 看 points_count)。
- 沒資料就重跑 `bash handoff/scripts/3_ingest_md_to_qdrant.sh`。

### Q4. ETL 跑很久 / Mapbox 用量爆掉
- 用 repo 內附的 `docker/csv-ingest/cache/geocode_cache.json`,大部分地址都已快取。
- 若要重新 geocode,設 `--no-geocode` 跳過,只用 CSV 裡已有的 lat/lng。

### Q5. Postgres 沒裝 PostGIS
- 用 `postgis/postgis:15-3.3` Docker image,自動帶。
- 否則裝完要 `CREATE EXTENSION postgis;` 在 dashboarddb 裡跑一次。

### Q6. 帳號登入 (auth) 問題
- 開發階段 BE 路由的 `IsLoggedIn()` middleware 已**暫時註解掉**(`router.go`),讓 chatbot 不用登入也能玩。**正式上線前要解除註解!**

---

## 9. 後續開發建議

- **加更多 RAG 文件**:把新 .md 丟進 `md_files/`,重跑 step 6 即可。
- **加更多 POI 類別**:在 `csv_files/` 加 CSV → 改 `etl.py` 的 dataframe 讀取邏輯 → 改 `tools/location.go` 的 `search_nearby_pois` category enum → 改 FE `aiChatStore.js` 工具 schema description。
- **改 LLM 提供者**:目前綁 TWCC,改其他 OpenAI-compatible 端點只要動 `BE/app/services/ai/ai_service.go`(改 endpoint + payload 格式)。
- **路徑面板新功能**:畫面上點 marker 顯示詳情、拖曳 waypoint 重排順序、儲存常用路徑等,都可以擴充 `RoutePanel.vue` + `mapStore.aiRoute`。

---

## 10. 聯絡 / 來源

- 原專案上游:https://github.com/tpe-doit/Taipei-City-Dashboard
- 本 fork:`frank931023/dashboard-26`
- 主要 commit `feature/ai-rag-route-panel`(AI + 路徑面板的所有改動)

如果你卡住,先翻 `aiChatStore.js` 跟 `mapStore.js` 的註解,我寫得很多。Tool 呼叫順序看 BE log + 瀏覽器 Network panel 的 `/ai/chat/twai` 回傳 (有 `tool_invocations` 陣列)。
