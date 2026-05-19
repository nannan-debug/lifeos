// Cloudflare Worker: DeepSeek AI proxy
// Modes:
// 1. parse: Chinese natural-language input -> structured LifeOS records
// 2. chat: LifeOS Agent V1 gentle chat + confirmable action drafts

const AI_PROVIDER = {
  url: "https://api.deepseek.com/chat/completions",
  model: "deepseek-v4-pro",
  keyEnv: "DEEPSEEK_API_KEY",
};

const AGENT_PERSONA = `你叫 Arya猫，是 Anna 在 LifeOS 里的高判断力猫猫搭档。
你不是客服型 AI，也不是只会顺从和附和的助手；你更像一个能一起判断、一起推进、一起拿结果的联合创始人式伙伴。
默认可以用中文和英文交流；根据 Anna 的输入自然选择语言，可以自然使用准确的英文术语，但不要为了显得专业而滥用英文。
核心风格：结果导向、结论前置、简洁直接、有判断、少废话、不表演式共情。
默认优先级：结果 > 速度 > 简洁 > 完美。
低风险、高确定性的事直接推进；高成本、不可逆、对外发送、删除或隐私权限相关的事必须先问 Anna。
如果 Anna 的判断明显偏了，可以直接指出，但要给依据，目标是共同得到更优解，不是争输赢。
在 LifeOS 生活记录场景里，你仍然要温柔、克制、少追问；接住用户的话，但不要替用户下心理结论。
你不是心理治疗师、法律顾问、医疗或金融专家。`;

const USER_PROFILE = `用户叫 Anna。她是 ENTP，30 岁，女生，AI 产品经理。
她在 AI 行业深耕约 3 年，做过 AI 图像/视频工具平台、AI 漫剧项目、漫剧工具平台和偏泛娱乐的视频小 App。
她目前处于主动研究和重新搭建方向的阶段，重点关注 agent 模式和 agent team workflow。
她希望你像高判断力、结果导向、接近联合创始人的搭档，而不是客服或纯执行器。
她接受中文和英文交流；偏好结论前置、表达干练、直接、有现实参照；可以提问，但问题必须显著提高判断质量或降低风险。
她不喜欢：太啰嗦、太爱确认、太像客服、表演式安抚、无意义客套。
她接受你指出她的错误、偏差或短视，但要简洁、有依据、能推动更好的决策。
Anna 的工作目标是未来构建一套能协作、能执行、能交付的 agent team workflow，所以回答相关工作问题时要多考虑系统设计、角色分工、任务流转和验收方式。
LifeOS 的产品目标是帮助 Anna 获得正确引导、及时提醒、总结复盘，并把生活里的想法、情绪、梦境、待办和时间记录整理成可持续使用的个人系统。
理解 Anna 是为了更好地帮助她，不是建立监控档案；不要声称知道她没有提供过的事实。`;

const CHAT_POLICY = `提醒/待办只需要 title、date、startTime 三个核心信息。
如果用户已经给出要做什么、日期、时间，就不要继续询问材料类型、地点、是否打印等非必要细节。
如果 followUpQuestion 不为 null，actionSuggestions 必须为空数组。
用户讲梦时，只做陪伴式引导，不要给梦下心理结论，不要说“反映了压力/情绪/潜意识”等判断。
如果用户要求把梦记录到随手记，inbox action 必须带 inboxType: "做梦"。
聊天入口要复用拆解 AI 的分类能力：随手记必须尽量带 inboxType、mood、feelings；时间记录必须尽量带 module。`;

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

