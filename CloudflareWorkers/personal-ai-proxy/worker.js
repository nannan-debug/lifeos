// Cloudflare Worker: LifeOS AI Agent (Arya猫)
// 模块化结构 — 详见 agent/AGENT.md
//
// 目录结构：
//   agent/     — 猫猫人格、system prompts
//   skills/    — 可插拔技能（dbt-emotional-care）
//   handlers/  — 请求处理器（chat/quick/parse/utility/trace）
//   lib/       — 共享工具（ai-client/actions/normalizers/http）

import { AI_PROVIDER } from "./lib/ai-client.js";
import { CORS_HEADERS, jsonError } from "./lib/http.js";
import { makeTrace, handleTraceRelay } from "./handlers/trace.js";
import { handleParse } from "./handlers/parse.js";
import { handleQuick } from "./handlers/quick.js";
import { handleChat, handleChatStream } from "./handlers/chat.js";
import { handleUtility } from "./handlers/utility.js";

export default {
  async fetch(request, env, ctx) {
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: CORS_HEADERS });
    }

    if (request.method !== "POST") {
      return jsonError(405, "method_not_allowed");
    }

    const url = new URL(request.url);
    if (url.pathname === "/v1/traces/events") {
      return handleTraceRelay(request, env, ctx);
    }

    const provided = request.headers.get("X-Client-Secret");
    if (!provided || provided !== env.CLIENT_SECRET) {
      return jsonError(401, "unauthorized");
    }

    let body;
    try {
      body = await request.json();
    } catch {
      return jsonError(400, "invalid_json");
    }

    const apiKey = env[AI_PROVIDER.keyEnv];
    if (!apiKey) {
      return jsonError(500, "missing_api_key", { expected: AI_PROVIDER.keyEnv });
    }

    const mode = body.mode;
    const trace = makeTrace(env, ctx, body, mode || "parse");
    trace("worker_received", {
      payload: {
        mode: String(mode || "parse"),
        hasInput: Boolean(body.input || body.text),
        messagesCount: Array.isArray(body.messages) ? body.messages.length : 0,
      },
    });

    if (mode === "chat" && body.stream === true) {
      return handleChatStream(body, AI_PROVIDER, apiKey, trace);
    }

    if (mode === "chat") {
      return handleChat(body, AI_PROVIDER, apiKey, trace);
    }

    if (mode === "quick") {
      return handleQuick(body, AI_PROVIDER, apiKey, trace);
    }

    if (mode === "utility") {
      return handleUtility(body, AI_PROVIDER, apiKey, trace);
    }

    return handleParse(body, AI_PROVIDER, apiKey, trace);
  },
};
