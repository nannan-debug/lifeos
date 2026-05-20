# 当前在做：Agent V2 — 分层交互 + 轻量 Memory

> **目的**：大功能横跨多个 PR 时，这份文档是"在飞状态"的唯一真相。新接手的人（或断线重连的 AI）只看这一份就能继续。
>
> **生命周期**：开工时建 → 每个 PR 合并后更新进度表 → 整个功能上线后，把内容归档到 `docs/archived-features/<feature>.md`，本文件清空换下一个功能。

---

## 背景

Agent V1 只有一种交互深度——每次请求都加载完整上下文（system prompt + contextSummary + 历史消息），无论用户只是想快速记一句话还是想深入聊天。同时 Agent 没有跨会话记忆，每次清空聊天后所有积累的理解都丢失。

## 设计：三层交互深度

```
⚡ 本地快录（已有）     → 纯本地关键词解析，不走网络
↑  AI 快录（默认）     → 单轮 AI 分析，轻量 prompt，无 memory
💬 对话模式（手动切换） → 多轮对话，加载 memory + contextSummary
```

用户手动切换快录/对话模式（GlobalAIInputBar 左上角按钮）。

## PR 进度表

| PR | 内容 | 状态 |
|---|---|---|
| PR 1 | Agent V1 架构重构——瘦身 prompt、清理死码、引入 AIClient 依赖注入 | ✅ [#63](https://github.com/nannan-debug/lifeos/pull/63) 2026-05-19 |
| PR 2 | Agent V2 全量——分层交互 + Memory 系统 + Worker quick/extract_memories | 🔄 [#65](https://github.com/nannan-debug/lifeos/pull/65) 待合并 |

## PR 2 包含的改动

**Worker（`CloudflareWorkers/personal-ai-proxy/worker.js`）：**
- `handleQuick()`：轻量单轮，max_tokens 500，temperature 0.3
- `extract_memories` utility：从对话提取 1-3 条 memory
- prompt 精简（~2200→~1200 字）
- 空响应自动重试

**iOS 端：**
- `AgentMemory` 数据模型 + LRU 淘汰（上限 15 条）
- `AgentManager.quickSend()` 快录路径
- `AgentManager` memory CRUD + 自动提取（clearChat 时触发）
- `AgentOrchestrator` contextSummary 注入 memory + 随手记带标题
- `GlobalAIInputBar` 模式切换 UI + memory 状态提示
- 对话模式更正时清掉旧 action cards（防重复）
- 设置页 Memory 管理列表
- 随手记卡片和编辑页展示 action title

**工具：**
- `scripts/agent_lab.py` Python 实验脚本

## 已知问题

- DeepSeek 在多轮对话中偶尔混淆实体属性（如搞反哪场面试好/差），这是模型能力限制，非代码 bug
- Memory 提取依赖 LLM 判断，没有 embedding 相似度去重（当前 15 条上限下尚不是问题）

## 阻塞 / 待人工

- PR #65 待 Anna 合并

---

上一项已完成归档：

- [`iCloud 同步迁移到 CloudKit`](docs/archived-features/cloudkit-sync-migration.md) — 随 `1.7.0 (build 11)` 提交审核（2026-05-18），三个 PR 全部合入
