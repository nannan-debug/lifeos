# 开屏动效优化设计记录

## 目标

在不影响当前 App Store 审核中 build 的前提下，为 LifeOS 增加一个温柔的首次启动植物生长动效，并让系统原生 Launch Screen 与 App 内动效在视觉上衔接。

## 已锁定决策

- 只在本次资源版本首次打开时播放一次 App 内动画。
- 不加「跳过 / 继续」按钮，动画结束后自动淡出进入主界面。
- 原生 `UILaunchScreen` 保持静态，避免违反 iOS Launch Screen 不能播放动画的限制。
- 原生 Launch Screen 使用奶白背景 `#FBF7EF` + 半透明植物完成态。
- App 内动画使用 SwiftUI 分层图片资源，不再手写植物 Shape。
- 字体先用系统 serif 近似，不引入 `ZCOOL XiaoWei` / `Noto Serif SC` 字体包。
- 不修改 `project.yml` 里的版本号字段，当前仍保持 `1.2.0 (build 4)`。

## 动效规格

- 背景：`#FBF7EF`
- 植物主绿色：沿用资源内颜色
- 正文墨绿：`#263326`
- 茎干：delay `0s`，duration `0.6s`，自下而上 reveal
- 叶片：delay `0.6s`，duration `0.525s`，从连接点 scale + opacity
- 花朵：delay `1.125s`，duration `0.375s`，scale + opacity
- Wordmark：delay `0.8s`，duration `0.8s`，fade + slideUp 6pt
- 整体淡出：delay `1.5s`，duration `0.3s`

## 当前资源来源

最新源文件来自本机：

- `/Users/newblue/Desktop/flower/flower.svg`
- `/Users/newblue/Desktop/flower/plant_growth_layers.svg`
- `/Users/newblue/Desktop/flower/stem.svg`
- `/Users/newblue/Desktop/flower/leaf-left.svg`
- `/Users/newblue/Desktop/flower/leaf-right.svg`
- `/Users/newblue/Desktop/flower/pot.svg`

其中用户最后明确要求：`flower.svg` 和 `plant_growth_layers.svg` 必须用最新版本。当前仓库里的生成物已经用这两个最新文件重新生成，并做过 hash 对比。

## 生成资源

- `Sources/App/Assets.xcassets/LaunchPlantFlowerV2.imageset/flower-v2.png`
  - 来源：`/Users/newblue/Desktop/flower/flower.svg`
  - 尺寸：`432x402`，作为 @3x 资源，对应 SwiftUI 显示尺寸 `144x134`
- `Sources/App/Assets.xcassets/PlantStaticV3.imageset/plant-static-v3.png`
  - 来源：`/Users/newblue/Desktop/flower/plant_growth_layers.svg`
  - 尺寸：`432x1077`，作为 @3x 资源，对应静态完成态
  - 透明度 `0.35` 已烘进 PNG，用于原生 Launch Screen
- `Sources/App/Assets.xcassets/LaunchPlantStem.imageset/stem.png`
- `Sources/App/Assets.xcassets/LaunchPlantLeafLeft.imageset/leaf-left.png`
- `Sources/App/Assets.xcassets/LaunchPlantLeafRight.imageset/leaf-right.png`
- `Sources/App/Assets.xcassets/LaunchPlantPot.imageset/pot.png`

## 缓存坑

iOS / 模拟器会缓存原生 Launch Screen。之前复用 `PlantStatic` / `PlantStaticV2` 时，截图仍可能显示旧植物。为避免误判，当前资源名已经升到：

- 原生 Launch 静态图：`PlantStaticV3`
- App 内花朵层：`LaunchPlantFlowerV2`
- 首次动画播放状态 key：`launch.slowGrowth.v3.seen`

后续如果再次替换 Launch Screen 静态图，建议继续改资源名，而不是复用同名图片。

## 涉及文件

- `Sources/App/PersonalSystemApp.swift`
  - 用 `FirstRunLaunchGate` 包住 `RootTabView`
- `Sources/Views/PlantGrowthLaunchView.swift`
  - App 内首次启动动效
  - 使用 `@AppStorage("launch.slowGrowth.v3.seen")`
  - 支持 Reduce Motion
- `project.yml`
  - `UILaunchScreen.UIImageName = PlantStaticV3`
- `Sources/App/Info.plist`
  - 由 `xcodegen` 同步生成，当前也指向 `PlantStaticV3`
- `PersonalSystem.xcodeproj/project.pbxproj`
  - 由 `xcodegen` 同步生成

## 验证记录

- `xcodegen` 已执行。
- `xcodebuild -project PersonalSystem.xcodeproj -scheme PersonalSystem -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' build` 已通过。
- 当前 `project.yml` 版本号仍为 `1.2.0 (build 4)`，未 bump。
- 已逐像素 hash 校验：
  - 当前 Desktop `flower.svg` 现场渲染结果 = 仓库 `flower-v2.png`
  - 当前 Desktop `plant_growth_layers.svg` 现场渲染结果 = 仓库 `plant-static-v3.png`

