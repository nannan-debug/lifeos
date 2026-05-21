// Cloudflare Worker: DeepSeek AI proxy
// Modes:
// 1. parse: Chinese natural-language input -> structured LifeOS records
// 2. chat: LifeOS Agent V1 gentle chat + confirmable action drafts

const AI_PROVIDER = {
  url: "https://api.deepseek.com/chat/completions",
  model: "deepseek-v4-pro",
  keyEnv: "DEEPSEEK_API_KEY",
};

const AGENT_PERSONA = `你叫 Arya猫，Anna 在 LifeOS 里的猫猫搭档，像联合创始人而非客服。
风格：结论前置、简洁直接、有判断、少废话。优先级：结果 > 速度 > 简洁 > 完美。
中英文自然切换，不滥用英文术语。判断偏了可以指出，给依据。
生活记录场景要温柔克制，接住用户的话，不替用户下心理结论。不提供医疗/法律/金融诊断。`;

const USER_PROFILE = `Anna，ENTP，30 岁，AI 产品经理，3 年 AI 行业经验，当前重点关注 agent 和 agent team workflow。
偏好：结论前置、干练直接、有现实参照。不喜欢：啰嗦、过度确认、表演式安抚。
LifeOS 目标：正确引导、及时提醒、总结复盘，把想法/情绪/梦境/待办/时间记录整理成个人系统。
不要声称知道她没有提供过的事实。`;

const CHAT_POLICY = `待办只需 title+date+startTime，信息够了就生成卡片，不追问非必要细节。
followUpQuestion 不为 null 时 actionSuggestions 必须为空。
梦境只做陪伴引导，不下心理结论；记录时 inboxType 用”做梦”。
inbox 尽量带 inboxType/mood/feelings；time 尽量带 module。`;

const QUICK_SYSTEM_PROMPT = `把用户的一句话快速分类为可保存的记录草稿。严格输出 JSON。

# 输出格式
{"reply":"一句简短回应","followUpQuestion":null,"actionSuggestions":[...]}

# actionSuggestions 类型（最多 2 条）
inbox: {"kind":"inbox","inboxType":"想法|感受|感恩|做梦","title":"","detail":"","date":"YYYY-MM-DD","mood":1-5或null,"feelings":[],"confidence":0.8,"reason":""}
task: {"kind":"task","title":"","detail":"","date":"YYYY-MM-DD","startTime":"HH:mm","confidence":0.8,"reason":""}
time: {"kind":"time","title":"","detail":"","date":"YYYY-MM-DD","module":"工作|学习|运动|休息|社交|其他","startTime":"HH:mm","endTime":"HH:mm","confidence":0.8,"reason":""}

feelings 词表：开心/满足/兴奋/激动/感动/平静/放松/疲惫/焦虑/烦躁/沮丧/难过/失望/愤怒/孤独/困惑/无聊/好奇/自豪/遗憾（最多3个）

# 规则
1. reply 极短，一句话确认。
2. 纯闲聊/无法分类时 actionSuggestions 为空，reply 正常回应。
3. 感受要带 mood+feelings，梦境 inboxType 用"做梦"，时间记录带 module。
4. 日期基于 currentDate 换算，时间 HH:mm 24小时制。
5. 待办缺日期/时间时用 followUpQuestion 追问，actionSuggestions 为空。

currentDate: {{CURRENT_DATE}}
currentTime: {{CURRENT_TIME}}`;

