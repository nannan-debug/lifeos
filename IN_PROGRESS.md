# 当前在做：灵感与反思模块 V2

> **目的**：大功能横跨多个 PR 时，这份文档是"在飞状态"的唯一真相。新接手的人（或断线重连的 AI）只看这一份就能继续。
>
> **生命周期**：开工时建 → 每个 PR 合并后更新进度表 → 整个功能上线后，把内容归档到 `docs/archived-features/<feature>.md`，本文件清空换下一个功能。

---

## 元信息

| 项 | 值 |
|---|---|
| 功能名 | 灵感与反思模块 V2 — 自动化 + 不打扰 + 复盘时间维度 |
| 触发来源 | V1（1.2.0）dogfood 后用户真实反馈 |
| 决策来源 | 2026-05-01 的 grill-me session 拍板 |
| 规划版本号 | `1.3.0`（V2 PR 全部合完后再 bump；同一版本会一起带上已合入 `[Unreleased]` 的 iCloud 同步等改动） |
| 当前阶段 | ⏳ PR 1 待开工 |
| 上一版本状态 | `1.2.0 (build 4)` 已 App Store 上架（2026-05-02 过审）。Anna 后续单独做：打 `v1.2.0` tag / 发 GitHub Release / 更新 `LAUNCH_CHECKLIST.md` 状态。 |
| 版本 bump 时机 | 等 V2 PR 1-4 全合完后再开 PR 5 bump 1.3.0（不要中途 bump）|

---

## 主题（一句话）

> 用户 dogfood V1 后反馈："主题不想主动加""关联卡片基本不用还挡正文""复盘没有时间维度"——指向同一个产品方向：**让系统替用户做更多自动化，UI 隐藏没用的部分，复盘要明确时间窗**。

---

## PR 进度表

| # | 标题 | 状态 | PR | 合并日期 |
|---|---|---|---|---|
| 1 | `fix: Review 卡片时间显示去秒级` | ⏳ | — | — |
| 2 | `refactor: 砍第二大脑关联卡片 + 反向链接` | ⏳ | — | — |
| 3 | `feat: 第二大脑 topic AI 自动推荐` | ⏳ | — | — |
| 4 | `feat: 复盘 Hub 本周/本月 toggle` | ⏳ | — | — |
| 5 | `chore: bump 1.3.0 / build 5` | ⏳ | — | — |

总工程量估算：**6-9 个 evening session**（V1 是 17-22 个，V2 比 V1 小很多）

---

## 锁定决策清单

> grill-me 期间逐一拍板。**改动方向前必须先回头改这里**，不要直接动代码。

### 决策 1：Review 卡片时间显示去秒级（V1 落地 bug，归 V2 PR 1 顺手修）

- 现状：`ReviewSessionView.swift` 用 `Text(turn.createdAt, style: .relative)`，会自动 tick "32 秒前 → 33 秒前..."
- 问题：违反 grill-me Q4c "Review 仪式不要计时元素" 的精神（PRD 0.2 仪式原则）
- 修法：改成 **绝对时间戳（如 `5/1 14:30`）**——静态、信息密度低、ADHD 友好

### 决策 2：彻底砍第二大脑关联卡片 + 反向链接

- 现状：BrainCardDetailView 有 3 个 section（来源 / 关联卡片 / 反向链接）
- dogfood 反馈：用户从来没用过"+ 关联卡片"，section 还显眼挡正文
- 决策：**关联卡片 + 反向链接两个 section 完全删除**
  - 删 `Sources/Views/CardLinkPickerSheet.swift`
  - BrainCardDetailView 砍两个 Section + "+ 关联卡片" 按钮
  - AppStore 砍 `linkBrainCards / unlinkBrainCards / backlinks(for:)` 三个方法
  - 相关 4 个单测删（Bidirectional / Idempotent / SelfLink / RemoveCleansBacklinks）
- 数据兼容：`BrainCard.links` Codable 字段**保留**——不破坏老数据反序列化，万一未来恢复也不丢数据。但所有写入路径全部砍。
- ⚠️ 来源（sources）section 不动——这个用户没反馈问题且 ADHD 价值高

### 决策 3：第二大脑 topic AI 自动推荐（混合：AI 推荐 + 用户接受/拒绝）

