import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    @AppStorage("auth.user") private var user = ""
    @AppStorage(DailyStateReminderService.enabledKey) private var dailyReminderEnabled = false
    @AppStorage(DailyStateReminderService.hourKey) private var dailyReminderHour = DailyStateReminderService.defaultHour
    @AppStorage(DailyStateReminderService.minuteKey) private var dailyReminderMinute = DailyStateReminderService.defaultMinute

    @State private var showDeleteConfirm = false

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
                        AgentDebugLogListView()
                            .environmentObject(store)
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(CreamTheme.green.opacity(0.12))
                                Image(systemName: "bubble.left.and.text.bubble.right")
                                    .font(.system(size: 17, weight: .semibold))
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(CreamTheme.green)
                            }
                            .frame(width: 36, height: 36)

                            VStack(alignment: .leading, spacing: 3) {
                                Text("AI 聊天调试")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(CreamTheme.text)
                                Text("导出猫猫对话请求与返回")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    NavigationLink {
                        AgentMemoryListView()
                            .environmentObject(store)
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(Color.purple.opacity(0.12))
                                Image(systemName: "brain.head.profile")
                                    .font(.system(size: 17, weight: .semibold))
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(.purple)
                            }
                            .frame(width: 36, height: 36)

                            VStack(alignment: .leading, spacing: 3) {
                                Text("Agent 记忆")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(CreamTheme.text)
                                Text("\(store.agentMemories.count) 条记忆")
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
            .alert("同步完成", isPresented: Binding(
                get: { store.healthSyncCompletionMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        store.healthSyncCompletionMessage = nil
                    }
                }
            )) {
                Button("知道了") {
                    store.healthSyncCompletionMessage = nil
                }
            } message: {
                Text(store.healthSyncCompletionMessage ?? "")
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
                    title: "同步睡眠",
                    subtitle: store.healthSyncStatusText
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

            Toggle(isOn: Binding(
                get: { store.isWakeDreamReminderEnabled },
                set: { store.setWakeDreamReminderEnabled($0) }
            )) {
                healthKitRow(
                    icon: "cloud.moon",
                    title: "醒后梦境提醒"
                )
            }
            .tint(CreamTheme.green)
            .disabled(!store.isHealthSleepSyncEnabled)

            Button {
                store.syncHealthKitNow(showCompletionAlert: true)
            } label: {
                HStack {
                    Text(store.isHealthSyncing ? "同步中..." : "立即同步")
                        .font(.body.weight(.semibold))
                    Spacer()
                    if store.isHealthSyncing {
                        ProgressView()
                            .tint(CreamTheme.green)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption.weight(.semibold))
                    }
                }
                .foregroundStyle(CreamTheme.green)
            }
            .disabled(store.isHealthSyncing || (!store.isHealthSleepSyncEnabled && !store.isHealthWorkoutSyncEnabled))
        } header: {
            Text("Apple 健康")
        }
    }

    private func healthKitRow(icon: String, title: String, subtitle: String? = nil) -> some View {
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
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
            }
        }
    }

    private func scheduleDailyReminder() {
        let hour = dailyReminderHour
        let minute = dailyReminderMinute
        Task {
            let granted = await DailyStateReminderService.schedule(hour: hour, minute: minute)
            await MainActor.run {
                if granted {
                    dailyReminderEnabled = true
                } else {
                    dailyReminderEnabled = false
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

private struct AgentMemoryListView: View {
    @EnvironmentObject var store: AppStore
    @State private var newMemoryText = ""

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("手动添加一条记忆", text: $newMemoryText)
                        .textFieldStyle(.plain)
                    Button {
                        store.addAgentMemory(content: newMemoryText)
                        newMemoryText = ""
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(CreamTheme.green)
                    }
                    .disabled(newMemoryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            Section {
                if store.agentMemories.isEmpty {
                    Text("还没有记忆")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.agentMemories) { memory in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(memory.content)
                                .font(.subheadline)
                            HStack(spacing: 8) {
                                Text(memory.category)
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.purple.opacity(0.1)))
                                    .foregroundStyle(.purple)
                                Text(memory.source == "auto" ? "自动提取" : "手动添加")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(memory.createdAt, style: .date)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            store.removeAgentMemory(id: store.agentMemories[index].id)
                        }
                    }
                }
            }
        }
        .navigationTitle("Agent 记忆")
    }
}

private struct AgentDebugLogListView: View {
    @EnvironmentObject var store: AppStore
    @State private var showClearConfirm = false
    @State private var exportFileURL: URL?

