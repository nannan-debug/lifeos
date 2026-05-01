# AI 协作开场白模板

> 每次开新 Claude Code（或其他 AI Coding 工具）session 协作开发 LifeOS iOS 时，
> 复制下方代码块整段粘贴到对话框，把最后一行的 `【想做的事】` 改成具体内容即可。
>
> ⚠️ 不要把"当前版本号 / 审核状态"硬编码进模板——让 AI 自己去
> [LAUNCH_CHECKLIST.md](LAUNCH_CHECKLIST.md) 读最新状态，模板才不会过期。

---

## 标准开场白（直接复制）

````
你将协作开发 LifeOS iOS 的新功能。

仓库：/Users/newblue/Projects/ios-app-lifeos
GitHub：github.com/nannan-debug/lifeos

开始任何任务前，请按顺序读完这些文件，并在回复里确认你已理解：

1. IN_PROGRESS.md      — 当前在飞的大功能（如有）。**有内容则你接的就是这个，不要另起炉灶**
2. CLAUDE.md           — 工作规范 / ADHD 友好硬约束（红线）
3. CONTRIBUTING.md     — 分支命名 / commit 规范
4. VERSIONING.md       — 版本号约定（注意：project.yml 是 source of truth，不是 Info.plist）
5. LAUNCH_CHECKLIST.md — 当前上架状态 + 发版 SOP（重点看 §4.8 审核期间开发策略）
6. CHANGELOG.md        — 版本变更历史（按需，发版相关时看）
7. PRODUCT_BRIEF.md    — 产品背景（按需）

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
- 改完代码必须提醒我 commit
- 不要碰 Secrets.swift / .env / 任何凭证
- DEVELOPMENT_TEAM 必须保持 355RQ5S3DW
- ADHD 友好原则：不准 streak / 完成率审判 / "你已经 X 天没打开" / 高饱和警告色

工作流：
1. 我说"想加 X 功能 / 想修 X bug"
2. 你确认 main 是最新且干净
3. 你开 feat/xxx 或 fix/xxx 分支
4. 写代码 + 给我看
5. 我满意后你 push + 开 PR
6. 我自己 review → squash merge → 删分支

我现在想做的事：
【在这里写具体描述，越细越好——例如「复盘 Tab 的日复盘 V1，按 PRODUCT_BRIEF §5️⃣ 实现」】
````

---

## 使用建议

- **描述越具体越好**：
  - ❌ 模糊：「加复盘」
  - ✅ 具体：「复盘 Tab 的日复盘 V1：今日时间饼图 + 心情时间线 + AI 一句温柔总结，按 PRODUCT_BRIEF §5️⃣ 设计原则」
- **超过一周没用过的 session 别复用**：上下文容易漂移，新开一个干净 session 用这个模板更安全
- **改 bug 时调整**：把"功能"改成"bug + 复现步骤"，把 `feat/xxx` 改成 `fix/xxx`
- **想发新版时**：不要用这个模板，而是直接说「想发 1.x.x 版本，请按 LAUNCH_CHECKLIST §4 SOP 走」——AI 会读 SOP 引导你

---

## 模板会过时吗？

只有这些情况需要更新这个文件：

- 仓库 / GitHub URL 变了
- 团队 ID `355RQ5S3DW` 变了（换 Apple Developer 账号）
- 新增了一个"红线规则"（比如新增的隐私 / 合规约束）
- 工作流本身变了（比如不再用 squash merge 了）

**不需要**因为版本号 bump、新功能上线、文档微调而更新。版本相关的事让 AI 自己去 [LAUNCH_CHECKLIST.md](LAUNCH_CHECKLIST.md) 看。