- 现状：用户从不主动给卡片打 topic → 主题视图永远空 → "主题"功能死的
- 决策：**AI 推荐 chip + 用户一键接受/拒绝**，保留手动输入能力

#### 默认主题集（5 个）

```
工作 / 学习 / 生活 / 灵感 / 人际
```

> 设计依据：grill-me 时讨论用户最初提的 7 项（工作/学习/金融/科技/生活/人际/思维）粒度不统一。"思维"太宽几乎所有卡片都属于；"金融/科技"是个人领域不通用。精简到 5 个：场景（工作/学习/生活）+ 类型（灵感/人际）。

#### 触发时机：sheet 打开时立即调（grill-me Q6=A）

- 进 `BrainCardEditorSheet` 时（不论是 .deriveFromTurn 还是 .edit）立即在后台调一次 AI
- loading 状态：灰色 chip 占位 + 旋转 indicator
- 结果回来后 chip 变可点击，用户点接受 / 点 X 拒绝
- 推荐 chip 跟用户已选 chip 视觉区分（"AI 觉得是 [...]" 分组）

#### 失败兜底：静默 + 不强制（grill-me Q7=A+C）

- AI 调用失败：**不显示推荐**（什么都不发生），用户照常手动加 topic
- AI 准确但用户没接受：保存时**不强制 topic**，可以保存空 topic 卡片（ADHD 友好原则反对强制必填）

#### Prompt 设计要点（实现时参考，可调）

```
输入：title + content
输出：1-3 个 topic（优先从默认集 [工作/学习/生活/灵感/人际] 选；可创新但应简洁有概括性）
格式：JSON 数组，topic 不带 #（UI 层归一加 #）
```

#### Topic 概念**只在第二大脑用**（grill-me Q3c=A）

- 不扩到 ToDo / ConversationTurn —— V2 不做大分类系统重构

### 决策 4：复盘 Hub 加本周/本月 toggle

- 现状：Hub 三个数字（待处理/已处理/搁置）固定 7 日窗口，**没文字说明窗口**——用户搞不清看的是哪段时间
- 决策：**Hub 顶部加 segment "本周 / 本月" toggle**
  - 三个数字按 toggle 切窗口（7 天 / 30 天）
  - `ReviewQueue.archivedCount/dismissedCount/pendingCount` 加 `windowDays: Int = 7` 参数
- **Review 队列保持 7 日窗不变**（grill-me Q4b=A）
  - 切到"本月"时 Hub 显示 30 天数字，但点进 Review 模式队列仍只 7 天
  - 加一行小字提示「队列仍为最近 7 天」避免用户困惑

---

## 不在 V2 范围（V3+ 延后）

- DBT 行为链分析 + 自我觉察档案（最大延期项）
- 复盘 Tab 完整阅读型统计（饼图 / 心情时间线 / AI 一句温柔总结）
- 第二大脑 Markdown 渲染 / 视觉气质 / 直接录入入口
- 关联图谱可视化
- 反向链接 context 显示（既然反向链接砍了，自动作废）
- 把 topic 概念扩到 ToDo / ConversationTurn 全局分类系统
- 被动建链建议（第二大脑 PRD 5.5 机制 1）—— 关联卡片砍了后这个也作废
- AI 摘要、AI 一句温柔总结（除了 topic 推荐这种小颗粒，其他都延后）

---

## PR 1-4 实施 breakdown

> 每个 PR 都要：
> 1. 从最新 main 拉分支 `<type>/<branch-name>`
> 2. 写代码 + 跑测试（`xcodebuild test -scheme PersonalSystem -destination 'platform=iOS Simulator,name=iPhone 17'`）
> 3. **如有用户可见变化 → 同时更新 `CHANGELOG.md [Unreleased]`**（[`AGENTS.md`](AGENTS.md) 的强制规则）
> 4. 让 Anna review → squash merge → 把这份 IN_PROGRESS.md 进度表对应行标 ✅
> 5. 为下一个 PR 标 🚧

### PR 1 · `fix: Review 卡片时间显示去秒级`

**改的文件**（1 个）：

