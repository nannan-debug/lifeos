const state = {
  traces: [],
  events: [],
  selectedTraceId: null,
  selectedEventId: null,
  selectedEvent: null,
  autoRefreshTimer: null,
  lastReceivedAt: null,        // 最新 event 的 receivedAt，用于增量检测
  currentDate: null,           // 当前查询的日期，切日期时重置
  currentView: "traces",
  usageLoadedFor: null,
  growthLoadedFor: null,
  growth: null,
};

const $ = (id) => document.getElementById(id);

const USAGE_LABELS = {
  usage_app_open: "打开 App",
  usage_tab_switch: "切换 Tab",
  usage_turn_created: "新随手记",
  usage_task_created: "新待办",
  usage_task_completed: "完成待办",
  usage_time_created: "新时间记录",
  usage_check_toggled: "打卡",
  usage_ai_chat_sent: "Arya 对话",
  usage_calendar_created: "新日历事件",
  usage_review_opened: "打开复盘",
  usage_braincard_viewed: "查看第二大脑",
  usage_export: "导出",
};

const EVENT_LABELS = {
  // iOS 端
  request_started: "发起请求",
  response_merged: "收到回复",
  request_failed: "请求失败",
  tool_call_started: "工具调用",
  tool_call_result: "工具结果",
  action_auto_confirmed: "自动保存",
  action_confirmed: "手动确认",
  action_dismissed: "取消建议",
  action_auto_undo: "撤销保存",
  debug_log_created: "调试日志",
  // Worker 端
  worker_received: "Worker 收到",
  prompt_built: "Prompt 组装",
  response_decoded: "响应解析",
  stream_started: "流式开始",
  stream_finished: "流式完成",
  stream_failed: "流式失败",
  stream_error: "流式异常",
  model_call_started: "模型调用",
  model_call_finished: "模型返回",
  model_call_failed: "模型失败",
  usage_batch: "使用统计汇总",
};
function eventLabel(name) { return EVENT_LABELS[name] ? `${name} ${EVENT_LABELS[name]}` : name; }

function todayKey() {
  return new Date().toISOString().slice(0, 10);
}

function shortTime(value) {
  if (!value) return "";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return String(value).slice(11, 19);
  return date.toLocaleTimeString("zh-CN", { hour: "2-digit", minute: "2-digit", second: "2-digit" });
}

function formatLatency(ms) {
  if (!ms) return "";
  return (ms / 1000).toFixed(1) + "s";
}

function compact(text, fallback = "") {
  const value = String(text || fallback || "").replace(/\s+/g, " ").trim();
  return value.length > 96 ? `${value.slice(0, 96)}...` : value;
}

function eventId(event, index) {
  return `${event.traceId}-${event.eventName}-${event.timestamp || event.receivedAt}-${index}`;
}

function usageSummary(payload = {}, maxItems = 4) {
  return Object.entries(payload)
    .map(([key, value]) => [USAGE_LABELS[key] || key, Number(value) || 0])
    .filter(([, count]) => count > 0)
    .sort((a, b) => b[1] - a[1])
    .slice(0, maxItems)
    .map(([label, count]) => `${label} ${count}`)
    .join("、");
}

function escapeHTML(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll("\"", "&quot;");
}

function highlightJSON(value) {
  return escapeHTML(JSON.stringify(value, null, 2))
    .replace(/"([^"]+)":/g, '<span class="json-key">"$1"</span>:')
    .replace(/: "([^"]*)"/g, ': <span class="json-string">"$1"</span>')
    .replace(/: (true|false)/g, ': <span class="json-boolean">$1</span>')
    .replace(/: (null)/g, ': <span class="json-null">$1</span>')
    .replace(/: (-?\d+\.?\d*)/g, ': <span class="json-number">$1</span>')
    .replace(/\\n/g, "\n")
    .replace(/\\t/g, "  ");
}

function tryParseJSON(value) {
  if (typeof value !== "string") return value;
  const trimmed = value.trim();
  if (!trimmed || !["{", "["].includes(trimmed[0])) return value;
  try {
    return JSON.parse(trimmed);
  } catch {
    return value;
  }
}

function readableText(value) {
  if (value === null || value === undefined || value === "") return "";
  if (typeof value === "string") return value;
  return JSON.stringify(value, null, 2);
}

