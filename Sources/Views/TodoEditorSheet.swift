import SwiftUI

// MARK: - Todo Editor Sheet (Apple Calendar 风格)

enum TodoEditorMode {
    case create(defaultDate: Date)
    case edit(task: TaskEntry)
}

struct TodoEditorSheet: View {
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
