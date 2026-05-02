import SwiftUI

// MARK: - Queue logic (抽出来便于单测)

/// Review 模式队列 + 统计的纯函数。
/// 输入 turns，输出过滤排序后的队列、各状态计数。所有时间窗口都是当下往前滚 7 天。
enum ReviewQueue {

    /// Review 模式队列：想法/感受 + reviewStatus pending + 最近 7 天 + 倒序
    static func queue(turns: [ConversationTurn], now: Date = Date()) -> [ConversationTurn] {
        filtered(turns: turns, now: now, statuses: ["pending"])
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// 7 日窗内 reviewStatus == archived 的想法/感受条数
    static func archivedCount(turns: [ConversationTurn], now: Date = Date()) -> Int {
        filtered(turns: turns, now: now, statuses: ["archived"]).count
    }

    /// 7 日窗内 reviewStatus == dismissed 的想法/感受条数
    static func dismissedCount(turns: [ConversationTurn], now: Date = Date()) -> Int {
        filtered(turns: turns, now: now, statuses: ["dismissed"]).count
    }

    /// 7 日窗内 reviewStatus == pending 的想法/感受条数（即 queue.count）
    static func pendingCount(turns: [ConversationTurn], now: Date = Date()) -> Int {
        filtered(turns: turns, now: now, statuses: ["pending"]).count
    }

    private static let queueableTypes: Set<String> = ["想法", "感受"]

    private static func filtered(turns: [ConversationTurn], now: Date, statuses: Set<String>) -> [ConversationTurn] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now
        return turns.filter { turn in
            turn.createdAt >= cutoff
                && queueableTypes.contains(turn.recognizedType)
                && statuses.contains(turn.reviewStatus)
        }
    }
}

// MARK: - Sheet payload helper

private struct DerivePayload: Identifiable {
    let turn: ConversationTurn
    var id: UUID { turn.id }
}

// MARK: - View

struct ReviewSessionView: View {
    @EnvironmentObject var store: AppStore

    @State private var deriveTodoFromTurn: DerivePayload?
    @State private var deriveBrainFromTurn: DerivePayload?

    private static let timeStampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d HH:mm"
        return formatter
    }()

    private var queue: [ConversationTurn] {
        ReviewQueue.queue(turns: store.turns)
    }

    private var pending: Int { queue.count }
    private var archived: Int { ReviewQueue.archivedCount(turns: store.turns) }
    private var dismissed: Int { ReviewQueue.dismissedCount(turns: store.turns) }

    var body: some View {
        List {
            Section {
                statHeader
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 12, trailing: 12))
            }

            if queue.isEmpty {
                Section {
                    emptyState
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            } else {
                Section {
                    ForEach(queue) { turn in
                        queueCard(turn)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(CreamTheme.glassStrong)
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
        .creamBackground()
        .sheet(item: $deriveTodoFromTurn) { payload in
            TodoEditorSheet(mode: .deriveFromTurn(turn: payload.turn))
                .environmentObject(store)
        }
        .sheet(item: $deriveBrainFromTurn) { payload in
            BrainCardEditorSheet(mode: .deriveFromTurn(turn: payload.turn))
                .environmentObject(store)
        }
    }

    // MARK: - Stat header

    private var statHeader: some View {
        HStack(spacing: 0) {
            statCell(label: "待处理", value: pending, color: .primary)
            Divider().frame(height: 32)
            statCell(label: "已处理", value: archived, color: CreamTheme.green)
            Divider().frame(height: 32)
            statCell(label: "搁置", value: dismissed, color: .secondary)
        }
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.9))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(CreamTheme.green.opacity(0.12), lineWidth: 1)
        )
    }

    private func statCell(label: String, value: Int, color: Color) -> some View {
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

    // MARK: - Queue card

    private func queueCard(_ turn: ConversationTurn) -> some View {
        HStack(spacing: 0) {
            // 左侧彩色竖条（跟随记 Tab 日视图卡片同款）
            RoundedRectangle(cornerRadius: 2)
                .fill(TurnTypeStyle.color(for: turn.recognizedType))
                .frame(width: 4)
                .padding(.vertical, 6)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(turn.createdAt, formatter: Self.timeStampFormatter)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    typeChip(turn.recognizedType)
                }

                Text(TurnTypeStyle.displayText(for: turn))
                    .font(.subheadline)

                if turn.moodScore != nil || !turn.feelingTags.isEmpty {
                    moodLine(turn)
                }
            }
            .padding(.leading, 10)
            .padding(.trailing, 12)
            .padding(.vertical, 12)
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.9))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(TurnTypeStyle.color(for: turn.recognizedType).opacity(0.12), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.035), radius: 8, x: 0, y: 2)
        .listRowInsets(EdgeInsets(top: 5, leading: 8, bottom: 5, trailing: 8))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                store.updateTurnReviewStatus(id: turn.id, reviewStatus: "dismissed")
            } label: {
                Label("搁置", systemImage: "xmark.circle")
            }
            .tint(.gray)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            // 想法卡片：[→ 第二大脑] [→ ToDo]
            // 感受卡片：[→ 第二大脑]（PRD 3.4：感受不能直接转 ToDo）
            Button {
                deriveBrainFromTurn = DerivePayload(turn: turn)
            } label: {
                Label("→ 第二大脑", systemImage: "brain.head.profile")
            }
            .tint(CreamTheme.green.opacity(0.85))

            if turn.recognizedType == "想法" {
                Button {
                    deriveTodoFromTurn = DerivePayload(turn: turn)
                } label: {
                    Label("→ ToDo", systemImage: "checkmark.circle")
                }
                .tint(CreamTheme.green)
            }
        }
    }

    private func typeChip(_ type: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: TurnTypeStyle.icon(for: type))
                .font(.caption2)
            Text(type)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(TurnTypeStyle.color(for: type))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(TurnTypeStyle.bgColor(for: type))
        .clipShape(Capsule())
    }

    private func moodLine(_ turn: ConversationTurn) -> some View {
        HStack(spacing: 6) {
            if let score = turn.moodScore {
                Text(moodEmoji(for: score))
                    .font(.system(size: 14))
            }
            ForEach(turn.feelingTags, id: \.self) { tag in
                Text(tag)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(TurnTypeStyle.color(for: turn.recognizedType).opacity(0.8))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(TurnTypeStyle.bgColor(for: turn.recognizedType))
                    .clipShape(Capsule())
            }
        }
    }

    private func moodEmoji(for score: Int) -> String {
        switch score {
        case 1: return "😣"
        case 2: return "😔"
        case 3: return "😐"
        case 4: return "🙂"
        case 5: return "😄"
        default: return ""
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            MascotCatAssetView(stroke: CreamTheme.green)
                .frame(width: 96, height: 96)
            Text("队列已清空。")
                .font(.headline)
                .foregroundStyle(CreamTheme.green)
            Text("下周再见。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}
