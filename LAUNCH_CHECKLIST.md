# LifeOS · 上架交接清单

> 目的：在一个新的 Claude 对话里，把这份文档丢给它，就能接手指导我完成剩下所有事情。
> 这份文档 = 背景 + 已做 + 待办 + 关键信息 + 已知卡点。
>
> 最后更新：2026-04-22

---

## 0. 一句话背景

我叫 Anna，正在开发一个叫 **LifeOS** 的 iOS app（Swift/SwiftUI）。
这是个给 ADHD 人群的"人生观察系统"：四个 Tab（今日/时间/随记/设置）+ 未来复盘 Tab + 全局 AI 输入框。
目标：**上架除中国大陆外全球区的 Apple App Store**，不做中国区（省去 ICP 备案 + 软著）。
我不是专业开发者，个人独立做这个 app。

---

## 1. 项目基本信息

| 项目 | 值 |
|---|---|
| 产品名 | **LifeOS** |
| App Store 显示名 | `LifeOS` |
| Bundle ID | `ai.anna.personalsystem` |
| iOS 最低支持 | iOS 16.0 |
| Swift 版本 | 5.9 |
| Xcode project | XcodeGen 生成（源头是 `project.yml`）|
| 主语言 | 简体中文（zh-Hans）|
| 目标区域 | 除中国大陆外全球区 |
| 定价 | 免费，无内购 |

### 关键目录（Mac 本地）

```
/Users/newblue/Projects/openclaw-project/lobster-team/ios-app/
├── project.yml                       # XcodeGen 配置
├── PersonalSystem.xcodeproj          # Xcode 工程
├── Sources/
│   ├── App/                          # AppDelegate, Info.plist, Assets
│   │   └── Assets.xcassets/
│   │       ├── AppIcon.appiconset/   # 13 个 icon 尺寸（已生成）
│   │       ├── LaunchBackground.colorset/
│   │       └── LaunchLogo.imageset/
│   ├── Models/Models.swift
│   ├── ViewModels/AppStore.swift
│   ├── Views/                        # 所有 SwiftUI 页面
│   └── Services/                     # AI 解析服务
├── Resources/Mascot/                 # 原始猫咪素材
├── PRIVACY_POLICY.md                 # 隐私政策草稿（有占位符待替换）
├── PRODUCT_BRIEF.md                  # 产品长版说明（给设计师）
├── PRODUCT_BRIEF_SHORT.md            # 产品精简版（给设计师）
└── LAUNCH_CHECKLIST.md               # 本文件
```

---

## 2. 已经完成的事 ✅

### 代码/产品侧
- ✅ 4 个主 Tab 功能开发完成（今日/时间/随记/设置）
- ✅ 全局 AI 输入框（FAB + 展开态 + 小猫 mascot + 首次使用同意弹窗 `AIConsentSheet`）
- ✅ AI 后端接 Cloudflare Worker（`ai.dogdada.com`，背后是 DeepSeek）
- ✅ 打卡项按 tag 分组 + 折叠展开（仿 iOS 提醒事项）
- ✅ 按 `auth.userId` 用户隔离的 UserDefaults key（Hermes agent 改的，已验证）
- ✅ App 名改为 `LifeOS`（`CFBundleDisplayName`）
- ✅ App Icon 已应用（13 个尺寸，米底 + 绿描边趴猫，去 alpha）
- ✅ LaunchScreen 配置（`UILaunchScreen` 字典 + LaunchBackground colorset + LaunchLogo）
- ✅ 构建 + 测试通过（`xcodebuild build` + `xcodebuild test`）

### 合规/文档侧
- ✅ 隐私政策中文版草稿：`PRIVACY_POLICY.md`（**有占位符待替换**，见第 4 节）
- ✅ 首次使用 AI 的用户同意流程（写入 UserDefaults `ai.consent.v1`）
- ✅ 产品简介（长版 + 短版）给设计师

