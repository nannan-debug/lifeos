# LifeOS · App Store Connect 文案草稿 v1

> 用法：把每一栏直接复制到 ASC 对应输入框里。字符数都是 ASC 标准下数好的（中文 1 字 = 1 字符）。
> 调性原则：温柔、不审判、不焦虑营销、不堆功能名词。
> 最后更新：2026-04-26

---

## 1. App Name（App 名称，ASC 不可改太多次，谨慎）

```
LifeOS
```

> 说明：如果你已经在 ASC 里建过这个 App，这一栏多半已经填好。如果想加副标提示词进 Name，例如 `LifeOS - 温柔人生系统`，最多 30 字符；但**不建议改**，纯 `LifeOS` 看起来更像一个"产品"而不是"工具"。

---

## 2. Subtitle（副标题，**最多 30 字符**，会显示在 App 名下）

三个方向，选一个，或拼一拼：

| 方向 | 文案 | 字符数 | 适用场景 |
|---|---|---|---|
| **强定位**（推荐） | `为 ADHD 设计 · 温柔的人生观察` | 17 | 直接喊出目标人群，搜 "ADHD" 一进来就认 |
| 强卖点 | `说一句话，AI 帮你温柔归位` | 14 | 突出 AI 输入这个差异化 |
| 强情感 | `温柔看见自己，慢慢就好` | 12 | 适合做品牌但拉新弱 |

**我推荐第一个。** ADHD 关键词同时进了 Subtitle 和 Keywords，对 ASO 是双重加分。

---

## 3. Promotional Text（**最多 170 字符** · 可随时改、不用重审）

显示在 Description 上方第一屏，最显眼的位置。建议放"现在的状态 / 想强调的东西"，**而不是产品介绍**（那是 Description 的活）。

```
不是又一个待办 app。LifeOS 是为 ADHD 人群做的「人生脚手架」——说一句话，AI 帮你把今天的打卡、待办、时间块、心情温柔归位。可以漏，可以断，系统永远在等你回来。
```

字符数：约 88 字 ✅（远低于 170）

> 这条上架后随时能改，不算"宣发文案"也行。比如 1.1 加了暗色模式，可以改成"1.1 上线啦：暗色模式 + ⌘ 复盘 Tab 雏形"

---

## 4. Description（描述，建议 400–800 字）

下面这一整块直接复制：

```
LifeOS 不是又一个生产力 app。

它是为 ADHD（以及任何被"先选分类再填字段"压垮的人）设计的「人生观察系统」——把记录这件事压到最低摩擦：说一句话，AI 自动帮你归位到今天该去的地方。

方法论底层借用了 DBT（辩证行为疗法）的核心理念：先观察，再调节。先看清自己，行动自然发生。

【4 个 Tab，温柔覆盖一天】
· 今日 — 打卡 + 待办，按你自己的标签分组
· 时间 — 时间块记录，看见时间花到哪了
· 随记 — 想法 / 感受 / 感恩 / 做梦，给情绪起个名字
· 设置 — 导出 CSV、清空数据、修改昵称

【全局 AI 输入】
任何页面底部都浮着一个输入框。打一句「明早 9 点和妈视频，提前去花店」，它自己拆成待办 + 时间块。不想联网时，⚡按钮走纯本地解析，一字不外传。

【ADHD 友好的硬承诺】
· 没有连续打卡 streak（断一次就 delete 的是 ADHD）
· 没有「你已经 X 天没打开了」这种通知
· 没有完成率百分比 / 排名 / 跟上周对比
· 任何输入都能空着提交
· 用「留白」「明天再说」「先歇一歇」代替「未完成」「失败」

【关于隐私】
· 数据只存你 iPhone 本地，卸载即清空
· 只有你主动按下 ↑ 触发 AI 时，当次输入文本才会发往我们的 Cloudflare 服务器，转给 DeepSeek 解析后立刻丢弃
· 不收集 IDFA / 不接统计 SDK / 不跟踪 / 无广告 / 无内购

献给所有「明明很努力，只是大脑不这么工作」的你。
温柔地照镜子，慢慢把自己看清楚。
```

字符数：约 530 字 ✅

