# LifeOS · 截图拍摄清单

> 用法：拍一张就打一个勾。先拍真实界面，再去做包装图。
> 目标设备：`iPhone 15 Pro Max`
> 最后更新：2026-04-26

---

## 0. 开拍前

- [ ] 模拟器设备是 `iPhone 15 Pro Max`
- [ ] App 用的是最新 build
- [ ] 状态栏统一为 `9:41`
- [ ] 电量显示为满电
- [ ] 信号 / Wi‑Fi 状态正常
- [ ] 界面里没有调试信息、报错弹窗、空白占位 bug

状态栏命令：

```bash
xcrun simctl status_bar booted override \
  --time "9:41" \
  --batteryState charged \
  --batteryLevel 100 \
  --cellularBars 4 \
  --wifiBars 3
```

---

## 1. Shot 01 · Today

- [ ] 页面：Today
- [ ] 有 4-6 个打卡项
- [ ] 不要全部完成，留 2-3 个未完成
- [ ] 页面干净，没有遮挡
- [ ] 对应文案：
  - 大标题：`温柔看住每一天`
  - 副标：`可以漏，可以断，系统永远在等你`

---

## 2. Shot 02 · AI Input

- [ ] 页面：任意页都可以，但推荐 Today
- [ ] 全局 AI 输入框处于展开态
- [ ] 输入框内有自然语言原文
- [ ] 不要真的提交，只展示输入态
- [ ] 推荐输入：
  - `明早9点和妈视频，提前去花店`
- [ ] 对应文案：
  - 大标题：`说一句话，AI 帮你归位`
  - 副标：`不用先选分类再填字段`

---

## 3. Shot 03 · Time

- [ ] 页面：Time
- [ ] 至少有 4 条时间记录
- [ ] 类别不要全一样
- [ ] 时间分布看起来像真实一天
- [ ] 对应文案：
  - 大标题：`看见时间花到哪了`
  - 副标：`只观察，不审判`

---

## 4. Shot 04 · Inbox / Emotion

- [ ] 页面：Inbox / 随记
- [ ] 至少 1 条感受记录
- [ ] 至少 1-2 个情绪标签可见
- [ ] 页面不要过满，留一点呼吸感
- [ ] 对应文案：
  - 大标题：`给情绪起个名字`
  - 副标：`命名情绪，就是调节情绪`

---

## 5. Shot 05 · Closing

- [ ] 页面：Today hero 或 Settings
- [ ] 如果用 Settings，界面要整洁
- [ ] 不要用复盘页
- [ ] 对应文案：
  - 大标题：`慢慢把自己看清楚`
  - 副标：`你的人生脚手架，不是优化工具`

---

## 6. 文件命名建议

- [ ] `lifeos-shot-1.png`
- [ ] `lifeos-shot-2.png`
- [ ] `lifeos-shot-3.png`
- [ ] `lifeos-shot-4.png`
- [ ] `lifeos-shot-5.png`

包装导出后：

- [ ] `lifeos-shot-1-marketing.png`
- [ ] `lifeos-shot-2-marketing.png`
- [ ] `lifeos-shot-3-marketing.png`
- [ ] `lifeos-shot-4-marketing.png`
- [ ] `lifeos-shot-5-marketing.png`

---

## 7. 导出后校验

- [ ] 每张尺寸都是 `1290 × 2796`
- [ ] 标题没换行
- [ ] mascot 没变形
- [ ] 设备外框没裁掉
- [ ] 画面没有超出边界

校验命令：

```bash
for f in ~/Desktop/lifeos-shot-*-marketing.png; do
  sips -g pixelWidth -g pixelHeight "$f" | tail -2
done
```

---

## 8. ASC 上传顺序

- [ ] 先传 Shot 01
- [ ] 再传 Shot 02
- [ ] 再传 Shot 03
- [ ] 再传 Shot 04
- [ ] 最后传 Shot 05

---

## 9. 不要做的事

- [ ] 不要用 Claude 凭空画 UI
- [ ] 不要用未上线功能截图
- [ ] 不要把时间、状态栏、语言风格做得前后不一致
- [ ] 不要上传尺寸不对的图