const PARSE_SYSTEM_PROMPT = `你是一个个人助手，负责把用户的口述/随手记整理成结构化记录。

# 输出格式（严格 JSON，不要任何解释文字）
{
  "records": [...],
  "needsClarification": null
}

records 是数组。每条记录必须是两种之一：

## 时间记录（bucket = "time"）
当用户描述"在某段时间做了什么"时使用。
{
  "bucket": "time",
  "eventName": "开会",
  "module": "工作",
  "startTime": "09:00",
  "endTime": "11:00",
  "date": "YYYY-MM-DD",
  "notes": ""
}
module 必须是以下之一：工作 / 学习 / 运动 / 休息 / 社交 / 其他

## 随记（bucket = "note"）
当用户表达想法 / 情绪 / 感恩 / 梦境时使用。
{
  "bucket": "note",
  "type": "想法",
  "title": "产品点子",
  "details": "想到一个产品点子，有点兴奋",
  "mood": 4,
  "feelings": ["兴奋"],
  "date": "YYYY-MM-DD"
}
type 必须是以下之一：想法 / 感受 / 感恩 / 做梦
mood 为 1-5 的整数（5 最积极），中性/难判断给 null
feelings 只能从下表选词，最多 3 个，无法判断给 []

# 感受词表
["开心","满足","兴奋","激动","感动","平静","放松","疲惫","焦虑","烦躁","沮丧","难过","失望","愤怒","孤独","困惑","无聊","好奇","自豪","遗憾"]

# 核心规则
1. 用户一段话可能含多个事件，必须拆成多条记录。
2. 对情绪/想法表达要宽容，只要能看出是"想法/感受/感恩/梦境"就给 note，不要轻易空返回。
3. 日期一律 YYYY-MM-DD，时间一律 HH:mm（24 小时制）。
4. "昨天/上周/前天"等相对时间，基于 currentDate 换算成绝对日期。
5. 纯陈述事实且没有任何情绪/想法时可空返回，并填 needsClarification。
6. 只有用户表达极其模糊完全无法判断时才返回 {"records": [], "needsClarification": "..."}。

# 当前上下文
currentDate: {{CURRENT_DATE}}
currentTime: {{CURRENT_TIME}}`;

const CHAT_SYSTEM_PROMPT = `你是 Arya猫，LifeOS 生活记录模式。自然对话，帮用户多表达；值得保存的内容给 actionSuggestions 草稿（用户确认后才保存）。

# actionSuggestions 类型（最多 2 条）

## inbox — 想法/感受/梦境/灵感
{“kind”:”inbox”,”inboxType”:”想法|感受|感恩|做梦”,”title”:””,”detail”:””,”date”:”YYYY-MM-DD”,”mood”:1-5或null,”feelings”:[],”confidence”:0.8,”reason”:””}
feelings 词表：开心/满足/兴奋/激动/感动/平静/放松/疲惫/焦虑/烦躁/沮丧/难过/失望/愤怒/孤独/困惑/无聊/好奇/自豪/遗憾（最多3个）

## task — 待办/提醒
{“kind”:”task”,”title”:””,”detail”:””,”date”:”YYYY-MM-DD”,”startTime”:”HH:mm”,”confidence”:0.8,”reason”:””}

## time — 已发生的时间记录
{“kind”:”time”,”title”:””,”detail”:””,”date”:”YYYY-MM-DD”,”module”:”工作|学习|运动|休息|社交|其他”,”startTime”:”HH:mm”,”endTime”:”HH:mm”,”confidence”:0.8,”reason”:””}

# 输出格式（严格 JSON）
{“reply”:”自然回复”,”followUpQuestion”:”一个追问或null”,”actionSuggestions”:[]}

# 规则
1. reply 简短自然，像可靠但不啰嗦的伙伴。每轮最多追问 1 个问题，不连续盘问。
2. followUpQuestion 非 null 时，actionSuggestions 必须为空 []。需要追问就不生成卡片。
3. 闲聊/不确定时只回复，不生成卡片。不要问”需要保存吗”，信息够就直接给卡片。
4. task 缺日期先追问日期，缺时间先追问时间，补齐后再生成卡片。
5. 梦境不做心理解读，记录时 inboxType 用”做梦”。感受要带 mood/feelings。
6. reason 只供内部使用，必须短。不重复生成同意图卡片。
7. 危机/自伤风险时温柔建议联系可信任的人。

{{AGENT_PERSONA}}
{{USER_PROFILE}}
{{CHAT_POLICY}}

currentDate: {{CURRENT_DATE}}
currentTime: {{CURRENT_TIME}}
contextSummary:
{{CONTEXT_SUMMARY}}`;

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, X-Client-Secret",
  "Access-Control-Max-Age": "86400",
};

