<!-- Developed for Taipei Codefest 2026 -->

<script setup>
import { ref, watch } from "vue";
import VueApexCharts from "vue3-apexcharts";

const props = defineProps(["chart_config", "activeChart", "series"]);

const cities = ["雙北", "臺北市", "新北市"];
const vehicleTypes = ["汽車", "機車"];
const selectedCity = ref("雙北");
const selectedType = ref("汽車");

const FUEL_META = {
	"汽油":     { label: "汽油",     color: "#F5AD4A", dash: 0 },
	"汽油/電能": { label: "油電混合", color: "#9DC56E", dash: 5 },
	"電能":     { label: "電能",     color: "#4CB495", dash: 0 },
};

const localSeries = ref([]);
const chartColors = ref([]);
const kpi = ref({ evCount: 0, evGrowth: 0, gasDecline: 0, evShare: 0 });

const chartOptions = ref({
	chart: {
		stacked: false,
		toolbar: { show: false },
	},
	dataLabels: { enabled: false },
	fill: {
		type: "gradient",
		gradient: { opacityFrom: 0.3, opacityTo: 0.02, shadeIntensity: 0.5 },
	},
	grid: { show: false },
	legend: {
		show: true,
		position: "bottom",
		fontSize: "12px",
	},
	markers: {
		hover: { size: 5 },
		size: 0,
		strokeWidth: 0,
	},
	stroke: {
		curve: "smooth",
		show: true,
		width: 2.5,
	},
	tooltip: {
		custom: function ({ series, seriesIndex, dataPointIndex, w }) {
			const d = w.config.series[seriesIndex].data[dataPointIndex];
			const label = typeof d.x === "string" ? d.x.slice(0, 7) : d.x;
			const idx = (series[seriesIndex][dataPointIndex] ?? 0).toFixed(1);
			const raw = d.raw != null ? Number(d.raw).toLocaleString() : "—";
			return (
				'<div class="chart-tooltip">' +
				"<h6>" + label + " - " + w.globals.seriesNames[seriesIndex] + "</h6>" +
				"<span>" + raw + " 輛（指數 " + idx + "）</span>" +
				"</div>"
			);
		},
	},
	xaxis: {
		axisBorder: { color: "#555", height: "0.8" },
		axisTicks: { show: false },
		crosshairs: { show: false },
		labels: { datetimeUTC: false },
		tooltip: { enabled: false },
		type: "datetime",
	},
	yaxis: {
		labels: { formatter: (val) => val.toFixed(0) },
	},
	annotations: {
		yaxis: [{ y: 100, borderColor: "#666", borderWidth: 1, strokeDashArray: 4 }],
	},
});

function computeKPI(rebuilt) {
	const ev  = rebuilt.find((s) => s.name === "電能");
	const gas = rebuilt.find((s) => s.name === "汽油");
	const hyb = rebuilt.find((s) => s.name === "油電混合");
	if (!ev || !ev.data.length) {
		kpi.value = { evCount: 0, evGrowth: 0, gasDecline: 0, evShare: 0 };
		return;
	}

	const lastEV   = ev.data[ev.data.length - 1]?.y ?? 0;
	const firstEV  = ev.data[0]?.y ?? 1;
	const lastGas  = gas?.data[gas.data.length - 1]?.y ?? 0;
	const firstGas = gas?.data[0]?.y ?? 1;
	const lastHyb  = hyb?.data[hyb.data.length - 1]?.y ?? 0;
	const total    = lastEV + lastGas + lastHyb;

	kpi.value = {
		evCount:    lastEV,
		evGrowth:   (lastEV / firstEV - 1) * 100,
		gasDecline: (1 - lastGas / firstGas) * 100,
		evShare:    total > 0 ? (lastEV / total) * 100 : 0,
	};
}

function rebuildSeries(series) {
	if (!series) return;

	const fuelOrder = ["汽油", "汽油/電能", "電能"];
	const rebuilt = [];
	const colors = [];
	const dashes = [];

	for (const fuel of fuelOrder) {
		const meta = FUEL_META[fuel];
		let merged = null;

		if (selectedCity.value === "雙北") {
			const tpe  = series.find((s) => s.name === `臺北市_${selectedType.value}_${fuel}`);
			const ntpe = series.find((s) => s.name === `新北市_${selectedType.value}_${fuel}`);
			if (tpe && ntpe) {
				const copy = JSON.parse(JSON.stringify(tpe));
				copy.data = copy.data.map((d, i) => {
					const other = ntpe.data[i];
					if (!d || !other || typeof d !== "object") return d;
					return { ...d, y: (d.y ?? 0) + (other.y ?? 0) };
				});
				merged = copy;
			} else {
				merged = tpe
					? JSON.parse(JSON.stringify(tpe))
					: ntpe ? JSON.parse(JSON.stringify(ntpe)) : null;
			}
		} else {
			const found = series.find((s) => s.name === `${selectedCity.value}_${selectedType.value}_${fuel}`);
			if (found) merged = JSON.parse(JSON.stringify(found));
		}

		if (!merged) continue;
		rebuilt.push({ ...merged, name: meta.label });
		colors.push(meta.color);
		dashes.push(meta.dash);
	}

	// Compute KPIs before normalization (raw values still in d.y)
	computeKPI(rebuilt);

	// Normalize to index (base=100). Skip series with tiny base (< 50 vehicles)
	// to avoid meaningless swings (e.g. 機車 油電混合: only 2 vehicles).
	const normalized = [];
	for (const s of rebuilt) {
		const base = s.data[0]?.y ?? 0;
		if (base < 50) continue;
		for (const d of s.data) {
			if (d && typeof d === "object") {
				d.raw = d.y;
				d.y = parseFloat(((d.raw / base) * 100).toFixed(1));
			}
		}
		normalized.push(s);
	}
	const finalColors = normalized.map((s) => colors[rebuilt.indexOf(s)]);
	const finalDashes = normalized.map((s) => dashes[rebuilt.indexOf(s)]);

	const allY = normalized.flatMap((s) =>
		s.data.map((d) => (d && typeof d === "object" ? d.y : 0))
	);
	const minY = Math.floor(Math.min(...allY) - 2);
	const maxY = Math.ceil(Math.max(...allY) + 2);

	localSeries.value = normalized;
	chartColors.value = finalColors;
	chartOptions.value = {
		...chartOptions.value,
		colors: finalColors,
		stroke: { ...chartOptions.value.stroke, dashArray: finalDashes },
		yaxis: { ...chartOptions.value.yaxis, min: minY, max: maxY },
	};
}

