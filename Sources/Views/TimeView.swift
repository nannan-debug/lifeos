import SwiftUI

struct TimeView: View {
    @EnvironmentObject var store: AppStore
    @AppStorage("fields.time") private var timeFields = "事件名称,开始时间,结束时间,分类"
    @State private var showAdd = false
    @State private var editTarget: TimeEntry?
    @State private var showCalendarOverlay = false
    @State private var displayMonth = Date()

    private let calendar = Calendar.current
    private let weekSymbols = ["日", "一", "二", "三", "四", "五", "六"]

    @State private var name = ""
    @State private var start = ""
    @State private var end = ""
    @State private var startAt = Date()
    @State private var endAt = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
    @State private var category = "工作"
    @State private var extraValues: [String: String] = [:]
    @State private var errorMessage = ""
    @State private var showError = false

    // 圆盘交互（D1: 15分钟粒度，不支持跨天）
    @State private var dialStartMinutes = 9 * 60
    @State private var dialEndMinutes = 10 * 60
    @State private var dialCategory = "工作"
    @State private var dialName = ""
    @State private var dialNote = ""
    @State private var showOverlapConfirm = false
    @State private var selectedEntryID: UUID?

    private var dialSegments: [DialSegment] {
        store.timeEntries.compactMap { entry in
            guard let s = parseMinutes(entry.start), let e = parseMinutes(entry.end), e > s else { return nil }
            return DialSegment(
                id: entry.id,
                startMinutes: s,
                endMinutes: e,
                color: colorForCategory(entry.category),
                name: entry.name,
                category: entry.category,
                start: entry.start,
                end: entry.end
            )
        }
    }

    private var selectedEntry: TimeEntry? {
        guard let id = selectedEntryID else { return nil }
        return store.timeEntries.first(where: { $0.id == id })
    }

