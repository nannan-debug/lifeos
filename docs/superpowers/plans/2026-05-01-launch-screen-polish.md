# 开屏动效优化实施记录

> 2026-05-01 晚间更新：本记录描述的是上一版“L1 静态 + L2 慢生长动画”实现。当前已按新交付包改为纯静态开屏，最新记录见 `docs/superpowers/plans/2026-05-01-launch-screen-static-replacement.md`。

> 这份记录给后续 AI / 开发者接手用。当前功能已经实现，不是待办计划。

## 一句话总结

在 `feat/launch-screen-polish` 分支上，新增首次启动植物生长动效；原生 Launch Screen 改为奶白背景 + 半透明植物静态图；所有资源已升版命名以避开 iOS Launch Screen 缓存。

## 当前实现

### 1. App 内首次启动动效

文件：`Sources/Views/PlantGrowthLaunchView.swift`

实现点：

- `FirstRunLaunchGate` 包住 `RootTabView`
- 用 `@AppStorage("launch.slowGrowth.v3.seen")` 记录是否播放过
- 首次播放后自动淡出，无按钮
- Reduce Motion 开启时直接展示完成态再淡出
- 动画层使用 asset catalog 图片，而不是手写植物 Shape

当前动画层：

- `LaunchPlantPot`
- `LaunchPlantStem`
- `LaunchPlantLeafLeft`
- `LaunchPlantLeafRight`
- `LaunchPlantFlowerV2`

### 2. 原生 Launch Screen

文件：

- `project.yml`
- `Sources/App/Info.plist`

实现点：

- `UILaunchScreen.UIColorName = LaunchBackground`
- `UILaunchScreen.UIImageName = PlantStaticV3`
- `LaunchBackground` 仍为奶白色
- `PlantStaticV3` 是半透明完成态植物，透明度已烘进 PNG

注意：不要手动改 `Info.plist` 作为 source of truth。要改 `project.yml` 后跑 `xcodegen`。

### 3. 最新资源映射

用户最后指定只更新这两个源：

- `/Users/newblue/Desktop/flower/flower.svg`
- `/Users/newblue/Desktop/flower/plant_growth_layers.svg`

生成结果：

- `flower.svg`
  - 生成到 `Sources/App/Assets.xcassets/LaunchPlantFlowerV2.imageset/flower-v2.png`
  - 显示尺寸：`144x134`
  - PNG 尺寸：`432x402`
- `plant_growth_layers.svg`
  - 生成到 `Sources/App/Assets.xcassets/PlantStaticV3.imageset/plant-static-v3.png`
  - PNG 尺寸：`432x1077`
  - 透明度：`0.35`

其他层暂时仍来自同目录早前文件：

- `stem.svg`
- `leaf-left.svg`
- `leaf-right.svg`
- `pot.svg`

## 复现生成命令

如果后续要重新生成最新花朵：

```bash
/opt/homebrew/bin/rsvg-convert \
  -w 432 \
  -h 402 \
  -o Sources/App/Assets.xcassets/LaunchPlantFlowerV2.imageset/flower-v2.png \
  /Users/newblue/Desktop/flower/flower.svg
```

如果后续要重新生成最新静态 Launch 图：

```bash
perl -pe 's/<svg /<svg opacity="0.35" /' \
  /Users/newblue/Desktop/flower/plant_growth_layers.svg \
  > /tmp/lifeos-launch-assets/plant_static_v3_latest.svg

/opt/homebrew/bin/rsvg-convert \
  -w 432 \
  -h 1077 \
  -o Sources/App/Assets.xcassets/PlantStaticV3.imageset/plant-static-v3.png \
  /tmp/lifeos-launch-assets/plant_static_v3_latest.svg
```

重新生成后跑：

```bash
xcodegen
xcodebuild -project PersonalSystem.xcodeproj -scheme PersonalSystem -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' build
```

## 验证命令

确认当前 Desktop 源文件与仓库生成物一致：

```bash
/opt/homebrew/bin/rsvg-convert \
  -w 432 \
  -h 402 \
  -o /tmp/latest-flower-check.png \
  /Users/newblue/Desktop/flower/flower.svg

shasum -a 256 \
  /tmp/latest-flower-check.png \
  Sources/App/Assets.xcassets/LaunchPlantFlowerV2.imageset/flower-v2.png
```

```bash
perl -pe 's/<svg /<svg opacity="0.35" /' \
  /Users/newblue/Desktop/flower/plant_growth_layers.svg \
  > /tmp/latest-static-check.svg

/opt/homebrew/bin/rsvg-convert \
  -w 432 \
  -h 1077 \
  -o /tmp/latest-static-check.png \
  /tmp/latest-static-check.svg

shasum -a 256 \
  /tmp/latest-static-check.png \
  Sources/App/Assets.xcassets/PlantStaticV3.imageset/plant-static-v3.png
```

两组 hash 应完全一致。

## 已踩过的坑

### Launch Screen 缓存

iOS 会缓存原生 Launch Screen。即使替换了同名 asset，模拟器截图仍可能显示旧图。

本次解决方式：

- 静态图资源从 `PlantStaticV2` 升为 `PlantStaticV3`
- App 内花朵资源从 `LaunchPlantFlower` 升为 `LaunchPlantFlowerV2`
- 首次播放 key 从旧值升为 `launch.slowGrowth.v3.seen`

后续如果再次换图，也建议继续升资源名。

### 版本号

当前 App 已提审，等待审核期间不能随便 bump 版本号。

本次没有改：

- `CFBundleShortVersionString`
- `CFBundleVersion`
- `MARKETING_VERSION`
- `CURRENT_PROJECT_VERSION`

当前仍为 `1.2.0 (build 4)`。

## 当前验证状态

- `xcodegen` 已执行。
- `xcodebuild` 已通过，输出 `BUILD SUCCEEDED`。
- 未 stage，未 commit。