- `Sources/Views/ReviewSessionView.swift` —— 把 `Text(turn.createdAt, style: .relative)` 改成绝对时间戳显示
  - 期望显示格式：`5/1 14:30`（年份省略，月日时分）
  - 实现思路：自定义一个 `static let timeStampFormatter: DateFormatter` （`MM/dd HH:mm`），`Text(turn.createdAt, formatter: ...)`
  - 注意 `.relative` 是 Date 用 trailing closure 形式的 SwiftUI Text 初始化器；改用 `Text(date, formatter:)` 是另一个初始化器

**Test plan**：

- [ ] 真机跑：复盘 Tab → Review → 队列卡片顶部时间从"X 秒前"变成 `5/1 14:30` 静态格式
- [ ] 静态：屏幕停留一分钟，时间不再 tick
- [ ] 单测不需要新增（视觉级改动）

**CHANGELOG [Unreleased]**：

- 不写。这是 V1 落地的小 bug 修，用户感知低，归内部修复。**不写进 [Unreleased]**。

**估算**：1 晚（约 1h，含编译验证）

---

### PR 2 · `refactor: 砍第二大脑关联卡片 + 反向链接`

**改/删的文件**：

- 🗑️ 删：`Sources/Views/CardLinkPickerSheet.swift`
- ✏️ 改：`Sources/Views/BrainCardDetailView.swift`
  - 删整个 "关联卡片" Section（含 `linked` computed property、`showLinkPicker` State、`.sheet(isPresented: $showLinkPicker)`）
  - 删整个 "反向链接" Section（含 `backlinks` computed property）
  - 详情页只保留：标题/topics/content + 来源 section + 编辑按钮
- ✏️ 改：`Sources/ViewModels/AppStore.swift`
  - 删 `linkBrainCards(_:_:)` 方法
  - 删 `unlinkBrainCards(_:_:)` 方法
  - 删 `backlinks(for:)` 方法
  - **保留** `BrainCard.links: [UUID]` 字段（Codable 兼容老数据；reload 时仍能反序列化老卡片的 links 数组——只是没人读它了）
  - **保留** `removeBrain(id:)` 里的 "反向清理 links" 那段（作为防御性清理，对未来可能恢复也有意义；约 5 行）
- ✏️ 改：`Tests/PersonalSystemSmokeTests.swift` 删 4 个 case：
  - `testLinkBrainCardsBidirectionalAndIdempotent`
  - `testLinkBrainCardsRejectsSelfLink`
  - `testUnlinkBrainCardsBidirectional`
  - `testBacklinksLookup`
  - **`testRemoveBrainCleansBacklinks` 保留**（仍验证 removeBrain 防御性清理逻辑——如果保留了那段代码）

**Test plan**：

- [ ] `xcodebuild test` 全绿（保留 case 数应该是原来的减 4）
- [ ] 真机跑：进任何一张卡片详情页，**不再看到**"关联卡片"和"反向链接" section
- [ ] 老卡片如果有 links 数据：进卡片详情页不报错（兼容验证）

**CHANGELOG [Unreleased]**：

```markdown
### 改进
- 第二大脑卡片详情简化：移除"关联卡片 / 反向链接"section，腾出正文空间。手动建链使用率太低，让位给后续的自动化方案（[#PR编号]）
```

**估算**：1-2 晚（约 1.5h，主要工作是清理 + 跑测试）

---

### PR 3 · `feat: 第二大脑 topic AI 自动推荐`

**改/新建文件**：

- ✏️ 改：`Sources/Services/AIParser.swift` —— 加新方法 `static func suggestTopics(title: String, content: String) async throws -> [String]`
  - 调 Cloudflare Worker（`ai.dogdada.com`）的 topic 推荐 endpoint（要跟 Worker 端协调；如 endpoint 暂未实现，先用现有 `parse` endpoint 拼接特殊 prompt 走通流程）
  - 输出：`[String]`，每项不带 `#`，UI 归一加 `#`
- ✏️ 改：`Sources/Views/TopicChipInput.swift` —— 现有结构上加 "AI 推荐" 分组
  - 多一个 `@Binding var aiSuggestions: [String]?`（nil = 还没调或失败；空数组 = 调过没结果；非空 = 显示）
  - 推荐 chip 视觉跟已选 chip 区分（如：浅色背景 + "AI 觉得"前缀 / 不同 tint）
  - 点 chip 一次 → 移到已选区
