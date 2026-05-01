import SwiftUI

/// 第二大脑卡片详情页（PRD 5.7）：title + topics + content + 来源 + 关联卡片 + 反向链接。
/// 右上角"编辑"按钮弹 BrainCardEditorSheet。
struct BrainCardDetailView: View {
    @EnvironmentObject var store: AppStore

    let cardId: UUID

    @State private var showEditor: Bool = false
    @State private var showLinkPicker: Bool = false

    /// 实时从 store 取最新版本：编辑后 store 数组更新会触发 body 重算
    private var card: BrainCard? {
        store.brainCards.first(where: { $0.id == cardId })
    }

    private var linked: [BrainCard] {
        guard let card else { return [] }
        return card.links.compactMap { id in
            store.brainCards.first(where: { $0.id == id })
        }
    }

    private var backlinks: [BrainCard] {
        store.backlinks(for: cardId)
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
        .sheet(isPresented: $showLinkPicker) {
            CardLinkPickerSheet(currentCardId: cardId)
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
                if linked.isEmpty {
                    Text("还没关联任何卡片。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.white.opacity(0.85))
                } else {
                    ForEach(linked) { other in
                        NavigationLink {
                            BrainCardDetailView(cardId: other.id)
                                .environmentObject(store)
                        } label: {
                            cardLinkRow(other)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                store.unlinkBrainCards(cardId, other.id)
                            } label: {
                                Label("取消关联", systemImage: "link.badge.minus")
                            }
                        }
                        .listRowBackground(Color.white.opacity(0.85))
                    }
                }

                Button {
                    showLinkPicker = true
                } label: {
                    Label("关联卡片", systemImage: "plus.circle")
                        .foregroundStyle(CreamTheme.green)
                }
                .listRowBackground(Color.white.opacity(0.85))
            } header: {
                sectionHeader(icon: "link", text: "关联卡片 (\(linked.count))")
            }

            Section {
                if backlinks.isEmpty {
                    Text("暂无其他卡片引用这张。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.white.opacity(0.85))
                } else {
                    ForEach(backlinks) { other in
                        NavigationLink {
                            BrainCardDetailView(cardId: other.id)
                                .environmentObject(store)
                        } label: {
                            cardLinkRow(other)
                        }
                        .listRowBackground(Color.white.opacity(0.85))
                    }
                }
            } header: {
                sectionHeader(icon: "arrow.uturn.left", text: "反向链接 (\(backlinks.count))")
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

    private func cardLinkRow(_ card: BrainCard) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(card.title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
            if !card.topics.isEmpty {
                Text(card.topics.joined(separator: " "))
                    .font(.caption2)
                    .foregroundStyle(CreamTheme.green.opacity(0.8))
            }
        }
        .padding(.vertical, 2)
    }
}