### 设计侧（进行中）
- ✅ 正在用 claude.ai/design 做视觉重设计
- ✅ 已选定方向（需要用户补充：具体是 A/B/C 哪个方向）
- ⏳ 全部主页面 Hi-Fi 稿、交互态、暗色、空状态、图标重绘

---

## 3. 还没做的事 ❌（按优先级）

### 🔴 P0 · 阻塞上架的硬需求

#### 3.1 获得一个干净的 Apple Developer 个人账号

**背景**：我之前误登录了前公司 SeeKoo LLC 的 Apple Developer 账号，**不能**用那个账号发我的个人 app（法律风险、app 归公司、收入归公司）。

**当前状态**：
- 已退出登录
- 已通知前公司 HR 回收我的团队权限
- 正在等 HR 处理（1-3 天）

**要做的**：
1. 等前公司把我的 Apple ID 从 SeeKoo LLC Team 里踢掉（或者直接用另一个 Apple ID 也行）
2. 访问 https://developer.apple.com/programs/enroll/
3. 选 **Individual**（不是 Organization）
4. 付 $99/年
5. 等审核通过（几小时 – 7 天）

#### 3.2 处理签名证书和打包

等开发者账号下来后：
1. **Developer Portal → Identifiers** → 创建 App ID，Bundle ID 填 `ai.anna.personalsystem`
2. **Developer Portal → Certificates** → 创建 **Apple Distribution** 证书，下载 `.cer`
3. **Xcode → Signing & Capabilities** → 选到新的开发者账号，Automatic signing
4. **Xcode → Product → Archive** → 导出 IPA 或直接 upload to App Store Connect
5. 版本号管理：首版 `CFBundleShortVersionString=1.0.0`, `CFBundleVersion=1`

#### 3.3 App Store Connect 建 App 记录

账号下来后，去 https://appstoreconnect.apple.com/apps
1. 点 `+` → New App
2. 填：
   - Platforms: iOS
   - Name: `LifeOS`
   - Primary Language: `Simplified Chinese (zh-Hans)`
   - Bundle ID: 选下拉里的 `ai.anna.personalsystem`
   - SKU: `lifeos-ios-001`（随便填，唯一即可）
3. 创建

#### 3.4 填 App Information（中文为主）

需要准备好：
- **副标题（Subtitle）**：30 字以内，例如 `ADHD 的温柔人生系统`
- **Promotional Text**：170 字内，上架后可随时改
- **Description（描述）**：~200 字介绍，强调 ADHD、不审判、一句话记录
- **Keywords（关键词）**：100 字符，逗号分隔，例如 `ADHD,待办,时间记录,情绪,日记,AI,DBT,脚手架`
- **Support URL**：一个公开的支持页（可以是 Notion 公开链接）
- **Marketing URL**（可选）：产品官网/Landing page
- **Category**：Primary = `Productivity` 或 `Lifestyle`；Secondary = 另一个

#### 3.5 填 App Privacy（苹果隐私"营养标签"）

这是个问卷。参考 `PRIVACY_POLICY.md` 老实填：
- **Data Linked to You**：无（LifeOS 不绑定用户身份）
- **Data Not Linked to You**：
  - User Content（用户主动发到 AI 服务的文本）
  - Diagnostics（无，我们不接任何统计 SDK）
- **Tracking**：不追踪
- **Data Types Collected**：
  - User Content: Yes（发给 AI 时的当次文本）
  - 其他全部 No

#### 3.6 准备截图

必传的两套：
- **iPhone 6.7" Display**（iPhone 15 Pro Max 模拟器）：至少 3 张，最多 10 张，1290×2796 px
- **iPhone 6.1" Display** / 6.5"：至少 3 张

建议的 5 张截图叙事（按 ADHD 故事线排）：
1. 今日 Tab 打卡 —— "温柔看住每一天"
2. 全局 AI 输入展开态 —— "说一句话，AI 替你归位"
3. 时间 Tab —— "看见时间花哪了"
4. 随记 Tab + 情绪标签 —— "给情绪起个名字"
5. 复盘 Tab（等开发完）—— "温柔照镜子"