    var body: some View {
        List {
            Section {
                if store.agentDebugLogs.isEmpty {
                    Text("还没有 AI 聊天调试记录")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.agentDebugLogs) { log in
                        NavigationLink {
                            AgentDebugLogDetailView(log: log)
                        } label: {
                            logRow(log)
                        }
                    }
                }
            } header: {
                Text("最近记录")
            } footer: {
                Text("未配置云端 Agent Trace 时，这里保留最近 20 条本机调试记录；配置后完整日志会统一上传到 trace 服务。")
            }
        }
        .navigationTitle("AI 聊天调试")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if let exportFileURL, !store.agentDebugLogs.isEmpty {
                    ShareLink(item: exportFileURL) {
                        Text("导出")
                    }
                } else {
                    Button("导出") {}
                        .disabled(true)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("清空") { showClearConfirm = true }
                    .disabled(store.agentDebugLogs.isEmpty)
            }
        }
        .confirmationDialog("清空本机 AI 聊天调试记录？", isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("清空", role: .destructive) {
                store.clearAgentDebugLogs()
                refreshExportFile()
            }
            Button("取消", role: .cancel) {}
        }
        .onAppear { refreshExportFile() }
        .onChange(of: store.agentDebugLogs) { _ in refreshExportFile() }
        .listStyle(.insetGrouped)
        .tint(CreamTheme.green)
        .scrollContentBackground(.hidden)
        .background(CreamTheme.glassStrong)
    }

    private func refreshExportFile() {
        exportFileURL = AgentDebugLogMarkdownExporter.makeFile(for: store.agentDebugLogs)
    }

    private func logRow(_ log: AgentChatDebugLog) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(log.input)
                .font(.body.weight(.semibold))
                .foregroundStyle(CreamTheme.text)
                .lineLimit(2)
            HStack(spacing: 8) {
                Text(log.createdAt, style: .time)
                Text("\(log.actionSuggestionsSummary.count) suggested")
                Text("\(log.mergedActionSummary.count) merged")
                if !log.errorMessage.isEmpty {
                    Text("失败")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct AgentDebugLogDetailView: View {
    let log: AgentChatDebugLog
    @State private var exportFileURL: URL?

    var body: some View {
        List {
            detailSection("输入", rows: [log.input])
            detailSection("请求上下文", rows: [
                "currentDate=\(log.currentDate)",
                "currentTime=\(log.currentTime)"
            ])
            detailSection("猫猫人格", rows: [log.personaSummary.isEmpty ? "无" : log.personaSummary])
            detailSection("用户信息", rows: [log.userSummary.isEmpty ? "无" : log.userSummary])
            detailSection("聊天历史", rows: emptyFallback(log.messagesSummary))
            detailSection("LifeOS 上下文", rows: [log.contextSummary.isEmpty ? "无" : log.contextSummary])
            detailSection("回复", rows: [log.reply])
            detailSection("追问", rows: [log.followUpQuestion.isEmpty ? "无" : log.followUpQuestion])
            detailSection("AI 建议", rows: emptyFallback(log.actionSuggestionsSummary))
            detailSection("进入卡片队列", rows: emptyFallback(log.mergedActionSummary))
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
            exportFileURL = AgentDebugLogMarkdownExporter.makeFile(for: [log])
        }
        .listStyle(.insetGrouped)
        .tint(CreamTheme.green)
        .scrollContentBackground(.hidden)
        .background(CreamTheme.glassStrong)
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

private enum AgentDebugLogMarkdownExporter {
    static func makeFile(for logs: [AgentChatDebugLog]) -> URL? {
        guard !logs.isEmpty else { return nil }
        let filename: String
        if logs.count == 1, let log = logs.first {
            filename = "lifeos-agent-debug-\(filenameTimestamp.string(from: log.createdAt)).md"
        } else {
            filename = "lifeos-agent-debug-\(filenameTimestamp.string(from: Date()))-\(logs.count).md"
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try markdown(for: logs).write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    private static let filenameTimestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()

    private static func markdown(for logs: [AgentChatDebugLog]) -> String {
        guard !logs.isEmpty else { return "" }
        if logs.count == 1, let log = logs.first {
            return """
            # LifeOS Agent Debug Log

            \(markdownBody(for: log, headingLevel: 2))
            """
        }
        return """
        # LifeOS Agent Debug Logs

        - Exported At: \(Date().formatted(date: .complete, time: .complete))
        - Count: \(logs.count)

        \(logs.map { markdownBody(for: $0, headingLevel: 2) }.joined(separator: "\n\n---\n\n"))
        """
    }

    private static func markdownBody(for log: AgentChatDebugLog, headingLevel: Int) -> String {
        let h = String(repeating: "#", count: headingLevel)
        let childH = String(repeating: "#", count: headingLevel + 1)
        return """
        \(h) \(log.createdAt.formatted(date: .abbreviated, time: .shortened))

        - Created At: \(log.createdAt.formatted(date: .complete, time: .complete))
        - Current Date: \(log.currentDate)
        - Current Time: \(log.currentTime)

        \(childH) Input
        \(log.input)

        \(childH) Agent Persona
        \(log.personaSummary.isEmpty ? "无" : log.personaSummary)

        \(childH) User Summary
        \(log.userSummary.isEmpty ? "无" : log.userSummary)

        \(childH) Messages Sent
        \(joined(log.messagesSummary))

        \(childH) Context Summary
        \(log.contextSummary.isEmpty ? "无" : log.contextSummary)

        \(childH) Reply
        \(log.reply)

        \(childH) Follow-up Question
        \(log.followUpQuestion.isEmpty ? "无" : log.followUpQuestion)

        \(childH) AI Action Suggestions
        \(joined(log.actionSuggestionsSummary))

        \(childH) Merged Into Pending Cards
        \(joined(log.mergedActionSummary))

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
