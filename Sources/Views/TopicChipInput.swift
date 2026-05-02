import SwiftUI

/// 第二大脑卡片的 topics 输入器：输入框 + chip 横向显示 + 老 topic 模糊补全。
/// 输入"命"时弹出 #命名 候选；按回车或点候选 chip 添加。
struct TopicChipInput: View {
    @Binding var topics: [String]
    @Binding var aiSuggestions: [String]?
    /// 既有 topic 池：用来做模糊补全。一般传 store 里所有 BrainCard 已用过的 topic 去重列表。
    let availableTopics: [String]
    let aiLoading: Bool

    @State private var draft: String = ""
    @FocusState private var focused: Bool

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 模糊匹配：包含 draft 的老 topic，去掉已选中的，最多 5 条
    private var suggestions: [String] {
        guard !trimmedDraft.isEmpty else { return [] }
        let lower = trimmedDraft.lowercased()
        return availableTopics
            .filter { !topics.contains($0) && $0.lowercased().contains(lower) && $0.lowercased() != lower }
            .prefix(5)
            .map { $0 }
    }

    private var visibleAISuggestions: [String] {
        (aiSuggestions ?? [])
            .filter { suggestion in
                !topics.contains(normalized(suggestion))
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 已选 chip 横向 wrap
            if !topics.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(topics, id: \.self) { topic in
                        chip(topic)
                    }
                }
            }

            TextField("加主题（回车添加）", text: $draft)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .focused($focused)
                .submitLabel(.done)
                .onSubmit { addDraft() }

            if aiLoading {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.75)
                    Text("AI 正在看主题")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if !visibleAISuggestions.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(visibleAISuggestions, id: \.self) { suggestion in
                        aiChip(suggestion)
                    }
                }
            }

            if !suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(suggestions, id: \.self) { s in
                            Button {
                                add(s)
                            } label: {
                                Text(formatted(s))
                                    .font(.caption)
                                    .foregroundStyle(CreamTheme.green)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(CreamTheme.green.opacity(0.1))
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func chip(_ topic: String) -> some View {
        HStack(spacing: 4) {
            Text(formatted(topic))
                .font(.caption.weight(.medium))
            Button {
                topics.removeAll { $0 == topic }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption2)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .foregroundStyle(CreamTheme.green)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(CreamTheme.green.opacity(0.12))
        .clipShape(Capsule())
    }

    private func aiChip(_ topic: String) -> some View {
        HStack(spacing: 4) {
            Button {
                add(topic)
                aiSuggestions?.removeAll { normalized($0) == normalized(topic) }
            } label: {
                Text(formatted(topic))
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.plain)

            Button {
                aiSuggestions?.removeAll { normalized($0) == normalized(topic) }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption2)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .foregroundStyle(CreamTheme.green)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(CreamTheme.green.opacity(0.08))
        .overlay(
            Capsule()
                .stroke(CreamTheme.green.opacity(0.18), lineWidth: 1)
        )
        .clipShape(Capsule())
    }

    /// 显示用：保证以 "#" 开头
    private func formatted(_ raw: String) -> String {
        raw.hasPrefix("#") ? raw : "#\(raw)"
    }

    private func addDraft() {
        let value = trimmedDraft
        guard !value.isEmpty else { return }
        add(value)
    }

    private func add(_ raw: String) {
        // 归一存储：保证以 # 开头
        let value = normalized(raw)
        if !topics.contains(value) {
            topics.append(value)
        }
        draft = ""
    }

    private func normalized(_ raw: String) -> String {
        raw.hasPrefix("#") ? raw : "#\(raw)"
    }
}

// MARK: - FlowLayout（chip wrap 用，iOS 16+ 自带 Layout 协议）

private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowH: CGFloat = 0
        var totalH: CGFloat = 0

        for sub in subviews {
            let sz = sub.sizeThatFits(.unspecified)
            if x + sz.width > maxW && x > 0 {
                totalH += rowH + spacing
                x = 0
                rowH = 0
            }
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
        totalH += rowH
        y = totalH
        return CGSize(width: maxW == .infinity ? x : maxW, height: y)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowH: CGFloat = 0
        let maxX = bounds.maxX

        for sub in subviews {
            let sz = sub.sizeThatFits(.unspecified)
            if x + sz.width > maxX && x > bounds.minX {
                x = bounds.minX
                y += rowH + spacing
                rowH = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
    }
}
