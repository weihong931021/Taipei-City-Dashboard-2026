# 🤖 Claude Code Merge / Cherry-Pick 規格書

> 給隊友環境裡的 Claude Code（或人工）使用,把 weihong 的「永續環境 dashboard」改動套到隊友的 develop branch。

---

## 0. 前置假設

- 隊友 repo 在 `Taipei-City-Dashboard-2026` 的 develop 分支
- 起點 commit 不早於 `0f81d3b`（"修改: 調整行政區界資料串接邏輯 (#1222)"）
- Docker 兩個 postgres 容器已起、能連線
- 收到 `handoff_package/` 整個資料夾(含 81 MB 資料,主要是 power_by_district CSV + street_tree geojson)

如果隊友的 develop 比 `0f81d3b` 晚很多,先看 §6「衝突備案」。

---

## 1. 變更摘要（一句話）

新增雙北永續環境 dashboard,5 個組件:**EV 充電樁、環保餐廳、行道樹、綠地組成、用電 + 碳排**。
含 DB schema、ETL 結果（CSV / GeoJSON）、組件註冊 SQL、所有 FE 視覺元件。

涉及兩個層:

| 層 | 動了什麼 | 怎麼套用 |
|---|---|---|
| DB | 兩個 postgres、9 張新表、5 個 component、1 個 dashboard、若干 patch | 跑 `bash handoff_package/scripts/run_all.sh`,細節見 [DB_MIGRATION.md](DB_MIGRATION.md) |
| FE | 28 個檔(28 修改 + 6 新增 asset + 8 新增 geojson) | tar 解壓覆蓋 or cherry-pick,細節見 [FE_PACKAGE.md](FE_PACKAGE.md) |

---

## 2. 來源 commit 清單

按時間順序（舊 → 新）。Hash 來自 weihong 本機 develop branch:

| Hash | Subject | 主要 scope |
|---|---|---|
| `09ae4e2` | 新增: 臺北市電動車輛成長趨勢組件 (EVTrendChart) | FE only — 新檔 `EVTrendChart.vue` |
| `525e866` | feat: 永續環境 dashboard with EV / restaurant / green / power components | DB + FE 大塊主修改（92 檔） |
| `8c0758f` | docs(handoff): 加交棒文件 + 一鍵 setup 腳本 | docs 只 |
| `d6a08df` | fix(handoff): include run_all.sh (was caught by *.sh gitignore) | docs 只 |
| `5298443` | docs(handoff_package): 集中所有交棒檔案到單一資料夾 | docs 只(把零散 handoff/ 整理到 handoff_package/) |

加上 **未 commit** 的 working-tree 改動:

| 範圍 | 檔 | 行數 |
|---|---|---|
| FE | `src/components/map/MapContainer.vue` | +8 / -10 |
| FE | `src/dashboardComponent/components/EVTrendChart.vue` | +7 / -3 |
| FE | `src/store/mapStore.js` | +12 / -2 |
| DB | `hackathon/sql/02_charging_station_component.sql` + `handoff_package/sql/02_*` | +2 / -2(同步兩份) |
| DB | `hackathon/sql/06_restaurant_component.sql` + `handoff_package/sql/06_*` | +1 / -1(同步兩份) |

---

## 3. 套用模式選擇

### 模式 A：GitHub Download ZIP（推薦，本次採用）

適合：完整 sync,隊友沒在動同樣的檔、沒 in-flight PR。

寄件方:

```bash
# 確保 working-tree 7 檔已 commit + push 到自己的 fork
git status                  # 應 clean
git push origin develop
```

收件方:

