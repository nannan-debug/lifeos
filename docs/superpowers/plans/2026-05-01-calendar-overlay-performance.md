# 2026-05-01 日历弹层卡顿修复记录

## 背景

用户反馈：点击顶部日期打开日历时，动画会一卡一卡。

涉及入口：

- 今日页：`Sources/Views/TodayView.swift`
- 时间页：`Sources/Views/TimeView.swift`
- 随记页：`Sources/Views/RootTabView.swift` 内的 `QuickCaptureView`
- 共用日历弹层：`Sources/Views/CreamCalendar.swift`

## 根因判断

主要不是动画曲线本身的问题，而是打开/关闭时有额外计算和合成压力：

1. 旧实现用 `opacity(0)` 隐藏日历弹层，关闭后弹层仍然留在 SwiftUI view tree 里参与布局、diff 和部分绘制。
2. 日期标记 `markerForDate` 是逐日计算的：
   - 今日页逐日调用 `store.hasRecordTrace(on:)`，内部会读取打卡 / 时间 UserDefaults。
   - 时间页逐日调用 `store.timeCategories(on:)`，内部会读取时间 UserDefaults。
   - 随记页逐日遍历 `store.turns.contains { Calendar.current.isDate(...) }`。
3. `dateKey(for:)` 每次都会新建 `DateFormatter`，在日历网格这种高频路径里不划算。

## 本次改动

### 1. 弹层改为条件挂载

三个入口都从“常驻 + opacity 隐藏”改为：

```swift
if showCalendarOverlay {
    calendarOverlay
        .transition(.opacity.combined(with: .move(edge: .top)))
        .zIndex(20)
}
```

这样关闭时日历不再继续占用布局和绘制成本。

### 2. 打开/关闭动画集中到状态切换

顶部日期按钮和日历内部关闭动作都使用 `withAnimation` 包住状态变化，避免依赖整棵 view 上的隐式动画。

### 3. 日期标记按月批量预取

`Sources/ViewModels/AppStore.swift` 新增 helper：

- `calendarDateKey(for:)`
- `recordTraceDateKeys(inMonth:)`
- `timeCategoriesByDateKey(inMonth:)`

打开日历时按当前月份一次性读出标记数据，`markerForDate` 只做内存里的 `Set` / dictionary 查询。

### 4. 复用 DateFormatter

`AppStore.dateKey(for:)` 改为复用静态 `DateFormatter`，减少日历网格渲染时的小对象创建。

## 验证

已通过编译：

```bash
xcodebuild -project PersonalSystem.xcodeproj -scheme PersonalSystem -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' build
```

结果：`BUILD SUCCEEDED`

## 接手注意

- 如果后续继续优化，可以用 Instruments 的 SwiftUI / Time Profiler 看点击顶部日期后的首帧耗时。
- 不要把弹层改回常驻 opacity 隐藏；那是这次卡顿的关键来源之一。
- 如果随记数量未来很多，可以再给 `turns` 增加按月索引 helper，目前已从“每个日期格遍历 turns”降到“打开时遍历一次 turns”。
