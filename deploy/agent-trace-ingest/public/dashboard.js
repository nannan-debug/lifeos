const state = {
  traces: [],
  events: [],
  selectedTraceId: null,
  selectedEventId: null,
  selectedEvent: null,
};

const $ = (id) => document.getElementById(id);

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

async function requestJSON(url, options = {}) {
  const response = await fetch(url, {
    ...options,
    headers: {
      "Content-Type": "application/json",
      ...(options.headers || {}),
    },
  });
  const body = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(body.error || `HTTP ${response.status}`);
  }
  return body;
}

async function loadSession() {
  const session = await requestJSON("/dashboard/api/session");
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
    await loadTraces();
  }
}

function queryURL() {
  const params = new URLSearchParams();
  params.set("date", $("dateInput").value || todayKey());
  params.set("limit", "500");
  params.set("summaryOnly", "1");
  const q = $("searchInput").value.trim();
  const traceId = $("traceInput").value.trim();
  const source = $("sourceInput").value;
  if (q) params.set("q", q);
  if (traceId) params.set("traceId", traceId);
  if (source !== "all") params.set("source", source);
  if ($("errorsOnlyInput").checked) params.set("errorsOnly", "1");
  return `/dashboard/api/traces?${params}`;
}

async function loadTraces() {
  setBusy(true, "查询中...");
  try {
    setLoading("正在读取 trace 摘要...");
    const body = await requestJSON(queryURL());
    state.traces = body.traces || [];
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
    showError(error);
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
  const params = new URLSearchParams();
  params.set("date", $("dateInput").value || todayKey());
  params.set("traceId", state.selectedTraceId);
  params.set("limit", "1000");
  const body = await requestJSON(`/dashboard/api/traces?${params}`);
  state.events = (body.events || []).map((event, index) => ({ ...event, __id: eventId(event, index) }));
  if (!state.events.some((event) => event.__id === state.selectedEventId)) {
    state.selectedEvent = state.events[0] || null;
    state.selectedEventId = state.selectedEvent?.__id || null;
  }
  renderTimeline();
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
          <span>${escapeHTML(event.eventName)}</span>
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
    $("jsonView").innerHTML = "";
    return;
  }
  $("eventSummary").className = "event-summary";
  $("eventSummary").innerHTML = `
    <div class="metric-grid">
      <div class="metric"><span>Event</span><strong>${escapeHTML(event.eventName)}</strong></div>
      <div class="metric"><span>Source</span><strong>${escapeHTML(event.source)}</strong></div>
      <div class="metric"><span>Latency</span><strong>${event.latencyMs ? formatLatency(event.latencyMs) : "n/a"}</strong></div>
      <div class="metric"><span>Tokens</span><strong>${escapeHTML(event.usage?.total_tokens || event.usage?.totalTokens || "n/a")}</strong></div>
    </div>
    ${event.error ? `<div class="pill error">${escapeHTML(event.error.type || "error")}: ${escapeHTML(event.error.message)}</div>` : ""}
  `;
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
    });
    await loadSession();
  } catch (error) {
    $("loginMessage").textContent = error.message === "invalid_credentials" ? "账户或密码不对。" : error.message;
  }
}

async function logout() {
  await requestJSON("/dashboard/api/logout", { method: "POST", body: "{}" });
  state.traces = [];
  state.events = [];
  state.selectedTraceId = null;
  state.selectedEvent = null;
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

function bindEvents() {
  $("dateInput").value = todayKey();
  $("loginForm").addEventListener("submit", login);
  $("logoutButton").addEventListener("click", logout);
  $("refreshButton").addEventListener("click", loadTraces);
  $("traceFilters").addEventListener("submit", (event) => {
    event.preventDefault();
    loadTraces();
  });
  $("copyJsonButton").addEventListener("click", copyJSON);
  ["dateInput", "sourceInput", "errorsOnlyInput"].forEach((id) => $(id).addEventListener("change", loadTraces));
}

bindEvents();
function showError(error) {
  $("timeline").className = "timeline empty-state";
  $("timeline").textContent = `读取失败：${error.message}`;
}

loadSession().catch((error) => {
  $("loginPanel").hidden = false;
  $("appPanel").hidden = true;
  $("loginMessage").textContent = error.message;
});
