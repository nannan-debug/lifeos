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
            if !prefill.isEmpty, rawInput.isEmpty {
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
                        if store.isAgentLoading {
                            thinkingRow
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
                VStack(alignment: .leading, spacing: 8) {
                    Text(message.content)
                        .font(.callout)
                        .lineSpacing(4)
                        .foregroundStyle(CreamTheme.text.opacity(0.9))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 26)
            }
        }
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

    private var thinkingRow: some View {
        HStack(spacing: 10) {
            ProgressView()
                .scaleEffect(0.75)
                .tint(CreamTheme.green)
            Text("猫猫在想怎么接这句话...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
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
            ForEach(store.agentSession.pendingActions) { action in
                actionCard(action)
            }
        }
    }

    private func actionCard(_ action: AgentActionDraft) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: actionIcon(for: action.kind))
                    .foregroundStyle(CreamTheme.green)
                Text(actionLabel(for: action.kind))
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
                Text("保存")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CreamTheme.green)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(CreamTheme.green.opacity(0.13)))
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
            HStack(alignment: .center, spacing: 10) {
                TextField("问问、快速记录或聊聊今天...", text: $rawInput, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.callout)
                    .lineLimit(1...5)
                    .submitLabel(.send)
                    .focused($inputFocused)
                    .disabled(store.isAgentLoading)
                    .onSubmit {
                        if canSend { submitAgent() }
                    }
                    .padding(.vertical, 11)

                Button {
                    submitAgent()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(canSend ? CreamTheme.green : Color.gray.opacity(0.26)))
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .frame(width: 42, height: 42, alignment: .center)
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

    private var canSend: Bool {
        hasText && !store.isAgentLoading
    }

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
        if chatMode {
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

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_Hans")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
