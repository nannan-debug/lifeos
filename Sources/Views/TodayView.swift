import SwiftUI
import UIKit

struct TodayView: View {
    @EnvironmentObject var store: AppStore

    @State private var displayMonth = Date()
    @State private var showCalendarOverlay = false
    @State private var quoteOffset: Int = 0

    // A 方案：顶部分段 "check" | "todo"
    @State private var segment: String = "check"

    // 打卡项管理面板
    @State private var showCheckManager = false

    // 折叠/展开的 tag 集合（持久化到 AppStorage，重新打开保持状态）
    @AppStorage("checks.collapsedTags") private var collapsedTagsRaw: String = ""

    // 待办输入
    @State private var newTodoTitle = ""

    // 新建待办详细面板（仿苹果日历）
    @State private var showNewTodoSheet = false

    // 编辑已有待办
    @State private var editingTask: TaskEntry?

    private let calendar = Calendar.current

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                List {
                    if segment == "check" {
                        checkSection
                    } else {
                        todoSection
                    }
                }
                .toolbar(.hidden, for: .navigationBar)
                .listStyle(.insetGrouped)
                .tint(CreamTheme.green)
                .scrollContentBackground(.hidden)
                .background(CreamTheme.glassStrong)
                .safeAreaInset(edge: .top, spacing: 0) {
                    VStack(spacing: 8) {
                        todayTopDateBar
                        segmentPicker
                    }
                }

