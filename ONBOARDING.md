# 新会话 / 新 AI 协作者 上手指南

> 给任何首次接触本项目的人或 AI 用。
> 用法：在新会话开头，**复制下方"AI Kickoff Prompt"整段粘贴给 AI**；自己读则按"人类阅读顺序"。

---

## 项目一句话

**LifeOS** — 为 ADHD 人群设计的「人生观察系统」iOS app（SwiftUI · iOS 16+ · 1.0.0 已提交 App Store 审核）。

仓库：`/Users/newblue/Projects/openclaw-project/lobster-team/ios-app` · GitHub：`github.com/nannan-debug/lifeos`

---

## AI Kickoff Prompt（复制整段）

```
你将协作开发 LifeOS iOS。

仓库：/Users/newblue/Projects/openclaw-project/lobster-team/ios-app
GitHub：github.com/nannan-debug/lifeos

开始任何任务前，请按以下顺序读完这些文件，并在回复里确认你已理解：

1. CLAUDE.md          — 工作规范 / ADHD 友好原则（硬约束）
2. RELEASE_FLOW.md    — 迭代和发版完整流程，含 AI 硬规则
3. VERSIONING.md      — 版本号约定
4. CONTRIBUTING.md    — 分支命名 / commit 规范
5. LAUNCH_CHECKLIST.md — 当前上架状态
6. PRODUCT_BRIEF.md   — 产品背景（按需）

读完后用 4 行向我汇报：
（1）当前版本号和发布状态
（2）当前 git 分支和有没有未提交改动
（3）你理解的 ADHD 友好硬约束（一句话）
（4）等我下一步指令 —— 不要主动改任何文件

特别注意：
- 不要替我决定语义化版本号（要发新版时先问"是 1.0.x 还是 1.1.0?"）
- 不要替我跑 Archive / Upload / Submit（这些必须我手动在 Xcode/ASC 里点）
- 改完代码必须提醒我 commit（避免 working tree 改动丢失）
- 不要碰 Secrets.swift / .env / 任何凭证
- DEVELOPMENT_TEAM 必须保持 355RQ5S3DW（不要选 Personal Team）
```

> 这段已设计为防 AI 偷懒：要求 AI 汇报 4 件具体事实，编造的话第 1/2 项会露馅。

---

## 一键复制到剪贴板

```bash
cd /Users/newblue/Projects/openclaw-project/lobster-team/ios-app
sed -n '/^```$/,/^```$/p' ONBOARDING.md | sed -n '2,/^```$/p' | sed '$d' | pbcopy
```
（或者直接 `cat ONBOARDING.md` 自己手动复制 Kickoff 那段）

---

## 人类阅读顺序

如果你是真人首次接手：

1. **先读这份** ONBOARDING.md（你正在读）
2. [README.md](README.md) — 5 分钟产品/技术概览
3. [CLAUDE.md](CLAUDE.md) — **必读**，工作规范 + ADHD 硬约束
4. [RELEASE_FLOW.md](RELEASE_FLOW.md) — 日常迭代和发版流程
5. [PRODUCT_BRIEF.md](PRODUCT_BRIEF.md) 或 [PRODUCT_BRIEF_SHORT.md](PRODUCT_BRIEF_SHORT.md) — 产品 why
6. [CONTRIBUTING.md](CONTRIBUTING.md) + [VERSIONING.md](VERSIONING.md) — 协作 / 版本
7. [LAUNCH_CHECKLIST.md](LAUNCH_CHECKLIST.md) — 上架真实进度

跑起来：见 CLAUDE.md「本地启动」一节。

---

## 不同场景的快速入口

| 场景 | 看哪里 |
|---|---|
| 我要本地跑起来 | CLAUDE.md「本地启动」 |
| 我要做新功能 / 改 bug | RELEASE_FLOW §1 日常迭代 |
| 我要发新版本 / 提审 | RELEASE_FLOW §2 发版流程 |
| 签名报错 / Team 选哪个 | RELEASE_FLOW §3 常见坑 |
| 怎么写 commit / 起分支名 | CONTRIBUTING.md |
| 这版本号该怎么递 | VERSIONING.md |
| 当前上架到哪一步了 | LAUNCH_CHECKLIST.md |
| ASC 文案 / 截图 | ASC_COPY_DRAFT_v1.md / ASC_SCREENSHOT_PLAN.md |
