export function normalizeInboxType(value) {
  const inboxType = String(value || "").trim();
  return ["想法", "感受", "感恩", "做梦", "DBT练习"].includes(inboxType) ? inboxType : null;
}

export function normalizeMood(value) {
  const mood = Number(value);
  return Number.isInteger(mood) && mood >= 1 && mood <= 5 ? mood : null;
}

export function normalizeFeelings(value) {
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

export function normalizeTimeModule(value) {
  const module = String(value || "").trim();
  if (module === "休息") return "其他";
  return ["睡觉", "社交", "运动", "其他", "娱乐", "工作", "学习"].includes(module) ? module : null;
}
