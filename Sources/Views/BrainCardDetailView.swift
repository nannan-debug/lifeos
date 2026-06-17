import SwiftUI

/// 第二大脑卡片详情页（PRD 5.7）：title + topics + content + 来源。
/// 右上角"编辑"按钮弹 BrainCardEditorSheet。
struct BrainCardDetailView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    let cardId: UUID

    @State private var showEditor: Bool = false
    @State private var showExtensionComposer: Bool = false

    /// 实时从 store 取最新版本：编辑后 store 数组更新会触发 body 重算
    private var card: BrainCard? {
        store.brainCards.first(where: { $0.id == cardId })
    }

    var body: some View {
        Group {
            if let card {
                content(for: card)
            } else {
                // 卡片被删除后等待 dismiss 动画返回卡片墙。
                Color.clear
            }
        }
        .navigationTitle("卡片")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if card != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("编辑") { showEditor = true }
                        .tint(CreamTheme.green)
                }
            }
        }
        .creamBackground()
        .sheet(isPresented: $showEditor) {
            if let card {
                BrainCardEditorSheet(mode: .edit(card: card)) {
                    dismiss()
                }
                    .environmentObject(store)
            }
        }
        .sheet(isPresented: $showExtensionComposer) {
            BrainCardExtensionComposerSheet(cardId: cardId)
                .environmentObject(store)
        }
        .onChange(of: store.brainCards.map(\.id)) { ids in
            if !ids.contains(cardId), !showEditor {
                dismiss()
            }
        }
    }

    @ViewBuilder
    private func content(for card: BrainCard) -> some View {
        List {
            if let dbt = card.dbtSession {
                dbtSessionSection(card: card, session: dbt)
            } else {
                regularCardSection(card)
            }

            if !card.sources.isEmpty {
                Section {
                    ForEach(card.sources, id: \.noteId) { src in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(src.excerpt)
                                .font(.subheadline)
                            Text(card.kind == "dbtSession" ? "来自 DBT 对话" : "来自随手记")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                        .listRowBackground(Color.white.opacity(0.85))
                    }
                } header: {
                    sectionHeader(icon: "link", text: "来源 (\(card.sources.count))")
                }
            }

            if let dbt = card.dbtSession, !dbt.transcript.isEmpty {
                Section {
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(dbt.transcript) { turn in
                                DBTTranscriptTurnRow(turn: turn)
                            }
                        }
                        .padding(.vertical, 8)
                    } label: {
                        Label("\(dbt.transcript.count) 轮完整对话", systemImage: "text.bubble")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(CreamTheme.green)
                    }
                    .listRowBackground(Color.white.opacity(0.86))
                } header: {
                    sectionHeader(icon: "quote.bubble", text: "完整对话")
                }
            }

            Section {
                if card.extensions.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("后来想到的内容，可以先轻轻放在这里。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(Color.white.opacity(0.82))
                } else {
                    ForEach(card.extensions) { extensionNote in
                        BrainCardExtensionRow(extensionNote: extensionNote)
                            .swipeActions(edge: .trailing) {
                                Button("删除", role: .destructive) {
                                    store.removeBrainExtension(cardId: card.id, extensionId: extensionNote.id)
                                }
                            }
                            .listRowBackground(Color.white.opacity(0.86))
                    }
                }

                Button {
                    showExtensionComposer = true
                } label: {
                    Label("补一段想法", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(CreamTheme.green)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .listRowBackground(CreamTheme.green.opacity(0.08))
            } header: {
                sectionHeader(icon: "quote.bubble", text: "延伸思考")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(CreamTheme.glassStrong)
    }

    private func regularCardSection(_ card: BrainCard) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text(card.title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)

                if !card.topics.isEmpty {
                    topicChips(card.topics)
                }

                if !card.content.isEmpty {
                    Text(card.content)
                        .font(.body)
                        .foregroundStyle(.primary)
                }
            }
            .padding(.vertical, 4)
            .listRowBackground(Color.white.opacity(0.9))
        }
    }

    private func topicChips(_ topics: [String]) -> some View {
        HStack(spacing: 6) {
            ForEach(topics, id: \.self) { topic in
                Text(topic.hasPrefix("#") ? topic : "#\(topic)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(CreamTheme.green)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(CreamTheme.green.opacity(0.12)))
            }
        }
    }

    @ViewBuilder
    private func dbtSessionSection(card: BrainCard, session: BrainDBTSession) -> some View {
        let summaries = displayDBTSummaries(session.summary)
        let actions = displayDBTActions(session.actions)
        Section {
            VStack(alignment: .leading, spacing: 14) {
                Label("DBT 会话卡", systemImage: "leaf")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(CreamTheme.green)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(CreamTheme.green.opacity(0.12)))

                Text(card.title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)

                if !card.topics.isEmpty {
                    topicChips(card.topics)
                }

                if let shift = session.emotionalShift, !shift.isEmpty {
                    Label(shift, systemImage: "waveform.path.ecg")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 12).fill(CreamTheme.green.opacity(0.08)))
                }
            }
            .padding(.vertical, 4)
            .listRowBackground(Color.white.opacity(0.9))

            if !summaries.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("本次练习摘要")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(Array(summaries.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .top, spacing: 9) {
                            Circle()
                                .fill(CreamTheme.green.opacity(0.68))
                                .frame(width: 6, height: 6)
                                .padding(.top, 7)
                            Text(item)
                                .font(.body)
                                .foregroundStyle(.primary)
                        }
                    }
                }
                .padding(.vertical, 4)
                .listRowBackground(Color.white.opacity(0.86))
            }

            if !session.skills.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("使用技能")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(session.skills) { skill in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(skill.name)
                                .font(.subheadline.weight(.semibold))
                            Text(skill.note)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 12).fill(CreamTheme.green.opacity(0.07)))
                    }
                }
                .padding(.vertical, 4)
                .listRowBackground(Color.white.opacity(0.86))
            }

            if !actions.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("后续行动")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(Array(actions.enumerated()), id: \.offset) { _, action in
                        Label(action, systemImage: "checkmark.circle")
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                    }
                }
                .padding(.vertical, 4)
                .listRowBackground(Color.white.opacity(0.86))
            }
        }
    }

    private func displayDBTSummaries(_ summaries: [String]) -> [String] {
        summaries
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { item in
                !item.isEmpty
                    && !item.contains("保留完整对话")
                    && !item.contains("沉淀到第二大脑")
                    && !item.contains("不只停留在当下")
            }
    }

    private func displayDBTActions(_ actions: [String]) -> [String] {
        let markers = ["下一步", "后续行动", "我会", "我准备", "我打算", "行动：", "行动:"]
        return actions
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { item in
                guard !item.isEmpty else { return false }
                return markers.contains { item.hasPrefix($0) }
            }
    }

    private func sectionHeader(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text)
        }
    }
}

private struct BrainCardExtensionRow: View {
    let extensionNote: BrainCardExtension

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(CreamTheme.green.opacity(0.52))
                    .frame(width: 3, height: 13)

                Text(extensionNote.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Text(extensionNote.content)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }
}

private struct DBTTranscriptTurnRow: View {
    let turn: BrainDBTTurn

    private var isUser: Bool { turn.role == "user" }

    var body: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 5) {
            Text(isUser ? "我" : "AI")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(turn.content)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(isUser ? Color.black.opacity(0.045) : CreamTheme.green.opacity(0.08))
                )
                .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        }
    }
}

private struct BrainCardExtensionComposerSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    let cardId: UUID

    @State private var content: String = ""

    private var canSave: Bool {
        !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("现在想到什么，先放这里…", text: $content, axis: .vertical)
                        .lineLimit(5...12)
                } footer: {
                    Text("这段内容会追加到卡片的延伸思考里，不会覆盖原来的正文。")
                }
            }
            .navigationTitle("补一段想法")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        if store.addBrainExtension(cardId: cardId, content: content) != nil {
                            dismiss()
                        }
                    }
                    .disabled(!canSave)
                }
            }
            .tint(CreamTheme.green)
        }
    }
}
