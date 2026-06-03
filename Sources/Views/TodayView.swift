import SwiftUI
import UIKit

private struct CompletedTaskGroup: Identifiable {
    let id: String
    let title: String
    let tasks: [TaskEntry]
}

private enum CompletedTaskClearScope: Identifiable {
    case oneMonth
    case sixMonths
    case oneYear
    case all

    var id: String { title }

    var title: String {
        switch self {
        case .oneMonth: return L.overOneMonth
        case .sixMonths: return L.overSixMonths
        case .oneYear: return L.overOneYear
        case .all: return L.allCompleted
        }
    }

    var cutoff: Date? {
        let calendar = Calendar.current
        switch self {
        case .oneMonth:
            return calendar.date(byAdding: .month, value: -1, to: Date())
        case .sixMonths:
            return calendar.date(byAdding: .month, value: -6, to: Date())
        case .oneYear:
            return calendar.date(byAdding: .year, value: -1, to: Date())
        case .all:
            return nil
        }
    }
}

struct TodayView: View {
    @EnvironmentObject var store: AppStore

    @State private var displayMonth = Date()
    @State private var showCalendarOverlay = false
    @State private var calendarTraceKeys: Set<String> = []
    @State private var quoteOffset: Int = 0

    // A 方案：顶部分段 "check" | "todo"
    @State private var segment: String = "check"

    // 折叠/展开的 tag 集合（持久化到 AppStorage，重新打开保持状态）
    @AppStorage("checks.collapsedTags") private var collapsedTagsRaw: String = ""

    // ── inline 编辑状态（B 方案：管理面板已下线，所有 CRUD 在打卡页就地完成）

    // 当前正在哪一组的"添加打卡项"行里输入；nil = 外层不展示新增入口
    @State private var addingItemForGroup: String? = nil
    @State private var addingItemText: String = ""
    @FocusState private var addItemFocused: Bool

    @State private var celebratingGroup: String? = nil
    @State private var sortingGroup: String? = nil
    @State private var sortingGroups: Bool = false

    // 底部"新建分组"行
    @State private var addingNewGroup: Bool = false
    @State private var newGroupText: String = ""
    @FocusState private var newGroupFocused: Bool

    // 重命名 / 删除 弹窗
    @State private var renamingItem: String? = nil
    @State private var renameItemText: String = ""

    @State private var renamingGroup: String? = nil
    @State private var renameGroupText: String = ""

    @State private var groupToDelete: String? = nil

    // 错误提示（重名等）
    @State private var inlineErrorMsg: String? = nil

    // 待办输入
    @State private var newTodoTitle = ""
    @State private var selectedTodoID: UUID?
    @State private var editingTodoTitleID: UUID?
    @State private var editingTodoTitleText = ""
    @State private var completedTasksExpanded = false
    @State private var showingCompletedClearOptions = false
    @State private var clearCompletedScope: CompletedTaskClearScope?
    @FocusState private var focusedTodoTitleID: UUID?

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
                .environment(\.editMode, .constant((sortingGroup == nil && !sortingGroups) ? EditMode.inactive : EditMode.active))
                .tint(CreamTheme.green)
                .scrollContentBackground(.hidden)
                .background(CreamTheme.glassStrong)
                .safeAreaInset(edge: .top, spacing: 0) {
                    VStack(spacing: 8) {
                        todayTopDateBar
                        segmentPicker
                    }
                }

