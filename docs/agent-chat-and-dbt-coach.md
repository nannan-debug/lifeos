# Agent Chat + DBT Coach Behavior

> 目的：固定 AI 对话窗、多会话历史和 DBT Coach 的当前产品契约。代码、Worker prompt、trace 排查和回归测试都应向本文档对齐。
>
> 最近更新：2026-06-03

---

## 1. 对话历史管理

### 用户行为

- AI 面板顶部历史入口打开历史抽屉。
- 历史抽屉支持搜索、切换、新建对话。
- 历史条目长按打开系统 context menu：
  - `重命名`：弹出标题输入框，只修改历史列表显示名称。
  - `删除`：走现有删除确认；删除后仍支持撤销。
- 列表平时不常驻显示删除按钮，避免误触和视觉噪音。

### 存储规则

- 会话正文保存在 `Application Support/agent-threads/<userId>/<threadId>.json`。
- 线程索引保存在 `UserDefaults`，对应 `AgentChatThreadIndexItem`。
- 手动重命名只更新 `AgentChatThread.title` 和索引项，不修改消息正文。
- 手动重命名会设置 `titleGenerated = true`，防止后续 AI 自动标题覆盖用户改名。
- 重命名不改变 `updatedAt`，避免旧对话因为改名突然跳到列表顶部。

### 关键文件

- `Sources/Views/GlobalAIInputBar.swift`
  - 历史 row context menu。
  - 重命名 alert。
  - 删除确认 alert。
- `Sources/ViewModels/AppStore.swift`
  - `renameAgentThread(id:title:)` 转发到 `AgentManager`。
- `Sources/Services/AgentManager.swift`
  - `renameThread(id:title:)` 持久化标题与索引。
- `Sources/Localization/L.swift`
  - 对话重命名相关中英文文案。

### 回归样本

1. 打开 AI 对话历史。
2. 长按任意历史条目。
3. 预期：出现 `重命名` 和红色 `删除`。
4. 点击 `重命名`，输入 `面试焦虑复盘` 并保存。
5. 预期：历史列表标题立即更新；重新打开 App 后仍保留该标题。
6. 继续和该对话聊天。
7. 预期：AI 自动标题不会覆盖 `面试焦虑复盘`。

---

## 2. DBT Coach 的边界

DBT Coach 是 LifeOS 的结构化自我关怀练习，不是医疗诊断或治疗。

- 普通 chat 模式只负责识别时机并征求同意。
- 用户未同意前，普通 chat 不直接开始 DBT 步骤。
- 用户同意后，App 进入 `dbtCoach` 模式，由 DBT Coach 引导练习。
- DBT Coach 每轮只推进一个小步骤。
- 未完成练习时不生成 `actionSuggestions`。
- 完成练习时可生成 `brain` actionSuggestion，保存为 DBT 练习记录。

---

## 3. DBT 路由与确定性 handoff

### 为什么不能只靠模型

“可以的 / 好的 / 试一下 / 使用了”这类短确认很容易被模型当成普通聊天。如果完全依赖 Worker 返回 `toolCall: startDBTSession`，会出现用户同意后只回复“DBT Coach 已经准备好了”，但没有真正开始第 1 步的问题。

### 当前规则

App 端在 `AgentManager.send(...)` 的最前面做确定性判断：

- 当前没有 active DBT session。
- 上一轮 assistant 明确提到 `DBT` 或 `Coach`。
- 上一轮 assistant 的语义是在邀请切换 / 试练习 / 做练习。
- 当前用户输入是确认词，如：
  - 中文：`可以`、`可以的`、`好的`、`试试`、`试一下`、`开始`、`使用`、`切过去`
  - 英文：`ok`、`okay`、`yes`、`sure`、`go ahead`、`let's try`

满足以上条件时，App 不再等模型发 toolCall，而是直接：

1. 把用户确认消息写入当前 thread。
2. 调用 `startDBTSession(skillId:)` 创建 active session。
3. 用 `agentMode = "dbtCoach"` 发起第二次请求。
4. 要求 DBT Coach 直接开始第 1 步。

### 技能选择

如果上一轮 assistant 已经建议了具体技能，App 会从文本里推断：