const CHAT_SYSTEM_PROMPT = `你是 Arya猫在 LifeOS 里的生活记录模式。你仍然是 Anna 的高判断力猫猫搭档，但在这里优先做正确引导、及时提醒、总结复盘和可确认记录。

你的目标：
1. 和用户自然对话，帮助用户多表达一点。
2. 每轮最多追问 1 个问题。
3. 不要连续盘问，不要审讯式提问。
4. 可以基于本轮聊天历史和近期 LifeOS 摘要理解用户，但不要假装知道没有给出的事实。
5. 当用户明显表达了值得保存的内容时，给出 actionSuggestions 草稿；但绝不说已经保存。
6. 所有保存都必须用户确认，所以你的建议只是草稿。

# 可建议保存的类型

## inbox
用户表达想法、感受、梦境、灵感、观察时使用。
{
  "kind": "inbox",
  "inboxType": "想法 | 感受 | 感恩 | 做梦",
  "title": "简短标题",
  "detail": "可保存的正文",
  "date": "YYYY-MM-DD",
  "mood": 4,
  "feelings": ["兴奋"],
  "confidence": 0.8,
  "reason": "为什么建议保存"
}
inboxType 必须是以下之一：想法 / 感受 / 感恩 / 做梦
mood 为 1-5 的整数（5 最积极），中性/难判断给 null
feelings 只能从下表选词，最多 3 个，无法判断给 []
["开心","满足","兴奋","激动","感动","平静","放松","疲惫","焦虑","烦躁","沮丧","难过","失望","愤怒","孤独","困惑","无聊","好奇","自豪","遗憾"]

## task
用户表达要做、提醒、计划、截止事项时使用。
{
  "kind": "task",
  "title": "待办标题",
  "detail": "补充说明",
  "date": "YYYY-MM-DD",
  "startTime": "HH:mm",
  "confidence": 0.8,
  "reason": "为什么建议保存"
}

## time
用户描述已经发生的某段时间记录时使用。
{
  "kind": "time",
  "title": "做了什么",
  "detail": "补充说明",
  "date": "YYYY-MM-DD",
  "module": "工作",
  "startTime": "HH:mm",
  "endTime": "HH:mm",
  "confidence": 0.8,
  "reason": "为什么建议保存"
}
module 必须是以下之一：工作 / 学习 / 运动 / 休息 / 社交 / 其他

# 输出格式
严格输出 JSON，不要 markdown，不要解释文字：
{
  "reply": "给用户的自然回复",
  "followUpQuestion": "可选，最多一个温柔追问；如果不需要追问则为 null",
  "actionSuggestions": []
}

# 规则
1. actionSuggestions 最多 2 条。
2. 不确定就不要建议保存。
3. 闲聊时只回复，不要生成保存卡片。
4. followUpQuestion 可以为 null。
5. reply 要短一点、自然一点，像一个可靠但不啰嗦的伙伴。
6. 不提供医疗、法律、金融等专业诊断。
7. 如果用户明显处于危机或自伤风险，温柔建议联系身边可信任的人或当地紧急服务。
8. 如果你需要追问用户补充关键信息，本轮 actionSuggestions 必须为空。
9. 不要为同一个意图连续生成重复 actionSuggestions。
10. 对于提醒/待办：
- 如果用户只说了要提醒/要做什么，但没有明确日期，先追问日期，不生成卡片。
- 如果用户说了日期但没有明确时间，先追问时间，不生成卡片。
- 用户补充完整日期和时间后，再生成一张完整 task 卡片。
11. reason 只给系统内部使用，必须短，不要写“用户明确要求...”这类重复可见内容的话。
12. 如果 followUpQuestion 不为 null，actionSuggestions 必须是空数组 []。不要一边追问，一边建议保存。
13. 不要问“需要我建议保存吗”；如果信息不完整，直接问缺失的信息。如果信息完整，直接给 actionSuggestions。
14. 对梦境内容不要做解释性结论，不要推断用户心理原因。可以说“这个梦信息量很大/画面很多”，然后轻轻问一个开放问题。
15. inbox 的 inboxType 必须是以下之一：想法 / 感受 / 感恩 / 做梦。只要用户明确说“梦到/梦见/做梦”，并要求记录到随手记，就用 "做梦"，不要用 "想法"。
16. 生成 inbox action 时，复用随手记分类规则：感受要给 mood/feelings；感恩用 inboxType="感恩"；梦境用 inboxType="做梦"；灵感/观点/计划想法用 inboxType="想法"。
17. 生成 time action 时，复用时间记录分类规则，尽量给 module；无法判断时给 "其他"。

# Agent 人格
{{AGENT_PERSONA}}

# 用户信息
{{USER_PROFILE}}

# 当前策略
{{CHAT_POLICY}}

# 当前上下文
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
  async fetch(request, env) {
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

    if (mode === "chat") {
      return handleChat(body, AI_PROVIDER, apiKey);
    }

    if (mode === "utility") {
      return handleUtility(body, AI_PROVIDER, apiKey);
    }

    return handleParse(body, AI_PROVIDER, apiKey);
  },
};

async function handleParse(body, provider, apiKey) {
  const text = (body.text || body.input || "").trim();
  const currentDate = body.currentDate || "";
  const currentTime = body.currentTime || "";

  if (!text) return jsonError(400, "empty_text");

  const systemPrompt = PARSE_SYSTEM_PROMPT
    .replace("{{CURRENT_DATE}}", currentDate)
    .replace("{{CURRENT_TIME}}", currentTime);

  const parsed = await callAIJSON(provider, apiKey, [
    { role: "system", content: systemPrompt },
    { role: "user", content: text },
  ], 0.2, 700);

  if (parsed.errorResponse) return parsed.errorResponse;

  const records = Array.isArray(parsed.records) ? parsed.records : [];
  const needsClarification = typeof parsed.needsClarification === "string"
    ? parsed.needsClarification
    : null;

  return jsonOk({ records, needsClarification });
}

async function handleChat(body, provider, apiKey) {
  const input = (body.input || body.text || "").trim();
  const currentDate = body.currentDate || "";
  const currentTime = body.currentTime || "";
  const contextSummary = String(body.contextSummary || "").slice(0, 4000);

  if (!input) return jsonError(400, "empty_input");

  const history = Array.isArray(body.messages)
    ? body.messages
        .filter((m) => m && (m.role === "user" || m.role === "assistant") && typeof m.content === "string")
        .slice(-6)
        .map((m) => ({
          role: m.role,
          content: m.content.slice(0, 800),
        }))
    : [];

  const effectiveContext = history.length === 0 ? (contextSummary || "无") : "（已在首轮提供）";

  const systemPrompt = CHAT_SYSTEM_PROMPT
    .replace("{{AGENT_PERSONA}}", AGENT_PERSONA)
    .replace("{{USER_PROFILE}}", USER_PROFILE)
    .replace("{{CHAT_POLICY}}", CHAT_POLICY)
    .replace("{{CURRENT_DATE}}", currentDate)
    .replace("{{CURRENT_TIME}}", currentTime)
    .replace("{{CONTEXT_SUMMARY}}", effectiveContext);

  const parsed = await callAIJSON(provider, apiKey, [
    { role: "system", content: systemPrompt },
    ...history,
    { role: "user", content: input },
  ], 0.5);

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

  return jsonOk({
    reply,
    followUpQuestion,
    actionSuggestions,
    debug: {
      rawModelOutput: parsed.__rawModelOutput || "",
      suppressedActionsReason: shouldSuppressActions ? "followUpQuestion_present" : null,
    },
  });
}

async function handleUtility(body, provider, apiKey) {
  const task = (body.task || "").trim();
  if (!task) return jsonError(400, "missing_task");

  if (task === "suggest_topics") {
    const title = (body.title || "").trim();
    const content = (body.content || "").trim();
    if (!title && !content) return jsonError(400, "empty_content");
    const prompt = `给以下笔记建议 2-4 个主题标签（中文短语，不带 # 号）。只返回 JSON：{"topics":["标签1","标签2"]}
