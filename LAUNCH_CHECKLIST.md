# LifeOS · 上架真实进度清单

> 目的：给新的 AI / 协作者一个能立即接手的真实状态，而不是历史计划。
> 最后更新：2026-06-12

---

## 0. 当前结论

**LifeOS 1.13.0 (build 17) 已通过审核并上架 App Store。**

- ✅ `1.0.0 (build 1)` — App Store 首发（2026-04）
- ✅ `1.1.0 (build 3)` — 2026-04-30 上架
- ✅ `1.2.0 (build 4)` — 2026-05-02 上架
- ✅ `1.3.0 (build 5)` — 2026-05-03 上架
- ✅ `1.4.0 (build 6)` — 2026-05-04 上架
- ✅ `1.5.0 (build 7)` — 2026-05-07 上架
- ✅ `1.5.1 (build 8)` — 2026-05-11 上架
- ✅ `1.5.2 (build 9)` — 2026-05-13 上架
- ✅ `1.6.0 (build 10)` — 2026-05-15 上架
- ✅ `1.7.0 (build 11)` — 2026-05-20 上架
- ✅ `1.8.0 (build 12)` — 2026-05-21 上架
- ✅ `1.11.0 (build 15)` — 2026-05-26 上架（中英文双语支持 + AI 语言匹配）
- ✅ `1.12.0 (build 16)` — 2026-06-04 上架（DBT 修复 + Agent 体验优化）
- ✅ `1.13.0 (build 17)` — 2026-06-14 上架（猫猫首次问卷、人设设置、分层记忆与情绪梳理体验优化）
- ✅ App ID：`6763877227`
- ✅ App Store Connect 状态：1.0.0 ~ 1.13.0 均 Ready for Distribution

**注：1.9.0 (build 13) 和 1.10.0 (build 14) 已合入 main 但未单独发版上架，功能随 1.11.0 一起发布。**

---

## 1. 项目基本信息

| 项目 | 值 |
|---|---|
| 产品名 | **LifeOS** |
| App Store 显示名 | `LifeOS` |
| Bundle ID | `ai.anna.personalsystem` |
| iOS 最低支持 | iOS 17.0 |
| Swift 版本 | 5.9 |
| Xcode project | XcodeGen 生成（源头是 `project.yml`） |
| 主语言 | 简体中文（zh-Hans），应用内支持中英文切换 |
| 目标区域 | 除中国大陆外全球区 |
| 定价 | 免费，无内购 |
| 已上架营销版本 | `1.13.0` (build 17) |
| 当前 main 状态 | `1.13.0 (build 17)` 已上架 App Store |
| Development Team | `355RQ5S3DW` |

关键路径：

```text
/Users/newblue/Projects/ios-app-lifeos/
├── project.yml
├── PersonalSystem.xcodeproj
├── Sources/
├── PRIVACY_POLICY.md
├── docs/operations/appstore/ASC_COPY_DRAFT_v1.md
├── docs/operations/appstore/ASC_SCREENSHOT_PLAN.md
├── docs/                     # GitHub Pages 页面（Support / Privacy）
└── LAUNCH_CHECKLIST.md
```

---

## 2. 已完成 ✅

### 2.1 代码 / 产品

- ✅ 4 个主 Tab 已完成：今日 / 时间 / 随记 / 设置
- ✅ 全局 AI 输入框已完成：FAB、展开态、mascot、首次同意弹窗
- ✅ AI 后端为 `ai.dogdada.com`，实际解析方文案已统一为 **DeepSeek**
- ✅ 打卡项按 tag 分组与折叠展开
- ✅ 本地数据按 `auth.userId` 分隔存储
- ✅ App 名已设为 `LifeOS`
- ✅ App Icon 已配置
- ✅ Launch Screen 已配置
- ✅ `Info.plist` 版本号已设为 `1.0.0 (1)`
- ✅ `PrivacyInfo.xcprivacy` 已存在
- ⏸️ CSV 导出 / 导入入口已暂时下线，后续若恢复需保证覆盖范围与说明一致