                if showCalendarOverlay {
                    calendarOverlay
                        .transition(.opacity)
                        .zIndex(20)
                }
            }
            .onAppear {
                displayMonth = startOfMonth(for: store.selectedDate)
                refreshCalendarMarkers()
                segment = store.todaySegment
            }
            .onChange(of: segment) { store.todaySegment = $0 }
            .onChange(of: store.todaySegment) { newSegment in
                guard segment != newSegment else { return }
                segment = newSegment
            }
            .onChange(of: store.selectedDate) { newDate in
                let m = startOfMonth(for: newDate)
                if !calendar.isDate(m, equalTo: displayMonth, toGranularity: .month) {
                    displayMonth = m
                }
            }
            .onChange(of: displayMonth) { _ in refreshCalendarMarkers() }
            .onChange(of: store.checkItems.count) { _ in refreshCalendarMarkers() }
            .onChange(of: store.timeEntries.count) { _ in refreshCalendarMarkers() }
            .sheet(item: $editingTask) { task in
                TodoEditorSheet(mode: .edit(task: task))
                    .environmentObject(store)
            }
            .confirmationDialog(
                L.clearCompletedTitle,
                isPresented: $showingCompletedClearOptions,
                titleVisibility: .visible
            ) {
                Button(L.overOneMonth) { clearCompletedScope = .oneMonth }
                Button(L.overSixMonths) { clearCompletedScope = .sixMonths }
                Button(L.overOneYear) { clearCompletedScope = .oneYear }
                Button(L.allCompleted) { clearCompletedScope = .all }
                Button(L.cancel, role: .cancel) {}
            } message: {
                Text(L.clearCompletedMsg)
            }
            .alert(item: $clearCompletedScope) { scope in
                let count = completedTaskCount(for: scope)
                return Alert(
                    title: Text(L.clearScopeTitle(scope.title)),
                    message: Text(count == 0 ? L.clearScopeNoItems : L.clearScopeCount(count)),
                    primaryButton: .default(Text(count == 0 ? L.ok : L.clearButton)) {
                        guard count > 0 else { return }
                        store.clearCompletedTasks(olderThan: scope.cutoff)
                    },
                    secondaryButton: .cancel(Text(L.cancel))
                )
            }
            // ── inline 编辑：重命名打卡项
            .alert(
                L.renameCheckItem,
                isPresented: Binding(
                    get: { renamingItem != nil },
                    set: { if !$0 { renamingItem = nil } }
                ),
                presenting: renamingItem
            ) { _ in
                TextField(L.newNamePlaceholder, text: $renameItemText)
                Button(L.save) {
                    if let old = renamingItem {
                        let ok = store.renameDailyCheckItem(from: old, to: renameItemText)
                        if !ok {
                            inlineErrorMsg = L.renameFailItem
                        }
                    }
                    renamingItem = nil
                }
                Button(L.cancel, role: .cancel) { renamingItem = nil }
            } message: { _ in
                Text(L.renameCheckHint(""))
            }
            // ── inline 编辑：重命名分组
            .alert(
                L.renameGroup,
                isPresented: Binding(
                    get: { renamingGroup != nil },
                    set: { if !$0 { renamingGroup = nil } }
                ),
                presenting: renamingGroup
            ) { _ in
                TextField(L.newNamePlaceholder, text: $renameGroupText)
                Button(L.save) {
                    if let old = renamingGroup {
                        let ok = store.renameDailyCheckGroup(from: old, to: renameGroupText)
                        if !ok {
                            inlineErrorMsg = L.renameFailGroup
                        }
                    }
                    renamingGroup = nil
                }
                Button(L.cancel, role: .cancel) { renamingGroup = nil }
            } message: { group in
                Text(L.renameGroupHint(group))
            }
            // ── inline 编辑：删除分组（带级联确认）
            .alert(
                L.deleteGroup,
                isPresented: Binding(
                    get: { groupToDelete != nil },
                    set: { if !$0 { groupToDelete = nil } }
                ),
                presenting: groupToDelete
            ) { group in
                Button(L.delete, role: .destructive) {
                    store.removeDailyCheckGroup(group)
                    groupToDelete = nil
                }
                Button(L.cancel, role: .cancel) { groupToDelete = nil }
            } message: { group in
                let count = store.dailyCheckItemCount(forGroup: group)
                if count == 0 {
                    Text(L.deleteGroupEmpty(group))
                } else {
                    Text(L.deleteGroupWithCount(group, count))
                }
            }
            // ── inline 错误提示（轻量 alert，避免破坏温柔语气）
            .alert(
                L.notice,
                isPresented: Binding(
                    get: { inlineErrorMsg != nil },
                    set: { if !$0 { inlineErrorMsg = nil } }
                ),
                presenting: inlineErrorMsg
            ) { _ in
                Button(L.ok, role: .cancel) { inlineErrorMsg = nil }
            } message: { msg in
                Text(msg)
            }
        }
        .creamBackground()
    }

    // MARK: - Segment Picker

    private var segmentPicker: some View {
        Picker("", selection: $segment) {
            Text(L.segmentCheck).tag("check")
            Text(L.segmentTodo).tag("todo")
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 12)
    }

    // MARK: - Check Section (existing content refactored out)

    @ViewBuilder
    private var checkSection: some View {
        // 全部内容并到一个 Section（备选 1：去掉 motivationalCard 与分组之间的 ~32pt section gap）
        // motivationalCard 自带白色 RoundedRectangle 背景，会盖住下层 section 默认卡的对应区域，
        // 视觉上像是顶部白卡 + 下面分组卡，但贴得很近。
        Section {
            motivationalCard
                .listRowInsets(EdgeInsets(top: 3, leading: 6, bottom: 6, trailing: 6))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

            if sortingGroups {
                groupSortingHeader
                ForEach(groupedCheckTags, id: \.self) { tag in
                    groupSortingRow(for: tag)
                }
                .onMove { source, destination in
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        store.moveDailyCheckGroups(from: source, to: destination)
                    }
                }
            } else {
                ForEach(Array(groupedCheckTags.enumerated()), id: \.element) { idx, tag in
                    collapsibleHeader(for: tag)

                    if !isTagCollapsed(tag) || sortingGroup == tag {
                        ForEach(store.checkItems.filter { $0.tag == tag }) { item in
                            checkRow(item, isSorting: sortingGroup == tag)
                        }
                        .onMove { source, destination in
                            guard sortingGroup == tag else { return }
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                                store.moveDailyCheckItems(inGroup: tag, from: source, to: destination)
                            }
                        }
                        if addingItemForGroup == tag {
                            inlineAddItemRow(forGroup: tag)
                        }
                        if celebratingGroup == tag {
                            groupCompletionCelebration(for: tag)
                        }
                    }
                }

                // 未分组的打卡项：直接列出来，不挂 header
                // 只有在确实存在未分组项时才显示这块（含其末尾的 inline 添加行），
                // 避免所有分组都收起后，未分组添加行假装是最后一组的"漏网"添加行。
                if !untaggedCheckItems.isEmpty {
                    ForEach(untaggedCheckItems) { item in
                        checkRow(item, isSorting: false)
                    }
                }

                inlineAddGroupRow
            }
        }
    }

    /// tag → SF Symbol 映射（早/晚 用太阳月亮，其他用 tag 图标）
    private func iconName(for tag: String) -> String {
        switch tag.lowercased() {
        case "早", "早上", "晨间", "morning": return "sun.max.fill"
        case "晚", "晚上", "夜间", "evening": return "moon.stars.fill"
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
            if sortingGroup == tag {
                endSorting()
                return
            }
            guard sortingGroup == nil else { return }
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

                if sortingGroup == tag {
                    Text(L.done)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(CreamTheme.green)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(CreamTheme.green.opacity(0.10)))
                } else {
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
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.42).onEnded { _ in
                startSortingGroups()
            }
        )
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 4, leading: 6, bottom: 2, trailing: 6))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        // 左滑分组头：新增 / 重命名 / 删除（删除带级联确认弹窗）
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if sortingGroup == nil {
                Button(role: .destructive) {
                    groupToDelete = tag
                } label: {
                    Label(L.delete, systemImage: "trash")
                }
                Button {
                    renamingGroup = tag
                    renameGroupText = tag
                } label: {
                    Label(L.rename, systemImage: "pencil")
                }
                .tint(CreamTheme.green)
                Button {
                    startAddingItem(forGroup: tag)
                } label: {
                    Label(L.add, systemImage: "plus")
                }
                .tint(CreamTheme.green.opacity(0.88))
            }
        }
    }

    private var groupSortingHeader: some View {
        HStack {
            Text(L.reorderGroups)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Button(L.done) { endSorting() }
                .font(.caption.weight(.semibold))
                .foregroundStyle(CreamTheme.green)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .listRowInsets(EdgeInsets(top: 4, leading: 6, bottom: 0, trailing: 6))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private func groupSortingRow(for tag: String) -> some View {
        let total = store.checkItems.filter { $0.tag == tag }.count
        let doneCount = store.checkItems.filter { $0.tag == tag && $0.done }.count
        return HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(CreamTheme.green.opacity(0.12))
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
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(CreamTheme.green.opacity(0.05))
        )
        .listRowInsets(EdgeInsets(top: 4, leading: 6, bottom: 4, trailing: 6))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    /// 单个打卡行（大号字，仿提醒事项）
    @ViewBuilder
    private func checkRow(_ item: DailyCheckItem, isSorting: Bool = false) -> some View {
        Button {
            guard !isSorting else { return }
            let wasComplete = isGroupComplete(item.tag)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                store.toggle(item)
            }
            if !wasComplete && isGroupComplete(item.tag) {
                showGroupCompletion(for: item.tag)
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
            .padding(.vertical, 6)   // 收紧（C 方案，原 8）
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isSorting ? CreamTheme.green.opacity(0.05) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 0, leading: 6, bottom: 0, trailing: 6))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .transition(.opacity.combined(with: .move(edge: .top)))
        // 左滑：重命名 / 删除（B 方案 inline 编辑）
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if sortingGroup == nil {
                Button(role: .destructive) {
                    withAnimation { store.removeDailyCheckItem(item.title) }
                } label: {
                    Label(L.delete, systemImage: "trash")
                }
                Button {
                    renamingItem = item.title
                    renameItemText = item.title
                } label: {
                    Label(L.rename, systemImage: "pencil")
                }
                .tint(CreamTheme.green)
            }
        }
    }

    /// 分组内临时新增行：只在分组头左滑点"新增"后出现。
    @ViewBuilder
    private func inlineAddItemRow(forGroup tag: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.circle")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(CreamTheme.green.opacity(0.85))

            TextField(L.newCheckItemPlaceholder, text: $addingItemText)
                .textFieldStyle(.plain)
                .font(.callout)
                .submitLabel(.done)
                .focused($addItemFocused)
                .onSubmit { commitInlineAddItem(forGroup: tag) }

            Spacer()
        }
        .padding(.leading, 32)
        .padding(.trailing, 14)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .listRowInsets(EdgeInsets(top: 0, leading: 6, bottom: 0, trailing: 6))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    @ViewBuilder
    private func groupCompletionCelebration(for tag: String) -> some View {
        GroupCompletionCelebrationView(text: L.groupCompleted(tag))
            .padding(.leading, 28)
            .padding(.trailing, 14)
            .padding(.vertical, 6)
            .listRowInsets(EdgeInsets(top: 0, leading: 6, bottom: 4, trailing: 6))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .transition(.opacity.combined(with: .move(edge: .top)))
    }

    /// 底部新建分组行
    @ViewBuilder
    private var inlineAddGroupRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(CreamTheme.green.opacity(addingNewGroup ? 0.9 : 0.6))
                .frame(width: 22)

            if addingNewGroup {
                TextField(L.newGroupExample, text: $newGroupText)
                    .textFieldStyle(.plain)
                    .font(.callout)
                    .submitLabel(.done)
                    .focused($newGroupFocused)
                    .onSubmit(commitInlineAddGroup)
            } else {
                Text(L.newGroupButton)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(CreamTheme.green.opacity(0.8))
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            if !addingNewGroup {
                addingNewGroup = true
                newGroupText = ""
                newGroupFocused = true
            }
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 6, bottom: 4, trailing: 6))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private func commitInlineAddItem(forGroup tag: String) {
        let clean = addingItemText.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty {
            // 空输入 + 回车 → 退出 inline
            addingItemForGroup = nil
            addItemFocused = false
            return
        }
        let ok = store.addDailyCheckItem(clean, tag: tag)
        if ok {
            addingItemText = ""
            addingItemForGroup = nil
            addItemFocused = false
        } else {
            inlineErrorMsg = L.duplicateItem
        }
    }

    private func startAddingItem(forGroup tag: String) {
        if isTagCollapsed(tag) {
            toggleCollapse(tag)
        }
        endSorting()
        addingItemForGroup = tag
        addingItemText = ""
        DispatchQueue.main.async {
            addItemFocused = true
        }
    }

    private func startSorting(group tag: String) {
        guard sortingGroup != tag else { return }
        sortingGroups = false
        addingItemForGroup = nil
        addingItemText = ""
        addItemFocused = false
        if isTagCollapsed(tag) {
            toggleCollapse(tag)
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            sortingGroup = tag
        }
    }

    private func startSortingGroups() {
        guard !sortingGroups else { return }
        sortingGroup = nil
        addingItemForGroup = nil
        addingItemText = ""
        addItemFocused = false
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            sortingGroups = true
        }
    }

    private func endSorting() {
        guard sortingGroup != nil || sortingGroups else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.26, dampingFraction: 0.9)) {
            sortingGroup = nil
            sortingGroups = false
        }
    }

    private func isGroupComplete(_ tag: String) -> Bool {
        guard !tag.isEmpty else { return false }
        let items = store.checkItems.filter { $0.tag == tag }
        return !items.isEmpty && items.allSatisfy(\.done)
    }

    private func showGroupCompletion(for tag: String) {
        guard !tag.isEmpty else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            celebratingGroup = tag
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            guard celebratingGroup == tag else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                celebratingGroup = nil
            }
        }
    }

    private func commitInlineAddGroup() {
        let clean = newGroupText.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty {
            addingNewGroup = false
            newGroupFocused = false
            return
        }
        let ok = store.addDailyCheckGroup(clean)
        if ok {
            newGroupText = ""
            addingNewGroup = false
            newGroupFocused = false
        } else {
            inlineErrorMsg = L.duplicateGroup
        }
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

    /// 当前展示的分组顺序（来自 AppStore，已包含空分组；不含未分组）
    private var groupedCheckTags: [String] {
        store.dailyCheckGroups
    }

    /// 没有归到任何分组的打卡项（tag 为空），单独排在最后，无 header 渲染
    private var untaggedCheckItems: [DailyCheckItem] {
        store.checkItems.filter { $0.tag.isEmpty }
    }


    // MARK: - Todo Section

    private var pendingTasks: [TaskEntry] {
        store.tasks.filter { $0.status != "已完成" }
    }

    private var doneTasks: [TaskEntry] {
        store.tasks
            .filter { $0.status == "已完成" }
            .sorted { completedSortDate($0) > completedSortDate($1) }
    }

    private var completedTaskGroups: [CompletedTaskGroup] {
        let grouped = Dictionary(grouping: doneTasks) { completionDayKey(for: $0) }
        return grouped.map { key, tasks in
            CompletedTaskGroup(
                id: key,
                title: completionGroupTitle(for: key),
                tasks: tasks.sorted { completedSortDate($0) > completedSortDate($1) }
            )
        }
        .sorted { $0.id > $1.id }
    }

    @ViewBuilder
    private var todoSection: some View {
        // 新建待办 —— 快速输入
        Section {
            // 快速输入（只取标题，默认今天、全天、无优先级）
            HStack(spacing: 10) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(CreamTheme.green.opacity(0.8))

                TextField(L.todoQuickAddPlaceholder, text: $newTodoTitle)
                    .textFieldStyle(.plain)
                    .submitLabel(.done)
                    .onSubmit(commitNewTodo)

                if !newTodoTitle.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button(L.todoAddButton, action: commitNewTodo)
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
        }

        // 未完成
        if !pendingTasks.isEmpty {
            Section {
                ForEach(pendingTasks) { task in
                    todoRow(task)
                }
            } header: {
                Text("\(L.todoPendingHeader) · \(pendingTasks.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        } else {
            Section {
                Text(L.emptyTodoMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 16)
                    .listRowInsets(EdgeInsets(top: 8, leading: 6, bottom: 8, trailing: 6))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }

        // 已完成：默认折叠，需要时按完成日期展开查看。
        if !doneTasks.isEmpty {
            Section {
                completedTasksSummaryRow

                if completedTasksExpanded {
                    ForEach(completedTaskGroups) { group in
                        completedGroupHeader(group)

                        ForEach(group.tasks) { task in
                            completedTodoRow(task)
                        }
                    }
                }
            } header: {
                Text("\(L.todoDoneHeader) · \(doneTasks.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var completedTasksSummaryRow: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    completedTasksExpanded.toggle()
                }
            } label: {
                Image(systemName: completedTasksExpanded ? "chevron.down.circle.fill" : "chevron.right.circle.fill")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(CreamTheme.green.opacity(0.82))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        completedTasksExpanded.toggle()
                    }
                } label: {
                    Text(completedTasksExpanded ? L.collapseCompleted : L.viewCompleted)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)

                if let latest = doneTasks.first {
                    Text("\(L.lastCompleted)\(latest.title)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Text("\(doneTasks.count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color(.secondarySystemFill)))

            Button(L.clearButton) {
                showingCompletedClearOptions = true
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(CreamTheme.green)
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
    }

    private func completedGroupHeader(_ group: CompletedTaskGroup) -> some View {
        Text(group.title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .listRowInsets(EdgeInsets(top: 0, leading: 6, bottom: 0, trailing: 6))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    @ViewBuilder
    private func todoRow(_ task: TaskEntry) -> some View {
        let done = task.status == "已完成"
        let isSelected = selectedTodoID == task.id
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
                    .frame(width: 24, height: 24, alignment: .center)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // 标题/详情区
            VStack(alignment: .leading, spacing: 4) {
                if editingTodoTitleID == task.id {
                    TextField(L.titleLabel, text: $editingTodoTitleText)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(done ? .secondary : .primary)
                        .textFieldStyle(.plain)
                        .submitLabel(.done)
                        .focused($focusedTodoTitleID, equals: task.id)
                        .frame(minHeight: 24, alignment: .center)
                        .onSubmit { commitInlineTodoTitle(task) }
                } else {
                    Text(task.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(done ? .secondary : .primary)
                        .frame(minHeight: 24, alignment: .center)
                }

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
            .onTapGesture {
                selectTodoForInlineEditing(task)
            }

            if isSelected {
                Button {
                    commitInlineTodoTitle(task)
                    editingTask = task
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 21, weight: .medium))
                        .foregroundStyle(CreamTheme.green)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .onChange(of: focusedTodoTitleID) { focusedID in
            if editingTodoTitleID == task.id && focusedID != task.id {
                commitInlineTodoTitle(task)
            }
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
                Label(L.delete, systemImage: "trash")
            }
        }
    }

    private func completedTodoRow(_ task: TaskEntry) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    store.toggleTask(task)
                }
            } label: {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Color(.tertiaryLabel))
                    .frame(width: 24, height: 24, alignment: .center)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 5) {
                Text(task.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .strikethrough(true, color: Color(.tertiaryLabel))
                    .frame(minHeight: 24, alignment: .center)

                if !task.detail.isEmpty {
                    Text(task.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Text(completedMetaLine(for: task))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                editingTask = task
            }

            Button {
                editingTask = task
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Color(.tertiaryLabel))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.58))
        )
        .listRowInsets(EdgeInsets(top: 3, leading: 6, bottom: 3, trailing: 6))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                store.removeTask(id: task.id)
            } label: {
                Label(L.delete, systemImage: "trash")
            }
        }
    }

    private func selectTodoForInlineEditing(_ task: TaskEntry) {
        if let currentID = editingTodoTitleID,
           currentID != task.id,
           let currentTask = store.tasks.first(where: { $0.id == currentID }) {
            commitInlineTodoTitle(currentTask)
        }

        selectedTodoID = task.id
        editingTodoTitleID = task.id
        editingTodoTitleText = task.title
        focusedTodoTitleID = task.id
    }

    private func commitInlineTodoTitle(_ task: TaskEntry) {
        guard editingTodoTitleID == task.id else { return }
        let clean = editingTodoTitleText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !clean.isEmpty, clean != task.title {
            store.updateTask(
                id: task.id,
                title: clean,
                detail: task.detail,
                priority: task.priority,
                dueDate: task.dueDate,
                isAllDay: task.isAllDay,
                startTime: task.startTime,
                endTime: task.endTime,
                location: task.location
            )
        }
        editingTodoTitleID = nil
        editingTodoTitleText = ""
        focusedTodoTitleID = nil
    }

    private func completedMetaLine(for task: TaskEntry) -> String {
        guard let completedAt = task.completedAt else {
            return "\(L.completedAt)\(L.completedAtUnknown)"
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: L.localeId)
        formatter.dateFormat = L.isEn ? "MMM d, yy h:mm a" : "M/d/yy a h:mm"
        return "\(L.completedAt)\(formatter.string(from: completedAt))"
    }

    private func completedTaskCount(for scope: CompletedTaskClearScope) -> Int {
        guard let cutoff = scope.cutoff else { return doneTasks.count }
        return doneTasks.filter { completedSortDate($0) < cutoff }.count
    }

    private func completedSortDate(_ task: TaskEntry) -> Date {
        task.completedAt ?? dateFromKey(task.date) ?? .distantPast
    }

    private func completionDayKey(for task: TaskEntry) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: completedSortDate(task))
    }

    private func completionGroupTitle(for key: String) -> String {
        guard let date = dateFromKey(key) else { return key }
        let cal = Calendar.current
        if cal.isDateInToday(date) { return L.today }
        if cal.isDateInYesterday(date) { return L.yesterday }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: L.localeId)
        formatter.dateFormat = L.isEn ? "MMM d, EEEE" : "M月d日 EEEE"
        return formatter.string(from: date)
    }

    private func dateFromKey(_ key: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: key)
    }

    /// 组装时间/日期元信息行（比如 "今天" 或 "4月18日 · 09:00-10:30"）
    private func metaLineFor(_ task: TaskEntry) -> String? {
        var parts: [String] = []
        if !task.dueDate.isEmpty {
            parts.append(shortDateLabel(task.dueDate))
        }
        if !task.startTime.isEmpty {
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
        if cal.isDateInToday(d) { return L.today }
        if cal.isDateInTomorrow(d) { return L.tomorrow }
        if cal.isDateInYesterday(d) { return L.yesterday }
        let out = DateFormatter()
        out.locale = Locale(identifier: L.localeId)
        out.dateFormat = L.isEn ? "MMM d" : "M月d日"
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
                    Text(L.dailyQuoteLabel)
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

    private typealias Quote = L.Quote

    private var dailyQuote: Quote {
        let quotes = L.dailyQuotes
        let dayNumber = Calendar.current.ordinality(of: .day, in: .year, for: store.selectedDate) ?? 0
        return quotes[(dayNumber + quoteOffset) % quotes.count]
    }

    private var todayTopDateBar: some View {
        HStack(spacing: 12) {
            Text(segment == "check" ? L.dailyCheckTitle : L.todoTitle)
                .font(.headline.weight(.semibold))
                .animation(.easeInOut(duration: 0.15), value: segment)

            Spacer(minLength: 6)

            Button {
                displayMonth = startOfMonth(for: store.selectedDate)
                withAnimation(.easeOut(duration: 0.10)) {
                    showCalendarOverlay.toggle()
                }
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
                calendarTraceKeys.contains(store.calendarDateKey(for: day)) ? .dot(CreamTheme.green) : .none
            }
        )
    }

    private func refreshCalendarMarkers() {
        calendarTraceKeys = store.recordTraceDateKeys(inMonth: displayMonth)
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

private struct GroupCompletionCelebrationView: View {
    let text: String

    @State private var sparkle = false

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(CreamTheme.green)
                    .scaleEffect(sparkle ? 1.12 : 0.9)

                ForEach(0..<5, id: \.self) { index in
                    Circle()
                        .fill(sparkColor(index))
                        .frame(width: 4, height: 4)
                        .offset(sparkle ? sparkOffset(index) : .zero)
                        .opacity(sparkle ? 0 : 0.9)
                }
            }
            .frame(width: 28, height: 28)

            Text(text)
                .font(.footnote.weight(.medium))
                .foregroundStyle(CreamTheme.text.opacity(0.78))

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 13)
                .fill(CreamTheme.green.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13)
                .stroke(CreamTheme.green.opacity(0.14), lineWidth: 1)
        )
        .onAppear {
            withAnimation(.easeOut(duration: 0.8)) {
                sparkle = true
            }
        }
    }

    private func sparkOffset(_ index: Int) -> CGSize {
        let offsets = [
            CGSize(width: -13, height: -10),
            CGSize(width: 12, height: -11),
            CGSize(width: -16, height: 6),
            CGSize(width: 15, height: 7),
            CGSize(width: 0, height: -17)
        ]
        return offsets[index % offsets.count]
    }

    private func sparkColor(_ index: Int) -> Color {
        [CreamTheme.green, Color(red: 0.94, green: 0.70, blue: 0.28), Color(red: 0.55, green: 0.72, blue: 0.45)][index % 3]
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
