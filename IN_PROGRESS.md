# 当前在做：AI 全屏对话窗 + 多会话历史

> **目的**：大功能横跨多个 PR 时，这份文档是"在飞状态"的唯一真相。新接手的人（或断线重连的 AI）只看这一份就能继续。
>
> **生命周期**：开工时建 → 每个 PR 合并后更新进度表 → 整个功能上线后，把内容归档到 `docs/archived-features/<feature>.md`，本文件清空换下一个功能。

---

## 背景

Agent V2 已经完成「快录 / 对话」分层与轻量 Memory，但 UI 仍是底部浮动输入条，只能展示最近几条消息，不适合长对话、历史回看和多会话管理。

本轮参考 Notion 手机端 AI 对话窗，把 LifeOS 的猫猫 AI 升级为独立全屏面板，同时保留低摩擦记录入口。

## 设计

```
全局猫猫 FAB
  → fullScreenCover 全屏 AI 面板
  ├─ 快录模式：轻量单轮，不带 memory/context
  ├─ 对话模式：多轮聊天，带当前 thread history + context + memory
  └─ 历史抽屉：搜索 / 切换 / 新建 / 删除撤销
```

## PR 进度表

| PR | 内容 | 状态 |
|---|---|---|
| PR 1 | AI 全屏对话窗 + 多会话文件存储 + 历史抽屉 | ✅ [#68](https://github.com/nannan-debug/lifeos/pull/68) 已合入 main；`1.8.0 (build 12)` 已提交 App Review，等待 Apple 审核 |

## 本轮包含的改动

**持久化：**
- 新增 `AgentChatThread` 和 `AgentChatThreadIndexItem`
- `Application Support/agent-threads/<userId>/<threadId>.json` 保存会话正文
- `UserDefaults` 只保存 thread 索引、当前 thread id、memory/debug 等轻量数据
- 旧 `ps.agent.chat.*` 自动迁移为一个 thread
- 会话上限 30 个，超出删除最旧的非当前会话

**交互：**
- `GlobalAIInputBar` 折叠态保留猫猫 FAB
- 展开改为 `fullScreenCover` 全屏 AI 面板
- 顶部支持历史入口和新建对话
- 历史抽屉支持搜索、切换、删除，并提供撤销
- 底部输入区保留显式「快录 / 对话」模式
- action card 改为出现在对话流中，确认后写入随手记 / 待办 / 时间记录

**Memory：**
- 新建对话、关闭面板、清空对话时，若当前对话足够长则提取记忆
- 删除历史不触发记忆提取

## 已知问题 / 待验收

- 等待 Apple 审核 `1.8.0 (build 12)`。
- App Store 显示 Ready for Distribution / 已上架后，打 `v1.8.0` tag、发 GitHub Release，并把本功能归档到 `docs/archived-features/agent-fullscreen-chat.md`。

---

上一项已完成：

- Agent V2 — 分层交互 + 轻量 Memory（PR #63/#65/#66，2026-05-20）
- iCloud 同步迁移到 CloudKit — 随 `1.7.0 (build 11)` 上架（2026-05-20）