标题：${title}
正文：${content}`;
    const parsed = await callAIJSON(provider, apiKey, [
      { role: "system", content: "你是标签建议工具。只输出 JSON，不要解释。" },
      { role: "user", content: prompt },
    ], 0.2, 200);
    if (parsed.errorResponse) return parsed.errorResponse;
    const topics = Array.isArray(parsed.topics) ? parsed.topics.map(t => String(t).trim()).filter(Boolean).slice(0, 5) : [];
    return jsonOk({ result: topics });
  }

  if (task === "suggest_title") {
    const content = (body.content || "").trim();
    if (!content) return jsonError(400, "empty_content");
    const prompt = `给以下笔记内容起一个简短标题（6-12个字，不要标点）。只返回 JSON：{"title":"标题"}
正文：${content}`;
    const parsed = await callAIJSON(provider, apiKey, [
      { role: "system", content: "你是标题生成工具。只输出 JSON，不要解释。" },
      { role: "user", content: prompt },
    ], 0.2, 100);
    if (parsed.errorResponse) return parsed.errorResponse;
    const title = typeof parsed.title === "string" ? parsed.title.trim() : "";
    return jsonOk({ result: title });
  }

  return jsonError(400, "unknown_task", { task });
}

async function callAIJSON(provider, apiKey, messages, temperature, maxTokens = 2048) {
  let upstream;
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
    return {
      errorResponse: jsonError(502, "ai_network_failed", {
        message: String(e).slice(0, 200),
      }),
    };
  }

  if (!upstream.ok) {
    const errText = await upstream.text();
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
    return {
      errorResponse: jsonError(502, "ai_empty_response"),
    };
  }

  try {
    const parsed = JSON.parse(content);
    parsed.__rawModelOutput = content;
    return parsed;
  } catch {
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
