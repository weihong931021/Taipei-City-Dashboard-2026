# 🚀 合併後完整 Setup 流程

涵蓋兩塊一起跑:
- **A 半:永續環境 dashboard**(weihong / `handoff_package/`)— 5 個組件 + power_by_district
- **B 半:AI 城市助手**(frank / `handoff/`)— RAG + 路線規劃 + 碳排計算 + qdrant + redis

---

## 0. 前置(只做一次)

### 0.1 必裝

- Docker Desktop 24+ (含 Compose v2)
- Git
- 一個 [Mapbox token](https://account.mapbox.com/access-tokens/)(免費)
- 一個 [TWCC API key](https://www.twcc.ai/)(台灣 AI 雲,跑 LLM 用)

> 不需要本機裝 Python / Node / Go,所有東西都在 container 裡。

### 0.2 環境變數

把兩份 env example 合併:

```bash
cd Taipei-City-Dashboard-2026

# B 半提供的 template 比較完整,當基底
cp handoff/env.example docker/.env

# 編輯 docker/.env 必填:
#   VITE_MAPBOXTOKEN, MAPBOX_TOKEN     (同一個 pk.* token)
#   TWCC_API_URL, TWCC_API_KEY, TWCC_MODEL
#   DB_DASHBOARD_PASSWORD, DB_MANAGER_PASSWORD   (任意)
#   QDRANT_API_KEY                       (任意,但 docker-compose 跟 BE 兩邊要對得上)
#   QDRANT_DOC_COLLECTION=documents      (B 半 RAG 用)
#   JWT_SECRET, IDNO_SALT                (任意 random string)
```

### 0.3 Docker network(注意:**已改名**)

```bash
docker network create --driver=bridge \
  --subnet=192.168.129.0/24 --gateway=192.168.129.1 \
  br_dashboard_2026
```

> 原本 frank 的 doc 寫 `br_dashboard` + `192.168.128.0/24`,本 repo merge 後改成 `br_dashboard_2026` + `192.168.129.0/24`(避開既有 dev 環境)。`docker-compose-{db,init}.yaml` + `handoff/scripts/02,03` 已同步修正。

---

## 1. DB 層(postgres + qdrant + redis + pgadmin)

```bash
docker compose -f docker/docker-compose-db.yaml up -d
sleep 30   # 等兩個 postgres ready
docker ps | grep -E "postgres|qdrant|redis|pgadmin"
```

預期容器:`postgres-data`, `postgres-manager`, `qdrant`, `redis`, `pgadmin`。

---

## 2. Init container(BE cobra 命令套既有 schema/demo)

```bash
docker compose -f docker/docker-compose-init.yaml up
# 跑完 container 自己 exit
```

這步把 `db-sample-data/dashboard-demo.sql` + `dashboardmanager-demo.sql` seed 進去(這兩份 dump **包含我這邊永續組件的 demo 資料**,所以 A 半的 components 501/502/701 + dashboard 601 一進來就有了)。

---

## 3. AI 工具表 schema + 資料 + RAG 知識庫(B 半)

```bash
# 3a. 建 restaurants + ev_stations 兩張新表(裝 PostGIS extension)
bash handoff/scripts/01_apply_ai_schema.sh

# 3b. 15 支 CSV → Postgres,首次會用 docker/csv-ingest/cache/geocode_cache.json
#     避免重打 Mapbox geocode API,~600 筆 POI
bash handoff/scripts/02_load_csv_to_pg.sh

# 3c. 13 份 MD → Qdrant `documents` collection
#     首次 build image 要 download e5-base 模型 ~1.1 GB,耐心等
bash handoff/scripts/03_ingest_md_to_qdrant.sh
```

> 都跑完才能用 AI 助手的「文件問答」「附近 POI」「碳排計算」三個工具。

---

## 4. 永續環境組件 SQL + ETL(A 半)

```bash
bash handoff_package/scripts/run_all.sh
```

依序跑:
- 5 個 component 註冊 SQL(EV / 餐廳 / 用電 / 行道樹 / 綠地)→ `dashboardmanager`
- 12 年用電 CSV + 20 年碳排 CSV → `dashboard`
- power_by_district MIGRATION + post-migration patches

完成後 dashboard 601 (`sustainability_newtpe`) 應該有 5+2 個 components。

> 詳細執行順序 + idempotent / rollback 說明見 [`handoff_package/DB_MIGRATION.md`](DB_MIGRATION.md)。

---

## 5. 應用層(BE + FE + nginx)

```bash
docker compose -f docker/docker-compose.yaml up -d
```

### ⚠️ 重要:每次 git pull / merge 後,**必須重 build BE / FE**

```bash
docker compose -f docker/docker-compose.yaml up -d --build dashboard-be dashboard-fe
```

不重 build 會看到很經典的症狀:**舊 BE container 沒有新 tool 註冊**(例如 `compute_carbon_emission`),AI chat 會回 `(沒有回覆)`,BE log 出現 `Tool Error: tool xxx not found`。

---

## 6. 驗證

### 6.1 開瀏覽器

| URL | 說明 |
|---|---|
| http://localhost:8080 | FE(主) |
| http://localhost:8088 | BE API |
| http://localhost:6333/dashboard | Qdrant 控制台 |
| http://localhost:8889 | pgadmin |

### 6.2 DB sanity check

```bash
# A 半 — 永續組件
docker exec postgres-manager psql -U postgres -d dashboardmanager -c \
  "SELECT id, index, components FROM dashboards WHERE id = 601;"
# 預期 components 含 {501,502,701,...,301,302}

# B 半 — POI 表
docker exec postgres-data psql -U postgres -d dashboard -c \
  "SELECT (SELECT count(*) FROM restaurants), (SELECT count(*) FROM ev_stations);"
# 預期都 > 0

# B 半 — RAG 知識庫
curl -s http://localhost:6333/collections/documents \
  -H "api-key: $QDRANT_API_KEY" | jq '.result.points_count'
# 預期 50+
```

### 6.3 功能測試

#### A 半:`http://localhost:8080/mapview?index=sustainability_newtpe&city=metrotaipei`

預期看到 5 個組件:充電樁 / 環保餐廳 / 行道樹 / 綠地 / 用電碳排。地圖上應有充電樁紫/綠 icon + 餐廳橘 icon。

#### B 半:右下角機器人 icon → chatbot

- **RAG**:「台北市環保餐廳補助有哪些?」→ 應有 `[來源: xxx.md]` 引用
- **路徑**:「我要從信義區去台北 101」→ AI 反問交通工具 → 選後地圖出現分段路徑線
- **POI**:「附近有哪些環保餐廳?」→ AI 反問位置

---

## 7. 日常開發循環

```bash
# 早上開機
docker compose -f docker/docker-compose-db.yaml up -d
docker compose -f docker/docker-compose.yaml    up -d

# 改完 BE Go code
docker compose -f docker/docker-compose.yaml up -d --build dashboard-be

# 改完 FE Vue code(若不用 hot reload)
docker compose -f docker/docker-compose.yaml up -d --build dashboard-fe

# 收工
docker compose -f docker/docker-compose.yaml    down
docker compose -f docker/docker-compose-db.yaml down   # 通常 DB 不關
```

---

## 8. Failure cheat sheet(合併後常見問題)

| 症狀 | 真因 | 解 |
|---|---|---|
| AI chat 回「(沒有回覆)」 | BE container 是 merge 前舊版,新 tool 沒註冊 | `up -d --build dashboard-be` |
| BE log: `Tool Error: tool xxx not found` | 同上 | 同上 |
| `There is already a source with ID "..."` | mapStore.js 重複 addSource | 已 patch(本 commit 加 `getSource()` guard) |
| `Cannot read properties of undefined (reading 'includes')` MobileLayers.vue | `currentDashboard.index` 在初始載入時為 undefined | 已 patch(本 commit 加 optional chaining) |
| `Geolocation permission has been blocked` | **瀏覽器權限**,跟程式無關 | 點網址列 🔒 → Location → Allow → F5 |
| `events.mapbox.com BLOCKED_BY_CLIENT` | ad blocker / Brave Shields 擋 mapbox telemetry | 不影響功能,可忽略 |
| RAG 查不到 | qdrant `documents` collection 空 | 重跑 `bash handoff/scripts/03_ingest_md_to_qdrant.sh` |
| 地圖 icon 缺 | `public/images/map/*.png` 沒進到 fe build | 重 build dashboard-fe |
| 永續組件出不來但 BE log 200 | seed 已跑過,但 `run_all.sh` 沒跑 | 跑 `bash handoff_package/scripts/run_all.sh` |
| Network 連不上 | network 名沒對齊 | `docker network ls` 確認 `br_dashboard_2026` 存在 |

---

## 9. 完整 happy-path 一行版本(從零到能跑)

```bash
git clone https://github.com/weihong931021/Taipei-City-Dashboard-2026.git
cd Taipei-City-Dashboard-2026
cp handoff/env.example docker/.env
# 編輯 docker/.env 填 token 跟密碼
docker network create --driver=bridge \
  --subnet=192.168.129.0/24 --gateway=192.168.129.1 br_dashboard_2026
docker compose -f docker/docker-compose-db.yaml up -d && sleep 30
docker compose -f docker/docker-compose-init.yaml up
bash handoff/scripts/01_apply_ai_schema.sh
bash handoff/scripts/02_load_csv_to_pg.sh
bash handoff/scripts/03_ingest_md_to_qdrant.sh
bash handoff_package/scripts/run_all.sh
docker compose -f docker/docker-compose.yaml up -d --build
# → http://localhost:8080
```

完整總執行時間:首次 ~30-45 分(主要是 e5-base 模型 + Mapbox geocode 不在 cache 的部分),之後 < 5 分。
