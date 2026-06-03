# LifeOS · App Store 截图执行方案 v1

> 用 claude.ai/design 出营销截图包装层，真实截图来自 iOS 模拟器。
> 最后更新：2026-04-26

---

## 关键约束（先看，后面所有决策都基于这条）

Apple 审核条款 5.0 + 4.0 要求：**截图必须真实代表 app 内容**。
所以 **不能** 让 Claude 凭空画一份"假装是 LifeOS 真实界面"的截图 —— 那种会被打回。

✅ 合法路径：**真实模拟器截图 + Claude design 包装层**（米色底 + 标语 + mascot + 设备外框）
❌ 禁路：纯 Claude 想象出来的"未来版"界面、含未开发的复盘 Tab 截图

---

## 整体工作流

```
① 模拟器跑出 5 张干净的真实截图（各 1290×2796）
        ↓
② Claude design 出一个营销截图模板 Artifact（HTML/React）
   把真实截图当 <img> 塞进去，加标语 + mascot + 米底
        ↓
③ 浏览器把 Artifact 截成最终 PNG，sips 强制压回 1290×2796
        ↓
④ 5 张拖进 ASC 的 6.5"/6.7" Display 槽
```

---

## Step ①：跑 5 张真实截图

### 模拟器选型
**iPhone 15 Pro Max**（原生分辨率 1290×2796，正好等于 ASC 6.7" 槽位，不用任何缩放）

### 5 张拍法（按 ADHD 叙事弧线，**不是**按 Tab 顺序）

| # | 拍哪一屏 | 怎么准备数据 |
|---|---|---|
| 1 | TodayView | 故意留几个未打卡（不要全勾，体现"留白"是 OK 的）|
| 2 | GlobalAIInputBar **展开态** | 输入框里输入「明早 9 点和妈视频，提前买花」，**但还没按提交**，让用户能看见自然语言原文 |
| 3 | TimeView | 当天有 4-5 个不同类别的时间块，颜色错开，体现一天的密度 |
| 4 | InboxView | 至少一条「感受」类型 + 1-2 个情绪标签，体现情绪归位 |
| 5 | TodayView 顶部 hero（带 mascot 的早晨问候 / 空状态）或 SettingsView "关于你" | 收尾用，**不要用复盘 Tab**（还没开发，会被 Apple 抓到拒）|

### 截屏命令

```bash
# 在 Xcode 启动 iPhone 15 Pro Max 模拟器后

# 法一：模拟器窗口前台时按 Cmd + S，存到桌面
# 法二：命令行
xcrun simctl io booted screenshot ~/Desktop/lifeos-shot-1.png
xcrun simctl io booted screenshot ~/Desktop/lifeos-shot-2.png
# ... 1 到 5
```

---

## Step ②：Claude design Prompt（直接复制）

打开 https://claude.ai/ → 新建对话，粘下面这一整段：

````
帮我在 Artifact 里做一个 App Store 营销截图模板（HTML + 内联 CSS）。
画布严格 1290×2796 像素。整体调性：温柔、不焦虑、ADHD 友好。

风格规范：
- 背景：米色 cream（#F8F1E4 系，带一点温暖偏黄，参考 Notion 的 Beige）
- 主色：墨绿描边色（#2D4A3E 系），用于副标和点缀线
- 字体：iOS 系统字 -apple-system, "PingFang SC", sans-serif
- 圆角：所有卡片 24px

布局（从上到下）：
1. 顶部 200px：一行大标题（中文，48-56pt 半粗），下面一行小副标（22pt regular，墨绿）
2. 中部：一台 iPhone 15 Pro Max 的简化设备外框（圆角 60px，1.5px 黑色描边，去 home indicator），框内嵌入 <img id="screenshot" src=""> 占位（图源由我后面替换为真实截图，1290×2796 → 在框内等比缩到约 1000px 宽）
3. 底部 180px：左下角放一个手绘趴猫 emoji 或 SVG（先用 🐱 占位，等会儿我替换成 cat-lay.svg），右下小字 "LifeOS"

要做成"模板组件"：
- 顶部用两个 input：一个填大标题，一个填副标
- 文件选择器：上传一张本地 png，自动塞进 #screenshot
- 底部一个按钮 "Export PNG"，点击后用 html2canvas 把整个 1290×2796 画布导出成同尺寸 png

