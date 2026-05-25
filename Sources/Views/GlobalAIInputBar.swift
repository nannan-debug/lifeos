import SwiftUI

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
    @State private var recentlyDeletedThread: AgentChatThread?
    @State private var verticalDragOffset: CGFloat = 0
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
        .alert("删除这段对话？", isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )) {
            Button("明天再说", role: .cancel) {
                pendingDelete = nil
            }
            Button("删除", role: .destructive) {
                if let item = pendingDelete {
                    recentlyDeletedThread = store.deleteAgentThread(id: item.id)
                }
                pendingDelete = nil
            }
        } message: {
            Text("这只会删除这段猫猫对话，不会影响已经保存到随手记、待办或时间里的内容。")
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
        }
        .padding(.bottom, 8)
        .contentShape(Rectangle())
        .highPriorityGesture(panelDismissDrag)
    }

    private var displayTitle: String {
        store.agentSession.messages.isEmpty ? "LifeOS AI" : store.currentAgentThreadTitle
    }

    private var conversationArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if store.agentSession.messages.isEmpty && store.agentSession.pendingActions.isEmpty {
                        emptyState
                            .padding(.top, 36)
                    } else {
                        ForEach(store.agentSession.messages) { message in
                            messageRow(message)
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
            Text("可以快速记一件事，也可以慢慢聊清楚。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func messageRow(_ message: AgentChatMessage) -> some View {
        HStack(alignment: .top) {
            if message.role == "user" {
                Spacer(minLength: 46)
                Text(message.content)
                    .font(.callout)
                    .foregroundStyle(CreamTheme.text)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 22)
                            .fill(Color.black.opacity(0.045))
                    )
                    .frame(maxWidth: 285, alignment: .trailing)
            } else if message.autoSavedAction != nil {
                autoSavedRow(message)
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
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 26)
            }
        }
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
                    Text("查看")
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
                Text("撤销")
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
                Text("猫猫在想怎么接这句话...")
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
                Text("猫猫在想...")
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
                Text("思考过程")
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
                Text("思考过程")
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
                Text("Arya 的计划")
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
                        Text("开始执行")
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

            Text("\(completed)/\(total) 已完成")
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
                TextField("问问、快速记录或聊聊今天...", text: $rawInput, axis: .vertical)
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

            Text("对话")
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
                TextField("搜索", text: $searchText)
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
                Text("已移除「\(thread.title.isEmpty ? "新的对话" : thread.title)」")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Button("撤销") {
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
                    Text("还没有留下对话。新的想法可以从这里开始。")
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
                    Text(item.title.isEmpty ? "新的对话" : item.title)
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

            Button {
                pendingDelete = item
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary.opacity(0.72))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
        }
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
        if action.kind == .inbox && action.inboxType == "DBT练习" {
            return "保存练习记录"
        }
        switch action.kind {
        case .inbox: return "建议存随手记"
        case .task: return "建议存待办"
        case .time: return "建议存时间"
        case .calendarEvent: return "建议加日历"
        case .editTask: return "建议改待办"
        case .editTime: return "建议改时间"
        case .editInbox: return "建议改随手记"
        case .deleteTask: return "建议删待办"
        case .deleteTime: return "建议删时间"
        case .deleteInbox: return "建议删随手记"
        case .completeTask: return "建议标完成"
        }
    }

    private func actionIcon(for action: AgentActionDraft) -> String {
        if action.kind == .inbox && action.inboxType == "DBT练习" {
            return "leaf"
        }
        switch action.kind {
        case .inbox: return "square.and.pencil"
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
        case .editTask, .editTime, .editInbox: return "确认修改"
        case .deleteTask, .deleteTime, .deleteInbox: return "确认删除"
        case .completeTask: return "确认"
        case .calendarEvent: return "添加到日历"
        default: return "保存"
        }
    }

    private func actionTintColor(for action: AgentActionDraft) -> Color {
        switch action.kind {
        case .deleteTask, .deleteTime, .deleteInbox: return .red
        case .calendarEvent: return .blue
        default: return CreamTheme.green
        }
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_Hans")
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
