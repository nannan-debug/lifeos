# CLAUDE.md — LifeOS iOS

> 这份文件是 Claude Code 的工作规范。在开始任何任务前请先阅读全文。

---

## 项目概览

**LifeOS** 是一款为 ADHD 人群设计的「人生观察系统」。
核心理念：低摩擦记录 + 可视化回看，帮助用户看清自己的生活，而非"优化"自己。

- 技术栈：SwiftUI · Swift 5.9 · iOS 17+ · XcodeGen
- 数据存储：本地 `UserDefaults`（按 `userId` 分库）+ CloudKit 同步（private database，`CKSyncEngine`）
- AI 后端：Cloudflare Worker (`ai.dogdada.com`) + DeepSeek LLM
- 仓库：`github.com/nannan-debug/lifeos`

---

## 仓库结构

```
Sources/
  App/          # 入口 + Info.plist + Assets
  Models/       # 数据模型（Models.swift）
  ViewModels/   # AppStore（全局状态）
  Services/     # AgentManager + AIParser + AIClient + Secrets（Secrets.swift 已 gitignore）
  Views/        # 所有 SwiftUI 页面
CloudflareWorkers/
  personal-ai-proxy/  # Cloudflare Worker（AI 代理 + prompt 管理）
Tests/          # 单元测试
scripts/        # Python 实验脚本（agent_lab.py）
project.yml     # XcodeGen 配置，版本号 source of truth，勿手编 .xcodeproj
Secrets.example.swift  # Secrets 模板，真实文件不进仓库
```

**关键文件：**
- `Sources/ViewModels/AppStore.swift` — 全局状态，所有 @Published 数据都在这里
- `Sources/Services/AgentManager.swift` — Agent 核心：会话管理、快录/对话路由、Memory CRUD、action card 生命周期
- `Sources/Services/AIParser.swift` — AI 网络层：chat / quick / extractMemories 请求
- `Sources/Services/AIClient.swift` — AIClient 协议（依赖注入，方便测试 mock）
- `Sources/Services/AgentOrchestrator.swift` — 构建 contextSummary（随手记+待办+时间+打卡+memory）
- `Sources/Views/GlobalAIInputBar.swift` — 全局浮动输入框（快录/对话模式切换）
- `Sources/Views/RootTabView.swift` — Tab 容器
- `CloudflareWorkers/personal-ai-proxy/worker.js` — AI 代理（prompt、路由、工具端点）
- `scripts/agent_lab.py` — Python 快速实验脚本（测 prompt 不需要 Xcode rebuild）
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
| `ConversationTurn` | 随手记（想法/感受/感恩/做梦，含 payload 字典存标题等元数据） |
| `AgentChatSession` | Agent 对话会话（消息历史 + pending action cards） |
| `AgentMemory` | 跨会话记忆（content/category/lastUsedAt，上限 15 条） |
| `AgentActionDraft` | Agent 建议的 action card（inbox/task/time 三种） |

数据通过 `AppStore` 持久化到 `UserDefaults`，key 按 `userId` 前缀隔离（`scopedKey(_:)`）。

---

## Agent 架构

三层架构：iOS App → Cloudflare Worker（代理 + prompt）→ DeepSeek LLM

```
用户输入
  → GlobalAIInputBar（快录/对话模式手动切换）
  ├─ ⚡ 本地快录：纯本地关键词解析，不走网络
  ├─ ↑ AI 快录（默认）：单轮 → AIParser.quick() → Worker handleQuick
  │   不带历史、不带 contextSummary、不带 memory
  │   max_tokens: 500, temperature: 0.3
  └─ 💬 对话模式（手动切换）：多轮 → AgentManager.send() → Worker handleChat
      带历史（最近 8 轮）+ contextSummary + memory（最多 10 条）

Worker 返回 → AgentChatResponse（reply + actionSuggestions）
  → action cards 展示在输入栏上方，用户确认后写入数据桶
```

**核心流程文件：**
- `GlobalAIInputBar` → `AppStore.submitQuickText()` 或 `submitAgentText()`
- `AgentManager.quickSend()` / `send()` → `AIClient.quick()` / `chat()`
- `AgentOrchestrator.makeContextSummary()` 拼接上下文（随手记带标题 + 待办 + 时间 + 打卡 + memory）
- `AgentManager.mergeActionSuggestions()` 管理 action card 去重与替换
- `AgentManager.confirmAction()` → `AppStore` 写入数据

**Memory 系统：**
- 仅对话模式使用，快录模式不涉及
- 清空对话时自动提取（≥4 条消息触发，调 Worker `extract_memories` utility）
- 每次最多提取 3 条，每条 ≤60 字，分 fact/preference/summary 三类
- 总上限 15 条，按 `lastUsedAt` LRU 淘汰
- 对话模式首轮随 contextSummary 注入（Worker 只在 history 为空时发 system prompt）
- 设置页可手动查看/添加/删除 memory

**Worker 端点（`CloudflareWorkers/personal-ai-proxy/worker.js`）：**
- `mode: "chat"` → 多轮对话，完整 system prompt + 历史
- `mode: "quick"` → 单轮快录，极简 prompt，无历史
- `mode: "utility"` → 工具端点（`extract_memories` / `suggest_topics` / `suggest_title`）

**Prompt 实验：** `python3 scripts/agent_lab.py` 可快速测试 prompt 效果（30 秒反馈），不需要 Xcode rebuild。支持 `quick "文本"` / `chat` / `test_quick_vs_chat` 三种模式。

**修改 prompt / action schema 时：** Worker 的 system prompt 和 iOS 端的 `AgentChatResponse` / `AgentActionDraft` 解码必须保持同步。改完 Worker 需 `cd CloudflareWorkers/personal-ai-proxy && npx wrangler deploy` 部署。

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

测试文件在 `Tests/PersonalSystemSmokeTests.swift`。
添加新 Service / Agent 逻辑时，**必须补测试**。View 层不强制测试。
Agent 相关测试使用 `MockAIClient`（实现 `AIClient` 协议），不依赖真实网络。

---

## PR Checklist

提 PR 前自检：

- [ ] `Secrets.swift` 没有被 stage
- [ ] UI 改动附了截图或录屏
- [ ] ADHD 友好原则没被破坏（见上方硬约束）
- [ ] 新页面有空状态
- [ ] Agent prompt / schema 改动已同步 Worker 和 iOS 端
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

## 数据安全红线

LifeOS 的数据是本地优先存储，删 App 即清空本机数据。曾因忽视这一点导致用户数据丢失，以下为硬规则：

- **不要为排查构建 / 签名问题而删除 App**：必须先用设置页「导出全部数据」或确认 CloudKit 已同步，再删。
- **不要用存有真实个人数据的设备 / 账号做开发调试**：用模拟器或测试账号；真机验证前先确认数据已备份。
- **抹机 / 删除 App / reset 等破坏性操作前，先确认有一份已验证的备份。**
- 涉及 iCloud / CloudKit 同步逻辑改动时，绝不能让「本机为空」反向覆盖、清空云端数据。

---

## 联系 & 决策

- 技术问题：开 GitHub Issue（`bug` / `question` label）
- 产品决策：先和 Anna 对齐再动
- 紧急问题：Telegram / 微信直接戳 Anna
