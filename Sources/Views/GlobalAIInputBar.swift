import SwiftUI

private struct AIComposerMessage: Identifiable {
    let id = UUID()
    let label: String
    let text: String
    let isUser: Bool
}

/// 全局 AI 输入框 —— 类似 Notion 的浮动按钮
/// - 折叠态：右下角一个圆形 `+` 按钮，小猫趴在按钮左上方
/// - 展开态：底部完整输入条，带 ⚡ 快捷本地 & ↑ AI 拆解 两个按钮；小猫趴在输入条右上方
/// - 点击输入条外部空白区域可收起
/// - AI 解析结果由 AppStore.submitAIText 路由到 time / task / inbox 三种桶
struct GlobalAIInputBar: View {
    @EnvironmentObject var store: AppStore

    @State private var rawInput = ""
    @State private var isExpanded = false
    @FocusState private var inputFocused: Bool

    // 键盘是否弹起（用来隐藏折叠态 FAB，避免跟 tabbar / 其他输入框挤在一起）
    @State private var keyboardVisible = false

    // AI 首次使用同意弹窗
    @State private var showConsent = false
    @State private var pendingAIText: String? = nil
    @State private var submittedPromptPreview: String? = nil
    @State private var submittedSupplementPreview: String? = nil
    @State private var composerMessages: [AIComposerMessage] = []

