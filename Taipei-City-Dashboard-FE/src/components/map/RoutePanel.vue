<script setup>
// Combined route + instructions panel (single source of truth for both
// "路徑" inputs and "行程" turn-by-turn). One fixed-size card with an
// internal scrollbar; collapse handle on the right edge.
//
// Replaces @mapbox/mapbox-gl-directions UI entirely. Reads / writes
// mapStore.aiRoute.

import { computed } from "vue";
import { useMapStore } from "../../store/mapStore";

const mapStore = useMapStore();
const route = computed(() => mapStore.aiRoute);

// Per-leg colours — must match mapStore._routeLegColors() so the chips in the
// 行程 section line up with the line colours on the map.
const LEG_COLORS = ["#1e88e5", "#43a047", "#fb8c00", "#8e24aa", "#e53935", "#3949ab", "#00897b"];

// Build "A → 1", "1 → 2", "2 → B" labels for each leg using stop badges.
const legLabels = computed(() => {
	const r = route.value;
	const stops = [
		r.origin ? "A" : null,
		...(r.waypoints || []).map((_, i) => String(i + 1)),
		r.destination ? "B" : null,
	].filter(Boolean);
	const labels = [];
	for (let i = 0; i < stops.length - 1; i++) {
		labels.push(`${stops[i]} → ${stops[i + 1]}`);
	}
	return labels;
});

// Click "+ 新增停靠點" then on the map. mapStore.pickingWaypoint is the flag
// that addPopup() reads to suppress the simultaneous popup-on-click handler.
function startPickingWaypoint() {
	if (!mapStore.map || mapStore.pickingWaypoint) return;
	mapStore.pickingWaypoint = true;
	mapStore.map.getCanvas().style.cursor = "crosshair";
	mapStore.map.once("click", (e) => {
		mapStore.map.getCanvas().style.cursor = "";
		mapStore.pickingWaypoint = false;
		mapStore.addRouteWaypoint([e.lngLat.lng, e.lngLat.lat]);
	});
}

function cancelPicking() {
	if (!mapStore.pickingWaypoint) return;
	mapStore.pickingWaypoint = false;
	if (mapStore.map) mapStore.map.getCanvas().style.cursor = "";
}

function removeWaypoint(i) {
	mapStore.removeRouteWaypoint(i);
}

function setMode(mode) {
	mapStore.setRouteMode(mode);
}

function togglePanel() {
	mapStore.routePanelCollapsed = !mapStore.routePanelCollapsed;
}

function formatStop(p, fallback) {
	if (!p) return fallback;
	if (p.label && p.label !== "起點" && p.label !== "終點") return p.label;
	return `${p.lng.toFixed(5)}, ${p.lat.toFixed(5)}`;
}

function fmtDistance(m) {
	if (m == null) return "";
	if (m >= 1000) return `${(m / 1000).toFixed(2)} km`;
	return `${Math.round(m)} m`;
}
</script>

