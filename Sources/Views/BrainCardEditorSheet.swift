import SwiftUI

enum BrainCardEditorMode {
    /// 从 Review 模式右滑「→ 第二大脑」衍生：sources 由 turn 自动建立，
    /// 保存时联动 derivative + reviewStatus = "archived"
    case deriveFromTurn(turn: ConversationTurn)
    case edit(card: BrainCard)
}

struct BrainCardEditorSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    let mode: BrainCardEditorMode

    @State private var title: String = ""
    @State private var content: String = ""
    @State private var topics: [String] = []
    /// 仅展示用：新建模式下从 turn 预填的来源；编辑模式下读卡片的 sources。两种模式都只读。
    @State private var sources: [BrainCardSource] = []

    private var editingID: UUID? {
        if case .edit(let c) = mode { return c.id }
        return nil
    }

    private var availableTopics: [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for card in store.brainCards {
            for t in card.topics where !seen.contains(t) {
                seen.insert(t)
                ordered.append(t)
            }
        }
        return ordered
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("标题", text: $title)
                        .font(.title3.weight(.semibold))
                }

                Section("正文") {
                    TextField("写点什么…", text: $content, axis: .vertical)
                        .lineLimit(4...12)
                }

                Section("主题") {
                    TopicChipInput(topics: $topics, availableTopics: availableTopics)
                }

                if !sources.isEmpty {
                    Section("来源") {
                        ForEach(sources, id: \.noteId) { src in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(src.excerpt)
                                    .font(.subheadline)
                                Text("来自随手记")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                if editingID != nil {
                    Section {
                        Button("删除卡片", role: .destructive) {
                            if let id = editingID {
                                store.removeBrain(id: id)
                            }
                            dismiss()
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
            .navigationTitle(editingID == nil ? "新建卡片" : "编辑卡片")
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
        case .deriveFromTurn(let turn):
            // 标题预填 = turn 原文前 20 字（与 → ToDo 同款），剩下进 content
            let raw = turn.rawText
            if raw.count <= 20 {
                title = raw
                content = ""
            } else {
                title = String(raw.prefix(20))
                content = String(raw.dropFirst(20))
            }
            // 来源 excerpt 取 turn 原文前 30 字（与 → ToDo 同款）
            let excerpt = raw.count > 30 ? String(raw.prefix(30)) + "…" : raw
            sources = [BrainCardSource(noteId: turn.id, excerpt: excerpt)]
            topics = []
        case .edit(let c):
            title = c.title
            content = c.content
            topics = c.topics
            sources = c.sources
        }
    }

    private func save() {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return }

        switch mode {
        case .edit(let c):
            store.updateBrain(id: c.id, title: cleanTitle, content: content, topics: topics)
        case .deriveFromTurn(let turn):
            let cardID = store.addBrain(
                title: cleanTitle,
                content: content,
                topics: topics,
                sources: sources
            )
            if let cardID {
                store.appendTurnDerivative(
                    turnId: turn.id,
                    derivative: TurnDerivative(type: "brain", targetId: cardID, createdAt: Date())
                )
                store.updateTurnReviewStatus(id: turn.id, reviewStatus: "archived")
            }
        }
        dismiss()
    }
}
