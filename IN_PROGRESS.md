# 当前在做：暂无大功能

> **目的**：大功能横跨多个 PR 时，这份文档是"在飞状态"的唯一真相。新接手的人（或断线重连的 AI）只看这一份就能继续。
>
> **生命周期**：开工时建 → 每个 PR 合并后更新进度表 → 整个功能上线后，把内容归档到 `docs/archived-features/<feature>.md`，本文件清空换下一个功能。

---

## 当前状态

暂无跨 PR 大功能在飞。

## 最近完成

- LifeOS `1.12.0 (build 16)` — 已上传 App Store Connect 并提交 App Review（2026-06-04）。等待 Apple 审核结果；尚未上架，不能打 tag / GitHub Release。
- Trace Dashboard / Growth Ops — 已合入 `main`：
  - #94 新增 Growth Ops tab，读取本地小红书运营素材目录，只做素材管理和手动发布包，不自动发布。
  - #98 收敛 Growth Ops 空状态 CTA：`录参考帖` / `建选题` / `写今日草稿` 分别创建 `references` / `topics` / 月份草稿 Markdown；发布包区域不再重复放“新建草稿”。
  - 小红书运营内容目录 `docs/operations/growth/xiaohongshu/` 已 gitignore，默认只保留本地，不上传 GitHub。
- 中英文双语支持 — `1.11.0 (build 15)` 已提交审核（2026-05-25）。[#83](https://github.com/nannan-debug/lifeos/pull/83)。
  - 轻量 i18n 方案：`Sources/Localization/L.swift` 集中管理 ~150 个双语字符串，`UserDefaults("app.language")` 切换
  - 设置页语言 Picker + 全 App UI 替换 + AI 语言匹配 + 70 条英文每日语录
  - 数据存储层不受影响（分类/标签等仍以中文存储，display mapping 函数在显示时翻译）
- Usage Analytics Dashboard — 随 `1.10.0 (build 14)` 合入 main。[#82](https://github.com/nannan-debug/lifeos/pull/82)。
- AI 全屏对话窗 + 多会话历史 — 随 `1.8.0 (build 12)` 上架（2026-05-21）。
- Agent Trace 全量上传链路 — [#71](https://github.com/nannan-debug/lifeos/pull/71) 已合入 `main`。
- Agent V2 — 分层交互 + 轻量 Memory（PR #63/#65/#66，2026-05-20）。
- iCloud 同步迁移到 CloudKit — 随 `1.7.0 (build 11)` 上架（2026-05-20）。
