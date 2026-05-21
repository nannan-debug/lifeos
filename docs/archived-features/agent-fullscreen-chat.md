# AI 全屏对话窗 + 多会话历史（已上线）

> 归档时间：2026-05-21  
> 上线版本：`1.8.0 (build 12)`  
> 主要 PR：[#68](https://github.com/nannan-debug/lifeos/pull/68)

---

## 背景

Agent V2 已经完成「快录 / 对话」分层与轻量 Memory，但 UI 仍是底部浮动输入条，只能展示最近几条消息，不适合长对话、历史回看和多会话管理。

本轮参考 Notion 手机端 AI 对话窗，把 LifeOS 的猫猫 AI 升级为独立全屏面板，同时保留低摩擦记录入口。

## 设计

```text
全局猫猫 FAB
  → fullScreenCover 全屏 AI 面板
  ├─ 快录模式：轻量单轮，不带 memory/context
  ├─ 对话模式：多轮聊天，带当前 thread history + context + memory
  └─ 历史抽屉：搜索 / 切换 / 新建 / 删除撤销
```

## 已上线内容

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

## 上架收尾

- ✅ `1.8.0 (build 12)` 已提交 App Review（2026-05-20）
- ✅ `1.8.0 (build 12)` 已通过审核并上架（2026-05-21，用户确认）
- ✅ Tag `v1.8.0` 已 push
- ✅ GitHub Release [v1.8.0](https://github.com/nannan-debug/lifeos/releases/tag/v1.8.0) 已发布
