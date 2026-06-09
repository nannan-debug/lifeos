import { AGENT_PERSONA, USER_PROFILE, CHAT_POLICY } from "../agent/persona.js";
import { CHAT_SYSTEM_PROMPT } from "../agent/prompts.js";
import { buildDBTSkillBlock, normalizeDBTSession, reconcileDBTSessionProgress } from "../skills/dbt-emotional-care/index.js";
import { callAIJSON, compactMessageContent, extractFirstJSONObject, STREAM_JSON_DELIMITER } from "../lib/ai-client.js";
import { validateActionSuggestion, normalizeActionSuggestion, limitActionSuggestions } from "../lib/actions.js";
import { jsonOk, jsonError, CORS_HEADERS } from "../lib/http.js";

// ── Build alternating history ──────────────────────────────────────────
function buildHistory(rawMessages, maxSlice = 12) {
  const rawHistory = Array.isArray(rawMessages)
    ? rawMessages
        .filter((m) => m && (m.role === "user" || m.role === "assistant") && typeof m.content === "string")
        .slice(-maxSlice)
        .map((m) => ({ role: m.role, content: compactMessageContent(m.content, 1200) }))
    : [];

  // Ensure user/assistant alternate — merge consecutive same-role messages
  const history = [];
  for (const m of rawHistory) {
    if (history.length > 0 && history[history.length - 1].role === m.role) {
      history[history.length - 1].content += "\n" + m.content;
    } else {
      history.push({ ...m });
    }
  }
  // Drop trailing user message (current input will be appended separately)
  if (history.length > 0 && history[history.length - 1].role === "user") {
    history.pop();
  }

  return { rawHistory, history };
}

// ── Build system prompt with all replacements ──────────────────────────
function buildSystemPrompt(body, incomingDBTSession) {
  const currentDate = body.currentDate || "";
  const currentTime = body.currentTime || "";
  const contextSummary = String(body.contextSummary || "").slice(0, 4000);
  const userProfileText = typeof body.userProfile === "string" && body.userProfile.trim()
    ? body.userProfile.trim().slice(0, 500)
    : USER_PROFILE;

  const { history } = buildHistory(body.messages);
  const hasToolResult = contextSummary.includes("数据查询结果：");
  const effectiveContext = (history.length === 0 || hasToolResult) ? (contextSummary || "无") : "（已在首轮提供）";

  const dbtSkillBlock = buildDBTSkillBlock(incomingDBTSession, currentDate);
  const systemPrompt = CHAT_SYSTEM_PROMPT
    .replace("{{AGENT_PERSONA}}", AGENT_PERSONA)
    .replace("{{USER_PROFILE}}", userProfileText)
    .replace("{{CHAT_POLICY}}", CHAT_POLICY)
    .replace("{{DBT_SKILL_BLOCK}}", dbtSkillBlock)
    .replace(/\{\{CURRENT_DATE\}\}/g, currentDate)
    .replace("{{CURRENT_TIME}}", currentTime)
    .replace("{{CONTEXT_SUMMARY}}", effectiveContext);

  return { systemPrompt, effectiveContext, contextSummary };
}