function renderDialogue(messages) {
  const parsed = tryParseJSON(messages);
  if (!Array.isArray(parsed)) return "";
  return `
    <section class="readable-section">
      <h3>Messages</h3>
      <div class="message-list">
        ${parsed.map((message) => `
          <article class="message-row ${escapeHTML(message.role || "unknown")}">
            <span>${escapeHTML(message.role || "unknown")}</span>
            <p>${escapeHTML(readableText(message.content))}</p>
          </article>
        `).join("")}
      </div>
    </section>
  `;
}

function renderReadablePayload(event) {
  const payload = event.payload || {};
  const rows = [
    ["Input", payload.input],
    ["Reply", payload.reply],
    ["Follow-up", payload.followUpQuestion],
    ["Intermediate", payload.intermediateReply],
    ["Tool", payload.toolName || payload.toolCall],
    ["Reasoning", payload.reasoning],
  ].filter(([, value]) => value !== undefined && value !== null && value !== "");

  const messages = renderDialogue(payload.messages);
  const dbtSession = tryParseJSON(payload.dbtSession);
  const actionSuggestions = tryParseJSON(payload.actionSuggestions);
  const mergedActions = tryParseJSON(payload.mergedActions);

  const sections = [];
  if (rows.length) {
    sections.push(`
      <section class="readable-section">
        <h3>Payload</h3>
        <div class="readable-fields">
          ${rows.map(([label, value]) => `
            <div class="readable-field">
              <span>${escapeHTML(label)}</span>
              <p>${escapeHTML(readableText(tryParseJSON(value)))}</p>
            </div>
          `).join("")}
        </div>
      </section>
    `);
  }
  if (messages) sections.push(messages);
  if (dbtSession && typeof dbtSession === "object") {
    sections.push(`
      <section class="readable-section">
        <h3>DBT Session</h3>
        <div class="readable-fields compact">
          <div class="readable-field"><span>Status</span><p>${escapeHTML(dbtSession.status || "n/a")}</p></div>
          <div class="readable-field"><span>Skill</span><p>${escapeHTML(dbtSession.skillId || "n/a")}</p></div>
          <div class="readable-field"><span>Step</span><p>${escapeHTML(String((dbtSession.currentStepIndex ?? 0) + 1))}</p></div>
        </div>
      </section>
    `);
  }
  for (const [title, value] of [["Actions", actionSuggestions], ["Merged Actions", mergedActions]]) {
    if (Array.isArray(value) && value.length) {
      sections.push(`
        <section class="readable-section">
          <h3>${escapeHTML(title)}</h3>
          <div class="action-list">
            ${value.map((action) => `
              <article class="action-row">
                <strong>${escapeHTML(action.title || action.kind || "action")}</strong>
                <p>${escapeHTML(action.detail || action.reason || "")}</p>
              </article>
            `).join("")}
          </div>
        </section>
      `);
    }
  }
  return sections.join("");
}

// ── 带超时 + 自动重试的 fetch ──
async function requestJSON(url, options = {}) {
  const maxRetries = options._retries ?? 2;
  const timeoutMs = options._timeout ?? 15000;
  let lastError;

  for (let attempt = 0; attempt <= maxRetries; attempt++) {
    if (attempt > 0) {
      await new Promise((r) => setTimeout(r, 800 * attempt));
    }
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    try {
      const response = await fetch(url, {
        ...options,
        signal: controller.signal,
        credentials: "same-origin",
        headers: {
          "Content-Type": "application/json",
          ...(options.headers || {}),
        },
      });
      clearTimeout(timer);

      const body = await response.json().catch(() => ({}));
      if (response.status === 401) {
        if (body.error === "invalid_credentials") {
          throw new Error("invalid_credentials");
        }
        handleSessionExpired();
        throw new Error("会话已过期，请重新登录");
      }

      if (!response.ok) {
        throw new Error(body.error || `HTTP ${response.status}`);
      }
      return body;
    } catch (error) {
      clearTimeout(timer);
      lastError = error;
      if (error.message.includes("会话已过期")) throw error;
      if (error.name !== "AbortError" && error.message !== "Failed to fetch" && !error.message.includes("NetworkError")) {
        throw error;
      }
    }
  }
  throw lastError || new Error("网络连接失败");
}

function handleSessionExpired() {
  $("loginPanel").hidden = false;
  $("appPanel").hidden = true;
  $("loginMessage").textContent = "会话已过期，请重新登录。";
  stopAutoRefresh();
}

// ── 自动刷新 ──
function startAutoRefresh() {
  stopAutoRefresh();
  state.autoRefreshTimer = setInterval(() => {
    loadCurrentView(true);
  }, 60000);
}

function stopAutoRefresh() {
  if (state.autoRefreshTimer) {
    clearInterval(state.autoRefreshTimer);
    state.autoRefreshTimer = null;
  }
}

