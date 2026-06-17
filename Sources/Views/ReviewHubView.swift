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
    @State private var reviewCalendarDateKeys: Set<String> = []
    @State private var snapshot = ReviewHubSnapshot.empty

    private let calendar = Calendar.current

    private enum HubWindow: String, CaseIterable, Identifiable {
        case week
        case month

        var id: String { rawValue }
        var title: String { self == .week ? L.weekLabel : L.monthLabel }
    }

    private var window: HubWindow {
        get { HubWindow(rawValue: windowRaw) ?? .week }
        nonmutating set { windowRaw = newValue.rawValue }
    }

    private var selectedReviewDate: Date {
        get { parseStoredDate(selectedDateRaw) ?? Date() }
        nonmutating set { selectedDateRaw = storageDateFormatter.string(from: newValue) }
    }

    private var currentPeriod: (start: Date, end: Date) {
        switch window {
        case .week:
            let start = startOfWeek(for: selectedReviewDate)
            return (start, calendar.date(byAdding: .day, value: 7, to: start) ?? start)
        case .month:
            let start = startOfMonth(for: selectedReviewDate)
            return (start, calendar.date(byAdding: .month, value: 1, to: start) ?? start)
        }
    }

    private var periodLabel: String {
        window == .week ? L.thisWeek : L.thisMonth
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                ScrollView {
                    VStack(spacing: 12) {
                        checkHabitCard
                        timeDistributionCard

                        NavigationLink {
                            ReviewSessionView(period: currentPeriod).environmentObject(store)
                        } label: {
                            pendingIdeasCard
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
                .navigationTitle(L.reviewTitle)
                .onAppear { UsageTracker.track(UsageTracker.reviewOpened) }
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
                refreshSnapshot()
                refreshCalendarMarkers()
            }
            .onChange(of: windowRaw) { _ in refreshSnapshot() }
            .onChange(of: selectedDateRaw) { _ in refreshSnapshot() }
            .onChange(of: displayMonth) { _ in refreshCalendarMarkers() }
            .onChange(of: store.turns.count) { _ in
                refreshSnapshot()
                refreshCalendarMarkers()
            }
            .onChange(of: store.brainCards.count) { _ in refreshSnapshot() }
            .onChange(of: store.checkItems.map(\.done)) { _ in refreshSnapshot() }
            .onChange(of: store.timeEntries.count) { _ in refreshSnapshot() }
        }
        .creamBackground()
    }

    private var topPeriodBar: some View {
        HStack(spacing: 10) {
            Text(L.reviewTitle)
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
        CreamCalendarOverlay(
            selectedDate: Binding(get: { selectedReviewDate }, set: { selectedReviewDate = $0 }),
            displayMonth: $displayMonth,
            isPresented: $showCalendarOverlay,
            markerForDate: { day in
                reviewCalendarDateKeys.contains(store.calendarDateKey(for: day)) ? .dot(CreamTheme.green) : .none
            }
        )
    }

    private func refreshCalendarMarkers() {
        reviewCalendarDateKeys = Set(
            store.turns
                .filter { ["想法", "感受"].contains($0.recognizedType) }
                .map { store.calendarDateKey(for: $0.createdAt) }
        )
    }

    private func refreshSnapshot() {
        let period = currentPeriod
        let days = dates(from: period.start, to: period.end)
        let checkGroups = store.reviewCheckGroupSummaries(start: period.start, end: period.end)
        let timeItems = store.reviewTimeCategorySummaries(start: period.start, end: period.end)
        let dayCount = calendar.dateComponents([.day], from: calendar.startOfDay(for: period.start), to: calendar.startOfDay(for: period.end)).day ?? 0
        let recordedMinutes = timeItems.reduce(0) { $0 + $1.minutes }
        let maxMinutes = max(timeItems.map(\.minutes).max() ?? 1, 1)
        let queue = ReviewQueue.queue(turns: store.turns, start: period.start, end: period.end)

        snapshot = ReviewHubSnapshot(
            period: period,
            pending: queue.count,
            checkGroupSummaries: checkGroups,
            checkWeekDates: days.map(Optional.some),
            checkMonthWeeks: monthWeeks(days: days, periodStart: period.start),
            checkStatusByGroupAndDate: checkStatusLookup(from: checkGroups),
            timeSummaries: timeItems,
            recordedTimeMinutes: recordedMinutes,
            unrecordedTimeMinutes: max(max(dayCount, 0) * 24 * 60 - recordedMinutes, 0),
            maxTimeMinutes: maxMinutes,
            recentPendingIdeas: Array(queue.prefix(2)),
            brainCount: store.brainCards.count,
            brainPreview: Array(store.brainCards.sorted { $0.createdAt > $1.createdAt }.prefix(2))
        )
    }

    private func monthWeeks(days: [Date], periodStart: Date) -> [[Date?]] {
        let leading = leadingBlankDaysBeforeMonday(for: periodStart)
        let trailing = (7 - ((leading + days.count) % 7)) % 7
        let cells = Array(repeating: nil as Date?, count: leading) + days.map(Optional.some) + Array(repeating: nil as Date?, count: trailing)
        return stride(from: 0, to: cells.count, by: 7).map { start in
            Array(cells[start..<min(start + 7, cells.count)])
        }
    }

    private func checkStatusLookup(from groups: [ReviewCheckGroupSummary]) -> [String: [String: CheckGroupStatus]] {
        Dictionary(uniqueKeysWithValues: groups.map { group in
            let days = Dictionary(uniqueKeysWithValues: group.days.map { day in
                (
                    store.calendarDateKey(for: day.date),
                    CheckGroupStatus(completedCount: day.completedCount, totalCount: day.totalCount)
                )
            })
            return (group.title, days)
        })
    }

    // MARK: - Weekly review cards

    private var checkHabitCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            cardHeader(icon: "checkmark.circle", title: L.checkCard, trailing: nil)

            if snapshot.checkGroupSummaries.isEmpty {
                emptyLine(L.emptyCheckHint)
            } else {
                checkCalendarPanel
            }
        }
        .reviewCardStyle()
    }

    private var checkCalendarPanel: some View {
        VStack(spacing: window == .week ? 0 : 10) {
            switch window {
            case .week:
                checkMatrixBlock(dates: snapshot.checkWeekDates, isMonth: false)
            case .month:
                ForEach(Array(snapshot.checkMonthWeeks.enumerated()), id: \.offset) { _, week in
                    checkMatrixBlock(dates: week, isMonth: true)
                }
            }
        }
    }

    private func checkMatrixBlock(dates: [Date?], isMonth: Bool) -> some View {
        HStack(alignment: .top, spacing: 9) {
            VStack(alignment: .leading, spacing: isMonth ? 7 : 8) {
                Text("")
                    .frame(height: isMonth ? 17 : 18)
                ForEach(snapshot.checkGroupSummaries, id: \.title) { group in
                    Text(group.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(width: 42, height: isMonth ? 31 : 36, alignment: .leading)
                }
            }

            VStack(spacing: isMonth ? 7 : 8) {
                HStack(spacing: 5) {
                    ForEach(Array(dates.enumerated()), id: \.offset) { _, date in
                        VStack(spacing: 1) {
                            if let date {
                                Text(weekdaySingleTitle(date))
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(.secondary.opacity(0.66))
                                Text(dayNumberTitle(date))
                                    .font(.caption2.weight(calendar.isDateInToday(date) ? .bold : .medium))
                                    .foregroundStyle(calendar.isDateInToday(date) ? CreamTheme.green : .secondary)
                                    .monospacedDigit()
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: isMonth ? 17 : 18)
                    }
                }

                ForEach(snapshot.checkGroupSummaries, id: \.title) { group in
                    HStack(spacing: 5) {
                        ForEach(Array(dates.enumerated()), id: \.offset) { _, date in
                            CheckMatrixCell(
                                status: date.map { checkStatus(for: group, on: $0) },
                                isToday: date.map { calendar.isDateInToday($0) } ?? false
                            )
                            .frame(maxWidth: .infinity)
                            .frame(height: isMonth ? 31 : 36)
                        }
                    }
                }
            }
        }
    }

    private var timeDistributionCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            cardHeader(icon: "clock", title: L.timeDistCard, trailing: nil)

            VStack(spacing: 13) {
                if snapshot.timeSummaries.isEmpty {
                    emptyLine(L.emptyTimeHint)
                } else {
                    ForEach(snapshot.timeSummaries, id: \.category) { item in
                        TimeDistributionRow(
                            title: L.displayCategory(item.category),
                            duration: durationText(minutes: item.minutes),
                            ratio: CGFloat(item.minutes) / CGFloat(snapshot.maxTimeMinutes),
                            color: timeColor(for: item.category)
                        )
                    }
                }

                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.black.opacity(0.14))
                        .frame(width: 4, height: 4)
                    Text("\(L.unrecordedTime) \(durationText(minutes: snapshot.unrecordedTimeMinutes))")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Spacer()
                }
                .padding(.top, 1)
            }
        }
        .reviewCardStyle()
    }

    private func checkStatus(for group: ReviewCheckGroupSummary, on date: Date) -> CheckGroupStatus {
        snapshot.checkStatusByGroupAndDate[group.title]?[store.calendarDateKey(for: date)] ?? .empty
    }

    private func dates(from start: Date, to end: Date) -> [Date] {
        var result: [Date] = []
        var cursor = calendar.startOfDay(for: start)
        let exclusiveEnd = calendar.startOfDay(for: end)
        while cursor < exclusiveEnd {
            result.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result
    }

    private func leadingBlankDaysBeforeMonday(for date: Date) -> Int {
        let weekday = calendar.component(.weekday, from: date)
        return (weekday + 5) % 7
    }

    private var pendingIdeasCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 8) {
                    Image(systemName: "tray")
                        .foregroundStyle(CreamTheme.green)
                    Text(L.pendingIdeas)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                Spacer()
                Text("\(snapshot.pending) \(L.countItems)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary.opacity(0.45))
            }

            if snapshot.recentPendingIdeas.isEmpty {
                emptyLine(L.emptyPendingHint(periodLabel))
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(snapshot.recentPendingIdeas) { turn in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(CreamTheme.green.opacity(0.5))
                                .frame(width: 4, height: 4)
                            Text(TurnTypeStyle.displayText(for: turn))
                                .font(.caption)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                        }
                    }
                }
            }

            Text(L.goProcess)
                .font(.caption.weight(.semibold))
                .foregroundStyle(CreamTheme.green)
        }
        .reviewCardStyle()
    }

    private func cardHeader(icon: String, title: String, trailing: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(CreamTheme.green)
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func emptyLine(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary.opacity(0.85))
    }

    private func durationText(minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        if hours > 0 && mins > 0 { return "\(hours)h \(mins)m" }
        if hours > 0 { return "\(hours)h" }
        return "\(mins)m"
    }

    private func timeColor(for category: String) -> Color {
        // Keep in sync with TimeView's Notion Inked category palette.
        switch category {
        case "睡觉": return Color(red: 0.608, green: 0.494, blue: 0.647)
        case "工作": return Color(red: 0.357, green: 0.549, blue: 0.710)
        case "运动": return Color(red: 0.353, green: 0.620, blue: 0.435)
        case "学习": return Color(red: 0.749, green: 0.635, blue: 0.204)
        case "社交": return Color(red: 0.408, green: 0.447, blue: 0.671)
        case "娱乐": return Color(red: 0.753, green: 0.529, blue: 0.369)
        case "其他": return Color(red: 0.420, green: 0.659, blue: 0.627)
        default: return CreamTheme.green
        }
    }

    private var secondBrainCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "brain.head.profile")
                    .foregroundStyle(CreamTheme.green)
                Text(L.brainCard)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(snapshot.brainCount) \(L.countCards)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary.opacity(0.45))
            }

            if snapshot.brainPreview.isEmpty {
                emptyLine(L.emptyBrainHint)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(snapshot.brainPreview) { card in
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
        .reviewCardStyle()
    }

    private var periodTitle: String {
        switch window {
        case .week:
            return "\(shortDateTitle(snapshot.period.start))-\(shortDateTitle(calendar.date(byAdding: .day, value: -1, to: snapshot.period.end) ?? snapshot.period.start))"
        case .month:
            return monthTitle(snapshot.period.start)
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
        formatter.locale = Locale(identifier: L.localeId)
        formatter.dateFormat = "M/d"
        return formatter.string(from: date)
    }

    private func monthTitle(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: L.localeId)
        formatter.dateFormat = L.isEn ? "MMM yyyy" : "yyyy年M月"
        return formatter.string(from: date)
    }

    private func dayNumberTitle(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: L.localeId)
        formatter.dateFormat = "d"
        return formatter.string(from: date)
    }

    private func weekdaySingleTitle(_ date: Date) -> String {
        let symbols = L.weekSymbols
        let weekday = calendar.component(.weekday, from: date)
        return symbols[min(max(weekday - 1, 0), symbols.count - 1)]
    }

}