// ── Non-streaming chat ─────────────────────────────────────────────────
export async function handleChat(body, provider, apiKey, trace) {
  const input = (body.input || body.text || "").trim();
  const currentDate = body.currentDate || "";

  if (!input) return jsonError(400, "empty_input");

  const incomingDBTSession = normalizeDBTSession(body.dbtSession, {}, currentDate, body.threadId || "");
  const { systemPrompt, effectiveContext, contextSummary } = buildSystemPrompt(body, incomingDBTSession);
  const { rawHistory, history } = buildHistory(body.messages);

  const messages = [
    { role: "system", content: systemPrompt },
    ...history,
    { role: "user", content: input },
  ];
  trace("prompt_built", {
    model: provider.model,
    provider: "deepseek",
    temperature: 0.5,
    maxTokens: 4096,
    payload: {
      messages,
      rawHistory,
      normalizedHistory: history,
      contextSummary,
      effectiveContext,
    },
  });

  const parsed = await callAIJSON(provider, apiKey, messages, 0.5, 4096, 0, trace);

  if (parsed.errorResponse) return parsed.errorResponse;

  const reply = typeof parsed.reply === "string" && parsed.reply.trim()
    ? parsed.reply.trim()
    : "我在。你可以继续说一点，我会慢慢跟上你的节奏。";

  const followUpQuestion = typeof parsed.followUpQuestion === "string" && parsed.followUpQuestion.trim()
    ? parsed.followUpQuestion.trim()
    : null;

  const toolCall = parsed.toolCall && typeof parsed.toolCall === "object" && parsed.toolCall.name
    ? { name: String(parsed.toolCall.name), args: parsed.toolCall.args || {} }
    : null;
  const hasActiveDBT = incomingDBTSession && incomingDBTSession.status === "active";
  const modelReturnedDBT = parsed.dbtSession && typeof parsed.dbtSession === "object";
  const dbtSession = (hasActiveDBT || modelReturnedDBT)
    ? reconcileDBTSessionProgress(
        normalizeDBTSession(parsed.dbtSession, incomingDBTSession, currentDate, body.threadId || ""),
        incomingDBTSession,
        input,
        followUpQuestion,
        currentDate,
        reply
      )
    : null;

  const shouldSuppressActions = followUpQuestion !== null || toolCall !== null;

  const actionSuggestions = shouldSuppressActions
    ? []
    : Array.isArray(parsed.actionSuggestions)
      ? limitActionSuggestions(parsed.actionSuggestions
          .map(normalizeActionSuggestion)
          .filter(Boolean)
          .map(a => validateActionSuggestion(a, input, currentDate))
          .filter(Boolean))
      : [];

  trace("response_decoded", {
    model: provider.model,
    provider: "deepseek",
    usage: parsed.__usage || null,
    payload: {
      reply,
      followUpQuestion,
      toolCall,
      dbtSession,
      shouldSuppressActions,
      actionSuggestions,
      rawModelOutput: parsed.__rawModelOutput || "",
    },
  });

  return jsonOk({
    reply,
    followUpQuestion,
    actionSuggestions,
    toolCall,
    dbtSession,
    debug: {
      rawModelOutput: parsed.__rawModelOutput || "",
      suppressedActionsReason: shouldSuppressActions
        ? (toolCall ? "toolCall_present" : "followUpQuestion_present")
        : null,
    },
    usage: parsed.__usage || null,
  });
}

