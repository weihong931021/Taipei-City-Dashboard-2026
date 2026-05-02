# 交接資料夾 (handoff/)

把專案交給下一位開發者所需的設定範本、SQL、Setup 腳本、規格文件。

## 內容

```
handoff/
├── HANDOFF.md                  ← 主要交接文件,先讀這個
├── env.example                 ← .env 範本 (複製到 docker/.env 後填值)
├── sql/
│   ├── README.md               ← SQL 套用指引
│   └── 03_ai_tools_schema.sql  ← AI 用的 restaurants + ev_stations 表
└── scripts/
    ├── 01_apply_ai_schema.sh    ← 套 03_ai_tools_schema.sql (用 docker exec)
    ├── 02_load_csv_to_pg.sh     ← CSV → Postgres ETL (docker run, 不需本機 Python)
    └── 03_ingest_md_to_qdrant.sh ← MD → Qdrant 嵌入 (docker run)
```

## 為什麼只有一份 SQL?

- `dashboarddb` 跟 `dashboardmanagerdb` 兩個 DB 由 `docker/docker-compose-db.yaml` 透過 `POSTGRES_DB` env 自動建。
- Schema + demo 資料由 `docker/docker-compose-init.yaml` 跑 BE 的 cobra 命令 (`migrateDB` + `initDashboard`) **自動套**,讀的是 `db-sample-data/*.sql`(repo 上游就帶的)。
- **只有 AI 工具新增的 `restaurants` + `ev_stations` 兩張表是這次新加的**,所以 handoff/sql/ 只有那一份。

## 怎麼開始

**從 [HANDOFF.md](./HANDOFF.md) 第 5 章「完整部署步驟」開始**。簡短版:

```bash
# 1. clone + 設 .env
git clone https://github.com/frank931023/dashboard-26.git
cd dashboard-26
git checkout feature/ai-rag-route-panel
cp handoff/env.example docker/.env
# 編輯 docker/.env 填 Mapbox token / TWCC key / DB 密碼

# 2. 建 network + DB 層
docker network create --driver=bridge --subnet=192.168.129.0/24 \
    --gateway=192.168.129.1 br_dashboard_2026
docker compose -f docker/docker-compose-db.yaml up -d

# 3. 套既有 schema/demo 資料 (BE init container 自動跑)
docker compose -f docker/docker-compose-init.yaml up

# 4. 套 AI 工具 schema + 灌資料
bash handoff/scripts/01_apply_ai_schema.sh
bash handoff/scripts/02_load_csv_to_pg.sh
bash handoff/scripts/03_ingest_md_to_qdrant.sh

# 5. 拉應用層
docker compose -f docker/docker-compose.yaml up -d

# → 開 http://localhost:8080
```

Repo 根目錄的 `csv_files/` 和 `md_files/` 是 ETL 腳本要讀的原始資料,**不要刪**。

## Windows 提示

腳本是 bash,Windows 用戶請用 **Git Bash** 跑(裝 Git for Windows 就有)。PowerShell 跑不了。