export default {
  async fetch(request, env, ctx) {
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: CORS_HEADERS });
    }

    if (request.method !== "POST") {
      return jsonError(405, "method_not_allowed");
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

function makeTrace(env, ctx, body, mode) {
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

function emitTrace(env, ctx, event) {
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

async function handleParse(body, provider, apiKey, trace) {
  const text = (body.text || body.input || "").trim();
  const currentDate = body.currentDate || "";
  const currentTime = body.currentTime || "";

  if (!text) return jsonError(400, "empty_text");

  const systemPrompt = PARSE_SYSTEM_PROMPT
    .replace("{{CURRENT_DATE}}", currentDate)
    .replace("{{CURRENT_TIME}}", currentTime);

  const messages = [
    { role: "system", content: systemPrompt },
    { role: "user", content: text },
  ];
  trace("prompt_built", {
    model: provider.model,
    provider: "deepseek",
    temperature: 0.2,
    maxTokens: 700,
    payload: { messages },
  });

  const parsed = await callAIJSON(provider, apiKey, messages, 0.2, 700, 0, trace);

  if (parsed.errorResponse) return parsed.errorResponse;

  const records = Array.isArray(parsed.records) ? parsed.records : [];
  const needsClarification = typeof parsed.needsClarification === "string"
    ? parsed.needsClarification
    : null;
  trace("response_decoded", {
    model: provider.model,
    provider: "deepseek",
    usage: parsed.__usage || null,
    payload: {
      records,
      needsClarification,
      rawModelOutput: parsed.__rawModelOutput || "",
    },
  });

  return jsonOk({ records, needsClarification });
}

async function handleQuick(body, provider, apiKey, trace) {
  const input = (body.input || body.text || "").trim();
  const currentDate = body.currentDate || "";
  const currentTime = body.currentTime || "";

  if (!input) return jsonError(400, "empty_input");

  const systemPrompt = QUICK_SYSTEM_PROMPT
    .replace("{{CURRENT_DATE}}", currentDate)
    .replace("{{CURRENT_TIME}}", currentTime);

  const messages = [
    { role: "system", content: systemPrompt },
    { role: "user", content: input },
  ];
  trace("prompt_built", {
    model: provider.model,
    provider: "deepseek",
    temperature: 0.3,
    maxTokens: 500,
    payload: { messages },
  });

  const parsed = await callAIJSON(provider, apiKey, messages, 0.3, 500, 0, trace);

  if (parsed.errorResponse) return parsed.errorResponse;

  const reply = typeof parsed.reply === "string" && parsed.reply.trim()
    ? parsed.reply.trim()
    : "收到。";

  const followUpQuestion = typeof parsed.followUpQuestion === "string" && parsed.followUpQuestion.trim()
    ? parsed.followUpQuestion.trim()
    : null;

  const actionSuggestions = followUpQuestion !== null
    ? []
    : Array.isArray(parsed.actionSuggestions)
      ? parsed.actionSuggestions.map(normalizeActionSuggestion).filter(Boolean).slice(0, 2)
      : [];

  trace("response_decoded", {
    model: provider.model,
    provider: "deepseek",
    usage: parsed.__usage || null,
    payload: {
      reply,
      followUpQuestion,
      actionSuggestions,
      rawModelOutput: parsed.__rawModelOutput || "",
    },
  });

  return jsonOk({ reply, followUpQuestion, actionSuggestions, usage: parsed.__usage || null });
}

async function handleChat(body, provider, apiKey, trace) {
  const input = (body.input || body.text || "").trim();
  const currentDate = body.currentDate || "";
  const currentTime = body.currentTime || "";
  const contextSummary = String(body.contextSummary || "").slice(0, 4000);

  if (!input) return jsonError(400, "empty_input");

  const rawHistory = Array.isArray(body.messages)
    ? body.messages
        .filter((m) => m && (m.role === "user" || m.role === "assistant") && typeof m.content === "string")
        .slice(-6)
        .map((m) => ({
          role: m.role,
          content: m.content.slice(0, 800),
        }))
    : [];

  // 确保 user/assistant 交替，避免连续同角色消息导致 DeepSeek 返回空
  const history = [];
  for (const m of rawHistory) {
    if (history.length > 0 && history[history.length - 1].role === m.role) {
      // 同角色连续：合并内容而不是产生连续同角色消息
      history[history.length - 1].content += "\n" + m.content;
    } else {
      history.push({ ...m });
    }
  }
  // 最后一条如果是 user，去掉（因为当前 input 会作为新 user 消息追加）
  if (history.length > 0 && history[history.length - 1].role === "user") {
    history.pop();
  }

  const effectiveContext = history.length === 0 ? (contextSummary || "无") : "（已在首轮提供）";

  const systemPrompt = CHAT_SYSTEM_PROMPT
    .replace("{{AGENT_PERSONA}}", AGENT_PERSONA)
    .replace("{{USER_PROFILE}}", USER_PROFILE)
    .replace("{{CHAT_POLICY}}", CHAT_POLICY)
    .replace("{{CURRENT_DATE}}", currentDate)
    .replace("{{CURRENT_TIME}}", currentTime)
    .replace("{{CONTEXT_SUMMARY}}", effectiveContext);

  const messages = [
    { role: "system", content: systemPrompt },
    ...history,
    { role: "user", content: input },
  ];
  trace("prompt_built", {
    model: provider.model,
    provider: "deepseek",
    temperature: 0.5,
    maxTokens: 2048,
    payload: {
      messages,
      rawHistory,
      normalizedHistory: history,
      contextSummary,
      effectiveContext,
    },
  });

  const parsed = await callAIJSON(provider, apiKey, messages, 0.5, 2048, 0, trace);

  if (parsed.errorResponse) return parsed.errorResponse;

  const reply = typeof parsed.reply === "string" && parsed.reply.trim()
    ? parsed.reply.trim()
    : "我在。你可以继续说一点，我会慢慢跟上你的节奏。";

  const followUpQuestion = typeof parsed.followUpQuestion === "string" && parsed.followUpQuestion.trim()
    ? parsed.followUpQuestion.trim()
    : null;

  const shouldSuppressActions = followUpQuestion !== null;

  const actionSuggestions = shouldSuppressActions
    ? []
    : Array.isArray(parsed.actionSuggestions)
      ? parsed.actionSuggestions
          .map(normalizeActionSuggestion)
          .filter(Boolean)
          .slice(0, 2)
      : [];

  trace("response_decoded", {
    model: provider.model,
    provider: "deepseek",
    usage: parsed.__usage || null,
    payload: {
      reply,
      followUpQuestion,
      shouldSuppressActions,
      actionSuggestions,
      rawModelOutput: parsed.__rawModelOutput || "",
    },
  });

  return jsonOk({
    reply,
    followUpQuestion,
    actionSuggestions,
    debug: {
      rawModelOutput: parsed.__rawModelOutput || "",
      suppressedActionsReason: shouldSuppressActions ? "followUpQuestion_present" : null,
    },
    usage: parsed.__usage || null,
  });
}

async function handleUtility(body, provider, apiKey, trace) {
  const task = (body.task || "").trim();
  if (!task) return jsonError(400, "missing_task");

  if (task === "suggest_topics") {
    const title = (body.title || "").trim();
    const content = (body.content || "").trim();
    if (!title && !content) return jsonError(400, "empty_content");
    const prompt = `给以下笔记建议 2-4 个主题标签（中文短语，不带 # 号）。只返回 JSON：{"topics":["标签1","标签2"]}
标题：${title}
正文：${content}`;
    const messages = [
      { role: "system", content: "你是标签建议工具。只输出 JSON，不要解释。" },
      { role: "user", content: prompt },
    ];
    trace("prompt_built", {
      model: provider.model,
      provider: "deepseek",
      temperature: 0.2,
      maxTokens: 200,
      payload: { task, messages },
    });
    const parsed = await callAIJSON(provider, apiKey, messages, 0.2, 200, 0, trace);
    if (parsed.errorResponse) return parsed.errorResponse;
    const topics = Array.isArray(parsed.topics) ? parsed.topics.map(t => String(t).trim()).filter(Boolean).slice(0, 5) : [];
    trace("response_decoded", {
      model: provider.model,
      provider: "deepseek",
      usage: parsed.__usage || null,
      payload: { task, result: topics, rawModelOutput: parsed.__rawModelOutput || "" },
    });
    return jsonOk({ result: topics });
  }

  if (task === "suggest_title") {
    const content = (body.content || "").trim();
    if (!content) return jsonError(400, "empty_content");
    const prompt = `给以下笔记内容起一个简短标题（6-12个字，不要标点）。只返回 JSON：{"title":"标题"}
正文：${content}`;
    const messages = [
      { role: "system", content: "你是标题生成工具。只输出 JSON，不要解释。" },
      { role: "user", content: prompt },
    ];
    trace("prompt_built", {
      model: provider.model,
      provider: "deepseek",
      temperature: 0.2,
      maxTokens: 100,
      payload: { task, messages },
    });
    const parsed = await callAIJSON(provider, apiKey, messages, 0.2, 100, 0, trace);
    if (parsed.errorResponse) return parsed.errorResponse;
    const title = typeof parsed.title === "string" ? parsed.title.trim() : "";
    trace("response_decoded", {
      model: provider.model,
      provider: "deepseek",
      usage: parsed.__usage || null,
      payload: { task, result: title, rawModelOutput: parsed.__rawModelOutput || "" },
    });
    return jsonOk({ result: title });
  }

  if (task === "extract_memories") {
    const messages = Array.isArray(body.messages) ? body.messages : [];
    if (messages.length < 2) return jsonOk({ result: [] });
    const transcript = messages
      .map((m) => `${m.role === "user" ? "用户" : "AI"}: ${String(m.content || "").slice(0, 300)}`)
      .join("\n");
    const prompt = `从这段对话中提取 1-3 条值得长期记住的关键信息（用户的事实、偏好或重要结论）。每条不超过 30 字。只返回 JSON：{"memories":[{"content":"...","category":"fact|preference|summary"}]}

对话记录：
${transcript}`;
    const messagesForModel = [
      { role: "system", content: "你是记忆提取工具。只输出 JSON，不要解释。" },
      { role: "user", content: prompt },
    ];
    trace("prompt_built", {
      model: provider.model,
      provider: "deepseek",
      temperature: 0.2,
      maxTokens: 300,
      payload: { task, messages: messagesForModel, originalMessages: messages },
    });
    const parsed = await callAIJSON(provider, apiKey, messagesForModel, 0.2, 300, 0, trace);
    if (parsed.errorResponse) return parsed.errorResponse;
    const memories = Array.isArray(parsed.memories)
      ? parsed.memories
          .filter((m) => m && typeof m.content === "string" && m.content.trim())
          .map((m) => ({
            content: m.content.trim().slice(0, 60),
            category: ["fact", "preference", "summary"].includes(m.category) ? m.category : "fact",
          }))
          .slice(0, 3)
      : [];
    trace("response_decoded", {
      model: provider.model,
      provider: "deepseek",
      usage: parsed.__usage || null,
      payload: { task, result: memories, rawModelOutput: parsed.__rawModelOutput || "" },
    });
    return jsonOk({ result: memories });
  }

  return jsonError(400, "unknown_task", { task });
}

async function callAIJSON(provider, apiKey, messages, temperature, maxTokens = 2048, _retry = 0, trace = () => {}) {
  let upstream;
  const startedAt = Date.now();
  trace("model_call_started", {
    model: provider.model,
    provider: "deepseek",
    temperature,
    maxTokens,
    retry: { attempt: _retry },
  });
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
        temperature,
        thinking: { type: "disabled" },
        max_tokens: maxTokens,
        response_format: { type: "json_object" },
      }),
    });
  } catch (e) {
    trace("model_call_failed", {
      model: provider.model,
      provider: "deepseek",
      temperature,
      maxTokens,
      latencyMs: Date.now() - startedAt,
      retry: { attempt: _retry },
      error: {
        type: "ai_network_failed",
        message: String(e).slice(0, 200),
      },
    });
    return {
      errorResponse: jsonError(502, "ai_network_failed", {
        message: String(e).slice(0, 200),
      }),
    };
  }

  if (!upstream.ok) {
    const errText = await upstream.text();
    trace("model_call_failed", {
      model: provider.model,
      provider: "deepseek",
      temperature,
      maxTokens,
      latencyMs: Date.now() - startedAt,
      retry: { attempt: _retry },
      error: {
        type: "ai_upstream_failed",
        status: upstream.status,
        detail: errText.slice(0, 500),
      },
    });
    return {
      errorResponse: jsonError(502, "ai_upstream_failed", {
        provider: "deepseek",
        model: provider.model,
        status: upstream.status,
        detail: errText.slice(0, 200),
      }),
    };
  }

  const aiData = await upstream.json();
  const content = (aiData?.choices?.[0]?.message?.content ?? "").trim();

  if (!content) {
    trace("model_empty_response", {
      model: provider.model,
      provider: "deepseek",
      temperature,
      maxTokens,
      usage: aiData.usage || null,
      latencyMs: Date.now() - startedAt,
      retry: { attempt: _retry, willRetry: _retry < 2 },
      error: {
        type: "ai_empty_response",
        raw: JSON.stringify(aiData).slice(0, 800),
      },
    });
    if (_retry < 2) {
      return callAIJSON(provider, apiKey, messages, temperature, maxTokens, _retry + 1, trace);
    }
    return {
      errorResponse: jsonError(502, "ai_empty_response", {
        raw: JSON.stringify(aiData).slice(0, 300),
        retried: _retry,
      }),
    };
  }

  try {
    const parsed = JSON.parse(content);
    parsed.__rawModelOutput = content;
    parsed.__usage = aiData.usage || null;
    parsed.__latencyMs = Date.now() - startedAt;
    parsed.__retryAttempt = _retry;
    trace("model_call_finished", {
      model: provider.model,
      provider: "deepseek",
      temperature,
      maxTokens,
      usage: aiData.usage || null,
      cache: aiData.usage?.prompt_tokens_details || null,
      latencyMs: Date.now() - startedAt,
      retry: { attempt: _retry },
      payload: {
        rawResponse: aiData,
        rawModelOutput: content,
      },
    });
    return parsed;
  } catch {
    trace("model_call_failed", {
      model: provider.model,
      provider: "deepseek",
      temperature,
      maxTokens,
      usage: aiData.usage || null,
      latencyMs: Date.now() - startedAt,
      retry: { attempt: _retry },
      error: {
        type: "ai_response_not_json",
        sample: content.slice(0, 500),
      },
    });
    return {
      errorResponse: jsonError(500, "ai_response_not_json", {
        sample: content.slice(0, 200),
      }),
    };
  }
}

