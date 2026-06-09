import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    @AppStorage("auth.user") private var user = ""
    @AppStorage("app.language") private var appLanguage = "zh"
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

                Section(L.accountSection) {
                    editableProfileRow(title: L.nickname, value: displayNickname, field: .nickname)
                }

                Section(L.aboutMeSection) {
                    editableProfileRow(
                        title: L.aboutMe,
                        value: store.userProfile.isEmpty
                            ? L.aboutMeEmpty(store.resolvedCatName)
                            : String(store.userProfile.prefix(40)) + (store.userProfile.count > 40 ? "…" : ""),
                        field: .aboutMe
                    )
                }

                Section(L.catPersonaSection) {
                    editableProfileRow(
                        title: L.catNameLabel,
                        value: store.resolvedCatName,
                        field: .catName
                    )

                    NavigationLink {
                        CatStylePickerView()
                            .environmentObject(store)
                    } label: {
                        HStack {
                            Text(L.catStyleLabel)
                            Spacer()
                            Text(store.catStyle.isEmpty ? L.styleDirect : displayStyle(store.catStyle))
                                .foregroundStyle(.secondary)
                        }
                    }

                    catOptionRow(
                        title: L.catRoleLabel,
                        value: store.catRole.isEmpty ? L.roleQuiet : displayRole(store.catRole),
                        options: catRoleOptions,
                        selection: Binding(get: { store.catRole }, set: { store.catRole = $0 })
                    )

                    catOptionRow(
                        title: L.catProactivityLabel,
                        value: store.catProactivity.isEmpty ? L.proactivityOccasional : displayProactivity(store.catProactivity),
                        options: catProactivityOptions,
                        selection: Binding(get: { store.catProactivity }, set: { store.catProactivity = $0 })
                    )

                    catOptionRow(
                        title: L.catMemoryPreferenceLabel,
                        value: store.catMemoryPreference.isEmpty ? L.memoryPreferenceBalanced : displayMemoryPreference(store.catMemoryPreference),
                        options: catMemoryPreferenceOptions,
                        selection: Binding(get: { store.catMemoryPreference }, set: { store.catMemoryPreference = $0 })
                    )

                    editableProfileRow(
                        title: L.catInstructionsLabel,
                        value: store.catInstructions.isEmpty
                            ? L.catInstructionsEmpty
                            : String(store.catInstructions.prefix(40)) + (store.catInstructions.count > 40 ? "…" : ""),
                        field: .catInstructions
                    )
                }

                Section(L.languageSection) {
                    Picker(L.languageSection, selection: $appLanguage) {
                        Text("中文").tag("zh")
                        Text("English").tag("en")
                    }
                    .pickerStyle(.segmented)
                }

                Section(L.dataSection) {
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
                                Text(L.exportCSV)
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
                                Text(L.aiDebug)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(CreamTheme.text)
                                Text(L.aiDebugSubtitle)
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
                                Text(L.agentMemory)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(CreamTheme.text)
                                Text("\(store.agentMemories.count) \(L.memoryCount)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

#if DEBUG
                Section(L.testPersonaTitle) {
                    NavigationLink {
                        TestPersonaSwitcherView()
                            .environmentObject(store)
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(Color.orange.opacity(0.12))
                                Image(systemName: "person.3.sequence")
                                    .font(.system(size: 17, weight: .semibold))
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(.orange)
                            }
                            .frame(width: 36, height: 36)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(L.testPersonaTitle)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(CreamTheme.text)
                                Text(store.isTestPersona ? L.testPersonaCurrent(store.currentAuthUserId) : L.testPersonaSettingsSubtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
#endif

                Section {
                    Button(L.clearAllData, role: .destructive) {
                        showDeleteConfirm = true
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .navigationTitle(L.settingsTitle)
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog(L.clearAllConfirm, isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button(L.confirmClear, role: .destructive) {
                    wipeAllData()
                }
                Button(L.cancel, role: .cancel) {}
            }
            .alert(L.syncCompleted, isPresented: Binding(
                get: { store.healthSyncCompletionMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        store.healthSyncCompletionMessage = nil
                    }
                }
            )) {
                Button(L.gotIt) {
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
            .onAppear {
                store.refreshLocalizedSettingsStatusText()
            }
            .onChange(of: appLanguage) { _ in
                store.refreshLocalizedSettingsStatusText()
            }
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
                        Text(L.iCloudSync)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(CreamTheme.text)
                        Text(store.iCloudSyncStatusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .tint(CreamTheme.green)
#if DEBUG
            .disabled(store.isTestPersona)
#endif
        } header: {
            Text(L.syncSection)
        } footer: {
#if DEBUG
            if store.isTestPersona {
                Text(L.testPersonaICloudDisabled)
            }
#endif
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
                    title: L.syncSleep,
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
                    title: L.syncWorkout
                )
            }
            .tint(CreamTheme.green)

            Toggle(isOn: Binding(
                get: { store.isWakeDreamReminderEnabled },
                set: { store.setWakeDreamReminderEnabled($0) }
            )) {
                healthKitRow(
                    icon: "cloud.moon",
                    title: L.wakeDreamReminder
                )
            }
            .tint(CreamTheme.green)
            .disabled(!store.isHealthSleepSyncEnabled)

            Button {
                store.syncHealthKitNow(showCompletionAlert: true)
            } label: {
                HStack {
                    Text(store.isHealthSyncing ? L.syncing : L.syncNow)
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
            Text(L.healthSection)
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
                    L.reminderTime,
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
            Text(L.reminderSection)
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
                Text(L.dailyReminder)
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
        return L.defaultNickname(suffix)
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
                if field.isMultiline {
                    TextEditor(text: $draftValue)
                        .frame(minHeight: field == .catInstructions ? 220 : 120)
                } else {
                    TextField(field.title, text: $draftValue)
                }
            }
            .navigationTitle(editTitle(for: field))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.cancel) { editingField = nil }
                }
                if field == .catInstructions && draftValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button(L.useInstructionTemplate) {
                            draftValue = L.catInstructionsTemplate
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.save) {
                        saveDraftValue(for: field)
                        editingField = nil
                    }
                    .disabled(field == .nickname && draftValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func rawValue(for field: ProfileField) -> String {
        switch field {
        case .nickname: return displayNickname
        case .aboutMe: return store.userProfile
        case .catName: return store.catName
        case .catInstructions: return store.catInstructions
        }
    }

    private func saveDraftValue(for field: ProfileField) {
        let clean = draftValue.trimmingCharacters(in: .whitespacesAndNewlines)
        switch field {
        case .nickname:
            user = clean.isEmpty ? user : clean
        case .aboutMe:
            store.userProfile = clean
        case .catName:
            store.catName = clean
        case .catInstructions:
            store.catInstructions = clean
        }
    }

    private func editTitle(for field: ProfileField) -> String {
        switch field {
        case .aboutMe: return L.editAboutMe
        case .catName: return L.editCatName
        case .catInstructions: return L.editCatInstructions
        case .nickname: return L.editNickname
        }
    }

    private func displayStyle(_ key: String) -> String {
        switch key {
        case "温柔体贴": return L.styleWarm
        case "简洁直接": return L.styleDirect
        case "幽默毒舌": return L.styleWitty
        case "知性冷静": return L.styleCalm
        default: return key
        }
    }

    private var catRoleOptions: [(label: String, key: String, desc: String)] {
        [
            (L.roleQuiet, "安静陪伴", L.isEn ? "Listen first, fewer suggestions" : "少建议，多接住"),
            (L.roleAction, "行动搭子", L.isEn ? "Break things into tiny next steps" : "帮你拆一个很小的下一步"),
            (L.roleAdvisor, "冷静参谋", L.isEn ? "Structured, calm tradeoffs" : "结构化分析，帮你看清取舍"),
            (L.roleWittyFriend, "轻松吐槽朋友", L.isEn ? "Light humor without pressure" : "轻松一点，但不制造压力"),
        ]
    }

    private var catProactivityOptions: [(label: String, key: String, desc: String)] {
        [
            (L.proactivityReplyOnly, "只回应", L.isEn ? "Only respond to what you say now" : "只回应当下，不主动提过去"),
            (L.proactivityOccasional, "偶尔接回", L.isEn ? "Occasionally recall useful context" : "偶尔自然接回重要背景"),
            (L.proactivityActive, "主动关心", L.isEn ? "Gentle check-ins for important plans" : "轻轻关心近期计划和状态"),
        ]
    }

    private var catMemoryPreferenceOptions: [(label: String, key: String, desc: String)] {
        [
            (L.memoryPreferenceBalanced, "平衡记忆", L.isEn ? "Remember only useful context" : "只记有帮助的背景"),
            (L.memoryPreferencePrivate, "少记私人细节", L.isEn ? "Be conservative with sensitive details" : "对私人信息更保守"),
            (L.memoryPreferencePlans, "多记计划", L.isEn ? "Pay more attention to short-term plans" : "更关注近期计划"),
            (L.memoryPreferencePreferences, "多记偏好", L.isEn ? "Prioritize interaction preferences" : "优先记住互动偏好"),
        ]
    }

    private func catOptionRow(title: String, value: String, options: [(label: String, key: String, desc: String)], selection: Binding<String>) -> some View {
        NavigationLink {
            CatOptionPickerView(title: title, options: options, selection: selection)
        } label: {
            HStack {
                Text(title)
                Spacer()
                Text(value)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func displayRole(_ key: String) -> String {
        switch key {
        case "安静陪伴": return L.roleQuiet
        case "行动搭子": return L.roleAction
        case "冷静参谋": return L.roleAdvisor
        case "轻松吐槽朋友": return L.roleWittyFriend
        default: return key
        }
    }

    private func displayProactivity(_ key: String) -> String {
        switch key {
        case "只回应": return L.proactivityReplyOnly
        case "偶尔接回": return L.proactivityOccasional
        case "主动关心": return L.proactivityActive
        default: return key
        }
    }

    private func displayMemoryPreference(_ key: String) -> String {
        switch key {
        case "平衡记忆": return L.memoryPreferenceBalanced
        case "少记私人细节": return L.memoryPreferencePrivate
        case "多记计划": return L.memoryPreferencePlans
        case "多记偏好": return L.memoryPreferencePreferences
        default: return key
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
    case aboutMe
    case catName
    case catInstructions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nickname: return L.nickname
        case .aboutMe: return L.aboutMe
        case .catName: return L.catNameLabel
        case .catInstructions: return L.catInstructionsLabel
        }
    }

    var isMultiline: Bool {
        self == .aboutMe || self == .catInstructions
    }
}

private struct CatStylePickerView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    private let styles: [(label: String, key: String, desc: String)] = [
        (L.styleWarm, "温柔体贴", L.isEn ? "Patient, empathetic, soft tone" : "温柔耐心、关心感受、语气柔软"),
        (L.styleDirect, "简洁直接", L.isEn ? "Concise, opinionated, no fluff" : "结论前置、有判断、少废话"),
        (L.styleWitty, "幽默毒舌", L.isEn ? "Sharp, witty, a bit sarcastic" : "犀利调侃、话少但靠谱"),
        (L.styleCalm, "知性冷静", L.isEn ? "Analytical, calm, structured" : "理性分析、条理清晰、不带情绪"),
    ]

    var body: some View {
        List {
            ForEach(styles, id: \.key) { style in
                Button {
                    store.catStyle = style.key
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(style.label)
                                .font(.body.weight(.medium))
                                .foregroundStyle(CreamTheme.text)
                            Text(style.desc)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if (store.catStyle.isEmpty ? "简洁直接" : store.catStyle) == style.key {
                            Image(systemName: "checkmark")
                                .foregroundStyle(CreamTheme.green)
                        }
                    }
                }
            }
        }
        .navigationTitle(L.catStyleLabel)
        .navigationBarTitleDisplayMode(.inline)
        .listStyle(.insetGrouped)
        .tint(CreamTheme.green)
        .scrollContentBackground(.hidden)
        .background(CreamTheme.glassStrong)
    }
}

private struct CatOptionPickerView: View {
    let title: String
    let options: [(label: String, key: String, desc: String)]
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            ForEach(options, id: \.key) { option in
                Button {
                    selection = option.key
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(option.label)
                                .font(.body.weight(.medium))
                                .foregroundStyle(CreamTheme.text)
                            Text(option.desc)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if (selection.isEmpty ? (options.first?.key ?? "") : selection) == option.key {
                            Image(systemName: "checkmark")
                                .foregroundStyle(CreamTheme.green)
                        }
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .listStyle(.insetGrouped)
        .tint(CreamTheme.green)
        .scrollContentBackground(.hidden)
        .background(CreamTheme.glassStrong)
    }
}

private struct AgentMemoryListView: View {
    @EnvironmentObject var store: AppStore
    @State private var newMemoryText = ""
    @State private var newMemoryScope = "state"
    @State private var editingMemory: AgentMemory?

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    TextField(L.addMemoryPlaceholder, text: $newMemoryText)
                        .textFieldStyle(.plain)
                    Picker("", selection: $newMemoryScope) {
                        Text(L.memoryScopeProfile).tag("profile")
                        Text(L.memoryScopePreference).tag("preference")
                        Text(L.memoryScopeState).tag("state")
                        Text(L.memoryScopePlan).tag("plan")
                    }
                    .pickerStyle(.segmented)
                    Button {
                        store.addAgentMemory(content: newMemoryText, scope: newMemoryScope)
                        newMemoryText = ""
                    } label: {
                        Label(L.save, systemImage: "plus.circle.fill")
                    }
                    .disabled(newMemoryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            if store.agentMemories.isEmpty {
                Section {
                    Text(L.noMemories)
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(["profile", "preference", "state", "plan"], id: \.self) { scope in
                    let items = store.agentMemories.filter { $0.scope == scope }
                    if !items.isEmpty {
                        Section(memoryScopeLabel(scope)) {
                            ForEach(items) { memory in
                                memoryRow(memory)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(L.agentMemoryTitle)
        .sheet(item: $editingMemory) { memory in
            AgentMemoryEditView(memory: memory)
                .environmentObject(store)
        }
    }

    private func memoryRow(_ memory: AgentMemory) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(memory.content)
                .font(.subheadline)
            HStack(spacing: 8) {
                Text(memoryScopeLabel(memory.scope))
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.purple.opacity(0.1)))
                    .foregroundStyle(.purple)
                Text(memory.source == "auto" ? L.autoExtracted : L.manuallyAdded)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if memory.status != "active" {
                    Text(memory.status == "rejected" ? L.memoryStatusRejected : L.memoryStatusArchived)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(memory.createdAt, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                store.removeAgentMemory(id: memory.id)
            } label: {
                Label(L.delete, systemImage: "trash")
            }
            Button {
                store.expireAgentMemory(id: memory.id)
            } label: {
                Label(L.expireMemory, systemImage: "archivebox")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                editingMemory = memory
            } label: {
                Label(L.editMemory, systemImage: "pencil")
            }
            Button {
                store.confirmAgentMemoryAsLongTerm(id: memory.id)
            } label: {
                Label(L.makeLongTerm, systemImage: "pin")
            }
            .tint(CreamTheme.green)
        }
    }

    private func memoryScopeLabel(_ scope: String) -> String {
        switch scope {
        case "profile": return L.memoryScopeProfile
        case "preference": return L.memoryScopePreference
        case "plan": return L.memoryScopePlan
        default: return L.memoryScopeState
        }
    }
}

private struct AgentMemoryEditView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let memory: AgentMemory
    @State private var content: String
    @State private var scope: String
    @State private var status: String

    init(memory: AgentMemory) {
        self.memory = memory
        _content = State(initialValue: memory.content)
        _scope = State(initialValue: memory.scope)
        _status = State(initialValue: memory.status)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $content)
                        .frame(minHeight: 100)
                }
                Section {
                    Picker(L.agentMemoryTitle, selection: $scope) {
                        Text(L.memoryScopeProfile).tag("profile")
                        Text(L.memoryScopePreference).tag("preference")
                        Text(L.memoryScopeState).tag("state")
                        Text(L.memoryScopePlan).tag("plan")
                    }
                    Picker(L.memoryStatusLabel, selection: $status) {
                        Text(L.memoryStatusActive).tag("active")
                        Text(L.memoryStatusArchived).tag("archived")
                        Text(L.memoryStatusRejected).tag("rejected")
                    }
                }
            }
            .navigationTitle(L.editMemory)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.save) {
                        store.updateAgentMemory(id: memory.id, content: content, scope: scope, status: status)
                        dismiss()
                    }
                    .disabled(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
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
                    Text(L.noDebugLogs)
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
                Text(L.recentLogs)
            } footer: {
                Text(L.debugFooter)
            }
        }
        .navigationTitle(L.agentDebugTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if let exportFileURL, !store.agentDebugLogs.isEmpty {
                    ShareLink(item: exportFileURL) {
                        Text(L.export)
                    }
                } else {
                    Button(L.export) {}
                        .disabled(true)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(L.clearLabel) { showClearConfirm = true }
                    .disabled(store.agentDebugLogs.isEmpty)
            }
        }
        .confirmationDialog(L.clearDebugConfirm, isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button(L.clearLabel, role: .destructive) {
                store.clearAgentDebugLogs()
                refreshExportFile()
            }
            Button(L.cancel, role: .cancel) {}
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
                    Text(L.failed)
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
            detailSection(L.debugInput, rows: [log.input])
            detailSection(L.debugRequestContext, rows: [
                "currentDate=\(log.currentDate)",
                "currentTime=\(log.currentTime)"
            ])
            detailSection(L.debugPersona, rows: [log.personaSummary.isEmpty ? L.noneValue : log.personaSummary])
            detailSection(L.debugUserInfo, rows: [log.userSummary.isEmpty ? L.noneValue : log.userSummary])
            detailSection(L.debugChatHistory, rows: emptyFallback(log.messagesSummary))
            detailSection(L.debugLifeOSContext, rows: [log.contextSummary.isEmpty ? L.noneValue : log.contextSummary])
            detailSection(L.debugReply, rows: [log.reply])
            detailSection(L.debugFollowUp, rows: [log.followUpQuestion.isEmpty ? L.noneValue : log.followUpQuestion])
            detailSection(L.debugAISuggestions, rows: emptyFallback(log.actionSuggestionsSummary))
            detailSection(L.debugMergedQueue, rows: emptyFallback(log.mergedActionSummary))
            if !log.errorMessage.isEmpty {
                detailSection(L.debugError, rows: [log.errorMessage])
            }
            detailSection("Raw JSON", rows: [log.rawResponse.isEmpty ? L.noneValue : log.rawResponse])
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
        rows.isEmpty ? [L.noneValue] : rows
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
        \(log.personaSummary.isEmpty ? L.noneValue : log.personaSummary)

        \(childH) User Summary
        \(log.userSummary.isEmpty ? L.noneValue : log.userSummary)

        \(childH) Messages Sent
        \(joined(log.messagesSummary))

        \(childH) Context Summary
        \(log.contextSummary.isEmpty ? L.noneValue : log.contextSummary)

        \(childH) Reply
        \(log.reply)

        \(childH) Follow-up Question
        \(log.followUpQuestion.isEmpty ? L.noneValue : log.followUpQuestion)

        \(childH) AI Action Suggestions
        \(joined(log.actionSuggestionsSummary))

        \(childH) Merged Into Pending Cards
        \(joined(log.mergedActionSummary))

        \(childH) Error
        \(log.errorMessage.isEmpty ? L.noneValue : log.errorMessage)

        \(childH) Raw JSON
        ```json
        \(log.rawResponse.isEmpty ? L.noneValue : log.rawResponse)
        ```
        """
    }

    private static func joined(_ rows: [String]) -> String {
        rows.isEmpty ? L.noneValue : rows.map { "- \($0)" }.joined(separator: "\n")
    }
}
