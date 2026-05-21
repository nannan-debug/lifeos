import http from "node:http";
import { promises as fs } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { createGzip } from "node:zlib";
import { pipeline } from "node:stream/promises";
import { createReadStream, createWriteStream } from "node:fs";

const DEFAULT_PORT = 8787;
const MAX_BODY_BYTES = 2 * 1024 * 1024;
const TOKEN_HEADER = "x-lifeos-trace-token";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

export function createTraceServer(options = {}) {
  const traceDir = options.traceDir || process.env.TRACE_DIR || "/var/lib/lifeos-traces";
  const traceToken = options.traceToken ?? process.env.TRACE_TOKEN ?? "";

  async function writeJSON(res, status, payload) {
    const body = JSON.stringify(payload);
    res.writeHead(status, {
      "Content-Type": "application/json; charset=utf-8",
      "Content-Length": Buffer.byteLength(body),
    });
    res.end(body);
  }

  function isAuthorized(req) {
    return Boolean(traceToken) && req.headers[TOKEN_HEADER] === traceToken;
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
    return normalized;
  }

  async function listEvents(query) {
    const day = String(query.get("date") || new Date().toISOString().slice(0, 10));
    if (!/^\d{4}-\d{2}-\d{2}$/.test(day)) {
      const err = new Error("invalid_date");
      err.status = 400;
      throw err;
    }
    const traceId = String(query.get("traceId") || "").trim();
    const limit = Math.min(Number(query.get("limit") || 200), 1000);
    const file = path.join(traceDir, `${day}.jsonl`);
    let raw = "";
    try {
      raw = await fs.readFile(file, "utf8");
    } catch (err) {
      if (err.code === "ENOENT") return [];
      throw err;
    }
    return raw
      .split("\n")
      .filter(Boolean)
      .map((line) => JSON.parse(line))
      .filter((event) => !traceId || event.traceId === traceId)
      .slice(-limit);
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
    try {
      const url = new URL(req.url || "/", "http://localhost");

      if (req.method === "GET" && url.pathname === "/health") {
        await writeJSON(res, 200, { ok: true });
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
  server.listen(port, "0.0.0.0", () => {
    console.log(`lifeos-agent-trace-ingest listening on :${port}`);
  });
}
