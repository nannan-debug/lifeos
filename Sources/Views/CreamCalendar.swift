import SwiftUI

/// 统一日历弹窗组件 — 三个页面共用
/// 周日起始，支持自定义日期标记
struct CreamCalendarOverlay: View {
    @Binding var selectedDate: Date
    @Binding var displayMonth: Date
    @Binding var isPresented: Bool
    var markerForDate: (Date) -> CreamCalendarMarker

    private let calendar = Calendar.current
    private let weekSymbols = ["日", "一", "二", "三", "四", "五", "六"]

    var body: some View {
        ZStack(alignment: .top) {
            // 遮罩
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .onTapGesture {
                    isPresented = false
                }

            // 日历卡片
            calendarCard
                .padding(.horizontal, 16)
                .padding(.top, 8)
        }
    }

    private var calendarCard: some View {
        VStack(spacing: 0) {
            // 月份导航
            HStack {
                Button { withAnimation(.easeInOut(duration: 0.2)) { changeMonth(by: -1) } } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                }

                Spacer()

                Text(monthTitle(displayMonth))
                    .font(.subheadline.weight(.bold))

                Spacer()

                Button { withAnimation(.easeInOut(duration: 0.2)) { changeMonth(by: 1) } } label: {
                    Image(systemName: "chevron.right")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 4)
            .padding(.bottom, 10)

            // 星期头（周日起始）
            HStack(spacing: 0) {
                ForEach(weekSymbols, id: \.self) { w in
                    Text(w)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 6)

            // 日期网格
            let cells = monthCells(for: displayMonth)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(Array(cells.enumerated()), id: \.offset) { _, date in
                    if let day = date {
                        dayCellView(day)
                    } else {
                        Color.clear.frame(height: 44)
                    }
                }
            }
        }
        .padding(16)
        // 用不透明底色代替 .regularMaterial，避免材质在动画中反复合成引起的掉帧
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(red: 0.98, green: 0.98, blue: 0.98))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.black.opacity(0.06), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.12), radius: 24, x: 0, y: 10)
        .compositingGroup() // 让整个卡片作为单层合成，动画只需 blend 一次
    }

    @ViewBuilder
    private func dayCellView(_ day: Date) -> some View {
        let isSelected = calendar.isDate(day, inSameDayAs: selectedDate)
        let isToday = calendar.isDateInToday(day)
        let marker = markerForDate(day)

        Button {
            selectedDate = day
            isPresented = false
        } label: {
            VStack(spacing: 3) {
                Text("\(calendar.component(.day, from: day))")
                    .font(.system(size: 15, weight: isSelected ? .bold : .regular, design: .rounded))
                    .foregroundStyle(dayTextColor(isSelected: isSelected, isToday: isToday))

                markerView(marker, isSelected: isSelected)
                    .frame(height: 8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(dayBackground(isSelected: isSelected, isToday: isToday))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private func dayTextColor(isSelected: Bool, isToday: Bool) -> Color {
        if isSelected { return .white }
        if isToday { return CreamTheme.green }
        return .primary
    }

    @ViewBuilder
    private func dayBackground(isSelected: Bool, isToday: Bool) -> some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 10).fill(CreamTheme.green)
        } else if isToday {
            RoundedRectangle(cornerRadius: 10).fill(CreamTheme.green.opacity(0.08))
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private func markerView(_ marker: CreamCalendarMarker, isSelected: Bool) -> some View {
        switch marker {
        case .none:
            Color.clear.frame(width: 6, height: 6)

        case .dot(let color):
            Circle()
                .fill(isSelected ? .white.opacity(0.8) : color)
                .frame(width: 6, height: 6)

        case .multiDot(let colors):
            HStack(spacing: 2) {
                ForEach(Array(colors.prefix(3).enumerated()), id: \.offset) { _, c in
                    Circle()
                        .fill(isSelected ? .white.opacity(0.8) : c)
                        .frame(width: 5, height: 5)
                }
            }

        case .ring(let colors):
            if colors.count == 1 {
                Circle()
                    .stroke(isSelected ? .white.opacity(0.7) : colors[0], lineWidth: 2)
                    .frame(width: 8, height: 8)
            } else {
                let gc = colors + [colors[0]]
                Circle()
                    .stroke(
                        AngularGradient(colors: isSelected ? [.white.opacity(0.7)] : gc, center: .center),
                        lineWidth: 2
                    )
                    .frame(width: 8, height: 8)
            }
        }
    }

    // MARK: - Helpers

    private func changeMonth(by value: Int) {
        displayMonth = calendar.date(byAdding: .month, value: value, to: displayMonth) ?? displayMonth
    }

    private func monthTitle(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月"
        return f.string(from: date)
    }

    private func startOfMonth(for date: Date) -> Date {
        let comps = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: comps) ?? date
    }

    /// 周日起始的月份日期格子
    private func monthCells(for month: Date) -> [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: month) else { return [] }
        let start = startOfMonth(for: month)
        let firstWeekday = calendar.component(.weekday, from: start) // 1=Sun
        var cells: [Date?] = Array(repeating: nil, count: max(0, firstWeekday - 1))
        for day in range {
            if let d = calendar.date(byAdding: .day, value: day - 1, to: start) {
                cells.append(d)
            }
        }
        while cells.count % 7 != 0 {
            cells.append(nil)
        }
        return cells
    }
}

/// 日期标记类型
enum CreamCalendarMarker {
    case none
    case dot(Color)
    case multiDot([Color])
    case ring([Color])
}
