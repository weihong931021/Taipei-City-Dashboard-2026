<script setup>
import { ref, watch, nextTick, computed } from "vue";
import { storeToRefs } from "pinia";
import SendIcon from "../icons/SendIcon.vue";
import BotLogo from "../icons/BotLogo.vue";
import UserLogo from "../icons/UserLogo.vue";

import { useAiChatStore } from "../../store/aiChatStore";

const aiChatStore = useAiChatStore();
const { messages, loading } = storeToRefs(aiChatStore);

const userMessage = ref("");
const chatAreaRef = ref(null);
const isStickyOpen = ref(false);

// Adapt aiChatStore.messages to the existing template shape (id, role, content, etc.)
const chatData = computed(() =>
	messages.value.map((m, i) => ({
		id: i,
		role: m.role, // 'user' | 'bot'
		content: m.content,
		quickReplies: m.quickReplies,
		error: m.error,
		isDefault: i === 0,
	})),
);

function sendBtnHandler(text) {
	if (!text.trim() || loading.value) return;
	aiChatStore.send(text);
	userMessage.value = "";
}

function quickReplyHandler(text) {
	if (loading.value) return;
	aiChatStore.send(text);
}

function resetHandler() {
	aiChatStore.reset();
}

const toggleSticky = () => {
	isStickyOpen.value = !isStickyOpen.value;
};

watch(
	() => chatData.value.length,
	async () => {
		await nextTick();
		const chat = chatAreaRef.value;
		if (!chat) return;
		chat.scrollTop = chat.scrollHeight - chat.clientHeight;
	},
	{ deep: true },
);
</script>

<template>
  <div class="chat-widget">
    <!-- 標題 -->
    <div class="header">
      <h3>臺北城市儀表板小幫手</h3>
      <button
        class="reset-btn"
        title="重新開始對話"
        @click="resetHandler"
      >
        重新開始
      </button>
    </div>

    <!-- 聊天區 -->
    <div
      ref="chatAreaRef"
      class="chat-area scrollbar-custom"
    >
      <!-- 置頂訊息 -->
      <div class="chat-message sticky-message">
        <div
          class="sticky-header"
          @click="toggleSticky"
        >
          <span>置頂公告：小幫手使用須知</span>
          <button class="toggle-btn">
            {{ isStickyOpen ? "-" : "+" }}
          </button>
        </div>
        <div
          v-show="isStickyOpen"
          class="sticky-body"
        >
          <span>小幫手可協助您：<br>
            • 查詢台北/新北永續政策、補助、循環經濟相關文件 (RAG)<br>
            • 找附近的環保餐廳或電動車充電站 (請至 /mapview 看地圖渲染)<br>
            • 規劃路線 (回傳路徑會在 /mapview 地圖上畫出)<br><br>
            提示：路線/找店類問題小幫手會反問細節，請點選快速回覆按鈕。</span>
        </div>
      </div>
      <div
        v-for="chat in chatData"
        :key="chat.id"
        class="message"
      >
        <!-- 機器人訊息 -->
        <div
          v-if="chat.role === 'bot'"
          class="bot"
        >
          <div class="avatar">
            <BotLogo />
          </div>
          <div class="content">
            <div
              v-if="chat.content"
              class="message--bubble"
              :class="{ 'message--bubble--error': chat.error }"
            >
              <p>{{ chat.content }}</p>
            </div>
            <!-- 快速回覆按鈕 (CoT 澄清流程) -->
            <div
              v-if="chat.quickReplies && chat.quickReplies.length"
              v-horizontal-wheel
              class="message--button scrollbar-x-hide"
            >
              <button
                v-for="(q, j) in chat.quickReplies"
                :key="j"
                :disabled="loading"
                @click="quickReplyHandler(q)"
              >
                {{ q }}
              </button>
            </div>
          </div>
        </div>
        <!-- 使用者訊息 -->
        <div
          v-else
          class="user"
        >
          <div class="avatar">
            <UserLogo />
          </div>
          <div
            v-if="chat.content"
            class="content"
          >
            <div class="message--bubble">
              <p>{{ chat.content }}</p>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- 載入指示器 -->
    <div
      v-if="loading"
      class="loading-bar"
    >
      <span>思考中…</span>
    </div>

    <!-- 輸入區 -->
    <div class="input-area">
      <input
        v-model="userMessage"
        type="text"
        :disabled="loading"
        placeholder="輸入訊息..."
        @keyup.enter="sendBtnHandler(userMessage)"
      >
      <button
        :disabled="loading || !userMessage.trim()"
        @click="sendBtnHandler(userMessage)"
      >
        <SendIcon />
      </button>
    </div>
  </div>
</template>