<template>
  <div
    v-if="mapStore.routeUiVisible"
    class="rpanel"
    :class="{ collapsed: mapStore.routePanelCollapsed }"
  >
    <!-- Collapsed: thin handle pinned to the left edge of the map. -->
    <button
      v-if="mapStore.routePanelCollapsed"
      class="rpanel__handle"
      title="展開路徑"
      @click="togglePanel"
    >
      ▶
    </button>

    <template v-else>
      <!-- Sticky header: title + collapse button -->
      <div class="rpanel__head">
        <span class="rpanel__title">路徑規劃</span>
        <button
          class="rpanel__collapse"
          title="收起"
          @click="togglePanel"
        >
          ◀
        </button>
      </div>

      <!-- Single scrollable body holds both 路徑 and 行程 sections. -->
      <div class="rpanel__scroll scrollbar-custom">
        <!-- ─────────── 路徑 ─────────── -->
        <section class="rpanel__section">
          <div class="rpanel__section-title">路徑</div>

          <ol class="stop-list">
            <li class="stop-row">
              <span class="badge badge--a">A</span>
              <span class="stop-text">{{ formatStop(route.origin, "起點 (尚未設定)") }}</span>
            </li>

            <li
              v-for="(w, i) in route.waypoints"
              :key="i"
              class="stop-row"
            >
              <span class="badge badge--wp">{{ i + 1 }}</span>
              <span class="stop-text">{{ formatStop(w, `停靠點 ${i + 1}`) }}</span>
              <button
                class="row-btn"
                title="移除停靠點"
                @click="removeWaypoint(i)"
              >
                −
              </button>
            </li>

            <li class="stop-row stop-row--add">
              <button
                class="add-wp"
                :class="{ active: mapStore.pickingWaypoint }"
                @click="mapStore.pickingWaypoint ? cancelPicking() : startPickingWaypoint()"
              >
                <span v-if="!mapStore.pickingWaypoint">+ 新增停靠點</span>
                <span v-else>請點地圖選位置 (再點取消)</span>
              </button>
            </li>

            <li class="stop-row">
              <span class="badge badge--b">B</span>
              <span class="stop-text">{{ formatStop(route.destination, "終點 (尚未設定)") }}</span>
            </li>
          </ol>

          <div class="modes">
            <button
              v-for="m in ['driving', 'walking', 'cycling']"
              :key="m"
              :class="{ active: route.mode === m }"
              :disabled="mapStore.aiRouteLoading"
              @click="setMode(m)"
            >
              {{ m === "driving" ? "開車" : m === "walking" ? "走路" : "騎車" }}
            </button>
          </div>

          <div
            v-if="mapStore.aiRouteLoading"
            class="loading"
          >
            重新計算中…
          </div>
        </section>

        <!-- ─────────── 行程 ─────────── -->
        <section
          v-if="route.legs && route.legs.length"
          class="rpanel__section rpanel__section--legs"
        >
          <div class="rpanel__section-title">
            行程
            <span class="section-summary">
              {{ route.totalDurationMin }} 分鐘 · {{ route.totalDistanceKm }} km
            </span>
          </div>

          <div
            v-for="(leg, i) in route.legs"
            :key="i"
            class="leg"
          >
            <div class="leg__head">
              <span
                class="leg__chip"
                :style="{ background: LEG_COLORS[i % LEG_COLORS.length] }"
              >
                {{ legLabels[i] || `第 ${i + 1} 段` }}
              </span>
              <span class="leg__meta">
                {{ leg.duration_min }} 分鐘 · {{ leg.distance_km }} km
              </span>
            </div>
            <ol class="leg__steps">
              <li
                v-for="(s, j) in leg.steps"
                :key="j"
              >
                <div class="step-instr">{{ s.instruction || s.name || "(無描述)" }}</div>
                <div
                  v-if="s.distance_m"
                  class="step-dist"
                >
                  {{ fmtDistance(s.distance_m) }}
                </div>
              </li>
            </ol>
          </div>
        </section>
      </div>
    </template>
  </div>
</template>

<style lang="scss" scoped>
.rpanel {
	position: absolute;
	top: 12px;
	left: 12px;
	z-index: 3;
	width: 340px;
	height: calc(100vh - 120px);
	max-height: 720px;
	background: rgba(20, 20, 22, 0.95);
	color: #fff;
	border: 1px solid rgba(255, 255, 255, 0.12);
	border-radius: 10px;
	box-shadow: 0 4px 16px rgba(0, 0, 0, 0.5);
	font-size: 13px;
	display: flex;
	flex-direction: column;
	overflow: hidden;
	transition: width 0.2s ease;

	&.collapsed {
		width: 28px;
		height: 80px;
		background: rgba(20, 20, 22, 0.85);
	}

	&__handle {
		width: 100%;
		height: 100%;
		background: transparent;
		border: none;
		color: #fff;
		cursor: pointer;
		font-size: 14px;

		&:hover {
			background: rgba(255, 255, 255, 0.05);
		}
	}

	&__head {
		display: flex;
		align-items: center;
		justify-content: space-between;
		padding: 12px 14px;
		border-bottom: 1px solid rgba(255, 255, 255, 0.08);
		flex-shrink: 0;
	}

	&__title {
		font-weight: 700;
		font-size: 14px;
	}

	&__collapse {
		width: 24px;
		height: 24px;
		border: none;
		border-radius: 4px;
		background: rgba(255, 255, 255, 0.08);
		color: #fff;
		cursor: pointer;

		&:hover {
			background: rgba(255, 255, 255, 0.18);
		}
	}

	&__scroll {
		flex: 1;
		min-height: 0;
		overflow-y: auto;
		padding: 12px 14px 14px;
	}

	&__section {
		& + & {
			margin-top: 14px;
			padding-top: 14px;
			border-top: 1px solid rgba(255, 255, 255, 0.08);
		}
	}

	&__section-title {
		font-weight: 700;
		font-size: 13px;
		margin-bottom: 8px;
		color: #fff;
		display: flex;
		align-items: baseline;
		gap: 8px;

		.section-summary {
			color: #aaa;
			font-size: 11px;
			font-weight: 400;
		}
	}
}

