import SwiftUI

/// 详情页"+ 关联卡片"sheet：列所有其他卡片（排除自己 + 已链接），
/// 顶部搜索框 filter title；勾选自动调 store.linkBrainCards 建立双向连接，
/// "完成"关 sheet。
struct CardLinkPickerSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    let currentCardId: UUID

    @State private var query: String = ""

    private var candidates: [BrainCard] {
        guard let current = store.brainCards.first(where: { $0.id == currentCardId }) else { return [] }
        let excluded = Set([currentCardId] + current.links)
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return store.brainCards
            .filter { !excluded.contains($0.id) }
            .filter { q.isEmpty || $0.title.lowercased().contains(q) || $0.content.lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar

                if candidates.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(candidates) { card in
                            Button {
                                store.linkBrainCards(currentCardId, card.id)
                            } label: {
                                row(card)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("关联卡片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .tint(CreamTheme.green)
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("搜索卡片", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func row(_ card: BrainCard) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "plus.circle")
                .foregroundStyle(CreamTheme.green)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(card.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                if !card.content.isEmpty {
                    Text(card.content)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if !card.topics.isEmpty {
                    Text(card.topics.joined(separator: " "))
                        .font(.caption2)
                        .foregroundStyle(CreamTheme.green.opacity(0.85))
                }
            }
        }
        .padding(.vertical, 6)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "link")
                .font(.title)
                .foregroundStyle(.secondary)
            Text(query.isEmpty ? "暂时没有可关联的卡片。" : "没有匹配的卡片。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