### 2.2 开发者账号 / 签名

- ✅ Apple Developer 个人账号已注册并付费生效
- ✅ 已脱离前公司 Team
- ✅ `project.yml` 已写入 `DEVELOPMENT_TEAM = 355RQ5S3DW`
- ✅ `.xcodeproj` 当前也同步到了同一个 Team ID

### 2.3 合规 / 文案材料

- ✅ 中文隐私政策草稿已填入真实开发者名和邮箱：`PRIVACY_POLICY.md`
- ✅ AI 首次同意流程已落地：`ai.consent.v1`
- ✅ App Store Connect 文案草稿已整理：`docs/operations/appstore/ASC_COPY_DRAFT_v1.md`
- ✅ App Store 截图执行方案已整理：`docs/operations/appstore/ASC_SCREENSHOT_PLAN.md`
- ✅ App Review Notes 英文草稿已准备

### 2.4 支持页面

- ✅ 已在仓库内准备 GitHub Pages 用的静态页面：
  - `docs/index.html` → Support URL
  - `docs/privacy.html` → Privacy Policy URL

---

## 3. 首发已完成的事项 ✅（历史归档）

下面这些都是 1.0.0 首发前后必须做、现在已经完成的事，留作记录：

- ✅ App Store Connect 创建 `LifeOS` 的 App 记录
- ✅ Bundle ID `ai.anna.personalsystem` 在 Apple Developer Portal 注册
- ✅ 成功 Archive + 上传 build
- ✅ 通过 TestFlight 测试
- ✅ App Privacy 问卷填写保存
- ✅ Age Rating 填写
- ✅ Pricing & Availability 设置（已排除 China mainland）
- ✅ 5 张 6.7" 截图生成并上传
- ✅ ASC metadata 文案填写（按 [ASC_COPY_DRAFT_v1.md](docs/operations/appstore/ASC_COPY_DRAFT_v1.md)）
- ✅ Support URL / Privacy Policy URL 公开链接落地
- ✅ 首次审核通过、上架

---

## 4. 后续版本更新流程（每次发版的标准 SOP）

每次发新版本走这 6 步，不用再走 §3 那些一次性配置。

### 4.1 在 feature 分支做完代码改动并 PR 合到 main

```bash
git checkout main && git pull
git checkout -b feat/xxx
# ...写代码...
git push -u origin feat/xxx
gh pr create --title "feat: ..." --body "..."
# review 通过后 squash merge
```

发版 PR 前额外检查：

- 先 `git fetch origin`，确认本地 `main` 已包含远端最新状态文档，尤其是 `IN_PROGRESS.md` / `LAUNCH_CHECKLIST.md`，避免发版分支和状态更新 PR 冲突。
- 发版 PR 只做版本号、`xcodegen` 同步、`CHANGELOG` 归档、必要的发版状态文档；不要顺手塞未确认的新功能。
- PR description 里必须写清楚：版本号 / build、包含哪些用户可见改动、验证命令、Apple Developer / ASC 里仍需人工处理的事项。
- 开 PR 后，同时准备 GitHub squash merge 的 title/body；body 至少写 1-3 句，避免 merge commit 只剩一行标题和 `Co-authored-by`。

### 4.2 改 `project.yml` 的版本号（不是 Info.plist！）

> ⚠️ **真正的 source of truth 是 `project.yml`**。`xcodegen` 每次都会用 `project.yml` 重新生成 `Info.plist` 和 `pbxproj`——直接改 `Info.plist` 会被覆盖回去。详见 [VERSIONING.md](VERSIONING.md)。

`project.yml` 里**两段**版本号都要改（共 4 个字段）：

```yaml
targets:
  PersonalSystem:
    info:
      properties:
        CFBundleShortVersionString: 1.2.0   # ← Marketing version（feat = MINOR bump，bugfix = PATCH bump）
        CFBundleVersion: "3"                # ← Build number（永远 +1，绝不能跟历史 build 重复）
        ITSAppUsesNonExemptEncryption: false  # 已固化，别动（出口合规豁免）
        # ...
    settings:
      base:
        MARKETING_VERSION: 1.2.0            # ← 同 Marketing
        CURRENT_PROJECT_VERSION: 3          # ← 同 Build
```

