import { normalizeInboxType, normalizeMood, normalizeFeelings, normalizeTimeModule } from "./normalizers.js";

// Self-correction Layer 1: Rule-based validation
// Zero-cost checks that catch obvious LLM mistakes before they reach the user.
// Returns the action with adjusted confidence, or null if fatally wrong.
export function validateActionSuggestion(action, userInput, currentDate) {
  if (!action) return null;
  let conf = action.confidence;
  const issues = [];

  // 1. Date sanity: action date should be within ±30 days of today
  if (action.date) {
    const actionDate = new Date(action.date + "T00:00:00");
    const today = currentDate ? new Date(currentDate + "T00:00:00") : new Date();
    if (!isNaN(actionDate.getTime()) && !isNaN(today.getTime())) {
      const diffDays = Math.abs((actionDate - today) / 86400000);
      if (diffDays > 30) {
        issues.push("date_out_of_range");
        conf = Math.min(conf, 0.3);
      }
    }
  }

  // 2. Time logic: endTime should be after startTime (same day)
  if (action.startTime && action.endTime) {
    const [sh, sm] = action.startTime.split(":").map(Number);
    const [eh, em] = action.endTime.split(":").map(Number);
    if (sh * 60 + sm > eh * 60 + em) {
      issues.push("end_before_start");
      conf = Math.min(conf, 0.4);
    }
  }

  // 3. Title faithfulness: for create actions, at least one keyword from
  //    the title should appear in the user's input (prevents fabrication)
  if (userInput && action.title && !["editTask","editTime","editInbox","deleteTask","deleteTime","deleteInbox","completeTask"].includes(action.kind)) {
    const titleWords = action.title.replace(/[^一-鿿\w]/g, " ").split(/\s+/).filter(w => w.length >= 2);
    const inputLower = userInput.toLowerCase();
    const matchCount = titleWords.filter(w => inputLower.includes(w.toLowerCase())).length;
    if (titleWords.length > 0 && matchCount === 0) {
      issues.push("title_not_in_input");
      conf = Math.min(conf, 0.5);
    }
  }

  // 4. Empty critical fields
  if (action.kind === "time" && (!action.startTime || !action.endTime)) {
    issues.push("time_missing_range");
    conf = Math.min(conf, 0.5);
  }

  return { ...action, confidence: conf, _validationIssues: issues.length > 0 ? issues : undefined };
}

export function normalizeActionSuggestion(action) {
  if (!action || typeof action !== "object") return null;

  const kind = String(action.kind || "").trim();
  const validKinds = ["inbox", "brain", "task", "time", "calendarEvent", "editTask", "editTime", "editInbox", "deleteTask", "deleteTime", "deleteInbox", "completeTask"];
  if (!validKinds.includes(kind)) return null;

  const isMutation = kind.startsWith("edit") || kind.startsWith("delete") || kind === "completeTask";
  const targetId = typeof action.targetId === "string" ? action.targetId.trim() : null;
  if (isMutation && !targetId) return null;

  const title = String(action.title || "").trim();
  if (!isMutation && !title) return null;

  const confidenceNumber = Number(action.confidence);
  const confidence = Number.isFinite(confidenceNumber)
    ? Math.max(0, Math.min(1, confidenceNumber))
    : 0.6;

  return {
    kind,
    targetId: targetId || undefined,
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

/** Limit actions: max 8 create, max 3 mutation, mutations + creates don't mix */
export function limitActionSuggestions(actions) {
  const mutations = actions.filter(a => ["editTask","editTime","deleteTask","deleteTime","completeTask"].includes(a.kind));
  const creates = actions.filter(a => ["inbox","brain","task","time","calendarEvent"].includes(a.kind));
  if (mutations.length > 0) return mutations.slice(0, 3);
  return coalescedTimeActions(creates).slice(0, 8);
}

function coalescedTimeActions(actions) {
  const kept = [];
  for (const action of actions) {
    if (action.kind !== "time") {
      kept.push(action);
      continue;
    }

    const range = timeRange(action);
    if (!range) {
      kept.push(action);
      continue;
    }

    const existingIndex = kept.findIndex(existing => {
      if (existing.kind !== "time") return false;
      if ((existing.date || "") !== (action.date || "")) return false;
      const existingRange = timeRange(existing);
      return existingRange && rangesOverlap(range, existingRange);
    });

    if (existingIndex === -1) {
      kept.push(action);
    } else if (timeActionScore(action) > timeActionScore(kept[existingIndex])) {
      kept[existingIndex] = action;
    }
  }
  return kept;
}

function timeRange(action) {
  const start = clockMinutes(action.startTime, false);
  const end = clockMinutes(action.endTime, true);
  if (start === null || end === null || end <= start) return null;
  return { start, end };
}

function clockMinutes(value, allow24) {
  if (typeof value !== "string") return null;
  const match = value.match(/^(\d{1,2}):(\d{2})$/);
  if (!match) return null;
  const hour = Number(match[1]);
  const minute = Number(match[2]);
  if (!Number.isInteger(hour) || !Number.isInteger(minute) || minute < 0 || minute > 59) return null;
  if (allow24 && hour === 24 && minute === 0) return 24 * 60;
  if (hour < 0 || hour > 23) return null;
  return hour * 60 + minute;
}

function rangesOverlap(lhs, rhs) {
  return Math.max(lhs.start, rhs.start) < Math.min(lhs.end, rhs.end);
}

function timeActionScore(action) {
  const fields = [action.title, action.detail, action.date, action.startTime, action.endTime, action.reason];
  const completeness = fields.reduce((score, value) => {
    return score + (typeof value === "string" && value.trim() ? 1 : 0);
  }, 0);
  return completeness * 100 + String(action.detail || "").trim().length + String(action.title || "").trim().length;
}
