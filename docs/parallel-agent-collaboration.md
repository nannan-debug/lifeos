# 多 Agent 并行协作 SOP

> 目的：当用户同时让 Claude Code、Codex 或其它 agent 开发 LifeOS 时，用这份 SOP 降低分支冲突、状态漂移和发版误操作。

## 适用场景

- 一个 agent 已在当前工作区开发，且存在未提交改动。
- 另一个 agent 需要同步处理其它模块、bug、文档或发版准备。
- 多个 PR 会在同一候选版本中进入 `main`。

## 标准流程

1. 先读 `CLAUDE.md`、`AGENTS.md`、`CONTRIBUTING.md`、`VERSIONING.md`、`LAUNCH_CHECKLIST.md`、`CHANGELOG.md`、`IN_PROGRESS.md`。
2. 用 `git status --short --branch` 确认当前分支和未提交改动。
3. 如果当前工作区已有另一个 agent 的改动，不在原工作区切分支，也不覆盖、stash、revert 对方改动。
4. 从最新 `origin/main` 创建独立 worktree 和独立分支：

   ```bash
   git fetch origin
   git worktree add /private/tmp/ios-app-lifeos-<topic> -b fix/<topic> origin/main
   ```

5. 先诊断问题边界，再决定是否实现。跨模块 bug 尤其要先找触发点、数据流和共享文件。
6. 明确文件所有权：
   - Agent / AI / Worker / Trace 方向默认归 Agent 分支处理。
   - 非 Agent 的 UI、HealthKit、Widget、设置、导出等方向可由独立分支处理。
   - `Sources/ViewModels/AppStore.swift`、`Sources/Models/Models.swift` 是共享高冲突文件，动之前先说明原因和影响范围。
7. 每个方向独立 PR 到 `main`。不建议把多个 agent 的改动先合进一个“大集成分支”。
8. 谁后合并，谁负责基于最新 `main` 解决冲突并重新跑相关验证。
9. 用户可见变化写入 `CHANGELOG.md` 的 `[Unreleased]`；发版状态变化写入 `LAUNCH_CHECKLIST.md`；跨多个 PR 的大功能写入 `IN_PROGRESS.md`。

## 冲突处理原则

- 不直接 push `main`，除非用户明确要求并且最终回复说明绕过了 PR 规则。
- 不改对方未提交文件；如果必须碰同一个核心文件，优先缩小 diff，并在最终回复里点名。
- 不提前改版本号、Archive、Submit Review、打 tag 或发 GitHub Release。
- 发版相关动作必须区分：
  - 代码已合并：PR 已进入 `main`。
  - 已提交审核：App Store Connect 已 Submit to App Review。
  - 已上架：ASC 显示 Ready for Distribution / 已 release，之后才打 tag 和 GitHub Release。

## 推荐分支命名

- Agent 功能：`feat/agent-xxx`
- 普通修复：`fix/<module>-<issue>`
- 视觉调整：`style/<screen>-<change>`
- 文档 / SOP：`docs/<topic>`
- Codex 临时隔离 worktree 可放在 `/private/tmp/ios-app-lifeos-<topic>`，最终仍通过正常 git 分支和 PR 交付。

## PR 合并顺序建议

1. 文档或低风险内部改动先合。
2. 共享模型 / AppStore 改动尽量后合，并在合前同步最新 `main`。
3. UI 与服务逻辑可独立合，但如果都依赖同一数据结构，先合数据结构 PR。
4. 发版 PR 最后做，只包含版本号、`xcodegen` 同步、CHANGELOG 归档和必要状态文档。
