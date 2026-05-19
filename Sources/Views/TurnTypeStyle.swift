import SwiftUI

/// 一组共享的 turn 视觉样式 helper，给随记 Tab / 复盘 Tab 等多个地方用。
/// 之前这些散在 QuickCaptureView 内部当 private 方法，PR 4 抽出来给 ReviewSessionView 复用。
enum TurnTypeStyle {

    /// SF Symbol 名 — 类型 chip 的图标
    static func icon(for type: String) -> String {
        switch type {
        case "想法": return "lightbulb.fill"
        case "todo": return "checkmark.circle.fill"
        case "感受": return "heart.fill"
        case "感恩": return "hands.sparkles.fill"
        case "做梦": return "moon.stars.fill"
        case "时间记录": return "clock.fill"
        default: return "tag.fill"
        }
    }

    /// 主色 — 用于类型 chip 文字、左侧色条等强调位（方案 B「绿主暖辅」）
    static func color(for type: String) -> Color {
        switch type {
        case "想法": return Color(red: 0.24, green: 0.65, blue: 0.36)   // #3DA55C 品牌绿
        case "todo": return Color(red: 0.353, green: 0.498, blue: 0.608) // #5A7F9B 雾蓝
        case "感受": return Color(red: 0.627, green: 0.502, blue: 0.361) // #A0805C 暖棕
        case "感恩": return Color(red: 0.490, green: 0.541, blue: 0.290) // #7D8A4A 橄榄
        case "做梦": return Color(red: 0.482, green: 0.451, blue: 0.580) // #7B7394 薰灰
        case "时间记录": return Color(red: 0.353, green: 0.498, blue: 0.608) // #5A7F9B 雾蓝
        default: return .secondary
        }
    }

    /// 浅色底 — 用于 chip 背景、感受词标签底色
    static func bgColor(for type: String) -> Color {
        switch type {
        case "想法": return Color(red: 0.918, green: 0.961, blue: 0.929) // #EAF5ED
        case "todo": return Color(red: 0.910, green: 0.937, blue: 0.961) // #E8EFF5
        case "感受": return Color(red: 0.961, green: 0.937, blue: 0.914) // #F5EFE9
        case "感恩": return Color(red: 0.949, green: 0.953, blue: 0.910) // #F2F3E8
        case "做梦": return Color(red: 0.933, green: 0.929, blue: 0.953) // #EEEDF3
        case "时间记录": return Color(red: 0.910, green: 0.937, blue: 0.961) // #E8EFF5
        default: return Color(red: 0.96, green: 0.96, blue: 0.96)
        }
    }

    static func displayTitle(for turn: ConversationTurn) -> String? {
        guard turn.targetBucket != "time" else { return nil }
        let title = turn.payload["title"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return title.isEmpty ? nil : title
    }

    /// 卡片正文文本：优先 payload.detail（AI 拆解后的精炼版本），回退 rawText
    static func displayText(for turn: ConversationTurn) -> String {
        if turn.targetBucket == "time" {
            if let note = turn.payload["note"], !note.isEmpty { return note }
            return turn.payload["name"] ?? turn.rawText
        }
        let detail = turn.payload["detail"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return detail.isEmpty ? turn.rawText : detail
    }
}
