import { PARSE_SYSTEM_PROMPT } from "../agent/prompts.js";
import { callAIJSON } from "../lib/ai-client.js";
import { jsonOk, jsonError } from "../lib/http.js";

export async function handleParse(body, provider, apiKey, trace) {
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