改完跑 xcodegen 同步，并做一个 PR 合并：

```bash
git checkout -b chore/bump-version-1.2.0
# 编辑 project.yml ...
xcodegen
grep -A1 "CFBundleVersion" Sources/App/Info.plist  # 必须看到新版本号
git add project.yml PersonalSystem.xcodeproj/project.pbxproj
git commit -m "chore: bump version to 1.2.0 / build 4"
git push -u origin chore/bump-version-1.2.0
gh pr create --title "chore: bump 1.2.0 / build 4" --body "..."
# squash merge 后回到 main && pull
```

### 4.3 Archive + 上传到 App Store Connect

> 💡 上次踩坑：如果 Xcode 在 xcodegen 之前就开着项目，先**完全关闭 Xcode 再重开**，否则 Xcode 缓存的是旧 pbxproj，archive 出来还是旧版本。

```bash
open PersonalSystem.xcodeproj
```

1. Xcode 顶部 device 选 **`Any iOS Device (arm64)`**（不要选模拟器、不要选 iPhone）
2. **Product → Archive**（等 1–3 分钟编译）
3. Organizer 弹出后**先看右侧面板的 Version**——必须是新版本号，不是别 distribute
4. **Distribute App → App Store Connect → Upload**
5. 看到 "Successfully uploaded" 就关 Organizer，等 5–30 分钟 ASC 处理

> 💡 Organizer 里如果累积了很多旧 archive，建议右键删掉避免之后手滑选错——本地 archive 删了不影响线上。

### 4.4（可选）TestFlight 内测一轮

- 把自己加进 internal testers
- TestFlight app 装一下，自己跑几天 / 找 1–2 人帮跑
- 发现 bug → 改代码 → build +1 重传（按 4.2 的方式 bump build，4.3 重新上传）

### 4.5 在 ASC 创建新版本 + 提交审核

1. App Store Connect → LifeOS → Distribution → 左侧 `iOS App` 旁的 **+** → 输入新版本号 → Create
2. 填 **What's New in This Version**（用户更新时看到的"更新内容"，中文，每条一行，总长不超过 4000 字符）
3. 滚到 **Build** 区域 → Add Build → 选刚才上传的 build（如果还没出现就过几分钟刷新）
4. 截图如果新功能引起明显 UI 变化，重新生成（参考 [ASC_SCREENSHOT_PLAN.md](docs/operations/appstore/ASC_SCREENSHOT_PLAN.md)）；变化不大就不换
5. App Privacy / Age Rating / Pricing 通常无需改
6. **Save** → 顶部 **Add for Review** → **Submit to App Review**

> 💡 出口合规已永久豁免。`project.yml` 里的 `ITSAppUsesNonExemptEncryption: false` 会让每次新 build 自动跳过"missing export compliance information"那个弹窗，无需手动到 TestFlight 标签答题。

按 [ASC_FINAL_REVIEW_CHECKLIST.md](docs/operations/appstore/ASC_FINAL_REVIEW_CHECKLIST.md) 过一遍提交前自检。

### 4.6 等审核

通常 24–48h 出结果。期间状态在 ASC 显示 `Waiting for Review` → `In Review` → `Pending Developer Release` / `Ready for Distribution`。

被拒的话邮件会写明原因，按提示改代码，回 §4.2 bump build（不必 bump marketing）重传。

### 4.7 过审后：打 git tag + 发 GitHub Release

> ⚠️ **必须等 Apple 邮件通知 "Ready for Distribution" 后再做**。提前打 tag 一旦被拒就指错 commit。

```bash
git checkout main && git pull
git tag -a v1.2.0 -m "1.2.0 · 一句话说明本次更新"
git push origin v1.2.0

gh release create v1.2.0 --title "v1.2.0" --notes "$(cat <<'EOF'
## 新功能
- ...

## 改进
- ...

## 修复
- ...
EOF
)"
```

