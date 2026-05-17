# 当前在做：iCloud 同步迁移到 CloudKit

> **目的**：大功能横跨多个 PR 时，这份文档是"在飞状态"的唯一真相。新接手的人（或断线重连的 AI）只看这一份就能继续。
>
> **生命周期**：开工时建 → 每个 PR 合并后更新进度表 → 整个功能上线后，把内容归档到 `docs/archived-features/<feature>.md`，本文件清空换下一个功能。

---

## 背景

原 iCloud 同步把全部数据塞进 `NSUbiquitousKeyValueStore` 的单键快照，存在 1MB 静默丢弃、整包覆盖无合并、重装后开启同步可能用空数据覆盖云端等数据丢失风险。迁移到 CloudKit（逐记录同步、按 Apple ID 隔离的 private database、跨重装持久存在）以根治。

## 锁定决策清单

> 改动此清单前先和 Anna 对齐，不要直接改。

1. **最低系统**：iOS 17+，用 `CKSyncEngine`。
2. **同步开关**：保留设置项，**默认开**；关闭 = 仅暂停，云端数据保留，重新打开续传。
3. **同步范围**：核心 6 类 —— 打卡、时间记录、待办、AI 对话、第二大脑、打卡项配置。AI 失败日志、遗留 inbox **不同步**。
4. **Schema**（private database）：`CheckDay` 按日期一条；`TimeEntry` / `Task` / `Turn` / `BrainCard` 各按 UUID 一条；`DailyConfig` 打卡项配置单例。
5. **存储模型**：本地 `UserDefaults` 仍是 App 的工作存储，`CKSyncEngine` 在旁做镜像；迁移**只读本地、永不删除本地数据**（本地始终是一份兜底）。
6. **过渡**：首次启动一次性导入 —— 本地有数据则迁本地；本地为空则读一次旧 KVS 快照当种子。之后彻底弃用 KVS，一次性标志位守住。
7. **安全网**：首次迁移前自动写一份完整 JSON 本地备份；设置页提供「导出全部数据」。

## PR 进度表

| PR | 内容 | 状态 |
|---|---|---|
| PR 1 | 安全网先行：设置页「导出全部数据」+ JSON 备份序列化器 | ✅ [#51](https://github.com/nannan-debug/lifeos/pull/51) 2026-05-17 |
| PR 2 | CloudKit 基建：iCloud capability + 容器、Schema 常量、本地数据 ↔ CKRecord 双向转换器 + 单测（无行为变化，不含同步引擎） | 🚧 |
| PR 3 | `CKSyncEngine` 接入 + 上行/下行同步 + 一次性迁移（迁移前自动备份）+ 切 CloudKit 为默认 + 退役 KVS | ⏳ |

> PR 2/3 边界微调：`CKSyncEngine` 控制器与启用/迁移逻辑绑定，从 PR 2 挪到 PR 3，使 PR 2 只交付一层可单测的纯转换代码、零死代码。

## 阻塞 / 待人工

- iCloud 容器 `iCloud.ai.anna.personalsystem` 已注册、App target 已加 iCloud(CloudKit) capability、构建通过（2026-05-17 完成）。

## 关联

- PR #50（交互 Widget + KVS 同步止血修复）已并入 `main`，是 CloudKit 上线前的过渡保护；CloudKit 上线后其 iCloud 同步部分被取代。

---

上一项已完成归档：

- [`灵感与反思模块 V2`](docs/archived-features/v2-inspiration-reflection.md) — 随 `1.3.0 (build 5)` 上架完成归档（2026-05-03）
