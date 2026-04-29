# LifeOS · 上架真实进度清单

> 目的：给新的 AI / 协作者一个能立即接手的真实状态，而不是历史计划。
> 最后更新：2026-04-29

---

## 0. 当前结论

**LifeOS 已经在 App Store 上线，1.1.0 已提审等审核。** 🎉

- ✅ `1.0.0 (build 1)` — App Store 首发（2026-04）
- ⏳ `1.1.0 (build 2)` — 2026-04-29 Submit for Review，等待 Apple 审核（24–48h）
- ✅ App ID：`6763877227`
- ✅ App Store Connect 状态：1.0.0 Ready for Distribution / 1.1.0 Waiting for Review

当前阶段重心是"**持续迭代 + 版本更新**"：

1. 收集真实用户反馈（设置页有反馈邮箱入口）
2. 做小步迭代（feat → MINOR bump，bugfix → PATCH bump）
3. 每个版本走 §4 SOP：改 project.yml → Archive → ASC 审核 → 过审打 tag

**审核期间想做新功能怎么办？** 见 §4.8。

---

## 1. 项目基本信息

| 项目 | 值 |
|---|---|
| 产品名 | **LifeOS** |
| App Store 显示名 | `LifeOS` |
| Bundle ID | `ai.anna.personalsystem` |
| iOS 最低支持 | iOS 16.0 |
| Swift 版本 | 5.9 |
| Xcode project | XcodeGen 生成（源头是 `project.yml`） |
| 主语言 | 简体中文（zh-Hans） |
| 目标区域 | 除中国大陆外全球区 |
| 定价 | 免费，无内购 |
| 已上架营销版本 | `1.0.0` (build 1) |
| 当前开发分支版本 | `1.1.0` (build 2) |
| Development Team | `355RQ5S3DW` |

关键路径：