    var body: some View {
        NavigationStack {
            List {
                Section("24小时圆盘（拖拽选时间段）") {
                    VStack(spacing: 16) {
                        RadialRangePicker(
                            startMinutes: $dialStartMinutes,
                            endMinutes: $dialEndMinutes,
                            existingSegments: dialSegments,
                            centerTitle: "\(timeText(from: dialStartMinutes)) - \(timeText(from: dialEndMinutes))",
                            centerSubtitle: dialName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? dialCategory : dialName,
                            accent: colorForCategory(dialCategory),
                            onSelectSegment: { seg in
                                selectedEntryID = seg.id
                                dialStartMinutes = seg.startMinutes
                                dialEndMinutes = seg.endMinutes
                                dialCategory = normalizedCategory(seg.category)
                                dialName = seg.name
                                if let matched = store.timeEntries.first(where: { $0.id == seg.id }) {
                                    dialNote = matched.extra[remarkFieldName] ?? ""
                                } else {
                                    dialNote = ""
                                }
                            }
                        )
                        .frame(height: 338)
                        .padding(.horizontal, 4)

                        HStack {
                            Label(timeText(from: dialStartMinutes), systemImage: "play.fill")
                            Spacer()
                            Label(timeText(from: dialEndMinutes), systemImage: "stop.fill")
                            Spacer()
                            Text(durationText(start: dialStartMinutes, end: dialEndMinutes))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(colorForCategory(dialCategory))
                        }
                        .font(.subheadline)
                        .padding(.horizontal, 8)

                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 8) {
                                if selectedEntry != nil {
                                    Label("编辑事件", systemImage: "pencil.circle.fill")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(colorForCategory(dialCategory))
                                } else {
                                    Label("新建事件", systemImage: "plus.circle")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(colorForCategory(dialCategory))
                                }
                                Spacer()
                                Text("\(timeText(from: dialStartMinutes)) - \(timeText(from: dialEndMinutes))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            HStack(spacing: 10) {
                                Label("类型", systemImage: "square.grid.2x2")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)

                                Spacer(minLength: 10)

                                Menu {
                                    ForEach(categoryOptions, id: \.self) { op in
                                        Button {
                                            dialCategory = op
                                        } label: {
                                            Label(op, systemImage: iconForCategory(op))
                                        }
                                        .tint(colorForCategory(op))
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: iconForCategory(dialCategory))
                                            .symbolRenderingMode(.hierarchical)
                                        Text(dialCategory)
                                            .font(.subheadline.weight(.semibold))
                                        Image(systemName: "chevron.up.chevron.down")
                                            .font(.caption2)
                                            .opacity(0.5)
                                    }
                                    .foregroundStyle(colorForCategory(dialCategory))
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                            .background(Color.white.opacity(0.88))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.black.opacity(0.05), lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 12))

                            TextField("一句话描述", text: $dialName)
                                .font(.body)
                                .textInputAutocapitalization(.never)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 11)
                                .background(Color.white.opacity(0.88))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.black.opacity(0.05), lineWidth: 1)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 12))

                            TextField("补充详情", text: $dialNote, axis: .vertical)
                                .font(.body)
                                .lineLimit(2...4)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 11)
                                .background(Color.white.opacity(0.88))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.black.opacity(0.05), lineWidth: 1)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .padding(12)
                        .background(bgColorForCategory(dialCategory).opacity(selectedEntry == nil ? 0.8 : 1.0))
                        .clipShape(RoundedRectangle(cornerRadius: 14))

                        if selectedEntry != nil {
                            // ── 编辑模式：已选中一条现有事件 ──
                            HStack(spacing: 8) {
                                Button {
                                    updateSelectedEntry()
                                } label: {
                                    HStack {
                                        Image(systemName: "checkmark.circle.fill")
                                        Text("更新事件")
                                            .fontWeight(.semibold)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(colorForCategory(dialCategory))

                                Button {
                                    createNewFromEditMode()
                                } label: {
                                    HStack {
                                        Image(systemName: "plus")
                                        Text("新建")
                                            .fontWeight(.semibold)
                                    }
                                    .padding(.vertical, 12)
                                    .padding(.horizontal, 16)
                                }
                                .buttonStyle(.bordered)
                                .tint(colorForCategory(dialCategory))
                            }
                        } else {
                            // ── 新建模式 ──
                            Button {
                                saveFromDial()
                            } label: {
                                HStack {
                                    Image(systemName: "plus.circle.fill")
                                    Text("保存这段时间")
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(colorForCategory(dialCategory))
                        }
                    }
                    .onAppear {
                        if dialCategory.isEmpty { dialCategory = categoryOptions.first ?? "工作" }
                        if !categoryOptions.contains(dialCategory) { dialCategory = categoryOptions.first ?? "工作" }
                        if category.isEmpty || !categoryOptions.contains(category) { category = categoryOptions.first ?? "工作" }
                    }
                }

                Section("时间记录") {
                    ForEach(store.timeEntries) { e in
                        Button {
                            // 点击记录 → 在圆盘上定位并进入编辑模式
                            selectedEntryID = e.id
                            dialStartMinutes = parseMinutes(e.start) ?? 0
                            dialEndMinutes = parseMinutes(e.end) ?? 60
                            dialCategory = normalizedCategory(e.category)
                            dialName = e.name
                            dialNote = e.extra[remarkFieldName] ?? ""
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(e.name).font(.headline).foregroundStyle(colorForCategory(e.category))
                                HStack(spacing: 6) {
                                    Image(systemName: iconForCategory(e.category))
                                        .symbolRenderingMode(.hierarchical)
                                        .foregroundStyle(colorForCategory(e.category))
                                    Text("\(e.start) - \(e.end)")
                                        .foregroundStyle(.secondary)
                                    Text("·")
                                        .foregroundStyle(.secondary)
                                    Text(e.category)
                                        .font(.caption.weight(.semibold))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(bgColorForCategory(e.category))
                                        .foregroundStyle(colorForCategory(e.category))
                                        .clipShape(Capsule())
                                }
                                .font(.subheadline)

                                if let note = e.extra[remarkFieldName], !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    HStack(alignment: .top, spacing: 6) {
                                        Image(systemName: "text.alignleft")
                                            .font(.caption)
                                            .foregroundStyle(colorForCategory(e.category))
                                        Text(note)
                                            .font(.caption)
                                            .foregroundStyle(colorForCategory(e.category).opacity(0.85))
                                            .lineLimit(2)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                    .background(bgColorForCategory(e.category))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete(perform: store.removeTimeEntry)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .listStyle(.insetGrouped)
            .tint(CreamTheme.green)
            .scrollContentBackground(.hidden)
            .background(CreamTheme.glassStrong)
            .safeAreaInset(edge: .top) {
                timeTopDateBar
            }
            .overlay(alignment: .top) {
                timeCalendarOverlay
                    .compositingGroup()
                    .opacity(showCalendarOverlay ? 1 : 0)
                    .offset(y: showCalendarOverlay ? 0 : -16)
                    .allowsHitTesting(showCalendarOverlay)
                    .animation(.easeOut(duration: 0.22), value: showCalendarOverlay)
                    .zIndex(20)
            }
            .sheet(isPresented: $showAdd) {
                NavigationStack {
                    Form {
                        TextField(fieldName(0, "一句话描述"), text: $name)
                        DatePicker(fieldName(1, "开始时间"), selection: $startAt, displayedComponents: .hourAndMinute)
                            .datePickerStyle(.compact)
                        DatePicker(fieldName(2, "结束时间"), selection: $endAt, displayedComponents: .hourAndMinute)
                            .datePickerStyle(.compact)
                        Picker(fieldName(3, "类型"), selection: $category) {
                            ForEach(categoryOptions, id: \.self) { op in
                                HStack(spacing: 8) {
                                    Image(systemName: iconForCategory(op))
                                        .foregroundStyle(colorForCategory(op))
                                        .frame(width: 16)
                                    Text(op)
                                        .foregroundStyle(colorForCategory(op))
                                }
                                .tag(op)
                            }
                        }
                        .tint(colorForCategory(category))
                        ForEach(Array(extraFieldNames.enumerated()), id: \.element) { idx, field in
                            extraInputView(field: field, extraIndex: idx)
                        }
                    }
                    .navigationTitle(editTarget == nil ? "新增时间块" : "编辑时间块")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("取消") {
                                showAdd = false
                                editTarget = nil
                            }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("保存") {
                                if category.isEmpty || !categoryOptions.contains(category) {
                                    category = normalizedCategory(category)
                                }
                                start = formatTime(startAt)
                                end = formatTime(endAt)
                                let err: String?
                                if let target = editTarget {
                                    err = store.updateTimeEntry(id: target.id, name: name, start: start, end: end, category: category, extra: extraValues)
                                } else {
                                    err = store.addTimeEntry(name: name, start: start, end: end, category: category, extra: extraValues)
                                }
                                if let err {
                                    errorMessage = err
                                    showError = true
                                } else {
                                    showAdd = false
                                    editTarget = nil
                                }
                            }
                            .disabled(name.isEmpty)
                        }
                    }
                }
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
            .onChange(of: timeFields) { _ in
                store.reloadFieldConfig()
                if dialCategory.isEmpty || !categoryOptions.contains(dialCategory) { dialCategory = categoryOptions.first ?? "工作" }
                if category.isEmpty || !categoryOptions.contains(category) { category = categoryOptions.first ?? "工作" }
            }
            // Animation driven by withAnimation() in calendar toggle button
            .alert("保存失败", isPresented: $showError) {
                Button("知道了", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            .alert("时间重叠", isPresented: $showOverlapConfirm) {
                Button("取消", role: .cancel) {}
                Button("继续新建") {
                    confirmCreateOverlap()
                }
            } message: {
                Text("这段时间已有其他事件，是否还要新建？")
            }
        }
        .creamBackground()
    }

    private var timeTopDateBar: some View {
        HStack(spacing: 12) {
            Text("时间记录")
                .font(.headline.weight(.semibold))

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

    private var timeCalendarOverlay: some View {
        CreamCalendarOverlay(
            selectedDate: $store.selectedDate,
            displayMonth: $displayMonth,
            isPresented: $showCalendarOverlay,
            markerForDate: { day in
                let cats = store.timeCategories(on: day)
                if cats.isEmpty { return .none }
                let colors = cats.map(colorForCategory)
                return .ring(colors)
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

    private func updateSelectedEntry() {
        guard let entry = selectedEntry else { return }
        if dialCategory.isEmpty { dialCategory = categoryOptions.first ?? "工作" }
        if dialEndMinutes <= dialStartMinutes {
            errorMessage = "结束时间必须晚于开始时间"
            showError = true
            return
        }

        let startText = timeText(from: dialStartMinutes)
        let endText = timeText(from: dialEndMinutes)
        let normalizedName = dialName.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = normalizedName.isEmpty ? "\(dialCategory)时间块" : normalizedName

        var extra = entry.extra
        let note = dialNote.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty {
            extra[remarkFieldName] = note
        } else {
            extra.removeValue(forKey: remarkFieldName)
        }

        if let err = store.updateTimeEntry(id: entry.id, name: finalName, start: startText, end: endText, category: dialCategory, extra: extra) {
            errorMessage = err
            showError = true
            return
        }

        // 更新成功，保持选中状态
    }

    private func saveFromDial() {
        if dialCategory.isEmpty { dialCategory = categoryOptions.first ?? "工作" }
        if !categoryOptions.contains(dialCategory) { dialCategory = normalizedCategory(dialCategory) }
        if dialEndMinutes <= dialStartMinutes {
            errorMessage = "结束时间必须晚于开始时间"
            showError = true
            return
        }

        let startText = timeText(from: dialStartMinutes)
        let endText = timeText(from: dialEndMinutes)
        let normalizedName = dialName.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = normalizedName.isEmpty ? "\(dialCategory)时间块" : normalizedName

        var extra: [String: String] = [:]
        let note = dialNote.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty {
            extra[remarkFieldName] = note
        }

        if let err = store.addTimeEntry(name: finalName, start: startText, end: endText, category: dialCategory, extra: extra) {
            errorMessage = err
            showError = true
            return
        }

        // 保存成功后保留分类，清空描述
        dialName = ""
        dialNote = ""
        selectedEntryID = nil
    }

    private func createNewFromEditMode() {
        // 检查时间是否与已有事件重叠（排除当前选中的事件）
        let hasOverlap = dialSegments.contains { seg in
            if seg.id == selectedEntryID { return false }
            return dialStartMinutes < seg.endMinutes && dialEndMinutes > seg.startMinutes
        }

        if hasOverlap {
            showOverlapConfirm = true
        } else {
            // 没有重叠，直接清除选中并创建
            selectedEntryID = nil
            saveFromDial()
        }
    }

    private func confirmCreateOverlap() {
        // 用户确认叠加创建
        selectedEntryID = nil
        saveFromDial()
    }

    private func jumpToFreeSlotOnDial() {
        selectedEntryID = nil
        dialName = ""
        dialNote = ""
        if dialCategory.isEmpty { dialCategory = categoryOptions.first ?? "工作" }

        let sorted = dialSegments.sorted { $0.startMinutes < $1.startMinutes }
        let step = 15
        let minDuration = 30
        let preferredDuration = 60
        let dayEnd = 23 * 60 + 45

        var cursor = 8 * 60
        for seg in sorted {
            if seg.endMinutes <= cursor { continue }

            let gap = seg.startMinutes - cursor
            if gap >= minDuration {
                dialStartMinutes = cursor
                var candidateEnd = min(cursor + preferredDuration, seg.startMinutes)
                if candidateEnd - dialStartMinutes < minDuration {
                    candidateEnd = dialStartMinutes + minDuration
                }
                dialEndMinutes = min(dayEnd, max(dialStartMinutes + step, candidateEnd))
                return
            }
            cursor = max(cursor, seg.endMinutes)
        }

        if dayEnd - cursor >= minDuration {
            dialStartMinutes = cursor
            dialEndMinutes = min(dayEnd, cursor + preferredDuration)
            return
        }

        dialEndMinutes = dayEnd
        dialStartMinutes = max(0, dayEnd - minDuration)
    }

    private func durationText(start: Int, end: Int) -> String {
        let mins = max(0, end - start)
        return "\(mins / 60)h\(mins % 60)m"
    }

    private func timeText(from minutes: Int) -> String {
        let h = max(0, min(23, minutes / 60))
        let m = max(0, min(59, minutes % 60))
        return String(format: "%02d:%02d", h, m)
    }

    private func parseMinutes(_ text: String) -> Int? {
        let parts = text.split(separator: ":")
        guard parts.count == 2,
              let h = Int(parts[0]),
              let m = Int(parts[1]),
              (0...23).contains(h),
              (0...59).contains(m) else { return nil }
        return h * 60 + m
    }

    private func fieldName(_ index: Int, _ fallback: String) -> String {
        let arr = store.timeFieldNames
        return index < arr.count ? arr[index] : fallback
    }

    private var extraFieldNames: [String] {
        let arr = store.timeFieldNames
        return arr.count > 4 ? Array(arr.dropFirst(4)) : []
    }

    private var remarkFieldName: String {
        fieldName(4, "备注")
    }

    private var categoryOptions: [String] {
        let key = fieldName(3, "分类")
        let configured = store.timeFieldOptions[key] ?? []
        if !configured.isEmpty { return configured }
        return ["睡觉", "社交", "运动", "其他", "娱乐", "工作", "学习"]
    }

    private func normalizedCategory(_ raw: String) -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value == "产品" { return "工作" }
        if categoryOptions.contains(value) { return value }
        return categoryOptions.first ?? "工作"
    }

    @ViewBuilder
    private func extraInputView(field: String, extraIndex: Int) -> some View {
        let t = fieldTypeForExtraField(at: extraIndex)
        let options = store.timeFieldOptions[field] ?? []
        if t == "select" && !options.isEmpty {
            Picker(field, selection: Binding(
                get: { extraValues[field] ?? options.first ?? "" },
                set: { extraValues[field] = $0 }
            )) {
                ForEach(options, id: \.self) { op in Text(op).tag(op) }
            }
        } else if field == remarkFieldName {
            TextField(field, text: Binding(
                get: { extraValues[field] ?? "" },
                set: { extraValues[field] = $0 }
            ), axis: .vertical)
            .lineLimit(2...4)
        } else {
            TextField(field, text: Binding(
                get: { extraValues[field] ?? "" },
                set: { extraValues[field] = $0 }
            ))
            .keyboardType(keyboardTypeForType(t))
        }
    }

    private func fieldTypeForExtraField(at extraIndex: Int) -> String {
        let types = store.timeFieldTypes
        let fullIndex = extraIndex + 4
        return fullIndex < types.count ? types[fullIndex].lowercased() : "text"
    }

    private func keyboardTypeForType(_ t: String) -> UIKeyboardType {
        t == "number" ? .decimalPad : .default
    }

    private func iconForCategory(_ c: String) -> String {
        switch c {
        case "睡觉": return "bed.double"
        case "社交": return "person.2"
        case "运动": return "figure.run"
        case "娱乐": return "gamecontroller"
        case "工作": return "briefcase"
        case "学习": return "book"
        case "其他": return "sparkles"
        default: return "square.grid.2x2"
        }
    }

    private func colorForCategory(_ c: String) -> Color {
        // Notion Inked 配色 — 主色（用于文字、图标、标签）
        switch c {
        case "睡觉": return Color(red: 0.608, green: 0.494, blue: 0.647) // #9B7EA5 紫灰
        case "工作": return Color(red: 0.357, green: 0.549, blue: 0.710) // #5B8CB5 蓝灰
        case "运动": return Color(red: 0.353, green: 0.620, blue: 0.435) // #5A9E6F 绿色
        case "学习": return Color(red: 0.749, green: 0.635, blue: 0.204) // #BFA234 琥珀黄
        case "社交": return Color(red: 0.408, green: 0.447, blue: 0.671) // #6872AB 靛蓝
        case "娱乐": return Color(red: 0.753, green: 0.529, blue: 0.369) // #C0875E 暖棕
        case "其他": return Color(red: 0.420, green: 0.659, blue: 0.627) // #6BA8A0 青绿
        default: return CreamTheme.green
        }
    }

    private func bgColorForCategory(_ c: String) -> Color {
        // Notion Inked 配色 — 浅底色（用于背景、备注区域）
        switch c {
        case "睡觉": return Color(red: 0.953, green: 0.929, blue: 0.961) // #F3EDF5
        case "工作": return Color(red: 0.922, green: 0.949, blue: 0.973) // #EBF2F8
        case "运动": return Color(red: 0.918, green: 0.961, blue: 0.929) // #EAF5ED
        case "学习": return Color(red: 0.984, green: 0.965, blue: 0.902) // #FBF6E6
        case "社交": return Color(red: 0.929, green: 0.933, blue: 0.961) // #EDEEF5
        case "娱乐": return Color(red: 0.973, green: 0.945, blue: 0.918) // #F8F1EA
        case "其他": return Color(red: 0.918, green: 0.961, blue: 0.953) // #EAF5F3
        default: return CreamTheme.green.opacity(0.08)
        }
    }

    private func formatTime(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }

    private func parseTime(_ text: String) -> Date? {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        guard let t = f.date(from: text) else { return nil }
        let cal = Calendar.current
        let now = Date()
        let c = cal.dateComponents([.hour, .minute], from: t)
        return cal.date(bySettingHour: c.hour ?? 0, minute: c.minute ?? 0, second: 0, of: now)
    }
}

private struct DialSegment: Identifiable {
    let id: UUID
    let startMinutes: Int
    let endMinutes: Int
    let color: Color
    let name: String
    let category: String
    let start: String
    let end: String
}

private struct SectorSliceShape: Shape {
    let startProgress: CGFloat
    let endProgress: CGFloat

    func path(in rect: CGRect) -> Path {
        guard endProgress > startProgress else { return Path() }

        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) * 0.46
        let startAngle = Angle(radians: Double(startProgress * 2 * .pi - .pi / 2))
        let endAngle = Angle(radians: Double(endProgress * 2 * .pi - .pi / 2))

        var path = Path()
        path.move(to: center)
        path.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
        path.closeSubpath()
        return path
    }
}

private struct RadialRangePicker: View {
    @Binding var startMinutes: Int
    @Binding var endMinutes: Int
    let existingSegments: [DialSegment]
    let centerTitle: String
    let centerSubtitle: String
    let accent: Color
    let onSelectSegment: ((DialSegment) -> Void)?

    private let step = 15
    private let maxMinute = 23 * 60 + 45

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let radius = size * 0.46

            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.88))
                    .overlay(
                        Circle()
                            .stroke(CreamTheme.green.opacity(0.14), lineWidth: 1)
                    )

                ForEach(0..<24, id: \.self) { h in
                    let angle = angleForMinute(h * 60)
                    let p1 = point(on: center, radius: radius * 0.83, angle: angle)
                    let p2 = point(on: center, radius: radius, angle: angle)
                    Path { p in
                        p.move(to: p1)
                        p.addLine(to: p2)
                    }
                    .stroke(Color.secondary.opacity(0.22), lineWidth: 1)
                }

                ForEach(existingSegments) { seg in
                    SectorSliceShape(
                        startProgress: CGFloat(seg.startMinutes) / CGFloat(maxMinute + step),
                        endProgress: CGFloat(seg.endMinutes) / CGFloat(maxMinute + step)
                    )
                    .fill(seg.color.opacity(0.38))
                    .contentShape(
                        SectorSliceShape(
                            startProgress: CGFloat(seg.startMinutes) / CGFloat(maxMinute + step),
                            endProgress: CGFloat(seg.endMinutes) / CGFloat(maxMinute + step)
                        )
                    )
                    .onTapGesture {
                        onSelectSegment?(seg)
                    }
                }

                SectorSliceShape(
                    startProgress: CGFloat(startMinutes) / CGFloat(maxMinute + step),
                    endProgress: CGFloat(endMinutes) / CGFloat(maxMinute + step)
                )
                .fill(accent.opacity(0.46))

                Circle()
                    .trim(from: CGFloat(startMinutes) / CGFloat(maxMinute + step), to: CGFloat(endMinutes) / CGFloat(maxMinute + step))
                    .stroke(accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                // 中央留白区：纯白底
                Circle()
                    .fill(Color.white)
                    .frame(width: radius * 0.82, height: radius * 0.82)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.9), lineWidth: 1)
                    )

                VStack(spacing: 4) {
                    Text(centerTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(centerSubtitle.isEmpty ? "时间记录" : centerSubtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                handle(center: center, radius: radius, minute: startMinutes, title: "开始")
                    .gesture(dragGesture(for: .start, center: center))

                handle(center: center, radius: radius, minute: endMinutes, title: "结束")
                    .gesture(dragGesture(for: .end, center: center))

                hourLabel("24/00", at: center, radius: radius + 18, minute: 0)
                hourLabel("06", at: center, radius: radius + 18, minute: 6 * 60)
                hourLabel("12", at: center, radius: radius + 18, minute: 12 * 60)
                hourLabel("18", at: center, radius: radius + 18, minute: 18 * 60)
            }
        }
    }

    private enum DragTarget { case start, end }

    private func dragGesture(for target: DragTarget, center: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let raw = minuteFromLocation(value.location, center: center)
                let snapped = snap(raw)

                switch target {
                case .start:
                    var candidate = max(0, min(snapped, maxMinute - step))
                    if candidate >= endMinutes {
                        endMinutes = min(maxMinute, candidate + step)
                    }
                    candidate = min(candidate, endMinutes - step)
                    startMinutes = max(0, candidate)

                case .end:
                    var candidate = max(step, min(snapped, maxMinute))
                    if candidate <= startMinutes {
                        startMinutes = max(0, candidate - step)
                    }
                    candidate = max(candidate, startMinutes + step)
                    endMinutes = min(maxMinute, candidate)
                }
            }
    }

    @ViewBuilder
    private func handle(center: CGPoint, radius: CGFloat, minute: Int, title: String) -> some View {
        let angle = angleForMinute(minute)
        let p = point(on: center, radius: radius, angle: angle)
        VStack(spacing: 2) {
            Circle()
                .fill(accent)
                .frame(width: 18, height: 18)
                .overlay(Circle().stroke(.white, lineWidth: 2))
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color.clear)
        .contentShape(Rectangle())
        .position(x: p.x, y: p.y)
    }

    @ViewBuilder
    private func hourLabel(_ text: String, at center: CGPoint, radius: CGFloat, minute: Int) -> some View {
        let angle = angleForMinute(minute)
        let p = point(on: center, radius: radius, angle: angle)
        Text(text)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .position(x: p.x, y: p.y)
    }

    private func angleForMinute(_ minute: Int) -> CGFloat {
        let ratio = CGFloat(minute) / CGFloat(maxMinute + step)
        return ratio * 2 * .pi - .pi / 2
    }

    private func point(on center: CGPoint, radius: CGFloat, angle: CGFloat) -> CGPoint {
        CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
    }

    private func minuteFromLocation(_ location: CGPoint, center: CGPoint) -> Int {
        let dx = location.x - center.x
        let dy = location.y - center.y
        var angle = atan2(dy, dx) + .pi / 2
        if angle < 0 { angle += 2 * .pi }
        let ratio = angle / (2 * .pi)
        let minute = Int((ratio * CGFloat(maxMinute + step)).rounded())
        return max(0, min(maxMinute, minute))
    }

    private func snap(_ minute: Int) -> Int {
        let snapped = Int((Double(minute) / Double(step)).rounded()) * step
        return max(0, min(maxMinute, snapped))
    }
}
