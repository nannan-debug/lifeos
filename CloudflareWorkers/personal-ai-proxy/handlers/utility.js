import { callAIJSON } from "../lib/ai-client.js";
import { jsonOk, jsonError } from "../lib/http.js";

export async function handleUtility(body, provider, apiKey, trace) {
  const task = (body.task || "").trim();
  if (!task) return jsonError(400, "missing_task");

  if (task === "suggest_topics") {
    const title = (body.title || "").trim();
    const content = (body.content || "").trim();
    if (!title && !content) return jsonError(400, "empty_content");
    const prompt = `给以下笔记建议 1-2 个主题标签。只能从这些固定主题中选择：生活、工作、学习、读书摘要、情绪、灵感。
选择规则：
- 工作：职业、项目、产品、技术、行业、商业、会议、客户、面试
- 学习：课程、考试、论文、研究、教程、知识整理
- 读书摘要：书摘、读后感、阅读笔记、文章/书籍摘要
- 生活：健康、饮食、睡眠、运动、家务、旅行、日常安排
- 情绪：感受、心情、焦虑、失望、开心、压力、DBT
- 灵感：创意、点子、设计想法、非工作语境下的观察和洞察
只返回 JSON：{"topics":["工作"]}
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
    const topics = normalizeBrainTopics(parsed.topics, `${title} ${content}`);
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
    const prompt = `给以下笔记内容起一个相对完整的简短标题（8-20个字，保留核心主谓宾，不要标点，不要从短语中间截断）。只返回 JSON：{"title":"标题"}
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
    const prompt = `从这段对话中提取 1-3 条值得猫猫后续陪伴用户时记住的关键信息。每条不超过 30 字。

区分 scope：
- "profile"：长期画像，如身份、职业、长期目标、稳定背景（如"用户是产品经理"）
- "preference"：互动偏好和边界（如"用户喜欢简洁回答"、"用户不想被催"）
- "state"：近期状态或情绪阶段（如"最近在学 Swift"、"这几天压力大"）
- "plan"：短期计划或明确时间事件（如"下周有面试"、"周五要提交材料"）

不要提取医疗诊断、敏感推断或你不确定的私人事实。
只返回 JSON：{"memories":[{"content":"...","category":"fact|preference|summary","scope":"profile|preference|state|plan","confidence":0.0到1.0}]}

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
            scope: ["profile", "preference", "state", "plan"].includes(m.scope) ? m.scope : "state",
            confidence: typeof m.confidence === "number" ? Math.max(0, Math.min(1, m.confidence)) : 0.75,
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

const FIXED_BRAIN_TOPICS = ["生活", "工作", "学习", "读书摘要", "情绪", "灵感"];

function normalizeBrainTopics(rawTopics, context) {
  const result = [];
  if (Array.isArray(rawTopics)) {
    for (const raw of rawTopics) appendTopic(result, mapBrainTopic(raw, context));
  }
  for (const topic of inferBrainTopics(context)) appendTopic(result, topic);
  return result.slice(0, 2);
}

function appendTopic(result, topic) {
  if (topic && FIXED_BRAIN_TOPICS.includes(topic) && !result.includes(topic)) {
    result.push(topic);
  }
}

function mapBrainTopic(raw, context) {
  const clean = String(raw || "").trim().replace(/^[#＃]+|[#＃]+$/g, "");
  if (!clean) return null;
  if (clean === "灵感" && hasWorkSignal(context)) return "工作";
  if (FIXED_BRAIN_TOPICS.includes(clean)) return clean;
  if (/(读书|书摘|阅读)/i.test(clean)) return "读书摘要";
  if (/(情绪|感受|心情)/i.test(clean)) return "情绪";
  if (/(工作|职业|产品|技术|行业|商业)/i.test(clean)) return "工作";
  if (/(学习|研究|课程)/i.test(clean)) return "学习";
  if (/(生活|健康|日常)/i.test(clean)) return "生活";
  if (/(灵感|想法|创意|观察)/i.test(clean)) return hasWorkSignal(context) ? "工作" : "灵感";
  return null;
}

function inferBrainTopics(text) {
  const rules = [
    ["读书摘要", ["读书", "书摘", "读后感", "阅读", "摘录", "摘要", "书里", "这本书"]],
    ["工作", ["工作", "项目", "产品", "会议", "客户", "同事", "PRD", "需求", "开发", "代码", "技术", "行业", "公司", "面试", "taste"]],
    ["学习", ["学习", "课程", "考试", "复习", "论文", "知识", "研究", "教程"]],
    ["生活", ["生活", "吃饭", "睡觉", "运动", "打球", "休息", "健康"]],
    ["情绪", ["情绪", "感受", "焦虑", "开心", "难过", "失望", "压力", "DBT", "心情"]],
    ["灵感", ["灵感", "想法", "创意", "点子", "设计", "观察", "洞察", "突然想到"]],
  ];
  const result = [];
  for (const [topic, keywords] of rules) {
    if (keywords.some((keyword) => text.toLowerCase().includes(keyword.toLowerCase()))) {
      result.push(topic);
      if (result.length === 2) break;
    }
  }
  return result;
}

function hasWorkSignal(text) {
  return ["工作", "项目", "产品", "技术", "行业", "商业", "公司", "客户", "需求", "PRD", "taste"].some((keyword) =>
    text.toLowerCase().includes(keyword.toLowerCase())
  );
}
