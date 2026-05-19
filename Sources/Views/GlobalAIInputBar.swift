import SwiftUI

/// 全局 AI 输入框 —— 类似 Notion 的浮动按钮
/// - 折叠态：右下角一个圆形 `+` 按钮，小猫趴在按钮左上方
/// - 展开态：底部完整输入条，带 ⚡ 快捷本地 & ↑ AI 发送 两个按钮；小猫趴在输入条右上方
/// - 点击输入条外部空白区域可收起
/// - 所有 AI 输入统一走 Agent 聊天通道：猫自动判断是记录还是闲聊
struct GlobalAIInputBar: View {
    static let openComposerNotification = Notification.Name("LifeOSOpenGlobalAIComposer")

    @EnvironmentObject var store: AppStore

    @State private var rawInput = ""
    @State private var isExpanded = false
    @FocusState private var inputFocused: Bool

    @State private var keyboardVisible = false

    // AI 首次使用同意弹窗
    @State private var showConsent = false
    @State private var pendingAIText: String? = nil

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(alignment: .trailing, spacing: 8) {
                if isExpanded {
                    expandedBarWithMascot
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if !keyboardVisible {
                    fabWithMascot
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, keyboardVisible ? 6 : 54)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            withAnimation(.easeInOut(duration: 0.18)) { keyboardVisible = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeInOut(duration: 0.18)) { keyboardVisible = false }
        }
        .onReceive(NotificationCenter.default.publisher(for: Self.openComposerNotification)) { notification in
            if let prompt = notification.object as? String, !prompt.isEmpty, rawInput.isEmpty {
                rawInput = prompt
            }
            expand()
        }
        .sheet(isPresented: $showConsent) {
            AIConsentSheet {
                if let text = pendingAIText {
                    store.submitAgentText(text)
                    rawInput = ""
                    pendingAIText = nil
                }
            }
        }
    }

