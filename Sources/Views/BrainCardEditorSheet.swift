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
    @State private var aiSuggestions: [String]? = nil
    @State private var aiLoading: Bool = false
    @State private var didRequestAISuggestions: Bool = false
    @State private var aiSuggestionTask: Task<Void, Never>? = nil
    @State private var aiTitleTask: Task<Void, Never>? = nil
    @State private var aiTitleLoading: Bool = false
    @State private var aiTitleSuggestion: String? = nil

    private static let defaultTopics = ["#工作", "#学习", "#生活", "#灵感", "#人际"]

    private var editingID: UUID? {
        if case .edit(let c) = mode { return c.id }
        return nil
    }

    private var availableTopics: [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for t in Self.defaultTopics {
            seen.insert(t)
            ordered.append(t)
        }
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

                    if aiTitleLoading {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.75)
                            Text("AI 正在想标题")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else if let aiTitleSuggestion, !aiTitleSuggestion.isEmpty {
                        Button {
                            title = aiTitleSuggestion
                        } label: {
                            HStack(spacing: 6) {
                                Text("AI")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(CreamTheme.green)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(CreamTheme.green.opacity(0.10))
                                    .clipShape(Capsule())
                                Text(aiTitleSuggestion)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(CreamTheme.green)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(CreamTheme.green.opacity(0.08))
                            .overlay(
                                Capsule()
                                    .stroke(CreamTheme.green.opacity(0.18), lineWidth: 1)
                            )
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section("正文") {
                    TextField("写点什么…", text: $content, axis: .vertical)
                        .lineLimit(4...12)
                }

                Section("主题") {
                    TopicChipInput(
                        topics: $topics,
                        aiSuggestions: $aiSuggestions,
                        availableTopics: availableTopics,
                        aiLoading: aiLoading
                    )
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
            .onAppear {
                hydrate()
                requestAITitleIfNeeded()
                requestAISuggestions()
            }
            .onDisappear {
                aiSuggestionTask?.cancel()
                aiTitleTask?.cancel()
            }
        }
    }

    private func hydrate() {
        switch mode {
        case .deriveFromTurn(let turn):
            let raw = turn.rawText
            title = ""
            content = raw
            aiTitleSuggestion = nil
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

    private func requestAITitleIfNeeded() {
        guard editingID == nil else { return }
        guard case .deriveFromTurn = mode else { return }

        let cleanContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanContent.isEmpty else { return }

        aiTitleLoading = true
        aiTitleTask = Task {
            do {
                let suggestion = try await AIParser.suggestBrainTitle(content: cleanContent)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    aiTitleSuggestion = suggestion
                    aiTitleLoading = false
                    if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        title = suggestion
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    aiTitleSuggestion = nil
                    aiTitleLoading = false
                }
            }
        }
    }

    private func requestAISuggestions() {
        guard !didRequestAISuggestions else { return }
        didRequestAISuggestions = true

        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty || !cleanContent.isEmpty else {
            aiSuggestions = []
            return
        }

        aiLoading = true
        aiSuggestionTask = Task {
            do {
                let suggestions = try await AIParser.suggestTopics(title: cleanTitle, content: cleanContent)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    aiSuggestions = suggestions
                    aiLoading = false
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    aiSuggestions = []
                    aiLoading = false
                }
            }
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
