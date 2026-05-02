// Pinia store for the new AI Assistant (CoT chatbot + RAG + spatial tools).
// Talks to BE /ai/chat/twai with all tool schemas attached.

import { defineStore } from "pinia";
import { ref } from "vue";
import http from "../router/axios";
import { useMapStore } from "./mapStore";

const TOOL_DEFS = [
	{
		type: "function",
		function: {
			name: "search_documents",
			description:
				"從台北/新北市永續政策、環保餐廳、循環經濟、補助、旅遊等 markdown 知識庫做語意搜尋。回傳 top-K 段落含來源引用。任何查事實、政策、報告類問題務必先用此工具。",
			parameters: {
				type: "object",
				properties: {
					query: { type: "string", description: "搜尋語句" },
					top_k: { type: "integer", default: 5 },
					min_score: { type: "number", default: 0.7 },
				},
				required: ["query"],
			},
		},
	},
	{
		type: "function",
		function: {
			name: "resolve_location",
			description:
				"把地點名稱/地址轉成經緯度。先查內部 POI 資料庫(餐廳/充電站)，找不到再用 Mapbox geocoding。",
			parameters: {
				type: "object",
				properties: {
					name: { type: "string", description: "地點名稱或完整地址" },
				},
				required: ["name"],
			},
		},
	},
	{
		type: "function",
		function: {
			name: "search_nearby_pois",
			description:
				"在指定座標附近搜尋環保餐廳/電動車充電站/換電站。category 必須是 restaurant | charging_station | swap_station 之一。",
			parameters: {
				type: "object",
				properties: {
					lat: { type: "number" },
					lng: { type: "number" },
					category: {
						type: "string",
						enum: ["restaurant", "charging_station", "swap_station"],
					},
					vehicle_type: {
						type: "string",
						enum: ["car", "scooter"],
						description: "充電站可選: car=汽車, scooter=機車",
					},
					radius_m: { type: "integer", default: 1500 },
					limit: { type: "integer", default: 10 },
				},
				required: ["lat", "lng", "category"],
			},
		},
	},
	{
		type: "function",
		function: {
			name: "compute_route",
			description:
				"用 Mapbox 算路徑,回傳 GeoJSON geometry + 距離 + 時間。" +
				"如有中途停靠點,放在 waypoints 陣列(順序=拜訪順序),Mapbox 會經過每個點規劃。",
			parameters: {
				type: "object",
				properties: {
					origin_lat: { type: "number" },
					origin_lng: { type: "number" },
					dest_lat: { type: "number" },
					dest_lng: { type: "number" },
					mode: {
						type: "string",
						enum: ["walking", "driving", "cycling"],
						default: "driving",
					},
					waypoints: {
						type: "array",
						description:
							"中途停靠點(可選)。每個元素是 {lat, lng},順序=要拜訪的順序。" +
							"使用前每個地點都需先呼叫 resolve_location 取得座標。" +
							"若使用者沒提到停靠點就省略此欄位。",
						items: {
							type: "object",
							properties: {
								lat: { type: "number" },
								lng: { type: "number" },
							},
							required: ["lat", "lng"],
						},
					},
				},
				required: ["origin_lat", "origin_lng", "dest_lat", "dest_lng"],
			},
		},
	},
	{
		type: "function",
		function: {
			name: "compute_carbon_emission",
			description:
				"算一段旅程的 CO2 碳排放量(g)。給距離 (km) + 交通工具,回傳總克數+來源係數。" +
				"資料來自 csv_files/ 的機車與大客車排碳係數表 + EPA 小客車典型值。" +
				"模式可選: walking, cycling, scooter, driving (=car), bus, bus_city, bus_highway, mrt, taxi。",
			parameters: {
				type: "object",
				properties: {
					distance_km: { type: "number", description: "旅程距離 (公里)" },
					mode: {
						type: "string",
						enum: ["walking", "cycling", "scooter", "driving", "car", "bus", "bus_city", "bus_highway", "mrt", "taxi"],
					},
					passengers: { type: "integer", description: "公車/捷運可填乘客數計算每人分攤", default: 1 },
				},
				required: ["distance_km", "mode"],
			},
		},
	},
];

