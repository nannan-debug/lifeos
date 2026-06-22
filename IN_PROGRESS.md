# 当前在做：无跨 PR 的在飞功能

> **目的**：大功能横跨多个 PR 时，这份文档是"在飞状态"的唯一真相。新接手的人（或断线重连的 AI）只看这一份就能继续。
>
> **生命周期**：开工时建 → 每个 PR 合并后更新进度表 → 整个功能上线后，把内容归档到 `docs/archived-features/<feature>.md`，本文件清空换下一个功能。

---

## 当前状态

当前没有跨 PR 的在飞大功能。最新上架版本为 `1.13.0 (build 17)`。

### 已完成的合规事项

- ✅ ICP 备案已通过，备案号已挂网站底部
- ✅ 公安联网备案已通过（2026-06-17），主体 + APP 均为「有效」状态
  - APP 公安备案不发放单独备案号，审核通过即合规
  - 如需网站公安备案号（「京公网安备」），需在 `beian.mps.gov.cn`「我的网站」单独申请
  - 详见 `LAUNCH_CHECKLIST.md` §2.4

## 最近完成

- 公安联网备案审核通过（主体 + APP）— 2026-06-17 通过，2026-06-22 确认无需展示备案号。
- AI 时间记录/复盘/卡片识别修复 + Worker prompt 优化 — [#108](https://github.com/nannan-debug/lifeos/pull/108) 已合入 main（2026-06-17）。
- 公安备案进展同步 + 英文 ASC 文案 — [#109](https://github.com/nannan-debug/lifeos/pull/109) 已合入 main（2026-06-17）。
- 过期 PR 清理（#36, #62, #90, #93, #95, #99 已关闭）、本地旧分支清理（70+ 分支已删）。
- 中英文双语支持 — `1.11.0 (build 15)` 已提交审核（2026-05-25）。[#83](https://github.com/nannan-debug/lifeos/pull/83)。
  - 轻量 i18n 方案：`Sources/Localization/L.swift` 集中管理 ~150 个双语字符串，`UserDefaults("app.language")` 切换
  - 设置页语言 Picker + 全 App UI 替换 + AI 语言匹配 + 70 条英文每日语录
  - 数据存储层不受影响（分类/标签等仍以中文存储，display mapping 函数在显示时翻译）
- Usage Analytics Dashboard — 随 `1.10.0 (build 14)` 合入 main。[#82](https://github.com/nannan-debug/lifeos/pull/82)。
- AI 全屏对话窗 + 多会话历史 — 随 `1.8.0 (build 12)` 上架（2026-05-21）。
- Agent Trace 全量上传链路 — [#71](https://github.com/nannan-debug/lifeos/pull/71) 已合入 `main`。
- Agent V2 — 分层交互 + 轻量 Memory（PR #63/#65/#66，2026-05-20）。
- iCloud 同步迁移到 CloudKit — 随 `1.7.0 (build 11)` 上架（2026-05-20）。
