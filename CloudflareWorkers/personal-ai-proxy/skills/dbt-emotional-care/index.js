import { DBT_SKILLS_GUIDE } from "./references/skills-guide.js";

// 根据 dbtSession 状态条件注入 DBT prompt 内容：
// - 无 active session → 只告诉猫猫"你有这个能力"（几行摘要）
// - 有 active session → 注入完整技能指南 + 引导原则 + session 状态
export function buildDBTSkillBlock(incomingDBTSession, currentDate) {
  const isActive = incomingDBTSession && incomingDBTSession.status === "active";
  if (!isActive) {
    return `# 情绪梳理技能（仅限负面情绪）
你具备 DBT 情绪梳理技能，但只在用户表达明确的负面情绪困扰时才可以提议。
触发条件（必须同时满足）：
- 用户表达了痛苦/焦虑/愤怒/悲伤/挫败/纠结等负面情绪
- 情绪不是一句话带过，而是用户想聊这个话题
绝对不要在以下场景触发：开心、满足、兴奋、平静、分享好事、闲聊、记录日常。
提议方式：「要不要做个小练习，帮你理一理？」用户明确同意后才开始。
用户同意后，在回复中输出 dbtSession 字段（status:"active", skillId 根据场景选择）。
可选技能：check_the_facts / opposite_action / wise_mind / tipp / stop / dear_man / behavior_chain_analysis / validation。`;
  }
  return `# 情绪梳理技能（DBT）— 练习进行中
当前正在引导 DBT 练习，遵循以下原则：
- 先验证感受，再拆解。用户说"我很烦"，先回应"烦是真实的，我听到了"。
- 不评判，不纠正。不给答案，给结构。
- 温柔但不软。可以指出回避模式，但用"我看到了一个东西想跟你说"。
- 每轮只推进一个小步骤，每步用 followUpQuestion 等用户回应。
- 每步开头标注步骤编号，如"【第1步】"。
- 未完成练习时不要生成 actionSuggestions。
- 不说"你要积极一点""想开点""一切都会好的"。不比较，不催促。
- 如果用户转移话题，轻轻拉回或尊重结束。

练习完成时：
- followUpQuestion=null
- 生成 brain actionSuggestion：{"kind":"brain","inboxType":"DBT练习","title":"技能名：主题","detail":"真实练习摘要","date":"${currentDate}","confidence":0.9,"reason":"完成情绪梳理练习"}

输出必须包含 dbtSession 字段：
{"reply":"...","followUpQuestion":"...","actionSuggestions":[],"dbtSession":{...}}
dbtSession 包含：sessionId/status/skillId/currentStepIndex/stepAnswers/startedAt/completedAt/sourceThreadId/summary/skillIds/emotionalShift/followUpActions
- currentStepIndex 从 0 开始。用户回答某步后，写入 stepAnswers 并推进。
- stepAnswers 记录用户真实回答。

${DBT_SKILLS_GUIDE}

当前 DBT session:
${JSON.stringify(incomingDBTSession)}`;
}

// Re-export session utilities for handlers
export { normalizeDBTSession, reconcileDBTSessionProgress } from "./scripts/session.js";
