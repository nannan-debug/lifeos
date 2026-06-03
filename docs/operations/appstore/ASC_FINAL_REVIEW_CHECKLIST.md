# LifeOS · App Store 提审前最终核对表

> 用法：提审当天从上到下过一遍，能打勾的都打勾，不能打勾的先不要提交。
> 最后更新：2026-04-26

---

## 1. Pages / 公网链接

- [ ] `https://nannan-debug.github.io/lifeos/` 可以正常打开
- [ ] `https://nannan-debug.github.io/lifeos/privacy.html` 可以正常打开
- [ ] Support 页里邮箱正确：`2944197725@qq.com`
- [ ] Privacy 页里开发者名正确：`nannan guo`

---

## 2. App Store Connect 基础信息

- [ ] App 名称：`LifeOS`
- [ ] Bundle ID：`ai.anna.personalsystem`
- [ ] Primary Language：`Simplified Chinese (zh-Hans)`
- [ ] Category：
  - Primary = `Lifestyle`
  - Secondary = `Productivity`
- [ ] Price = `Free`
- [ ] Availability 已排除 `China mainland`

---

## 3. 文案填写

直接参考 `ASC_COPY_DRAFT_v1.md`：

- [ ] Subtitle 已填写
- [ ] Promotional Text 已填写
- [ ] Description 已填写
- [ ] Keywords 已填写
- [ ] Support URL 已填写
- [ ] Privacy Policy URL 已填写
- [ ] Marketing URL 已决定：
  - 留空，或
  - 暂时与 Support URL 相同

---

## 4. App Privacy

- [ ] 问题 “Do you or your third-party partners collect data from this app?” 已选 `Yes`
- [ ] 只勾选 `User Content -> Other User Content`
- [ ] `Linked to user` = `No`
- [ ] `Used for tracking` = `No`
- [ ] `Used for` = `App Functionality`
- [ ] 其他数据类型全部 `No / Not Collected`
- [ ] Tracking = `No`

---

## 5. Age Rating

- [ ] 全部内容项都选 `None`
- [ ] `Medical/Treatment Information` 选 `None`
- [ ] `User-Generated Content` 选 `No`
- [ ] 最终分级是 `4+`

---

## 6. App Review Information

- [ ] First Name = `nannan`
- [ ] Last Name = `guo`
- [ ] Phone 已填常用手机号（带 `+86`）
- [ ] Email = `2944197725@qq.com`
- [ ] Sign-in required = `No`
- [ ] Demo Account 留空
- [ ] Review Notes 已粘贴

---

## 7. 构建与版本

- [ ] `CFBundleShortVersionString` 正确
- [ ] `CFBundleVersion` 比上一次上传更大
- [ ] Xcode Signing 指向个人账号
- [ ] Archive 成功
- [ ] Build 已上传到 App Store Connect
- [ ] Build Processing 完成，可选进当前版本

---

## 8. 截图

参考 `ASC_SCREENSHOT_PLAN.md`：

- [ ] 已准备 5 张真实截图
- [ ] 已统一状态栏为 `9:41`
- [ ] 已做营销包装层
- [ ] 每张 PNG 尺寸为 `1290 × 2796`
- [ ] 已上传到 `iPhone 6.7" Display`
- [ ] 显示顺序正确

建议顺序：

1. Today
2. AI 展开态
3. Time
4. Inbox / 情绪
5. Today Hero 或 Settings

---

## 9. 最后一眼风险检查

- [ ] 没有出现“医疗诊断 / 治疗 / 改善 ADHD 症状”之类表述
- [ ] 截图没有使用未上线功能
- [ ] 文案和实际 UI 一致
- [ ] 没有写错 AI 供应商名称
- [ ] 隐私政策、Support 页面、ASC 文案三者一致

---

## 10. 提交策略

- [ ] Version Release 选 `Manually release this version`
- [ ] 提交前再读一遍 Review Notes
- [ ] 提交后记录本次版本号和 build 号

---

## 11. 当前推荐提交口径

一句话：

**LifeOS 是一个本地优先的个人记录与观察工具，不是医疗 app；只有用户主动触发 AI 时，当次输入文本才会发送到 Cloudflare Worker 并转发给 DeepSeek 做解析。**
