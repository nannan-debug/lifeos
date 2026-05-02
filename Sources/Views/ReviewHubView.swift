import SwiftUI

/// 复盘 Tab 进入时的 Hub 仪表盘。
/// V1 PR 4：Review 卡片可点 push 进 ReviewSessionView；第二大脑卡片显占位"即将上线"。
/// V1 PR 5：第二大脑卡片激活，显示张数 + 最近预览，点击 push 进 BrainCardWallView。
struct ReviewHubView: View {
    @EnvironmentObject var store: AppStore
    @AppStorage("review.hub.window") private var windowRaw: String = HubWindow.week.rawValue

    private enum HubWindow: String, CaseIterable, Identifiable {
        case week
        case month

        var id: String { rawValue }
        var title: String { self == .week ? "本周" : "本月" }
        var days: Int { self == .week ? 7 : 30 }
    }

    private var window: HubWindow {
        get { HubWindow(rawValue: windowRaw) ?? .week }
        nonmutating set { windowRaw = newValue.rawValue }
    }

    private var pending: Int { ReviewQueue.pendingCount(turns: store.turns, windowDays: window.days) }
    private var archived: Int { ReviewQueue.archivedCount(turns: store.turns, windowDays: window.days) }
    private var dismissed: Int { ReviewQueue.dismissedCount(turns: store.turns, windowDays: window.days) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        ReviewSessionView().environmentObject(store)
                    } label: {
                        reviewCard
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 8, trailing: 12))
                    .listRowSeparator(.hidden)
                }

                Section {
                    NavigationLink {
                        BrainCardWallView().environmentObject(store)
                    } label: {
                        secondBrainCard
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 8, trailing: 12))
                    .listRowSeparator(.hidden)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(CreamTheme.glassStrong)
            .navigationTitle("复盘")
            .safeAreaInset(edge: .top) {
                windowPicker
            }
        }
        .creamBackground()
    }

    private var windowPicker: some View {
        Picker("复盘窗口", selection: Binding(get: { window }, set: { window = $0 })) {
            ForEach(HubWindow.allCases) { value in
                Text(value.title).tag(value)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(CreamTheme.glassStrong)
    }

    // MARK: - Review 卡片

    private var reviewCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Review")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
            }

            HStack(spacing: 0) {
                statBlock(label: "待处理", value: pending, color: .primary)
                Divider().frame(height: 32)
                statBlock(label: "已处理", value: archived, color: CreamTheme.green)
                Divider().frame(height: 32)
                statBlock(label: "搁置", value: dismissed, color: .secondary)
            }

            if window == .month {
                Text("队列仍为最近 7 天")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.95))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(CreamTheme.green.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 3)
    }

    private func statBlock(label: String, value: Int, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.title2.weight(.bold))
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 第二大脑 卡片（PR 5 激活）

    private var brainCount: Int { store.brainCards.count }
    private var brainPreview: [BrainCard] {
        Array(store.brainCards.sorted { $0.createdAt > $1.createdAt }.prefix(2))
    }

    private var secondBrainCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "brain.head.profile")
                    .foregroundStyle(CreamTheme.green)
                Text("第二大脑")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(brainCount) 张")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            if brainPreview.isEmpty {
                Text("处理过的「想法 / 感受」可以沉淀成卡片，按主题聚合。")
                    .font(.caption)
                    .foregroundStyle(.secondary.opacity(0.85))
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(brainPreview) { card in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(CreamTheme.green.opacity(0.5))
                                .frame(width: 4, height: 4)
                            Text(card.title)
                                .font(.caption)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.95))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(CreamTheme.green.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 3)
    }
}
