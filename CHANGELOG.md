# Changelog

> LifeOS iOS 版本变更记录。格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)。
>
> **更新规则**：
> - 每次 `chore: bump version to x.y.z` 的 PR 里**顺带把 [Unreleased] 段落整理成一个版本段落**。
> - 用户能感知的变化才写（新功能 / 体验改进 / Bug 修复）。纯文档、纯重构、CI 配置等内部变化**不写在这里**——commit 历史里有就够了。
> - 中文。一句话讲清楚。能链 PR 就链 PR。

---

## [Unreleased]

### 新增
- 灵感与反思模块 V1 开发中（详见 [`IN_PROGRESS.md`](IN_PROGRESS.md)）

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
