import { QUICK_SYSTEM_PROMPT } from "../agent/prompts.js";
import { callAIJSON } from "../lib/ai-client.js";
import { validateActionSuggestion, normalizeActionSuggestion, limitActionSuggestions } from "../lib/actions.js";
import { jsonOk, jsonError } from "../lib/http.js";

export async function handleQuick(body, provider, apiKey, trace) {
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
  const maxTokens = input.length > 80 ? 1500 : 500;
  trace("prompt_built", {
    model: provider.model,
    provider: "deepseek",
    temperature: 0.3,
    maxTokens,
    payload: { messages },
  });

  const parsed = await callAIJSON(provider, apiKey, messages, 0.3, maxTokens, 0, trace);

  if (parsed.errorResponse) return parsed.errorResponse;

  const reply = typeof parsed.reply === "string" && parsed.reply.trim()
    ? parsed.reply.trim()
    : "收到。";

  const followUpQuestion = typeof parsed.followUpQuestion === "string" && parsed.followUpQuestion.trim()
    ? parsed.followUpQuestion.trim()
    : null;

  const text = body.text || body.input || "";
  const actionSuggestions = followUpQuestion !== null
    ? []
    : Array.isArray(parsed.actionSuggestions)
      ? limitActionSuggestions(parsed.actionSuggestions.map(normalizeActionSuggestion).filter(Boolean)
          .map(a => validateActionSuggestion(a, text, currentDate)).filter(Boolean))
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
