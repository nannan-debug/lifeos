# 迭代 & 发版流程

> 这份文档同时给人和 AI 协作者读。
> AI 协作者：识别到下面"触发场景"时，**主动按对应章节引导用户**，每一步都先确认再动手；不要默默替用户做 commit / tag / 上传这些有副作用的操作。

---

## 触发场景速查（AI 用）

| 用户意图（关键词） | 走哪一节 |
|---|---|
| "做新功能 / 改 bug / 调样式" | §1 日常迭代 |
| "改完了 / 这版差不多了 / 帮我提交" | §1 第 5–7 步 |
| "发新版 / 提审 / 上架更新 / 1.0.x / 1.1.0" | §2 发版流程 |
| "本地跑不起来 / 签名报错 / ASC 报错" | §3 常见坑 |
| "团队选哪个 / DEVELOPMENT_TEAM" | §3.2 |
| "build 不能上传 / build 重复" | §3.3 |

> AI 在不确定时永远先问一句"你想发版本号是 X.Y.Z 吗"再操作，不要替用户决定语义化版本。

---

## §0 当前发布坐标（每次发版后由人手动更新这一节）

| 项 | 值 |
|---|---|
| Bundle ID | `ai.anna.personalsystem` |
| Development Team | `355RQ5S3DW`（Xcode 下拉里显示为 `nannan guo`，**不是** Personal Team）|
| 最近一次上传 | `1.0.0 (build 1)` · 2026-04-26 · 已提交审核 |
| 下一次发版预期 | `1.0.1`（bug fix）或 `1.1.0`（新功能） |

> AI：每次帮用户走完 §2，提醒用户更新本节。

---

## §1 日常迭代

每次开始改代码前严格按这个顺序，AI 看到用户上来就直接改文件应**先停下来确认是否在分支上**。

### 1. 同步 main
```bash
cd /Users/newblue/Projects/openclaw-project/lobster-team/ios-app
git checkout main && git pull
```

### 2. 起分支（命名见 [CONTRIBUTING.md](CONTRIBUTING.md)）
```bash
git checkout -b feat/<功能名>     # 新功能
git checkout -b fix/<bug 描述>    # bug 修复
git checkout -b style/<改动>      # 视觉调整
```

### 3. 改代码
- 守 [CLAUDE.md](CLAUDE.md) 里的 **ADHD 友好原则**（绝对禁止 / 必须保证）
- 不手编 `.xcodeproj`：改 `project.yml` 后跑 `xcodegen`
- `Secrets.swift` 永远不入库

### 4. 本地验证
- Xcode 跑模拟器 + 至少一台真机
- `Cmd+U` 跑测试
- 涉及 UI 改动留截图/录屏（PR 时贴上）

### 5. 小步 commit
```bash
git add Sources/...
git commit -m "feat: 简短描述"   # 用 Conventional Commits，见 CLAUDE.md
```
- **AI：每次写完代码必须主动提醒"要不要 commit？"**——否则改动会像 2026-04-28 那次一样丢失（无 stash 无 reflog）

### 6. 推 + 开 PR
```bash
git push -u origin <分支名>
gh pr create --fill
```

### 7. Squash Merge → 删分支 → 同步 main
```bash
git checkout main && git pull
git branch -d <分支名>
```

> 走完 §1 不等于发版。发版要再走 §2。

---

## §2 发版流程（已上架后发新版本）

> 前置：要发布的所有功能/修复都已经 merge 进 main，main 干净。

### 2.1 决定版本号（参考 [VERSIONING.md](VERSIONING.md)）

- `1.0.x` — 仅 bug 修复
- `1.x.0` — 新功能（向下兼容）
- `x.0.0` — 大改版 / 数据迁移 / 去功能

> AI：用户说"发新版"时**主动确认版本号语义**，别擅自决定。

### 2.2 改版本号（**Info.plist 和 pbxproj 两处都要改**）

[Sources/App/Info.plist](Sources/App/Info.plist)：
```xml
<key>CFBundleShortVersionString</key>
<string>1.0.1</string>     <!-- Marketing -->
<key>CFBundleVersion</key>
<string>2</string>         <!-- Build：必须比上次大，永不回退永不重复 -->
```

更稳的做法：改 [project.yml](project.yml) 里的 `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`，然后：
```bash
xcodegen
```

如果直接改 [PersonalSystem.xcodeproj/project.pbxproj](PersonalSystem.xcodeproj/project.pbxproj)，搜两处 `MARKETING_VERSION` 和两处 `CURRENT_PROJECT_VERSION` 全部一致更新。

