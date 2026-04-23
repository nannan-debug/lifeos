import SwiftUI

struct InboxView: View {
    @EnvironmentObject var store: AppStore
    @AppStorage("fields.inbox") private var inboxFields = "标题,正文,类型,状态"
    @State private var title = ""
    @State private var detail = ""
    @State private var extraValues: [String: String] = [:]

    @State private var editTarget: InboxNote?
    @State private var showEdit = false
    @State private var editTitle = ""
    @State private var editDetail = ""
    @State private var kind = "Idea"
    @State private var status = "待整理"

    @State private var editKind = "Idea"
    @State private var editStatus = "待整理"

    var body: some View {
        NavigationStack {
            List {
                Section("快速记录") {
                    TextField(fieldName(0, "标题"), text: $title)
                    TextField(fieldName(1, "正文"), text: $detail, axis: .vertical)
                    Picker(fieldName(2, "类型"), selection: $kind) {
                        ForEach(kindOptions, id: \.self) { op in
                            Label(op, systemImage: iconForKind(op)).tag(op)
                        }
                    }
                    Picker(fieldName(3, "状态"), selection: $status) {
                        ForEach(statusOptions, id: \.self) { op in Text(op).tag(op) }
                    }
                    ForEach(Array(extraFieldNames.enumerated()), id: \.element) { idx, field in
                        extraInputView(field: field, extraIndex: idx)
                    }
                    Button("保存") {
                        store.addInbox(title: title, detail: detail, kind: kind, status: status, extra: extraValues)
                        title = ""; detail = ""; extraValues = [:]
                        kind = kindOptions.first ?? "Idea"
                        status = statusOptions.first ?? "待整理"
                    }
                }
                Section("最近记录") {
                    ForEach(store.inbox) { n in
                        Button {
                            editTarget = n
                            editTitle = n.title
                            editDetail = n.detail
                            editKind = n.kind
                            editStatus = n.status
                            extraValues = n.extra
                            showEdit = true
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Image(systemName: iconForKind(n.kind))
                                        .symbolRenderingMode(.hierarchical)
                                        .foregroundStyle(CreamTheme.green)
                                    Text(n.title).font(.headline)
                                }
                                Text(n.detail).font(.subheadline).foregroundStyle(.secondary)
                                Text("类型：\(n.kind) · 状态：\(n.status)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button("已整理") { store.markInboxDone(id: n.id) }.tint(.green)
                        }
                    }
                    .onDelete(perform: store.removeInbox)
                }
            }
            .navigationTitle("随手记")
            .navigationBarTitleDisplayMode(.inline)
            .listStyle(.insetGrouped)
            .tint(CreamTheme.green)
            .scrollContentBackground(.hidden)
            .background(CreamTheme.glassStrong)
            .onChange(of: inboxFields) { _ in
                store.reloadFieldConfig()
            }
            .sheet(isPresented: $showEdit) {
                NavigationStack {
                    Form {
                        TextField(fieldName(0, "标题"), text: $editTitle)
                        TextField(fieldName(1, "详情"), text: $editDetail, axis: .vertical)
                        ForEach(Array(extraFieldNames.enumerated()), id: \.element) { idx, field in
                            extraInputView(field: field, extraIndex: idx)
                        }
                        Picker(fieldName(2, "类型"), selection: $editKind) {
                            ForEach(kindOptions, id: \.self) { op in
                                Label(op, systemImage: iconForKind(op)).tag(op)
                            }
                        }
                        Picker(fieldName(3, "状态"), selection: $editStatus) {
                            ForEach(statusOptions, id: \.self) { op in Text(op).tag(op) }
                        }
                    }
                    .navigationTitle("编辑随手记")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("取消") { showEdit = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("保存") {
                                if let t = editTarget {
                                    store.updateInbox(id: t.id, title: editTitle, detail: editDetail, kind: editKind, status: editStatus, extra: extraValues)
                                }
                                showEdit = false
                            }
                            .disabled(editTitle.isEmpty)
                        }
                    }
                }
            }
        }
        .creamBackground()
    }

    private func fieldName(_ index: Int, _ fallback: String) -> String {
        let arr = store.inboxFieldNames
        return index < arr.count ? arr[index] : fallback
    }

    private var kindOptions: [String] {
        let key = fieldName(2, "类型")
        let configured = store.inboxFieldOptions[key] ?? []
        return configured.isEmpty ? ["Idea", "Todo", "Emotion", "Decision", "Question", "Reference"] : configured
    }

    private var statusOptions: [String] {
        let key = fieldName(3, "状态")
        let configured = store.inboxFieldOptions[key] ?? []
        return configured.isEmpty ? ["待整理", "已整理"] : configured
    }

    private var extraFieldNames: [String] {
        let arr = store.inboxFieldNames
        return arr.count > 4 ? Array(arr.dropFirst(4)) : []
    }

    @ViewBuilder
    private func extraInputView(field: String, extraIndex: Int) -> some View {
        let t = fieldTypeForExtraField(at: extraIndex)
        let options = store.inboxFieldOptions[field] ?? []
        if t == "select" && !options.isEmpty {
            Picker(field, selection: Binding(
                get: { extraValues[field] ?? options.first ?? "" },
                set: { extraValues[field] = $0 }
            )) {
                ForEach(options, id: \.self) { op in Text(op).tag(op) }
            }
        } else {
            TextField(field, text: Binding(
                get: { extraValues[field] ?? "" },
                set: { extraValues[field] = $0 }
            ))
            .keyboardType(keyboardTypeForType(t))
        }
    }

    private func fieldTypeForExtraField(at extraIndex: Int) -> String {
        let types = store.inboxFieldTypes
        let fullIndex = extraIndex + 4
        return fullIndex < types.count ? types[fullIndex].lowercased() : "text"
    }

    private func keyboardTypeForType(_ t: String) -> UIKeyboardType {
        t == "number" ? .decimalPad : .default
    }

    private func iconForKind(_ kind: String) -> String {
        switch kind.lowercased() {
        case "idea": return "lightbulb"
        case "todo": return "checkmark.circle"
        case "emotion": return "heart"
        case "decision": return "arrow.triangle.branch"
        case "question": return "questionmark.circle"
        case "reference": return "bookmark"
        default: return "note.text"
        }
    }
}