1. 開 [weihong931021/Taipei-City-Dashboard-2026](https://github.com/weihong931021/Taipei-City-Dashboard-2026) → Code → Download ZIP
2. 解壓,檔案就位（含 81 MB `handoff_package/` + 14 MB `street_tree_tpe.geojson` 全部到位）
3. `bash handoff_package/scripts/run_all.sh`
4. `cd Taipei-City-Dashboard-FE && npm install && npm run dev`

> GitHub 對個別檔限 100 MB（本 repo 最大檔 14 MB，OK），整個 ZIP 沒大小限制。

### 模式 A'：tarball（無法用 GitHub 時）

```bash
# 寄件方
cd Taipei-City-Dashboard-2026
tar -czf weihong_handoff.tar.gz \
  handoff_package/ \
  -T handoff_package/FE_FILES.list

# 收件方
tar -xzf weihong_handoff.tar.gz
bash handoff_package/scripts/run_all.sh
cd Taipei-City-Dashboard-FE && npm install && npm run dev
```

### 模式 B：git cherry-pick(乾淨歷史,適合 PR 流程)

寄件方:

```bash
# 1. 把 working-tree 的 7 個 uncommitted 檔先 commit 起來
git add Taipei-City-Dashboard-FE/src/components/map/MapContainer.vue \
        Taipei-City-Dashboard-FE/src/dashboardComponent/components/EVTrendChart.vue \
        Taipei-City-Dashboard-FE/src/store/mapStore.js \
        hackathon/sql/02_charging_station_component.sql \
        hackathon/sql/06_restaurant_component.sql \
        handoff_package/sql/02_charging_station_component.sql \
        handoff_package/sql/06_restaurant_component.sql
git commit -m "fix: DistrictChart on EV/restaurant + map race-condition guards"

# 2. 推到隊友看得到的 branch
git push origin develop:weihong/sustainability-handoff
```

收件方:

```bash
git fetch origin
git log --oneline origin/weihong/sustainability-handoff -10   # 確認有 6 個 commit
git cherry-pick 09ae4e2 525e866 8c0758f d6a08df 5298443 <new-fix-hash>
# 衝突處理見 §6
bash handoff_package/scripts/run_all.sh
```

### 模式 C：format-patch(離線傳遞)

```bash
# 寄件
git format-patch 0f81d3b..HEAD --output-directory weihong-patches/
# 把 weihong-patches/ + handoff_package/data 兩份打包

# 收件
git am weihong-patches/*.patch
```

---

## 4. 套用順序(嚴格,三段式)

### 4.1 程式碼進來

走模式 A / B / C 任一

### 4.2 後端服務啟動

`docker compose up -d`,seed SQL 會在 init 階段自動載入(handoff_package/seeds/ 透過 docker-compose-init.yaml 掛 volume)。
如果 docker volume 已存在,seed 不會跑,需手動載入:

```bash
docker exec -i postgres-data psql -U postgres -d dashboard \
  < handoff_package/seeds/dashboard-demo.sql
docker exec -i postgres-manager psql -U postgres -d dashboardmanager \
  < handoff_package/seeds/dashboardmanager-demo.sql
```

### 4.3 跑 migration

```bash
bash handoff_package/scripts/run_all.sh
```

詳見 [DB_MIGRATION.md](DB_MIGRATION.md) §C。

### 4.4 前端

```bash
cd Taipei-City-Dashboard-FE
npm install   # package-lock 變動,但無新 dep
npm run dev
```

### 4.5 驗證

- HTTP `localhost:5173` 或 `localhost:8080` → 雙北儀表板 → 永續環境
- 5 個組件全部能渲染,地圖層 icon 正常顯示
- DB 驗證:
  ```bash
  docker exec postgres-manager psql -U postgres -d dashboardmanager \
    -c "SELECT id, components FROM dashboards WHERE id = 601;"
  # 預期 components 含 {501, 502, 701, 301, 302, ...}
  ```

---

## 5. 跨檔依賴(若 cherry-pick 部分檔,要一起帶)

| 改動主題 | 必須一起套的檔 |
|---|---|
| EV 充電樁地圖 | `mapConfig.js` (icon 註冊) + `mapStore.js` (loadImage 容錯) + `public/images/map/ev_*.png` + `public/mapData/ev_charging_*.geojson` + `sql/02_charging_station_component.sql` |
| BarChart 多 series 固定色 | `BarChart.vue`(支援 `colors` prop) + `02_*.sql`(`color` 陣列要傳 2 個) |
| MapLegend 自動 dedup | `MapLegend.vue` + `mapConfig.js`(icon 必須註冊) |
| 行道樹 + 綠地 | `09_green_component.sql` + `post_migration_patches.sql` (補 component_maps) + `green_park_type_tpe.geojson` + `street_tree_tpe.geojson` |
| 用電/碳排 | `power_by_district/MIGRATION.sql` + 12 個 `dist_kwh_*.csv` + `taipei_emission.csv` + `post_migration_patches.sql` (合併 dashboard 601) |

---

## 6. 衝突備案

### 6.1 component / dashboard id 撞號

新增佔用的 id:
- components: 301, 302, 501, 502, 701
- dashboards: 601

如果隊友的 `dashboardmanager` 已用了上述 id,改 SQL 內的數字(全文搜尋取代),三個檔會用到:
- `handoff_package/sql/02_charging_station_component.sql` (501, 601)
- `handoff_package/sql/05_power_usage_component.sql` (502)
- `handoff_package/sql/06_restaurant_component.sql` (701)
- `handoff_package/data/power_by_district/MIGRATION.sql` (301, 302)

改完同步在 `post_migration_patches.sql` 把 id 對應改掉。

### 6.2 同檔衝突(模式 B / C 才會碰到)

最容易衝突的檔:
- `Taipei-City-Dashboard-FE/src/store/mapStore.js`
- `Taipei-City-Dashboard-FE/src/store/contentStore.js`
- `Taipei-City-Dashboard-FE/src/dashboardComponent/components/BarChart.vue`

衝突處理原則:
1. 先看 commit subject 確認 weihong 的這段改了什麼
2. **保留** weihong 的改 + 隊友的改的 union(這幾個檔多半是各加各的功能,不會互踩)
3. 跑 `npm run dev`,確認沒 console error

### 6.3 seeds 已被改過

如果隊友的 `dashboard-demo.sql` / `dashboardmanager-demo.sql` 已有他們的修改,**不要直接覆蓋**。改用:

```bash
# 不覆蓋整個 seed,只跑 component 註冊
bash handoff_package/scripts/run_all.sh
```

註冊 SQL 都是 idempotent,可以在已有 seed 上 incremental 加。

---

## 7. 失敗排查 cheat sheet

| 症狀 | 原因 | 解法 |
|---|---|---|
| 地圖點開沒 icon | mapConfig.js 沒有對應 icon 註冊 / public/images/map/*.png 沒帶 | 檢查兩者都有 |
| BarChart 顏色亂跳 | `component_charts.color` 陣列長度跟 series 數對不上 | 02/06 SQL 的 color 陣列要跟 series 數一致 |
| 永續環境 dashboard 進不去 | dashboard 601 沒掛 group | 跑 `post_migration_patches.sql` §5 |
| street_tree 點看不到 | `street_tree_tpe.geojson` 沒擺到 `public/mapData/` | 檢查檔在 |
| 用電組件報 SQL error | `power_usage_by_district` 表空 | 跑 Step 1.5 / 1.6 載 CSV |
| Console: `Cannot read property 'addImage' of undefined` | 隊友環境沒套 mapStore.js 容錯 patch | 補套 working-tree 那筆 mapStore.js 改 |

---

## 8. 收尾

跑完一輪沒問題後,告知 weihong:
- 哪些 commit 已套上
- 是否有把 working-tree 那 7 個 uncommitted 檔吃進來
- 任何衝突解法是否需 weihong 確認

---

## Appendix：檔案位置速查

```
Taipei-City-Dashboard-2026/
├── handoff_package/                   ← 整包交付物
│   ├── README.md                      ← 原 readme(完整 setup)
│   ├── DB_MIGRATION.md                ← DB migration spec
│   ├── FE_PACKAGE.md                  ← FE 打包清單
│   ├── FE_FILES.list                  ← tar 用的 file list
│   ├── MERGE_SPEC.md                  ← 本檔
│   ├── scripts/
│   │   ├── run_all.sh                 ← 一鍵跑完所有 SQL
│   │   ├── post_migration_patches.sql
│   │   └── docker.env.example
│   ├── sql/                           ← 12 份 manager-side SQL
│   ├── seeds/                         ← docker init 用的兩份 dump
│   ├── data/
│   │   ├── hackathon/                 ← street_tree / green_park CSV
│   │   ├── hackathon_etl/             ← Python ETL(reference)
│   │   └── power_by_district/         ← 13 份用電/碳排 CSV + ETL
│   └── proposals/                     ← hackathon 提案文件(背景)
└── Taipei-City-Dashboard-FE/          ← FE 動到的檔(見 FE_PACKAGE.md)
```
