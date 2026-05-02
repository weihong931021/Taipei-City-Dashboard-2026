# 交接資料夾 (handoff/)

把專案交給下一位開發者所需的全部設定資料、SQL、Setup 腳本、規格文件。

## 內容

```
handoff/
├── HANDOFF.md                  ← 主要交接文件,先讀這個
├── env.example                 ← .env 範本 (複製到 docker/.env 後填值)
├── sql/
│   ├── README.md               ← SQL 套用順序
│   ├── 00_create_databases.sql
│   ├── 01_dashboard.sql        ← 既有 dashboard schema + demo 資料 (2.4 MB)
│   ├── 02_dashboardmanager.sql ← 帳號/權限 schema (40 KB)
│   └── 03_ai_tools_schema.sql  ← AI 用的 restaurants + ev_stations 表
└── scripts/
    ├── 1_setup_databases.sh    ← 建 DB + 套 schema
    ├── 2_load_csv_to_pg.sh     ← CSV → Postgres ETL (要 Mapbox token)
    └── 3_ingest_md_to_qdrant.sh ← MD → Qdrant embeddings (RAG)
```

## 怎麼開始

**從 [HANDOFF.md](./HANDOFF.md) 第 5 章「完整部署步驟」開始**。簡短版:

```bash
cp handoff/env.example docker/.env       # 填 Mapbox token 等
docker compose -f docker/docker-compose-db.yaml up -d   # 拉 Postgres / Qdrant
bash handoff/scripts/1_setup_databases.sh
bash handoff/scripts/2_load_csv_to_pg.sh
bash handoff/scripts/3_ingest_md_to_qdrant.sh
docker compose -f docker/docker-compose.yaml up -d      # 跑 BE + FE
```

Repo 根目錄的 `csv_files/` 和 `md_files/` 是腳本要讀的原始資料,**不要刪**。