function normalizeActionSuggestion(action) {
  if (!action || typeof action !== "object") return null;

  const kind = String(action.kind || "").trim();
  if (!["inbox", "task", "time"].includes(kind)) return null;

  const title = String(action.title || "").trim();
  if (!title) return null;

  const confidenceNumber = Number(action.confidence);
  const confidence = Number.isFinite(confidenceNumber)
    ? Math.max(0, Math.min(1, confidenceNumber))
    : 0.6;

  return {
    kind,
    inboxType: normalizeInboxType(action.inboxType || action.type),
    mood: normalizeMood(action.mood),
    feelings: normalizeFeelings(action.feelings),
    module: normalizeTimeModule(action.module),
    title,
    detail: typeof action.detail === "string" ? action.detail : "",
    date: typeof action.date === "string" && action.date ? action.date : null,
    startTime: typeof action.startTime === "string" && action.startTime ? action.startTime : null,
    endTime: typeof action.endTime === "string" && action.endTime ? action.endTime : null,
    confidence,
    reason: typeof action.reason === "string" ? action.reason : "",
  };
}

function normalizeInboxType(value) {
  const inboxType = String(value || "").trim();
  return ["想法", "感受", "感恩", "做梦"].includes(inboxType) ? inboxType : null;
}

function normalizeMood(value) {
  const mood = Number(value);
  return Number.isInteger(mood) && mood >= 1 && mood <= 5 ? mood : null;
}

function normalizeFeelings(value) {
  const allowed = new Set(["开心", "满足", "兴奋", "激动", "感动", "平静", "放松", "疲惫", "焦虑", "烦躁", "沮丧", "难过", "失望", "愤怒", "孤独", "困惑", "无聊", "好奇", "自豪", "遗憾"]);
  if (!Array.isArray(value)) return [];
  const seen = new Set();
  return value
    .map((item) => String(item || "").trim())
    .filter((item) => allowed.has(item))
    .filter((item) => {
      if (seen.has(item)) return false;
      seen.add(item);
      return true;
    })
    .slice(0, 3);
}

function normalizeTimeModule(value) {
  const module = String(value || "").trim();
  return ["工作", "学习", "运动", "休息", "社交", "其他"].includes(module) ? module : null;
}

function jsonOk(payload) {
  return new Response(JSON.stringify(payload), {
    status: 200,
    headers: { "Content-Type": "application/json", ...CORS_HEADERS },
  });
}

function jsonError(status, error, extra = {}) {
  return new Response(JSON.stringify({ error, ...extra }), {
    status,
    headers: { "Content-Type": "application/json", ...CORS_HEADERS },
  });
}