如果在 ASC 选了手动 release（默认就是手动），还要去 ASC 网页点 **Release this version** 把 app 真正推到所有用户。

### 4.8 审核期间想做新功能 / 修 bug 怎么办？

**核心原则：审核期间不动 main 上的版本号、不重新 archive。** 让当前提审版本安静过审。

| 想做的事 | 做法 |
|---|---|
| 新功能 / 小优化 | 正常开 `feat/xxx` 分支写代码、PR 合到 main，**不要在 main 上改 project.yml 的 MARKETING_VERSION / CURRENT_PROJECT_VERSION**。等当前版本上线后，开新分支 bump 到下一个版本（1.1.x patch 或 1.x.0 minor）|
| 发现当前提审 build 有严重 bug | 在 ASC 点 **Remove This Version from Review**（撤回审核）→ 改代码 → bump build 到下一个数字（不必 bump marketing）→ 重新 archive 上传 → 重新 Submit |
| 发现 metadata / 截图问题（非代码） | ASC 里改即可，**审核期间也能改大部分 metadata**，改完 Save 不影响排队。但 What's New 一旦提交就锁了，要改得撤审 |

实际操作中，告诉 AI："审核中，我想加 X 功能"，AI 会从最新 main 拉 `feat/xxx` 分支让你正常开发。所有 PR 照常合 main，只是别动版本号；合入后 AI 应主动把用户可见变化写入 `CHANGELOG.md` `[Unreleased]`。

状态口径必须分清：

- **代码已合并**：发版 PR 已进 `main`，但还没 Archive / Upload / Submit。
- **已提交审核**：ASC 已 Submit to App Review。此时可以更新 `LAUNCH_CHECKLIST.md` / `IN_PROGRESS.md` 记录审核中，但不要打 tag。
- **已上架**：Apple 显示 Ready for Distribution / 已 release。此时再打 `vX.Y.Z` tag、发 GitHub Release，并把发版状态文档改成已上架。

> 📝 开新 AI session 时直接套用 [AI_HANDOFF.md](AI_HANDOFF.md) 里的开场白模板，
> 帮 AI 一次性把规范、硬约束、工作流装进上下文。

---

## 5. 后续迭代要持续注意的事 ⚠️

### 5.1 提审文案不能漂离 UI

之后改设置页 / AI 入口 / 同意弹窗的逻辑时，务必同步检查：

- `AIConsentSheet.swift`
- `docs/operations/appstore/ASC_COPY_DRAFT_v1.md`（用作 ASC 提审文案）
- 截图文案

### 5.2 永远不要把 LifeOS 表述成"医疗 app"

红线：

- 不诊断
- 不治疗
- 不提供医疗建议
- 是个人记录 / 观察工具

`docs/operations/appstore/ASC_COPY_DRAFT_v1.md` 里已经处理好这条，后续改文案不要漂回敏感表述。

### 5.3 build number 永远 +1，永远不重复

Apple 后台拒绝重复 build number。哪怕只是改一个 typo 重新 archive，build 也要 +1。

### 5.4 隐私问卷与代码行为对齐

如果后续加了任何向第三方发数据的功能（analytics / 第三方 SDK / 新的 AI 服务商），必须更新 ASC 的 App Privacy 问卷。当前承诺：

- 只发往 `ai.dogdada.com`（用户主动触发的 AI 解析）
- Apple 健康同步只读取用户授权的睡眠分析和体能训练记录，并只写入本地时间表；不发送给 AI 后端
- 不收集行为日志
- 没有第三方 analytics

新功能动到这块时记得回 ASC 更新。

下个包含 Apple 健康同步的版本发版前，必须人工确认：

- Apple Developer / App ID 已启用 HealthKit capability
- App Store Connect App Privacy 问卷补充 Health & Fitness 相关数据使用说明
- Review Notes 说明 HealthKit 数据只用于本地时间记录同步，不用于诊断、治疗或医疗建议

