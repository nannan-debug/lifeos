import test from "node:test";
import assert from "node:assert/strict";
import { promises as fs } from "node:fs";
import os from "node:os";
import path from "node:path";
import { createTraceServer } from "../server.js";

async function withServer(fn) {
  const traceDir = await fs.mkdtemp(path.join(os.tmpdir(), "lifeos-traces-"));
  const { server } = createTraceServer({ traceDir, traceToken: "test-token" });
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
