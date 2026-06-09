import { jsonError } from "./http.js";

export const AI_PROVIDER = {
  url: "https://api.deepseek.com/chat/completions",
  model: "deepseek-v4-pro",
  keyEnv: "DEEPSEEK_API_KEY",
};

export const STREAM_JSON_DELIMITER = "<<<JSON>>>";

export function compactMessageContent(value, maxLength = 1200) {
  const text = String(value || "");
  if (text.length <= maxLength) return text;
  const headLength = Math.floor(maxLength * 0.45);
  const marker = "\n…（中间省略，保留末尾以便理解确认/追问）…\n";
  const tailLength = Math.max(200, maxLength - headLength - marker.length);
  return `${text.slice(0, headLength)}${marker}${text.slice(-tailLength)}`;
}

export function extractFirstJSONObject(text) {
  const start = text.indexOf("{");
  if (start === -1) return null;
  let depth = 0;
  let inString = false;
  let escaped = false;
  for (let i = start; i < text.length; i++) {
    const ch = text[i];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (ch === "\\") {
        escaped = true;
      } else if (ch === "\"") {
        inString = false;
      }
      continue;
    }
    if (ch === "\"") {
      inString = true;
    } else if (ch === "{") {
      depth += 1;
    } else if (ch === "}") {
      depth -= 1;
      if (depth === 0) return text.slice(start, i + 1);
    }
  }
  return null;
}

export async function callAIJSON(provider, apiKey, messages, temperature, maxTokens = 2048, _retry = 0, trace = () => {}, useJsonFormat = true) {
  let upstream;
  const startedAt = Date.now();
  trace("model_call_started", {
    model: provider.model,
    provider: "deepseek",
    temperature,
    maxTokens,
    retry: { attempt: _retry },
  });
  const bodyObj = {
    model: provider.model,
    messages,
    temperature,
    max_tokens: maxTokens,
  };
  if (useJsonFormat) {
    bodyObj.response_format = { type: "json_object" };
  }
  try {
    upstream = await fetch(provider.url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${apiKey}`,
      },
      body: JSON.stringify(bodyObj),
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
  const msg = aiData?.choices?.[0]?.message;
  const content = (msg?.content || msg?.reasoning_content || "").trim();

  if (!content) {
    const rawContent = (msg?.content || "");
    const isWhitespaceOnly = rawContent.length > 0 && !rawContent.trim();
    trace("model_empty_response", {
      model: provider.model,
      provider: "deepseek",
      temperature,
      maxTokens,
      usage: aiData.usage || null,
      latencyMs: Date.now() - startedAt,
      retry: { attempt: _retry, willRetry: _retry < 3 },
      error: {
        type: isWhitespaceOnly ? "ai_whitespace_response" : "ai_empty_response",
        raw: JSON.stringify(aiData).slice(0, 800),
      },
    });
    if (_retry < 3) {
      const dropFormat = useJsonFormat && _retry >= 0;
      const nextFormat = dropFormat ? false : useJsonFormat;
      let nextMessages = messages;
      let nextTemp = temperature;
      if (_retry >= 1) {
        nextTemp = 0.3;
        const nudge = { role: "user", content: "请直接用 JSON 格式回复，不要输出空格或空行。" };
        nextMessages = [...messages, nudge];
      }
      if (_retry >= 2) {
        const system = messages.find(m => m.role === "system");
        const lastUser = [...messages].reverse().find(m => m.role === "user");
        nextMessages = [system, { role: "user", content: lastUser.content + "\n\n请直接用 JSON 格式回复。" }].filter(Boolean);
        nextTemp = 0.1;
      }
      return callAIJSON(provider, apiKey, nextMessages, nextTemp, maxTokens, _retry + 1, trace, nextFormat);
    }
    return {
      errorResponse: jsonError(502, "ai_empty_response", {
        raw: JSON.stringify(aiData).slice(0, 300),
        retried: _retry,
      }),
    };
  }

  const cleaned = content.replace(/^```(?:json)?\s*\n?/i, "").replace(/\n?```\s*$/i, "").trim();
  try {
    const parsed = JSON.parse(cleaned);
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
    const fallback = {
      reply: cleaned,
      followUpQuestion: null,
      actionSuggestions: [],
      __rawModelOutput: content,
      __usage: aiData.usage || null,
      __latencyMs: Date.now() - startedAt,
      __retryAttempt: _retry,
      __textFallback: true,
    };
    trace("model_call_finished", {
      model: provider.model,
      provider: "deepseek",
      temperature,
      maxTokens,
      usage: aiData.usage || null,
      latencyMs: Date.now() - startedAt,
      retry: { attempt: _retry },
      payload: {
        rawModelOutput: content,
        textFallback: true,
      },
    });
    return fallback;
  }
}
