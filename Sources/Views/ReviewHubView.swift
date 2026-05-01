import SwiftUI

/// 复盘 Tab 进入时的 Hub 仪表盘。
/// V1 PR 4：Review 卡片可点 push 进 ReviewSessionView；第二大脑卡片显占位"即将上线"。
/// V1 PR 5：第二大脑卡片激活，显示张数 + 最近预览，点击 push 进 BrainCardWallView。
struct ReviewHubView: View {
    @EnvironmentObject var store: AppStore

    private var pending: Int { ReviewQueue.pendingCount(turns: store.turns) }
    private var archived: Int { ReviewQueue.archivedCount(turns: store.turns) }
    private var dismissed: Int { ReviewQueue.dismissedCount(turns: store.turns) }

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
                    secondBrainPlaceholder
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 8, trailing: 12))
                        .listRowSeparator(.hidden)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(CreamTheme.glassStrong)
            .navigationTitle("复盘")
        }
        .creamBackground()
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

    // MARK: - 第二大脑 卡片（PR 4 占位）

    private var secondBrainPlaceholder: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "brain.head.profile")
                    .foregroundStyle(.secondary)
                Text("第二大脑")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text("即将上线")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(red: 0.96, green: 0.96, blue: 0.96))
                    .clipShape(Capsule())
            }
            Text("处理过的「想法 / 感受」可以沉淀成卡片，按主题聚合。")
                .font(.caption)
                .foregroundStyle(.secondary.opacity(0.85))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.gray.opacity(0.15), lineWidth: 1)
        )
    }
}
