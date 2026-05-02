# 🎨 FE 打包清單 — 永續環境 Dashboard

打包目標：把 `Taipei-City-Dashboard-FE/` 底下 weihong 動過的所有檔案壓成一包，給隊友 cherry-pick。

---

## A. 打包方式

### A1. 推薦：GitHub Download ZIP（傳整包 repo）

前提：所有改動都已 commit + push 到 `origin/develop`（個人 fork：`weihong931021/Taipei-City-Dashboard-2026`）。

1. 寄件方確認 push：

   ```bash
   git status                         # 應該 clean
   git log origin/develop..HEAD       # 應該空（或已 push）
   git push origin develop
   ```

2. 收件方下載：
   - GitHub 開 [weihong931021/Taipei-City-Dashboard-2026](https://github.com/weihong931021/Taipei-City-Dashboard-2026)
   - Code → Download ZIP（會抓 develop branch tip 整個 repo）
   - 或用 git：`git clone -b develop --depth 1 https://github.com/weihong931021/Taipei-City-Dashboard-2026.git`

3. ZIP 內含的關鍵檔（自動帶到）：
   - 全部 FE 改動 + 8 個新 GeoJSON（含 14 MB `street_tree_tpe.geojson`）
   - 全部 `handoff_package/`（81 MB，含 13 個 power_by_district CSV）

> GitHub 單檔上限 100 MB（本 repo 最大檔 14 MB，沒問題）；整個 repo Download ZIP 沒大小限制。

### A2. Fallback：只打 FE 改動的小包（無法用 GitHub 時）

```bash
# 寄件方在 repo root
tar -czf fe_handoff.tar.gz -T handoff_package/FE_FILES.list
# 或
zip -r fe_handoff.zip $(cat handoff_package/FE_FILES.list)
```

清單檔 `handoff_package/FE_FILES.list` 每行一個相對路徑（28 個檔，~15 MB 含 geojson）。

> 此模式不含 `handoff_package/` 本身（DB 部分要另外打），通常只在「隊友只要 FE 增量」時用。

---

## B. 檔案清單分類

### B1. 已 commit（在 5298443 / 525e866 / 09ae4e2 三個 commit 內）

#### 圖示資產（不能漏，BarChart icon 跟 mapbox symbol 都靠這 3 張）

```
Taipei-City-Dashboard-FE/public/images/map/ev_charging.png       (587 B)
Taipei-City-Dashboard-FE/public/images/map/ev_motor.png          (2.2 KB)
Taipei-City-Dashboard-FE/public/images/map/restaurant.png        (489 B)
Taipei-City-Dashboard-FE/src/dashboardComponent/assets/map/ev_charging.png
Taipei-City-Dashboard-FE/src/dashboardComponent/assets/map/ev_motor.png
Taipei-City-Dashboard-FE/src/dashboardComponent/assets/map/restaurant.png
```

> 為什麼有兩份：`/public/images/map/` 是 mapbox runtime fetch 用，`/src/dashboardComponent/assets/map/` 是 Vue chart 元件 import 用。兩邊都要。

#### Map data（GeoJSON，runtime fetch）

```
Taipei-City-Dashboard-FE/public/mapData/env_restaurant_tpe.geojson           (168 KB)
Taipei-City-Dashboard-FE/public/mapData/env_restaurant_new_tpe.geojson       (204 KB)
Taipei-City-Dashboard-FE/public/mapData/ev_charging_car_tpe.geojson          ( 64 KB)
Taipei-City-Dashboard-FE/public/mapData/ev_charging_car_new_tpe.geojson      ( 36 KB)
Taipei-City-Dashboard-FE/public/mapData/ev_charging_motor_tpe.geojson        (200 KB)
Taipei-City-Dashboard-FE/public/mapData/ev_charging_motor_new_tpe.geojson    (132 KB)
Taipei-City-Dashboard-FE/public/mapData/green_park_type_tpe.geojson          (840 KB)
Taipei-City-Dashboard-FE/public/mapData/street_tree_tpe.geojson              ( 14 MB)  ← 最大
```

> `street_tree_tpe.geojson` 是 80k 點、14 MB，在 GitHub 單檔 100 MB 限制內，Download ZIP 會帶到（GitHub 對個檔最高 100 MB，整個 repo zip 沒大小限制）。

#### 修改的 Vue / JS / TS

```
Taipei-City-Dashboard-FE/src/assets/configs/mapbox/mapConfig.js                          (+73 行：ev_charging/ev_motor/restaurant icon 註冊)
Taipei-City-Dashboard-FE/src/components/dialogs/admin/AdminComponentSettings.vue         (+9 行：admin UI 補欄)
Taipei-City-Dashboard-FE/src/components/dialogs/admin/AdminComponentTemplate.vue         (+9 行：同上)
Taipei-City-Dashboard-FE/src/components/utilities/miscellaneous/ComponentTag.vue         (+1 行：tag wrap fix)
Taipei-City-Dashboard-FE/src/dashboardComponent/DashboardComponent.vue                   (+3 行)
Taipei-City-Dashboard-FE/src/dashboardComponent/components/BarChart.vue                  (+66 行：多 series 固定色)
Taipei-City-Dashboard-FE/src/dashboardComponent/components/EVTrendChart.vue              (+23 行：新組件)
Taipei-City-Dashboard-FE/src/dashboardComponent/components/MapLegend.vue                 (+44 行：自動讀 map_config 顯示 icon + dedup)
Taipei-City-Dashboard-FE/src/dashboardComponent/utilities/chartTypes.ts                  (+1 行)
Taipei-City-Dashboard-FE/src/dashboardComponent/utilities/cityManager.ts                 (+31 行)
Taipei-City-Dashboard-FE/src/store/contentStore.js                                       (+15 行)
Taipei-City-Dashboard-FE/src/store/mapStore.js                                           (+7 行：3D building 條件載入)
Taipei-City-Dashboard-FE/package-lock.json                                               (+270 行：npm 重 lock，無新 dep，可改用 npm install 重生)
```

### B2. Uncommitted（必納入,還沒 commit）

```diff
Taipei-City-Dashboard-FE/src/components/map/MapContainer.vue
  -  移除 `v-if="!authStore.user?.user_id"` 限制，savedLocations 不論登入都顯示
  -  diff: +8 / -10 行

Taipei-City-Dashboard-FE/src/dashboardComponent/components/EVTrendChart.vue
  -  汽油/電能 series 加 dashArray=5 虛線區分
  -  diff: +7 / -3 行

Taipei-City-Dashboard-FE/src/store/mapStore.js
  -  fetch geojson + loadImage 加 `if (!this.map) return` guard，避免 unmount 後 race condition
  -  loadImage 失敗從 throw 改 console.warn，避免一張 icon 失敗整個 map 炸掉
  -  hasImage check 防止重複 addImage
  -  diff: +12 / -2 行
```

---

## C. 套用步驟（給隊友）

1. 解壓到 repo root：`tar -xzf fe_handoff.tar.gz`（會直接覆蓋 `Taipei-City-Dashboard-FE/` 底下對應檔）
2. `cd Taipei-City-Dashboard-FE && npm install`（package-lock 有變動，但無新 dep）
3. `npm run dev` → 看 `localhost:5173` → 雙北儀表板 → 永續環境
4. 預期 5 個組件可正常渲染：充電樁地圖、環保餐廳、行道樹、綠地、用電/碳排

> 若 git 友善的隊友：見 `MERGE_SPEC.md` 的 cherry-pick 模式，避免覆蓋他們在同檔的改動。