const SYSTEM_PROMPT = `你是台北/新北的城市生活助手,只做兩件事:

【功能 1 - 日常知識問答 (RAG)】
觸發條件:使用者問環保政策、補助、循環經濟、環保餐廳、永續報告、垃圾分類、家電汰換補助等知識性問題。
做法:
- 一定先呼叫 search_documents 查文件
- 用查到的內容回答,結尾加 [來源: 檔名]
- 沒查到就老實說「知識庫沒有相關資料」,不要編造

【功能 2 - 路線規劃 (CoT 強制澄清式)】
觸發條件:使用者問「從 A 到 B」「帶我去」「附近的 X」「最近的充電站」「想吃 X 餐廳」等路線/找地點問題。

# 重要規則 — 一定要做 CoT 反問

只要是路線/找地點請求,**第一回合不要直接呼叫工具**,必須用反問 JSON 蒐集資訊。
依下列順序檢查使用者已知 vs. 未知,缺什麼就問什麼,問**至少 2 次,最多 3 次**:

  Slot 1 - 起點 (origin): 沒明確說就反問。
  Slot 2 - 交通方式 (mode): 即使使用者沒問,也反問一次 (除非他主動講了)。
  Slot 3 - 細節確認 (optional): 如果還有歧義 (例如「附近的餐廳」沒說範圍 / 多個同名地點要選哪個 / 是否要繞停靠點),
          再問一次。沒歧義就跳過此題直接執行工具。

反問**必須只有一段純 JSON**,不要任何前後文字、不要 markdown code block、不要 \`\`\`:
{"type":"clarify","question":"請問你的出發地是哪裡?","quick_replies":["我目前位置","台北車站","台北101"]}

quick_replies 給 2-3 個合理選項。使用者也可以**自己打字**回覆,不一定要點按鈕,所以選項不是窮舉。

# 收完資訊後才開始呼叫工具

依序呼叫:
  1. resolve_location(起點名稱) → 取得 origin 座標
  2. 對使用者提到的每個停靠點 (例如「中間經過 X」「順便去 Y」「先到 X 再去 Y」),呼叫 resolve_location(名稱)
     收集成 waypoints 陣列。**使用者沒提就不要主動問**,不要把它列入反問次數。
  3. resolve_location(終點名稱) 或 search_nearby_pois(起點 + 類別) 挑最近的
  4. compute_route(origin_lat, origin_lng, dest_lat, dest_lng, mode, waypoints=[{lat,lng},...])
  5. compute_carbon_emission(distance_km=路線距離, mode=交通工具) ← 必呼叫

# 最後回覆

工具都跑完後用自然中文總結:「為你規劃 X 公里 / Y 分鐘的路線(經過 N 個停靠點),預計排碳 Z g CO2,已顯示在地圖上」。
不要再輸出 JSON,直接講話。

【全域原則】
- search_nearby_pois 一定要 lat/lng,沒有就先 resolve_location。
- 同一輪不要重複呼叫同一個 tool。
- 不要編造座標。
- 反問 JSON 出現任何前後文字 = 嚴重錯誤,程式會解析失敗。`;