function viewFromHash() {
  if (window.location.hash === "#usage") return "usage";
  if (window.location.hash === "#growth") return "growth";
  return "traces";
}

function dateRangeKey() {
  return `${currentStartDate()}..${currentEndDate()}`;
}

function updateViewUI() {
  const view = state.currentView;
  $("appPanel").dataset.view = view;
  $("tracesPage").hidden = view !== "traces";
  $("usagePage").hidden = view !== "usage";
  $("growthPage").hidden = view !== "growth";
  $("tracesTab").classList.toggle("active", view === "traces");
  $("usageTab").classList.toggle("active", view === "usage");
  $("growthTab").classList.toggle("active", view === "growth");
  $("searchButton").textContent = view === "traces" ? "搜索" : "刷新";
}

async function loadCurrentView(silent = false) {
  if (state.currentView === "usage") {
    await loadUsage(silent);
  } else if (state.currentView === "growth") {
    await loadGrowth(silent);
  } else {
    await loadTraces(silent);
  }
}

async function setView(view, { updateHash = true } = {}) {
  state.currentView = ["usage", "growth"].includes(view) ? view : "traces";
  updateViewUI();
  if (updateHash && window.location.hash !== `#${state.currentView}`) {
    window.location.hash = state.currentView;
    return;
  }
  await loadCurrentView();
}

async function loadSession() {
  const session = await requestJSON("/dashboard/api/session", { _retries: 1 });
  $("loginPanel").hidden = session.authenticated;
  $("appPanel").hidden = !session.authenticated;
  if (!session.enabled) {
    $("loginPanel").hidden = false;
    $("appPanel").hidden = true;
    $("loginMessage").textContent = "Dashboard 还没有配置账户和密码。";
    return;
  }
  if (session.authenticated) {
    $("sessionUser").textContent = session.user;
    state.currentView = viewFromHash();
    updateViewUI();
    await loadCurrentView();
    startAutoRefresh();
  }
}

function currentStartDate() {
  return $("startDateInput").value || todayKey();
}
function currentEndDate() {
  return $("endDateInput").value || currentStartDate();
}

function queryURL(extra = {}) {
  const params = new URLSearchParams();
  params.set("startDate", currentStartDate());
  params.set("endDate", currentEndDate());
  params.set("limit", "1000");
  params.set("summaryOnly", "1");
  params.set("kind", extra.kind || "ai");
  const q = $("searchInput").value.trim();
  const traceId = $("traceInput").value.trim();
  const source = $("sourceInput").value;
  if (q) params.set("q", q);
  if (traceId) params.set("traceId", traceId);
  if (source !== "all") params.set("source", source);
  if ($("errorsOnlyInput").checked) params.set("errorsOnly", "1");
  if (extra.since) params.set("since", extra.since);
  return `/dashboard/api/traces?${params}`;
}

function listByDate(items = [], max = 4) {
  return [...items]
    .sort((a, b) => String(b.data?.updated_at || b.data?.date || "").localeCompare(String(a.data?.updated_at || a.data?.date || "")))
    .slice(0, max);
}

// 从 traces 列表里提取最晚的 receivedAt（用于增量检测）
function extractLastReceivedAt(traces) {
  let latest = state.lastReceivedAt || "";
  for (const trace of traces) {
    if (trace.lastAt && trace.lastAt > latest) latest = trace.lastAt;
  }
  return latest || null;
}

async function loadTraces(silent = false) {
  const queryDate = currentStartDate();

  // ── 增量检测：静默刷新时，先查有没有新数据 ──
  if (silent && state.lastReceivedAt && state.currentDate === queryDate) {
    try {
      const check = await requestJSON(queryURL({ since: state.lastReceivedAt }), { _retries: 1, _timeout: 8000 });
      const newTraces = check.traces || [];
      if (newTraces.length === 0) {
        // 没有新数据，只更新时间戳
        setRefreshState("无新数据");
        return;
      }
      // 有新数据 → 继续走全量刷新（服务器有缓存，很快）
    } catch {
      // 增量检测失败，静默忽略
      return;
    }
  }

  if (!silent) setBusy(true, "查询中...");
  try {
    if (!silent) setLoading("正在读取 trace 摘要...");
    const body = await requestJSON(queryURL());
    state.traces = body.traces || [];
    state.currentDate = queryDate;
    state.lastReceivedAt = extractLastReceivedAt(state.traces);

    if (!state.traces.some((trace) => trace.traceId === state.selectedTraceId)) {
      state.selectedTraceId = state.traces[0]?.traceId || null;
      state.selectedEventId = null;
      state.selectedEvent = null;
    }
    renderTraceList();
    await loadSelectedTraceEvents();
    renderEventDetail();
    setRefreshState("已更新");
  } catch (error) {
    if (!silent) showError(error);
    setRefreshState("读取失败");
  } finally {
    setBusy(false);
  }
}

