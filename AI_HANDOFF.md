# AI 协作开场白模板

> 每次开新 Claude Code（或其他 AI Coding 工具）session 协作开发 LifeOS iOS 时，
> 复制下方代码块整段粘贴到对话框，把最后一段「我现在想做的事」按场景挑一个填好即可。
>
> ⚠️ 不要把"当前版本号 / 审核状态 / 在飞功能"硬编码进模板——让 AI 自己去
> [`IN_PROGRESS.md`](IN_PROGRESS.md) 和 [`LAUNCH_CHECKLIST.md`](LAUNCH_CHECKLIST.md) 读最新状态，模板才不会过期。

---

## 标准开场白（直接复制）

````
你将协作开发 LifeOS iOS 的新功能，可能是接手别的 AI session 的工作。

仓库：/Users/newblue/Projects/ios-app-lifeos
GitHub：github.com/nannan-debug/lifeos

开始任何任务前，请按顺序读完这些文件，并在回复里确认你已理解：

1. IN_PROGRESS.md      — 当前在飞的大功能（如有）。**有内容则你接的就是这个，不要另起炉灶**
2. CLAUDE.md           — 工作规范 （红线）
3. AGENTS.md           — 主动沉淀规则（合 main 时是否要更新 CHANGELOG / IN_PROGRESS / LAUNCH_CHECKLIST）
4. CONTRIBUTING.md     — 分支命名 / commit 规范
5. VERSIONING.md       — 版本号约定（注意：project.yml 是 source of truth，不是 Info.plist）
6. LAUNCH_CHECKLIST.md — 当前上架状态 + 发版 SOP（重点看 §4.8 审核期间开发策略）
7. CHANGELOG.md        — 版本变更历史（按需，发版相关时看）

读完后用 5 行向我汇报：
（1）当前线上版本号 + ASC 审核状态
（2）当前 git 分支 + 有没有未提交改动
（3）IN_PROGRESS.md 里有没有在飞功能 —— 如果有，下一个待办 PR 是哪个
（4）你理解的"审核期间开发新功能"的核心约束（一句话）
（5）等我下一步指令 —— 不要主动改任何文件

重要硬规则（违反就停手问我）：
- 不要 bump main 上的版本号（如果有审核中的 build，bump 会破坏当前提审）
- 不要替我决定 patch vs minor 版本（要发版时先问）
- 不要替我跑 Archive / Upload / Submit（这些必须我手动在 Xcode/ASC 里点）
- 改完代码必须提醒我 commit，不要自己 commit
- 不要碰 Secrets.swift / .env / 任何凭证
- DEVELOPMENT_TEAM 必须保持 355RQ5S3DW
- 任何想动 IN_PROGRESS.md "锁定决策清单" 的内容 → 先停下来问我，不要直接改
- 用户可见的代码改动必须顺手更新 CHANGELOG.md [Unreleased]（AGENTS.md 强制）

工作流（每个 PR 一轮）：
1. 我告诉你做什么（接 IN_PROGRESS 下一个 PR / 新功能 / 修 bug / 发版）
2. 你确认 main 是最新且干净
3. 如果是 IN_PROGRESS 在飞功能，先把对应 PR 行标 🚧（commit 时一起进 PR）
4. 你开新分支（type/short-name 见 CONTRIBUTING.md）
5. 写代码 → 跑测试 → 给我看 diff
6. 我满意后你 push 分支 + 开 PR（PR 描述含 Test plan）
7. 用户可见的改动你顺手更新 CHANGELOG.md [Unreleased]
8. 我自己 review → squash merge → 删分支
9. 合后你把 IN_PROGRESS 进度表对应 PR 标 ✅ + 填 PR 链接 + 日期（开下一个 PR 时一并做）

我现在想做的事：
【按场景挑一个填写下面】

- 接手在飞功能：
  「继续 IN_PROGRESS.md 里的功能，从下一个 ⏳ 状态的 PR 开始（先报告你看到的下一个 PR 是什么）」

- 新功能：
  「想加 X 功能：[简短描述]，参考 CLAUDE.md / 某 issue / 某外部 PRD。先帮我用 grill-me 拷问范围再开发」

- 修 bug：
  「修 bug：[复现步骤] / 期望行为是 A、实际是 B / 影响哪个 Tab」

- 发版（V2 PR 1-N 全合完后）：
  「想发 1.x.x 版本，请按 LAUNCH_CHECKLIST §4 SOP 引导我走」

- 文档 / 重构：
  「想做 X 类整理：[范围 + 目的]」
````

---

## 使用建议

- **任务描述越具体越好**：
  - ❌ 模糊：「加一个反思功能」
  - ✅ 具体：「加 DBT 行为链分析 + 自我觉察档案 Tab，按 PRD §6 / IN_PROGRESS.md 锁定决策清单的'V3 候选'范围，从 grill-me 拷问开始」
- **大功能先 grill-me 再写代码**：跨多个 PR 的功能，先用 `/grill-me` 把范围 / 决策 / PR 拆分敲死，沉淀到 `IN_PROGRESS.md`，再让 AI（或换一个 AI）执行
- **超过一周没用的 session 别复用**：上下文容易漂移，新开一个干净 session 用这个模板更安全
- **想发新版时**：上面"发版"场景的开场白即可，AI 会读 LAUNCH_CHECKLIST §4 SOP 引导你
- **遇到 AI 跑偏 / 决策模糊时**：用 `/grill-me` 重新对齐——比 "你想清楚再回答" 这种泛指令有效得多

---

## 模板会过时吗？

只有这些情况需要更新这个文件：

- 仓库 / GitHub URL 变了
- 团队 ID `355RQ5S3DW` 变了（换 Apple Developer 账号）
- 新增了一个"红线规则"（比如新增的隐私 / 合规约束 / 数据红线）
- 工作流本身变了（比如不再用 squash merge 了 / 改用 trunk-based / 加了 CI 检查）
- 必读文件清单变了（新增重要规范文档 / 删了某个文档）

**不需要**因为版本号 bump、新功能上线、文档微调而更新。版本相关的事让 AI 自己去 [`LAUNCH_CHECKLIST.md`](LAUNCH_CHECKLIST.md) 和 [`IN_PROGRESS.md`](IN_PROGRESS.md) 看。
