import test from "node:test";
import assert from "node:assert/strict";
import { promises as fs } from "node:fs";
import os from "node:os";
import path from "node:path";
import { createTraceServer } from "../server.js";

async function withServer(fn, options = {}) {
  const traceDir = await fs.mkdtemp(path.join(os.tmpdir(), "lifeos-traces-"));
  const { server } = createTraceServer({
    traceDir,
    traceToken: "test-token",
    dashboardUser: options.dashboardUser,
    dashboardPassword: options.dashboardPassword,
    dashboardSecret: options.dashboardSecret,
  });
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const { port } = server.address();
  try {
    await fn({ baseURL: `http://127.0.0.1:${port}`, traceDir });
  } finally {
    await new Promise((resolve) => server.close(resolve));
    await fs.rm(traceDir, { recursive: true, force: true });
  }
}

test("rejects missing token", async () => {
  await withServer(async ({ baseURL }) => {
    const res = await fetch(`${baseURL}/v1/traces/events`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ traceId: "t1", eventName: "request_started", source: "ios" }),
    });
    assert.equal(res.status, 401);
  });
});

test("appends a valid event to a day jsonl file", async () => {
  await withServer(async ({ baseURL, traceDir }) => {
    const res = await fetch(`${baseURL}/v1/traces/events`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-LifeOS-Trace-Token": "test-token",
      },
      body: JSON.stringify({
        traceId: "trace-1",
        eventName: "request_started",
        source: "ios",
        timestamp: "2026-05-20T10:00:00.000Z",
        payload: { input: "hello" },
      }),
    });
    assert.equal(res.status, 200);
    const raw = await fs.readFile(path.join(traceDir, "2026-05-20.jsonl"), "utf8");
    const line = JSON.parse(raw.trim());
    assert.equal(line.traceId, "trace-1");
    assert.equal(line.eventName, "request_started");
    assert.equal(line.receivedAt.length > 0, true);
  });
});

test("keeps concurrent appends as separate lines", async () => {
  await withServer(async ({ baseURL, traceDir }) => {
    await Promise.all(Array.from({ length: 20 }, (_, index) => fetch(`${baseURL}/v1/traces/events`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-LifeOS-Trace-Token": "test-token",
      },
      body: JSON.stringify({
        traceId: `trace-${index}`,
        eventName: "model_call_finished",
        source: "worker",
        timestamp: "2026-05-20T10:00:00.000Z",
      }),
    })));
    const raw = await fs.readFile(path.join(traceDir, "2026-05-20.jsonl"), "utf8");
    assert.equal(raw.trim().split("\n").length, 20);
  });
});

test("queries by trace id", async () => {
  await withServer(async ({ baseURL }) => {
    for (const eventName of ["request_started", "response_decoded"]) {
      await fetch(`${baseURL}/v1/traces/events`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-LifeOS-Trace-Token": "test-token",
        },
        body: JSON.stringify({
          traceId: "trace-query",
          eventName,
          source: "ios",
          timestamp: "2026-05-20T10:00:00.000Z",
        }),
      });
    }
    const res = await fetch(`${baseURL}/v1/traces/events?date=2026-05-20&traceId=trace-query`, {
      headers: { "X-LifeOS-Trace-Token": "test-token" },
    });
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.events.length, 2);
  });
});

test("rejects invalid json", async () => {
  await withServer(async ({ baseURL }) => {
    const res = await fetch(`${baseURL}/v1/traces/events`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-LifeOS-Trace-Token": "test-token",
      },
      body: "{bad",
    });
    assert.equal(res.status, 400);
  });
});

test("serves the dashboard shell", async () => {
  await withServer(async ({ baseURL }) => {
    const res = await fetch(`${baseURL}/dashboard`);
    assert.equal(res.status, 200);
    const body = await res.text();
    assert.equal(body.includes("LifeOS Agent Trace"), true);
  });
});

test("rejects dashboard trace queries without a login session", async () => {
  await withServer(async ({ baseURL }) => {
    const res = await fetch(`${baseURL}/dashboard/api/traces?date=2026-05-20`);
    assert.equal(res.status, 401);
  }, {
    dashboardUser: "anna",
    dashboardPassword: "secret",
    dashboardSecret: "dashboard-secret",
  });
});

