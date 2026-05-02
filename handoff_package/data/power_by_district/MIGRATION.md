# 永續環境組件整合包 (Migration Package)

> **版本**：1.0
> **作者**：box755
> **建立日期**：2026-05-02
> **資料夾**：`Taipei-City-Dashboard-DE/dags/proj_city_dashboard/power_by_district/`

---

## 📦 內容物

本整合包提供 **2 個組件 + 1 個新儀表板**，圍繞「**永續環境 × 電動車**」主題：

| 組件 | 內容 | 圖型 |
|------|------|------|
| **雙北各行政區用電統計** | 2015-2025 雙北民生用電歷年總量 + 成長率 | ColumnLineChart 雙軸 |
| **台北市歷年碳排部門結構** | 2015-2024 台北 6 部門碳排放堆疊 | ColumnChart + BarPercentChart |

新儀表板：**永續環境** (`metrotaipei_sustainability`)

---

## 📊 資料來源

| Dataset | 來源 | 用途 |
|---------|------|------|
| `dist_kwh_*.csv` (104-115 共 12 年) | 政府資料開放平臺 [dataset/14135](https://data.gov.tw/dataset/14135) — 「台灣電力公司鄉鎮市(郵遞區)別用電統計資料」 | 用電組件 |
| `taipei_emission.csv` | 台北市政府環保局 — 「臺北市溫室氣體排放統計」 | 碳排組件 |

---

## 📁 檔案清單

```
power_by_district/
├── MIGRATION.md                         ← 本檔（操作說明）
├── MIGRATION.sql                        ← 一鍵註冊組件（postgres-manager）
├── load_csv.sql                         ← 用電 ETL（postgres-data）
├── load_emission.sql                    ← 碳排 ETL（postgres-data）
├── uninstall.sql                        ← 完整卸載腳本
│
├── job_config.json                      ← Airflow DAG 設定（選用）
├── power_by_district.py                 ← Airflow ETL 腳本（選用）
├── __init__.py                          ← Python package marker
└── README.md                            ← Dev 用備忘
```

---

## 🚀 整合步驟（給接手者）

### 前置條件

- 兩個 PostgreSQL DB 已運作：
  - `postgres-data`（dashboard 資料庫）
  - `postgres-manager`（dashboardmanager 設定庫）
- 已可使用 `docker exec postgres-data psql ...` 連線
- 你解開本壓縮包後，13 份 CSV 已內建在 **`datasets/`** 資料夾內

### Step 1：載入用電量資料（postgres-data）

```bash
# 1.1 把 12 份用電 CSV 複製進容器（從 datasets/ 內）
cd power_by_district
for y in 104 105 106 107 108 109 110 111 112 113 114 115; do
  docker cp datasets/dist_kwh_${y}.csv postgres-data:/tmp/dist_kwh_${y}.csv
done

# 1.2 執行 ETL
docker cp load_csv.sql postgres-data:/tmp/
docker exec postgres-data psql -U postgres -d dashboard -f /tmp/load_csv.sql
```

**預期結果**：
```
total_rows | 70000+ rows
years_count | 12 (2015-2026)
districts | 41 (台北 12 + 新北 29)
```

### Step 2：載入碳排資料（postgres-data）

> ✅ `datasets/taipei_emission.csv` **已預先轉好 UTF-8 編碼**，可直接使用。
> （原始來源是 BIG5/cp950 編碼）

```bash
docker cp datasets/taipei_emission.csv postgres-data:/tmp/taipei_emission.csv
docker cp load_emission.sql postgres-data:/tmp/
docker exec postgres-data psql -U postgres -d dashboard -f /tmp/load_emission.sql
```

**預期結果**：20 rows (2005-2024)

### Step 3：註冊組件（postgres-manager）

```bash
docker cp MIGRATION.sql postgres-manager:/tmp/
docker exec postgres-manager psql -U postgres -d dashboardmanager -f /tmp/MIGRATION.sql
```

**MIGRATION.sql 是 idempotent 的** — 重跑會先清掉舊版再建立新版，不會重複插入。

### Step 4：驗證

```bash
# 應該看到「永續環境」儀表板含 2 個組件
docker exec postgres-manager psql -U postgres -d dashboardmanager -c "
  SELECT id, index, name, components FROM dashboards WHERE index = 'metrotaipei_sustainability';
"
```

打開前端，左側選單 → 雙北 → 應該出現「**永續環境**」儀表板（icon: 綠葉 `eco`）。

---

## ⚙️ 技術實作要點

### 用電 CSV 格式差異
- **舊版（104-111）**：9 欄、欄名「用電種類」、千分位 `"59,628"`、類別後有全形空白
- **新版（112-115）**：8 欄、欄名「項目」、純數字
- ETL 用兩個 staging table 分別處理後 UNION

### 行政區範圍篩選
- 臺北市：郵遞區號 100-116（12 區）
- 新北市：207、208、220-253（29 區，排除基隆 200-206、連江 209-212）
- ETL 自動為新北行政區補「區」字（CSV 內如「板橋」→「板橋區」）

### 個資遮罩處理
- `*` / `**` / `***` (半形) → NULL
- `＊` (全形，僅舊版用) → NULL

### 城市切換
- `city='taipei'` → 純台北 12 區資料
- `city='metrotaipei'` → 雙北 41 區資料
- 兩個城市的 query_charts 各為一筆，前端依使用者切換

### 地圖層
- 重用既有 `public/mapData/metrotaipei_town.geojson`（NLSC 行政區界，已內建專案）
- `power_by_district` 使用 `fill-extrusion` 3D 立體柱（高度 = 用電量）
- Cross-filter: `map_filter.byParam.xParam = "TNAME"`

---

## ⚠️ 已知限制

1. **2026 年資料不完整**：只有 1-3 月，圖表 SQL 已 `WHERE year BETWEEN 2015 AND 2025` 排除
2. **碳排組件僅台北**：原始資料只統計台北市，雙北 mode 顯示同一份內容（已加註）
3. **無新北獨立 city**：專案前端僅支援 `taipei`/`metrotaipei` 兩個 city enum
4. **Mapbox token 需要**：3D fill-extrusion 需要 `mapbox/dark-v11` 或同級 style 的 access

---

## 🔄 卸載

如要完整移除本整合包：

```bash
docker cp uninstall.sql postgres-manager:/tmp/
docker exec postgres-manager psql -U postgres -d dashboardmanager -f /tmp/uninstall.sql

# 同時可選擇刪除 data table:
docker exec postgres-data psql -U postgres -d dashboard -c "
  DROP TABLE IF EXISTS power_by_district;
  DROP TABLE IF EXISTS taipei_emission;
"
```

---

## 📞 問題回報

若整合過程遇到問題，可檢查：

| 問題 | 可能原因 |
|------|---------|
| 後端 API 回傳空 | postgres-data 表還沒建好 → 重跑 Step 1-2 |
| 前端看不到組件 | dashboards 沒掛入 component → 重跑 Step 3 |
| 中文亂碼 | `psql -f` 透過 stdin pipe 編碼遺失 → 用 `docker cp` 進容器後用容器內 `psql -f` |
| Choropleth 配色錯亂 | 行政區名稱對不上 GeoJSON 的 `TNAME` → 檢查 `town` 欄位是否有「區」字 |