async function loadSelectedTraceEvents() {
  state.events = [];
  if (!state.selectedTraceId) {
    renderTimeline();
    return;
  }
  setLoading("正在读取完整链路...");
  try {
    const params = new URLSearchParams();
    params.set("startDate", currentStartDate());
    params.set("endDate", currentEndDate());
    params.set("traceId", state.selectedTraceId);
    params.set("limit", "1000");
    const body = await requestJSON(`/dashboard/api/traces?${params}`);
    state.events = (body.events || []).map((event, index) => ({ ...event, __id: eventId(event, index) }));
    if (!state.events.some((event) => event.__id === state.selectedEventId)) {
      state.selectedEvent = state.events[0] || null;
      state.selectedEventId = state.selectedEvent?.__id || null;
    }
    renderTimeline();
  } catch (error) {
    $("timeline").className = "timeline empty-state";
    $("timeline").innerHTML = `<span>读取失败：${escapeHTML(error.message)}</span> <button class="retry-link" onclick="loadSelectedTraceEvents()">重试</button>`;
  }
}

function setLoading(text) {
  $("timeline").className = "timeline empty-state";
  $("timeline").textContent = text;
}

function setBusy(isBusy, text = "") {
  $("refreshButton").disabled = isBusy;
  $("searchButton").disabled = isBusy;
  if (text) setRefreshState(text);
}

function setRefreshState(text) {
  const now = new Date().toLocaleTimeString("zh-CN", { hour: "2-digit", minute: "2-digit", second: "2-digit" });
  $("refreshState").textContent = `${text} · ${now}`;
}

function renderTraceList() {
  $("traceCount").textContent = String(state.traces.length);
  if (state.traces.length === 0) {
    $("traceList").innerHTML = '<div class="empty-state">没有查到 trace</div>';
    return;
  }
  $("traceList").innerHTML = state.traces.map((trace) => `
    <button class="trace-card ${trace.hasError ? "error" : ""} ${trace.traceId === state.selectedTraceId ? "active" : ""}" data-trace-id="${escapeHTML(trace.traceId)}">
      <div class="trace-title">${escapeHTML(compact(trace.title, trace.traceId))}</div>
      <div class="trace-meta">
        <span class="pill ${trace.hasError ? "error" : "ok"}">${trace.status}</span>
        <span class="pill">${escapeHTML(shortTime(trace.lastAt))}</span>
        <span class="pill">${trace.eventCount} events</span>
        ${trace.latencyMs ? `<span class="pill">${formatLatency(trace.latencyMs)}</span>` : ""}
        ${trace.sources.map((source) => `<span class="pill">${escapeHTML(source)}</span>`).join("")}
      </div>
    </button>
  `).join("");
  document.querySelectorAll(".trace-card").forEach((card) => {
    card.addEventListener("click", () => {
      state.selectedTraceId = card.dataset.traceId;
      state.selectedEventId = null;
      state.selectedEvent = null;
      renderTraceList();
      loadSelectedTraceEvents().catch(showError);
      renderEventDetail();
    });
  });
}

function selectedEvents() {
  return state.events.filter((event) => event.traceId === state.selectedTraceId);
}

function eventPreview(event) {
  if (event.eventName === "usage_batch") {
    return usageSummary(event.payload) || "没有使用计数";
  }
  return compact(
    event.error?.message ||
    event.payload?.input ||
    event.payload?.reply ||
    event.payload?.rawModelOutput ||
    event.payload?.message ||
    ""
  );
}

