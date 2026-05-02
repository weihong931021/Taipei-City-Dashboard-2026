# SQL 套用順序

依編號逐一執行,**不要跳號**,因為後一個依賴前一個。

| 順序 | 檔名 | 跑在哪個 DB | 內容 |
|---|---|---|---|
| 1 | `00_create_databases.sql` | postgres (superuser) | `CREATE DATABASE dashboarddb`、`dashboardmanagerdb`,啟用 PostGIS |
| 2 | `01_dashboard.sql` | `dashboarddb` | 主 dashboard schema + demo 資料 (從原專案 `db-sample-data/dashboard-demo.sql` copy 過來,2.4 MB) |
| 3 | `02_dashboardmanager.sql` | `dashboardmanagerdb` | 帳號 / 權限 schema + demo 資料 (40 KB) |
| 4 | `03_ai_tools_schema.sql` | `dashboarddb` | AI 工具用的 `restaurants` + `ev_stations` 表 (**只有 schema,資料要跑 ETL**) |

## 套用範例

```bash
# 假設 postgres 在 localhost:5432, user=postgres, password 用 PGPASSWORD env

export PGPASSWORD=your_password
PG="psql -h localhost -U postgres"

$PG -f 00_create_databases.sql
$PG -d dashboarddb         -f 01_dashboard.sql
$PG -d dashboardmanagerdb  -f 02_dashboardmanager.sql
$PG -d dashboarddb         -f 03_ai_tools_schema.sql
```

> 步驟 4 之後,跑 `../scripts/2_load_csv_to_pg.sh` 把 `csv_files/` 灌進 `restaurants` + `ev_stations`。

## 注意

- `01_dashboard.sql` 是 pg_dump 出來的格式,內含 `DROP TABLE IF EXISTS ... CASCADE`,**重複跑會清掉現有資料**,小心。
- `03_ai_tools_schema.sql` 也有 `DROP TABLE IF EXISTS`,跑第二次會清空 restaurants / ev_stations。
- PostGIS extension 必須先安裝在 postgres 伺服器上 (Docker 用 `postgis/postgis` image 即可)。
