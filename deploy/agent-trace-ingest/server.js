import http from "node:http";
import { promises as fs } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import crypto from "node:crypto";
import { createGzip } from "node:zlib";
import { pipeline } from "node:stream/promises";
import { createReadStream, createWriteStream } from "node:fs";

const DEFAULT_PORT = 8787;
const MAX_BODY_BYTES = 2 * 1024 * 1024;
const TOKEN_HEADER = "x-lifeos-trace-token";
const DASHBOARD_COOKIE = "lifeos_trace_session";
const DASHBOARD_SESSION_TTL_MS = 1000 * 60 * 60 * 12;
const CACHE_TTL_MS = 5000; // 5 秒缓存，避免同一秒内重复读磁盘

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const publicDir = path.join(__dirname, "public");

export function createTraceServer(options = {}) {
  const traceDir = options.traceDir || process.env.TRACE_DIR || "/var/lib/lifeos-traces";
  const traceToken = options.traceToken ?? process.env.TRACE_TOKEN ?? "";
  const dashboardUser = options.dashboardUser ?? process.env.DASHBOARD_USER ?? "";
  const dashboardPassword = options.dashboardPassword ?? process.env.DASHBOARD_PASSWORD ?? "";
  const dashboardSecret = options.dashboardSecret ?? process.env.DASHBOARD_SESSION_SECRET ?? traceToken;

  // ── 内存缓存：{ day -> { events, mtime, cachedAt } } ──
  const dayCache = new Map();

  async function cachedReadDay(day) {
    const file = path.join(traceDir, `${day}.jsonl`);
    const now = Date.now();
    const cached = dayCache.get(day);

    // 快路径：缓存未过期直接返回
    if (cached && now - cached.cachedAt < CACHE_TTL_MS) {
      return cached.events;
    }

    // 检查文件是否有变化（stat 比 readFile 轻量得多）
    let stat;
    try {
      stat = await fs.stat(file);
    } catch (err) {
      if (err.code === "ENOENT") {
        dayCache.set(day, { events: [], mtime: 0, cachedAt: now });
        return [];
      }
      throw err;
    }
    const mtime = stat.mtimeMs;

    // 文件没变 → 刷新 cachedAt 直接返回
    if (cached && cached.mtime === mtime) {
      cached.cachedAt = now;
      return cached.events;
    }

    // 读文件 + 解析
    const raw = await fs.readFile(file, "utf8");
    const events = [];
    for (const line of raw.split("\n")) {
      if (!line) continue;
      try {
        events.push(JSON.parse(line));
      } catch {
        // 跳过损坏行，不炸掉整个请求
        console.warn(`[warn] corrupt line in ${day}.jsonl, skipped`);
      }
    }

    dayCache.set(day, { events, mtime, cachedAt: now });

    // 只保留最近 7 天缓存，防内存泄漏
    if (dayCache.size > 7) {
      const oldest = [...dayCache.keys()].sort()[0];
      dayCache.delete(oldest);
    }

    return events;
  }

  // 写入后让缓存失效
  function invalidateCache(day) {
    dayCache.delete(day);
  }

  async function writeJSON(res, status, payload) {
    if (res.writableEnded) return;
    const body = JSON.stringify(payload);
    try {
      res.writeHead(status, {
        "Content-Type": "application/json; charset=utf-8",
        "Content-Length": Buffer.byteLength(body),
      });
      res.end(body);
    } catch (_) { /* client already disconnected */ }
  }

  function isAuthorized(req) {
    return Boolean(traceToken) && req.headers[TOKEN_HEADER] === traceToken;
  }

  function isDashboardEnabled() {
    return Boolean(dashboardUser && dashboardPassword && dashboardSecret);
  }

  function timingSafeEqualText(a, b) {
    const left = Buffer.from(String(a));
    const right = Buffer.from(String(b));
    if (left.length !== right.length) return false;
    return crypto.timingSafeEqual(left, right);
  }

  function parseCookies(req) {
    const header = req.headers.cookie || "";
    return Object.fromEntries(header
      .split(";")
      .map((part) => part.trim())
      .filter(Boolean)
      .map((part) => {
        const index = part.indexOf("=");
        if (index === -1) return [part, ""];
        return [part.slice(0, index), decodeURIComponent(part.slice(index + 1))];
      }));
  }

  function signSession(payload) {
    const body = Buffer.from(JSON.stringify(payload)).toString("base64url");
    const signature = crypto
      .createHmac("sha256", dashboardSecret)
      .update(body)
      .digest("base64url");
    return `${body}.${signature}`;
  }

  function verifySession(token) {
    if (!token || !isDashboardEnabled()) return false;
    const [body, signature] = token.split(".");
    if (!body || !signature) return false;
    const expected = crypto
      .createHmac("sha256", dashboardSecret)
      .update(body)
      .digest("base64url");
    if (!timingSafeEqualText(signature, expected)) return false;
    try {
      const payload = JSON.parse(Buffer.from(body, "base64url").toString("utf8"));
      return payload.user === dashboardUser && Number(payload.exp) > Date.now();
    } catch {
      return false;
    }
  }

  function isDashboardAuthorized(req) {
    return verifySession(parseCookies(req)[DASHBOARD_COOKIE]);
  }

  function setDashboardCookie(res, token) {
    const attrs = [
      `${DASHBOARD_COOKIE}=${encodeURIComponent(token)}`,
      "Path=/dashboard",
      "HttpOnly",
      "SameSite=Lax",
      "Max-Age=43200",
    ];
    res.setHeader("Set-Cookie", attrs.join("; "));
  }

  function clearDashboardCookie(res) {
    res.setHeader("Set-Cookie", `${DASHBOARD_COOKIE}=; Path=/dashboard; HttpOnly; SameSite=Lax; Max-Age=0`);
  }

  async function readJSONBody(req) {
    let size = 0;
    const chunks = [];
    for await (const chunk of req) {
      size += chunk.length;
      if (size > MAX_BODY_BYTES) {
        const err = new Error("request_too_large");
        err.status = 413;
        throw err;
      }
      chunks.push(chunk);
    }
    if (chunks.length === 0) return null;
    try {
      return JSON.parse(Buffer.concat(chunks).toString("utf8"));
    } catch {
      const err = new Error("invalid_json");
      err.status = 400;
      throw err;
    }
  }

  function normalizeEvent(event) {
    if (!event || typeof event !== "object" || Array.isArray(event)) {
      const err = new Error("event_must_be_object");
      err.status = 400;
      throw err;
    }
    const traceId = String(event.traceId || "").trim();
    const eventName = String(event.eventName || "").trim();
    const source = String(event.source || "").trim();
    if (!traceId || !eventName || !source) {
      const err = new Error("missing_required_fields");
      err.status = 400;
      throw err;
    }
    const timestamp = event.timestamp || new Date().toISOString();
    return {
      receivedAt: new Date().toISOString(),
      ...event,
      traceId,
      eventName,
      source,
      timestamp,
    };
  }

  function dayKeyFromTimestamp(timestamp) {
    const value = String(timestamp || "");
    if (/^\d{4}-\d{2}-\d{2}/.test(value)) return value.slice(0, 10);
    return new Date().toISOString().slice(0, 10);
  }

  async function appendEvent(event) {
    const normalized = normalizeEvent(event);
    const day = dayKeyFromTimestamp(normalized.timestamp);
    await fs.mkdir(traceDir, { recursive: true });
    const file = path.join(traceDir, `${day}.jsonl`);
    await fs.appendFile(file, `${JSON.stringify(normalized)}\n`, "utf8");
    invalidateCache(day);
    return normalized;
  }

  function dateRange(query) {
    const startDate = String(query.get("startDate") || query.get("date") || new Date().toISOString().slice(0, 10));
    const endDate = String(query.get("endDate") || startDate);
    const datePattern = /^\d{4}-\d{2}-\d{2}$/;
    if (!datePattern.test(startDate) || !datePattern.test(endDate)) {
      const err = new Error("invalid_date");
      err.status = 400;
      throw err;
    }
    const days = [];
    let cursor = startDate;
    while (cursor <= endDate && days.length <= 31) {
      days.push(cursor);
      const d = new Date(cursor + "T00:00:00Z");
      d.setUTCDate(d.getUTCDate() + 1);
      cursor = d.toISOString().slice(0, 10);
    }
    return days;
  }

  async function listEvents(query) {
    const days = dateRange(query);
    const traceId = String(query.get("traceId") || "").trim();
    const since = String(query.get("since") || "").trim();
    const limit = Math.min(Number(query.get("limit") || 200), 2000);
    const chunks = await Promise.all(days.map((d) => cachedReadDay(d).catch(() => [])));
    const allEvents = chunks.flat();
    return allEvents
      .filter((event) => !traceId || event.traceId === traceId)
      .filter((event) => !since || (event.receivedAt || "") > since)
      .slice(-limit);
  }

  function eventSearchBlob(event) {
    return [
      event.traceId,
      event.sessionId,
      event.threadId,
      event.eventName,
      event.source,
      event.error?.message,
      event.payload?.input,
      event.payload?.reply,
      event.payload?.rawModelOutput,
    ].filter(Boolean).join(" ").toLowerCase();
  }

  const MODE_LABELS = { utility: "工具", chat: "对话", quick: "快录", parse: "解析" };
  const TASK_LABELS = { extract_memories: "提取记忆", suggest_topics: "推荐话题", suggest_title: "生成标题" };
  function modeTitle(events) {
    const modeEv = events.find((e) => e.mode || e.payload?.mode);
    if (!modeEv) return "";
    const mode = modeEv.mode || modeEv.payload?.mode || "";
    const taskEv = events.find((e) => e.task || e.payload?.task);
    const task = taskEv?.task || taskEv?.payload?.task || "";
    const modeLabel = MODE_LABELS[mode] || mode;
    const taskLabel = TASK_LABELS[task] || task;
    return taskLabel ? `[${modeLabel}] ${taskLabel}` : `[${modeLabel}]`;
  }

  const IOS_EVENT_LABELS = {
    action_auto_confirmed: "自动保存",
    action_confirmed: "手动确认",
    action_dismissed: "取消建议",
    action_auto_undo: "撤销保存",
  };
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

  function usageTitle(events) {
    const ev = events.find((e) => e.eventName === "usage_batch");
    if (!ev) return "";
    const items = Object.entries(ev.payload || {})
      .map(([key, value]) => [USAGE_LABELS[key] || key, Number(value) || 0])
      .filter(([, count]) => count > 0)
      .sort((a, b) => b[1] - a[1])
      .slice(0, 3)
      .map(([label, count]) => `${label} ${count}`);
    return items.length ? `使用统计：${items.join("、")}` : "使用统计";
  }

  function iosActionTitle(events) {
    const ev = events.find((e) => IOS_EVENT_LABELS[e.eventName]);
    if (!ev) return "";
    const label = IOS_EVENT_LABELS[ev.eventName];
    const result = ev.payload?.result || "";
    return result ? `${result}` : label;
  }

  function summarizeTrace(traceId, events) {
    const sorted = [...events].sort((a, b) => String(a.timestamp || "").localeCompare(String(b.timestamp || "")));
    const first = sorted[0] || {};
    const last = sorted[sorted.length - 1] || {};
    const errorEvent = sorted.find((event) => event.error);
    const inputEvent = sorted.find((event) => event.payload?.input);
    const responseEvent = [...sorted].reverse().find((event) => event.payload?.reply || event.payload?.rawModelOutput);
    const totalLatency = sorted.reduce((sum, event) => sum + (Number(event.latencyMs) || 0), 0);
    const usage = sorted.reduce((acc, event) => {
      acc.promptTokens += Number(event.usage?.prompt_tokens || event.usage?.promptTokens || 0);
      acc.completionTokens += Number(event.usage?.completion_tokens || event.usage?.completionTokens || 0);
      acc.totalTokens += Number(event.usage?.total_tokens || event.usage?.totalTokens || 0);
      return acc;
    }, { promptTokens: 0, completionTokens: 0, totalTokens: 0 });
    return {
      traceId,
      eventCount: sorted.length,
      firstAt: first.timestamp || first.receivedAt || "",
      lastAt: last.timestamp || last.receivedAt || "",
      sources: [...new Set(sorted.map((event) => event.source).filter(Boolean))],
      hasError: Boolean(errorEvent),
      status: errorEvent ? "error" : "ok",
      title: inputEvent?.payload?.input || responseEvent?.payload?.reply || usageTitle(sorted) || modeTitle(sorted) || iosActionTitle(sorted) || traceId,
      lastEventName: last.eventName || "",
      latencyMs: totalLatency || null,
      usage,
    };
  }

  async function usageReport(query) {
    const days = dateRange(query);
    const chunks = await Promise.all(days.map((d) => cachedReadDay(d).catch(() => [])));
    const allEvents = chunks.flat().filter((e) => e.eventName === "usage_batch");

    const userMap = new Map();   // sessionId → { events, lastSeen }
    const dailyMap = new Map();  // date → { events, users }
    const featureTotals = {};

    for (const event of allEvents) {
      const sid = event.sessionId || "unknown";
      const date = (event.timestamp || event.receivedAt || "").slice(0, 10);
      const payload = event.payload || {};

      // Per-user aggregation
      if (!userMap.has(sid)) userMap.set(sid, { events: {}, totalEvents: 0, lastSeen: "" });
      const user = userMap.get(sid);
      if (date > user.lastSeen) user.lastSeen = date;

      // Per-day aggregation
      if (!dailyMap.has(date)) dailyMap.set(date, { totalEvents: 0, users: new Set() });
      const day = dailyMap.get(date);
      day.users.add(sid);

      for (const [key, val] of Object.entries(payload)) {
        const count = Number(val) || 0;
        user.events[key] = (user.events[key] || 0) + count;
        user.totalEvents += count;
        featureTotals[key] = (featureTotals[key] || 0) + count;
        day.totalEvents += count;
      }
    }

    const users = [...userMap.entries()]
      .map(([sessionId, data]) => ({
        sessionId,
        shortId: sessionId.replace(/^dev-/, "").slice(0, 6).toUpperCase(),
        events: data.events,
        totalEvents: data.totalEvents,
        lastSeen: data.lastSeen,
      }))
      .sort((a, b) => b.totalEvents - a.totalEvents);

    const daily = [...dailyMap.entries()]
      .map(([date, data]) => ({ date, totalEvents: data.totalEvents, activeUsers: data.users.size }))
      .sort((a, b) => a.date.localeCompare(b.date));

    const totalEvents = users.reduce((sum, u) => sum + u.totalEvents, 0);

    return { totalUsers: users.length, totalEvents, users, daily, featureTotals };
  }

  async function dashboardEvents(query) {
    const allEvents = await listEvents(query);
    const source = String(query.get("source") || "").trim();
    const search = String(query.get("q") || "").trim().toLowerCase();
    const kind = String(query.get("kind") || "all").trim();
    const errorsOnly = query.get("errorsOnly") === "1";
    const hasFilters = Boolean((source && source !== "all") || search || errorsOnly);
    let matchingEvents = allEvents;
    if (source && source !== "all") {
      matchingEvents = matchingEvents.filter((event) => event.source === source);
    }
    if (errorsOnly) {
      matchingEvents = matchingEvents.filter((event) => Boolean(event.error));
    }
    if (search) {
      matchingEvents = matchingEvents.filter((event) => eventSearchBlob(event).includes(search));
    }
    const matchingTraceIds = new Set(matchingEvents.map((event) => event.traceId));
    let events = hasFilters ? allEvents.filter((event) => matchingTraceIds.has(event.traceId)) : allEvents;
    events = events.sort((a, b) => String(a.timestamp || a.receivedAt || "").localeCompare(String(b.timestamp || b.receivedAt || "")));
    const traceMap = new Map();
    for (const event of events) {
      const list = traceMap.get(event.traceId) || [];
      list.push(event);
      traceMap.set(event.traceId, list);
    }
    const filteredTraceEntries = [...traceMap.entries()].filter(([traceId, traceEvents]) => {
      const isUsageTrace = traceId.startsWith("usage-")
        || traceEvents.some((event) => event.eventName === "usage_batch");
      if (kind === "ai") return !isUsageTrace;
      if (kind === "usage") return isUsageTrace;
      return true;
    });
    const traces = filteredTraceEntries
      .map(([traceId, traceEvents]) => summarizeTrace(traceId, traceEvents))
      .sort((a, b) => String(b.lastAt).localeCompare(String(a.lastAt)));
    if (query.get("summaryOnly") === "1") {
      return { events: [], traces };
    }
    const visibleTraceIds = new Set(filteredTraceEntries.map(([traceId]) => traceId));
    return { events: events.filter((event) => visibleTraceIds.has(event.traceId)), traces };
  }

  // ── 静态文件缓存 ──
  const staticCache = new Map();

  async function serveStatic(res, filePath, contentType) {
    try {
      const now = Date.now();
      let cached = staticCache.get(filePath);
      if (!cached || now - cached.cachedAt > 30000) {
        const data = await fs.readFile(filePath);
        cached = { data, cachedAt: now };
        staticCache.set(filePath, cached);
      }
      res.writeHead(200, {
        "Content-Type": contentType,
        "Cache-Control": "no-store",
      });
      res.end(cached.data);
    } catch {
      await writeJSON(res, 404, { error: "not_found" });
    }
  }

  async function gzipDay(date) {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) {
      const err = new Error("invalid_date");
      err.status = 400;
      throw err;
    }
    const file = path.join(traceDir, `${date}.jsonl`);
    const gzFile = `${file}.gz`;
    await fs.access(file);
    await pipeline(createReadStream(file), createGzip(), createWriteStream(gzFile));
    return gzFile;
  }

  const server = http.createServer(async (req, res) => {
    // 30s 请求超时，防止连接挂起
    req.setTimeout(30000);
    res.setTimeout(30000);
    try {
      const url = new URL(req.url || "/", "http://localhost");

      if (req.method === "GET" && url.pathname === "/health") {
        await writeJSON(res, 200, { ok: true, cacheSize: dayCache.size });
        return;
      }

      if (url.pathname === "/dashboard" || url.pathname === "/dashboard/") {
        await serveStatic(res, path.join(publicDir, "dashboard.html"), "text/html; charset=utf-8");
        return;
      }

      if (req.method === "GET" && url.pathname === "/dashboard/dashboard.css") {
        await serveStatic(res, path.join(publicDir, "dashboard.css"), "text/css; charset=utf-8");
        return;
      }

      if (req.method === "GET" && url.pathname === "/dashboard/dashboard.js") {
        await serveStatic(res, path.join(publicDir, "dashboard.js"), "application/javascript; charset=utf-8");
        return;
      }

      if (req.method === "GET" && url.pathname === "/dashboard/api/session") {
        await writeJSON(res, 200, {
          ok: true,
          enabled: isDashboardEnabled(),
          authenticated: isDashboardAuthorized(req),
          user: isDashboardAuthorized(req) ? dashboardUser : null,
        });
        return;
      }

      if (req.method === "POST" && url.pathname === "/dashboard/api/login") {
        if (!isDashboardEnabled()) {
          await writeJSON(res, 503, { error: "dashboard_not_configured" });
          return;
        }
        const body = await readJSONBody(req);
        const user = String(body?.user || "");
        const password = String(body?.password || "");
        if (!timingSafeEqualText(user, dashboardUser) || !timingSafeEqualText(password, dashboardPassword)) {
          await writeJSON(res, 401, { error: "invalid_credentials" });
          return;
        }
        setDashboardCookie(res, signSession({ user, exp: Date.now() + DASHBOARD_SESSION_TTL_MS }));
        await writeJSON(res, 200, { ok: true, user });
        return;
      }

      if (req.method === "POST" && url.pathname === "/dashboard/api/logout") {
        clearDashboardCookie(res);
        await writeJSON(res, 200, { ok: true });
        return;
      }

      if (req.method === "GET" && url.pathname === "/dashboard/api/traces") {
        if (!isDashboardAuthorized(req)) {
          await writeJSON(res, 401, { error: "unauthorized" });
          return;
        }
        const data = await dashboardEvents(url.searchParams);
        await writeJSON(res, 200, { ok: true, ...data });
        return;
      }

      if (req.method === "GET" && url.pathname === "/dashboard/api/usage") {
        if (!isDashboardAuthorized(req)) {
          await writeJSON(res, 401, { error: "unauthorized" });
          return;
        }
        const data = await usageReport(url.searchParams);
        await writeJSON(res, 200, { ok: true, ...data });
        return;
      }

      if (!isAuthorized(req)) {
        await writeJSON(res, 401, { error: "unauthorized" });
        return;
      }

      if (req.method === "POST" && url.pathname === "/v1/traces/events") {
        const body = await readJSONBody(req);
        const events = Array.isArray(body?.events) ? body.events : [body];
        const written = [];
        for (const event of events) {
          written.push(await appendEvent(event));
        }
        await writeJSON(res, 200, { ok: true, written: written.length });
        return;
      }

      if (req.method === "GET" && url.pathname === "/v1/traces/events") {
        const events = await listEvents(url.searchParams);
        await writeJSON(res, 200, { ok: true, events });
        return;
      }

      if (req.method === "POST" && url.pathname === "/v1/traces/gzip") {
        const body = await readJSONBody(req);
        const gzFile = await gzipDay(String(body?.date || ""));
        await writeJSON(res, 200, { ok: true, file: path.basename(gzFile) });
        return;
      }

      await writeJSON(res, 404, { error: "not_found" });
    } catch (err) {
      console.error(`[${new Date().toISOString()}] ${req.method} ${req.url} → ${err.status || 500} ${err.message}`);
      await writeJSON(res, err.status || 500, {
        error: err.message || "internal_error",
      });
    }
  });

  return { server, appendEvent, listEvents };
}

if (process.argv[1] === __filename) {
  const port = Number(process.env.PORT || DEFAULT_PORT);
  const { server } = createTraceServer();

  process.on("uncaughtException", (err) => {
    console.error("[uncaughtException]", err);
  });
  process.on("unhandledRejection", (reason) => {
    console.error("[unhandledRejection]", reason);
  });
  server.on("error", (err) => {
    console.error("[server error]", err);
  });

  server.keepAliveTimeout = 65000;   // 比 nginx 的 60s 长一点
  server.headersTimeout = 70000;

  server.listen(port, "0.0.0.0", () => {
    console.log(`lifeos-agent-trace-ingest listening on :${port}`);
  });
}