.scrollbar-custom {
	&::-webkit-scrollbar {
		width: 4px;
	}
	&::-webkit-scrollbar-track {
		background: transparent;
	}
	&::-webkit-scrollbar-thumb {
		background: rgba(255, 255, 255, 0.18);
		border-radius: 2px;
	}
	&::-webkit-scrollbar-thumb:hover {
		background: rgba(255, 255, 255, 0.35);
	}
}

/* ────── 路徑 (stop list + modes) ────── */
.stop-list {
	list-style: none;
	margin: 0 0 10px 0;
	padding: 0;
	display: flex;
	flex-direction: column;
	gap: 4px;
}

.stop-row {
	display: flex;
	align-items: center;
	gap: 8px;
	padding: 6px 8px;
	background: rgba(255, 255, 255, 0.05);
	border-radius: 6px;
	min-height: 32px;

	.stop-text {
		flex: 1;
		color: #ddd;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
		font-size: 12px;
	}

	&--add {
		padding: 0;
		background: transparent;
	}
}

.badge {
	display: inline-flex;
	align-items: center;
	justify-content: center;
	width: 22px;
	height: 22px;
	border-radius: 50%;
	font-weight: 700;
	font-size: 12px;
	color: #fff;
	flex-shrink: 0;

	&--a { background: #4ea1ff; }
	&--b { background: #ff7043; }
	&--wp { background: #9b6ad6; }
}

.row-btn {
	width: 22px;
	height: 22px;
	border: none;
	border-radius: 50%;
	background: rgba(255, 255, 255, 0.12);
	color: #fff;
	cursor: pointer;
	font-size: 14px;
	line-height: 1;

	&:hover {
		background: #c0392b;
	}
}

.add-wp {
	width: 100%;
	padding: 8px;
	border: 1px dashed rgba(255, 255, 255, 0.25);
	border-radius: 6px;
	background: transparent;
	color: #bbb;
	cursor: pointer;
	font-size: 12px;
	transition: background-color 0.15s, color 0.15s, border-color 0.15s;

	&:hover {
		background: rgba(255, 255, 255, 0.05);
		color: #fff;
		border-color: rgba(255, 255, 255, 0.45);
	}

	&.active {
		background: var(--color-highlight, #00b4d8);
		color: #fff;
		border-style: solid;
		border-color: var(--color-highlight, #00b4d8);
	}
}

.modes {
	display: grid;
	grid-template-columns: repeat(3, 1fr);
	gap: 4px;

	button {
		padding: 6px;
		background: rgba(255, 255, 255, 0.05);
		color: #ddd;
		border: none;
		border-radius: 6px;
		cursor: pointer;
		font-size: 12px;

		&:hover:not(:disabled) {
			background: rgba(255, 255, 255, 0.12);
		}

		&.active {
			background: var(--color-highlight, #00b4d8);
			color: #fff;
			font-weight: 600;
		}

		&:disabled {
			opacity: 0.5;
			cursor: not-allowed;
		}
	}
}

.loading {
	font-size: 11px;
	color: #aaa;
	text-align: center;
	padding-top: 6px;
}

/* ────── 行程 (legs + steps) ────── */
.leg {
	margin-bottom: 10px;
	font-size: 12px;

	&:last-child {
		margin-bottom: 0;
	}

	&__head {
		display: flex;
		align-items: center;
		gap: 8px;
		margin-bottom: 6px;
		flex-wrap: wrap;
	}

	&__chip {
		padding: 2px 8px;
		border-radius: 10px;
		font-size: 11px;
		font-weight: 600;
		color: #fff;
	}

	&__meta {
		color: #aaa;
		font-size: 11px;
	}

	&__steps {
		list-style: none;
		margin: 0;
		padding: 0 0 0 6px;
		border-left: 2px solid rgba(255, 255, 255, 0.15);

		li {
			padding: 4px 0 4px 8px;

			.step-instr {
				color: #eee;
				line-height: 1.35;
			}

			.step-dist {
				color: #888;
				font-size: 10.5px;
				margin-top: 2px;
			}
		}
	}
}

@media (max-width: 1000px) {
	.rpanel {
		width: calc(100% - 24px);
		max-width: 360px;
		height: 60vh;
	}
}
</style>