function renderTimeline() {
  const events = selectedEvents();
  const trace = state.traces.find((item) => item.traceId === state.selectedTraceId);
  $("selectedTraceTitle").textContent = trace ? compact(trace.title, trace.traceId) : "选择一条 trace";
  $("selectedTraceMeta").textContent = trace ? `${trace.eventCount} events · ${trace.traceId}` : "";
  if (events.length === 0) {
    $("timeline").className = "timeline empty-state";
    $("timeline").textContent = "暂无数据";
    return;
  }
  $("timeline").className = "timeline";
  $("timeline").innerHTML = events.map((event) => `
    <article class="event-row">
      <div class="event-time">${escapeHTML(shortTime(event.timestamp || event.receivedAt))}</div>
      <button class="event-card ${event.error ? "error" : ""} ${event.__id === state.selectedEventId ? "active" : ""}" data-event-id="${escapeHTML(event.__id)}">
        <div class="event-head">
          <span>${escapeHTML(eventLabel(event.eventName))}</span>
          <span class="pill">${escapeHTML(event.source)}</span>
        </div>
        <div class="event-body">
          ${event.latencyMs ? `<div>${formatLatency(event.latencyMs)}</div>` : ""}
          ${eventPreview(event) ? `<div class="summary-line">${escapeHTML(eventPreview(event))}</div>` : ""}
        </div>
      </button>
    </article>
  `).join("");
  document.querySelectorAll(".event-card").forEach((card) => {
    card.addEventListener("click", () => {
      state.selectedEventId = card.dataset.eventId;
      state.selectedEvent = state.events.find((event) => event.__id === state.selectedEventId) || null;
      renderTimeline();
      renderEventDetail();
    });
  });
}

function renderEventDetail() {
  const event = state.selectedEvent;
  if (!event) {
    $("eventSummary").className = "event-summary empty-state";
    $("eventSummary").textContent = "选择时间线中的事件";
    $("readableView").innerHTML = "";
    $("jsonView").innerHTML = "";
    return;
  }
  $("eventSummary").className = "event-summary";
  $("eventSummary").innerHTML = `
    <div class="metric-grid">
      <div class="metric"><span>Event</span><strong>${escapeHTML(eventLabel(event.eventName))}</strong></div>
      <div class="metric"><span>Source</span><strong>${escapeHTML(event.source)}</strong></div>
      <div class="metric"><span>Latency</span><strong>${event.latencyMs ? formatLatency(event.latencyMs) : "n/a"}</strong></div>
      <div class="metric"><span>Tokens</span><strong>${escapeHTML(event.usage?.total_tokens || event.usage?.totalTokens || "n/a")}</strong></div>
    </div>
    ${event.eventName === "usage_batch" ? `<div class="summary-line">${escapeHTML(usageSummary(event.payload, 12) || "没有使用计数")}</div>` : ""}
    ${event.error ? `<div class="pill error">${escapeHTML(event.error.type || "error")}: ${escapeHTML(event.error.message)}</div>` : ""}
  `;
  $("readableView").innerHTML = renderReadablePayload(event);
  $("jsonView").innerHTML = highlightJSON(event);
}

async function login(event) {
  event.preventDefault();
  $("loginMessage").textContent = "";
  try {
    await requestJSON("/dashboard/api/login", {
      method: "POST",
      body: JSON.stringify({
        user: $("loginUser").value,
        password: $("loginPassword").value,
      }),
      _retries: 1,
    });
    await loadSession();
  } catch (error) {
    $("loginMessage").textContent = error.message === "invalid_credentials" ? "账户或密码不对。" : error.message;
  }
}

async function logout() {
  stopAutoRefresh();
  await requestJSON("/dashboard/api/logout", { method: "POST", body: "{}", _retries: 0 });
  state.traces = [];
  state.events = [];
  state.selectedTraceId = null;
  state.selectedEvent = null;
  state.lastReceivedAt = null;
  state.currentDate = null;
  await loadSession();
}

async function copyJSON() {
  if (!state.selectedEvent) return;
  await navigator.clipboard.writeText(JSON.stringify(state.selectedEvent, null, 2));
  $("copyJsonButton").textContent = "已复制";
  setTimeout(() => {
    $("copyJsonButton").textContent = "复制 JSON";
  }, 1200);
}

function showError(error) {
  $("timeline").className = "timeline empty-state";
  $("timeline").innerHTML = `<span>读取失败：${escapeHTML(error.message)}</span> <button class="retry-link" onclick="loadTraces()">重试</button>`;
}

// ── Usage Analytics ──
async function loadUsage(silent = false) {
  const key = dateRangeKey();
  if (silent && state.usageLoadedFor === key) return;
  if (!silent) setBusy(true, "读取 Usage...");
  try {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 10000);
    const response = await fetch(
      `/dashboard/api/usage?startDate=${currentStartDate()}&endDate=${currentEndDate()}`,
      { signal: controller.signal, credentials: "same-origin", headers: { "Content-Type": "application/json" } }
    );
    clearTimeout(timer);
    if (!response.ok) {
      const body = await response.json().catch(() => ({}));
      throw new Error(body.error || `HTTP ${response.status}`);
    }
    const body = await response.json();
    renderUsage(body);
    state.usageLoadedFor = key;
    setRefreshState("Usage 已更新");
  } catch (error) {
    $("usageSummary").innerHTML = `<div class="empty-state">加载失败：${escapeHTML(error.message)}</div>`;
    $("usageFeatures").innerHTML = "";
    $("usageUsers").innerHTML = "";
    setRefreshState("Usage 读取失败");
  } finally {
    setBusy(false);
  }
}

