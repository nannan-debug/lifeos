import test from "node:test";
import assert from "node:assert/strict";
import { promises as fs } from "node:fs";
import os from "node:os";
import path from "node:path";
import { createTraceServer } from "../server.js";

async function withServer(fn, options = {}) {
  const traceDir = await fs.mkdtemp(path.join(os.tmpdir(), "lifeos-traces-"));
  const growthDir = await fs.mkdtemp(path.join(os.tmpdir(), "lifeos-growth-"));
  const { server } = createTraceServer({
    traceDir,
    growthDir,
    traceToken: "test-token",
    dashboardUser: options.dashboardUser,
    dashboardPassword: options.dashboardPassword,
    dashboardSecret: options.dashboardSecret,
  });
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const { port } = server.address();
  try {
    await fn({ baseURL: `http://127.0.0.1:${port}`, traceDir, growthDir });
  } finally {
    await new Promise((resolve) => server.close(resolve));
    await fs.rm(traceDir, { recursive: true, force: true });
    await fs.rm(growthDir, { recursive: true, force: true });
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

test("allows a logged-in dashboard session to manage growth content", async () => {
  await withServer(async ({ baseURL, growthDir }) => {
    const login = await fetch(`${baseURL}/dashboard/api/login`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ user: "anna", password: "secret" }),
    });
    assert.equal(login.status, 200);
    const cookie = login.headers.get("set-cookie");

    const denied = await fetch(`${baseURL}/dashboard/api/growth`);
    assert.equal(denied.status, 401);

    const save = await fetch(`${baseURL}/dashboard/api/growth/content`, {
      method: "POST",
      headers: { "Content-Type": "application/json", Cookie: cookie },
      body: JSON.stringify({
        type: "drafts",
        title: "生活记录不用写很完整",
        pillar: "生活记录方法",
        status: "ready",
        keywords: ["生活记录"],
        tags: ["LifeOS"],
        body: "今天先记录一句也算数。",
      }),
    });
    assert.equal(save.status, 200);
    const saved = await save.json();
    assert.equal(saved.path.includes("drafts/"), true);

    const overview = await fetch(`${baseURL}/dashboard/api/growth`, {
      headers: { Cookie: cookie },
    });
    assert.equal(overview.status, 200);
    const body = await overview.json();
    assert.equal(body.counts.drafts, 1);
    assert.equal(body.counts.readyDrafts, 1);
    assert.equal(body.drafts[0].data.title, "生活记录不用写很完整");

    const files = await fs.readdir(path.join(growthDir, "drafts", new Date().toISOString().slice(0, 7)));
    assert.equal(files.some((file) => file.endsWith(".md")), true);
  }, {
    dashboardUser: "anna",
    dashboardPassword: "secret",
    dashboardSecret: "dashboard-secret",
  });
});

test("GET single growth item returns full body", async () => {
  await withServer(async ({ baseURL, growthDir }) => {
    const login = await fetch(`${baseURL}/dashboard/api/login`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ user: "anna", password: "secret" }),
    });
    const cookie = login.headers.get("set-cookie");

    const save = await fetch(`${baseURL}/dashboard/api/growth/content`, {
      method: "POST",
      headers: { "Content-Type": "application/json", Cookie: cookie },
      body: JSON.stringify({
        type: "topics",
        title: "测试选题",
        status: "idea",
        pillar: "生活记录方法",
        keywords: ["测试"],
        tags: ["测试标签"],
        body: "## 角度\n\n这是完整正文。\n\n## 用户搜索意图\n\n测试用。",
      }),
    });
    const saved = await save.json();

    const get = await fetch(`${baseURL}/dashboard/api/growth/content?type=topics&id=${encodeURIComponent(saved.id)}`, {
      headers: { Cookie: cookie },
    });
    assert.equal(get.status, 200);
    const item = await get.json();
    assert.equal(item.data.title, "测试选题");
    assert.equal(item.body.includes("这是完整正文"), true);
    assert.equal(item.body.includes("用户搜索意图"), true);
  }, {
    dashboardUser: "anna",
    dashboardPassword: "secret",
    dashboardSecret: "dashboard-secret",
  });
});

test("PUT updates growth item fully", async () => {
  await withServer(async ({ baseURL }) => {
    const login = await fetch(`${baseURL}/dashboard/api/login`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ user: "anna", password: "secret" }),
    });
    const cookie = login.headers.get("set-cookie");

    const save = await fetch(`${baseURL}/dashboard/api/growth/content`, {
      method: "POST",
      headers: { "Content-Type": "application/json", Cookie: cookie },
      body: JSON.stringify({
        type: "references",
        title: "原标题",
        status: "saved",
        body: "原正文",
      }),
    });
    const saved = await save.json();

    const put = await fetch(`${baseURL}/dashboard/api/growth/content`, {
      method: "PUT",
      headers: { "Content-Type": "application/json", Cookie: cookie },
      body: JSON.stringify({
        type: "references",
        id: saved.id,
        data: { title: "改后标题", status: "saved", pillar: "AI 陪伴记录" },
        body: "改后正文。",
      }),
    });
    assert.equal(put.status, 200);

    const get = await fetch(`${baseURL}/dashboard/api/growth/content?type=references&id=${encodeURIComponent(saved.id)}`, {
      headers: { Cookie: cookie },
    });
    const item = await get.json();
    assert.equal(item.data.title, "改后标题");
    assert.equal(item.data.pillar, "AI 陪伴记录");
    assert.equal(item.body.includes("改后正文"), true);
    assert.ok(item.data.updated_at);
  }, {
    dashboardUser: "anna",
    dashboardPassword: "secret",
    dashboardSecret: "dashboard-secret",
  });
});