watch(
	[() => props.series, selectedCity, selectedType],
	([newSeries]) => rebuildSeries(newSeries),
	{ deep: true, immediate: true }
);
</script>

<template>
  <div
    v-if="activeChart === 'EVTrendChart'"
    class="ev-trend-root"
  >
    <!-- KPI row -->
    <div class="ev-kpi-row">
      <div class="ev-kpi">
        <span class="ev-kpi-label">電能車數量</span>
        <span class="ev-kpi-value">{{ kpi.evCount.toLocaleString() }} 輛</span>
      </div>
      <div class="ev-kpi-divider" />
      <div class="ev-kpi">
        <span class="ev-kpi-label">電能成長（自 2024/03）</span>
        <span class="ev-kpi-value ev-up">▲ {{ kpi.evGrowth.toFixed(1) }}%</span>
      </div>
      <div class="ev-kpi-divider" />
      <div class="ev-kpi">
        <span class="ev-kpi-label">汽油車減少</span>
        <span class="ev-kpi-value ev-down">▼ {{ kpi.gasDecline.toFixed(1) }}%</span>
      </div>
      <div class="ev-kpi-divider" />
      <div class="ev-kpi">
        <span class="ev-kpi-label">電能佔比</span>
        <span class="ev-kpi-value">{{ kpi.evShare.toFixed(1) }}%</span>
      </div>
    </div>

    <!-- Controls row -->
    <div class="ev-controls">
      <div class="ev-type-toggle">
        <button
          v-for="type in vehicleTypes"
          :key="type"
          :class="['ev-trend-btn', { active: selectedType === type }]"
          @click="selectedType = type"
        >
          {{ type }}
        </button>
      </div>
    </div>

    <VueApexCharts
      width="100%"
      height="175px"
      type="area"
      :options="chartOptions"
      :series="localSeries"
    />
  </div>
</template>

<style scoped>
/* KPI */
.ev-kpi-row {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 6px 2px 8px;
  border-bottom: 1px solid var(--color-border, #333);
  margin-bottom: 6px;
}

.ev-kpi {
  display: flex;
  flex-direction: column;
  flex: 1;
  min-width: 0;
}

.ev-kpi-label {
  font-size: 0.62rem;
  color: var(--color-complement-text, #aaa);
  white-space: nowrap;
}

.ev-kpi-value {
  font-size: 0.88rem;
  font-weight: 600;
  color: var(--color-text, #fff);
  white-space: nowrap;
}

.ev-up   { color: #4CB495; }
.ev-down { color: #F5AD4A; }

.ev-kpi-divider {
  width: 1px;
  height: 28px;
  background: var(--color-border, #333);
  flex-shrink: 0;
}

/* root 不設 position: relative — 讓 .ev-controls 的 containing block 落到外層
   .dashboardcomponent (那個 position: relative 的 card)，這樣才能浮到城市下拉的同一排 */
.ev-trend-root {
  position: static;
}

/* Controls — 浮到 dashboard 卡片右上角，跟「雙北 ▼」同一排 */
.ev-controls {
  position: absolute;
  top: 4.4rem;
  right: 1rem;
  display: flex;
  align-items: center;
  margin: 0;
  z-index: 10;
}

/* Matches DashboardComponent .selectBtn; global select{} handles border/radius/padding */
.selectBtn {
  background-color: var(--color-component-background, #1a1a1a);
}

.ev-type-toggle {
  display: flex;
  gap: 4px;
}

.ev-trend-btn {
  background: transparent;
  border: 1px solid var(--color-border, #555);
  border-radius: 4px;
  color: var(--color-complement-text, #aaa);
  cursor: pointer;
  font-size: 0.75rem;
  padding: 2px 12px;
  transition: background 0.15s, color 0.15s, border-color 0.15s;
}

.ev-trend-btn.active {
  background: var(--color-highlight, #333);
  border-color: var(--color-complement-text, #aaa);
  color: #fff;
}
</style>
