import SwiftUI

/// 第二大脑卡片详情页（PRD 5.7）：title + topics + content + 来源。
/// 右上角"编辑"按钮弹 BrainCardEditorSheet。
struct BrainCardDetailView: View {
    @EnvironmentObject var store: AppStore

    let cardId: UUID

    @State private var showEditor: Bool = false

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