test("PATCH updates growth item status only", async () => {
  await withServer(async ({ baseURL }) => {
    const login = await fetch(`${baseURL}/dashboard/api/login`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ user: "anna", password: "secret" }),
    });
    const cookie = login.headers.get("set-cookie");

    const save = await fetch(`${baseURL}/dashboard/api/growth/content`, {
      method: "POST",
      headers: { "Content-Type": "application/json", Cookie: cookie },
      body: JSON.stringify({
        type: "topics",
        title: "状态测试",
        status: "idea",
        body: "不应该变。",
      }),
    });
    const saved = await save.json();

    const patch = await fetch(`${baseURL}/dashboard/api/growth/content`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json", Cookie: cookie },
      body: JSON.stringify({ type: "topics", id: saved.id, status: "selected" }),
    });
    assert.equal(patch.status, 200);

    const get = await fetch(`${baseURL}/dashboard/api/growth/content?type=topics&id=${encodeURIComponent(saved.id)}`, {
      headers: { Cookie: cookie },
    });
    const item = await get.json();
    assert.equal(item.data.status, "selected");
    assert.equal(item.data.title, "状态测试");
    assert.equal(item.body.includes("不应该变"), true);
  }, {
    dashboardUser: "anna",
    dashboardPassword: "secret",
    dashboardSecret: "dashboard-secret",
  });
});

test("DELETE removes growth item", async () => {
  await withServer(async ({ baseURL }) => {
    const login = await fetch(`${baseURL}/dashboard/api/login`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ user: "anna", password: "secret" }),
    });
    const cookie = login.headers.get("set-cookie");

    const save = await fetch(`${baseURL}/dashboard/api/growth/content`, {
      method: "POST",
      headers: { "Content-Type": "application/json", Cookie: cookie },
      body: JSON.stringify({ type: "references", title: "要删的", body: "bye" }),
    });
    const saved = await save.json();

    const del = await fetch(`${baseURL}/dashboard/api/growth/content`, {
      method: "DELETE",
      headers: { "Content-Type": "application/json", Cookie: cookie },
      body: JSON.stringify({ type: "references", id: saved.id }),
    });
    assert.equal(del.status, 200);

    const get = await fetch(`${baseURL}/dashboard/api/growth/content?type=references&id=${encodeURIComponent(saved.id)}`, {
      headers: { Cookie: cookie },
    });
    assert.equal(get.status, 404);
  }, {
    dashboardUser: "anna",
    dashboardPassword: "secret",
    dashboardSecret: "dashboard-secret",
  });
});

test("GET growth config returns tags.json content", async () => {
  await withServer(async ({ baseURL, growthDir }) => {
    const login = await fetch(`${baseURL}/dashboard/api/login`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ user: "anna", password: "secret" }),
    });
    const cookie = login.headers.get("set-cookie");

    await fs.mkdir(path.join(growthDir, "config"), { recursive: true });
    await fs.writeFile(path.join(growthDir, "config/tags.json"), JSON.stringify({
      pillars: ["生活记录方法", "AI 陪伴记录"],
      keywords: ["生活记录"],
      hashtags: ["#生活记录"],
      qualityChecklist: ["标题含关键词"],
    }));

    const res = await fetch(`${baseURL}/dashboard/api/growth/config`, {
      headers: { Cookie: cookie },
    });
    assert.equal(res.status, 200);
    const config = await res.json();
    assert.equal(config.pillars.length, 2);
    assert.equal(config.pillars[0], "生活记录方法");
  }, {
    dashboardUser: "anna",
    dashboardPassword: "secret",
    dashboardSecret: "dashboard-secret",
  });
});

test("rejects path traversal in growth content GET", async () => {
  await withServer(async ({ baseURL }) => {
    const login = await fetch(`${baseURL}/dashboard/api/login`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ user: "anna", password: "secret" }),
    });
    const cookie = login.headers.get("set-cookie");

    const get = await fetch(`${baseURL}/dashboard/api/growth/content?type=references&id=${encodeURIComponent("../../etc/passwd")}`, {
      headers: { Cookie: cookie },
    });
    assert.equal(get.status, 403);
  }, {
    dashboardUser: "anna",
    dashboardPassword: "secret",
    dashboardSecret: "dashboard-secret",
  });
});