private struct CheckGroupStatus: Equatable {
    let completedCount: Int
    let totalCount: Int

    static let empty = CheckGroupStatus(completedCount: 0, totalCount: 0)

    var isFull: Bool { totalCount > 0 && completedCount == totalCount }
    var hasAny: Bool { completedCount > 0 }
}

private struct ReviewHubSnapshot {
    let period: (start: Date, end: Date)
    let pending: Int
    let checkGroupSummaries: [ReviewCheckGroupSummary]
    let checkWeekDates: [Date?]
    let checkMonthWeeks: [[Date?]]
    let checkStatusByGroupAndDate: [String: [String: CheckGroupStatus]]
    let timeSummaries: [ReviewTimeCategorySummary]
    let recordedTimeMinutes: Int
    let unrecordedTimeMinutes: Int
    let maxTimeMinutes: Int
    let recentPendingIdeas: [ConversationTurn]
    let brainCount: Int
    let brainPreview: [BrainCard]

    static var empty: ReviewHubSnapshot {
        let now = Date()
        return ReviewHubSnapshot(
            period: (now, now),
            pending: 0,
            checkGroupSummaries: [],
            checkWeekDates: [],
            checkMonthWeeks: [],
            checkStatusByGroupAndDate: [:],
            timeSummaries: [],
            recordedTimeMinutes: 0,
            unrecordedTimeMinutes: 0,
            maxTimeMinutes: 1,
            recentPendingIdeas: [],
            brainCount: 0,
            brainPreview: []
        )
    }
}

