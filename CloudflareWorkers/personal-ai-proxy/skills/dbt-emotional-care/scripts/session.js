import { DBT_STEP_REGISTRY } from "../references/step-registry.js";

export function normalizeDBTSkillId(value) {
  const id = String(value || "").trim();
  const allowed = new Set(["check_the_facts", "opposite_action", "wise_mind", "tipp", "stop", "dear_man", "behavior_chain_analysis", "validation"]);
  return allowed.has(id) ? id : "validation";
}

export function dbtStepsForSkill(skillId) {
  const clean = normalizeDBTSkillId(skillId);
  return DBT_STEP_REGISTRY[clean] || DBT_STEP_REGISTRY.validation;
}

export function isDBTBootstrapInput(input) {
  const text = String(input || "");
  return text.includes("用户已同意开始 DBT 练习") || text.includes("开始第 1 步");
}

export function clampDBTStep(session) {
  const steps = dbtStepsForSkill(session.skillId);
  const maxIndex = Math.max(steps.length - 1, 0);
  return {
    ...session,
    currentStepIndex: Math.max(0, Math.min(Number(session.currentStepIndex) || 0, maxIndex)),
  };
}

export function normalizeDBTSession(value, fallback = {}, currentDate = "", threadId = "") {
  const src = value && typeof value === "object" ? value : {};
  const prev = fallback && typeof fallback === "object" ? fallback : {};
  const skillId = normalizeDBTSkillId(src.skillId || prev.skillId);
  const status = ["active", "completed", "cancelled"].includes(String(src.status || "").trim())
    ? String(src.status).trim()
    : (["active", "completed", "cancelled"].includes(String(prev.status || "").trim()) ? String(prev.status).trim() : "active");
  const stepAnswers = Array.isArray(src.stepAnswers) ? src.stepAnswers : (Array.isArray(prev.stepAnswers) ? prev.stepAnswers : []);
  return {
    sessionId: String(src.sessionId || prev.sessionId || crypto.randomUUID()),
    status,
    skillId,
    currentStepIndex: Number.isInteger(Number(src.currentStepIndex)) ? Number(src.currentStepIndex) : (Number(prev.currentStepIndex) || 0),
    stepAnswers: stepAnswers.slice(0, 12).map((item, index) => ({
      id: String(item.id || crypto.randomUUID()),
      stepIndex: Number.isInteger(Number(item.stepIndex)) ? Number(item.stepIndex) : index,
      prompt: String(item.prompt || "").slice(0, 500),
      answer: String(item.answer || "").slice(0, 1200),
    })),
    startedAt: String(src.startedAt || prev.startedAt || `${currentDate}T00:00`),
    completedAt: src.completedAt ? String(src.completedAt) : (prev.completedAt ? String(prev.completedAt) : null),
    sourceThreadId: String(src.sourceThreadId || prev.sourceThreadId || threadId || ""),
    summary: Array.isArray(src.summary) ? src.summary.map(x => String(x || "").trim()).filter(Boolean).slice(0, 5) : [],
    skillIds: Array.isArray(src.skillIds) && src.skillIds.length
      ? src.skillIds.map(normalizeDBTSkillId).filter(Boolean).slice(0, 4)
      : [skillId],
    emotionalShift: typeof src.emotionalShift === "string" && src.emotionalShift.trim() ? src.emotionalShift.trim().slice(0, 160) : null,
    followUpActions: Array.isArray(src.followUpActions) ? src.followUpActions.map(x => String(x || "").trim()).filter(Boolean).slice(0, 5) : [],
  };
}

export function reconcileDBTSessionProgress(session, incoming = {}, input = "", followUpQuestion = null, currentDate = "", reply = "") {
  if (!session || session.status !== "active") return session;
  if (isDBTBootstrapInput(input)) return clampDBTStep(session);

  const answer = String(input || "").trim();
  if (!answer) return clampDBTStep(session);

  const prevStep = Number.isInteger(Number(incoming?.currentStepIndex))
    ? Number(incoming.currentStepIndex)
    : Number(session.currentStepIndex) || 0;
  const steps = dbtStepsForSkill(session.skillId);
  const safePrevStep = Math.max(0, Math.min(prevStep, Math.max(steps.length - 1, 0)));
  const hasAnswerForStep = session.stepAnswers.some((item) => Number(item.stepIndex) === safePrevStep);
  const next = {
    ...session,
    stepAnswers: [...session.stepAnswers],
  };

  if (!hasAnswerForStep) {
    next.stepAnswers.push({
      id: crypto.randomUUID(),
      stepIndex: safePrevStep,
      prompt: steps[safePrevStep] || `第${safePrevStep + 1}步`,
      answer: answer.slice(0, 1200),
    });
  }

  const modelAdvanced = Number(next.currentStepIndex) > safePrevStep;
  const replyAsksQuestion = followUpQuestion !== null
    || /？|\?/.test(reply || "");
  if (replyAsksQuestion && !modelAdvanced) {
    next.currentStepIndex = Math.min(safePrevStep + 1, Math.max(steps.length - 1, 0));
  }

  return clampDBTStep(next, currentDate);
}
