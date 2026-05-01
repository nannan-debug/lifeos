# 当前在做：（无）

> **目的**：大功能横跨多个 PR 时，这份文档是"在飞状态"的唯一真相。新接手的人（或断线重连的 AI）只看这一份就能继续。
>
> **生命周期**：开工时建 → 每个 PR 合并后更新进度表 → 整个功能上线后，把内容归档到 `docs/archived-features/<feature>.md`，本文件清空换下一个功能。

---

## 当前状态

🟢 **空闲**。没有跨多 PR 的在飞功能。

最近完成：**灵感与反思模块 V1**（5 个 PR，2026-04-30 ~ 2026-05-01），归档在 [`docs/archived-features/v1-inspiration-reflection.md`](docs/archived-features/v1-inspiration-reflection.md)。代码已合 main，规划版本号 `1.2.0` 等待 bump 上线。

---

## 下一步该做什么？

如果开新大功能：

1. 把"当前在做"标题改成新功能名
2. 填元信息（功能名 / PRD 来源 / 决策来源 / 规划版本号 / 当前阶段）
3. 列 PR 进度表
4. 沉淀"锁定决策清单"
5. 列"不在本期范围"

如果开小功能 / 单 PR 改动：**不需要这份文档**，直接走 [`CONTRIBUTING.md`](CONTRIBUTING.md) 标准流程即可。

---

## 接手指南（有在飞功能时才生效）

按以下顺序读，5 分钟可上手：

1. 读这份 `IN_PROGRESS.md`（你正在看）
2. 读 [`CLAUDE.md`](CLAUDE.md) 工作规范 + ADHD 硬约束
3. 读 [`CONTRIBUTING.md`](CONTRIBUTING.md) 分支 / commit 规范
4. 读 [`LAUNCH_CHECKLIST.md`](LAUNCH_CHECKLIST.md) §4.8（审核期间开发策略）
5. 看上方 PR 进度表 → 找到下一个 ⏳ 状态的 PR
6. 看上方"锁定决策清单"对应该 PR 的部分
7. 跑 `git log main..origin/main --oneline` 确认本地是最新
8. 从最新 main 拉新分支 `git checkout -b <type>/<branch-name>`
9. 写代码 → 测试 → 让 Anna review → squash merge

**关键提醒**：

- 不要在 main 上 bump 版本号（功能全合完前别动 `project.yml` 的 MARKETING / BUILD）
- 改完代码必须提醒 Anna commit（不要自己 commit）
- 任何"是否扩大本 PR 范围"的犹豫 → 停下来问 Anna
- 想动"锁定决策清单"任何一条 → 停下来问 Anna
- 这份 IN_PROGRESS.md 每次 PR 合并后**手动更新进度表**（无自动化）
