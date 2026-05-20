# AGENTS.md — LifeOS iOS

> 给 OpenAI Codex 及其他读取 `AGENTS.md` 的编码 agent 使用。
>
> **本项目的工作规范统一维护在 [`CLAUDE.md`](./CLAUDE.md)。请先完整阅读那份文件，再开始任何任务。**
>
> 之所以拆成两份文件，只是为了兼容不同 agent 的默认文件名约定（Claude Code 读 `CLAUDE.md`，Codex 读 `AGENTS.md`）。规范本身不在这里复制，避免双份维护漂移。

## 同步阅读清单

`CLAUDE.md` 之外，开始任务前还应熟悉：

- [`CONTRIBUTING.md`](./CONTRIBUTING.md) — 分支命名 / commit 规范 / PR 流程
- [`VERSIONING.md`](./VERSIONING.md) — 版本号约定（注意：`project.yml` 是 source of truth，不是 `Info.plist`）
- [`LAUNCH_CHECKLIST.md`](./LAUNCH_CHECKLIST.md) — 当前上架状态 + 发版 SOP（重点看 §4.8 审核期间开发策略）

## Codex 协作口径

用户主要使用 Codex 参与本项目开发。除非用户明确要求只回答问题，否则 Codex 在完成一次代码或文档改动后，最终回复应使用中文，并主动交代：

1. 已经完成了什么，必要时列出关键文件或 commit。
2. 用户接下来需要如何验收或配合，例如看截图、跑 App、确认文案、决定是否 push / 开 PR。
3. 如果验收通过，Codex 下一步打算做什么。
4. 最后用一句明确问题询问用户现在是否要继续执行下一步；避免反复使用"你同意吗"这种泛问法。

Codex 还应主动识别需要沉淀的关键点，不等用户提醒：

- 审核期间合入 `main`、准备进入下个版本的用户可见改动，写进 [`CHANGELOG.md`](./CHANGELOG.md) 的 `[Unreleased]`。
- 当前审核状态、发版风险、必须人工处理的 Apple Developer / App Store Connect 步骤，更新到 [`LAUNCH_CHECKLIST.md`](./LAUNCH_CHECKLIST.md)。
- 跨多个 PR 的大功能进度，更新 [`IN_PROGRESS.md`](./IN_PROGRESS.md)；单 PR 小改动不强行写入。

示例口径：

> 这次我完成了 X，并已通过 Y 验证。你接下来需要检查 A / B；如果你确认没问题，我下一步会 push 分支并开 PR。现在要我继续做这一步吗？

内部整理类改动（CI、重构、纯文档等）不必强行写入 changelog；commit 历史和 PR 描述能说明即可。

## 发版 / PR 协作补充

当 Codex 帮用户准备发版 PR 或跨多项改动的 PR 时，除了正常代码与测试，还必须主动给出三份可直接使用的文本：

1. **PR description**：说明改了什么、为什么、影响范围、验证方式、仍需用户手动处理的事项。
2. **Squash merge title/body**：供 GitHub 合并页使用；body 至少写 1-3 句，不要只剩 `Co-authored-by`。
3. **App Store What's New**：如果本次 PR 对应上架版本，给一版用户可读的更新说明。

发版沟通里必须明确区分三个状态：

- **代码已合并**：PR 已进 `main`，但还没提交 Apple 审核。
- **已提交审核**：App Store Connect 已 Submit to App Review，等待 Apple 结果。
- **已上架**：ASC 显示 Ready for Distribution / 已 release，此时才打 tag 和 GitHub Release。

除非用户明确要求，Codex 不应直接 push `main`。即使是纯文档状态更新，也优先走小 PR；如果确实需要直推，最终回复必须点明这次绕过了 PR 规则。