```text
/Users/newblue/Projects/openclaw-project/lobster-team/ios-app/
├── project.yml
├── PersonalSystem.xcodeproj
├── Sources/
├── PRIVACY_POLICY.md
├── ASC_COPY_DRAFT_v1.md
├── ASC_SCREENSHOT_PLAN.md
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
- ✅ CSV 导出 / 导入已存在

### 2.2 开发者账号 / 签名

- ✅ Apple Developer 个人账号已注册并付费生效
- ✅ 已脱离前公司 Team
- ✅ `project.yml` 已写入 `DEVELOPMENT_TEAM = 355RQ5S3DW`
- ✅ `.xcodeproj` 当前也同步到了同一个 Team ID

### 2.3 合规 / 文案材料

- ✅ 中文隐私政策草稿已填入真实开发者名和邮箱：`PRIVACY_POLICY.md`
- ✅ AI 首次同意流程已落地：`ai.consent.v1`
- ✅ App Store Connect 文案草稿已整理：`ASC_COPY_DRAFT_v1.md`
- ✅ App Store 截图执行方案已整理：`ASC_SCREENSHOT_PLAN.md`
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
- ✅ ASC metadata 文案填写（按 [ASC_COPY_DRAFT_v1.md](ASC_COPY_DRAFT_v1.md)）
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
git commit -m "chore: bump version to 1.2.0 / build 3"
git push -u origin chore/bump-version-1.2.0
gh pr create --title "chore: bump 1.2.0 / build 3" --body "..."
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
4. 截图如果新功能引起明显 UI 变化，重新生成（参考 [ASC_SCREENSHOT_PLAN.md](ASC_SCREENSHOT_PLAN.md)）；变化不大就不换
5. App Privacy / Age Rating / Pricing 通常无需改
6. **Save** → 顶部 **Add for Review** → **Submit to App Review**

> 💡 出口合规已永久豁免。`project.yml` 里的 `ITSAppUsesNonExemptEncryption: false` 会让每次新 build 自动跳过"missing export compliance information"那个弹窗，无需手动到 TestFlight 标签答题。

按 [ASC_FINAL_REVIEW_CHECKLIST.md](ASC_FINAL_REVIEW_CHECKLIST.md) 过一遍提交前自检。

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

**核心原则：审核期间不动 main 上的版本号、不重新 archive。** 让 1.1.0 安静过审。

| 想做的事 | 做法 |
|---|---|
| 新功能 / 小优化 | 正常开 `feat/xxx` 分支写代码、PR 合到 main，**不要在 main 上改 project.yml 的 MARKETING_VERSION / CURRENT_PROJECT_VERSION**。等当前版本上线后，开新分支 bump 到下一个版本（1.1.x patch 或 1.x.0 minor）|
| 发现当前提审 build 有严重 bug | 在 ASC 点 **Remove This Version from Review**（撤回审核）→ 改代码 → bump build 到下一个数字（不必 bump marketing）→ 重新 archive 上传 → 重新 Submit |
| 发现 metadata / 截图问题（非代码） | ASC 里改即可，**审核期间也能改大部分 metadata**，改完 Save 不影响排队。但 What's New 一旦提交就锁了，要改得撤审 |

实际操作中，告诉 AI："审核中，我想加 X 功能"，AI 会从最新 main 拉 `feat/xxx` 分支让你正常开发。所有 PR 照常合 main，只是别动版本号。

> 📝 开新 AI session 时直接套用 [AI_HANDOFF.md](AI_HANDOFF.md) 里的开场白模板，
> 帮 AI 一次性把规范、硬约束、工作流装进上下文。

---

## 5. 后续迭代要持续注意的事 ⚠️

### 5.1 提审文案不能漂离 UI

之后改设置页 / AI 入口 / 同意弹窗的逻辑时，务必同步检查：

- `AIConsentSheet.swift`
- `ASC_COPY_DRAFT_v1.md`（用作 ASC 提审文案）
- 截图文案

### 5.2 永远不要把 LifeOS 表述成"医疗 app"

文案里会提到 `ADHD` 和 `DBT`，但红线是：

- 不诊断
- 不治疗
- 不提供医疗建议
- 是个人记录 / 观察工具

`ASC_COPY_DRAFT_v1.md` 里已经处理好这条，后续改文案不要漂回敏感表述。

### 5.3 build number 永远 +1，永远不重复

Apple 后台拒绝重复 build number。哪怕只是改一个 typo 重新 archive，build 也要 +1。

### 5.4 隐私问卷与代码行为对齐

如果后续加了任何向第三方发数据的功能（analytics / 第三方 SDK / 新的 AI 服务商），必须更新 ASC 的 App Privacy 问卷。当前承诺：

- 只发往 `ai.dogdada.com`（用户主动触发的 AI 解析）
- 不收集行为日志
- 没有第三方 analytics

新功能动到这块时记得回 ASC 更新。

### 5.5 截图随版本演进

如果新版本的 UI 跟商店截图差距明显（比如打卡页大改），上版本前需要重新出图。当前规则参考 [ASC_SCREENSHOT_PLAN.md](ASC_SCREENSHOT_PLAN.md)。

### 5.6 出口合规已永久豁免

`project.yml` 的 `info.properties` 已加 `ITSAppUsesNonExemptEncryption: false`（PR #4，2026-04-29）。理由：LifeOS 只通过 `URLSession` 走 HTTPS（iOS 系统级 TLS），不实现自定义加密，符合 Apple 出口合规豁免条件。

**如果未来引入了任何自定义加密**（bundle openssl、用 CryptoKit 做端到端加密、引入第三方 SDK 自带加密等），必须把这行删掉，并按 Apple 流程重新声明。

---

## 6. 下一步

### 6.1 等 1.1.0 审核结果（被动等）

收到 Apple 邮件 **Ready for Distribution** 后：

1. ASC 网页点 **Release this version**（如果选了手动 release）
2. 按 §4.7 打 tag `v1.1.0` + 发 GitHub Release

被拒的话邮件会写明原因，按 §4.8 第二行处理。

### 6.2 审核期间可以做的事

- 收集 1.0.0 真实用户反馈（设置页反馈邮箱）
- 在 feature 分支开发下一个版本的内容（按 §4.8 原则）
- 想清楚下一个版本是 1.1.x（patch）还是 1.2.0（minor）

---

## 7. 仓库内与上架最相关的文件

- `project.yml`
- `PersonalSystem.xcodeproj/project.pbxproj`
- `Sources/App/Info.plist`
- `Sources/App/PrivacyInfo.xcprivacy`
- `Sources/Views/AIConsentSheet.swift`
- `Sources/Services/AIParser.swift`
- `PRIVACY_POLICY.md`
- `ASC_COPY_DRAFT_v1.md`
- `ASC_SCREENSHOT_PLAN.md`
- `docs/index.html`
- `docs/privacy.html`

---

## 8. 一句话交接

**LifeOS 1.0.0 已上架 App Store（2026-04 首发），1.1.0 (build 2) 已于 2026-04-29 提审，等待 Apple 审核。`main` 上有出口合规永久豁免（PR #4）。下次发版按 §4 SOP 走，关键：改 `project.yml` 不是 `Info.plist`。**
