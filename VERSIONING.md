# 版本号规范

## 语义化版本（Semantic Versioning）

格式：`MAJOR.MINOR.PATCH`，例如 `1.2.3`。

| 位 | 什么时候加 1 | 例子 |
|---|---|---|
| **MAJOR** | 大改版，用户感知强烈的变化（UI 重构、数据迁移、去掉旧功能）| 1.0.0 → 2.0.0 |
| **MINOR** | 新功能上线，**向下兼容** | 1.0.0 → 1.1.0（加了复盘模块）|
| **PATCH** | bug 修复 / 小优化，**向下兼容** | 1.0.0 → 1.0.1（修了键盘遮挡 bug）|

---

## iOS 的双轨版本号

Apple 的 Info.plist 里有两个版本字段：

| 字段 | 中文名 | 用途 |
|---|---|---|
| `CFBundleShortVersionString` | Marketing Version | **用户看得到的版本号**，App Store / 设置里显示 |
| `CFBundleVersion` | Build Number | **内部版本号**，TestFlight/App Store 要求每次上传都必须递增 |

### 两者的关系

```
Marketing = 1.0.0       Marketing = 1.0.0       Marketing = 1.0.1
Build     = 1           Build     = 2           Build     = 3
(开发构建)              (TestFlight 第二次)    (上架后第一次修 bug)
```

**规则**：
- Marketing 按 Semver 走（看上面表）
- Build **单调递增**（1, 2, 3, 4…），不跟 Marketing 绑定，永远只增不减

---

## 本项目的版本路线图

| 版本 | 状态 | 说明 |
|---|---|---|
| `1.0.0` (build 1) | ✅ 已上架 | **App Store 首发**（2026-04，App ID `6763877227`）|
| `1.1.0` (build 2) | ⏳ 已提审 | 打卡页 inline 编辑重构（PR #2）—— 2026-04-29 Submit for Review，等待 Apple 审核 |
| `1.1.x` | 之后 | 1.1.0 上架后修 bug（build 继续 +1）|
| `1.x.0` | 之后 | 后续小功能更新（如复盘模块）|
| `2.0.0` | 未来 | 大改版（如云端同步、多账号）|

---

## 怎么改版本号

> ⚠️ **真正的 source of truth 是 `project.yml`，不是 `Info.plist`。**
> 每次 `xcodegen` 都会用 `project.yml` 重新生成 `Info.plist` 和 `pbxproj`——直接改 `Info.plist` 会被下一次 xcodegen 覆盖回去（这是 1.1.0 提审前踩过的坑）。

### 1. 改 `project.yml`（共 4 处版本号要全部同步）

```yaml
targets:
  PersonalSystem:
    info:
      properties:
        CFBundleShortVersionString: 1.1.0     # ← 改这里
        CFBundleVersion: "2"                  # ← 改这里（永远 +1）
        ITSAppUsesNonExemptEncryption: false  # ← 出口合规豁免，已固化，别动
        # ...
    settings:
      base:
        MARKETING_VERSION: 1.1.0              # ← 改这里
        CURRENT_PROJECT_VERSION: 2            # ← 改这里
```

### 2. 跑 xcodegen 同步到 Info.plist 和 pbxproj

```bash
xcodegen
grep -A1 "CFBundleVersion" Sources/App/Info.plist
# 必须看到新版本号，否则别 archive
```

### 3. commit 改动

`project.yml` 和 `PersonalSystem.xcodeproj/project.pbxproj` 都要 stage（pbxproj 是 xcodegen 重新生成的，diff 包含版本号字段更新）。

### 4. 打 git tag（**审核通过且 Release 后再打，不要提前**）

> ⚠️ tag 必须指向真正上线的 commit。如果在 Apple 审核期间提前打 tag，一旦被拒需要新 build，就要 force-update tag 或者 tag 指向错误 commit——都是埋坑。**等 Apple 邮件通知 Ready for Distribution 后再做这步。**

```bash
# 发版前确保 main 最新、干净
git checkout main && git pull

# 打 annotated tag（带消息的 tag，比 lightweight tag 规范）
git tag -a v1.1.0 -m "1.1.0 · 打卡页 inline 编辑 + 分组 CRUD"

# 推 tag 到远程
git push origin v1.1.0
```

### 5. 发 GitHub Release（可选但推荐）

```bash
gh release create v1.0.1 \
  --title "v1.0.1" \
  --notes "## 修复
- 键盘弹起时 FAB 不再盖 tabbar
- 感恩多事件保留在同一条记录

## 改进
- AI 追问后自动合并上下文"
```

---

## Tag 命名

- ✅ `v1.0.0` （推荐，`v` 前缀是业界惯例）
- ❌ `1.0.0` （没有 v 前缀，不够规范）
- ❌ `release-1.0.0` （冗余）

预发布用后缀：
- `v1.0.0-alpha.1` — 内部早期
- `v1.0.0-beta.1` — 公开测试
- `v1.0.0-rc.1` — 发版候选

---

## 一条铁律 🔒

**Build Number 永远不回退、永远不重复。**

Apple 的服务器强制执行这条——如果你第 5 次上传用了 build=3，而 build=4 已经上传过，会直接被拒。最简单的做法：build 永远就是"迄今为止所有 TestFlight/AppStore 上传次数 + 1"。