    var body: some View {
        ZStack(alignment: .bottom) {
            // 展开态下点击外部空白区域收起
            if isExpanded {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        collapse()
                    }
                    .transition(.opacity)
            }

            VStack(alignment: .trailing, spacing: 8) {
                // 没有输入上下文时才使用独立提示条；有上下文时提示放在输入框底部。
                if isExpanded, submittedPromptPreview == nil, store.pendingClarification == nil, let msg = store.aiDebugMessage {
                    debugBanner(msg)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if isExpanded {
                    expandedBarWithMascot
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if !keyboardVisible {
                    // 其他页面聚焦输入时键盘弹起 —— FAB 让位，避免视觉重叠
                    fabWithMascot
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 12)
            // 键盘弹起时贴近键盘（6pt），否则让出系统 tabbar 高度（54pt）
            // ——关键是跟键盘状态走，别跟 isExpanded 走：展开但键盘没上来的一瞬间会盖住 tabbar
            .padding(.bottom, keyboardVisible ? 6 : 54)
            // 不在这里再挂隐式 animation —— expand()/collapse() 已用 withAnimation 驱动，
            // 双重动画会让 transition 与 padding 分两段出现（这就是之前看到的"卡顿二段感"）
            .animation(.easeInOut(duration: 0.18), value: store.aiDebugMessage)
            .animation(.easeInOut(duration: 0.18), value: store.pendingClarification?.hint)
            .animation(.easeInOut(duration: 0.18), value: submittedPromptPreview)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            withAnimation(.easeInOut(duration: 0.18)) { keyboardVisible = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeInOut(duration: 0.18)) { keyboardVisible = false }
        }
        .sheet(isPresented: $showConsent) {
            AIConsentSheet {
                // 用户同意后继续之前暂存的 AI 调用
                if let text = pendingAIText {
                    preparePreviewForAISubmission(text)
                    store.submitAIText(effectiveAIText(for: text))
                    rawInput = ""
                    pendingAIText = nil
                }
            }
        }
        .onChange(of: store.isAILoading) { isLoading in
            if !isLoading {
                clearAIPreviewAfterSuccessfulResolution()
            }
        }
        .onChange(of: store.pendingClarification?.hint) { hint in
            if hint == nil, !store.isAILoading, store.aiDebugMessage == nil {
                clearAIPreview()
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
                .padding(.top, 38)   // 给小猫留出位置

                // 坐姿小猫在按钮正上方（脸朝右，图片原始方向）
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
                .padding(.top, 30)   // 给小猫留位置

            // 趴姿小猫：cat-lying 保持原始朝向（脸朝右）
            // 往上抬几个像素，轻轻搭在输入框顶部
            MascotCatAssetView(stroke: CreamTheme.green, assetName: "cat-lying")
                .frame(width: 84, height: 42)
                .offset(x: -12, y: 1)
                .allowsHitTesting(false)
        }
    }

    private var expandedBar: some View {
        let hasText = !rawInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let isLoading = store.isAILoading
        let canSend = hasText && !isLoading
        let promptPreview = store.pendingClarification?.originalText ?? submittedPromptPreview
        let hint = store.pendingClarification?.hint
        let assistantMessage = hint ?? (promptPreview == nil ? nil : store.aiDebugMessage)
        let hasPendingContext = promptPreview != nil || assistantMessage != nil
        let placeholder = hasPendingContext
        ? "补充一句就好..."
        : "说点什么…（AI 自动归类到待办/时间/随记）"

        return VStack(alignment: .leading, spacing: 9) {
            ForEach(displayedComposerMessages(promptPreview: promptPreview)) { message in
                dialogueLine(label: message.label, text: message.text, isUser: message.isUser)
            }

            if let assistantMessage {
                dialogueLine(label: "猫", text: assistantMessage, isUser: false, canDismiss: true)
            } else if isLoading {
                dialogueLine(label: "猫", text: "正在识别...", isUser: false)
            }

            HStack(alignment: .center, spacing: 8) {
                HStack(alignment: .center, spacing: 6) {
                    // 收起按钮（左侧，更明显）
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
                            if canSend { submitAI() }
                        }

                    if isLoading {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.7)
                            .tint(CreamTheme.green)
                            .frame(width: 28, height: 28)
                    } else {
                        // ⚡ 快捷本地
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

                        // ↑ AI 拆解
                        Button {
                            submitAI()
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
        .padding(.top, promptPreview == nil ? 8 : 10)
        .padding(.bottom, 8)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.98))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(
                    isLoading || assistantMessage != nil ? CreamTheme.green.opacity(0.38) : Color.black.opacity(0.08),
                    lineWidth: isLoading || assistantMessage != nil ? 1.3 : 1
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
                    store.aiDebugMessage = nil
                    store.pendingClarification = nil
                    clearAIPreview()
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

    // MARK: - Debug banner（失败/澄清提示）
    private func debugBanner(_ msg: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(.orange)
            Text(msg)
                .font(.caption2)
                .foregroundStyle(.orange)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Spacer()
            Button {
                store.aiDebugMessage = nil
                store.pendingClarification = nil
                clearAIPreview()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundStyle(.orange.opacity(0.6))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Expand / Collapse
    private func expand() {
        // 同步触发：输入框状态与键盘弹起合并为一次动画，避免 150ms 延迟带来的卡顿二段感
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
    private func submitAI() {
        let text = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        // 首次使用前弹出同意书，暂存输入待同意后继续
        if !AIConsent.hasAccepted {
            pendingAIText = text
            showConsent = true
            return
        }
        preparePreviewForAISubmission(text)
        store.submitAIText(effectiveAIText(for: text))
        rawInput = ""
    }

    private func submitLocal() {
        let text = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        store.submitLocalOnly(text)
        store.pendingClarification = nil
        rawInput = ""
        clearAIPreview()
    }

    private func preparePreviewForAISubmission(_ text: String) {
        if let pending = store.pendingClarification {
            ensureConversationStarts(with: pending.originalText)
            appendComposerMessage(label: "猫", text: pending.hint, isUser: false)
            appendComposerMessage(label: "我", text: text, isUser: true)
            submittedPromptPreview = pending.originalText
            submittedSupplementPreview = nil
        } else if let original = submittedPromptPreview, let message = store.aiDebugMessage {
            ensureConversationStarts(with: original)
            appendComposerMessage(label: "猫", text: message, isUser: false)
            appendComposerMessage(label: "我", text: text, isUser: true)
            submittedSupplementPreview = nil
        } else {
            composerMessages = [
                AIComposerMessage(label: "我", text: text, isUser: true)
            ]
            submittedPromptPreview = text
            submittedSupplementPreview = nil
        }
    }

    private func clearAIPreview() {
        submittedPromptPreview = nil
        submittedSupplementPreview = nil
        composerMessages = []
    }

    private func clearAIPreviewAfterSuccessfulResolution() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            if !store.isAILoading,
               store.pendingClarification == nil,
               store.aiDebugMessage == nil {
                clearAIPreview()
            }
        }
    }

    private func displayedComposerMessages(promptPreview: String?) -> [AIComposerMessage] {
        if !composerMessages.isEmpty {
            return composerMessages
        }
        if let promptPreview {
            return [AIComposerMessage(label: "我", text: promptPreview, isUser: true)]
        }
        return []
    }

    private func ensureConversationStarts(with text: String) {
        if composerMessages.isEmpty {
            composerMessages = [
                AIComposerMessage(label: "我", text: text, isUser: true)
            ]
        }
    }

    private func appendComposerMessage(label: String, text: String, isUser: Bool) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if composerMessages.last?.text != trimmed {
            composerMessages.append(AIComposerMessage(label: label, text: trimmed, isUser: isUser))
        }
    }

    private func effectiveAIText(for text: String) -> String {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if store.pendingClarification != nil {
            return clean
        }
        if let original = submittedPromptPreview,
           store.aiDebugMessage != nil {
            return "\(original)\n补充：\(clean)"
        }
        return clean
    }
}
