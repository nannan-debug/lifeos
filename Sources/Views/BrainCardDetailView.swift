import SwiftUI

/// 第二大脑卡片详情页（PRD 5.7）：title + topics + content + 来源。
/// 右上角"编辑"按钮弹 BrainCardEditorSheet。
struct BrainCardDetailView: View {
    @EnvironmentObject var store: AppStore

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
                // 卡片被删除（编辑 sheet 内删除按钮触发）→ 让 NavigationStack 自动 pop
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
                BrainCardEditorSheet(mode: .edit(card: card))
                    .environmentObject(store)
            }
        }
        .sheet(isPresented: $showExtensionComposer) {
            BrainCardExtensionComposerSheet(cardId: cardId)
                .environmentObject(store)
        }
    }

    @ViewBuilder
    private func content(for card: BrainCard) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text(card.title)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.primary)

                    if !card.topics.isEmpty {
                        Text(card.topics.joined(separator: "  "))
                            .font(.caption)
                            .foregroundStyle(CreamTheme.green)
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

            if !card.sources.isEmpty {
                Section {
                    ForEach(card.sources, id: \.noteId) { src in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(src.excerpt)
                                .font(.subheadline)
                            Text("来自随手记")
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
