import SwiftUI
import UIKit
import WidgetKit

enum CheckWidgetLink {
    static let todayCheck = URL(string: "lifeos://today/check")!
}

struct CheckWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: CheckWidgetSnapshot
}

struct CheckWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> CheckWidgetEntry {
        CheckWidgetEntry(date: Date(), snapshot: previewSnapshot)
    }

    func getSnapshot(in context: Context, completion: @escaping (CheckWidgetEntry) -> Void) {
        completion(CheckWidgetEntry(date: Date(), snapshot: CheckWidgetSnapshotStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CheckWidgetEntry>) -> Void) {
        let entry = CheckWidgetEntry(date: Date(), snapshot: CheckWidgetSnapshotStore.load())
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date().addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
}

struct CheckWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CheckWidgetEntry

    var body: some View {
        content
            .widgetURL(CheckWidgetLink.todayCheck)
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .systemSmall:
            CheckWidgetSmallView(snapshot: entry.snapshot)
        default:
            CheckWidgetMediumView(snapshot: entry.snapshot)
        }
    }
}

struct CheckWidgetSmallView: View {
    let snapshot: CheckWidgetSnapshot

    var body: some View {
        DeskWidgetCard {
            VStack(alignment: .leading, spacing: 6) {
                DeskHeader(snapshot: snapshot)

                if snapshot.items.isEmpty {
                    EmptyCheckWidgetState()
                } else {
                    ForEach(Array(snapshot.displayItems.prefix(3))) { item in
                        DeskRow(item: item, showsTapCue: false)
                    }
                }

                Spacer(minLength: 0)
            }
        }
    }
}

struct CheckWidgetMediumView: View {
    let snapshot: CheckWidgetSnapshot

    var body: some View {
        DeskWidgetCard {
            VStack(alignment: .leading, spacing: 9) {
                DeskHeader(snapshot: snapshot)

                if snapshot.items.isEmpty {
                    EmptyCheckWidgetState()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                } else {
                    let groupedItems = mediumColumns
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(groupedItems, id: \.title) { group in
                            DeskGroup(title: group.title, items: group.items)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            if group.title != groupedItems.last?.title {
                                Rectangle()
                                    .fill(DeskCardPalette.rule)
                                    .frame(width: 1)
                                    .padding(.vertical, 2)
                            }
                        }
                    }
                }

                Spacer(minLength: 0)
            }
        }
    }

    private var groupedDisplayItems: [(title: String, items: [CheckWidgetItemSnapshot])] {
        let items = Array(snapshot.displayItems.prefix(6))
        var result: [(title: String, items: [CheckWidgetItemSnapshot])] = []
        for item in items {
            let title = item.tag.isEmpty ? "今天" : item.tag
            if let index = result.firstIndex(where: { $0.title == title }) {
                result[index].items.append(item)
            } else {
                result.append((title: title, items: [item]))
            }
        }
        return Array(result.prefix(2))
    }

    private var mediumColumns: [(title: String, items: [CheckWidgetItemSnapshot])] {
        let groups = groupedDisplayItems
        guard groups.count == 1, let group = groups.first, group.items.count > 3 else {
            return groups.map { group in
                (title: group.title, items: Array(group.items.prefix(3)))
            }
        }

        let items = Array(group.items.prefix(6))
        let splitIndex = min(3, items.count)
        return [
            (title: group.title, items: Array(items.prefix(splitIndex))),
            (title: "", items: Array(items.dropFirst(splitIndex)))
        ].filter { !$0.items.isEmpty }
    }
}

enum DeskCardPalette {
    static let card = Color(red: 0.992, green: 0.980, blue: 0.957)
    static let ink = Color(red: 0.110, green: 0.094, blue: 0.071)
    static let inkSoft = Color.black.opacity(0.55)
    static let inkFaint = Color.black.opacity(0.30)
    static let rule = Color.black.opacity(0.07)
    static let done = Color.black.opacity(0.38)
    static let accent = Color(red: 0.722, green: 0.443, blue: 0.290)
}

struct DeskWidgetCard<Content: View>: View {
    @Environment(\.widgetFamily) private var family
    @ViewBuilder let content: Content

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            content
                .padding(14)
                .padding(.trailing, catContentInset)

