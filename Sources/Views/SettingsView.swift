import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    @AppStorage("auth.user") private var user = ""
    @AppStorage(DailyStateReminderService.enabledKey) private var dailyReminderEnabled = false
    @AppStorage(DailyStateReminderService.hourKey) private var dailyReminderHour = DailyStateReminderService.defaultHour
    @AppStorage(DailyStateReminderService.minuteKey) private var dailyReminderMinute = DailyStateReminderService.defaultMinute

    @State private var showDeleteConfirm = false
    @State private var reminderStatusText = "只在本机提醒，不上传你的记录。"

    @State private var editingField: ProfileField?
    @State private var draftValue = ""

    var body: some View {
        NavigationStack {
            List {
                iCloudSection
                healthKitSection
                dailyReminderSection

                Section("账号信息") {
                    editableProfileRow(title: "昵称", value: displayNickname, field: .nickname)
                }

                Section("数据") {
                    NavigationLink {
                        ExportView()
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(CreamTheme.green.opacity(0.12))
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 17, weight: .semibold))
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(CreamTheme.green)
                            }
                            .frame(width: 36, height: 36)

                            VStack(alignment: .leading, spacing: 3) {
                                Text("导出 CSV")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(CreamTheme.text)
                            }
                        }
                    }

                    NavigationLink {
                        AIDebugLogListView()
                            .environmentObject(store)
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(CreamTheme.green.opacity(0.12))
                                Image(systemName: "stethoscope")
                                    .font(.system(size: 17, weight: .semibold))
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(CreamTheme.green)
                            }
                            .frame(width: 36, height: 36)

                            VStack(alignment: .leading, spacing: 3) {
                                Text("AI 调试记录")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(CreamTheme.text)
                                Text("仅本机保存最近 20 条")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section {
                    Button("清空所有数据", role: .destructive) {
                        showDeleteConfirm = true
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("将永久删除本设备上的所有记录，是否继续？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("确认清空", role: .destructive) {
                    wipeAllData()
                }
                Button("取消", role: .cancel) {}
            }
            .sheet(item: $editingField) { field in
                editProfileSheet(field)
            }
            .listStyle(.insetGrouped)
            .tint(CreamTheme.green)
            .scrollContentBackground(.hidden)
            .background(CreamTheme.glassStrong)
        }
        .creamBackground()
    }

    @ViewBuilder
    private var iCloudSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { store.isICloudSyncEnabled },
                set: { store.setICloudSyncEnabled($0) }
            )) {
                HStack(spacing: 12) {
                    syncGlyph

                    VStack(alignment: .leading, spacing: 3) {
                        Text("iCloud 同步")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(CreamTheme.text)
                        Text(store.iCloudSyncStatusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .tint(CreamTheme.green)
        } header: {
            Text("同步")
        }
    }

    private var syncGlyph: some View {
        ZStack {
            Circle()
                .fill(CreamTheme.green.opacity(0.12))
            Image(systemName: "icloud")
                .font(.system(size: 19, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(CreamTheme.green)
        }
        .frame(width: 36, height: 36)
    }

    @ViewBuilder
    private var healthKitSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { store.isHealthSleepSyncEnabled },
                set: { store.setHealthSleepSyncEnabled($0) }
            )) {
                healthKitRow(
                    icon: "bed.double",
                    title: "同步睡眠"
                )
            }
            .tint(CreamTheme.green)

            Toggle(isOn: Binding(
                get: { store.isHealthWorkoutSyncEnabled },
                set: { store.setHealthWorkoutSyncEnabled($0) }
            )) {
                healthKitRow(
                    icon: "figure.run",
                    title: "同步运动"
                )
            }
            .tint(CreamTheme.green)

            Button {
                store.syncHealthKitNow()
            } label: {
                HStack {
                    Text("立即同步")
                        .font(.body.weight(.semibold))
                    Spacer()
                    Image(systemName: "arrow.clockwise")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(CreamTheme.green)
            }
            .disabled(!store.isHealthSleepSyncEnabled && !store.isHealthWorkoutSyncEnabled)
        } header: {
            Text("Apple 健康")
        }
    }

    private func healthKitRow(icon: String, title: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(CreamTheme.green.opacity(0.12))
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(CreamTheme.green)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(CreamTheme.text)
            }
        }
    }

    @ViewBuilder
    private var dailyReminderSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { dailyReminderEnabled },
                set: { enabled in
                    dailyReminderEnabled = enabled
                    if enabled {
                        scheduleDailyReminder()
                    } else {
                        DailyStateReminderService.cancel()
                        reminderStatusText = "已关闭。你可以随时再打开。"
                    }
                }
            )) {
                reminderRow
            }
            .tint(CreamTheme.green)

            if dailyReminderEnabled {
                DatePicker(
                    "提醒时间",
                    selection: Binding(
                        get: {
                            DailyStateReminderService.reminderDate(hour: dailyReminderHour, minute: dailyReminderMinute)
                        },
                        set: { newDate in
                            let value = DailyStateReminderService.hourAndMinute(from: newDate)
                            dailyReminderHour = value.hour
                            dailyReminderMinute = value.minute
                            scheduleDailyReminder()
                        }
                    ),
                    displayedComponents: .hourAndMinute
                )
            }
        } header: {
            Text("提醒")
        } footer: {
            Text(reminderStatusText)
        }
    }

    private var reminderRow: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(CreamTheme.green.opacity(0.12))
                Image(systemName: "bell.badge")
                    .font(.system(size: 17, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(CreamTheme.green)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 3) {
                Text("每日状态提醒")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(CreamTheme.text)
                Text("到点轻轻提醒你记录一下今天")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func scheduleDailyReminder() {
        let hour = dailyReminderHour
        let minute = dailyReminderMinute
        reminderStatusText = "正在设置本机提醒..."
        Task {
            let granted = await DailyStateReminderService.schedule(hour: hour, minute: minute)
            await MainActor.run {
                if granted {
                    dailyReminderEnabled = true
                    reminderStatusText = "每天 \(String(format: "%02d:%02d", hour, minute)) 提醒。只在本机提醒，不上传你的记录。"
                } else {
                    dailyReminderEnabled = false
                    reminderStatusText = "没有通知权限。可以在系统设置里为 LifeOS 打开通知。"
                }
            }
        }
    }

    private var displayNickname: String {
        let clean = user.trimmingCharacters(in: .whitespacesAndNewlines)
        if !clean.isEmpty { return clean }
        return defaultNickname
    }

    private var defaultNickname: String {
        let raw = store.currentAuthUserId
        let suffixSource = raw.isEmpty ? "LOCAL" : raw
        let suffix = String(suffixSource.suffix(4)).uppercased()
        return "用户-\(suffix)"
    }

    @ViewBuilder
    private func editableProfileRow(title: String, value: String, field: ProfileField) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
            Button {
                draftValue = rawValue(for: field)
                editingField = field
            } label: {
                Image(systemName: "pencil")
                    .foregroundStyle(CreamTheme.green)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func editProfileSheet(_ field: ProfileField) -> some View {
        NavigationStack {
            Form {
                TextField(field.title, text: $draftValue)
            }
            .navigationTitle("修改\(field.title)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { editingField = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        saveDraftValue(for: field)
                        editingField = nil
                    }
                    .disabled(draftValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func rawValue(for field: ProfileField) -> String {
        switch field {
        case .nickname: return displayNickname
        }
    }

    private func saveDraftValue(for field: ProfileField) {
        let clean = draftValue.trimmingCharacters(in: .whitespacesAndNewlines)
        switch field {
        case .nickname:
            user = clean.isEmpty ? user : clean
        }
    }

    /// 清空当前设备的全部本地记录。保留 `auth.userId`，继续用同一个身份继续使用。
    private func wipeAllData() {
        store.wipeCurrentUserData()
        UserDefaults.standard.removeObject(forKey: "auth.user")
        user = ""
    }
}

private enum ProfileField: String, Identifiable {
    case nickname

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nickname: return "昵称"
        }
    }
}

private struct AIDebugLogListView: View {
    @EnvironmentObject var store: AppStore
    @State private var showClearConfirm = false
    @State private var isSelecting = false
    @State private var selectedLogIDs: Set<UUID> = []
    @State private var batchExportFileURL: URL?

    var body: some View {
        List {
            Section {
                if store.aiDebugLogs.isEmpty {
                    Text("还没有 AI 调试记录")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.aiDebugLogs) { log in
                        if isSelecting {
                            Button {
                                toggleSelection(for: log)
                            } label: {
                                HStack(spacing: 12) {
                                    selectionIcon(for: log)
                                    logRow(log)
                                }
                            }
                            .buttonStyle(.plain)
                        } else {
                            NavigationLink {
                                AIDebugLogDetailView(log: log)
                            } label: {
                                logRow(log)
                            }
                        }
                    }
                }
            } header: {
                Text(isSelecting ? "已选择 \(selectedLogIDs.count) 条" : "最近记录")
            } footer: {
                Text("包含原始输入和 AI 返回内容，只保存在当前设备。")
            }
        }
        .navigationTitle("AI 调试记录")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if !store.aiDebugLogs.isEmpty {
                    Button(isSelecting ? "取消" : "选择") {
                        setSelectionMode(!isSelecting)
                    }
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                if isSelecting {
                    if let batchExportFileURL, !selectedLogIDs.isEmpty {
                        ShareLink(item: batchExportFileURL) {
                            Text("导出")
                        }
                    } else {
                        Button("导出") {}
                            .disabled(true)
                    }
                } else {
                    Button("清空") { showClearConfirm = true }
                        .disabled(store.aiDebugLogs.isEmpty)
                }
            }
        }
        .confirmationDialog("清空本机 AI 调试记录？", isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("清空", role: .destructive) {
                store.clearAIDebugLogs()
                setSelectionMode(false)
            }
            Button("取消", role: .cancel) {}
        }
        .onChange(of: selectedLogIDs) { _ in
            refreshBatchExportFile()
        }
        .onChange(of: store.aiDebugLogs) { logs in
            selectedLogIDs = selectedLogIDs.intersection(Set(logs.map(\.id)))
            refreshBatchExportFile()
        }
        .listStyle(.insetGrouped)
        .tint(CreamTheme.green)
        .scrollContentBackground(.hidden)
        .background(CreamTheme.glassStrong)
    }

    private var selectedLogs: [AIDebugLog] {
        store.aiDebugLogs.filter { selectedLogIDs.contains($0.id) }
    }

    private func setSelectionMode(_ enabled: Bool) {
        isSelecting = enabled
        if !enabled {
            selectedLogIDs = []
            batchExportFileURL = nil
        }
    }

    private func toggleSelection(for log: AIDebugLog) {
        if selectedLogIDs.contains(log.id) {
            selectedLogIDs.remove(log.id)
        } else {
            selectedLogIDs.insert(log.id)
        }
    }

    private func refreshBatchExportFile() {
        batchExportFileURL = AIDebugLogMarkdownExporter.makeFile(for: selectedLogs)
    }

    private func logRow(_ log: AIDebugLog) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(log.input)
                .font(.body.weight(.semibold))
                .foregroundStyle(CreamTheme.text)
                .lineLimit(2)
            HStack(spacing: 8) {
                Text(log.createdAt, style: .time)
                Text("\(log.recordsSummary.count) records")
                if !log.errorMessage.isEmpty {
                    Text("失败")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func selectionIcon(for log: AIDebugLog) -> some View {
        Image(systemName: selectedLogIDs.contains(log.id) ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(selectedLogIDs.contains(log.id) ? CreamTheme.green : .secondary)
            .frame(width: 28, height: 28)
    }
}

private struct AIDebugLogDetailView: View {
    let log: AIDebugLog
    @State private var exportFileURL: URL?

    var body: some View {
        List {
            detailSection("输入", rows: [log.input])
            detailSection("请求上下文", rows: [
                "currentDate=\(log.currentDate)",
                "currentTime=\(log.currentTime)"
            ])
            detailSection("AI records", rows: emptyFallback(log.recordsSummary))
            detailSection("App commit", rows: emptyFallback(log.commitSummary))
            if !log.needsClarification.isEmpty {
                detailSection("追问", rows: [log.needsClarification])
            }
            if !log.errorMessage.isEmpty {
                detailSection("错误", rows: [log.errorMessage])
            }
            detailSection("Raw JSON", rows: [log.rawResponse.isEmpty ? "无" : log.rawResponse])
        }
        .navigationTitle(log.createdAt.formatted(date: .abbreviated, time: .shortened))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let exportFileURL {
                    ShareLink(item: exportFileURL) {
                        Image(systemName: "square.and.arrow.up")
                    }
                } else {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear {
            exportFileURL = makeMarkdownExportFile()
        }
        .listStyle(.insetGrouped)
        .tint(CreamTheme.green)
        .scrollContentBackground(.hidden)
        .background(CreamTheme.glassStrong)
    }

    private func makeMarkdownExportFile() -> URL? {
        AIDebugLogMarkdownExporter.makeFile(for: [log])
    }

    private func detailSection(_ title: String, rows: [String]) -> some View {
        Section(title) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                Text(row)
                    .font(.footnote)
                    .textSelection(.enabled)
            }
        }
    }

    private func emptyFallback(_ rows: [String]) -> [String] {
        rows.isEmpty ? ["无"] : rows
    }
}

private enum AIDebugLogMarkdownExporter {
    static func makeFile(for logs: [AIDebugLog]) -> URL? {
        guard !logs.isEmpty else { return nil }
        let filename: String
        if logs.count == 1, let log = logs.first {
            filename = "lifeos-ai-debug-\(filenameTimestamp.string(from: log.createdAt)).md"
        } else {
            filename = "lifeos-ai-debug-\(filenameTimestamp.string(from: Date()))-\(logs.count).md"
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try markdown(for: logs).write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    static func markdown(for logs: [AIDebugLog]) -> String {
        guard !logs.isEmpty else { return "" }
        if logs.count == 1, let log = logs.first {
            return """
            # LifeOS AI Debug Log

            \(markdownBody(for: log, headingLevel: 2))
            """
        }

        return """
        # LifeOS AI Debug Logs

        - Exported At: \(Date().formatted(date: .complete, time: .complete))
        - Count: \(logs.count)

        \(logs.map { markdownBody(for: $0, headingLevel: 2) }.joined(separator: "\n\n---\n\n"))
        """
    }

    private static let filenameTimestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()

    private static func markdownBody(for log: AIDebugLog, headingLevel: Int) -> String {
        let h = String(repeating: "#", count: headingLevel)
        let childH = String(repeating: "#", count: headingLevel + 1)
        return """
        \(h) \(log.createdAt.formatted(date: .abbreviated, time: .shortened))

        - Created At: \(log.createdAt.formatted(date: .complete, time: .complete))
        - Current Date: \(log.currentDate)
        - Current Time: \(log.currentTime)

        \(childH) Input
        \(log.input)

        \(childH) AI Records
        \(joined(log.recordsSummary))

        \(childH) App Commit
        \(joined(log.commitSummary))

        \(childH) Needs Clarification
        \(log.needsClarification.isEmpty ? "无" : log.needsClarification)

        \(childH) Error
        \(log.errorMessage.isEmpty ? "无" : log.errorMessage)

        \(childH) Raw JSON
        ```json
        \(log.rawResponse.isEmpty ? "无" : log.rawResponse)
        ```
        """
    }

    private static func joined(_ rows: [String]) -> String {
        rows.isEmpty ? "无" : rows.map { "- \($0)" }.joined(separator: "\n")
    }
}
