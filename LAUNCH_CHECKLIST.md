# LifeOS · 上架真实进度清单

> 目的：给新的 AI / 协作者一个能立即接手的真实状态，而不是历史计划。
> 最后更新：2026-04-26

---

## 0. 当前结论

**LifeOS 已经进入 App Store 提审准备阶段。**

代码和基础合规材料基本齐了，最大的前置阻塞已经解除：

- ✅ Apple Developer 个人账号已注册
- ✅ 已脱离前公司 Team
- ✅ 工程里已写入新的 `DEVELOPMENT_TEAM`

当前最主要的剩余工作不是“继续开发功能”，而是：

1. 在 App Store Connect 完成在线配置确认
2. 生成并上传正式截图
3. 准备 Support URL / Privacy Policy URL
4. 做一次 Archive / TestFlight / 最终提审

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
| 当前营销版本 | `1.0.0` |
| 当前 build | `1` |
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

## 3. 当前状态不确定，需要到 ASC / Xcode 里确认 👀

这些项目**仓库里无法证明**，需要人工在线确认：

- ⏳ App Store Connect 里是否已创建 `LifeOS` 的 App 记录
- ⏳ Bundle ID `ai.anna.personalsystem` 是否已在 Apple Developer Portal 注册
- ⏳ 是否已成功 Archive 过一个可上传构建
- ⏳ 是否已上传过 TestFlight build
- ⏳ ASC 的 App Privacy 问卷是否已填写保存
- ⏳ Age Rating 是否已填写
- ⏳ Pricing & Availability 是否已排除 China mainland
- ⏳ 正式截图是否已生成并上传

---

## 4. 剩余必做项（按顺序）

### 4.1 确认 Apple 侧对象都存在

去 Apple Developer / App Store Connect 确认以下三件事：

1. `ai.anna.personalsystem` 已建成 App ID
2. ASC 里已创建 `LifeOS`
3. Xcode 的 Signing & Capabilities 已指向个人账号

### 4.2 做一版可上传构建

目标：

- Archive 成功
- 上传到 App Store Connect / TestFlight
- 如果首个上传失败，优先修签名或 metadata，不要乱改功能代码

版本策略：

- 首次 TestFlight 如果上传新包，建议保持 `1.0.0`
- `CFBundleVersion` 每上传一次必须递增

### 4.3 打通公开 URL

准备使用 GitHub Pages：

- Support URL：`https://nannan-debug.github.io/lifeos/`
- Privacy Policy URL：`https://nannan-debug.github.io/lifeos/privacy.html`

前提：

1. 仓库存在于 `nannan-debug/lifeos`
2. 仓库可开启 GitHub Pages
3. Pages Source 选择 `main` 分支下 `/docs`

### 4.4 生成并上传正式截图

目标槽位：

- iPhone 6.7" Display：至少 3 张，建议 5 张

仓库里已有方案：

- `ASC_SCREENSHOT_PLAN.md`

截图原则：

- 必须是真实模拟器截图
- 可以用 Claude Design 做外层包装
- 不要用“未来功能”假图

### 4.5 填完 ASC metadata

仓库里已有文案草稿：

- `ASC_COPY_DRAFT_v1.md`

重点字段：

- Subtitle
- Promotional Text
- Description
- Keywords
- Support URL
- Privacy Policy URL
- Category
- App Review Notes

---

## 5. 当前我认为还要注意的问题 ⚠️

### 5.1 Support URL 之前没有真正落地

之前只是文档里写了 Notion 方案，没有稳定链接。
现在改成仓库内静态页会更稳，但仍需你在 GitHub 里开启 Pages 才能真正生效。

### 5.2 `LAUNCH_CHECKLIST.md` 旧版信息已经过时

旧版里还写着：

- “Apple Developer 账号未完成”
- “隐私政策仍有占位符”

这些都不再准确，不能再当真实状态使用。

### 5.3 本地终端无法代替你确认 ASC 在线状态

我能确认仓库内容，但不能从本地文件判断：

- 你是否已创建 ASC 记录
- 你是否已上传截图
- 你是否已提交审核

这些必须在 App Store Connect 网页里核对。

### 5.4 提审表述要避免“医疗 app”误判

文案里虽然会提到 `ADHD` 和 `DBT`，但要始终坚持：

- 不诊断
- 不治疗
- 不提供医疗建议
- 是个人记录 / 观察工具

这点在 `ASC_COPY_DRAFT_v1.md` 里已经处理过，提审时不要改偏。

### 5.5 截图不要使用未上线的“复盘 Tab”

代码库里有 `ReviewView.swift` 雏形，但当前主 Tab 不是正式的“复盘产品态”。
提审截图建议继续按已有方案，用 Today / AI / Time / Inbox / Settings 组合。

### 5.6 提审文案要持续和现有 UI 对齐

目前已修正 AI 同意弹窗与 ASC 文案里关于“AI 开关”的表述。
后续如果继续修改设置页或 AI 入口，记得同步检查：

- `AIConsentSheet.swift`
- `ASC_COPY_DRAFT_v1.md`
- 截图文案

---

## 6. 建议的下一步

最顺的顺序是：

1. 开启 GitHub Pages，让 Support / Privacy 两个 URL 先可访问
2. 用 Xcode 做一次 Archive 并上传 TestFlight
3. 按 `ASC_SCREENSHOT_PLAN.md` 产出 5 张营销截图
4. 把 `ASC_COPY_DRAFT_v1.md` 内容填进 ASC
5. 完成 App Privacy / Age Rating / Pricing
6. 提交审核

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

**现在不是“还没准备上架”，而是“代码和文案差不多了，正在补齐 URL、截图、ASC 在线配置，并准备首个可提审构建”。**