                calendarOverlay
                    .compositingGroup()
                    .opacity(showCalendarOverlay ? 1 : 0)
                    .offset(y: showCalendarOverlay ? 0 : -16)
                    .allowsHitTesting(showCalendarOverlay)
                    .animation(.easeOut(duration: 0.22), value: showCalendarOverlay)
                    .zIndex(20)
            }
            .onAppear {
                displayMonth = startOfMonth(for: store.selectedDate)
            }
            .onChange(of: store.selectedDate) { newDate in
                let m = startOfMonth(for: newDate)
                if !calendar.isDate(m, equalTo: displayMonth, toGranularity: .month) {
                    displayMonth = m
                }
            }
            .sheet(isPresented: $showCheckManager) {
                CheckItemManagerSheet()
                    .environmentObject(store)
            }
            .sheet(isPresented: $showNewTodoSheet) {
                TodoEditorSheet(mode: .create(defaultDate: store.selectedDate))
                    .environmentObject(store)
            }
            .sheet(item: $editingTask) { task in
                TodoEditorSheet(mode: .edit(task: task))
                    .environmentObject(store)
            }
        }
        .creamBackground()
    }

    // MARK: - Segment Picker

    private var segmentPicker: some View {
        Picker("", selection: $segment) {
            Text("打卡").tag("check")
            Text("待办").tag("todo")
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 12)
    }

    // MARK: - Check Section (existing content refactored out)

    @ViewBuilder
    private var checkSection: some View {
        Section {
            motivationalCard
                .listRowInsets(EdgeInsets(top: 3, leading: 6, bottom: 3, trailing: 6))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }

        // 所有 tag 放进同一个 Section，用细分隔线分组，避免 Section 间距断层
        Section {
            ForEach(Array(groupedCheckTags.enumerated()), id: \.element) { idx, tag in
                // 非首个分组前加一条细线
                if idx > 0 {
                    Divider()
                        .overlay(Color.black.opacity(0.08))
                        .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

                collapsibleHeader(for: tag)

                if !isTagCollapsed(tag) {
                    ForEach(store.checkItems.filter { $0.tag == tag }) { item in
                        checkRow(item)
                    }
                }
            }
        }

        // 管理打卡项按钮
        Section {
            Button {
                showCheckManager = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.footnote.weight(.semibold))
                    Text("管理打卡项")
                        .font(.footnote.weight(.medium))
                }
                .foregroundStyle(CreamTheme.green.opacity(0.75))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .listRowInsets(EdgeInsets(top: 4, leading: 6, bottom: 4, trailing: 6))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    /// tag → SF Symbol 映射（早/晚 用太阳月亮，其他用 tag 图标）
    private func iconName(for tag: String) -> String {
        switch tag {
        case "早", "早上", "晨间", "morning": return "sun.max.fill"
        case "晚", "晚上", "夜间", "evening": return "moon.stars.fill"
        case "默认": return "checklist"
        default: return "tag.fill"
        }
    }

    /// 仿 iOS 提醒事项的可折叠组头：图标 + 大字 + 右侧计数 + 独立 chevron
    @ViewBuilder
    private func collapsibleHeader(for tag: String) -> some View {
        let collapsed = isTagCollapsed(tag)
        let total = store.checkItems.filter { $0.tag == tag }.count
        let doneCount = store.checkItems.filter { $0.tag == tag && $0.done }.count
        let allDone = total > 0 && doneCount == total

        Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                toggleCollapse(tag)
            }
        } label: {
            HStack(spacing: 12) {
                // 图标胶囊：不同 tag 不同颜色基调
                ZStack {
                    Circle()
                        .fill(CreamTheme.green.opacity(allDone ? 0.20 : 0.12))
                        .frame(width: 30, height: 30)
                    Image(systemName: iconName(for: tag))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(CreamTheme.green)
                }

                Text(tag)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)

                Spacer()

                Text("\(doneCount)/\(total)")
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)

                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .rotationEffect(.degrees(collapsed ? -90 : 0))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 4, leading: 6, bottom: 2, trailing: 6))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    /// 单个打卡行（大号字，仿提醒事项）
    @ViewBuilder
    private func checkRow(_ item: DailyCheckItem) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                store.toggle(item)
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(item.done ? CreamTheme.green : Color(.tertiaryLabel))

                Text(item.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(item.done ? .secondary : .primary)
                    .strikethrough(item.done, color: .secondary)

                Spacer()
            }
            .padding(.leading, 28)   // 左边缩进，让打卡行视觉上挂在组头下面
            .padding(.trailing, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 0, leading: 6, bottom: 0, trailing: 6))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Collapsed tag helpers

    private var collapsedTags: Set<String> {
        Set(collapsedTagsRaw.split(separator: ",").map(String.init).filter { !$0.isEmpty })
    }

    private func isTagCollapsed(_ tag: String) -> Bool {
        collapsedTags.contains(tag)
    }

    private func toggleCollapse(_ tag: String) {
        var set = collapsedTags
        if set.contains(tag) { set.remove(tag) } else { set.insert(tag) }
        collapsedTagsRaw = set.sorted().joined(separator: ",")
    }

    /// 当前展示的 tag 顺序：按首次出现顺序
    private var groupedCheckTags: [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for item in store.checkItems where !seen.contains(item.tag) {
            seen.insert(item.tag)
            ordered.append(item.tag)
        }
        return ordered
    }


    // MARK: - Todo Section

    private var pendingTasks: [TaskEntry] {
        store.tasks.filter { $0.status != "已完成" }
    }

    private var doneTasks: [TaskEntry] {
        store.tasks.filter { $0.status == "已完成" }
    }

    @ViewBuilder
    private var todoSection: some View {
        // 新建待办 —— 两种方式
        Section {
            // 快速输入（只取标题，默认今天、全天、无优先级）
            HStack(spacing: 10) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(CreamTheme.green.opacity(0.8))

                TextField("快速新增…（回车添加）", text: $newTodoTitle)
                    .textFieldStyle(.plain)
                    .submitLabel(.done)
                    .onSubmit(commitNewTodo)

                if !newTodoTitle.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button("添加", action: commitNewTodo)
                        .buttonStyle(.borderedProminent)
                        .tint(CreamTheme.green)
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.75))
            )
            .listRowInsets(EdgeInsets(top: 6, leading: 6, bottom: 3, trailing: 6))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            // 详细新建（打开仿苹果日历面板）
            Button {
                showNewTodoSheet = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(CreamTheme.green)
                    Text("详细新建（含时间、优先级、备注）")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.75))
                )
                .contentShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .listRowInsets(EdgeInsets(top: 3, leading: 6, bottom: 6, trailing: 6))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }

        // 未完成
        if !pendingTasks.isEmpty {
            Section {
                ForEach(pendingTasks) { task in
                    todoRow(task)
                }
            } header: {
                Text("待办 · \(pendingTasks.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        } else {
            Section {
                Text("今天没有待办，先去打卡或加一条吧 🌱")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 16)
                    .listRowInsets(EdgeInsets(top: 8, leading: 6, bottom: 8, trailing: 6))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }

        // 已完成
        if !doneTasks.isEmpty {
            Section {
                ForEach(doneTasks) { task in
                    todoRow(task)
                }
            } header: {
                Text("已完成 · \(doneTasks.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func todoRow(_ task: TaskEntry) -> some View {
        let done = task.status == "已完成"
        HStack(alignment: .top, spacing: 12) {
            // 勾选框（独立热区）
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    store.toggleTask(task)
                }
            } label: {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(done ? CreamTheme.green : Color(.tertiaryLabel))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // 标题/详情区（点击打开编辑面板）
            Button {
                editingTask = task
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(done ? .secondary : .primary)

                    if !task.detail.isEmpty {
                        Text(task.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    if let metaLine = metaLineFor(task) {
                        HStack(spacing: 6) {
                            if !task.priority.isEmpty {
                                badge(task.priority, tint: priorityTint(task.priority))
                            }
                            Text(metaLine)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.75))
        )
        .listRowInsets(EdgeInsets(top: 3, leading: 6, bottom: 3, trailing: 6))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                store.removeTask(id: task.id)
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    /// 组装时间/日期元信息行（比如 "今天 · 全天" 或 "4月18日 · 09:00-10:30"）
    private func metaLineFor(_ task: TaskEntry) -> String? {
        var parts: [String] = []
        if !task.dueDate.isEmpty {
            parts.append(shortDateLabel(task.dueDate))
        }
        if task.isAllDay {
            if !task.dueDate.isEmpty { parts.append("全天") }
        } else if !task.startTime.isEmpty {
            if task.endTime.isEmpty {
                parts.append(task.startTime)
            } else {
                parts.append("\(task.startTime)-\(task.endTime)")
            }
        }
        if parts.isEmpty && task.priority.isEmpty { return nil }
        // 有 priority 但没时间时也要返回空字符串，让上层渲染 badge
        return parts.joined(separator: " · ")
    }

    /// "2026-04-18" → "4月18日"；今天 → "今天"；明天 → "明天"
    private func shortDateLabel(_ key: String) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd"
        guard let d = df.date(from: key) else { return key }
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "今天" }
        if cal.isDateInTomorrow(d) { return "明天" }
        if cal.isDateInYesterday(d) { return "昨天" }
        let out = DateFormatter()
        out.locale = Locale(identifier: "zh_CN")
        out.dateFormat = "M月d日"
        return out.string(from: d)
    }

    private func badge(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(tint.opacity(0.12)))
    }

    private func priorityTint(_ p: String) -> Color {
        switch p {
        case "高": return .red
        case "中": return .orange
        case "低": return .blue
        default: return .secondary
        }
    }

    private func commitNewTodo() {
        let clean = newTodoTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        _ = store.addTask(title: clean)
        newTodoTitle = ""
    }

    // MARK: - Motivational Card

    private var motivationalCard: some View {
        motivationalCardView
            .listRowInsets(EdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6))
            .listRowBackground(Color.clear)
    }

    private var motivationalCardView: some View {
        let quote = dailyQuote
        return ZStack(alignment: .bottomTrailing) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(CreamTheme.green)
                    Text("每日一言")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(CreamTheme.green)

                    Spacer()

                    // 换一条按钮（图标 only，顶部没有小猫，可以顶到右边缘）
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                            quoteOffset += 1
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(CreamTheme.green.opacity(0.8))
                            .frame(width: 26, height: 26)
                            .background(
                                Circle().fill(CreamTheme.green.opacity(0.1))
                            )
                    }
                    .buttonStyle(.plain)
                }

                Text(quote.text)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    // 仅为小猫头部腾出空间；小猫主要在右下，这里留少量即可
                    .padding(.trailing, 56)
                    .id(quoteOffset) // 让文字切换时触发过渡

                HStack(spacing: 8) {
                    Rectangle()
                        .fill(CreamTheme.green.opacity(0.3))
                        .frame(width: 2, height: 14)

                    Text("— \(quote.author)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 0)
                }
                .padding(.trailing, 72)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.94))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(CreamTheme.green.opacity(0.25), lineWidth: 0.5)
            )

            MascotCatAssetView(stroke: CreamTheme.green)
                .frame(width: 72, height: 66)
                .alignmentGuide(.bottom) { d in d[.bottom] }
                .offset(x: 6, y: 2)
        }
        .padding(.trailing, 6)
        .padding(.bottom, 4)
        .shadow(color: .black.opacity(0.035), radius: 8, x: 0, y: 3)
    }

    // MARK: - Famous Quotes

    private struct Quote {
        let text: String
        let author: String
    }

    private var dailyQuote: Quote {
        let quotes: [Quote] = [
            // Warren Buffett
            Quote(text: "别人贪婪时我恐惧，别人恐惧时我贪婪。", author: "巴菲特"),
            Quote(text: "如果你不愿持有一只股票十年，那就连十分钟也不要持有。", author: "巴菲特"),
            Quote(text: "永远不要用借来的钱去投资。", author: "巴菲特"),
            Quote(text: "最好的投资就是投资你自己。", author: "巴菲特"),
            Quote(text: "诚实是一种非常昂贵的天赋，别指望从廉价的人那里得到。", author: "巴菲特"),
            Quote(text: "风险来自于你不知道自己在做什么。", author: "巴菲特"),
            Quote(text: "你人生中最重要的决定，是跟什么人结婚。", author: "巴菲特"),
            // Elon Musk
            Quote(text: "当某件事足够重要时，即使胜算不在你这边，你也要去做。", author: "马斯克"),
            Quote(text: "坚持是最重要的，除非你被迫放弃，否则永远不要放弃。", author: "马斯克"),
            Quote(text: "失败是一种选项，如果你从未失败，说明你不够创新。", author: "马斯克"),
            Quote(text: "第一步是确认某件事是可能的，然后概率自然会发生。", author: "马斯克"),
            Quote(text: "我宁愿乐观地犯错，也不愿悲观地正确。", author: "马斯克"),
            Quote(text: "生活不能只是关于解决一个又一个糟糕的问题，你需要那些让你每天早上兴奋醒来的事。", author: "马斯克"),
            // Steve Jobs
            Quote(text: "求知若饥，虚心若愚。", author: "乔布斯"),
            Quote(text: "你的时间有限，不要浪费在过别人的生活上。", author: "乔布斯"),
            Quote(text: "你无法预先把点点滴滴串连起来，唯有回头看时才会明白那些点滴如何串在一起。", author: "乔布斯"),
            Quote(text: "创新就是把事物区分为领导者和追随者。", author: "乔布斯"),
            Quote(text: "如果今天是我生命的最后一天，我会想做我今天要做的事吗？", author: "乔布斯"),
            Quote(text: "伟大的事业不是靠力气完成的，而是靠坚持。", author: "乔布斯"),
            // Jeff Bezos
            Quote(text: "聪明是一种天赋，善良是一种选择。", author: "贝佐斯"),
            Quote(text: "如果你从不犯错，说明你没有足够努力。", author: "贝佐斯"),
            Quote(text: "你的品牌就是别人不在场时对你的评价。", author: "贝佐斯"),
            Quote(text: "在某个时刻你不再是为了简历而工作，而是为了你的人生清单。", author: "贝佐斯"),
            Quote(text: "固执于愿景，灵活于细节。", author: "贝佐斯"),
            // Charlie Munger
            Quote(text: "想要得到某样东西，最可靠的办法是让自己配得上它。", author: "芒格"),
            Quote(text: "嫉妒是七宗罪中最愚蠢的，因为它不会给你带来任何乐趣。", author: "芒格"),
            Quote(text: "反过来想，总是反过来想。", author: "芒格"),
            Quote(text: "你不需要非常多的聪明才智，你需要的是耐心和纪律。", author: "芒格"),
            Quote(text: "在手里拿着锤子的人看来，什么东西都像钉子。", author: "芒格"),
            // Naval Ravikant
            Quote(text: "如果你不能想象自己为它工作一辈子，就不要开始。", author: "Naval"),
            Quote(text: "真正的财富是在睡觉时也在增长的资产。", author: "Naval"),
            Quote(text: "阅读不是为了炫耀，而是为了找到你自己。", author: "Naval"),
            Quote(text: "忙碌不是美德，清晰才是。", author: "Naval"),
            // Ray Dalio
            Quote(text: "痛苦加上反思等于进步。", author: "达利欧"),
            Quote(text: "最大的威胁不是错误本身，而是没有从错误中学习。", author: "达利欧"),
            Quote(text: "原则是处理反复出现的事情的方式。", author: "达利欧"),
            Quote(text: "如果你不担心自己可能犯错，你就可能犯很多错。", author: "达利欧"),
            // Marcus Aurelius
            Quote(text: "你有控制自己思想的力量，而不是外界的事件。认识到这一点，你就找到了力量。", author: "马可·奥勒留"),
            Quote(text: "幸福取决于你的思想品质。", author: "马可·奥勒留"),
            Quote(text: "阻碍行动的障碍反而推动了行动，挡在路上的东西成了路。", author: "马可·奥勒留"),
            Quote(text: "不要浪费时间争论一个好人应该是什么样子，做一个就好。", author: "马可·奥勒留"),
            // Albert Einstein
            Quote(text: "想象力比知识更重要。", author: "爱因斯坦"),
            Quote(text: "不是我有多聪明，只是我和问题相处的时间够久。", author: "爱因斯坦"),
            Quote(text: "疯狂就是一遍又一遍做同样的事情，却期待不同的结果。", author: "爱因斯坦"),
            Quote(text: "逻辑能把你从A带到B，想象力能带你去任何地方。", author: "爱因斯坦"),
            // Peter Thiel
            Quote(text: "竞争是留给失败者的。", author: "彼得·蒂尔"),
            Quote(text: "最成功的公司是那些有核心使命的公司。", author: "彼得·蒂尔"),
            Quote(text: "做别人没有做过的事，从0到1。", author: "彼得·蒂尔"),
            // Paul Graham
            Quote(text: "做不可扩展的事。", author: "保罗·格雷厄姆"),
            Quote(text: "活着就是为了创造，创造就是为了活着。", author: "保罗·格雷厄姆"),
            Quote(text: "创业公司最危险的事是做别人已经在做的事。", author: "保罗·格雷厄姆"),
            // Nassim Taleb
            Quote(text: "风会熄灭蜡烛，却能助长火焰。", author: "塔勒布"),
            Quote(text: "你最大的收益不是来自于预测，而是来自于韧性。", author: "塔勒布"),
            // Sam Altman
            Quote(text: "长期思考是最大的套利机会之一。", author: "阿尔特曼"),
            Quote(text: "你能做的最有价值的事就是坚持你的信念。", author: "阿尔特曼"),
            // Oprah Winfrey
            Quote(text: "你成为你所相信的。", author: "奥普拉"),
            Quote(text: "每天做一件让自己害怕的事。", author: "奥普拉"),
            // Winston Churchill
            Quote(text: "成功就是从失败走到失败，却依然热情不减。", author: "丘吉尔"),
            Quote(text: "你永远不可能通过屈服来到达终点。", author: "丘吉尔"),
            Quote(text: "完美主义是瘫痪的代名词。", author: "丘吉尔"),
            // Seneca
            Quote(text: "如果一个人不知道他要驶向哪个港口，那么任何风都不会是顺风。", author: "塞涅卡"),
            Quote(text: "时间是我们最短缺的资源，也是我们最浪费的资源。", author: "塞涅卡"),
            Quote(text: "困难会显露出一个人的性格。", author: "塞涅卡"),
            // Mixed
            Quote(text: "先做最难的事，你的一天会越来越轻松。", author: "马克·吐温"),
            Quote(text: "成为你想在这个世界上看到的改变。", author: "甘地"),
            Quote(text: "真正的强大不是从不跌倒，而是每次跌倒都爬起来。", author: "曼德拉"),
            Quote(text: "种一棵树最好的时间是二十年前，其次是现在。", author: "谚语"),
        ]
        let dayNumber = Calendar.current.ordinality(of: .day, in: .year, for: store.selectedDate) ?? 0
        return quotes[(dayNumber + quoteOffset) % quotes.count]
    }

    private var todayTopDateBar: some View {
        HStack(spacing: 12) {
            Text(segment == "check" ? "每日打卡" : "待办")
                .font(.headline.weight(.semibold))
                .animation(.easeInOut(duration: 0.15), value: segment)

            Spacer(minLength: 6)

            Button {
                displayMonth = startOfMonth(for: store.selectedDate)
                showCalendarOverlay.toggle()
            } label: {
                HStack(spacing: 6) {
                    Text(dateTitle(store.selectedDate))
                        .font(.subheadline.weight(.semibold))
                    Image(systemName: showCalendarOverlay ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(CreamTheme.green)
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(Color(red: 0.95, green: 0.97, blue: 0.95))
                .overlay(
                    RoundedRectangle(cornerRadius: 11)
                        .stroke(CreamTheme.green.opacity(0.20), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 11))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.white.opacity(0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(CreamTheme.green.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.045), radius: 10, x: 0, y: 3)
        .padding(.horizontal, 12)
        .padding(.top, 6)
    }

    private var calendarOverlay: some View {
        CreamCalendarOverlay(
            selectedDate: $store.selectedDate,
            displayMonth: $displayMonth,
            isPresented: $showCalendarOverlay,
            markerForDate: { day in
                store.hasRecordTrace(on: day) ? .dot(CreamTheme.green) : .none
            }
        )
    }

    private func startOfMonth(for date: Date) -> Date {
        let comps = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: comps) ?? date
    }

    private func dateTitle(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM d, yyyy"
        return f.string(from: date)
    }
}

// MARK: - Todo Editor Sheet (Apple Calendar 风格)

private enum TodoEditorMode {
    case create(defaultDate: Date)
    case edit(task: TaskEntry)
}

private struct TodoEditorSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    let mode: TodoEditorMode

    @State private var title: String = ""
    @State private var notes: String = ""
    @State private var location: String = ""
    @State private var isAllDay: Bool = true
    @State private var startDate: Date = Date()
    @State private var endDate: Date = Date().addingTimeInterval(3600)
    @State private var priority: String = "无"   // 无 / 低 / 中 / 高

    // 是否为"编辑已有"
    private var editingID: UUID? {
        if case .edit(let t) = mode { return t.id }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                // 标题 —— 大字号突出，类似 Apple 日历
                Section {
                    TextField("标题", text: $title)
                        .font(.title3.weight(.semibold))
                }

                // 时间
                Section {
                    Toggle("全天", isOn: $isAllDay.animation(.easeInOut(duration: 0.15)))
                        .tint(CreamTheme.green)

                    DatePicker(
                        "开始",
                        selection: $startDate,
                        displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute]
                    )
                    .onChange(of: startDate) { newVal in
                        if endDate < newVal {
                            endDate = newVal.addingTimeInterval(3600)
                        }
                    }

                    DatePicker(
                        "结束",
                        selection: $endDate,
                        in: startDate...,
                        displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute]
                    )
                }

                // 优先级
                Section {
                    Picker("优先级", selection: $priority) {
                        Text("无").tag("无")
                        Text("低").tag("低")
                        Text("中").tag("中")
                        Text("高").tag("高")
                    }
                }

                // 备注
                Section("备注") {
                    TextField("添加备注…", text: $notes, axis: .vertical)
                        .lineLimit(3...8)
                }

                // 删除（仅编辑模式）
                if editingID != nil {
                    Section {
                        Button("删除待办", role: .destructive) {
                            if let id = editingID {
                                store.removeTask(id: id)
                            }
                            dismiss()
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
            .navigationTitle(editingID == nil ? "新建待办" : "编辑待办")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editingID == nil ? "添加" : "保存") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .tint(CreamTheme.green)
            .onAppear(perform: hydrate)
        }
    }

    private func hydrate() {
        switch mode {
        case .create(let defaultDate):
            // 默认开始=所选日期 09:00，结束=10:00
            let cal = Calendar.current
            var comps = cal.dateComponents([.year, .month, .day], from: defaultDate)
            comps.hour = 9; comps.minute = 0
            let s = cal.date(from: comps) ?? defaultDate
            startDate = s
            endDate = s.addingTimeInterval(3600)
            isAllDay = true
            priority = "无"
        case .edit(let t):
            title = t.title
            notes = t.detail
            location = t.location
            priority = t.priority.isEmpty ? "无" : t.priority
            isAllDay = t.isAllDay

            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.dateFormat = "yyyy-MM-dd"
            let tf = DateFormatter()
            tf.locale = Locale(identifier: "en_US_POSIX")
            tf.dateFormat = "yyyy-MM-dd HH:mm"

            let dayStr = t.dueDate.isEmpty ? df.string(from: Date()) : t.dueDate
            if t.isAllDay {
                startDate = df.date(from: dayStr) ?? Date()
                endDate = startDate
            } else {
                startDate = tf.date(from: "\(dayStr) \(t.startTime.isEmpty ? "09:00" : t.startTime)") ?? Date()
                let endStr = t.endTime.isEmpty ? "10:00" : t.endTime
                endDate = tf.date(from: "\(dayStr) \(endStr)") ?? startDate.addingTimeInterval(3600)
            }
        }
    }

    private func save() {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd"
        let tf = DateFormatter()
        tf.locale = Locale(identifier: "en_US_POSIX")
        tf.dateFormat = "HH:mm"

        let dayKey = df.string(from: startDate)
        let startStr = isAllDay ? "" : tf.string(from: startDate)
        let endStr = isAllDay ? "" : tf.string(from: endDate)
        let prio = priority == "无" ? "" : priority
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return }

        if let id = editingID {
            store.updateTask(
                id: id,
                title: cleanTitle,
                detail: notes,
                priority: prio,
                dueDate: dayKey,
                isAllDay: isAllDay,
                startTime: startStr,
                endTime: endStr,
                location: location
            )
        } else {
            _ = store.addTask(
                title: cleanTitle,
                detail: notes,
                priority: prio,
                dueDate: dayKey,
                isAllDay: isAllDay,
                startTime: startStr,
                endTime: endStr,
                location: location
            )
        }
        dismiss()
    }
}

