# LifeOS

> 一个为 ADHD 人群设计的「人生观察系统」。不是待办清单，不是日记本，而是一套**生活脚手架**——帮助那些难以自我监督、时间感薄弱、情绪识别模糊的人，通过低摩擦的记录 + 可视化的回看，逐渐看清自己。

方法论底层借用了 DBT（辩证行为疗法）的四项核心技能：观察、情绪调节、痛苦耐受、人际有效性。

---

## 产品简介

- 📱 iOS 16+ · SwiftUI · 免费无内购
- 🗂️ 四个 Tab：**今日**（打卡/待办）、**时间**（时间块记录）、**随记**（想法/感受/感恩/做梦）、**设置**
- 🤖 全局 AI 输入框：说一句话，自动归类到对应桶
- 🌿 奶油 + 森林绿调性、趴姿小猫 mascot、空状态不空文案
- 🧘 ADHD 友好：不 streak、不审判、不通知轰炸

详见 [`PRODUCT_BRIEF.md`](./PRODUCT_BRIEF.md) / [`PRODUCT_BRIEF_SHORT.md`](./PRODUCT_BRIEF_SHORT.md)

---

## 技术栈

- **前端**：SwiftUI · Swift 5.9 · iOS 16+
- **项目生成**：[XcodeGen](https://github.com/yonaskolb/XcodeGen)（`project.yml`）
- **数据存储**：本地 UserDefaults（按 userId 分库）
- **AI 后端**：Cloudflare Worker (`ai.dogdada.com`) + Kimi 作为 LLM

---

## 本地跑起来

### 1. 前置依赖

```bash
brew install xcodegen
```

### 2. 克隆 & 配置 Secrets

```bash
git clone https://github.com/nannan-debug/lifeos.git
cd lifeos
cp Secrets.example.swift Sources/Services/Secrets.swift
# 编辑 Sources/Services/Secrets.swift，填入真实 AI secret
# （向 Anna 索取，或部署自己的 Worker 生成）
```

### 3. 生成 Xcode 项目

```bash
xcodegen
open PersonalSystem.xcodeproj
```

### 4. 跑模拟器

Cmd + R 即可。默认 scheme = `PersonalSystem`。

---

## 仓库结构

```
.
├── Sources/
│   ├── App/              # App entry + Info.plist + Assets
│   ├── Models/           # 数据模型
│   ├── ViewModels/       # AppStore（全局状态）
│   ├── Services/         # AIParser + Secrets（gitignored）
│   └── Views/            # 所有 SwiftUI 页面
├── Tests/                # 单元测试
├── Resources/            # 插画 / SVG 素材
├── project.yml           # XcodeGen 配置
├── Secrets.example.swift # Secrets 模板
├── PRODUCT_BRIEF.md      # 产品完整简介
├── CONTRIBUTING.md       # 协作规范
├── VERSIONING.md         # 版本号规范
└── LAUNCH_CHECKLIST.md   # 上架清单
```

---

## 协作须知

- 🌿 分支 & commit 规范：见 [`CONTRIBUTING.md`](./CONTRIBUTING.md)
- 🔢 版本号规范：见 [`VERSIONING.md`](./VERSIONING.md)
- 🚢 上架清单：见 [`LAUNCH_CHECKLIST.md`](./LAUNCH_CHECKLIST.md)

---

## License

MIT © 2026 Anna
