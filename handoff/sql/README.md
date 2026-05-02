# SQL 套用指引

這個 repo 的 schema/demo 資料是**自動套**的,你**幾乎不需要手動跑 psql**。

| Schema | 套用方式 | 動作 |
|---|---|---|
| `dashboardmanager DB` (帳號/權限) | `docker compose -f docker/docker-compose-init.yaml up` | 跑 BE 的 cobra 命令 `go run main.go migrateDB`,自動套 `db-sample-data/dashboardmanager-demo.sql` |
| `dashboard DB` (儀表板) | 同上 | 跑 BE 的 cobra 命令 `go run main.go initDashboard`,自動套 `db-sample-data/dashboard-demo.sql` |
| `restaurants` + `ev_stations` (本次新增) | `bash handoff/scripts/01_apply_ai_schema.sh` | 套 `03_ai_tools_schema.sql` 到 dashboard DB |

> Postgres image 用的是 `postgis/postgis:16-3.4-alpine`,DB 由 docker entrypoint 透過 `POSTGRES_DB` 環境變數自動建,**不需要手動 CREATE DATABASE**。PostGIS extension 也已自動啟用在預設 DB。

## 03_ai_tools_schema.sql 套用方式

最簡單(不需要本機裝 psql):

```bash
bash handoff/scripts/01_apply_ai_schema.sh
```

或手動:

```bash
# 從 host 透過 docker exec 跑
docker exec -i postgres-data psql -U postgres -d $DB_DASHBOARD_DBNAME < handoff/sql/03_ai_tools_schema.sql

# 或本機有 psql
PGPASSWORD=$DB_DASHBOARD_PASSWORD psql -h localhost -U postgres -d $DB_DASHBOARD_DBNAME \
  -f handoff/sql/03_ai_tools_schema.sql
```

## 注意

- `03_ai_tools_schema.sql` 含 `DROP TABLE IF EXISTS ... CASCADE`,**重複跑會清掉 restaurants / ev_stations 現有資料**。
- 套完 schema 後要跑 ETL 才有資料,見 `handoff/scripts/02_load_csv_to_pg.sh`。