---

## 5. Keywords（关键词，**100 字符上限**，逗号分隔、**逗号前后不要空格**）

```
ADHD,注意力,多动,觉察,DBT,心理咨询,待办,打卡,时间记录,日记,随记,情绪,心情,习惯,自我管理,焦虑,冥想,时间块,生活记录,心理健康,拖延症,番茄钟,AI助手
```

字符数：86 / 100 ✅（剩 14 字符余量，将来想加再加）

**为什么这么选**（不光是堆词，下面是策略）：
- **ADHD / DBT / 觉察 / 心理咨询 / 焦虑 / 拖延症** —— 你的核心人群关键词，竞争小、转化高
- **待办 / 打卡 / 时间记录 / 日记 / 时间块** —— 高搜索量品类词，蹭流量
- **自我管理 / 冥想 / 心理健康** —— 周边相关词，扩大触达
- **AI助手 / 番茄钟** —— 当下热词，加点曝光

> Apple 会自动把 App Name + Subtitle 里的词与 Keywords **合并匹配**，所以 Subtitle 里已经有的「ADHD / 人生观察」其实可以从 Keywords 里抠出去省字符 —— 我留着 ADHD 是因为它太核心了，重一遍没坏处。

---

## 6. Support URL（**必填** · 公开访问的网页）

推荐直接用仓库内的 GitHub Pages 页面。

如果仓库是 `nannan-debug/lifeos`，并且在 GitHub 里开启了 Pages（`main` 分支 `/docs`），那么：

- Support URL：`https://nannan-debug.github.io/lifeos/`
- Privacy Policy URL：`https://nannan-debug.github.io/lifeos/privacy.html`

最低限度要包含：

```markdown
# LifeOS · 帮助与支持

LifeOS 是一个为 ADHD 人群设计的人生观察系统。
如果你在使用中遇到任何问题、想反馈 bug 或新功能，欢迎随时联系。

## 联系方式
邮箱：2944197725@qq.com
（一般 24-48 小时内回复，单人维护，请耐心）

## 常见问题

**Q：我的数据存在哪？**
A：100% 存在你的 iPhone 本地。卸载 App = 全部清空。我们的服务器永远不持久化你的内容。

**Q：AI 是必须用的吗？**
A：不是。任何记录都可以纯手动添加。AI 是「降低记录摩擦」的工具，不是必经之路。

**Q：能导出我的数据吗？**
A：能。设置 → 关于你 → 导出 CSV，所有打卡 / 待办 / 时间记录 / 随记一键导出。

**Q：会不会上架内购？**
A：1.0 完全免费、无内购、无广告。未来即使加内购，原有功能也永远免费。

## 隐私政策
👉 [LifeOS Privacy Policy](https://nannan-debug.github.io/lifeos/privacy.html)
```

填到 ASC 的 Support URL 那一栏：`https://nannan-debug.github.io/lifeos/`

---

## 7. Marketing URL（可选 · 不填也能过审）

没 landing page 的话**直接留空**。审核员不会因为这一栏空就拒。

如果想偷懒：把 Support URL 同一个链接也填进来。

---

## 8. Category（类目）

| 栏位 | 推荐 | 理由 |
|---|---|---|
| Primary | **Lifestyle（生活）** | LifeOS 不是"完成更多任务"的工具，是"看见生活"的工具，归 Lifestyle 更贴 |
| Secondary | **Productivity（效率）** | 蹭一点效率类的搜索流量，但不让审核员拿"医疗 app"标准来审你 |

> ⚠️ **千万不要选 Health & Fitness（健康与健身）**。一旦进这个类目，Apple 会按"健康类 app"严格审，要求医学免责声明、专业资质背书等等，会让你折腾一周。

---

## 9. Age Rating（年龄分级）

会问你 ~12 道是非题。**全部选"无 / None"** 即可：

- Cartoon or Fantasy Violence: None
- Realistic Violence: None
- Sexual Content or Nudity: None
- Profanity or Crude Humor: None
- Alcohol, Tobacco, or Drug Use: None
- Mature/Suggestive Themes: None
- Horror/Fear Themes: None
- Medical/Treatment Information: **None**（重要 —— 虽然提到 ADHD/DBT，但 LifeOS 不诊断也不治疗，只是"记录工具"）
- Gambling: None
- Unrestricted Web Access: None
- User-Generated Content: **No**（用户笔记只存本地，不分享给其他用户）