每张截图顶部加一行文案（标语）更好转化。可以用 Figma 做带文字覆盖的 marketing screenshot。

#### 3.7 Age Rating（分级）

在 App Store Connect 里回答几个问题，应该会得到 **4+**（无暴力/成人内容/赌博等）。

#### 3.8 定价和区域

- **Pricing**: Free
- **Availability**: 选 **All Territories** → 然后去掉 **Mainland China**
- **Tax Information**: 会要求填税务信息（个人账号填 W-8BEN，10 分钟）

---

### 🟡 P1 · 上架前建议做但不强求

#### 3.9 托管隐私政策页面

App Store 要求 **Privacy Policy URL**，必须是**公开可访问的网页**，不能是 `.md` 文件。

选项：
- **GitHub Pages**（免费，推荐）：把 `PRIVACY_POLICY.md` 渲染成 HTML，开 GitHub Pages
- **Notion 公开页**（最快）：Notion 粘贴 → Share to web → 拿到公开链接
- **Vercel / Netlify**：适合想要自定义域名

#### 3.10 填 `PRIVACY_POLICY.md` 里的占位符

当前占位符：
- `[你的开发者名称 / 工作室名称 / 姓名]` → 换成你的真实身份
- `[support@your-domain.com]`（出现两处）→ 换成真实支持邮箱

建议注册一个专用支持邮箱（`support@lifeos.app` 之类），不要用私人邮箱。

#### 3.11 Support URL 建一个简单页面

一个说明页，列出：
- 产品简介（2-3 句）
- 联系邮箱
- FAQ（3-5 条）
- 隐私政策链接
- 反馈渠道

可以用 Notion 或 GitHub Pages 做。

#### 3.12 TestFlight 内测

上正式版前先 TestFlight 跑一轮：
1. Archive 上传 build 后会自动到 TestFlight
2. 加自己 / 朋友 5-10 人当内测
3. 跑 3-7 天，收集崩溃 + UX 反馈
4. 改完再提交审核

---

### 🟢 P2 · 上架后慢慢补的

#### 3.13 复盘 Tab 开发（产品核心模块，目前为空）

这是 LifeOS 的核心价值之一，但代码里**还没写**。参考 `PRODUCT_BRIEF.md` 第 5 节。
- 日复盘 / 周复盘 / 月复盘三层
- 强约束：不审判、不 streak、温柔照镜子

#### 3.14 暗色模式

现在只有浅色主题（`CreamTheme`）。需要：
- 定义 `CreamTheme.dark` 色板
- 全局 View 响应 `@Environment(\.colorScheme)`
- 适配 Mascot 猫（暗色下描边颜色调整）

#### 3.15 空状态 / 错误状态

- 每个 Tab 第一次进入的 empty state（用 mascot 不同姿势讲故事）
- 网络失败 / AI 超时的温柔提示文案

#### 3.16 英文本地化

首版简体中文即可；上架稳定后补英文，扩大海外触达。

#### 3.17 辅助功能（Accessibility）

- VoiceOver 标签
- Dynamic Type（字号随系统设置变化）
- 高对比度模式

---

## 4. 已知的卡点和注意事项 ⚠️

### 4.1 Apple Developer 账号历史问题
- 我 Apple ID 之前被加进了 SeeKoo LLC 的 Team
- **必须先从那个 Team 脱离**才能用同一个 Apple ID 注册 Individual
- 或者用**另一个 Apple ID** 注册 Individual（更快）

### 4.2 AI 代理域名 `ai.dogdada.com`
- 跑在 Cloudflare Workers（境外节点）
- **不需要 ICP 备案**（因为只上海外区）
- 腾讯云那边的备案流程已放弃

### 4.3 AI 首次使用同意流程
- 已实现在 `AIConsentSheet.swift`
- 写入 UserDefaults key: `ai.consent.v1`
- 欧盟 GDPR 下这种知情同意是加分项，海外上架需要

