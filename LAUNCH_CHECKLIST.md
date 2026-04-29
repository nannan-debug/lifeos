# LifeOS · 上架真实进度清单

> 目的：给新的 AI / 协作者一个能立即接手的真实状态，而不是历史计划。
> 最后更新：2026-04-29

---

## 0. 当前结论

**LifeOS 已经在 App Store 上线。** 🎉

- ✅ App Store 首发：`1.0.0 (build 1)`（2026-04）
- ✅ 应用商店可以搜到 `LifeOS` 并下载
- ✅ App ID：`6763877227`
- ✅ App Store Connect 状态：**Ready for Distribution**

当前阶段重心从"首次上架"切换到"**持续迭代 + 版本更新**"：

1. 收集真实用户反馈（设置页有反馈邮箱入口）
2. 做小步迭代（feat → MINOR bump，bugfix → PATCH bump）
3. 每个版本走 Archive → TestFlight → ASC 审核流程

下一个版本：`1.1.0 (build 2)` —— 打卡页 inline 编辑重构（[PR #2](https://github.com/nannan-debug/lifeos/pull/2)）。

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

## 4. 后续版本更新流程（以 1.1.0 为例）

每次发新版本走这个 SOP，不用再走 §3 那些一次性配置：

### 4.1 在 feature 分支做完代码改动并 PR 合到 main

当前 `1.1.0` 的 PR：[#2](https://github.com/nannan-debug/lifeos/pull/2)

### 4.2 改 Info.plist 版本号

```xml
<key>CFBundleShortVersionString</key>
<string>1.1.0</string>          <!-- feat → MINOR bump，bugfix → PATCH bump -->
<key>CFBundleVersion</key>
<string>2</string>               <!-- 永远 +1，不能跟过往任何 build 重复 -->
```

### 4.3 Archive + 上传到 App Store Connect

1. Xcode 顶部 device 选 `Any iOS Device (arm64)`
2. Product → Archive
3. Organizer 弹出后 → **Distribute App** → **App Store Connect** → **Upload**
4. 等 5–30 分钟，ASC 后台 TestFlight 出现新 build

### 4.4（可选）TestFlight 内测一轮

- 把自己加进 internal testers
- TestFlight app 装一下、自己跑几天 / 找 1–2 人帮跑
- 发现 bug → 改代码 → build +1 重传

### 4.5 在 ASC 创建新版本

1. App Store Connect → LifeOS → Distribution → 左侧 `iOS App` 点 `+`
2. 选 `1.1.0` 版本号
3. 填 **What's New in This Version**（用户更新时看到的"更新内容"，建议中文，每条一行 / 总长不超过 4000 字符）
4. 选刚刚上传的 build
5. 截图如果有新功能引起 UI 变化，需要重新生成（参考 [ASC_SCREENSHOT_PLAN.md](ASC_SCREENSHOT_PLAN.md)）
6. App Privacy / Age Rating / Pricing 通常无需改

### 4.6 提交审核

按 [ASC_FINAL_REVIEW_CHECKLIST.md](ASC_FINAL_REVIEW_CHECKLIST.md) 过一遍 → Submit for Review。

通常 24–48h 出结果。

### 4.7 通过后打 git tag

```bash
git checkout main && git pull
git tag -a v1.1.0 -m "1.1.0 · 打卡页 inline 编辑"
git push origin v1.1.0
gh release create v1.1.0 --title "v1.1.0" --notes "..."
```

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

---

## 6. 下一步（针对 1.1.0 提交）

按 §4 的 SOP 走：

1. 把 PR #2 合到 main
2. 打开 Xcode → Archive → 上传 ASC（build 2）
3. 自己 TestFlight 装一下，跑几天验证 inline 编辑没回归 bug
4. 在 ASC 创建 1.1.0 版本，填 What's New
5. 如果打卡页 UI 改动够明显，重新生成截图（建议至少把"打卡 inline 编辑"这一张换新）
6. Submit for Review，过审打 tag `v1.1.0`

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

**LifeOS 1.0.0 已上架 App Store（2026-04 首发）。当前在 `claude/optimistic-pare-7aee7f` 分支上准备 `1.1.0` 更新（PR #2，打卡页 inline 编辑），合并后按 §4 的 SOP 走 Archive → ASC → 提审流程。**
