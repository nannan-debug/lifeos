import http from "node:http";
import { promises as fs } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import crypto from "node:crypto";
import { createGzip } from "node:zlib";
import { pipeline } from "node:stream/promises";
import { createReadStream, createWriteStream } from "node:fs";
import { execFile } from "node:child_process";

const DEFAULT_PORT = 8787;
const MAX_BODY_BYTES = 2 * 1024 * 1024;
const TOKEN_HEADER = "x-lifeos-trace-token";
const DASHBOARD_COOKIE = "lifeos_trace_session";
const DASHBOARD_SESSION_TTL_MS = 1000 * 60 * 60 * 12;
const CACHE_TTL_MS = 5000; // 5 秒缓存，避免同一秒内重复读磁盘

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const publicDir = path.join(__dirname, "public");
const repoRoot = path.resolve(__dirname, "../..");
const DEFAULT_GROWTH_DIR = path.join(repoRoot, "docs/operations/growth/xiaohongshu");

const GROWTH_TYPES = {
  references: "references",
  topics: "topics",
  drafts: "drafts",
  published: "published",
  weekly: "analytics/weekly",
};

const XHS_CLI = process.env.XHS_CLI_PATH || "/home/ubuntu/.local/bin/xhs";
const XHS_IMAGE_DIR_NAME = "xhs-images";