### 5.5 截图随版本演进

如果新版本的 UI 跟商店截图差距明显（比如打卡页大改），上版本前需要重新出图。当前规则参考 [ASC_SCREENSHOT_PLAN.md](docs/operations/appstore/ASC_SCREENSHOT_PLAN.md)。

### 5.6 出口合规已永久豁免

`project.yml` 的 `info.properties` 已加 `ITSAppUsesNonExemptEncryption: false`（PR #4，2026-04-29）。理由：LifeOS 只通过 `URLSession` 走 HTTPS（iOS 系统级 TLS），不实现自定义加密，符合 Apple 出口合规豁免条件。

**如果未来引入了任何自定义加密**（bundle openssl、用 CryptoKit 做端到端加密、引入第三方 SDK 自带加密等），必须把这行删掉，并按 Apple 流程重新声明。

---

## 6. 下一步

### 6.1 1.2.0 上架收尾（已完成 ✅）

- ✅ ASC 状态 Ready for Distribution
- ✅ Tag `v1.2.0` 已 push（指向 bump commit `4eb9056`）
- ✅ GitHub Release `v1.2.0` 已发布
- ✅ 本文件已更新为 1.2.0 上架状态

### 6.2 1.3.0 上架收尾

- ✅ `chore: bump 1.3.0 / build 5`（[#30](https://github.com/nannan-debug/lifeos/pull/30)）已合入 main
- ✅ `1.3.0 (build 5)` 已 Archive / Upload / Submit to App Review（2026-05-02）
- ✅ `1.3.0 (build 5)` 已通过审核并上架（2026-05-03）
- ✅ Tag `v1.3.0` 已 push
- ✅ GitHub Release `v1.3.0` 已发布
- `IN_PROGRESS.md` 已归档灵感与反思模块 V2，当前没有跨 PR 的在飞功能

### 6.3 1.4.0 上架收尾（已上架，tag/release 决定跳过）

- ✅ 发版 PR：`1.4.0 (build 6)` 版本号 / changelog / 公开 Support & Privacy 页面 / 本清单状态更新（[#34](https://github.com/nannan-debug/lifeos/pull/34)）
- ✅ PR 已合入 main：`f97a4af chore: bump 1.4.0 build 6 (#34)`
- ✅ 用户已手动 Archive / Upload 到 App Store Connect
- ✅ ASC 已创建 `1.4.0` 新版本，填写 What's New，选择 build 6，并 Submit to App Review（2026-05-03）
- ✅ `1.4.0 (build 6)` 已通过 App Review（2026-05-04）并上架
- ℹ️ `v1.4.0` tag / GitHub Release **决定跳过**：1.4.0 上架时跳过了这一步，后续不再补打；这不影响线上，也不需要在后续发版交接中重复提醒。

### 6.4 1.5.0 上架收尾（已完成 ✅）

- ✅ 发版 PR：`1.5.0 (build 7)` 版本号 / changelog / 设置页 CSV 导出 + 时间记录页 PRD seed/键盘修复（[#37](https://github.com/nannan-debug/lifeos/pull/37)）
- ✅ PR 已合入 main：`628491e feat: 设置页新增 CSV 导出入口 (1.5.0 build 7) (#37)`
- ✅ 用户已手动 Archive / Upload 到 App Store Connect
- ✅ ASC 已创建 `1.5.0` 新版本，Submit to App Review 并通过审核（2026-05-07）
- ✅ Tag `v1.5.0` 已 push（指向 `628491e`）
- ✅ GitHub Release [v1.5.0](https://github.com/nannan-debug/lifeos/releases/tag/v1.5.0) 已发布

### 6.5 1.5.1 上架收尾（已完成 ✅）

- ✅ 发版 PR：`1.5.1 (build 8)` 版本号 / changelog / Apple 健康同步与 AI 输入框体验改进（[#40](https://github.com/nannan-debug/lifeos/pull/40)）
- ✅ 用户已手动 Archive / Upload 到 App Store Connect
- ✅ ASC 已创建 `1.5.1` 新版本，Submit to App Review 并通过审核（2026-05-11，用户确认）
- ✅ `1.5.1 (build 8)` 已上架（2026-05-11，用户确认）
- ✅ PR 已合入 main：`0c238fe Prepare LifeOS 1.5.1 build 8 release`
- ✅ Tag `v1.5.1` 已 push（指向 `0c238fe`）
- ✅ GitHub Release [v1.5.1](https://github.com/nannan-debug/lifeos/releases/tag/v1.5.1) 已发布

### 6.6 1.5.2 上架收尾（已完成 ✅）

- ✅ 发版 PR 已合入 main：`1.5.2 (build 9)` 版本号 / changelog / 本清单状态更新（[#43](https://github.com/nannan-debug/lifeos/pull/43)）
- ✅ 用户已手动 Archive / Upload 到 App Store Connect。
- ✅ ASC 已创建 / 选择 `1.5.2` 新版本，并 Submit to App Review（2026-05-11，用户确认）。
- ✅ `1.5.2 (build 9)` 已通过审核并上架（2026-05-13，用户确认）。
- ✅ Tag `v1.5.2` 已 push（指向 `940579f`）。
- ✅ GitHub Release [v1.5.2](https://github.com/nannan-debug/lifeos/releases/tag/v1.5.2) 已发布。

### 6.7 1.6.0 上架收尾（已完成 ✅）

- ✅ 功能 PR 已合入 `main`：AI 识别治理 / 每日状态提醒 / 待办完成历史 / 时间圆盘新建交互 / App Store 更新提示（[#46](https://github.com/nannan-debug/lifeos/pull/46)）。
- ✅ 发版 PR 已合入 `main`：`1.6.0 (build 10)` 版本号 / changelog / 本清单状态更新（[#47](https://github.com/nannan-debug/lifeos/pull/47)，merge commit `f563735`）。
- ✅ 用户已手动 Archive / Upload 到 App Store Connect。
- ✅ ASC 已创建 / 选择 `1.6.0` 新版本，并 Submit to App Review（2026-05-14，用户确认）。
- ✅ `1.6.0 (build 10)` 已通过审核并上架（2026-05-15，用户确认）。
- ✅ Tag `v1.6.0` 已 push（指向 `f563735`）。
- ✅ GitHub Release [v1.6.0](https://github.com/nannan-debug/lifeos/releases/tag/v1.6.0) 已发布。

### 6.8 1.7.0 上架收尾（已完成 ✅）

- ✅ 发版 PR 已合入 `main`：`1.7.0 (build 11)` 版本号 / changelog / 本清单状态更新（[#56](https://github.com/nannan-debug/lifeos/pull/56)）。
- ✅ 用户已手动 Archive / Upload 到 App Store Connect。
- ✅ ASC 已创建 / 选择 `1.7.0` 新版本，并 Submit to App Review（2026-05-18）。
- ✅ `1.7.0 (build 11)` 已通过审核并上架（2026-05-20，用户确认）。
- ✅ Tag `v1.7.0` 已 push。
- ✅ GitHub Release [v1.7.0](https://github.com/nannan-debug/lifeos/releases/tag/v1.7.0) 已发布。

### 6.9 1.8.0 上架收尾（已完成 ✅）

- ✅ 功能 / 发版 PR 已合入 `main`：`1.8.0 (build 12)` AI 全屏对话窗、多会话文件存储、历史搜索 / 切换 / 删除、Agent 对话视觉优化、Apple 健康睡眠同步修复、时间记录更新事件修复、随手记时间线排序和短标题优化（[#68](https://github.com/nannan-debug/lifeos/pull/68)，merge commit `fe56c50`）。
- ✅ 用户已手动 Archive / Upload 到 App Store Connect。
- ✅ ASC 已创建 / 选择 `1.8.0` 新版本，并 Submit to App Review（2026-05-20，用户确认）。
- ✅ `1.8.0 (build 12)` 已通过审核并上架（2026-05-21，用户确认）。
- ✅ Tag `v1.8.0` 已 push（指向 `f48daaa`，即 1.8.0 提审状态；不包含后续 1.8.1 候选的 Agent Trace 改动）。
- ✅ GitHub Release [v1.8.0](https://github.com/nannan-debug/lifeos/releases/tag/v1.8.0) 已发布。

### 6.10 1.11.0 上架收尾（已上架 ✅）

- ✅ 功能 PR 已合入 `main`：中英文双语支持 + AI 语言匹配（[#83](https://github.com/nannan-debug/lifeos/pull/83)，squash merge `5c96898`）。
- ✅ 版本号已 bump：`1.11.0 (build 15)`，commit `036d3c6`，已 push main。
- ✅ 用户已手动 Archive / Upload 到 App Store Connect 并 Submit to App Review（2026-05-25）。
- ✅ `1.11.0 (build 15)` 已通过审核并上架（2026-05-26，用户确认）。
- ✅ Tag `v1.11.0` 已 push（指向 `036d3c6`，即 1.11.0 提审状态）。
- ✅ GitHub Release [v1.11.0](https://github.com/nannan-debug/lifeos/releases/tag/v1.11.0) 已发布。

**关键改动清单（供 What's New 参考）：**
- 设置新增语言切换（中文/English）
- AI 自动匹配用户语言回复
- 全界面中英文双语支持
- 每日一言 70 条英文原版语录

### 6.11 1.12.0 上架收尾（已上架 ✅）

- ✅ `1.12.0 (build 16)` 已通过审核并上架（2026-06-04）。
- ✅ 当前 `main` / `project.yml` 状态为 `1.12.0 (build 16)`。
- ✅ App Store Connect 状态：Ready for Distribution。

**关键改动清单（供历史回看）：**
- AI 对话消息支持时间、复制、点赞和点踩。
- 对话历史支持长按重命名。
- 英文模式补齐日历弹层、时间圆盘拖拽手柄和设置页同步状态小字。
- 修复 AI 流式回复 JSON 片段外露和 DBT Coach 流程卡住 / 未保存的问题。

### 6.12 1.13.0 上架收尾（已上架 ✅）

- ✅ 发版 PR 已合入 `main`：`1.13.0 (build 17)` 版本号 / changelog / What's New / 本清单状态更新（[#105](https://github.com/nannan-debug/lifeos/pull/105)）。
- ✅ 用户已手动 Archive / Upload 到 App Store Connect，并 Submit to App Review（2026-06-12）。
- ✅ `1.13.0 (build 17)` 已通过审核并上架（2026-06-14，用户确认）。
- ✅ ASC 当前状态：`1.13.0 Ready for Distribution`。
- ✅ 已在 [`docs/operations/appstore/ASC_COPY_DRAFT_v1.md`](docs/operations/appstore/ASC_COPY_DRAFT_v1.md) §0 整理 `1.13.0` What's New 草稿。
- ✅ `CHANGELOG.md [Unreleased]` 已归档为 `1.13.0 (build 17)`。
- ✅ Tag `v1.13.0` / GitHub Release 待本次状态 PR 合并后完成。

---

## 7. 仓库内与上架最相关的文件

- `project.yml`
- `PersonalSystem.xcodeproj/project.pbxproj`
- `Sources/App/Info.plist`
- `Sources/App/PrivacyInfo.xcprivacy`
- `Sources/Views/AIConsentSheet.swift`
- `Sources/Services/AIParser.swift`
- `PRIVACY_POLICY.md`
- `docs/operations/appstore/ASC_COPY_DRAFT_v1.md`
- `docs/operations/appstore/ASC_SCREENSHOT_PLAN.md`
- `docs/index.html`
- `docs/privacy.html`

---

## 8. 一句话交接

**LifeOS 1.0.0 ~ 1.13.0 均已在 App Store 在线。最新线上版本为 `1.13.0 (build 17)`（猫猫首次问卷、人设设置、分层记忆与情绪梳理体验优化）。**
