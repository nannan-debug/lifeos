# 协作指南

欢迎加入 LifeOS 开发！这份文档写清楚"怎么一起干活不踩脚"。

---

## 分支模型：简化 GitHub Flow

因为是小团队（<5 人），用最轻的 GitHub Flow，不搞 GitFlow 那套复杂的 release / develop 分支。

```
main              ← 随时可发布的稳定状态，只接受 PR 合入，不允许直接 push
 │
 ├─ feat/xxx      ← 新功能分支
 ├─ fix/xxx       ← bug 修复分支
 ├─ style/xxx     ← 视觉/样式调整
 └─ docs/xxx      ← 文档
```

### 标准工作流

```bash
# 1. 从最新 main 拉分支
git checkout main
git pull
git checkout -b feat/gratitude-merge

# 2. 开发 + 多次小 commit
git add .
git commit -m "feat: merge multiple gratitude records locally"

# 3. 推远程
git push -u origin feat/gratitude-merge

# 4. 开 PR，指派一位 reviewer
gh pr create --title "feat: 感恩多事件合并为一条" --body "..."

# 5. 通过 review 后，Squash Merge 到 main
# 6. 删除分支
```

### main 分支保护

建议在 GitHub 仓库 Settings → Branches 开启：
- [x] Require a pull request before merging
- [x] Require approvals (至少 1 人)
- [ ] Require status checks (暂无 CI，先不开)
- [x] Do not allow bypassing the above settings

---

## Commit Message 规范：Conventional Commits

### 格式

```
<type>: <简短描述>

[可选详细说明]
```

### type 列表

| type | 用途 | 例子 |
|---|---|---|
| `feat` | 新功能 | `feat: 新增日复盘模块` |
| `fix` | bug 修复 | `fix: 键盘弹起时 FAB 不再盖 tabbar` |
| `style` | 纯视觉调整（不影响逻辑） | `style: 随记卡片改为圆角 14` |
| `refactor` | 重构（不改外在行为） | `refactor: AppStore 拆分为多个扩展` |
| `docs` | 文档 | `docs: 更新 README 本地运行步骤` |
| `chore` | 杂项（配置、依赖、构建） | `chore: 升级 Swift 到 5.10` |
| `test` | 测试相关 | `test: 为 AIParser 增加单元测试` |
| `perf` | 性能优化 | `perf: 减少列表滚动时的视图重建` |

### 写好 commit message 的小原则

- ✅ **描述做了什么，不解释为什么**（为什么放到 PR description）
- ✅ **用祈使句**："add", "fix", "update"（不是 "added"）
- ✅ **一个 commit 一件事**：别把无关改动塞一起
- ✅ **中文英文都行**，团队内保持一致即可（本项目用中文）

---

## Code Review 几条

reviewer 看 PR 时重点关注：

1. **没有硬编码的 secret / API key** —— 真出现了 reject 并要求改外挂
2. **UI 改动要配截图 / 录屏** —— SwiftUI 很多东西肉眼看才能判断
3. **ADHD 友好原则没被破坏** —— 参考 `PRODUCT_BRIEF.md` 第九章硬约束
4. **新页面有空状态** —— 别让用户看到冷冰冰的白屏

---

## 发版流程（打 tag 触发）

见 [`VERSIONING.md`](./VERSIONING.md)。

---

## 遇到问题

- 技术问题：直接开 Issue，打 `question` 或 `bug` label
- 产品决策：先和 Anna 对齐再动
- 紧急线上问题：Telegram / 微信直接戳

Happy hacking 🐱