### 4.4 XcodeGen 工作流
- 修改 `project.yml` 后要跑 `xcodegen` 重新生成 `.xcodeproj`
- 不要直接改 `.xcodeproj`（会被覆盖）

### 4.5 构建验证命令
```bash
cd /Users/newblue/Projects/openclaw-project/lobster-team/ios-app
xcodebuild -project PersonalSystem.xcodeproj \
  -scheme PersonalSystem \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO build
```

---

## 5. 建议的执行顺序（时间线）

```
Week 1  (等开发者账号 + 做设计)
├─ Day 0    催前公司移除 Team 权限
├─ Day 1    用自己 Apple ID 注册 Individual Developer（$99）
├─ Day 1-3  等审核 + 同时继续和 claude.ai/design 做视觉
├─ Day 3    开发者账号下来 → 建 App ID + Distribution 证书
└─ Day 3-7  实现设计师交付的视觉稿（至少主要 Tab）

Week 2  (打包 + 上架准备)
├─ Day 8    App Store Connect 建 App 记录
├─ Day 9    填 App Info + App Privacy 问卷
├─ Day 9    托管隐私政策（GitHub Pages / Notion）
├─ Day 10   用模拟器截 5 张截图 → Figma 加文案
├─ Day 11   Xcode Archive + 上传 build
├─ Day 12   TestFlight 内测（加自己 + 3-5 个朋友）
└─ Day 13-15 收反馈 + 改 bug

Week 3  (审核 + 上架)
├─ Day 16   正式提交审核
├─ Day 17-19 Apple 审核（24-72 小时）
└─ Day 20   上架 🎉
```

**合计约 3 周**。

---

## 6. 我希望新对话帮我做的事

把这份文档作为背景，按**我当前的阻塞点**来指导我：

1. 如果我当前卡在**开发者账号**那一步 → 帮我催前公司 / 判断要不要换 Apple ID
2. 如果我**账号下来了** → 一步步教我建 App ID、下证书、Archive、上传 build
3. 如果我**在 App Store Connect 填表** → 每个字段告诉我填什么、怎么写转化率高
4. 如果我**要截截图** → 给我模拟器命令 + Figma 截图加文案模板
5. 如果我**审核被拒** → 帮我读拒信、决定是申诉还是改
6. 如果我**想补复盘 Tab** → 和我一起把产品设计落地成代码

---

## 7. 关键文件索引（给新对话上下文用）

| 文件 | 作用 |
|---|---|
| `PRODUCT_BRIEF.md` | 产品全貌（长版）|
| `PRODUCT_BRIEF_SHORT.md` | 产品精简版（给设计师用的那份）|
| `PRIVACY_POLICY.md` | 隐私政策中文版（有占位符）|
| `project.yml` | Xcode 工程配置源头 |
| `Sources/Views/AIConsentSheet.swift` | AI 首次使用同意弹窗 |
| `Sources/Views/GlobalAIInputBar.swift` | 全局 AI 输入框 |
| `Sources/ViewModels/AppStore.swift` | 全局状态管理 |

---

## 8. 给新对话的开场白（可以直接抄）

```
我在做一个叫 LifeOS 的 iOS app，马上要上架 App Store（海外区）。

我把完整的上架清单和项目背景放在 LAUNCH_CHECKLIST.md，请先完整读完，
然后问我一句：「我当前卡在哪一步？」

根据我的回答，从那一步开始带我做，不要跳步，也不要一次讲太多。
每一步做完我会告诉你"下一步"，你再继续。

重要约束：
- 我不是专业开发者，不要假设我懂 Xcode / 证书 / 命令行
- 有命令行操作要贴完整命令，不要只说"执行 xxx"
- 遇到不确定的就先问我，不要假设
- 我的项目路径：/Users/newblue/Projects/openclaw-project/lobster-team/ios-app/

文档在这：
[粘贴 LAUNCH_CHECKLIST.md 全文]
```
