<!-- Developed by Taipei Urban Intelligence Center 2023-2024-->
<script setup>
import { ref, computed } from "vue";
import VueApexCharts from "vue3-apexcharts";

const props = defineProps([
	"chart_config",
	"activeChart",
	"series",
	"map_config",
	"map_filter",
	"map_filter_on",
]);

const emits = defineEmits([
	"filterByParam",
	"filterByLayer",
	"clearByParamFilter",
	"clearByLayerFilter",
	"fly"
]);

// 多 series（三維資料 e.g. 汽車/機車）時關掉 distributed，每個 series 用自己的 color
const isMultiSeries = (props.series?.length || 0) > 1;
const hasCategories = !!props.chart_config.categories;

const chartOptions = ref({
	chart: {
		offsetY: 15,
		stacked: true,
		toolbar: { show: false },
	},
	colors: [...props.chart_config.color],
	dataLabels: {
		offsetX: 20,
		textAnchor: "start",
	},
	grid: { show: false },
	legend: isMultiSeries
		? { show: true, position: "top", labels: { colors: "#a8a8a8" } }
		: { show: false },
	plotOptions: {
		bar: {
			borderRadius: 2,
			distributed: !isMultiSeries,
			horizontal: true,
			dataLabels: { hideOverflowingLabels: false },
		},
	},
	stroke: {
		colors: ["#282a2c"],
		show: true,
		width: 0,
	},
	tooltip: {
		custom: function ({ series, seriesIndex, dataPointIndex, w }) {
			const label = w.globals.labels[dataPointIndex];
			const seriesName = w.globals.seriesNames?.[seriesIndex] || "";
			const value = series[seriesIndex][dataPointIndex];
			return (
				'<div class="chart-tooltip">' +
				`<h6>${label}${seriesName ? ` - ${seriesName}` : ""}</h6>` +
				`<span>${value} ${props.chart_config.unit}</span>` +
				"</div>"
			);
		},
		followCursor: true,
	},
	xaxis: {
		axisBorder: { show: false },
		axisTicks: { show: false },
		labels: { show: false },
		type: "category",
		...(hasCategories && { categories: props.chart_config.categories }),
	},
	yaxis: {
		labels: {
			formatter: function (value) {
				return typeof value === "string" && value.length > 7
					? value.slice(0, 6) + "..."
					: value;
			},
		},
	},
});

const chartHeight = computed(() => {
	const itemCount = isMultiSeries
		? props.chart_config.categories?.length || props.series[0]?.data?.length || 0
		: props.series[0]?.data?.length || 0;
	return `${40 + itemCount * 30}`;
});

const selectedIndex = ref(null);

function handleDataSelection(_e, _chartContext, config) {
	if (!props.map_filter || !props.map_filter_on) {
		return;
	}
	if (
		`${config.dataPointIndex}-${config.seriesIndex}` !== selectedIndex.value
	) {
		// Supports filtering by xAxis
		if (props.map_filter.mode === "byParam") {
			emits(
				"filterByParam",
				props.map_filter,
				props.map_config,
				config.w.globals.labels[config.dataPointIndex],
				null
			);
		}
		// Supports filtering by xAxis
		else if (props.map_filter.mode === "byLayer") {
			emits(
				"filterByLayer",
				props.map_config,
				config.w.globals.labels[config.dataPointIndex]
			);
		}
		selectedIndex.value = `${config.dataPointIndex}-${config.seriesIndex}`;
	} else {
		if (props.map_filter.mode === "byParam") {
			emits("clearByParamFilter", props.map_config);
		} else if (props.map_filter.mode === "byLayer") {
			emits("clearByLayerFilter", props.map_config);
		}
		selectedIndex.value = null;
	}
}
</script>

<template>
  <div v-if="activeChart === 'BarChart'">
    <VueApexCharts
      width="100%"
      :height="chartHeight"
      type="bar"
      :options="chartOptions"
      :series="series"
      @data-point-selection="handleDataSelection"
    />
  </div>
</template>
