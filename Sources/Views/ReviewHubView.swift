import SwiftUI

/// 复盘 Tab 进入时的 Hub 仪表盘。
/// V1 PR 4：Review 卡片可点 push 进 ReviewSessionView；第二大脑卡片显占位"即将上线"。
/// V1 PR 5：第二大脑卡片激活，显示张数 + 最近预览，点击 push 进 BrainCardWallView。
struct ReviewHubView: View {
    @EnvironmentObject var store: AppStore
    @AppStorage("review.hub.window") private var windowRaw: String = HubWindow.week.rawValue
    @AppStorage("review.hub.selectedDate") private var selectedDateRaw: String = ""
    @State private var displayMonth = Date()
    @State private var showCalendarOverlay = false

    private let calendar = Calendar.current

    private enum HubWindow: String, CaseIterable, Identifiable {
        case week
        case month

        var id: String { rawValue }
        var title: String { self == .week ? "周" : "月" }
    }

    private var window: HubWindow {
        get { HubWindow(rawValue: windowRaw) ?? .week }
        nonmutating set { windowRaw = newValue.rawValue }
    }

    private var selectedReviewDate: Date {
        get { parseStoredDate(selectedDateRaw) ?? Date() }
        nonmutating set { selectedDateRaw = storageDateFormatter.string(from: newValue) }
    }

    private var period: (start: Date, end: Date) {
        switch window {
        case .week:
            let start = startOfWeek(for: selectedReviewDate)
            return (start, calendar.date(byAdding: .day, value: 7, to: start) ?? start)
        case .month:
            let start = startOfMonth(for: selectedReviewDate)
            return (start, calendar.date(byAdding: .month, value: 1, to: start) ?? start)
        }
    }

    private var pending: Int { ReviewQueue.pendingCount(turns: store.turns, start: period.start, end: period.end) }
    private var archived: Int { ReviewQueue.archivedCount(turns: store.turns, start: period.start, end: period.end) }
    private var dismissed: Int { ReviewQueue.dismissedCount(turns: store.turns, start: period.start, end: period.end) }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                ScrollView {
                    VStack(spacing: 12) {
                        NavigationLink {
                            ReviewSessionView().environmentObject(store)
                        } label: {
                            reviewCard
                        }
                        .buttonStyle(.plain)

                        NavigationLink {
                            BrainCardWallView().environmentObject(store)
                        } label: {
                            secondBrainCard
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, 18)
                }
                .background(CreamTheme.glassStrong)
                .navigationTitle("复盘")
                .toolbar(.hidden, for: .navigationBar)
                .safeAreaInset(edge: .top, spacing: 0) {
                    topPeriodBar
                }

                if showCalendarOverlay {
                    calendarOverlay
                        .transition(.opacity)
                        .zIndex(20)
                }
            }
            .onAppear {
                displayMonth = startOfMonth(for: selectedReviewDate)
            }
        }
        .creamBackground()
    }

    private var topPeriodBar: some View {
        HStack(spacing: 10) {
            Text("复盘")
                .font(.headline.weight(.semibold))

            Picker("", selection: Binding(get: { window }, set: { window = $0 })) {
                ForEach(HubWindow.allCases) { value in
                    Text(value.title).tag(value)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 88)

            Spacer(minLength: 6)

            Button {
                displayMonth = startOfMonth(for: selectedReviewDate)
                withAnimation(.easeOut(duration: 0.10)) {
                    showCalendarOverlay.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Text(periodTitle)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Image(systemName: showCalendarOverlay ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(CreamTheme.green)
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(Color(red: 0.95, green: 0.97, blue: 0.95))
                .overlay(
                    RoundedRectangle(cornerRadius: 11)
                        .stroke(CreamTheme.green.opacity(0.20), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 11))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.white.opacity(0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(CreamTheme.green.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.045), radius: 10, x: 0, y: 3)
        .padding(.horizontal, 12)
        .padding(.top, 6)
    }

    private var calendarOverlay: some View {
        let reviewDateKeys = Set(
            store.turns
                .filter { ["想法", "感受"].contains($0.recognizedType) }
                .map { store.calendarDateKey(for: $0.createdAt) }
        )

        return CreamCalendarOverlay(
            selectedDate: Binding(get: { selectedReviewDate }, set: { selectedReviewDate = $0 }),
            displayMonth: $displayMonth,
            isPresented: $showCalendarOverlay,
            markerForDate: { day in
                reviewDateKeys.contains(store.calendarDateKey(for: day)) ? .dot(CreamTheme.green) : .none
            }
        )
    }

    // MARK: - Review 卡片

    private var reviewCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .firstTextBaseline) {
                Text("Review")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary.opacity(0.45))
            }

            HStack(spacing: 0) {
                statBlock(label: "待处理", value: pending, color: .primary)
                Divider().frame(height: 28)
                statBlock(label: "已处理", value: archived, color: CreamTheme.green)
                Divider().frame(height: 28)
                statBlock(label: "搁置", value: dismissed, color: .secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
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

    private var periodTitle: String {
        switch window {
        case .week:
            return "\(shortDateTitle(period.start))-\(shortDateTitle(calendar.date(byAdding: .day, value: -1, to: period.end) ?? period.start))"
        case .month:
            return monthTitle(period.start)
        }
    }

    private var storageDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    private func parseStoredDate(_ raw: String) -> Date? {
        guard !raw.isEmpty else { return nil }
        return storageDateFormatter.date(from: raw)
    }

    private func startOfWeek(for date: Date) -> Date {
        var weekCalendar = Calendar.current
        weekCalendar.firstWeekday = 2
        let comps = weekCalendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return weekCalendar.date(from: comps) ?? weekCalendar.startOfDay(for: date)
    }

    private func startOfMonth(for date: Date) -> Date {
        let comps = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: comps) ?? calendar.startOfDay(for: date)
    }

    private func shortDateTitle(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M/d"
        return formatter.string(from: date)
    }

    private func monthTitle(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月"
        return formatter.string(from: date)
    }

    private func statBlock(label: String, value: Int, color: Color) -> some View {
        VStack(spacing: 3) {
            Text("\(value)")
                .font(.title3.weight(.bold))
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
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "brain.head.profile")
                    .foregroundStyle(CreamTheme.green)
                Text("第二大脑")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(brainCount) 张")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary.opacity(0.45))
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
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
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
