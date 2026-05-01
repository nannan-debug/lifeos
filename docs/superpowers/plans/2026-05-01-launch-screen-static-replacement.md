# 2026-05-01 开屏改为静态版记录

## 背景

开屏方案从“原生静态 L1 + App 内慢生长 L2 动画”调整为“纯静态开屏”。

用户给的新交付包：

`/Users/newblue/Downloads/_ (4).zip`

解压后目录名：

`LifeOS_慢生长_开发包`

本次采用其中的静态方向：

- `SplashScreen_静态稿.html`
- `plant_path.svg`
- `给AI开发用_prompt.md`
- `LaunchScreen.storyboard` 仅作为参数参考，项目仍使用 `project.yml` 里的现代 `UILaunchScreen` 配置

## 最终决策

- 不再使用 App 内 L2 动画层。
- 不新增字体文件，不接入 ZCOOL XiaoWei / Noto Serif SC。
- 除字体外，视觉信息按新交付包的方案 A「奶白极简」实现。
- 为规避 iOS Launch Screen 缓存，静态资源使用新名字：`LaunchStaticV1`。

## 视觉参数

色板来自交付包：

- 背景：`#FBF7EF`
- 植物线条 / 副标题：`#3DA65C`
- 主标题文字：`#263326`
- 叶片 / 花瓣 / 花盆填充：`#EAF3E8`

画面内容：

- 背景为奶白纯色。
- 中央植物来自 `plant_path.svg`，按静态稿约 `180 × 270pt` 呈现。
- Wordmark：`LifeOS`
- 副标题：`观察生活，不优化生活`
- 字体例外：使用系统可用 serif / sans 字体渲染，不打包第三方字体。

## 代码与资源改动

### App 入口

文件：`Sources/App/PersonalSystemApp.swift`

已从：

```swift
FirstRunLaunchGate {
    RootTabView()
}
```

改为：

```swift
RootTabView()
```

### 移除 L2 动画

删除：

`Sources/Views/PlantGrowthLaunchView.swift`

同时删除上一版动态开屏专用分层资源：

- `LaunchPlantFlowerV2`
- `LaunchPlantLeafLeft`
- `LaunchPlantLeafRight`
- `LaunchPlantPot`
- `LaunchPlantStem`
- `PlantStaticV3`

### 新静态资源

新增：

`Sources/App/Assets.xcassets/LaunchStaticV1.imageset/`

包含：

- `launch-static-v1.png`：393 × 852
- `launch-static-v1@2x.png`：786 × 1704
- `launch-static-v1@3x.png`：1179 × 2556

### Launch Screen 配置

文件：`project.yml`

```yaml
UILaunchScreen:
  UIColorName: LaunchBackground
  UIImageName: LaunchStaticV1
  UIImageRespectsSafeAreaInsets: false
```

已运行 `xcodegen` 同步到：

- `Sources/App/Info.plist`
- `PersonalSystem.xcodeproj/project.pbxproj`

## 生成方式

用交付包里的 `plant_path.svg` 组合成 393 × 852 静态 SVG，再用 `rsvg-convert` 输出 1x / 2x / 3x PNG。

后续如果要再次替换静态开屏，建议继续升资源名，例如 `LaunchStaticV2`，不要复用 `LaunchStaticV1`，避免模拟器或 iOS Launch Screen 缓存误判。

## 验证建议

1. 跑 `xcodebuild -project PersonalSystem.xcodeproj -scheme PersonalSystem -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' build`
2. 在模拟器中删除 App 后重装，避免 Launch Screen 缓存。
3. 如仍看到旧开屏，重启模拟器或换新资源名。