test("rejects invalid dashboard credentials", async () => {
  await withServer(async ({ baseURL }) => {
    const res = await fetch(`${baseURL}/dashboard/api/login`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ user: "anna", password: "wrong" }),
    });
    assert.equal(res.status, 401);
  }, {
    dashboardUser: "anna",
    dashboardPassword: "secret",
    dashboardSecret: "dashboard-secret",
  });
});

test("allows a logged-in dashboard session to query traces", async () => {
  await withServer(async ({ baseURL }) => {
    await fetch(`${baseURL}/v1/traces/events`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-LifeOS-Trace-Token": "test-token",
      },
      body: JSON.stringify({
        traceId: "dashboard-trace",
        eventName: "request_failed",
        source: "ios",
        timestamp: "2026-05-20T10:00:00.000Z",
        error: { type: "AIParseError", message: "network lost" },
        payload: { input: "今天状态不错" },
      }),
    });
    await fetch(`${baseURL}/v1/traces/events`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-LifeOS-Trace-Token": "test-token",
      },
      body: JSON.stringify({
        traceId: "dashboard-trace",
        eventName: "response_decoded",
        source: "worker",
        timestamp: "2026-05-20T10:00:02.000Z",
        payload: { reply: "收到，已记录。" },
      }),
    });
    await fetch(`${baseURL}/v1/traces/events`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-LifeOS-Trace-Token": "test-token",
      },
      body: JSON.stringify({
        traceId: "usage-12345678",
        eventName: "usage_batch",
        source: "ios",
        timestamp: "2026-05-20T10:05:00.000Z",
        payload: { usage_app_open: "1", usage_ai_chat_sent: "2" },
      }),
    });

    const login = await fetch(`${baseURL}/dashboard/api/login`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ user: "anna", password: "secret" }),
    });
    assert.equal(login.status, 200);
    const cookie = login.headers.get("set-cookie");
    assert.equal(cookie.includes("lifeos_trace_session="), true);

    const query = await fetch(`${baseURL}/dashboard/api/traces?date=2026-05-20&errorsOnly=1&q=network`, {
      headers: { Cookie: cookie },
    });
    assert.equal(query.status, 200);
    const body = await query.json();
    assert.equal(body.events.length, 2);
    assert.equal(body.traces.length, 1);
    assert.equal(body.traces[0].traceId, "dashboard-trace");
    assert.equal(body.traces[0].hasError, true);

    const summaryOnly = await fetch(`${baseURL}/dashboard/api/traces?date=2026-05-20&summaryOnly=1`, {
      headers: { Cookie: cookie },
    });
    assert.equal(summaryOnly.status, 200);
    const summaryBody = await summaryOnly.json();
    assert.equal(summaryBody.events.length, 0);
    assert.equal(summaryBody.traces.length, 2);

    const aiOnly = await fetch(`${baseURL}/dashboard/api/traces?date=2026-05-20&summaryOnly=1&kind=ai`, {
      headers: { Cookie: cookie },
    });
    assert.equal(aiOnly.status, 200);
    const aiOnlyBody = await aiOnly.json();
    assert.equal(aiOnlyBody.traces.length, 1);
    assert.equal(aiOnlyBody.traces[0].traceId, "dashboard-trace");

    const usageOnly = await fetch(`${baseURL}/dashboard/api/traces?date=2026-05-20&summaryOnly=1&kind=usage`, {
      headers: { Cookie: cookie },
    });
    assert.equal(usageOnly.status, 200);
    const usageOnlyBody = await usageOnly.json();
    assert.equal(usageOnlyBody.traces.length, 1);
    assert.equal(usageOnlyBody.traces[0].traceId, "usage-12345678");
    assert.equal(usageOnlyBody.traces[0].title.includes("使用统计"), true);
  }, {
    dashboardUser: "anna",
    dashboardPassword: "secret",
    dashboardSecret: "dashboard-secret",
  });
});
