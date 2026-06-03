import SwiftUI
import UIKit

struct GlobalAIInputBar: View {
    static let openComposerNotification = Notification.Name("LifeOSOpenGlobalAIComposer")

    @EnvironmentObject var store: AppStore
    @State private var showPanel = false
    @State private var pendingPrefill = ""
    @State private var keyboardVisible = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if !keyboardVisible {
                fabWithMascot
                    .padding(.horizontal, 12)
                    .padding(.bottom, 54)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            withAnimation(.easeInOut(duration: 0.18)) { keyboardVisible = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeInOut(duration: 0.18)) { keyboardVisible = false }
        }
        .onReceive(NotificationCenter.default.publisher(for: Self.openComposerNotification)) { notification in
            pendingPrefill = notification.object as? String ?? ""
            showPanel = true
        }
        .fullScreenCover(isPresented: $showPanel) {
            AgentChatPanel(prefill: pendingPrefill) {
                store.prepareAgentPanelClose()
                showPanel = false
                pendingPrefill = ""
            }
            .environmentObject(store)
            .presentationBackground(.clear)
        }
    }

    private var fabWithMascot: some View {
        ZStack(alignment: .topTrailing) {
            Button {
                showPanel = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(CreamTheme.green))
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

private struct AgentChatPanel: View {
    @EnvironmentObject var store: AppStore
    @FocusState private var inputFocused: Bool

    let prefill: String
    let onClose: () -> Void

    @State private var rawInput = ""
    private let chatMode = true
    @State private var showConsent = false
    @State private var pendingAIText: String?
    @State private var showHistory = false
    @State private var searchText = ""
    @State private var pendingDelete: AgentChatThreadIndexItem?
    @State private var renamingThread: AgentChatThreadIndexItem?
    @State private var renameDraft = ""
    @State private var recentlyDeletedThread: AgentChatThread?
    @State private var verticalDragOffset: CGFloat = 0
    @State private var copiedMessageID: UUID?
    @State private var historyDragOffset: CGFloat = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.10)
                .ignoresSafeArea()
                .onTapGesture {
                    if showHistory {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.88)) {
                            showHistory = false
                        }
                    }
                }

            VStack(spacing: 0) {
                Spacer(minLength: 54)

                ZStack {
                    panelBackground

                    VStack(spacing: 0) {
                        header
                        conversationArea
                        inputDock
                    }

                    if showHistory {
                        historyOverlay
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }
                }
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 38, topTrailingRadius: 38))
                .shadow(color: .black.opacity(0.12), radius: 24, x: 0, y: -4)
                .offset(y: max(0, verticalDragOffset))
            }
            .ignoresSafeArea(.container, edges: .bottom)
        }
        .onAppear {
            if prefill == "__nudge__" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    store.submitNudge()
                }
            } else if !prefill.isEmpty, rawInput.isEmpty {
                rawInput = prefill
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                inputFocused = true
            }
        }
        .sheet(isPresented: $showConsent) {
            AIConsentSheet {
                if let text = pendingAIText {
                    submitAI(text)
                    pendingAIText = nil
                }
            }
        }
        .alert(L.deleteConversation, isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )) {
            Button(L.cancel, role: .cancel) {
                pendingDelete = nil
            }
            Button(L.delete, role: .destructive) {
                if let item = pendingDelete {
                    recentlyDeletedThread = store.deleteAgentThread(id: item.id)
                }
                pendingDelete = nil
            }
        } message: {
            Text(L.deleteConversationHint)
        }
        .alert(L.renameConversation, isPresented: Binding(
            get: { renamingThread != nil },
            set: {
                if !$0 {
                    renamingThread = nil
                    renameDraft = ""
                }
            }
        )) {
            TextField(L.conversationNamePlaceholder, text: $renameDraft)
            Button(L.cancel, role: .cancel) {
                renamingThread = nil
                renameDraft = ""
            }
            Button(L.save) {
                commitThreadRename()
            }
            .disabled(renameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text(L.renameConversationHint)
        }
    }

    private var panelBackground: some View {
        LinearGradient(
            colors: [
                Color(red: 0.99, green: 0.99, blue: 0.97),
                .white,
                Color(red: 0.94, green: 0.97, blue: 0.94)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var header: some View {
        VStack(spacing: 8) {
            Capsule()
                .fill(CreamTheme.text.opacity(0.16))
                .frame(width: 38, height: 4)
                .padding(.top, 10)

            HStack {
                iconButton("clock.arrow.circlepath") {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                        showHistory = true
                    }
                }

                Spacer()

                Text(displayTitle)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(CreamTheme.text)
                    .lineLimit(1)
                    .frame(maxWidth: 210)

                Spacer()

                iconButton("square.and.pencil") {
                    store.createNewAgentThread()
                    inputFocused = true
                }
            }
            .padding(.horizontal, 24)

            if let dbt = store.activeDBTSession {
                dbtCoachBanner(dbt)
                    .padding(.horizontal, 24)
            }
        }
        .padding(.bottom, 8)
        .contentShape(Rectangle())
        .highPriorityGesture(panelDismissDrag)
    }

    private var displayTitle: String {
        if store.activeDBTSession != nil { return "DBT Coach" }
        return store.agentSession.messages.isEmpty ? "LifeOS AI" : store.currentAgentThreadTitle
    }

    private func dbtCoachBanner(_ session: AgentDBTSessionState) -> some View {
        HStack(spacing: 8) {
            Label(dbtSkillTitle(session.skillId), systemImage: "leaf")
                .font(.caption.weight(.semibold))
                .foregroundStyle(CreamTheme.green)
            Text("Step \(max(session.currentStepIndex + 1, 1))")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.black.opacity(0.045)))
            Spacer()
            Button("退出") {
                store.cancelDBTSession()
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(CreamTheme.green.opacity(0.08))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(CreamTheme.green.opacity(0.16), lineWidth: 1))
        )
    }

    private func dbtSkillTitle(_ id: String) -> String {
        switch id {
        case "check_the_facts": return "Check the Facts"
        case "opposite_action": return "Opposite Action"
        case "wise_mind": return "Wise Mind"
        case "tipp": return "TIPP"
        case "stop": return "STOP"
        case "dear_man": return "DEAR MAN"
        case "behavior_chain_analysis": return "Behavior Chain"
        default: return "DBT Practice"
        }
    }

    private var conversationArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if store.agentSession.messages.isEmpty && store.agentSession.pendingActions.isEmpty {
                        emptyState
                            .padding(.top, 36)
                    } else {
                        ForEach(Array(store.agentSession.messages.enumerated()), id: \.element.id) { index, message in
                            messageRow(message, at: index)
                                .id(message.id)
                        }
                        if store.isAgentLoading || store.streamingPhase != .idle {
                            streamingOrThinkingRow
                                .id("streaming-row")
                        }
                        if let msg = store.agentErrorMessage {
                            systemNotice(msg)
                        }
                        if let memStatus = store.agentMemoryStatus {
                            systemNotice(memStatus, icon: "brain.head.profile")
                        }
                        actionCards
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 136)
            }
            .onChange(of: store.agentSession.messages.count) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: store.agentSession.pendingActions.count) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: store.streamingContent) { _, _ in
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo("streaming-row", anchor: .bottom)
                }
            }
            .simultaneousGesture(contentDismissKeyboardDrag)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            ZStack(alignment: .top) {
                Circle()
                    .fill(.white.opacity(0.9))
                    .frame(width: 108, height: 108)
                    .shadow(color: .black.opacity(0.07), radius: 22, x: 0, y: 9)
                MascotCatAssetView(stroke: CreamTheme.green, assetName: "cat-lying")
                    .frame(width: 82, height: 41)
                    .offset(y: -20)
                Text("LifeOS AI")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(CreamTheme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.86)
                    .frame(width: 108, height: 108, alignment: .center)
                    .offset(y: 6)
            }
            Text(L.aiEmptyHint)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func messageRow(_ message: AgentChatMessage, at index: Int) -> some View {
        HStack(alignment: .top) {
            if message.role == "user" {
                Spacer(minLength: 46)
                VStack(alignment: .trailing, spacing: 6) {
                    Text(message.content)
                        .font(.callout)
                        .foregroundStyle(CreamTheme.text)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 22)
                                .fill(Color.black.opacity(0.045))
                        )
                    messageActionBar(message, alignment: .trailing, includeFeedback: false)
                }
                .frame(maxWidth: 285, alignment: .trailing)
            } else if message.autoSavedAction != nil {
                VStack(alignment: .leading, spacing: 6) {
                    autoSavedRow(message)
                    if isLastAssistantMessageInRun(at: index) {
                        assistantRunActionBar(endingAt: index, alignedWith: message)
                    }
                }
            } else if isActionResultMessage(message) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(message.content)
                        .font(.callout)
                        .foregroundStyle(CreamTheme.text.opacity(0.82))
                    if isLastAssistantMessageInRun(at: index) {
                        assistantRunActionBar(endingAt: index, alignedWith: message)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    if let reasoning = message.reasoningContent, !reasoning.isEmpty {
                        persistedReasoningSection(
                            content: reasoning,
                            timeMs: message.reasoningTimeMs
                        )
                    }
                    Text(markdownAttributed(message.content))
                        .font(.callout)
                        .lineSpacing(4)
                        .foregroundStyle(CreamTheme.text.opacity(0.9))
                    if isLastAssistantMessageInRun(at: index) {
                        assistantRunActionBar(endingAt: index, alignedWith: message)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 26)
            }
        }
    }

    private func isLastAssistantMessageInRun(at index: Int) -> Bool {
        let messages = store.agentSession.messages
        guard messages.indices.contains(index), messages[index].role != "user" else { return false }
        let next = index + 1
        return !messages.indices.contains(next) || messages[next].role == "user"
    }

    private func assistantRunFeedbackTarget(endingAt index: Int) -> AgentChatMessage? {
        let messages = store.agentSession.messages
        guard messages.indices.contains(index) else { return nil }
        var cursor = index
        while messages.indices.contains(cursor), messages[cursor].role != "user" {
            let candidate = messages[cursor]
            if candidate.autoSavedAction == nil, !isActionResultMessage(candidate) {
                return candidate
            }
            guard cursor > messages.startIndex else { break }
            cursor -= 1
        }
        return nil
    }

    private func assistantRunCopyText(endingAt index: Int) -> String {
        let messages = store.agentSession.messages
        guard messages.indices.contains(index) else { return "" }
        var pieces: [String] = []
        var cursor = index
        while messages.indices.contains(cursor), messages[cursor].role != "user" {
            let content = messages[cursor].content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !content.isEmpty {
                pieces.append(content)
            }
            guard cursor > messages.startIndex else { break }
            cursor -= 1
        }
        return pieces.reversed().joined(separator: "\n\n")
    }

    @ViewBuilder
    private func assistantRunActionBar(endingAt index: Int, alignedWith message: AgentChatMessage) -> some View {
        let feedbackTarget = assistantRunFeedbackTarget(endingAt: index)
        messageActionBar(
            message,
            alignment: .leading,
            includeFeedback: feedbackTarget.map { !$0.isError } ?? false,
            copyText: assistantRunCopyText(endingAt: index),
            feedbackTarget: feedbackTarget
        )
    }

    private func isActionResultMessage(_ message: AgentChatMessage) -> Bool {
        guard message.role == "assistant" else { return false }
        if message.isActionResult == true { return true }
        return [
            "已创建", "已更新", "已删除", "已完成",
            "Created ", "Updated ", "Deleted ", "Completed "
        ].contains { message.content.hasPrefix($0) }
    }

    @ViewBuilder
    private func messageActionBar(
        _ message: AgentChatMessage,
        alignment: Alignment,
        includeFeedback: Bool,
        copyText: String? = nil,
        feedbackTarget: AgentChatMessage? = nil
    ) -> some View {
        HStack(spacing: 6) {
            Text(timeText(message.createdAt))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .monospacedDigit()

            Button {
                copyMessage(message, text: copyText)
            } label: {
                Image(systemName: copiedMessageID == message.id ? "checkmark" : "doc.on.doc")
                    .font(.caption2.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(copiedMessageID == message.id ? CreamTheme.green : .secondary)
            .accessibilityLabel(copiedMessageID == message.id ? L.copied : L.copyMessage)

            if includeFeedback {
                let target = feedbackTarget ?? message
                feedbackButton(target, value: "liked", icon: "hand.thumbsup")
                feedbackButton(target, value: "disliked", icon: "hand.thumbsdown")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.58))
                .overlay(Capsule().strokeBorder(Color.black.opacity(0.04), lineWidth: 0.5))
        )
        .frame(maxWidth: .infinity, alignment: alignment)
    }

    private func feedbackButton(_ message: AgentChatMessage, value: String, icon: String) -> some View {
        let selected = message.feedback == value
        return Button {
            store.setAgentMessageFeedback(
                messageId: message.id,
                feedback: selected ? nil : value
            )
        } label: {
            Image(systemName: selected ? "\(icon).fill" : icon)
                .font(.caption2.weight(.semibold))
        }
        .buttonStyle(.plain)
        .foregroundStyle(selected ? CreamTheme.green : .secondary)
        .accessibilityLabel(value == "liked" ? L.likeMessage : L.dislikeMessage)
    }

    private func copyMessage(_ message: AgentChatMessage, text: String? = nil) {
        UIPasteboard.general.string = text ?? message.content
        withAnimation(.easeOut(duration: 0.12)) {
            copiedMessageID = message.id
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            if copiedMessageID == message.id {
                withAnimation(.easeOut(duration: 0.12)) {
                    copiedMessageID = nil
                }
            }
        }
    }

    private func timeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: L.localeId)
        formatter.dateFormat = L.isEn ? "h:mm a" : "HH:mm"
        return formatter.string(from: date)
    }

    private func markdownAttributed(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }

    private func autoSavedRow(_ message: AgentChatMessage) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(CreamTheme.green)
                .font(.system(size: 16))
            Text(message.content)
                .font(.callout)
                .foregroundStyle(CreamTheme.text.opacity(0.9))
            Spacer()
            if let ref = message.autoSavedAction, !ref.kind.isMutation, ref.kind != .calendarEvent {
                Button {
                    navigateToRecord(ref)
                } label: {
                    Text(L.view)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(CreamTheme.green)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().strokeBorder(CreamTheme.green.opacity(0.4), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            Button {
                store.undoAutoSavedAgentAction(messageId: message.id)
            } label: {
                Text(L.undo)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(CreamTheme.green.opacity(0.08))
        )
    }

    private func navigateToRecord(_ ref: AutoSavedActionRef) {
        onClose()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            switch ref.kind {
            case .inbox:
                store.pendingNavigation = .capture
            case .task:
                store.pendingNavigation = .todo
            case .time:
                store.pendingNavigation = .time(dateKey: nil)
            default:
                break
            }
        }
    }

    private var queuedMessagesBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(store.agentMessageQueue) { queued in
                HStack(spacing: 8) {
                    Image(systemName: "clock")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(queued.text)
                        .font(.caption)
                        .foregroundStyle(CreamTheme.text.opacity(0.7))
                        .lineLimit(1)
                    Spacer()
                    Button {
                        store.removeQueuedAgentMessage(id: queued.id)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.orange.opacity(0.08))
                )
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Streaming / Thinking UI

    @ViewBuilder
    private var streamingOrThinkingRow: some View {
        let phase = store.streamingPhase
        switch phase {
        case .reasoning:
            streamingReasoningRow
        case .content, .done:
            VStack(alignment: .leading, spacing: 8) {
                // Collapsed reasoning summary
                if !store.streamingReasoning.isEmpty {
                    reasoningCollapsedBadge(
                        text: store.streamingReasoning,
                        timeMs: store.agentReasoningTimeMs
                    )
                }
                // Streaming content with cursor
                if !store.streamingContent.isEmpty {
                    StreamingTextView(text: store.streamingContent, isActive: phase != .done)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .idle:
            // Fallback: non-streaming loading
            HStack(spacing: 10) {
                ProgressView()
                    .scaleEffect(0.75)
                    .tint(CreamTheme.green)
                Text(L.aiThinking)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var streamingReasoningRow: some View {
        DisclosureGroup {
            Text(store.streamingReasoning)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
        } label: {
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.6)
                    .tint(CreamTheme.green)
                Text(L.aiThinkingShort)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .opacity(pulseOpacity)
                    .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: pulseOpacity)
                    .onAppear { pulseOpacity = 0.4 }
            }
        }
        .tint(.secondary)
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.03))
        )
    }

    @State private var pulseOpacity: Double = 1.0

    /// Collapsed reasoning badge for completed reasoning phase
    private func reasoningCollapsedBadge(text: String, timeMs: Int?) -> some View {
        DisclosureGroup {
            Text(text)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "brain.head.profile")
                    .font(.caption2)
                    .foregroundStyle(CreamTheme.green)
                Text(L.thinkingProcess)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if let ms = timeMs {
                    Text("· \(String(format: "%.1f", Double(ms) / 1000))s")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .tint(.secondary)
        .font(.caption2)
    }

    /// Reasoning disclosure for persisted messages
    private func persistedReasoningSection(content: String, timeMs: Int?) -> some View {
        DisclosureGroup {
            Text(content)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
                .textSelection(.enabled)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "brain.head.profile")
                    .font(.caption2)
                    .foregroundStyle(CreamTheme.green)
                Text(L.thinkingProcess)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if let ms = timeMs {
                    Text("· \(String(format: "%.1f", Double(ms) / 1000))s")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .tint(.secondary)
        .font(.caption2)
    }

    private func systemNotice(_ text: String, icon: String = "leaf") -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(CreamTheme.green)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
            if store.agentErrorMessage == text {
                Button {
                    store.agentErrorMessage = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Capsule().fill(.white.opacity(0.72)))
    }

    private var actionCards: some View {
        VStack(alignment: .leading, spacing: 12) {
            let creates = store.pendingCreateActions
            let mutations = store.pendingMutationActions

            if creates.count >= 2 {
                actionChecklist(creates)
            } else {
                ForEach(creates) { action in
                    actionCard(action)
                }
            }

            ForEach(mutations) { action in
                actionCard(action)
            }
        }
    }

    // MARK: - Checklist UI (≥2 create actions)

    private var executionCompleted: Int {
        if case .executing(_, let completed) = store.agentExecutionState { return completed }
        return 0
    }

    private var isExecuting: Bool {
        if case .executing = store.agentExecutionState { return true }
        return false
    }

    private func actionChecklist(_ actions: [AgentActionDraft]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "list.bullet.clipboard")
                    .foregroundStyle(CreamTheme.green)
                Text(L.aryaPlan)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CreamTheme.text)
                Spacer()
                if !isExecuting {
                    Button {
                        store.dismissAllPendingAgentActions()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 8)

            ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                checklistRow(action, index: index)
            }

            if isExecuting {
                executionProgress(actions)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            } else {
                HStack(spacing: 12) {
                    Button {
                        store.executeAllPendingAgentActions()
                    } label: {
                        Text(L.startExecution)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Capsule().fill(CreamTheme.green))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
                .padding(.top, 6)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.white.opacity(0.9))
                .shadow(color: .black.opacity(0.06), radius: 18, x: 0, y: 8)
        )
    }

    @State private var expandedChecklistId: UUID?

    private func checklistRow(_ action: AgentActionDraft, index: Int) -> some View {
        let completed = executionCompleted > index
        let isCurrent = isExecuting && executionCompleted == index
        let isExpanded = expandedChecklistId == action.id

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expandedChecklistId = isExpanded ? nil : action.id
                }
            } label: {
                HStack(spacing: 10) {
                    ZStack {
                        if completed {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(CreamTheme.green)
                        } else if isCurrent {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "circle")
                                .foregroundStyle(.secondary.opacity(0.5))
                        }
                    }
                    .font(.callout)
                    .frame(width: 20)

                    Image(systemName: actionIcon(for: action))
                        .font(.caption)
                        .foregroundStyle(actionTintColor(for: action))

                    Text(action.title.isEmpty ? action.detail : action.title)
                        .font(.callout)
                        .foregroundStyle(completed ? .secondary : CreamTheme.text)
                        .strikethrough(completed)
                        .lineLimit(1)

                    Spacer()

                    if !isExecuting {
                        Button {
                            store.dismissAgentAction(id: action.id)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary.opacity(0.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .disabled(isExecuting)

            if isExpanded, !action.detail.isEmpty, action.detail != action.title {
                Text(action.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .padding(.horizontal, 14)
                    .padding(.leading, 30)
                    .padding(.bottom, 6)
            }

            if index < (store.pendingCreateActions.count - 1) {
                Divider()
                    .padding(.leading, 44)
            }
        }
    }

    private func executionProgress(_ actions: [AgentActionDraft]) -> some View {
        let total = actions.count
        let completed = executionCompleted
        let fraction = total > 0 ? Double(completed) / Double(total) : 0

        return VStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(CreamTheme.green.opacity(0.15))
                    Capsule()
                        .fill(CreamTheme.green)
                        .frame(width: geo.size.width * fraction)
                        .animation(.easeInOut(duration: 0.3), value: completed)
                }
            }
            .frame(height: 6)

            Text("\(completed)/\(total) \(L.nOfMCompleted)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Single action card (1 create or mutation)

    private func actionCard(_ action: AgentActionDraft) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: actionIcon(for: action))
                    .foregroundStyle(actionTintColor(for: action))
                Text(actionLabel(for: action))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CreamTheme.text)
                Spacer()
                Button {
                    store.dismissAgentAction(id: action.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            Text(action.title.isEmpty ? action.detail : action.title)
                .font(.callout.weight(.medium))
                .foregroundStyle(CreamTheme.text)
                .lineLimit(2)
            if !action.detail.isEmpty, action.detail != action.title {
                Text(action.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            Button {
                if let err = store.confirmAgentAction(id: action.id) {
                    store.agentErrorMessage = err
                }
            } label: {
                let tint = actionTintColor(for: action)
                Text(actionButtonText(for: action))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(tint.opacity(0.13)))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.white.opacity(0.9))
                .shadow(color: .black.opacity(0.06), radius: 18, x: 0, y: 8)
        )
    }

    private var inputDock: some View {
        VStack(spacing: 9) {
            if !store.agentMessageQueue.isEmpty {
                queuedMessagesBar
            }
            HStack(alignment: .center, spacing: 10) {
                TextField(L.aiInputPlaceholder, text: $rawInput, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.callout)
                    .lineLimit(1...5)
                    .submitLabel(.send)
                    .focused($inputFocused)
                    .onSubmit {
                        if hasText { submitAgent() }
                    }
                    .padding(.vertical, 11)

                if store.isAgentLoading && !hasText {
                    Button {
                        store.cancelAgentRequest()
                    } label: {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(Color.red.opacity(0.35)))
                    }
                    .buttonStyle(.plain)
                    .frame(width: 42, height: 42, alignment: .center)
                } else {
                    Button {
                        submitAgent()
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(hasText ? CreamTheme.green : Color.gray.opacity(0.26)))
                    }
                    .buttonStyle(.plain)
                    .disabled(!hasText)
                    .frame(width: 42, height: 42, alignment: .center)
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, 8)
            .background(
                RoundedRectangle(cornerRadius: 26)
                    .fill(.white.opacity(0.9))
                    .shadow(color: .black.opacity(0.10), radius: 22, x: 0, y: 8)
            )
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 22)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: 0.18),
                            .init(color: .black, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .allowsHitTesting(false)
        )
    }

    private var historyOverlay: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.88)) {
                        showHistory = false
                    }
                }

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: 22) {
                    historyHeader

                    historyList
                    undoDeleteBanner
                    historySearchDock
                }
                .padding(.horizontal, 30)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .background(
                    UnevenRoundedRectangle(topLeadingRadius: 36, topTrailingRadius: 36)
                        .fill(Color(red: 0.99, green: 0.99, blue: 0.98))
                )
                .offset(y: max(0, historyDragOffset))
                .shadow(color: .black.opacity(0.10), radius: 22, x: 0, y: -4)
            }
            .ignoresSafeArea(.container, edges: .bottom)
        }
    }

    private var historyHeader: some View {
        VStack(spacing: 12) {
            Capsule()
                .fill(CreamTheme.text.opacity(0.16))
                .frame(width: 38, height: 4)
                .padding(.top, 12)

            Text(L.conversationTitle)
                .font(.title2.weight(.bold))
                .foregroundStyle(CreamTheme.text)
                .frame(maxWidth: .infinity)
        }
        .contentShape(Rectangle())
        .highPriorityGesture(historyDismissDrag)
    }

    private var historySearchDock: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(L.search, text: $searchText)
                    .font(.callout)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 16)
            .frame(height: 52)
            .background(Capsule().fill(.white.opacity(0.92)))
            .shadow(color: .black.opacity(0.08), radius: 16, x: 0, y: 8)

            Button {
                store.createNewAgentThread()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.88)) {
                    showHistory = false
                }
                inputFocused = true
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(CreamTheme.text)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(.white.opacity(0.92)))
                    .shadow(color: .black.opacity(0.08), radius: 16, x: 0, y: 8)
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, 26)
    }

    @ViewBuilder
    private var undoDeleteBanner: some View {
        if let thread = recentlyDeletedThread {
            HStack(spacing: 10) {
                Text(L.removedThread(thread.title))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Button(L.undo) {
                    store.restoreAgentThread(thread)
                    recentlyDeletedThread = nil
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(CreamTheme.green)
            }
            .padding(.horizontal, 16)
            .frame(height: 42)
            .background(Capsule().fill(.white.opacity(0.92)))
            .shadow(color: .black.opacity(0.08), radius: 14, x: 0, y: 6)
        }
    }

    private var historyList: some View {
        let items = filteredThreads
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if !recentThreads(items).isEmpty {
                    historySection("过去 30 天", items: recentThreads(items))
                }
                if !olderThreads(items).isEmpty {
                    historySection("更早", items: olderThreads(items))
                }
                if items.isEmpty {
                    Text(L.emptyConversationHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 20)
                }
            }
            .padding(.bottom, 20)
        }
    }

    private var filteredThreads: [AgentChatThreadIndexItem] {
        store.agentThreadIndex
            .filter { store.agentThreadMatchesSearch($0, query: searchText) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private func recentThreads(_ items: [AgentChatThreadIndexItem]) -> [AgentChatThreadIndexItem] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? .distantPast
        return items.filter { $0.updatedAt >= cutoff }
    }

    private func olderThreads(_ items: [AgentChatThreadIndexItem]) -> [AgentChatThreadIndexItem] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? .distantPast
        return items.filter { $0.updatedAt < cutoff }
    }

    private func historySection(_ title: String, items: [AgentChatThreadIndexItem]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(items) { item in
                historyRow(item)
            }
        }
    }

    private func historyRow(_ item: AgentChatThreadIndexItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.id == store.currentAgentThreadID ? "bubble.left.fill" : "bubble.left")
                .font(.system(size: 18))
                .foregroundStyle(item.id == store.currentAgentThreadID ? CreamTheme.green : .secondary)
                .frame(width: 24)

            Button {
                store.selectAgentThread(id: item.id)
                withAnimation(.spring(response: 0.3, dampingFraction: 0.88)) {
                    showHistory = false
                }
            } label: {
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.title.isEmpty ? L.newConversation : item.title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(CreamTheme.text)
                        .lineLimit(1)
                    Text(relativeDate(item.updatedAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(item.id == store.currentAgentThreadID ? .white.opacity(0.78) : .clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: 18))
        .contextMenu {
            Button {
                beginThreadRename(item)
            } label: {
                Label(L.rename, systemImage: "pencil")
            }

            Button(role: .destructive) {
                pendingDelete = item
            } label: {
                Label(L.delete, systemImage: "trash")
            }
        }
    }

    private func beginThreadRename(_ item: AgentChatThreadIndexItem) {
        renamingThread = item
        renameDraft = item.title.isEmpty ? L.newConversation : item.title
    }

    private func commitThreadRename() {
        guard let item = renamingThread else { return }
        let clean = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        store.renameAgentThread(id: item.id, title: clean)
        renamingThread = nil
        renameDraft = ""
    }

    private func iconButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(CreamTheme.text.opacity(0.82))
                .frame(width: 48, height: 48)
                .background(
                    Circle()
                        .fill(.white.opacity(0.78))
                        .shadow(color: .black.opacity(0.055), radius: 15, x: 0, y: 7)
                )
        }
        .buttonStyle(.plain)
    }

    private func modeChip(title: String, icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(selected ? .white : CreamTheme.text.opacity(0.74))
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(
                    Capsule().fill(selected ? CreamTheme.green : .white.opacity(0.86))
                )
        }
        .buttonStyle(.plain)
    }

    private var hasText: Bool {
        !rawInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canSend: Bool { hasText }

    private func submitAgent() {
        let text = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if !AIConsent.hasAccepted {
            pendingAIText = text
            showConsent = true
            return
        }
        submitAI(text)
    }

    private func submitAI(_ text: String) {
        if store.isAgentLoading {
            store.enqueueAgentMessage(text)
        } else if chatMode {
            store.submitAgentText(text)
        } else {
            store.submitQuickText(text)
        }
        rawInput = ""
    }

    private func submitLocal() {
        let text = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        store.submitLocalOnly(text)
        rawInput = ""
    }

    private var panelDismissDrag: some Gesture {
        DragGesture(minimumDistance: 24, coordinateSpace: .local)
            .onChanged { value in
                guard !showHistory else { return }
                let downward = value.translation.height
                if downward > 0, downward > abs(value.translation.width) {
                    verticalDragOffset = min(downward * 0.86, 220)
                }
            }
            .onEnded { value in
                guard !showHistory else {
                    verticalDragOffset = 0
                    return
                }
                let downward = value.translation.height
                let predicted = value.predictedEndTranslation.height
                if downward > 210 || predicted > 420 {
                    onClose()
                } else {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        verticalDragOffset = 0
                    }
                }
            }
    }

    private var contentDismissKeyboardDrag: some Gesture {
        DragGesture(minimumDistance: 14, coordinateSpace: .local)
            .onChanged { value in
                let downward = value.translation.height
                guard downward > 10, downward > abs(value.translation.width) else { return }
                inputFocused = false
            }
    }

    private var historyDismissDrag: some Gesture {
        DragGesture(minimumDistance: 24, coordinateSpace: .local)
            .onChanged { value in
                let downward = value.translation.height
                if downward > 0, downward > abs(value.translation.width) {
                    historyDragOffset = min(downward * 0.86, 220)
                }
            }
            .onEnded { value in
                let downward = value.translation.height
                let predicted = value.predictedEndTranslation.height
                if downward > 210 || predicted > 420 {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.88)) {
                        showHistory = false
                        historyDragOffset = 0
                    }
                } else {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        historyDragOffset = 0
                    }
                }
            }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        guard let last = store.agentSession.messages.last else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    private func actionLabel(for action: AgentActionDraft) -> String {
        if (action.kind == .inbox || action.kind == .brain) && action.inboxType == "DBT练习" {
            return L.savePractice
        }
        switch action.kind {
        case .inbox: return L.suggestInbox
        case .brain: return L.suggestBrain
        case .task: return L.suggestTask
        case .time: return L.suggestTime
        case .calendarEvent: return L.suggestCalendar
        case .editTask: return L.suggestEditTask
        case .editTime: return L.suggestEditTime
        case .editInbox: return L.suggestEditInbox
        case .deleteTask: return L.suggestDeleteTask
        case .deleteTime: return L.suggestDeleteTime
        case .deleteInbox: return L.suggestDeleteInbox
        case .completeTask: return L.suggestComplete
        }
    }

    private func actionIcon(for action: AgentActionDraft) -> String {
        if (action.kind == .inbox || action.kind == .brain) && action.inboxType == "DBT练习" {
            return "leaf"
        }
        switch action.kind {
        case .inbox: return "square.and.pencil"
        case .brain: return "brain.head.profile"
        case .task: return "checklist"
        case .time: return "clock"
        case .calendarEvent: return "calendar.badge.plus"
        case .editTask, .editTime, .editInbox: return "pencil"
        case .deleteTask, .deleteTime, .deleteInbox: return "trash"
        case .completeTask: return "checkmark.circle"
        }
    }

    private func actionButtonText(for action: AgentActionDraft) -> String {
        switch action.kind {
        case .brain: return L.save
        case .editTask, .editTime, .editInbox: return L.confirmEdit
        case .deleteTask, .deleteTime, .deleteInbox: return L.confirmDelete
        case .completeTask: return L.confirm
        case .calendarEvent: return L.addToCalendar
        default: return L.save
        }
    }

    private func actionTintColor(for action: AgentActionDraft) -> Color {
        switch action.kind {
        case .deleteTask, .deleteTime, .deleteInbox: return .red
        case .brain: return CreamTheme.green
        case .calendarEvent: return .blue
        default: return CreamTheme.green
        }
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: L.localeId)
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Streaming text with blinking cursor

private struct StreamingTextView: View {
    let text: String
    let isActive: Bool
    @State private var showCursor = true

    var body: some View {
        Text(text + (isActive && showCursor ? "▍" : ""))
            .font(.callout)
            .lineSpacing(4)
            .foregroundStyle(CreamTheme.text.opacity(0.9))
            .onAppear {
                guard isActive else { return }
                startCursorBlink()
            }
            .onChange(of: isActive) { _, active in
                if active { startCursorBlink() }
            }
    }

    private func startCursorBlink() {
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
            if !isActive { timer.invalidate(); return }
            showCursor.toggle()
        }
    }
}
