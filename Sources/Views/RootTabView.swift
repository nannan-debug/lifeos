import SwiftUI
import Foundation

struct RootTabView: View {
    @StateObject private var store = AppStore()

    private enum Tab: Hashable { case today, time, capture, review, settings }
    @State private var selectedTab: Tab = .today

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                TodayView().environmentObject(store)
                    .tabItem { Label("今日", systemImage: "sun.max") }
                    .tag(Tab.today)

                TimeView().environmentObject(store)
                    .tabItem { Label("时间", systemImage: "clock") }
                    .tag(Tab.time)

                QuickCaptureView().environmentObject(store)
                    .tabItem { Label("随记", systemImage: "square.and.pencil") }
                    .tag(Tab.capture)

                ReviewHubView().environmentObject(store)
                    .tabItem { Label("复盘", systemImage: "moon.stars") }
                    .tag(Tab.review)

                SettingsView().environmentObject(store)
                    .tabItem { Label("设置", systemImage: "gearshape") }
                    .tag(Tab.settings)
            }
            .tint(Color(red: 0.24, green: 0.65, blue: 0.36))

            // 全局 AI 输入框可见性：
            // - 「今日·打卡」隐藏（打卡页有 inline 添加）
            // - 「今日·待办」显示
            // - 「复盘」隐藏（仪式空间不该被记录入口干扰）
            // - 「设置」隐藏（设置页不需要记录入口）
            // - 其余 Tab 始终显示
            if shouldShowAIInputBar {
                GlobalAIInputBar()
                    .environmentObject(store)
                    .allowsHitTesting(true)
            }
        }
        .onAppear {
            store.ensureLocalIdentity()
        }
    }

    private var shouldShowAIInputBar: Bool {
        if selectedTab == .settings { return false }
        if selectedTab == .review { return false }
        if selectedTab == .today { return store.todaySegment == "todo" }
        return true
    }

}

struct QuickCaptureView: View {
    @EnvironmentObject var store: AppStore

    @State private var editingTurnID: UUID?
    @State private var editingText = ""
    @State private var editingType = "想法"
    @State private var previewDate = Date()
    @State private var previewFilter = "全部"
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var displayMonth = Date()
    @State private var showCalendarOverlay = false
    @State private var calendarTurnDateKeys: Set<String> = []
    @State private var moodEditTurnID: UUID?
    @State private var moodPickerScore: Int = 0
    @State private var moodPickerFeelings: Set<String> = []
    @State private var showFeelingExpand = false
    @State private var deleteTurnID: UUID?
    @State private var showDeleteConfirm = false
    @State private var hiddenTodayIDs: Set<UUID> = []
    // 注：AI 输入框已全局化到 RootTabView，loading/debug 状态现在在 AppStore

    private let intentOptions = ["想法", "感受", "感恩", "做梦"]

    private let moodLevels: [(score: Int, emoji: String, label: String)] = [
        (1, "😣", "非常不愉快"),
        (2, "😔", "不愉快"),
        (3, "😐", "平静"),
        (4, "🙂", "愉快"),
        (5, "😄", "非常愉快"),
    ]

    private let positiveFeelings = ["感恩", "平静", "满足", "兴奋", "自信", "被爱", "有动力", "好奇", "放松", "成就感"]
    private let negativeFeelings = ["焦虑", "烦躁", "无力", "愤怒", "孤独", "内疚", "自责", "迷茫", "压抑", "疲惫"]
    private let calendar = Calendar.current
    private let globalInputClearance: CGFloat = 96

    private var turnsForPreview: [ConversationTurn] {
        var result = store.turns.filter {
            Calendar.current.isDate($0.createdAt, inSameDayAs: previewDate)
        }
        // 时间记录不在随记展示，直接去时间页面查看
        result = result.filter { $0.targetBucket != "time" }
        if previewFilter != "全部" {
            result = result.filter { $0.recognizedType == previewFilter }
        }
        // 过滤掉今天已隐藏的
        result = result.filter { !hiddenTodayIDs.contains($0.id) }
        return result
    }