export const useAiChatStore = defineStore("aiChat", () => {
	const messages = ref([
		{
			role: "bot",
			content:
				"哈囉！我是台北城市生活助手 🌱\n\n我可以幫你：\n• 查詢環保政策、補助、循環經濟相關文件\n• 找附近的環保餐廳或充電站\n• 規劃路線\n\n想了解什麼呢？",
		},
	]);
	const loading = ref(false);
	const sessionId = ref("ai_" + Date.now());

	// Latest results — kept in store so a side panel could optionally render them.
	// The actual map drawing is delegated to mapStore (existing Mapbox instance).
	const lastPois = ref([]);
	const lastRoute = ref(null);

	function reset() {
		const mapStore = useMapStore();
		messages.value = messages.value.slice(0, 1);
		lastPois.value = [];
		lastRoute.value = null;
		sessionId.value = "ai_" + Date.now();
		try {
			mapStore.clearAi();
			// Re-hide the route UI so we're back to the clean initial state.
			mapStore.routeUiVisible = false;
		} catch {
			/* map not initialised yet */
		}
	}

	// Try to parse a clarify JSON out of the bot's content.
	function tryParseClarify(text) {
		if (!text) return null;
		const m = text.match(/\{[\s\S]*?"type"\s*:\s*"clarify"[\s\S]*?\}/);
		if (!m) return null;
		try {
			const obj = JSON.parse(m[0]);
			if (obj.type === "clarify" && obj.question) return obj;
		} catch {
			/* ignore */
		}
		return null;
	}

	// Update the existing Mapbox map from this turn's tool invocations.
	function applyToolInvocations(invocations) {
		if (!Array.isArray(invocations)) return;
		const mapStore = useMapStore();
		const markers = [...lastPois.value];
		let routeData = null;
		// Track resolved locations in arrival order so we can label A / 停靠點 / B
		// in the route panel instead of just bare coords.
		const resolvedLocations = [];

		for (const inv of invocations) {
			let parsed;
			try {
				parsed = JSON.parse(inv.result);
			} catch {
				continue; // not JSON (e.g. search_documents text result)
			}
			if (inv.name === "resolve_location" && parsed.lat && parsed.lng) {
				const label = parsed.name || parsed.address;
				resolvedLocations.push({
					lng: parsed.lng,
					lat: parsed.lat,
					label,
				});
				markers.push({
					lng: parsed.lng,
					lat: parsed.lat,
					label,
					color: "#4ea1ff",
				});
			} else if (inv.name === "search_nearby_pois" && parsed.results) {
				for (const r of parsed.results) {
					markers.push({
						lng: r.lng,
						lat: r.lat,
						label: r.name,
						color: "#ff7043",
						subtitle: r.address,
						distance_m: r.distance_m,
					});
				}
			} else if (inv.name === "compute_route" && parsed.origin && parsed.destination) {
				// New shape (matches the hand-rolled RoutePanel + InstructionsPanel):
				// origin/dest as {lng,lat,label}, waypoints as [{lng,lat,label}],
				// plus legs[] for per-segment rendering & step-by-step instructions.

				// Match BE coords back to resolve_location names by proximity (≤ 5e-5 deg ≈ 5m).
				const matchLabel = (lng, lat) => {
					const hit = resolvedLocations.find(
						(r) => Math.abs(r.lng - lng) < 5e-5 && Math.abs(r.lat - lat) < 5e-5,
					);
					return hit ? hit.label : null;
				};

				const [oLng, oLat] = parsed.origin;
				const [dLng, dLat] = parsed.destination;
				routeData = {
					origin: {
						lng: oLng,
						lat: oLat,
						label: matchLabel(oLng, oLat) || "起點",
					},
					destination: {
						lng: dLng,
						lat: dLat,
						label: matchLabel(dLng, dLat) || "終點",
					},
					waypoints: (parsed.waypoints || []).map((wp, i) => {
						// BE returns waypoints as [lng,lat] arrays.
						const [wLng, wLat] = Array.isArray(wp)
							? wp
							: [wp.lng, wp.lat];
						return {
							lng: wLng,
							lat: wLat,
							label: matchLabel(wLng, wLat) || `停靠點 ${i + 1}`,
						};
					}),
					mode: parsed.mode || "driving",
					legs: Array.isArray(parsed.legs) ? parsed.legs : [],
					totalDistanceKm: parsed.distance_km,
					totalDurationMin: parsed.duration_min,
				};
				lastRoute.value = routeData;
			}
		}

		lastPois.value = markers;

		// Render markers and route in INDEPENDENT try/catch blocks: if pushing
		// POIs throws (e.g. fitBounds on stale map state), we still want the
		// route line to be drawn — it's the more user-visible result.
		if (markers.length) {
			try {
				mapStore.setAiPois(markers);
			} catch (e) {
				console.warn("AI chat: setAiPois failed", e);
			}
		}
		if (routeData) {
			try {
				mapStore.setRoute(routeData);
			} catch (e) {
				console.warn("AI chat: setRoute failed", e);
			}
		}
	}

	async function send(userText) {
		if (!userText.trim() || loading.value) return;
		messages.value.push({ role: "user", content: userText });
		loading.value = true;

		// Clear stale POI markers + route line so each turn shows only its own results.
		const mapStoreInst = useMapStore();
		try {
			mapStoreInst.clearAi();
		} catch {
			/* map not ready */
		}
		lastPois.value = [];
		lastRoute.value = null;

		// Build the API messages array.
		// TWCC llama3.3-70b context = 16k tokens. Tool results (POI lists, route geometry)
		// are large; if we replay full history every turn it explodes after ~3 turns.
		// Keep only the last MAX_HISTORY messages — older context is fine to drop because
		// each route-planning turn is self-contained.
		const MAX_HISTORY = 8;
		const recent = messages.value.slice(-MAX_HISTORY);
		const apiMessages = [{ role: "system", content: SYSTEM_PROMPT }];
		for (const m of recent) {
			// Truncate any single message above 2000 chars to keep total bounded.
			const content = (m.content || "").slice(0, 2000);
			if (m.role === "user") apiMessages.push({ role: "user", content });
			else if (m.role === "bot") apiMessages.push({ role: "assistant", content });
		}

		try {
			const res = await http.post("/ai/chat/twai", {
				session: sessionId.value,
				stream: false,
				messages: apiMessages,
				max_new_tokens: 800,
				temperature: 0.3,
				tools: TOOL_DEFS,
			});
			const data = res.data?.data;
			if (!data) throw new Error("empty response");

			applyToolInvocations(data.tool_invocations);

			const botText = data.content || "(沒有回覆)";
			const clarify = tryParseClarify(botText);
			if (clarify) {
				messages.value.push({
					role: "bot",
					content: clarify.question,
					quickReplies: clarify.quick_replies || [],
				});
			} else {
				messages.value.push({ role: "bot", content: botText });
			}
		} catch (e) {
			console.error("AI chat error:", e);
			messages.value.push({
				role: "bot",
				content: "抱歉,連線發生錯誤。請稍後再試。",
				error: true,
			});
		} finally {
			loading.value = false;
		}
	}

	return {
		messages,
		loading,
		sessionId,
		lastPois,
		lastRoute,
		send,
		reset,
	};
});
