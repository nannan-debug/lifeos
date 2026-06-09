import { CORS_HEADERS, jsonError } from "../lib/http.js";

export function makeTrace(env, ctx, body, mode) {
  const traceId = String(body.traceId || crypto.randomUUID());
  const sessionId = body.sessionId ? String(body.sessionId) : null;
  const threadId = body.threadId ? String(body.threadId) : null;
  return (eventName, fields = {}) => {
    emitTrace(env, ctx, {
      traceId,
      sessionId,
      threadId,
      eventName,
      source: "worker",
      timestamp: new Date().toISOString(),
      mode,
      ...fields,
    });
  };
}

export function emitTrace(env, ctx, event) {
  const url = env.TRACE_INGEST_URL;
  const token = env.TRACE_INGEST_TOKEN;
  if (!url || !token || !ctx?.waitUntil) return;
  ctx.waitUntil(fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-LifeOS-Trace-Token": token,
    },
    body: JSON.stringify(event),
  }).catch(() => undefined));
}

export async function handleTraceRelay(request, env, ctx) {
  const ingestUrl = env.TRACE_INGEST_URL;
  const ingestToken = env.TRACE_INGEST_TOKEN;
  if (!ingestUrl || !ingestToken) {
    return jsonError(503, "trace_ingest_not_configured");
  }
  const traceToken = request.headers.get("X-LifeOS-Trace-Token");
  if (!traceToken || traceToken !== ingestToken) {
    return jsonError(401, "unauthorized");
  }
  const body = await request.text();
  const resp = await fetch(ingestUrl, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-LifeOS-Trace-Token": ingestToken,
    },
    body,
  });
  const result = await resp.text();
  return new Response(result, {
    status: resp.status,
    headers: { "Content-Type": "application/json", ...CORS_HEADERS },
  });
}