<style lang="scss" scoped>
/* === 變數設定 === */
$bg-dark: #090909;
$panel-bg: #494b4e;
$card-bg: #282a2c;
$border-color: #888787;
$input-bg: #d9d9d9;
$white: #ffffff;
$scroll-thumb-hover: #ababab;
$radius-10: 10px;
$radius-15: 15px;
$radius-20: 20px;

/* === Scrollbar === */
.scrollbar-x-hide {
	scrollbar-width: none;

	&::-webkit-scrollbar {
		display: none;
	}
}

.scrollbar-custom {
	&::-webkit-scrollbar {
		width: 2px;
		background: transparent;
	}

	&::-webkit-scrollbar-thumb {
		background: $white;
		border-radius: 8px;
	}

	&::-webkit-scrollbar-thumb:hover {
		background: $scroll-thumb-hover;
	}
}

/* === 主要樣式 === */
.chat-widget {
	width: 400px;
	border-radius: $radius-20;
	overflow: hidden;
	background: $bg-dark;
	border: 1px solid $border-color;
	display: flex;
	flex-direction: column;

	.header {
		padding: 1rem;
		background: $panel-bg;
		border-bottom: 3px solid $border-color;
		display: flex;
		align-items: center;
		justify-content: space-between;

		h3 {
			font-size: 18px;
			font-weight: 700;
			color: $white;
			margin: 0;
		}

		.reset-btn {
			background: transparent;
			color: #ccc;
			border: 1px solid #777;
			border-radius: 6px;
			padding: 4px 10px;
			font-size: 12px;
			cursor: pointer;
			transition: all 0.15s;

			&:hover {
				color: $white;
				border-color: $white;
			}
		}
	}

	.loading-bar {
		padding: 6px 18px;
		background: rgba(255, 255, 255, 0.05);
		color: #aaa;
		font-size: 12px;
		font-style: italic;
		border-top: 1px solid rgba(255, 255, 255, 0.08);
	}

	.chat-area {
		flex: 1;
		margin: 0.25rem;
		padding: 0.75rem;
		overflow-y: auto;
		background: $bg-dark;

		.chat-message {
			padding: 4px 10px;
			margin: 0px 8px;
			border-radius: 8px;
			background-color: $bg-dark;
		}

		// 置頂訊息
		.sticky-message {
			border: 1px solid #ffffff;
			position: sticky;
			top: 0;
			z-index: 10;

			.sticky-header {
				display: flex;
				font-weight: bold;
				justify-content: space-between;
				align-items: center;
				cursor: pointer;
				padding: 8px 12px;
			}

			.sticky-body {
				padding: 8px 12px;
				font-weight: 400;
				font-size: 14px;
			}

			.toggle-btn {
				background: none;
				border: none;
				font-size: 14px;
				cursor: pointer;
				color: #ffffff;
			}
		}

		.message {
			padding: 8px;

			.bot,
			.user {
				display: flex;
				gap: 0.5rem;
				align-items: flex-start;

				&.user {
					flex-direction: row-reverse;
				}

				.avatar {
					width: 40px;
					height: 40px;
					display: flex;
					align-items: center;
					justify-content: center;
					flex-shrink: 0;

					svg {
						width: 100%;
						height: auto;
					}
				}

				.content {
					display: flex;
					flex-direction: column;
					gap: 0.5rem;

					.message--bubble {
						border: 1px solid $white;
						border-radius: $radius-10;
						background: $card-bg;

						p {
							color: $white;
							white-space: pre-line;
							margin: 0;
							padding-top: 8px;
							padding-bottom: 8px;
							padding-left: 16px;
							padding-right: 16px;
							font-size: 16px;
						}

						&--error {
							border-color: #c97070;
							background: #4a2a2a;
						}
					}

					.message--button {
						display: flex;
						gap: 0.5rem;
						overflow-x: auto;

						button {
							flex-shrink: 0;
							background: $panel-bg;
							color: $white;
							font-size: 14px;
							padding: 0.5rem 1rem;
							border-radius: $radius-15;
							border: none;
							cursor: pointer;
							white-space: nowrap;

							&:hover {
								filter: brightness(0.5);
							}
						}
					}
				}
			}
		}
	}

	.input-area {
		display: flex;
		align-items: center;
		justify-content: center;
		gap: 0.5rem;
		padding: 1.5rem 1.125rem;
		background: $panel-bg;

		input[type="text"] {
			background: $white;
			height: 35px;
			width: 100%;
			border-radius: 20px;
			padding: 0 1rem;
			border: none;
			outline: none;
			color: black;
		}

		button {
			height: 35px;
			display: flex;
			align-items: center;
			justify-content: center;
			background: transparent;
			border: none;
			cursor: pointer;

			&:hover {
				filter: brightness(0.5);
			}
		}
	}
}
</style>