// ── Streaming chat: DeepSeek SSE → client SSE ──────────────────────────
export async function handleChatStream(body, provider, apiKey, trace) {
  const input = (body.input || body.text || "").trim();
  const currentDate = body.currentDate || "";

  if (!input) return jsonError(400, "empty_input");

  const incomingDBTSession = normalizeDBTSession(body.dbtSession, {}, currentDate, body.threadId || "");
  const { systemPrompt: baseSystemPrompt, effectiveContext, contextSummary } = buildSystemPrompt(body, incomingDBTSession);
  const { rawHistory, history } = buildHistory(body.messages, 6);

  // Streaming system prompt: replace JSON output format with plain-text + delimiter
  const streamSuffix = `

# 输出方式（流式模式）
先用自然语言回复用户（不要包裹在 JSON 里），回复写完后，如果有结构化数据，换一行写：
${STREAM_JSON_DELIMITER}
然后紧跟一个 JSON 对象：{"followUpQuestion":"...或null","actionSuggestions":[...],"toolCall":null}
当用户正在进行 DBT 练习时，JSON 对象还必须包含 "dbtSession": {...}。
如果没有结构化数据要返回，就不写 ${STREAM_JSON_DELIMITER}，只输出自然语言回复。`;

  let systemPrompt = baseSystemPrompt.replace(
    /# 输出格式（严格 JSON）\n\{"reply":"自然回复","followUpQuestion":"一个追问或null","actionSuggestions":\[\]\}/,
    ""
  ) + streamSuffix;

  const trigger = body.trigger || "userMessage";
  if (trigger === "scheduledNudge") {
    const nudgeBlock = `
# 触发模式：定时提醒
用户刚从定时提醒通知进来，这是你主动发起的对话。不要等用户说话。
根据 contextSummary 直接给出温暖但不啰嗦的第一句话。
- 有未完成待办/打卡 → 温柔提及（不是催）
- 今天记录多 → 表达肯定
- 几天没来 → 关心但不催
- 不要说"你好"或"有什么可以帮你的"
- 像朋友晚上路过顺便敲门聊一句
- 第一条消息不要生成 actionSuggestions
`;
    systemPrompt = nudgeBlock + systemPrompt;
  }

  const userInput = trigger === "scheduledNudge" ? "（定时提醒触发，请主动开始对话）" : input;

  const messages = [
    { role: "system", content: systemPrompt },
    ...history,
    { role: "user", content: userInput },
  ];

  trace("stream_started", {
    model: provider.model,
    provider: "deepseek",
    temperature: 0.5,
    maxTokens: 4096,
    payload: {
      messages,
      rawHistory,
      normalizedHistory: history,
      contextSummary,
      effectiveContext,
    },
  });

  // Call DeepSeek with stream: true (no response_format)
  let upstream;
  const startedAt = Date.now();
  try {
    upstream = await fetch(provider.url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${apiKey}`,
      },
      body: JSON.stringify({
        model: provider.model,
        messages,
        temperature: 0.5,
        max_tokens: 4096,
        stream: true,
      }),
    });
  } catch (e) {
    trace("stream_failed", {
      model: provider.model,
      provider: "deepseek",
      latencyMs: Date.now() - startedAt,
      error: { type: "network", message: String(e).slice(0, 200) },
    });
    return jsonError(502, "ai_network_failed", { message: String(e).slice(0, 200) });
  }

  if (!upstream.ok) {
    const errText = await upstream.text();
    trace("stream_failed", {
      model: provider.model,
      provider: "deepseek",
      latencyMs: Date.now() - startedAt,
      error: { type: "upstream", status: upstream.status, detail: errText.slice(0, 500) },
    });
    return jsonError(502, "ai_upstream_failed", {
      status: upstream.status,
      detail: errText.slice(0, 200),
    });
  }

  // Transform upstream SSE → downstream SSE
  let reasoningBuf = "";
  let contentBuf = "";
  let contentForwarded = 0;
  let phase = "reasoning";
  let usage = null;
  let reasoningStartedAt = Date.now();
  let contentStartedAt = null;

  const { readable, writable } = new TransformStream();
  const writer = writable.getWriter();
  const encoder = new TextEncoder();

  function sendSSE(obj) {
    return writer.write(encoder.encode(`data: ${JSON.stringify(obj)}\n\n`));
  }

  const processUpstream = async () => {
    const reader = upstream.body.getReader();
    const decoder = new TextDecoder();
    let buffer = "";

    try {
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        buffer += decoder.decode(value, { stream: true });

        const lines = buffer.split("\n");
        buffer = lines.pop() || "";

        for (const line of lines) {
          const trimmed = line.trim();
          if (!trimmed || trimmed.startsWith(":")) continue;
          if (!trimmed.startsWith("data: ")) continue;
          const payload = trimmed.slice(6);

          if (payload === "[DONE]") {
            // Flush any held-back content
            const finalDelimIdx = contentBuf.indexOf(STREAM_JSON_DELIMITER);
            if (finalDelimIdx === -1 && contentForwarded < contentBuf.length) {
              const remaining = contentBuf.slice(contentForwarded);
              if (remaining.trim()) await sendSSE({ type: "content", text: remaining });
            } else if (finalDelimIdx !== -1 && contentForwarded < finalDelimIdx) {
              const remaining = contentBuf.slice(contentForwarded, finalDelimIdx).trimEnd();
              if (remaining) await sendSSE({ type: "content", text: remaining });
            }

            const reasoningTimeMs = contentStartedAt
              ? contentStartedAt - reasoningStartedAt
              : Date.now() - reasoningStartedAt;

            // Extract structured data
            let replyText = contentBuf;
            let followUpQuestion = null;
            let actionSuggestions = [];
            let toolCall = null;
            let dbtSession = null;

            const delimIdx = contentBuf.indexOf(STREAM_JSON_DELIMITER);
            if (delimIdx !== -1) {
              replyText = contentBuf.slice(0, delimIdx).trim();
              let jsonPart = contentBuf.slice(delimIdx + STREAM_JSON_DELIMITER.length).trim();
              const closingIdx = jsonPart.indexOf(STREAM_JSON_DELIMITER);
              if (closingIdx !== -1) {
                jsonPart = jsonPart.slice(0, closingIdx).trim();
              }
              jsonPart = jsonPart.replace(/^```(?:json)?\s*/i, "").replace(/\s*```\s*$/, "").trim();
              jsonPart = extractFirstJSONObject(jsonPart) || jsonPart;
              try {
                const structured = JSON.parse(jsonPart);
                followUpQuestion = typeof structured.followUpQuestion === "string" && structured.followUpQuestion.trim()
                  ? structured.followUpQuestion.trim()
                  : null;
                toolCall = structured.toolCall && typeof structured.toolCall === "object" && structured.toolCall.name
                  ? { name: String(structured.toolCall.name), args: structured.toolCall.args || {} }
                  : null;
                const hasActiveDBT = incomingDBTSession && incomingDBTSession.status === "active";
                const modelReturnedDBT = structured.dbtSession && typeof structured.dbtSession === "object";
                dbtSession = (hasActiveDBT || modelReturnedDBT)
                  ? reconcileDBTSessionProgress(
                      normalizeDBTSession(structured.dbtSession, incomingDBTSession, currentDate, body.threadId || ""),
                      incomingDBTSession,
                      input,
                      followUpQuestion,
                      currentDate,
                      replyText
                    )
                  : null;
                const shouldSuppressActions = followUpQuestion !== null || toolCall !== null;
                actionSuggestions = shouldSuppressActions
                  ? []
                  : Array.isArray(structured.actionSuggestions)
                    ? limitActionSuggestions(structured.actionSuggestions
                        .map(normalizeActionSuggestion).filter(Boolean)
                        .map(a => validateActionSuggestion(a, input, currentDate)).filter(Boolean))
                    : [];
              } catch {
                replyText = replyText.trim();
              }
            }

            if (!replyText) {
              replyText = "我在。你可以继续说一点，我会慢慢跟上你的节奏。";
            }

            await sendSSE({
              type: "done",
              reply: replyText,
              followUpQuestion,
              actionSuggestions,
              toolCall,
              dbtSession,
              usage,
              reasoningTimeMs,
            });

            trace("stream_finished", {
              model: provider.model,
              provider: "deepseek",
              usage,
              latencyMs: Date.now() - startedAt,
              payload: {
                reasoningLength: reasoningBuf.length,
                contentLength: contentBuf.length,
                replyLength: replyText.length,
                hasDelimiter: delimIdx !== -1,
                followUpQuestion,
                toolCall,
                dbtSession,
                actionSuggestionsCount: actionSuggestions.length,
                reasoningTimeMs,
              },
            });

            break;
          }

          let chunk;
          try {
            chunk = JSON.parse(payload);
          } catch {
            continue;
          }

          if (chunk.usage) {
            usage = chunk.usage;
          }

          const delta = chunk.choices?.[0]?.delta;
          if (!delta) continue;

          if (delta.reasoning_content) {
            reasoningBuf += delta.reasoning_content;
            await sendSSE({ type: "reasoning", text: delta.reasoning_content });
          }

          if (delta.content) {
            if (phase === "reasoning" && !contentStartedAt) {
              contentStartedAt = Date.now();
              phase = "content";
            }
            contentBuf += delta.content;

            const delimIdx = contentBuf.indexOf(STREAM_JSON_DELIMITER);
            if (delimIdx !== -1) {
              if (contentForwarded < delimIdx) {
                const safe = contentBuf.slice(contentForwarded, delimIdx).trimEnd();
                if (safe) await sendSSE({ type: "content", text: safe });
                contentForwarded = contentBuf.length;
              }
            } else {
              const holdBack = STREAM_JSON_DELIMITER.length - 1;
              const safeEnd = contentBuf.length - holdBack;
              if (safeEnd > contentForwarded) {
                const safe = contentBuf.slice(contentForwarded, safeEnd);
                await sendSSE({ type: "content", text: safe });
                contentForwarded = safeEnd;
              }
            }
          }
        }
      }
    } catch (e) {
      await sendSSE({ type: "error", message: String(e).slice(0, 200) });
      trace("stream_error", {
        model: provider.model,
        provider: "deepseek",
        latencyMs: Date.now() - startedAt,
        error: { type: "stream_read", message: String(e).slice(0, 200) },
      });
    } finally {
      await writer.close();
    }
  };

  // Don't await — let it run while we return the response
  processUpstream();

  return new Response(readable, {
    status: 200,
    headers: {
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache",
      "Connection": "keep-alive",
      ...CORS_HEADERS,
    },
  });
}
