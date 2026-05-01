import SwiftUI

/// 第二大脑入口页：顶部 segment toggle "卡片墙 / 主题"。
/// - 卡片墙：List 按 createdAt 倒序，每行 title + content 前 60 字 + topics + sources count。
/// - 主题：顶部水平 topic chip，选中后下方变成该 topic 卡片列表。
struct BrainCardWallView: View {
    @EnvironmentObject var store: AppStore

    enum Mode: String, CaseIterable, Identifiable {
        case wall = "卡片墙"
        case topic = "主题"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .wall
    @State private var selectedTopic: String? = nil

    private var allCards: [BrainCard] {
        store.brainCards.sorted { $0.createdAt > $1.createdAt }
    }

    private var allTopics: [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for card in allCards {
            for t in card.topics where !seen.contains(t) {
                seen.insert(t)
                ordered.append(t)
            }
        }
        return ordered
    }

    private var topicCards: [BrainCard] {
        guard let t = selectedTopic else { return [] }
        return allCards.filter { $0.topics.contains(t) }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $mode) {
                ForEach(Mode.allCases) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 4)

            if mode == .wall {
                wallView
            } else {
                topicView
            }
        }
        .navigationTitle("第二大脑")
        .navigationBarTitleDisplayMode(.inline)
        .creamBackground()
        .onAppear {
            // 进入主题模式时默认选第一个 topic
            if mode == .topic, selectedTopic == nil {
                selectedTopic = allTopics.first
            }
        }
        .onChange(of: mode) { newValue in
            if newValue == .topic, selectedTopic == nil {
                selectedTopic = allTopics.first
            }
        }
    }

    // MARK: - 卡片墙

    @ViewBuilder
    private var wallView: some View {
        if allCards.isEmpty {
            emptyWall
        } else {
            List {
                ForEach(allCards) { card in
                    NavigationLink {
                        BrainCardDetailView(cardId: card.id)
                            .environmentObject(store)
                    } label: {
                        cardRow(card)
                    }
                    .listRowBackground(Color.white.opacity(0.9))
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(CreamTheme.glassStrong)
        }
    }

    // MARK: - 主题视图

    @ViewBuilder
    private var topicView: some View {
        if allTopics.isEmpty {
            emptyTopics
        } else {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(allTopics, id: \.self) { topic in
                            topicChip(topic)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                .background(Color.white.opacity(0.5))

                if topicCards.isEmpty {
                    Spacer()
                    Text("这个主题下还没有卡片。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                } else {
                    List {
                        ForEach(topicCards) { card in
                            NavigationLink {
                                BrainCardDetailView(cardId: card.id)
                                    .environmentObject(store)
                            } label: {
                                cardRow(card)
                            }
                            .listRowBackground(Color.white.opacity(0.9))
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                    .background(CreamTheme.glassStrong)
                }
            }
        }
    }

    private func topicChip(_ topic: String) -> some View {
        let active = selectedTopic == topic
        return Button {
            selectedTopic = topic
        } label: {
            Text(topic)
                .font(.caption.weight(.medium))
                .foregroundStyle(active ? .white : CreamTheme.green)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(active ? CreamTheme.green : CreamTheme.green.opacity(0.12))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Card row

    private func cardRow(_ card: BrainCard) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(card.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            if !card.content.isEmpty {
                Text(snippet(card.content))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 6) {
                if !card.topics.isEmpty {
                    Text(card.topics.joined(separator: " "))
                        .font(.caption2)
                        .foregroundStyle(CreamTheme.green.opacity(0.85))
                }
                Spacer()
                if !card.sources.isEmpty {
                    Label("\(card.sources.count)", systemImage: "link")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func snippet(_ text: String) -> String {
        if text.count <= 60 { return text }
        return String(text.prefix(60)) + "…"
    }

    // MARK: - Empty states

    private var emptyWall: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "brain.head.profile")
                .font(.system(size: 48))
                .foregroundStyle(CreamTheme.green.opacity(0.7))
            Text("还没有卡片。")
                .font(.headline)
                .foregroundStyle(CreamTheme.green)
            Text("处理过的「想法 / 感受」可以沉淀成卡片，按主题聚合。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyTopics: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "number")
                .font(.title)
                .foregroundStyle(.secondary)
            Text("还没有主题。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