    // MARK: - FAB (折叠态) + 小猫（坐姿 mascot-cat，脸朝左）
    private var fabWithMascot: some View {
        HStack {
            Spacer()
            ZStack(alignment: .topTrailing) {
                Button {
                    expand()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(
                            Circle().fill(CreamTheme.green)
                        )
                        .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 4)
                }
                .buttonStyle(.plain)
                .padding(.top, 38)

                MascotCatAssetView(stroke: CreamTheme.green, assetName: "mascot-cat")
                    .frame(width: 58, height: 52)
                    .offset(x: 0, y: -2)
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Expanded Bar (展开态) + 趴姿小猫（cat-lying，脸朝左）
    private var expandedBarWithMascot: some View {
        ZStack(alignment: .topTrailing) {
            expandedBar
                .padding(.top, 30)

            MascotCatAssetView(stroke: CreamTheme.green, assetName: "cat-lying")
                .frame(width: 84, height: 42)
                .offset(x: -12, y: 1)
                .allowsHitTesting(false)
        }
    }

    private var expandedBar: some View {
        let hasText = !rawInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let isLoading = store.isAgentLoading
        let canSend = hasText && !isLoading
        let placeholder = "和猫说点什么…记录或闲聊都可以"

        return VStack(alignment: .leading, spacing: 9) {
            // 顶部工具栏：清空对话按钮
            HStack(spacing: 6) {
                Spacer()
                if !store.agentSession.messages.isEmpty {
                    Button {
                        store.clearAgentChat()
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                }
            }

            agentConversationPreview
            if store.isAgentLoading {
                dialogueLine(label: "猫", text: "我在想怎么接这句话...", isUser: false)
            }
            if let msg = store.agentErrorMessage {
                dialogueLine(label: "猫", text: msg, isUser: false, canDismiss: true)
            }
            agentActionCards

            HStack(alignment: .center, spacing: 8) {
                HStack(alignment: .center, spacing: 6) {
                    Button {
                        collapse()
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(CreamTheme.green)
                            .frame(width: 28, height: 28)
                            .background(
                                Circle().fill(CreamTheme.green.opacity(0.12))
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(isLoading)

                    TextField(placeholder, text: $rawInput, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.body)
                        .lineLimit(1...4)
                        .submitLabel(.send)
                        .focused($inputFocused)
                        .disabled(isLoading)
                        .frame(minHeight: 28, alignment: .center)
                        .onSubmit {
                            if canSend { submitAgent() }
                        }

                    if isLoading {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.7)
                            .tint(CreamTheme.green)
                            .frame(width: 28, height: 28)
                    } else {
                        // ⚡ 快捷本地（不走网络，直接本地关键词入库）
                        Button {
                            submitLocal()
                        } label: {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(hasText ? Color(red: 0.85, green: 0.65, blue: 0.25) : .secondary.opacity(0.4))
                                .frame(width: 28, height: 28)
                                .background(
                                    Circle().fill(
                                        hasText
                                        ? Color(red: 0.99, green: 0.93, blue: 0.80)
                                        : Color.gray.opacity(0.12)
                                    )
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(!hasText)

                        // ↑ AI 发送
                        Button {
                            submitAgent()
                        } label: {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 28, height: 28)
                                .background(
                                    Circle().fill(canSend ? CreamTheme.green : Color.gray.opacity(0.3))
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(!canSend)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.98))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(
                    isLoading ? CreamTheme.green.opacity(0.38) : Color.black.opacity(0.08),
                    lineWidth: isLoading ? 1.3 : 1
                )
        )
        .shadow(color: .black.opacity(0.14), radius: 16, x: 0, y: 6)
    }

    private func dialogueLine(label: String, text: String, isUser: Bool, canDismiss: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(isUser ? CreamTheme.green : .primary.opacity(0.46))
                .frame(width: 34, alignment: .leading)
            Text(text)
                .font(.caption)
                .foregroundStyle(Color.primary.opacity(isUser ? 0.78 : 0.62))
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            if canDismiss {
                Button {
                    store.agentErrorMessage = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.primary.opacity(0.32))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, 2)
    }

    private var agentConversationPreview: some View {
        let messages = store.agentSession.messages.suffix(4)
        return VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(messages)) { message in
                dialogueLine(
                    label: message.role == "user" ? "我" : "猫",
                    text: message.content,
                    isUser: message.role == "user"
                )
            }
        }
    }

    private var agentActionCards: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(store.agentSession.pendingActions) { action in
                agentActionCard(action)
            }
        }
    }

    private func agentActionCard(_ action: AgentActionDraft) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(actionLabel(for: action.kind), systemImage: actionIcon(for: action.kind))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CreamTheme.green)
                Spacer()
                Button {
                    store.dismissAgentAction(id: action.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            Text(action.title.isEmpty ? action.detail : action.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary.opacity(0.82))
                .lineLimit(2)
            if !action.detail.isEmpty, action.detail != action.title {
                Text(action.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Button {
                if let err = store.confirmAgentAction(id: action.id) {
                    store.agentErrorMessage = err
                }
            } label: {
                Label("保存", systemImage: "checkmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(CreamTheme.green))
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(CreamTheme.green.opacity(0.08))
        )
    }

    private func actionLabel(for kind: AgentActionKind) -> String {
        switch kind {
        case .inbox: return "建议存随手记"
        case .task: return "建议存待办"
        case .time: return "建议存时间"
        }
    }

    private func actionIcon(for kind: AgentActionKind) -> String {
        switch kind {
        case .inbox: return "square.and.pencil"
        case .task: return "checklist"
        case .time: return "clock"
        }
    }

    // MARK: - Expand / Collapse
    private func expand() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            isExpanded = true
        }
        inputFocused = true
    }

    private func collapse() {
        inputFocused = false
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            isExpanded = false
        }
    }

    // MARK: - Submit actions

    private func submitAgent() {
        let text = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if !AIConsent.hasAccepted {
            pendingAIText = text
            showConsent = true
            return
        }
        store.submitAgentText(text)
        rawInput = ""
    }

    private func submitLocal() {
        let text = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        store.submitLocalOnly(text)
        rawInput = ""
    }
}