5 张截图要轮流套这个模板，先把模板做出来给我。
````

> 上 prompt 拿到 Artifact 之后，**保留同一对话**继续提需求微调（"标题字小一号"、"米色再淡一点"、"mascot 换到右下"）。Claude 会基于已有 Artifact 改而不是重画。

---

## Step ②.5：上传真正的 mascot

在你项目里有现成的 mascot 文件可以替换占位 emoji：

- `Resources/Mascot/` 下的原始素材
- `Sources/App/cat-lay.svg`（趴猫，最适合做装饰）
- `Sources/App/cat-lying.png`（带描边版）

任选一个上传给 Claude，让它把模板里的 🐱 换成真实 mascot。

---

## Step ③：5 张截图的标题文案（直接复制）

按 ADHD 叙事弧线排，每条 ≤14 字 + 副标 ≤20 字，确保 1290 宽度下不换行：

| # | 大标题 | 副标 | 配的真实截图 |
|---|---|---|---|
| 1 | 温柔看住每一天 | 可以漏，可以断，系统永远在等你 | TodayView |
| 2 | 说一句话，AI 帮你归位 | 不用先选分类再填字段 | GlobalAIInputBar 展开态 |
| 3 | 看见时间花到哪了 | 只观察，不审判 | TimeView |
| 4 | 给情绪起个名字 | 命名情绪，就是调节情绪 | InboxView |
| 5 | 慢慢把自己看清楚 | 你的人生脚手架，不是优化工具 | TodayView hero / SettingsView |

---

## Step ④：导出 + 校验

模板里那个 "Export PNG" 用的是 html2canvas，**导出尺寸偶尔会差几像素**（浏览器渲染抖动）。上传 ASC 之前过一道：

```bash
# 用 sips 强制压回 1290×2796（macOS 自带，免装）
cd ~/Desktop
for i in 1 2 3 4 5; do
  sips -z 2796 1290 lifeos-shot-${i}-marketing.png
done
```

验收检查：

```bash
# 确认每张都是 1290×2796
for f in ~/Desktop/lifeos-shot-*-marketing.png; do
  sips -g pixelWidth -g pixelHeight "$f" | tail -2
done
```

5 张都过 → 拖进 ASC 的 iPhone 6.7" Display 槽（**至少 3 张，最多 10 张，建议 5 张**）。

---

## 常见坑预警

| 坑 | 怎么避 |
|---|---|
| 截图里有时间显示（11:25）每张都不一样 | 模拟器跑 `xcrun simctl status_bar booted override --time "9:41"`（苹果默认时间）统一 |
| 状态栏电量、信号都"好看" | 同上一条命令带 `--batteryLevel 100 --cellularBars 4 --wifiBars 3` |
| Mascot 在大屏上被压扁 | claude.ai 模板里 mascot 用 `width: auto` + `max-height` 双控 |
| Cream 米色在不同显示器看起来不一样 | 统一以你 `CreamTheme.swift` 里实际用的色值为准（先去 Xcode 里查一下 hex）|
| 标题在 1290 宽度下换行了 | 标题最多 14 个汉字、副标最多 20 个；超了就缩 |

### 一键给 5 张截图统一状态栏

```bash
xcrun simctl status_bar booted override \
  --time "9:41" \
  --batteryState charged \
  --batteryLevel 100 \
  --cellularBars 4 \
  --wifiBars 3
```

每次模拟器重启都要重跑一次。

---

## 如果想省事再省事：3 张就交差

ASC 6.7" 槽位 **最少 3 张**，最多 10 张。预算紧的话只做 1 / 2 / 4 三张（核心叙事够了），拒审风险一样低。

---

## 我没帮你定的两个东西

1. **CreamTheme 的真实 hex** —— 你去 `Sources/Views/CreamTheme.swift` 里查到主背景色和墨绿色的 hex，把上面 prompt 里的 `#F8F1E4` / `#2D4A3E` 替换成真实值，能保证营销截图的米色和 app 里完全一致
2. **是不是要做 6.5" 那一档** —— 你截图里 ASC 显示的是 6.5" Display；如果你跟着这份方案截 6.7"（1290×2796），ASC 会自动接受作为 6.5" 的"largest screen substitute"。**1 套截图覆盖两档**，省事。

---

> 完工标志：5 张 1290×2796 PNG 在桌面 → 拖进 ASC → 保存 → 完成 ✅
