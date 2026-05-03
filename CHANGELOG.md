# Changelog

> LifeOS iOS 版本变更记录。格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)。
>
> **更新规则**：
> - 每次 `chore: bump version to x.y.z` 的 PR 里**顺带把 [Unreleased] 段落整理成一个版本段落**。
> - 用户能感知的变化才写（新功能 / 体验改进 / Bug 修复）。纯文档、纯重构、CI 配置等内部变化**不写在这里**——commit 历史里有就够了。
> - 中文。一句话讲清楚。能链 PR 就链 PR。

---

## [Unreleased]

### 改进
- 时间圆盘支持从当天拖过零点记录到次日，跨日时间会在两天中自然显示，并用轻量虚线区分。

## [1.3.0] (build 5) — 2026-05-03

### 新增
- 设置页新增 iCloud 同步开关：使用 Apple iCloud Key-Value Storage 在同 Apple ID 设备间同步本地数据，默认关闭，用户手动开启（[#22](https://github.com/nannan-debug/lifeos/pull/22)）
- 第二大脑卡片创建/编辑时，AI 自动推荐 1-3 个主题标签——一键接受或忽略，不强制
- 默认主题集：工作 / 学习 / 生活 / 灵感 / 人际（也能继续手动添加任意主题）
- 复盘 Tab Hub 顶部加「本周 / 本月」切换与日历选择：可查看指定自然周 / 自然月的处理统计。Review 队列保持最近 7 天不变，避免 P 人面对一座积压山
- 复盘 Tab 新增周复盘轻卡片流：按打卡、时间分配、待处理想法回看一周，只呈现观察线索，不做打分审判

### 改进
- 打卡页新增打卡项入口改为分组头左滑操作，减少低频管理入口对日常打卡视线的打扰；整组完成时加入轻量提示、礼花动效和触感反馈
- 第二大脑卡片详情简化：移除"关联卡片 / 反向链接"section，腾出正文空间。手动建链使用率太低，让位给后续的自动化方案

---

## [1.2.0] (build 4) — 2026-05-01

灵感与反思模块 V1。设计沉淀见 [`docs/archived-features/v1-inspiration-reflection.md`](docs/archived-features/v1-inspiration-reflection.md)。

### 新增
- 新增第 5 个 Tab「复盘」：进入是 Hub 仪表盘，包含「Review」「第二大脑」两张卡片（[#15](https://github.com/nannan-debug/lifeos/pull/15)）
- **Review 模式**：把最近 7 天还没处理的「想法 / 感受」按时间倒序排成队列，左滑搁置 / 右滑沉淀；不计时、不催、不审判（[#15](https://github.com/nannan-debug/lifeos/pull/15)）
- **想法 → ToDo**：Review 模式右滑可以把一个想法直接变成待办，标题自动预填，原文片段保留作为来源（[#15](https://github.com/nannan-debug/lifeos/pull/15)）
- **第二大脑**：处理过的「想法 / 感受」可以沉淀为卡片，按主题（topic）聚合；卡片之间可以双向关联，并自动生成反向链接（[#17](https://github.com/nannan-debug/lifeos/pull/17)）
- 第二大脑卡片墙支持「卡片墙 / 主题」两种视图切换；topic 输入支持自动补全已用过的主题（[#17](https://github.com/nannan-debug/lifeos/pull/17)）

### 改进
- 砍掉随记 Tab 顶部的"日 / 周"toggle —— 周视图改放在复盘 Tab 的 Review 模式里，分工更清晰（[#12](https://github.com/nannan-debug/lifeos/pull/12)）
- 开屏改为静态植物视觉，文案更新为"观察生活，记录生活"。
- 优化日历弹层打开体验，减少卡顿感。

### 内部
- 数据模型扩展：`ConversationTurn` 加 `derivatives`、`TaskEntry` 加 `sourceNoteId/sourceExcerpt`，新增 `BrainCard` 等三个类型（[#13](https://github.com/nannan-debug/lifeos/pull/13)）
- 抽出 `TodoEditorSheet` 独立文件 + 清理旧版 InboxView 镜像写入（[#11](https://github.com/nannan-debug/lifeos/pull/11)、[#12](https://github.com/nannan-debug/lifeos/pull/12)）

---

## [1.1.0] (build 3) — 2026-04-30

App Store [Ready for Distribution]。

### 新增
- 打卡页支持分组独立 CRUD + inline 编辑：直接在打卡列表里加 / 改 / 删项目，不再需要单独的"管理面板"页面（[#2](https://github.com/nannan-debug/lifeos/pull/2)）
- 待办支持 AI 输入框直接拆解（[#7](https://github.com/nannan-debug/lifeos/pull/7)）

### 改进
- 今日页打卡分组之间的间距更舒服（[#7](https://github.com/nannan-debug/lifeos/pull/7)）
- 给新用户预置一组默认打卡项（吃维生素 / 回忆梦境 / 洗漱 / 出门 / 写日记 / 洗澡 / 上床看书），分到「早上 / 晚上」两组（[#7](https://github.com/nannan-debug/lifeos/pull/7)）

### 内部
- 出口合规永久豁免落到 `project.yml`（`ITSAppUsesNonExemptEncryption: false`），后续每个 build 自动跳过提审时的合规问卷（[#4](https://github.com/nannan-debug/lifeos/pull/4)）
- build 2 提审中曾撤回，并入 [#7](https://github.com/nannan-debug/lifeos/pull/7) 后以 build 3 重新 Submit 通过

---

## [1.0.0] (build 1) — 2026-04

🎉 **App Store 首发**。App ID `6763877227`。

### 首发功能
- 4 个主 Tab：今日（打卡 + 待办）/ 时间（24 小时圆盘）/ 随记（想法 / 感受 / 感恩 / 做梦）/ 设置
- 全局 AI 输入框：一句话自动归到打卡 / 待办 / 时间 / 随记四个桶（DeepSeek 后端）
- 数据本地存储，按用户 ID 隔离
- AI 首次使用同意流程
- CSV 导出 / 导入
- 简体中文，除中国大陆外全球区
