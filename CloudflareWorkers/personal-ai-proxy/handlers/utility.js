import { callAIJSON } from "../lib/ai-client.js";
import { jsonOk, jsonError } from "../lib/http.js";

export async function handleUtility(body, provider, apiKey, trace) {
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
    const prompt = `从这段对话中提取 1-3 条值得长期记住的关键信息。每条不超过 30 字。

区分 scope：
- "profile"：关于用户身份、性格、长期偏好、职业等不容易变的信息（如"用户是产品经理"、"不喜欢啰嗦"）
- "memory"：近期事件、短期状态、具体计划（如"下午要面试"、"最近在学 Swift"）

只返回 JSON：{"memories":[{"content":"...","category":"fact|preference|summary","scope":"profile|memory"}]}

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
            scope: m.scope === "profile" ? "profile" : "memory",
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
