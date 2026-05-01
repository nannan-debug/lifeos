# 当前在做：灵感与反思模块 V1

> **目的**：大功能横跨多个 PR 时，这份文档是"在飞状态"的唯一真相。新接手的人（或断线重连的 AI）只看这一份就能继续。
>
> **生命周期**：开工时建 → 每个 PR 合并后更新进度表 → 整个功能上线后，把内容归档到 `docs/archived-features/<feature>.md`，本文件清空换下一个功能。

---

## 元信息

| 项 | 值 |
|---|---|
| 功能名 | 灵感与反思模块 V1 |
| PRD 来源 | `~/Desktop/灵感与反思模块_PRD.md`（私人本地，不进仓库） |
| 决策来源 | 2026-04-30 的 grill-me session 拍板（见下方"锁定决策清单"） |
| 规划版本号 | `1.2.0`（V1 全部 PR 合完后再 bump，按 [VERSIONING.md](VERSIONING.md) §"怎么改版本号"） |
| 当前阶段 | ⏳ PR 5 待开工（最后一关） |

---

## PR 进度表

| # | 标题 | 状态 | PR | 合并日期 |
|---|---|---|---|---|
| 1 | `chore: 清理旧版 InboxView / 旧 ReviewView 与镜像数据写入` | ✅ | [#11](https://github.com/nannan-debug/lifeos/pull/11) | 2026-04-30 |
| 2 | `refactor: 砍随记 Tab 周视图 + 抽 TodoEditorSheet 到独立文件` | ✅ | [#12](https://github.com/nannan-debug/lifeos/pull/12) | 2026-05-01 |
| 3 | `feat: 数据模型扩展 — derivatives / sourceNoteId / BrainCard` | ✅ | [#13](https://github.com/nannan-debug/lifeos/pull/13) | 2026-05-01 |
| 4 | `feat: 复盘 Tab + Review 模式核心 + → ToDo 衍生` | ✅ | [#15](https://github.com/nannan-debug/lifeos/pull/15) | 2026-05-01 |
| 5 | `feat: 第二大脑完整模块` | ⏳ | — | — |

---

## 锁定决策清单

> grill-me 期间逐一拍板。**改动方向前必须先回头改这里**，不要直接动代码。

### 总体架构

- 进化现有 `QuickCaptureView`，**不**新建并行模块
- 新增第 5 个 Tab "复盘"（图标 `moon.stars`）
- 第二大脑 / 自我觉察档案入口埋在复盘 Tab 二级页（不上 tab bar）
- 砍随记 Tab 顶部"日 / 周"toggle（已在 PR 2 落地）

### Review 模式

- **队列**：`reviewStatus == "pending" && recognizedType ∈ {想法, 感受} && createdAt 在最近 7 天内`，按 `createdAt` 倒序
- **不要计时器，不要"承诺 1 小时"文案**
- 滑动手势：
  - 左滑（trailing）：`[搁置]` → `reviewStatus = "dismissed"`
  - 右滑（leading）：
    - 想法卡片：`[→ 第二大脑] [→ ToDo]`
    - 感受卡片：`[→ 第二大脑]`（PRD 3.4 硬规则：感受不能直接转 ToDo）
- 处理动作完成后：`reviewStatus = "archived"` + `derivatives` append 一条
- **没有"跳过"动作**（用 7 日窗口自然淘汰，不需要手动延期）

### → ToDo 衍生

- 复用 `TodoEditorSheet`（PR 2 已抽出）
- 标题预填 = turn 原文前 20 字，剩下进 notes
- `TaskEntry.sourceNoteId` + `sourceExcerpt`（前 30 字）记录来源

### → 第二大脑 衍生

- 弹 `BrainCardEditorSheet`，`BrainCardSource` 自动建立
- 来源处理同上

### 第二大脑（V1 范围）

- 卡片墙：标准 List，按 `createdAt` 倒序
- 顶部 segment toggle "卡片墙 / 主题"
- 主题视图：顶部水平 topic chip，选中后下方变成该 topic 卡片列表
- 卡片详情页：title + topics + content + 来源 section + 关联卡片 section + 反向链接 section
- 编辑入口：详情页右上角"编辑"按钮 → 弹 `BrainCardEditorSheet`
- topics 输入：chip 输入器（回车添加 + 老 topic 模糊补全）
- "+ 关联卡片"：弹 sheet 列所有其他卡片 + 顶部搜索框 + 勾选建链（双向）
- 创建入口：**仅 Review 衍生**。V1 不做"+"按钮 / 全局快捷入口

### 复盘 Tab Hub

- 进 Tab 是 Hub（不直接进 Review 模式，保留仪式感）
- 内容：
  - "Review" 卡片：显示「待处理 N · 已处理 N · 搁置 N」三个数字 + 整卡 NavigationLink push 进 Review 模式
  - "第二大脑" 卡片：PR 4 阶段显示"即将上线"占位；PR 5 激活后显示张数 + 最近 2 张 title 预览
- 数字颜色：保持中性（不用警告橙），ADHD 友好原则
- **不补"本周记录速览"**（之前砍周视图后特意决定不补）

### 数据模型（PR 3 已落地）

```swift
ConversationTurn 加 derivatives: [TurnDerivative] = []
TaskEntry 加 sourceNoteId: UUID? + sourceExcerpt: String
BrainCard / BrainCardSource / TurnDerivative 三个新类型
AppStore 加 brainCards / addBrain / linkBrainCards / backlinks 等
```

详见 [PR #13](https://github.com/nannan-debug/lifeos/pull/13)。

---

## PR 5 实施 breakdown

> 这一节是给开 PR 5 时直接照着干的工程清单。功能层面的"做什么"看上方"锁定决策清单"，本节只回答"动哪些文件 / 验收什么样"。

### 新建文件（5 个）

| 文件 | 职责 |
|---|---|
| `Sources/Views/BrainCardWallView.swift` | 第二大脑卡片墙入口页：顶部 segment toggle "卡片墙 / 主题"；卡片墙是 List 按 `createdAt` 倒序，每行 title + content 前 60 字 + topic chip + sources count；点 row push 到 BrainCardDetailView |
| `Sources/Views/BrainCardDetailView.swift` | 卡片详情页（PRD 5.7 wireframe）：title + topics chip 一行 + content 多行 + Section "🔗 来源 (N)" + Section "🔗 关联卡片 (N)"（底部 "+" 按钮弹 CardLinkPickerSheet） + Section "🔗 反向链接 (N)"（用 `store.backlinks(for:)` 反查）。右上角 toolbar "编辑" 弹 BrainCardEditorSheet |
| `Sources/Views/BrainCardEditorSheet.swift` | 创建/编辑 sheet：title TextField + content multiline TextField + TopicChipInput；创建模式如有 sources（从 turn 衍生）则只读显示；编辑模式 sources 也只读；保存调 `store.addBrain` 或 `store.updateBrain` |
| `Sources/Views/CardLinkPickerSheet.swift` | "+ 关联卡片" sheet：顶部 SearchBar filter title；List 显示所有其他卡片（排除自己 + 已链接的）；勾选自动调 `store.linkBrainCards(currentId, otherId)`；"完成"关 sheet |
| `Sources/Views/TopicChipInput.swift` | topics 输入器（独立可复用组件）：输入框 + 已加 chip 横向显示 + 老 topic 模糊补全（输入 "命" 弹 #命名 候选），按回车添加 |

### 修改文件（4 个）

| 文件 | 改动 |
|---|---|
| `Sources/Views/ReviewSessionView.swift` | 想法卡片右滑增加 `[→ 第二大脑]` 按钮（顺序：[→ 第二大脑] [→ ToDo]）；感受卡片右滑解锁 `[→ 第二大脑]`（PRD 3.4 V1 阶段终于完整）；点击弹 `BrainCardEditorSheet`（带 sources 预填），保存后联动 `appendTurnDerivative(type: "brain")` + `updateTurnReviewStatus("archived")` |
| `Sources/Views/ReviewHubView.swift` | 第二大脑卡片**激活**：从"即将上线"改成显示 `store.brainCards.count` 张 + 最近 2 张 title 预览；整卡 NavigationLink push 进 `BrainCardWallView` |
| `Sources/Views/TodoEditorSheet.swift` | 可能不动。但要回顾：`.deriveFromTurn` 模式现在的 save 联动 `type: "todo"` derivative —— PR 5 加 `BrainCardEditorSheet` 时同样模式联动 `type: "brain"` derivative，可考虑 store 提个统一的 helper（按需重构，不必强求） |
| `Sources/ViewModels/AppStore.swift` | 视情况加便利方法：`recentBrainCards(limit: Int)`（Hub 卡片预览用）；其他在 PR 3 已经齐了 |

### Test plan（合 PR 前手动跑一遍）

- [ ] 复盘 Tab Hub 第二大脑卡片显示张数 + 最近 2 张 title 预览
- [ ] Hub 第二大脑卡片点击 push 进 `BrainCardWallView`
- [ ] 卡片墙顶部"卡片墙 / 主题"toggle 切换正常
- [ ] 主题视图顶部 topic chip 选中后下方筛选正确
- [ ] **想法 → 第二大脑 端到端**：随记输入想法 → 复盘 → Review → 右滑 → 选 [→ 第二大脑] → 编辑器弹出 sources 预填可见 → 填 title / content / topics → 保存 → 卡片墙看到新卡 → 主题视图 topic 归类正确 → 详情页"来源"section 显示原 turn excerpt → derivatives 正确 → reviewStatus archived
- [ ] **感受 → 第二大脑 端到端**：感受卡片右滑现在有 [→ 第二大脑] 按钮（PR 4 后这条是死的，PR 5 解锁）
- [ ] 详情页"+ 关联卡片"：A 详情页 + 关联 B → 双向：A.links=[B.id] B.links=[A.id]，B 详情页"反向链接"显示 A
- [ ] topics 模糊补全：输入"命"时弹出已有 #命名 候选
- [ ] 编辑卡片：详情页右上角"编辑"弹 sheet，title/content/topics 可改，保存后详情页刷新
- [ ] 删除卡片：编辑 sheet 内"删除"按钮 → 卡片消失 → 其他卡片 links 里该 id 自动清掉（PR 3 `removeBrain` 已实现）
- [ ] 单测：`store.addBrain` / `linkBrainCards` / `backlinks` / `removeBrain` 已在 PR 3 测过，PR 5 不需要新增 store 测试，View 层不强测

### 估算工程量

**8-10 个 evening session（约 12-15 小时）** —— V1 里最大的一关。可拆分多个 commit：

1. `BrainCard` 数据展示（卡片墙 + 详情页只读）
2. 编辑器 + topics chip 输入器
3. 关联卡片 picker + 反向链接显示
4. Review 模式右滑加 [→ 第二大脑]
5. Hub 第二大脑卡片激活

最后一起 squash merge。

### 不在 PR 5 范围（仍归 V2 / V3）

- 第二大脑直接录入入口（FAB / 全局 AI 输入框联动）
- Markdown 渲染
- 视觉气质明显区分（衬线字体 / 加深色调）
- 反向链接显示 context 片段（V1 反链只显示对方卡片 title）
- 关联图谱可视化
- 被动建链建议
- 自我觉察档案 / DBT 行为链分析

---

## 不在 V1 范围（V2/V3 延后）

- 自我觉察档案 + DBT 行为链分析
- 复盘 Tab 阅读型统计可视化（日时间饼图 / 心情时间线 / AI 一句温柔总结）
- 第二大脑直接录入入口（FAB / 全局 AI 输入框联动）
- 关联图谱可视化
- 第二大脑 Markdown 渲染 / 视觉气质明显区分
- 被动建链建议
- 感恩 / 做梦的回顾性视图
- AI 摘要、AI 一句温柔总结

---

## 接手指南（如果 Claude 掉线 / 换人继续）

按以下顺序读，5 分钟可上手：

1. 读这份 `IN_PROGRESS.md`（你正在看）
2. 读 [`CLAUDE.md`](CLAUDE.md) 工作规范 + ADHD 硬约束
3. 读 [`CONTRIBUTING.md`](CONTRIBUTING.md) 分支 / commit 规范
4. 读 [`LAUNCH_CHECKLIST.md`](LAUNCH_CHECKLIST.md) §4.8（审核期间开发策略）
5. 看上方 PR 进度表 → 找到下一个 ⏳ 状态的 PR
6. 看上方"锁定决策清单"对应该 PR 的部分
7. 跑 `git log main..origin/main --oneline` 确认本地是最新
8. 从最新 main 拉新分支 `git checkout -b <type>/<branch-name>`
9. 写代码 → 测试 → 让 Anna review → squash merge

**关键提醒**：

- 不要在 main 上 bump 版本号（V1 全部合完前别动 `project.yml` 的 MARKETING / BUILD）
- 改完代码必须提醒 Anna commit（不要自己 commit）
- 任何"是否扩大本 PR 范围"的犹豫 → 停下来问 Anna
- 想动"锁定决策清单"任何一条 → 停下来问 Anna
- 这份 IN_PROGRESS.md 每次 PR 合并后**手动更新进度表**（无自动化）

---

## V1 上线后这份文档怎么处理

V1 全部 PR 合完 + 1.2.0 上架后：

1. 把当前内容复制到 `docs/archived-features/v1-inspiration-reflection.md`
2. 清空本文件（或换成下一个在飞功能的内容）
3. [`CHANGELOG.md`](CHANGELOG.md) 加 1.2.0 段落，归纳 V1 给用户看的变化