最终结果：**4+** ✅

---

## 10. App Privacy（"营养标签"问卷，最容易出错的地方）

直接照下面填：

### Q：Do you or your third-party partners collect data from this app?
**Yes**（即使你"不收集"，因为 AI 调用算"数据收集"，老老实实选 Yes 更安全）

### Data Types Collected

只勾 **User Content → Other User Content**：
- **Linked to user**: No
- **Used for tracking**: No
- **Used for**: App Functionality
- 详细说明（英文，可粘）：
  ```
  When the user explicitly taps the AI parse button, the text they typed in the input box is sent to our Cloudflare Worker proxy and then forwarded to DeepSeek for natural-language parsing. The text is not stored on our server and is not linked to any user identifier.
  ```

其他全部 **No / Not Collected**：
- Contact Info: No
- Health & Fitness: No
- Financial Info: No
- Location: No
- Sensitive Info: No
- Contacts: No
- Browsing History: No
- Search History: No
- Identifiers: No
- Purchases: No
- Usage Data: No
- Diagnostics: No
- Other Data: No

### Tracking
**No, we do not track users.**

---

## 11. Pricing and Availability

- **Price**: Free
- **Availability**:
  1. 先选 "Available in all territories"（全选）
  2. 再单独取消勾 **China mainland**
- **Pre-Order**: 不开（首版没必要）
- **Educational Discount**: 不开（免费 app 用不上）

---

## 12. App Review Information（提审时填）

| 字段 | 填什么 |
|---|---|
| First Name | nannan |
| Last Name | guo |
| Phone | 你常用的手机号（带国家码 +86）|
| Email | 2944197725@qq.com |
| Sign-in required | **No** |
| Demo Account | 留空 |
| Notes | 见下面 ↓ |

**Notes（给审核员的英文留言，重要！）**：

```
This app is a personal life-logging tool with no user account system. 
All data is stored locally in UserDefaults on the device — no server-side 
user records exist.

The "AI parse" feature (the upward-arrow button in the global input bar) 
sends the current input text to our Cloudflare Worker proxy 
(ai.dogdada.com), which forwards it to DeepSeek for natural-language 
parsing and returns a structured result. We do not persist this text on 
our server. Users see a one-time consent dialog before the first AI call 
(see AIConsentSheet). They can also use the lightning-bolt button next to 
it for fully local, offline parsing.

Privacy Policy: https://nannan-debug.github.io/lifeos/privacy.html

The app does not contain any medical, diagnostic, or treatment-related 
features. Mentions of "ADHD" / "DBT" in marketing copy refer to the 
target audience and methodology inspiration only — LifeOS is a personal 
journaling tool, not a medical app.

Thank you for your review!
```

---

## 13. Version Release（首版）

选 **Manually release this version**（不要勾自动发布）。
理由：批准通过的瞬间你能选择按下"发布"，给自己一个仪式感 + 留出朋友圈/小红书发布的窗口。

---

## 14. What's New in This Version（"更新内容"，首版可选填）

```
1.0 ｜ LifeOS 第一次见面。

· 今日 / 时间 / 随记 / 设置 四个 Tab
· 全局 AI 输入框 —— 说一句话，自动归位
· 数据 100% 本地存储，可一键导出 CSV

慢慢来，不急。
```

---

# 我没帮你定的两个东西

需要你自己决定 / 准备：

1. **确认 GitHub Pages 已开启** —— 只有 Pages 真正打开后，`https://nannan-debug.github.io/lifeos/` 和 `/privacy.html` 才会变成可访问链接。

2. **联系手机号** —— ASC 的 App Review Information 那一栏会要，海外审核员有时会真的打电话（罕见）。建议填你常用的手机号，加 `+86` 国家码。

---

> 全文写完，约 30 分钟阅读 / 5 分钟复制粘贴 / 0 分钟做决策（除了 §2 三选一）。
