# CLAUDE.md — LifeOS iOS

> 这份文件是 Claude Code 的工作规范。在开始任何任务前请先阅读全文。

---

## 项目概览

**LifeOS** 是一款为 ADHD 人群设计的「人生观察系统」。
核心理念：低摩擦记录 + 可视化回看，帮助用户看清自己的生活，而非"优化"自己。

- 技术栈：SwiftUI · Swift 5.9 · iOS 16+ · XcodeGen
- 数据存储：本地 `UserDefaults`（按 `userId` 分库）
- AI 后端：Cloudflare Worker (`ai.dogdada.com`) + Kimi LLM
- 仓库：`github.com/nannan-debug/lifeos`

---

## 仓库结构

```
Sources/
  App/          # 入口 + Info.plist + Assets
  Models/       # 数据模型（Models.swift）
  ViewModels/   # AppStore（全局状态，ObservableObject）
  Services/     # AIParser + Secrets（Secrets.swift 已 gitignore）
  Views/        # 所有 SwiftUI 页面
Tests/          # 单元测试（PersonalSystemSmokeTests）
project.yml     # XcodeGen 配置，勿手编 .xcodeproj
Secrets.example.swift  # Secrets 模板，真实文件不进仓库
```

**关键文件：**
- `Sources/ViewModels/AppStore.swift` — 全局状态，所有 @Published 数据都在这里
- `Sources/Services/AIParser.swift` — AI 解析逻辑与 schema 定义
- `Sources/Views/RootTabView.swift` — Tab 容器
- `project.yml` — XcodeGen 配置，改依赖/Target 时在这里改

---

## 本地启动

```bash
brew install xcodegen          # 一次性依赖
cp Secrets.example.swift Sources/Services/Secrets.swift
# 填入真实 AI secret（向 Anna 索取）
xcodegen
open PersonalSystem.xcodeproj  # Cmd+R 跑模拟器
```

> `Secrets.swift` 绝对不能提交。已在 .gitignore。提交前必须确认。

---

## 分支 & Commit 规范

详见 `CONTRIBUTING.md`，核心要点：

**分支命名：**
```
feat/xxx   fix/xxx   style/xxx   refactor/xxx   docs/xxx
```

**从最新 main 拉分支，PR 用 Squash Merge，合后删分支。**

**Commit message（Conventional Commits）：**
```
<type>: <简短描述（中文）>
```

| type | 场景 |
|---|---|
| `feat` | 新功能 |
| `fix` | bug 修复 |
| `style` | 纯视觉调整（不影响逻辑） |
| `refactor` | 重构（不改外在行为） |
| `docs` | 文档 |
| `chore` | 配置 / 依赖 / 构建 |
| `test` | 测试 |
| `perf` | 性能优化 |

**规则：**
- 用祈使句（"修复"，不是"修复了"）
- 一个 commit 一件事
- `main` 只接受 PR，不允许直接 push

---

## 版本号规范

详见 `VERSIONING.md`，核心要点：

- Marketing Version：`MAJOR.MINOR.PATCH`（用户可见，`CFBundleShortVersionString`）
- Build Number：单调递增，永不回退（`CFBundleVersion`）
- 发版：改 `Sources/App/Info.plist` → 打 annotated tag `v1.x.x` → push tag

**当前状态：** `1.0.0 (build 1)` — 开发完成，内部体验中，未上架

---

## 数据模型

全部定义在 `Sources/Models/Models.swift`。主要实体：

| 实体 | 用途 |
|---|---|
| `DailyCheckItem` | 每日打卡项 |
| `TaskEntry` | 待办任务（含优先级/截止时间） |
| `TimeEntry` | 时间块记录（起止时间 + 类别） |
| `InboxNote` | 随记（想法/感受/感恩/做梦） |
| `ConversationTurn` | AI 对话轮次 |

数据通过 `AppStore` 持久化到 `UserDefaults`，key 按 `userId` 前缀隔离（`scopedKey(_:)`）。

---

## AI 解析链路

```
用户输入一句话
  → GlobalAIInputBar
  → AppStore.handleAIInput()
  → AIParser（POST to Cloudflare Worker）
  → 解析 AIParsedRecord（bucket: "time" | "note"）
  → 写入对应数据桶
  
兜底：本地规则解析（不走网络）
追问：返回 needsClarification 时，AppStore 暂存 PendingClarification，
      下次提交自动拼接上下文
```

修改 AI schema 时，`AIParser.swift` 中的 `AIParsedRecord` struct 必须与 Cloudflare Worker 的 system prompt 保持同步。

---

## ADHD 友好原则（硬约束，任何改动都不能违反）

这是产品的核心承诺。**所有功能改动、文案改动、UI 改动都必须通过以下检查：**

### 绝对禁止

- ❌ 连续打卡 streak（断了一次就会弃用）
- ❌ "你已经 X 天没打开了" 类通知
- ❌ 完成率百分比、排名、与上周对比的审判式数字
- ❌ 强制必填字段（任何输入框都能空着提交）
- ❌ 高饱和激励色（荧光橙、警告红）

### 必须保证

- ✅ 用词永远温柔：用"留白 / 明天再说 / 先歇一歇"替代"未完成 / 失败 / 错过"
- ✅ 所有删除操作支持撤销
- ✅ 空状态有文案（不能是空白屏，用 mascot 或插画 + 温柔邀请语）
- ✅ 新页面必须有空状态设计

**代码 review 时**：有任何改动触碰上述约束，直接 reject。

---

## SwiftUI 代码约定

- 主题色 / 字体 / 间距定义在 `Sources/Views/CreamTheme.swift`，不要硬编码颜色
- 全局状态通过 `@EnvironmentObject var store: AppStore` 访问
- 避免在 View body 里做复杂计算，提取到 `AppStore` 或 computed property
- 视图文件只放 SwiftUI 视图，业务逻辑放 `AppStore` 扩展
- 不写注释，除非 WHY 不显而易见（绕过系统 bug、隐含不变量等）

---

## 测试

```bash
# Xcode 内：Cmd+U
# 或：
xcodebuild test -scheme PersonalSystem -destination 'platform=iOS Simulator,name=iPhone 15'
```

测试文件在 `Tests/PersonalSystemSmokeTests.swift`。
添加新 Service / 解析逻辑时，**必须补测试**。View 层不强制测试。

---

## PR Checklist

提 PR 前自检：

- [ ] `Secrets.swift` 没有被 stage
- [ ] UI 改动附了截图或录屏
- [ ] ADHD 友好原则没被破坏（见上方硬约束）
- [ ] 新页面有空状态
- [ ] commit message 符合 Conventional Commits
- [ ] 从最新 main 拉的分支（无冲突）

---

## 不该做的事

- **不要手动编辑 `.xcodeproj`**：用 `xcodegen` 从 `project.yml` 生成
- **不要改 `UserDefaults` key 命名**：会导致线上用户数据丢失（除非做迁移）
- **不要向 AI 后端发送用户的私人内容作为日志**：隐私红线
- **不要添加第三方 analytics/tracking SDK**：免费无内购，不收集行为数据
- **不要绕过 PR review 直接 push main**

---

## 联系 & 决策

- 技术问题：开 GitHub Issue（`bug` / `question` label）
- 产品决策：先和 Anna 对齐再动
- 紧急问题：Telegram / 微信直接戳 Anna