### 2.3 commit + tag + push

```bash
git add -A
git commit -m "release: v1.0.1 · <一句话说明>"
git tag -a v1.0.1 -m "1.0.1 · <发版说明>"
git push origin main
git push origin v1.0.1
```

### 2.4 Xcode Archive

1. Xcode 顶部 device 选 **Any iOS Device (arm64)**（不是模拟器，否则 Archive 灰）
2. 菜单 **Product → Archive**
3. 等几分钟，Organizer 自动弹出

> 如果 Archive 里 Team 提示 Personal Team 或报 "Failed Registering Bundle Identifier"：见 §3.2

### 2.5 上传到 App Store Connect

Organizer 选这次 archive：
1. **Distribute App**
2. **App Store Connect** → **Upload**
3. 全部默认（Automatic signing / Upload symbols / Manage version automatically）
4. 等到 "Upload Successful"

### 2.6 在 App Store Connect 提交新版本审核

https://appstoreconnect.apple.com → LifeOS → **Distribution**：

1. 左侧 **iOS App** → **+ Version or Platform** → 填 `1.0.1`
2. **Build** 区点 + → 选刚上传的 build（要等 5–15 分钟 "Processing" 完才出现，不出现就刷新）
3. **What's New in This Version**：写用户可见的更新说明（中文，2–4 行）
4. 截图 / 关键词 / 隐私问卷：1.0.0 没改过功能就直接复用；改了数据收集要更新隐私问卷
5. 右上 **Add for Review** → **Submit to App Review**

> 仅 bug fix 通常审核 < 1 天。
> 只想 TestFlight 内测不上架：跳过 2.6，让 Internal Testing 组直接装。

### 2.7 收尾

- [ ] 在 GitHub 发 Release（可选）：`gh release create v1.0.1 --title "v1.0.1" --notes "..."`
- [ ] 更新本文件 §0 的"最近一次上传"
- [ ] 审核通过后 push notification / 朋友圈通知用户（可选）

---

## §3 常见坑

### 3.1 build 上传后跑本地报 "Failed Registering Bundle Identifier"
原因：`DEVELOPMENT_TEAM` 被改成了 Personal Team。
修复：恢复成 `355RQ5S3DW`：
```bash
git diff PersonalSystem.xcodeproj/project.pbxproj | grep DEVELOPMENT_TEAM
# 如果显示被改，跑：
git restore PersonalSystem.xcodeproj/project.pbxproj
```

### 3.2 Xcode Team 下拉选哪个
- ✅ **`nannan guo`** = team `355RQ5S3DW` = 付费 Apple Developer 账号 = 上架用的那个
- ❌ `nan guo (Personal Team)` = team `QS37YQF7H5` = 免费 Personal Team，**不能**用同一个 bundle id

### 3.3 ASC 拒绝上传 / 报 build number 重复
原因：Apple 要求 build 单调递增，永不重复。
修复：把 `CFBundleVersion` 改成迄今所有上传过的 build 中**最大值 + 1**（保险起见）。

### 3.4 archive 里没显示我的 app / 灰着
原因：device 选了模拟器。
修复：顶部改成 **Any iOS Device (arm64)**。

### 3.5 改了 project.yml 但 Xcode 没生效
原因：忘了重新生成。
修复：
```bash
xcodegen
```
然后 Xcode 会提示重新加载 project，点 Revert / Reload。

### 3.6 改动丢失（如 2026-04-28 那次）
原因：working tree 改动没 commit，被外部工具 / IDE 的 discard 操作清掉，git 无 stash 无 reflog 可救。
预防：**改完代码就 commit，哪怕 WIP**：
```bash
git add -A && git commit -m "wip: 占位"
```
正式 PR 前可以 `git rebase -i` 整理。

---

## §4 AI 协作者的硬规则

1. **改完代码先提醒 commit**——除非用户明确说"先不 commit"
2. **不替用户决定语义化版本号**——总是先问"是 1.0.x 还是 1.1.0？"
3. **不替用户跑 archive / upload / submit**——这些是有外部副作用的操作，总是让用户在 Xcode/ASC 里手动点
4. **不动 `Secrets.swift` 不动 `.env`**——任何与凭证/密钥相关的改动一律先停下来确认
5. **遇到签名问题先看 §3.1–3.2**——99% 是 team 被改了
6. **每次走完 §2，提醒用户更新本文件 §0**