    var body: some View {
        NavigationStack {
            List {
                dayViewContent
            }
            .toolbar(.hidden, for: .navigationBar)
            .listStyle(.insetGrouped)
            .tint(CreamTheme.green)
            .scrollContentBackground(.hidden)
            .background(CreamTheme.glassStrong)
            .scrollDismissesKeyboard(.interactively)
            // 点击空白区域收起键盘
            .simultaneousGesture(
                TapGesture().onEnded {
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder),
                        to: nil, from: nil, for: nil
                    )
                }
            )
            .safeAreaInset(edge: .top, spacing: 0) {
                topFilterBar
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: globalInputClearance)
            }
            // 底部输入框已全局化：RootTabView 的 GlobalAIInputBar 负责所有 Tab
            .onAppear {
                displayMonth = startOfMonth(for: previewDate)
                refreshCalendarMarkers()
                // 轻唤醒 Worker，减少首次真发送时的冷启动等待
                AIParser.warmUp()
            }
            .onChange(of: previewDate) { newDate in
                let m = startOfMonth(for: newDate)
                if !calendar.isDate(m, equalTo: displayMonth, toGranularity: .month) {
                    displayMonth = m
                }
            }
            .onChange(of: displayMonth) { _ in refreshCalendarMarkers() }
            .onChange(of: store.turns.count) { _ in refreshCalendarMarkers() }
            .overlay(alignment: .top) {
                if showCalendarOverlay {
                    quickCaptureCalendarOverlay
                        .transition(.opacity)
                        .zIndex(20)
                }
            }
            // Animation driven by withAnimation() in calendar toggle button
            .alert("处理失败", isPresented: $showError) {
                Button("知道了", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            .confirmationDialog("确认删除这条记录？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("删除", role: .destructive) {
                    if let id = deleteTurnID {
                        store.removeCommittedTurn(id: id)
                    }
                    deleteTurnID = nil
                }
                Button("今天不再显示", role: .none) {
                    if let id = deleteTurnID {
                        hiddenTodayIDs.insert(id)
                    }
                    deleteTurnID = nil
                }
                Button("取消", role: .cancel) {
                    deleteTurnID = nil
                }
            } message: {
                Text("删除将永久移除这条记录。如果只是暂时不想看到，可以选择「今天不再显示」。")
            }
            .sheet(isPresented: Binding(
                get: { moodEditTurnID != nil },
                set: { if !$0 { moodEditTurnID = nil } }
            )) {
                moodPickerSheet
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(item: Binding(
                get: { editingTurnID.map(EditTurnRef.init) },
                set: { editingTurnID = $0?.id }
            )) { _ in
                editSheet
            }
        }
        .creamBackground()
    }

    // MARK: - Day View
    @ViewBuilder
    private var dayViewContent: some View {
                Section {
                    if turnsForPreview.isEmpty {
                        Text("这一天还没有记录")
                            .foregroundStyle(.secondary)
                    }

                    ForEach(turnsForPreview) { turn in
                        HStack(spacing: 0) {
                            // 左侧彩色竖条
                            RoundedRectangle(cornerRadius: 2)
                                .fill(TurnTypeStyle.color(for: turn.recognizedType))
                                .frame(width: 4)
                                .padding(.vertical, 6)

                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(turn.createdAt, style: .time)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    if turn.status == "needs_fix" {
                                        statusBadge(turn.status)
                                    }
                                    reviewStatusIcon(turn.reviewStatus)
                                    // 类型标签：浅底+主色
                                    HStack(spacing: 4) {
                                        Image(systemName: TurnTypeStyle.icon(for: turn.recognizedType))
                                            .font(.caption2)
                                        Text(turn.recognizedType)
                                            .font(.caption.weight(.semibold))
                                    }
                                    .foregroundStyle(TurnTypeStyle.color(for: turn.recognizedType))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(TurnTypeStyle.bgColor(for: turn.recognizedType))
                                    .clipShape(Capsule())
                                }

                                Text(TurnTypeStyle.displayText(for: turn))
                                    .font(.subheadline)

                                // 心情 + 感受词
                                if turn.moodScore != nil || !turn.feelingTags.isEmpty {
                                    HStack(spacing: 6) {
                                        if let score = turn.moodScore, let level = moodLevels.first(where: { $0.score == score }) {
                                            Text(level.emoji)
                                                .font(.system(size: 14))
                                        }
                                        if !turn.feelingTags.isEmpty {
                                            ForEach(turn.feelingTags, id: \.self) { tag in
                                                Text(tag)
                                                    .font(.caption2.weight(.medium))
                                                    .foregroundStyle(TurnTypeStyle.color(for: turn.recognizedType).opacity(0.8))
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(TurnTypeStyle.bgColor(for: turn.recognizedType))
                                                    .clipShape(Capsule())
                                            }
                                        }
                                    }
                                }

                                if turn.status == "needs_fix", !turn.fixHint.isEmpty {
                                    Text("⚠️ \(turn.fixHint)")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }
                            }
                            .padding(.leading, 10)
                            .padding(.trailing, 12)
                            .padding(.vertical, 12)
                        }
                        .opacity(turn.reviewStatus == "dismissed" ? 0.45 : 1.0)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(turn.status == "needs_fix" ? Color.orange.opacity(0.06) : Color.white.opacity(0.9))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(TurnTypeStyle.color(for: turn.recognizedType).opacity(0.12), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.035), radius: 8, x: 0, y: 2)
                        .listRowInsets(EdgeInsets(top: 5, leading: 8, bottom: 5, trailing: 8))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                deleteTurnID = turn.id
                                showDeleteConfirm = true
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                            Button {
                                beginEdit(turn)
                            } label: {
                                Label("再编辑", systemImage: "pencil")
                            }
                            .tint(CreamTheme.green)
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button {
                                moodEditTurnID = turn.id
                                moodPickerScore = turn.moodScore ?? 0
                                moodPickerFeelings = Set(turn.feelingTags)
                                showFeelingExpand = false
                            } label: {
                                Label("心情", systemImage: "face.smiling")
                            }
                            .tint(Color(red: 0.627, green: 0.502, blue: 0.361))
                        }
                        .contextMenu {
                            Button { beginEdit(turn) } label: { Label("编辑", systemImage: "pencil") }
                            Button {
                                moodEditTurnID = turn.id
                                moodPickerScore = turn.moodScore ?? 0
                                moodPickerFeelings = Set(turn.feelingTags)
                                showFeelingExpand = false
                            } label: { Label("记录心情", systemImage: "face.smiling") }
                            Divider()
                            Menu("Review 状态") {
                                Button { store.updateTurnReviewStatus(id: turn.id, reviewStatus: "pending") } label: { Label("待处理", systemImage: "tray") }
                                Button { store.updateTurnReviewStatus(id: turn.id, reviewStatus: "archived") } label: { Label("已处理", systemImage: "checkmark.circle") }
                                Button { store.updateTurnReviewStatus(id: turn.id, reviewStatus: "dismissed") } label: { Label("划掉", systemImage: "xmark.circle") }
                            }
                            Divider()
                            Button(role: .destructive) {
                                deleteTurnID = turn.id
                                showDeleteConfirm = true
                            } label: { Label("删除", systemImage: "trash") }
                        }
                    }
                }
    }

    // MARK: - Edit Sheet
    private var editSheet: some View {
        NavigationStack {
            Form {
                Section("内容") {
                    TextField("文本内容", text: $editingText, axis: .vertical)
                        .lineLimit(3...8)
                }
                Section("标签") {
                    Picker("识别标签", selection: $editingType) {
                        ForEach(intentOptions, id: \.self) { type in
                            Label(type, systemImage: TurnTypeStyle.icon(for: type))
                                .foregroundStyle(TurnTypeStyle.color(for: type))
                                .tag(type)
                        }
                    }
                }
                Section {
                    Button("删除这条", role: .destructive) {
                        if let id = editingTurnID { store.removeTurn(id: id) }
                        editingTurnID = nil
                    }
                }
            }
            .navigationTitle("编辑记录")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { editingTurnID = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        guard let id = editingTurnID else { return }
                        let err = store.reviseCommittedTurn(
                            id: id,
                            recognizedType: editingType,
                            targetBucket: "inbox",
                            text: editingText
                        )
                        if let err {
                            errorMessage = err
                            showError = true
                        }
                        editingTurnID = nil
                    }
                    .disabled(editingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var topFilterBar: some View {
        VStack(spacing: 10) {
            // 第一行：标题 + 日期
            HStack(spacing: 10) {
                Text("随手记")
                    .font(.headline.weight(.semibold))

                Spacer()

                Button {
                    displayMonth = startOfMonth(for: previewDate)
                    withAnimation(.easeOut(duration: 0.10)) {
                        showCalendarOverlay.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(dateTitle(previewDate))
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

            // 第二行：类型筛选
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    filterChip("全部", icon: "line.3.horizontal.decrease.circle", color: CreamTheme.green, bg: Color(red: 0.95, green: 0.97, blue: 0.95))
                    ForEach(intentOptions, id: \.self) { type in
                        filterChip(type, icon: TurnTypeStyle.icon(for: type), color: TurnTypeStyle.color(for: type), bg: TurnTypeStyle.bgColor(for: type))
                    }
                }
            }
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

    private func filterChip(_ label: String, icon: String, color: Color, bg: Color) -> some View {
        let isSelected = previewFilter == label
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                previewFilter = label
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(label)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(isSelected ? color : .secondary.opacity(0.6))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(isSelected ? bg : Color(red: 0.96, green: 0.96, blue: 0.96))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? color.opacity(0.25) : Color.clear, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private var quickCaptureCalendarOverlay: some View {
        CreamCalendarOverlay(
            selectedDate: $previewDate,
            displayMonth: $displayMonth,
            isPresented: $showCalendarOverlay,
            markerForDate: { day in
                calendarTurnDateKeys.contains(store.calendarDateKey(for: day)) ? .dot(CreamTheme.green) : .none
            }
        )
    }

    private func refreshCalendarMarkers() {
        calendarTurnDateKeys = Set(store.turns.map { store.calendarDateKey(for: $0.createdAt) })
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

    private func statusBadge(_ status: String) -> some View {
        let title: String
        let color: Color
        switch status {
        case "committed":
            title = "已写入"
            color = CreamTheme.green
        case "needs_fix":
            title = "待修正"
            color = .orange
        default:
            title = "处理中"
            color = .blue
        }
        return Text(title)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    @ViewBuilder
    private func reviewStatusIcon(_ status: String) -> some View {
        switch status {
        case "archived":
            Image(systemName: "checkmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(CreamTheme.green.opacity(0.6))
        case "dismissed":
            Image(systemName: "xmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(.secondary.opacity(0.4))
        default:
            EmptyView()
        }
    }

    private var moodPickerSheet: some View {
        VStack(spacing: 20) {
            Text("记录心情")
                .font(.headline.weight(.semibold))
                .padding(.top, 8)

            // 5 级心情
            HStack(spacing: 12) {
                ForEach(moodLevels, id: \.score) { level in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            moodPickerScore = moodPickerScore == level.score ? 0 : level.score
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Text(level.emoji)
                                .font(.system(size: 28))
                            Text(level.label)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(moodPickerScore == level.score ? CreamTheme.green.opacity(0.12) : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(moodPickerScore == level.score ? CreamTheme.green.opacity(0.3) : Color.clear, lineWidth: 1.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            // 感受词
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    withAnimation { showFeelingExpand.toggle() }
                } label: {
                    HStack {
                        Text("感受词")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        if !moodPickerFeelings.isEmpty {
                            Text("(\(moodPickerFeelings.count))")
                                .font(.caption)
                                .foregroundStyle(CreamTheme.green)
                        }
                        Spacer()
                        Image(systemName: showFeelingExpand ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)

                if showFeelingExpand {
                    feelingTagSection("正向", tags: positiveFeelings, color: CreamTheme.green)
                    feelingTagSection("负向", tags: negativeFeelings, color: Color(red: 0.627, green: 0.502, blue: 0.361))
                }
            }
            .padding(.horizontal, 4)

            // 保存按钮
            Button {
                if let id = moodEditTurnID {
                    store.updateTurnMood(
                        id: id,
                        moodScore: moodPickerScore > 0 ? moodPickerScore : nil,
                        feelingTags: Array(moodPickerFeelings).sorted()
                    )
                }
                moodEditTurnID = nil
            } label: {
                Text("保存")
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(CreamTheme.green)
            .padding(.horizontal, 4)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private func feelingTagSection(_ title: String, tags: [String], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                ForEach(tags, id: \.self) { tag in
                    let selected = moodPickerFeelings.contains(tag)
                    Button {
                        withAnimation(.easeInOut(duration: 0.12)) {
                            if selected { moodPickerFeelings.remove(tag) } else { moodPickerFeelings.insert(tag) }
                        }
                    } label: {
                        Text(tag)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(selected ? color : .secondary)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity)
                            .background(selected ? color.opacity(0.12) : Color(red: 0.96, green: 0.96, blue: 0.96))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(selected ? color.opacity(0.3) : Color.clear, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func beginEdit(_ turn: ConversationTurn) {
        editingTurnID = turn.id
        editingType = intentOptions.contains(turn.recognizedType) ? turn.recognizedType : "想法"
        editingText = TurnTypeStyle.displayText(for: turn)
    }

}

private struct EditTurnRef: Identifiable {
    let id: UUID
    init(_ id: UUID) { self.id = id }
}

struct CapturePlan {
    var timeEntries: [ParsedTimeEntry]
    var inboxEntries: [ParsedInboxEntry]
    var tasks: [ParsedTaskEntry]

    static let empty = CapturePlan(timeEntries: [], inboxEntries: [], tasks: [])
}

struct ParsedTimeEntry {
    var name: String
    var category: String
    var start: String
    var end: String
    var note: String
}

struct ParsedInboxEntry {
    var title: String
    var kind: String
    var detail: String
    var status: String
}

struct ParsedTaskEntry {
    var title: String
    var detail: String
    var status: String
    var priority: String
    var dueDate: String
    var date: String
}

struct ParseResult {
    var plan: CapturePlan
    var missingQuestions: [String]
}

enum QuickCaptureParser {
    static func parse(_ input: String) -> ParseResult {
        let segments = splitSegments(input)
        var timeEntries: [ParsedTimeEntry] = []
        var inboxEntries: [ParsedInboxEntry] = []
        var tasks: [ParsedTaskEntry] = []
        var missing: [String] = []
        let maxEvents = 1

        for seg in segments {
            let s = seg.trimmingCharacters(in: .whitespacesAndNewlines)
            if s.isEmpty { continue }
            let currentCount = timeEntries.count + inboxEntries.count + tasks.count
            if currentCount >= maxEvents { break }

            if looksLikeTask(s) {
                tasks.append(parseTask(s))
                continue
            }

            if let time = parseTimeEntry(s) {
                timeEntries.append(time)
                continue
            }

            if hasTimeSignal(s) {
                missing.append("“\(s)”像时间记录，但缺少明确开始/结束时间（例如 09:30-11:00）。")
                continue
            }

            let remain = maxEvents - (timeEntries.count + inboxEntries.count + tasks.count)
            if remain <= 0 { break }
            inboxEntries.append(contentsOf: parseInboxEntries(s).prefix(remain))
        }

        return ParseResult(
            plan: CapturePlan(timeEntries: timeEntries, inboxEntries: inboxEntries, tasks: tasks),
            missingQuestions: missing
        )
    }

    private static func splitSegments(_ text: String) -> [String] {
        text
            .replacingOccurrences(of: "\n", with: "。")
            .split(whereSeparator: { "。！？；;".contains($0) })
            .map(String.init)
    }

    private static func looksLikeTask(_ s: String) -> Bool {
        ["要做", "记得", "待会", "明天", "下周", "需要", "必须", "提醒我"].contains { s.contains($0) }
    }

    private static func parseTask(_ s: String) -> ParsedTaskEntry {
        let priority: String
        if s.contains("今天必须") || s.contains("很急") { priority = "高" }
        else if s.contains("重要但不急") { priority = "中" }
        else { priority = "" }

        let dueDate: String
        if s.contains("明天") { dueDate = "明天" }
        else if s.contains("周五") { dueDate = "周五" }
        else { dueDate = "" }

        let title = verbLeadingTitle(from: s)
        return ParsedTaskEntry(title: title, detail: s, status: "待办", priority: priority, dueDate: dueDate, date: todayKey())
    }

    private static func parseInboxEntries(_ s: String) -> [ParsedInboxEntry] {
        let kinds = inferInboxKinds(s)
        let title = summarizeTitle(s)
        let detail = threeLineSummary(s)
        return kinds.prefix(2).map { kind in
            ParsedInboxEntry(title: title, kind: kind, detail: detail, status: "待处理")
        }
    }

    private static func inferInboxKinds(_ s: String) -> [String] {
        var result: [String] = []

        if s.contains("梦") { result.append("做梦") }
        if s.contains("感恩") { result.append("感恩") }
        if s.contains("焦虑") || s.contains("开心") || s.contains("兴奋") || s.contains("难过") || s.contains("感受") { result.append("感受") }
        if s.contains("想") || s.contains("想法") || s.contains("要做") || s.lowercased().contains("todo") || s.contains("待办") { result.append("想法") }

        // 去重并保序
        var dedup: [String] = []
        for item in result where !dedup.contains(item) {
            dedup.append(item)
        }
        if dedup.isEmpty { return ["想法"] }
        return dedup
    }

    private static func parseTimeEntry(_ s: String) -> ParsedTimeEntry? {
        guard let (start, end) = extractTimeRange(s) else { return nil }
        let category = inferCategory(s)
        let name = inferEventName(s, fallback: category)
        return ParsedTimeEntry(name: name, category: category, start: start, end: end, note: s)
    }

    private static func hasTimeSignal(_ s: String) -> Bool {
        ["点", "上午", "下午", "晚上", "小时", "分钟", "-", "到"].contains { s.contains($0) }
    }

    private static func extractTimeRange(_ s: String) -> (String, String)? {
        let pattern = #"(\d{1,2})(?::(\d{1,2}))?\s*(?:-|到|至)\s*(\d{1,2})(?::(\d{1,2}))?"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let m = regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else {
            return nil
        }

        func part(_ i: Int) -> String {
            guard let r = Range(m.range(at: i), in: s), !r.isEmpty else { return "00" }
            return String(s[r])
        }

        let h1 = Int(part(1)) ?? 0
        let m1 = Int(part(2)) ?? 0
        let h2 = Int(part(3)) ?? 0
        let m2 = Int(part(4)) ?? 0

        guard (0...23).contains(h1), (0...23).contains(h2), (0...59).contains(m1), (0...59).contains(m2) else {
            return nil
        }

        let start = String(format: "%02d:%02d", h1, m1)
        let end = String(format: "%02d:%02d", h2, m2)
        if end <= start { return nil }
        return (start, end)
    }

    private static func inferCategory(_ s: String) -> String {
        if s.contains("睡") { return "睡觉" }
        if s.contains("工作") || s.contains("开会") || s.contains("方案") { return "工作" }
        if s.contains("学习") || s.contains("读书") { return "学习" }
        if s.contains("运动") || s.contains("健身") || s.contains("跑步") { return "运动" }
        if s.contains("电影") || s.contains("看书") { return "娱乐" }
        if s.contains("社交") || s.contains("朋友") { return "社交" }
        return "其他"
    }

    private static func inferEventName(_ s: String, fallback: String) -> String {
        if s.contains("开会") { return "会议" }
        if s.contains("健身") || s.contains("运动") { return "运动" }
        if s.contains("写方案") { return "写方案" }
        if s.contains("学习") { return "学习" }
        return fallback
    }

    private static func summarizeTitle(_ s: String) -> String {
        let cleaned = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.count <= 18 { return cleaned }
        return String(cleaned.prefix(18)) + "…"
    }

    private static func threeLineSummary(_ s: String) -> String {
        let cleaned = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.count <= 60 { return cleaned }
        return String(cleaned.prefix(60)) + "…"
    }

    private static func verbLeadingTitle(from s: String) -> String {
        let cleaned = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("提醒我") {
            return "处理：" + cleaned.replacingOccurrences(of: "提醒我", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return cleaned.count > 20 ? String(cleaned.prefix(20)) : cleaned
    }

    private static func todayKey() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}