- `Check the Facts` / `事实` → `check_the_facts`
- `Opposite Action` / `相反行动` / `反向行动` → `opposite_action`
- `Wise Mind` / `智慧心` → `wise_mind`
- `TIPP` → `tipp`
- `STOP` / `暂停` → `stop`
- `DEAR MAN` / `人际` → `dear_man`
- `行为链` / `复盘` → `behavior_chain_analysis`

无法判断时默认 `validation`。

### 首步兜底

如果 DBT Coach 首次响应没有 `followUpQuestion`，且回复里也没有问号，App 会用 `ensureDBTStarterResponse(...)` 本地补一个第一步问题，避免停在“准备好了”。

兜底问题按技能区分：

- `validation`：最明显的感受是什么？身体哪里最强？
- `check_the_facts`：确定发生了什么？先只写事实。
- `opposite_action`：情绪最想推你做什么动作？
- `wise_mind`：理性脑和情绪脑各怎么说？
- `tipp`：情绪强度 0-10 是几分？身体哪里明显？
- `stop`：此刻最想立刻做的冲动是什么？
- `dear_man`：想对谁表达什么请求或边界？
- `behavior_chain_analysis`：问题行为是什么？发生前 5 分钟有什么触发？

---

## 4. DBT session 进度

### 数据结构

`AgentDBTSessionState` 是 App 与 Worker 之间的练习状态契约：

- `status`: `active` / `completed` / `cancelled`
- `skillId`: 当前技能
- `currentStepIndex`: 当前步骤，从 0 开始
- `stepAnswers`: 用户每一步的真实回答
- `summary`: 完成后的真实练习摘要
- `skillIds`: 本次涉及的技能列表
- `followUpActions`: 用户明确说出的后续行动

### 进度规则

- 用户回答某一步后，Worker 必须把该回答写入 `stepAnswers`。
- 每轮最多推进一步。
- `currentStepIndex` 必须指向下一步要问的问题。
- App 收到 `dbtSession` 后用 `applyDBTSessionUpdate(...)` 覆盖本地 session。
- Worker 端会用 `reconcileDBTSessionProgress(...)` 做兜底，防止一直卡在第 1 步。

---

## 5. Trace 排查

DBT 相关 trace 事件：

- `dbt_handoff_started`
  - 模型返回 `toolCall: startDBTSession` 后进入 DBT。
- `dbt_handoff_confirmed_locally`
  - App 识别用户确认词后，本地确定性进入 DBT。
- `dbt_response_merged`
  - DBT Coach 回复和 `dbtSession` 已合并进当前 thread。
- `dbt_handoff_failed_with_local_fallback`
  - DBT Coach 请求失败，App 使用本地第 1 步问题兜底。

排查时优先看：

1. `mode` 是否从 `chat` 切到 `dbtCoach`。
2. `dbtSession.status` 是否为 `active`。
3. `currentStepIndex` 是否随用户回答推进。
4. `stepAnswers` 是否记录真实用户回答。
5. 首次进入 DBT 后是否有具体问题，而不是只说“准备好了”。

---

## 6. 回归测试

### Case A：普通建议后确认切 DBT

用户：

```text
有点空 说不上来，好像没什么
```

预期普通 chat：

- 接住用户感受。
- 可以建议切 DBT Coach。
- 不直接开始步骤。

用户：

```text
可以的
```

预期：

- App 进入 `dbtCoach` 模式。
- 当前标题区域显示 DBT Coach 状态。
- assistant 不停在“准备好了”。
- assistant 主动问第 1 步，例如：

```text
先只说一个点：此刻最明显的感受是什么？它在身体哪里最强？
```

### Case B：Check the Facts 技能

上一轮 assistant 建议：

```text
要不要切到 DBT Coach 做一个 Check the Facts 小练习？
```

用户：

```text
好
```

预期：

- `skillId = check_the_facts`。
- 首步问题聚焦事实：

```text
我们先只看事实：刚才这件事里，确定发生了什么？
```

### Case C：防误触

普通聊天中 assistant 没提 DBT，用户只说：

```text
可以
```

预期：

- 不进入 DBT Coach。
- 按普通 chat 处理。

### Case D：进度推进

进入 DBT 后，用户回答第一步：

```text
最明显的是空和无力，胸口有点闷。
```

预期：

- `stepAnswers` 新增第 1 步回答。
- `currentStepIndex` 推进到下一步。
- assistant 问下一步问题。