private struct CheckMatrixCell: View {
    let status: CheckGroupStatus?
    let isToday: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 11)
                .fill(fillColor)
            RoundedRectangle(cornerRadius: 11)
                .stroke(isToday ? CreamTheme.green.opacity(0.28) : strokeColor, lineWidth: isToday ? 1.4 : 1)

            if status?.isFull == true {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(CreamTheme.green)
            } else if status?.hasAny == true {
                Circle()
                    .fill(CreamTheme.green.opacity(0.58))
                    .frame(width: 5, height: 5)
            }
        }
    }

    private var fillColor: Color {
        guard let status else { return Color.clear }
        if status.isFull { return CreamTheme.green.opacity(0.045) }
        if status.hasAny { return CreamTheme.green.opacity(0.025) }
        return Color(red: 0.992, green: 0.992, blue: 0.970)
    }

    private var strokeColor: Color {
        guard let status else { return Color.clear }
        if status.isFull { return CreamTheme.green.opacity(0.28) }
        if status.hasAny { return CreamTheme.green.opacity(0.16) }
        return Color.black.opacity(0.055)
    }
}

private struct TimeDistributionRow: View {
    let title: String
    let duration: String
    let ratio: CGFloat
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Spacer(minLength: 12)

                Text(duration)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color.opacity(0.92))
                    .monospacedDigit()
                    .lineLimit(1)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.black.opacity(0.045))
                    Capsule()
                        .fill(color.opacity(0.58))
                        .frame(width: max(proxy.size.width * min(max(ratio, 0), 1), 10))
                }
            }
            .frame(height: 10)
        }
        .padding(.vertical, 2)
    }
}

private extension View {
    func reviewCardStyle() -> some View {
        self
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