- ✏️ 改：`Sources/Views/BrainCardEditorSheet.swift`
  - 加 `@State private var aiSuggestions: [String]? = nil` + `@State private var aiLoading = false`
  - `onAppear` 后启动 `Task` 调 `AIParser.suggestTopics(...)`
  - 触发时机：sheet 一打开就调（hydrate 之后），不管是 .deriveFromTurn 还是 .edit
  - 失败：catch 里设 `aiSuggestions = []`（静默降级）
  - 把 `aiSuggestions` 传给 `TopicChipInput`
- ✏️ 改：`Sources/Views/TopicChipInput.swift`（同上）
  - **注意**：默认主题集 `["工作", "学习", "生活", "灵感", "人际"]` 也通过现有 `availableTopics` 注入。需要 BrainCardEditorSheet 调用方把"默认集 + 老 topic 历史"合并去重传入

**Prompt 设计**（实现时参考，AIParser 内部）：

```
System / 任务描述：
你是一个第二大脑卡片分类助手。给定一张卡片的 title 和 content，
输出 1-3 个最贴切的主题标签。

优先从以下默认集选：[工作, 学习, 生活, 灵感, 人际]
如默认集都不贴切，可以创新（但应简洁、可复用、有概括性）。

输出：JSON 数组，每项是字符串，**不带 # 前缀**。
例：["工作", "命名"]

不要输出任何其他内容。
```

**Test plan**：

- [ ] 单测：mock AIParser.suggestTopics 返回固定数组，验证 BrainCardEditorSheet 把推荐传进 TopicChipInput
- [ ] 真机：从 Review 模式右滑 → 第二大脑，sheet 打开 → loading → 1-2 秒后看到推荐 chip
- [ ] 真机：点推荐 chip 移到已选区
- [ ] 真机：AI 失败时（断网测试）不显示推荐，sheet 仍可保存
- [ ] 真机：保存空 topic 卡片不报错（不强制必填）

**CHANGELOG [Unreleased]**：

```markdown
### 新增
- 第二大脑卡片创建/编辑时，AI 自动推荐 1-3 个主题标签——一键接受或忽略，不强制（[#PR编号]）
- 默认主题集：工作 / 学习 / 生活 / 灵感 / 人际（也能继续手动添加任意主题）
```

**估算**：3-4 晚（含 Cloudflare Worker 端 endpoint 协调、prompt 调试）

⚠️ **依赖**：如果 Worker 端没现成的 topic 推荐 endpoint，需要 Anna 在 Worker 仓库（不在本仓）加一个，或 V2 PR 3 临时 fallback 走 `parse` endpoint 拼特殊 prompt。先确认能力再开干。

---

### PR 4 · `feat: 复盘 Hub 本周/本月 toggle`

**改的文件**：

- ✏️ 改：`Sources/Views/ReviewSessionView.swift`
  - `enum ReviewQueue` 4 个静态方法都加 `windowDays: Int = 7` 参数（默认 7 天保持向后兼容）
  - `filtered(turns:now:statuses:)` 用 `windowDays` 算 cutoff
- ✏️ 改：`Sources/Views/ReviewHubView.swift`
  - 顶部加 `@State private var window: HubWindow = .week` enum，segment toggle 切换 "本周 / 本月"
  - `pending / archived / dismissed` computed property 根据 `window` 调 `ReviewQueue.*Count(turns:now:windowDays:)`，week=7, month=30
  - 切 "本月" 时在 Review 卡片底部加一行小字提示「Review 队列仍为最近 7 天」
  - toggle 状态用 `@AppStorage("review.hub.window")` 持久化，默认 `.week`
- ✏️ 改：`Tests/PersonalSystemSmokeTests.swift` 加 1-2 个 case：
  - `testReviewQueue30DayWindow`：构造 14 天前/29 天前/31 天前的 turn，验证 windowDays=30 时只有前两个进队列

**Test plan**：

- [ ] 单测：`testReviewQueue30DayWindow` 通过
- [ ] 真机：复盘 Tab 顶部出现 "本周 / 本月" toggle
- [ ] 真机：切 "本月" 时三个数字会变（如果用户有 7-30 天前的处理记录）
- [ ] 真机：切 "本月" 时下方有 "Review 队列仍为最近 7 天" 小字
- [ ] 真机：杀进程重启后 toggle 状态保留（@AppStorage 持久化生效）

**CHANGELOG [Unreleased]**：

