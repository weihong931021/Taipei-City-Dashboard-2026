# power_by_district — 永續環境組件包

**接手者請看 [MIGRATION.md](./MIGRATION.md) 開始整合。**

資料來源：
- 用電量：[政府資料開放平臺 dataset/14135](https://data.gov.tw/dataset/14135) — 「台灣電力公司鄉鎮市(郵遞區)別用電統計資料」
- 碳排放：台北市政府環保局 — 「臺北市溫室氣體排放統計」

---

## 檔案地圖

| 檔案 | 用途 | 跑在哪個 DB |
|------|------|------|
| **MIGRATION.md** | 整合操作手冊 | — |
| **MIGRATION.sql** | 註冊組件 + 儀表板（idempotent）| postgres-manager |
| **uninstall.sql** | 完整卸載 | postgres-manager |
| **load_csv.sql** | 用電量 ETL | postgres-data |
| **load_emission.sql** | 碳排放 ETL | postgres-data |
| job_config.json | Airflow DAG 設定（選用） | — |
| power_by_district.py | Airflow ETL 腳本（選用） | — |
| __init__.py | Python package marker | — |

---

## 快速整合（給趕時間的人）

```bash
# 1. 複製本資料夾到目標專案
cp -r power_by_district/ <目標>/Taipei-City-Dashboard-DE/dags/proj_city_dashboard/

# 2. 載入用電 CSV (12 年)
for y in 104 105 106 107 108 109 110 111 112 113 114 115; do
  docker cp dist_kwh_${y}.csv postgres-data:/tmp/
done
docker cp load_csv.sql postgres-data:/tmp/
docker exec postgres-data psql -U postgres -d dashboard -f /tmp/load_csv.sql

# 3. 載入碳排 CSV (要先轉 UTF-8)
docker cp taipei_emission.csv postgres-data:/tmp/
docker cp load_emission.sql postgres-data:/tmp/
docker exec postgres-data psql -U postgres -d dashboard -f /tmp/load_emission.sql

# 4. 註冊組件
docker cp MIGRATION.sql postgres-manager:/tmp/
docker exec postgres-manager psql -U postgres -d dashboardmanager -f /tmp/MIGRATION.sql

# 5. 完成 — 開瀏覽器看「永續環境」儀表板
```

完整步驟、技術細節、故障排除請看 [MIGRATION.md](./MIGRATION.md)。