function renderUsage(data) {
  if (!data) return;
  const days = data.daily?.length || 1;
  const dailyAvg = days > 0 ? Math.round(data.totalEvents / days) : 0;

  // Summary cards
  $("usageSummary").innerHTML = `
    <div class="usage-card">
      <div class="usage-card-value">${data.totalUsers}</div>
      <div class="usage-card-label">活跃用户</div>
    </div>
    <div class="usage-card">
      <div class="usage-card-value">${data.totalEvents}</div>
      <div class="usage-card-label">总事件数</div>
    </div>
    <div class="usage-card">
      <div class="usage-card-value">${dailyAvg}</div>
      <div class="usage-card-label">日均事件</div>
    </div>
    <div class="usage-card">
      <div class="usage-card-value">${days}</div>
      <div class="usage-card-label">统计天数</div>
    </div>
  `;

  // Feature bar chart
  const features = Object.entries(data.featureTotals || {})
    .sort((a, b) => b[1] - a[1]);
  const maxCount = features.length > 0 ? features[0][1] : 1;

  if (features.length === 0) {
    $("usageFeatures").innerHTML = '<div class="empty-state">暂无功能使用数据</div>';
  } else {
    $("usageFeatures").innerHTML = `
      <h3>功能使用排行</h3>
      ${features.map(([key, count]) => {
        const label = USAGE_LABELS[key] || key;
        const pct = Math.max(2, Math.round((count / maxCount) * 100));
        return `
          <div class="usage-bar-row">
            <span class="usage-bar-label">${escapeHTML(label)}</span>
            <div class="usage-bar-track">
              <div class="usage-bar-fill" style="width:${pct}%"></div>
            </div>
            <span class="usage-bar-count">${count}</span>
          </div>`;
      }).join("")}
    `;
  }

  // User list
  const users = data.users || [];
  if (users.length === 0) {
    $("usageUsers").innerHTML = '<div class="empty-state">暂无用户数据</div>';
  } else {
    $("usageUsers").innerHTML = `
      <h3>用户明细</h3>
      <table class="usage-table">
        <thead><tr><th>用户</th><th>事件数</th><th>最后活跃</th><th>主要功能</th></tr></thead>
        <tbody>
          ${users.map((u) => {
            const topFeatures = Object.entries(u.events)
              .sort((a, b) => b[1] - a[1])
              .slice(0, 3)
              .map(([k, v]) => `${USAGE_LABELS[k] || k}(${v})`)
              .join(", ");
            return `<tr>
              <td><code>${escapeHTML(u.shortId)}</code></td>
              <td>${u.totalEvents}</td>
              <td>${escapeHTML(u.lastSeen)}</td>
              <td>${escapeHTML(topFeatures)}</td>
            </tr>`;
          }).join("")}
        </tbody>
      </table>
    `;
  }
}

// ── Growth Ops ──
async function loadGrowth(silent = false) {
  const key = dateRangeKey();
  if (silent && state.growthLoadedFor === key) return;
  if (!$("growthPage")) return;
  if (!silent) setBusy(true, "读取 Growth Ops...");
  try {
    const data = await requestJSON("/dashboard/api/growth", { _retries: 1, _timeout: 10000 });
    state.growth = data;
    state.growthLoadedFor = key;
    renderGrowth(data);
    setRefreshState("Growth 已更新");
  } catch (error) {
    $("growthSummary").innerHTML = `<div class="empty-state">加载失败：${escapeHTML(error.message)}</div>`;
    $("growthFlow").innerHTML = "";
    $("growthDrafts").innerHTML = "";
    $("growthReferences").innerHTML = "";
    setRefreshState("Growth 读取失败");
  } finally {
    setBusy(false);
  }
}

