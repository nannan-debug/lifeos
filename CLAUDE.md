# CLAUDE.md — LifeOS iOS

> 这份文件是 Claude Code 的工作规范。在开始任何任务前请先阅读全文。

---

## 项目概览

**LifeOS** 是一款为 ADHD 人群设计的「人生观察系统」。
核心理念：低摩擦记录 + 可视化回看，帮助用户看清自己的生活，而非"优化"自己。

- 技术栈：SwiftUI · Swift 5.9 · iOS 16+ · XcodeGen
- 数据存储：本地 `UserDefaults`（按 `userId` 分库）
- AI 后端：Cloudflare Worker (`ai.dogdada.com`) + DeepSeek LLM
- 仓库：`github.com/nannan-debug/lifeos`

---

## 仓库结构

```
Sources/
  App/          # 入口 + Info.plist + Assets
  Models/       # 数据模型（Models.swift）
  ViewModels/   # AppStore + AIRoutingPolicy 等全局状态 / 策略
  Services/     # AIParser + 系统服务 + Secrets（Secrets.swift 已 gitignore）
  Views/        # 所有 SwiftUI 页面
Tests/          # 单元测试 + Fixtures 标准样本库
project.yml     # XcodeGen 配置，版本号 source of truth，勿手编 .xcodeproj
Secrets.example.swift  # Secrets 模板，真实文件不进仓库
```

**关键文件：**
- `Sources/ViewModels/AppStore.swift` — 全局状态，所有 @Published 数据都在这里
- `Sources/Services/AIParser.swift` — AI 解析逻辑与 schema 定义
- `Sources/ViewModels/AIRoutingPolicy.swift` — AI record 落库前的本地归类策略
- `Sources/Views/RootTabView.swift` — Tab 容器
- `project.yml` — XcodeGen 配置，改依赖/Target 时在这里改
- `Tests/Fixtures/ai-routing-cases.json` — AI 识别回归样本库

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

## 状态文档与交接工作流

开始任何任务前按顺序读：

1. `IN_PROGRESS.md`
2. `CLAUDE.md`
3. `AGENTS.md`
4. `CONTRIBUTING.md`
5. `VERSIONING.md`
6. `LAUNCH_CHECKLIST.md`
7. `CHANGELOG.md`

接手时先汇报：当前 git 分支、工作区是否干净、最近 release/tag 状态、`IN_PROGRESS.md` 当前状态、`main` 是否包含用户指定的关键 PR。

状态文档分工：

- `IN_PROGRESS.md`：只记录跨多个 PR 的在飞大功能；单 PR 小改动不强行写入。
- `CHANGELOG.md`：审核期间继续开发时，用户可见变化写入 `[Unreleased]`。
- `LAUNCH_CHECKLIST.md`：记录 App Store 审核 / 上架真实状态，以及必须由用户手动处理的 Apple Developer / ASC 步骤。

审核期间继续开发：

- 从最新 `main` 新建功能分支，照常 PR。
- 不改当前审核中版本号，不重新 Archive / Upload / Submit。
- 不打 tag，不创建 GitHub Release；只有 ASC 显示已上架 / Ready for Distribution 后才做。

---

## 版本号规范

详见 `VERSIONING.md`，核心要点：

- Marketing Version：`MAJOR.MINOR.PATCH`（用户可见，`CFBundleShortVersionString`）
- Build Number：单调递增，永不回退（`CFBundleVersion`）
- `project.yml` 是版本号 source of truth；改完必须跑 `xcodegen` 同步 `Info.plist` 和 `.xcodeproj`
- 发版 PR 只做版本号、`xcodegen` 同步、`CHANGELOG` 归档、必要的发版状态文档
- tag / GitHub Release 只在 App Store 已上架后做，不在 Submit to App Review 时做

**当前状态以 `LAUNCH_CHECKLIST.md` 为准。**

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

AI 落库前必须经过 `AIRoutingPolicy`。`AppStore` 负责真正写入数据，`AIRoutingPolicy` 只判断：进入哪个 bucket、是否跳过、是否需要二次确认。

AI 识别规则与回归样本维护：

- 产品契约在 `docs/ai-recognition-rules.md`。
- 标准样本库在 `Tests/Fixtures/ai-routing-cases.json`。
- 自动化测试在 `Tests/AIRoutingPolicyTests.swift`。
- 修 AI 归类 bug 时，先把失败输入脱敏后加入样本库，再改策略。
- 如果改了 bucket 边界、二次确认标准或样本标签，同步更新规则文档。

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
xcodebuild test -project PersonalSystem.xcodeproj -scheme PersonalSystem -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath .deriveddata
```

测试文件在 `Tests/PersonalSystemSmokeTests.swift` 和按功能拆分的测试文件中。
添加新 Service / 解析逻辑 / AI 路由策略时，**必须补测试**。View 层不强制测试。

AI 识别回归测试流程：

1. 从真实问题或调试导出中提炼脱敏输入。
2. 加入 `Tests/Fixtures/ai-routing-cases.json`，写清 `expectedRecords`、`notes`、`tags`。
3. 修改 `AIRoutingPolicy` 或相关解析逻辑。
4. 跑完整单测，确认旧样本没有回归。

---

## PR Checklist

提 PR 前自检：

- [ ] `Secrets.swift` 没有被 stage
- [ ] UI 改动附了截图或录屏
- [ ] ADHD 友好原则没被破坏（见上方硬约束）
- [ ] 新页面有空状态
- [ ] AI 识别 / 归类改动已更新样本库和规则文档
- [ ] 审核期间的用户可见改动已写入 `CHANGELOG.md` `[Unreleased]`
- [ ] 发版 / 审核状态变化已更新 `LAUNCH_CHECKLIST.md`
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