private struct CheckItemManagerSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var newItem = ""
    @State private var newTag = "早"
    @State private var customTag = ""
    @State private var errorMsg: String?

    // 快捷标签预设：用户也可自由输入自定义
    private let presetTags = ["早", "晚", "默认"]

    private var effectiveTag: String {
        let c = customTag.trimmingCharacters(in: .whitespacesAndNewlines)
        return c.isEmpty ? newTag : c
    }

    var body: some View {
        NavigationStack {
            List {
                Section("新增打卡项") {
                    TextField("例如：跑步、背单词…", text: $newItem)
                        .submitLabel(.done)
                        .onSubmit(commit)

                    // 分组标签：预设快捷 + 自定义
                    VStack(alignment: .leading, spacing: 6) {
                        Text("分组标签")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 6) {
                            ForEach(presetTags, id: \.self) { tag in
                                tagChip(tag, selected: customTag.isEmpty && newTag == tag) {
                                    newTag = tag
                                    customTag = ""
                                }
                            }
                        }
                        TextField("或自定义（例如：工作日、运动日…）", text: $customTag)
                            .font(.callout)
                    }
                    .padding(.vertical, 4)

                    HStack {
                        Spacer()
                        Button("添加", action: commit)
                            .buttonStyle(.borderedProminent)
                            .tint(CreamTheme.green)
                            .disabled(newItem.trimmingCharacters(in: .whitespaces).isEmpty)
                    }

                    if let errorMsg {
                        Text(errorMsg)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section("当前打卡项（左滑删除）") {
                    if store.dailyCheckEntries.isEmpty {
                        Text("暂无，先在上面加一个吧")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(store.dailyCheckEntries, id: \.title) { entry in
                            HStack(spacing: 8) {
                                Image(systemName: "circle")
                                    .foregroundStyle(.secondary)
                                Text(entry.title)
                                Spacer()
                                Text(entry.tag)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(CreamTheme.green)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(
                                        Capsule().fill(CreamTheme.green.opacity(0.12))
                                    )
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    store.removeDailyCheckItem(entry.title)
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("管理打卡项")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .listStyle(.insetGrouped)
            .tint(CreamTheme.green)
            .scrollContentBackground(.hidden)
            .background(CreamTheme.glassStrong)
        }
    }

    @ViewBuilder
    private func tagChip(_ tag: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(tag)
                .font(.caption.weight(.semibold))
                .foregroundStyle(selected ? .white : CreamTheme.green)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(selected ? CreamTheme.green : CreamTheme.green.opacity(0.12))
                )
        }
        .buttonStyle(.plain)
    }

    private func commit() {
        let clean = newItem.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        let ok = store.addDailyCheckItem(clean, tag: effectiveTag)
        if ok {
            newItem = ""
            customTag = ""
            errorMsg = nil
        } else {
            errorMsg = "已存在同名打卡项"
        }
    }
}

struct MascotCatAssetView: View {
    let stroke: Color
    var assetName: String = "mascot-cat"

    private static var imageCache: [String: UIImage] = [:]

    private static func loadImage(named name: String) -> UIImage? {
        if let cached = imageCache[name] { return cached }

        let bundle = Bundle.main
        // Only use PNG — preserves alpha. (SVG/PDF pipelines add a white bg)
        let candidates: [URL?] = [
            bundle.url(forResource: name, withExtension: "png"),
            bundle.url(forResource: name, withExtension: "png", subdirectory: "Mascot"),
            bundle.url(forResource: name, withExtension: "png", subdirectory: "Resources/Mascot")
        ]

        for url in candidates.compactMap({ $0 }) {
            if let img = UIImage(contentsOfFile: url.path) {
                imageCache[name] = img
                return img
            }
        }

        if let img = UIImage(named: name) {
            imageCache[name] = img
            return img
        }

        return nil
    }

    private static func renderPDF(at url: URL) -> UIImage? {
        guard let document = CGPDFDocument(url as CFURL), let page = document.page(at: 1) else {
            return nil
        }

        let pageRect = page.getBoxRect(.mediaBox)
        guard pageRect.width > 0, pageRect.height > 0 else { return nil }

        let targetWidth: CGFloat = 1024
        let scale = targetWidth / pageRect.width
        let targetSize = CGSize(width: targetWidth, height: pageRect.height * scale)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = UIScreen.main.scale

        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { context in
            UIColor.clear.setFill()
            context.fill(CGRect(origin: .zero, size: targetSize))

            let cg = context.cgContext
            cg.saveGState()

            cg.translateBy(x: 0, y: targetSize.height)
            cg.scaleBy(x: 1, y: -1)
            cg.scaleBy(x: scale, y: scale)
            cg.drawPDFPage(page)

            cg.restoreGState()
        }
    }

    var body: some View {
        if let image = Self.loadImage(named: assetName) {
            Image(uiImage: image)
                .renderingMode(.original)
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .aspectRatio(contentMode: .fit)
        } else {
            // Do NOT fallback to legacy line-art mascot.
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.95))
                Image(systemName: "photo")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(CreamTheme.green.opacity(0.65))
            }
            .aspectRatio(1, contentMode: .fit)
        }
    }
}