function renderGrowth(data) {
  if (!data || !$("growthLedger")) return;
  $("growthRoot").textContent = data.root || "growth dir";
  const ledgerRows = growthLedgerRows(data);
  $("growthLedgerCount").textContent = String(ledgerRows.length);
  $("growthDraftCount").textContent = String(data.drafts?.length || 0);
  $("growthReferenceCount").textContent = String(data.references?.length || 0);

  $("growthSummary").innerHTML = `
    <div class="usage-card compact">
      <div class="usage-card-value">${data.counts?.references || 0}</div>
      <div class="usage-card-label">参考帖</div>
    </div>
    <div class="usage-card compact">
      <div class="usage-card-value">${data.counts?.topics || 0}</div>
      <div class="usage-card-label">选题</div>
    </div>
    <div class="usage-card compact">
      <div class="usage-card-value">${data.counts?.readyDrafts || 0}</div>
      <div class="usage-card-label">Ready 草稿</div>
    </div>
    <div class="usage-card compact">
      <div class="usage-card-value">${data.counts?.needsReview || 0}</div>
      <div class="usage-card-label">待复盘</div>
    </div>
  `;

  const stages = [
    ["调研", data.counts?.references || 0, "沉淀参考帖、hook、结构、视觉"],
    ["选题", data.counts?.topics || 0, "从素材库和产品动态挑主题"],
    ["生产", data.counts?.drafts || 0, "文案、封面、发布检查"],
    ["发布", data.counts?.published || 0, "手动复制到小红书"],
    ["复盘", data.weekly?.length || 0, "记录数据，调整下周策略"],
  ];
  $("growthFlow").innerHTML = stages.map(([label, count, desc], index) => `
    <article class="growth-stage ${count > 0 ? "has-data" : ""}">
      <span class="growth-stage-index">${index + 1}</span>
      <div>
        <strong>${escapeHTML(label)}</strong>
        <p>${escapeHTML(desc)}</p>
      </div>
      <em>${count}</em>
    </article>
  `).join("");

  $("growthLedger").innerHTML = renderGrowthLedger(ledgerRows);
  $("growthDrafts").innerHTML = renderDraftPack(data.drafts || []);
  const referenceCards = [
    ...listByDate(data.references, 4).map((item) => renderCompactGrowthCard(item, "参考")),
    ...listByDate(data.weekly, 3).map((item) => renderCompactGrowthCard(item, "周报")),
  ].join("");
  $("growthReferences").innerHTML = referenceCards || '<div class="empty-state">暂无素材或周报</div>';
}

function growthLedgerRows(data) {
  const mapItem = (stage, item) => ({
    stage,
    title: item.data?.title || item.id,
    status: item.data?.status || "",
    pillar: item.data?.pillar || "",
    date: item.data?.publish_at || item.data?.date || "",
    keywords: [...(item.data?.keywords || []), ...(item.data?.tags || [])],
    source: item.path,
    excerpt: item.excerpt,
  });
  return [
    ...(data.references || []).map((item) => mapItem("调研", item)),
    ...(data.topics || []).map((item) => mapItem("选题", item)),
    ...(data.drafts || []).map((item) => mapItem("生产", item)),
    ...(data.published || []).map((item) => mapItem("发布", item)),
    ...(data.weekly || []).map((item) => mapItem("复盘", item)),
  ].sort((a, b) => String(b.date).localeCompare(String(a.date)));
}

function renderGrowthLedger(rows) {
  if (!rows.length) return '<div class="empty-state">暂无运营内容</div>';
  return `
    <table class="growth-table">
      <thead>
        <tr>
          <th>阶段</th>
          <th>标题 / 摘要</th>
          <th>支柱</th>
          <th>状态</th>
          <th>时间</th>
          <th>关键词</th>
          <th>文件</th>
        </tr>
      </thead>
      <tbody>
        ${rows.map((row) => `
          <tr>
            <td><span class="stage-chip">${escapeHTML(row.stage)}</span></td>
            <td>
              <strong>${escapeHTML(row.title)}</strong>
              <small>${escapeHTML(compact(row.excerpt, "暂无摘要"))}</small>
            </td>
            <td>${row.pillar ? `<span class="pill ok">${escapeHTML(row.pillar)}</span>` : ""}</td>
            <td><span class="status-dot ${escapeHTML(row.status)}"></span>${escapeHTML(row.status || "n/a")}</td>
            <td><code>${escapeHTML(row.date || "-")}</code></td>
            <td>
              <div class="keyword-line">
                ${row.keywords.slice(0, 4).map((tag) => `<span>${escapeHTML(tag)}</span>`).join("")}
              </div>
            </td>
            <td><code class="path-code">${escapeHTML(row.source)}</code></td>
          </tr>
        `).join("")}
      </tbody>
    </table>
  `;
}