```markdown
### 新增
- 复盘 Tab Hub 顶部加「本周 / 本月」切换：本月可以看到 30 天的处理统计，明确时间维度。Review 队列保持最近 7 天不变，避免 P 人面对一座积压山（[#PR编号]）
```

**估算**：1-2 晚（约 1.5h）

---

### PR 5 · `chore: bump 1.3.0 / build 5`

> **触发条件**：V2 PR 1-4 全部合并到 main 之后再开本 PR，避免中途 bump。1.2.0 已经过审上架（2026-05-02），版本 bump 路径已通畅。

**改的文件**：

- ✏️ 改：`project.yml`
  - `CFBundleShortVersionString: 1.3.0`
  - `CFBundleVersion: "5"`
  - `MARKETING_VERSION: 1.3.0`
  - `CURRENT_PROJECT_VERSION: 5`
- 跑 `xcodegen` 同步到 Info.plist + pbxproj
- ✏️ 改：`CHANGELOG.md`
  - 把 `[Unreleased]` 段落整个搬到新建的 `## [1.3.0] (build 5) — YYYY-MM-DD` 段落（含 iCloud 同步 + V2 四项内容）
  - `[Unreleased]` 重置为 `（暂无）`
- 验证：`grep -A1 "CFBundleVersion" Sources/App/Info.plist` 看到 5

**Test plan**：

- [ ] xcodegen 后无报错
- [ ] Info.plist 看到新版本号
- [ ] CHANGELOG 1.3.0 段落完整含所有 V2 + iCloud 内容
- [ ] PR 描述贴上 [LAUNCH_CHECKLIST §4](LAUNCH_CHECKLIST.md#4-后续版本更新流程每次发版的标准-sop) 链接，提醒 Anna 之后手动 Archive / Upload / Submit

**估算**：0.5 晚（约 30min）

⚠️ **不要替 Anna 跑 Archive / Upload / Submit**——按 [`CLAUDE.md`](CLAUDE.md) 硬规则，这些必须 Anna 手动在 Xcode / ASC 里点。

---

## 接手指南（如果 Claude 掉线 / 换人继续）

按以下顺序读，5 分钟可上手：

1. 读这份 `IN_PROGRESS.md`（你正在看）
2. 读 [`CLAUDE.md`](CLAUDE.md) 工作规范 + ADHD 硬约束
3. 读 [`AGENTS.md`](AGENTS.md) 的"主动沉淀"规则（每个 PR 要不要更新 CHANGELOG / IN_PROGRESS）
4. 读 [`CONTRIBUTING.md`](CONTRIBUTING.md) 分支 / commit 规范
5. 读 [`LAUNCH_CHECKLIST.md`](LAUNCH_CHECKLIST.md) §4.8（**审核期间**开发策略 — 我们当前就在审核期内）
6. 看上方 PR 进度表 → 找下一个 ⏳ 的 PR
7. 看上方 "PR 1-4 实施 breakdown" 对应该 PR 那一节
8. 跑 `git fetch && git log main..origin/main --oneline` 确认 main 最新
9. 从最新 main 拉新分支
10. 写代码 → 测试 → 提醒 Anna review → squash merge

**关键提醒**：

- 🟡 `1.2.0 (build 4)` 已上架（2026-05-02），版本 bump 通畅；但不要在 PR 1-4 中途 bump，等 PR 5 一次性做
- 🔴 改完代码必须**提醒 Anna commit**，不要自己 commit
- 🔴 任何"是否扩大本 PR 范围"的犹豫 → 停下来问 Anna
- 🔴 想动"锁定决策清单"任何一条 → 停下来问 Anna
- 🟡 每次 PR 合并后**手动更新本 IN_PROGRESS.md 进度表**（无自动化）
- 🟡 用户可见变化的 PR 要顺手更新 `CHANGELOG.md [Unreleased]`（[`AGENTS.md`](AGENTS.md) 强制规则）

---

## V2 上线后这份文档怎么处理

V2 全部 PR 合完 + 1.3.0 上架后：

1. 把当前内容复制到 `docs/archived-features/v2-inspiration-reflection.md`
2. 清空本文件（改成"当前在做：（无）"）
3. [`CHANGELOG.md`](CHANGELOG.md) 已经在 PR 5 的时候整理好了 1.3.0 段落
