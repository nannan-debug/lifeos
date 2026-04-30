# AGENTS.md — LifeOS iOS

> 给 OpenAI Codex 及其他读取 `AGENTS.md` 的编码 agent 使用。
>
> **本项目的工作规范统一维护在 [`CLAUDE.md`](./CLAUDE.md)。请先完整阅读那份文件，再开始任何任务。**
>
> 之所以拆成两份文件，只是为了兼容不同 agent 的默认文件名约定（Claude Code 读 `CLAUDE.md`，Codex 读 `AGENTS.md`）。规范本身不在这里复制，避免双份维护漂移。

## 同步阅读清单

`CLAUDE.md` 之外，开始任务前还应熟悉：

- [`CONTRIBUTING.md`](./CONTRIBUTING.md) — 分支命名 / commit 规范 / PR 流程
- [`VERSIONING.md`](./VERSIONING.md) — 版本号约定（注意：`project.yml` 是 source of truth，不是 `Info.plist`）
- [`LAUNCH_CHECKLIST.md`](./LAUNCH_CHECKLIST.md) — 当前上架状态 + 发版 SOP（重点看 §4.8 审核期间开发策略）
- [`PRODUCT_BRIEF.md`](./PRODUCT_BRIEF.md) — 产品背景与 ADHD 友好设计原则