            WidgetCatImage()
                .frame(width: catWidth)
                .offset(x: catOffset.width, y: catOffset.height)
                .opacity(0.96)
                .unredacted()
                .accessibilityHidden(true)
                .allowsHitTesting(false)
                .zIndex(1)
        }
        .deskCardBackground()
    }

    private var catWidth: CGFloat {
        family == .systemSmall ? 54 : 104
    }

    private var catContentInset: CGFloat {
        family == .systemSmall ? 18 : 26
    }

    private var catOffset: CGSize {
        family == .systemSmall ? CGSize(width: 12, height: 6) : CGSize(width: 16, height: 9)
    }
}

struct WidgetCatImage: View {
    private let image: UIImage?

    init() {
        if let bundledURL = Bundle.main.url(forResource: "cat-lying-none", withExtension: "png"),
           let bundledImage = UIImage(contentsOfFile: bundledURL.path) {
            image = bundledImage
        } else {
            image = UIImage(named: "CatLyingNone", in: .main, compatibleWith: nil)
        }
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                EmptyView()
            }
        }
    }
}

extension View {
    @ViewBuilder
    func deskCardBackground() -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            self.containerBackground(for: .widget) {
                DeskCardPalette.card
            }
        } else {
            ZStack {
                DeskCardPalette.card
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                self
            }
        }
    }
}

struct DeskHeader: View {
    let snapshot: CheckWidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("今日打卡")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DeskCardPalette.ink)

                Spacer(minLength: 8)

                if !snapshot.items.isEmpty {
                    Text("\(snapshot.completedCount)/\(snapshot.items.count)")
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .tracking(0.5)
                        .foregroundStyle(DeskCardPalette.inkSoft)
                }
            }

            Rectangle()
                .fill(DeskCardPalette.rule)
                .frame(height: 1)
                .padding(.top, 9)
        }
    }
}

struct DeskGroup: View {
    let title: String
    let items: [CheckWidgetItemSnapshot]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Group {
                if title.isEmpty {
                    Text(" ")
                } else {
                    Text(title)
                }
            }
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .tracking(0.5)
            .foregroundStyle(DeskCardPalette.accent)
            .lineLimit(1)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(items) { item in
                    Link(destination: CheckWidgetLink.todayCheck) {
                        DeskRow(item: item, showsTapCue: true)
                    }
                }
            }
        }
    }
}

struct DeskRow: View {
    let item: CheckWidgetItemSnapshot
    let showsTapCue: Bool

    var body: some View {
        HStack(spacing: 9) {
            ZStack {
                if item.done {
                    Circle()
                        .fill(DeskCardPalette.ink)
                        .frame(width: 13, height: 13)
                    Circle()
                        .fill(DeskCardPalette.card)
                        .frame(width: 5, height: 5)
                } else {
                    Circle()
                        .stroke(DeskCardPalette.inkFaint, lineWidth: 1.2)
                        .frame(width: 13, height: 13)
                }
            }
            .frame(width: 13, height: 13)

            Text(item.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(item.done ? DeskCardPalette.done : DeskCardPalette.ink)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)

            if showsTapCue {
                Circle()
                    .fill(DeskCardPalette.accent.opacity(0.42))
                    .frame(width: 4, height: 4)
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }
}

struct EmptyCheckWidgetState: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Rectangle()
                .fill(DeskCardPalette.accent)
                .frame(width: 22, height: 2)
            Text("今天可以慢慢来")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DeskCardPalette.inkSoft)
                .lineLimit(2)
        }
        .padding(.top, 6)
    }
}

@main
struct CheckWidget: Widget {
    let kind = "CheckWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CheckWidgetProvider()) { entry in
            CheckWidgetView(entry: entry)
        }
        .configurationDisplayName("LifeOS 今日打卡")
        .description("在桌面轻轻看一眼今天的打卡。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private let previewSnapshot = CheckWidgetSnapshot(
    dateKey: "2026-05-17",
    updatedAt: Date(),
    items: [
        CheckWidgetItemSnapshot(title: "吃维生素", done: true, tag: "早上"),
        CheckWidgetItemSnapshot(title: "回忆梦境", done: false, tag: "早上"),
        CheckWidgetItemSnapshot(title: "写日记", done: false, tag: "晚上"),
        CheckWidgetItemSnapshot(title: "上床看书", done: false, tag: "晚上")
    ]
)