function renderDraftPack(items) {
  const draft = items.find((item) => item.data?.status === "ready") || items[0];
  if (!draft) return '<div class="empty-state">暂无草稿</div>';
  const assets = draft.data?.assets || [];
  const tags = draft.data?.tags || [];
  const publishText = `${draft.data?.title || ""}\n\n${draft.excerpt || ""}\n\n${tags.map((tag) => `#${tag}`).join(" ")}`;
  return `
    <article class="publish-card">
      <div class="growth-card-head">
        <span class="pill ${draft.data?.status === "ready" ? "ok" : ""}">${escapeHTML(draft.data?.status || "draft")}</span>
        <span>${escapeHTML(draft.data?.publish_at || draft.data?.date || "")}</span>
      </div>
      <h3>${escapeHTML(draft.data?.title || draft.id)}</h3>
      <textarea readonly>${escapeHTML(`${draft.excerpt || ""}\n\n${tags.map((tag) => `#${tag}`).join(" ")}`)}</textarea>
      <button class="copy-button growth-copy" type="button" data-copy="${escapeHTML(publishText)}">复制标题 + 正文 + 标签</button>
      <div class="asset-stack">
        ${assets.length ? assets.map((asset) => `<code>${escapeHTML(asset)}</code>`).join("") : "<span>暂无图片资产</span>"}
      </div>
    </article>
  `;
}

function renderCompactGrowthCard(item, label) {
  const tags = [...(item.data?.keywords || []), ...(item.data?.tags || [])].slice(0, 3);
  return `
    <article class="growth-mini-card">
      <div class="growth-card-head">
        <span class="pill">${escapeHTML(label)}</span>
        <span>${escapeHTML(item.data?.date || "")}</span>
      </div>
      <strong>${escapeHTML(item.data?.title || item.id)}</strong>
      <p>${escapeHTML(compact(item.excerpt || item.data?.hook || item.path, item.path))}</p>
      <div class="keyword-line">
        ${tags.map((tag) => `<span>${escapeHTML(tag)}</span>`).join("")}
      </div>
    </article>
  `;
}

async function saveGrowthDraft() {
  const title = window.prompt("新草稿标题");
  if (!title || !title.trim()) return;
  try {
    await requestJSON("/dashboard/api/growth/content", {
      method: "POST",
      body: JSON.stringify({
        type: "drafts",
        title: title.trim(),
        status: "drafting",
        pillar: "生活记录方法",
        tags: ["生活记录", "LifeOS"],
        keywords: ["生活记录"],
        body: "## 正文\n\n先写一个真实场景。\n\n## 发布检查\n\n- 标题含关键词\n- 发布前人工审核\n",
      }),
      _retries: 1,
    });
    state.growthLoadedFor = null;
    await loadGrowth();
  } catch (error) {
    $("growthDrafts").innerHTML = `<div class="empty-state">保存失败：${escapeHTML(error.message)}</div>`;
  }
}

async function copyGrowthPack(event) {
  const button = event.target.closest(".growth-copy");
  if (!button) return;
  await navigator.clipboard.writeText(button.dataset.copy || "");
  button.textContent = "已复制";
  setTimeout(() => { button.textContent = "复制发布包"; }, 1200);
}

function bindEvents() {
  $("startDateInput").value = todayKey();
  $("endDateInput").value = todayKey();
  $("loginForm").addEventListener("submit", login);
  $("logoutButton").addEventListener("click", logout);
  $("refreshButton").addEventListener("click", () => loadCurrentView());
  $("traceFilters").addEventListener("submit", (event) => {
    event.preventDefault();
    loadCurrentView();
  });
  $("copyJsonButton").addEventListener("click", copyJSON);
  $("newGrowthDraftButton").addEventListener("click", saveGrowthDraft);
  $("growthPage").addEventListener("click", copyGrowthPack);
  document.querySelectorAll(".view-tab").forEach((button) => {
    button.addEventListener("click", () => setView(button.dataset.view));
  });
  window.addEventListener("hashchange", () => setView(viewFromHash(), { updateHash: false }));
  // 切日期 / 切来源 / 切错误过滤 → 重置增量状态，全量加载
  ["startDateInput", "endDateInput", "sourceInput", "errorsOnlyInput"].forEach((id) => {
    $(id).addEventListener("change", () => {
      state.lastReceivedAt = null;
      state.currentDate = null;
      state.usageLoadedFor = null;
      state.growthLoadedFor = null;
      loadCurrentView();
    });
  });
}

bindEvents();

loadSession().catch((error) => {
  $("loginPanel").hidden = false;
  $("appPanel").hidden = true;
  $("loginMessage").textContent = `连接失败：${error.message}`;
});