export function createTraceServer(options = {}) {
  const traceDir = options.traceDir || process.env.TRACE_DIR || "/var/lib/lifeos-traces";
  const growthDir = options.growthDir || process.env.GROWTH_DIR || DEFAULT_GROWTH_DIR;
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

  function parseFrontmatter(text) {
    if (!text.startsWith("---\n")) return { data: {}, body: text };
    const end = text.indexOf("\n---", 4);
    if (end === -1) return { data: {}, body: text };
    const raw = text.slice(4, end).trim();
    const body = text.slice(end + 4).replace(/^\n/, "");
    const data = {};
    let currentArrayKey = null;
    for (const line of raw.split("\n")) {
      const arrayItem = line.match(/^\s*-\s+(.*)$/);
      if (arrayItem && currentArrayKey) {
        data[currentArrayKey].push(coerceScalar(arrayItem[1]));
        continue;
      }
      currentArrayKey = null;
      const match = line.match(/^([A-Za-z0-9_-]+):\s*(.*)$/);
      if (!match) continue;
      const [, key, value] = match;
      if (value === "" || value === "[]") {
        data[key] = [];
        if (value === "") currentArrayKey = key;
      } else if (value.startsWith("[") && value.endsWith("]")) {
        data[key] = value.slice(1, -1).split(",").map((item) => coerceScalar(item.trim())).filter(Boolean);
      } else {
        data[key] = coerceScalar(value);
      }
    }
    return { data, body };
  }

  function serializeFrontmatter(data, body = "") {
    const lines = Object.entries(data).map(([key, value]) => {
      if (Array.isArray(value)) {
        if (value.length === 0) return `${key}: []\n`;
        return `${key}:\n${value.map((item) => `  - ${escapeYamlScalar(item)}`).join("\n")}\n`;
      }
      if (value && typeof value === "object") return `${key}: ${JSON.stringify(value)}\n`;
      return `${key}: ${escapeYamlScalar(value)}\n`;
    }).join("");
    return `---\n${lines}---\n\n${String(body || "").trim()}\n`;
  }

  function coerceScalar(value) {
    const text = String(value ?? "").replace(/^"|"$/g, "");
    if (text === "true") return true;
    if (text === "false") return false;
    if (/^-?\d+(\.\d+)?$/.test(text)) return Number(text);
    return text;
  }

  function escapeYamlScalar(value) {
    if (value === null || value === undefined) return "";
    if (typeof value === "number" || typeof value === "boolean") return String(value);
    const text = String(value);
    return /[:\[\],{}#\n]/.test(text) ? JSON.stringify(text) : text;
  }

  function slugify(input) {
    return String(input || "untitled")
      .trim()
      .toLowerCase()
      .replace(/[^\p{L}\p{N}]+/gu, "-")
      .replace(/^-+|-+$/g, "")
      .slice(0, 80) || "untitled";
  }

  function growthTypePath(type) {
    const folder = GROWTH_TYPES[type];
    if (!folder) {
      const err = new Error("invalid_growth_type");
      err.status = 400;
      throw err;
    }
    return path.join(growthDir, folder);
  }

  async function walkMarkdown(dir) {
    try {
      const entries = await fs.readdir(dir, { withFileTypes: true });
      const files = await Promise.all(entries.map((entry) => {
        const full = path.join(dir, entry.name);
        if (entry.isDirectory()) return walkMarkdown(full);
        return entry.name.endsWith(".md") && entry.name.toLowerCase() !== "readme.md" ? [full] : [];
      }));
      return files.flat();
    } catch {
      return [];
    }
  }

  async function listGrowthContent(type) {
    const base = growthTypePath(type);
    const files = await walkMarkdown(base);
    const items = await Promise.all(files.map(async (file) => {
      const text = await fs.readFile(file, "utf8");
      const { data, body } = parseFrontmatter(text);
      return {
        id: path.relative(base, file).replace(/\.md$/, ""),
        type,
        path: path.relative(growthDir, file),
        data,
        excerpt: body.trim().split("\n").find(Boolean) || "",
      };
    }));
    return items.sort((a, b) => String(b.data.updated_at || b.data.date || "").localeCompare(String(a.data.updated_at || a.data.date || "")));
  }

  async function growthOverview() {
    await fs.mkdir(growthDir, { recursive: true });
    for (const folder of Object.values(GROWTH_TYPES)) {
      await fs.mkdir(path.join(growthDir, folder), { recursive: true });
    }
    const [references, topics, drafts, published, weekly] = await Promise.all([
      listGrowthContent("references"),
      listGrowthContent("topics"),
      listGrowthContent("drafts"),
      listGrowthContent("published"),
      listGrowthContent("weekly"),
    ]);
    return {
      root: growthDir,
      references,
      topics,
      drafts,
      published,
      weekly,
      counts: {
        references: references.length,
        topics: topics.length,
        drafts: drafts.length,
        readyDrafts: drafts.filter((item) => item.data.status === "ready").length,
        published: published.length,
        needsReview: published.filter((item) => item.data.status !== "reviewed").length,
      },
    };
  }

  function resolveGrowthFile(type, id) {
    const base = growthTypePath(type);
    const file = path.join(base, `${id}.md`);
    const resolved = path.resolve(file);
    if (!resolved.startsWith(path.resolve(growthDir))) {
      const err = new Error("path_traversal");
      err.status = 403;
      throw err;
    }
    return resolved;
  }

  async function readGrowthItem(type, id) {
    const file = resolveGrowthFile(type, id);
    let text;
    try {
      text = await fs.readFile(file, "utf8");
    } catch (err) {
      if (err.code === "ENOENT") {
        const notFound = new Error("not_found");
        notFound.status = 404;
        throw notFound;
      }
      throw err;
    }
    const { data, body } = parseFrontmatter(text);
    const base = growthTypePath(type);
    return { id, type, path: path.relative(growthDir, file), data, body };
  }

  async function updateGrowthItem(type, id, newData, newBody) {
    const file = resolveGrowthFile(type, id);
    const existing = await readGrowthItem(type, id);
    const merged = { ...existing.data, ...newData, updated_at: new Date().toISOString() };
    const body = newBody !== undefined ? newBody : existing.body;
    await fs.writeFile(file, serializeFrontmatter(merged, body), "utf8");
    return { id, type, path: existing.path, data: merged };
  }

  async function deleteGrowthItem(type, id) {
    const file = resolveGrowthFile(type, id);
    await fs.access(file);
    await fs.unlink(file);
  }

  async function loadGrowthConfig() {
    const configFile = path.join(growthDir, "config/tags.json");
    try {
      const text = await fs.readFile(configFile, "utf8");
      return JSON.parse(text);
    } catch {
      return { pillars: [], keywords: [], hashtags: [], qualityChecklist: [] };
    }
  }

  function runXhsCli(args, timeoutMs = 30000) {
    return new Promise((resolve, reject) => {
      const proc = execFile(XHS_CLI, args, { timeout: timeoutMs, maxBuffer: 5 * 1024 * 1024 }, (err, stdout, stderr) => {
        if (err) return reject(new Error(stderr || err.message));
        try { resolve(JSON.parse(stdout)); } catch { reject(new Error("xhs CLI returned invalid JSON")); }
      });
    });
  }

  async function downloadImage(url, destPath) {
    const res = await fetch(url, {
      headers: { "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36", "Referer": "https://www.xiaohongshu.com/" },
    });
    if (!res.ok) throw new Error(`Image download failed: ${res.status}`);
    const buf = Buffer.from(await res.arrayBuffer());
    await fs.writeFile(destPath, buf);
    return buf.length;
  }

  async function fetchXhsNote(urlOrId) {
    const noteIdMatch = urlOrId.match(/(?:explore\/|discovery\/item\/)([a-f0-9]{24})/);
    const noteId = noteIdMatch ? noteIdMatch[1] : urlOrId.replace(/[^a-f0-9]/g, "");
    if (!noteId || noteId.length !== 24) throw new Error("invalid_note_id");

    const xsecMatch = urlOrId.match(/xsec_token=([^&]+)/);
    const args = ["read", noteId, "--json"];
    if (xsecMatch) args.push("--xsec-token", decodeURIComponent(xsecMatch[1]));

    const result = await runXhsCli(args);
    let note = result.data || {};
    // xhs CLI may return data in items[0].note_card format
    if (note.items && note.items[0]?.note_card) {
      note = note.items[0].note_card;
    }
    if (!note.title && !note.desc && !note.display_title) throw new Error("note_not_found");

    const imageDir = path.join(growthDir, XHS_IMAGE_DIR_NAME, noteId);
    await fs.mkdir(imageDir, { recursive: true });

    const images = [];
    let imageList = note.image_list || note.images || [];
    if (!imageList.length && note.cover) imageList = [note.cover];
    for (let i = 0; i < imageList.length; i++) {
      const img = imageList[i];
      const imgUrl = img.url || img.url_default
        || (img.info_list && img.info_list.find(x => x.image_scene === "WB_DFT")?.url)
        || (img.url_default) || "";
      if (!imgUrl) continue;
      const ext = imgUrl.includes("webp") ? "webp" : "jpg";
      const filename = `${i + 1}.${ext}`;
      try {
        await downloadImage(imgUrl, path.join(imageDir, filename));
        images.push({ index: i + 1, filename, localPath: `${XHS_IMAGE_DIR_NAME}/${noteId}/${filename}` });
      } catch { /* skip failed images */ }
    }

    const tags = (note.tag_list || note.tags || []).map(t => t.name || t).filter(Boolean);
    return {
      noteId,
      title: note.title || note.display_title || "",
      desc: note.desc || note.description || "",
      author: note.user?.nickname || note.user?.nick_name || "",
      authorId: note.user?.user_id || "",
      likes: note.interact_info?.liked_count || note.liked_count || "0",
      collects: note.interact_info?.collected_count || note.collected_count || "0",
      comments: note.interact_info?.comment_count || note.comment_count || "0",
      shares: note.interact_info?.shared_count || note.shared_count || "0",
      tags,
      images,
      url: `https://www.xiaohongshu.com/explore/${noteId}`,
    };
  }

  async function saveGrowthContent(input = {}) {
    const type = String(input.type || "");
    const title = String(input.title || input.data?.title || "未命名");
    const now = new Date().toISOString();
    const date = String(input.date || input.data?.date || now.slice(0, 10));
    const base = growthTypePath(type);
    const monthly = new Set(["drafts", "published"]);
    const folder = monthly.has(type) ? path.join(base, date.slice(0, 7)) : base;
    await fs.mkdir(folder, { recursive: true });
    const file = path.join(folder, `${date}-${slugify(title)}.md`);
    const data = {
      title,
      date,
      created_at: input.data?.created_at || now,
      updated_at: now,
      status: input.status || input.data?.status || (type === "topics" ? "idea" : "draft"),
      pillar: input.pillar || input.data?.pillar || "",
      keywords: input.keywords || input.data?.keywords || [],
      tags: input.tags || input.data?.tags || [],
      ...input.data,
    };
    await fs.writeFile(file, serializeFrontmatter(data, input.body || ""), "utf8");
    return {
      id: path.relative(base, file).replace(/\.md$/, ""),
      path: path.relative(growthDir, file),
      data,
    };
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

      if (req.method === "GET" && url.pathname === "/dashboard/api/growth") {
        if (!isDashboardAuthorized(req)) {
          await writeJSON(res, 401, { error: "unauthorized" });
          return;
        }
        const data = await growthOverview();
        await writeJSON(res, 200, { ok: true, ...data });
        return;
      }

      if (url.pathname === "/dashboard/api/growth/content") {
        if (!isDashboardAuthorized(req)) {
          await writeJSON(res, 401, { error: "unauthorized" });
          return;
        }
        if (req.method === "POST") {
          const data = await saveGrowthContent(await readJSONBody(req));
          await writeJSON(res, 200, { ok: true, ...data });
          return;
        }
        if (req.method === "GET") {
          const type = url.searchParams.get("type");
          const id = url.searchParams.get("id");
          if (!type || !id) {
            await writeJSON(res, 400, { error: "missing_type_or_id" });
            return;
          }
          const item = await readGrowthItem(type, id);
          await writeJSON(res, 200, { ok: true, ...item });
          return;
        }
        if (req.method === "PUT") {
          const body = await readJSONBody(req);
          const type = String(body?.type || "");
          const id = String(body?.id || "");
          if (!type || !id) {
            await writeJSON(res, 400, { error: "missing_type_or_id" });
            return;
          }
          const result = await updateGrowthItem(type, id, body.data || {}, body.body);
          await writeJSON(res, 200, { ok: true, ...result });
          return;
        }
        if (req.method === "PATCH") {
          const body = await readJSONBody(req);
          const type = String(body?.type || "");
          const id = String(body?.id || "");
          if (!type || !id) {
            await writeJSON(res, 400, { error: "missing_type_or_id" });
            return;
          }
          const patch = {};
          for (const key of ["status", "pillar", "tags", "keywords", "title"]) {
            if (body[key] !== undefined) patch[key] = body[key];
          }
          const result = await updateGrowthItem(type, id, patch);
          await writeJSON(res, 200, { ok: true, ...result });
          return;
        }
        if (req.method === "DELETE") {
          const body = await readJSONBody(req);
          const type = String(body?.type || "");
          const id = String(body?.id || "");
          if (!type || !id) {
            await writeJSON(res, 400, { error: "missing_type_or_id" });
            return;
          }
          await deleteGrowthItem(type, id);
          await writeJSON(res, 200, { ok: true });
          return;
        }
        await writeJSON(res, 405, { error: "method_not_allowed" });
        return;
      }

      if (req.method === "GET" && url.pathname === "/dashboard/api/growth/config") {
        if (!isDashboardAuthorized(req)) {
          await writeJSON(res, 401, { error: "unauthorized" });
          return;
        }
        const config = await loadGrowthConfig();
        await writeJSON(res, 200, { ok: true, ...config });
        return;
      }

      if (req.method === "POST" && url.pathname === "/dashboard/api/growth/fetch-xhs") {
        if (!isDashboardAuthorized(req)) {
          await writeJSON(res, 401, { error: "unauthorized" });
          return;
        }
        try {
          const body = await readJSONBody(req);
          const urlOrId = String(body?.url || "").trim();
          if (!urlOrId) {
            await writeJSON(res, 400, { error: "missing_url" });
            return;
          }
          const note = await fetchXhsNote(urlOrId);
          await writeJSON(res, 200, { ok: true, ...note });
        } catch (error) {
          const status = error.message === "invalid_note_id" ? 400 : 502;
          await writeJSON(res, status, { error: error.message });
        }
        return;
      }

      if (req.method === "GET" && url.pathname.startsWith("/dashboard/api/growth/images/")) {
        if (!isDashboardAuthorized(req)) {
          await writeJSON(res, 401, { error: "unauthorized" });
          return;
        }
        const imgPath = url.pathname.replace("/dashboard/api/growth/images/", "");
        const resolved = path.resolve(path.join(growthDir, XHS_IMAGE_DIR_NAME, imgPath));
        if (!resolved.startsWith(path.resolve(path.join(growthDir, XHS_IMAGE_DIR_NAME)))) {
          await writeJSON(res, 403, { error: "forbidden" });
          return;
        }
        try {
          const data = await fs.readFile(resolved);
          const ext = path.extname(resolved).slice(1);
          const mime = { webp: "image/webp", jpg: "image/jpeg", jpeg: "image/jpeg", png: "image/png" }[ext] || "application/octet-stream";
          res.writeHead(200, { "Content-Type": mime, "Cache-Control": "public, max-age=86400" });
          res.end(data);
        } catch {
          await writeJSON(res, 404, { error: "image_not_found" });
        }
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
