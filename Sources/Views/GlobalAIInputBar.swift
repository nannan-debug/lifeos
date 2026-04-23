import SwiftUI

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
                // 失败提示条（展开态顶部）
                if isExpanded, let msg = store.aiDebugMessage {
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
                    store.submitAIText(text)
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
                .offset(x: -12, y: 4)
                .allowsHitTesting(false)
        }
    }

    private var expandedBar: some View {
        let hasText = !rawInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let isLoading = store.isAILoading
        let canSend = hasText && !isLoading

        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                HStack(spacing: 6) {
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

                    TextField("说点什么…（AI 自动归类到待办/时间/随记）", text: $rawInput, axis: .horizontal)
                        .textFieldStyle(.plain)
                        .font(.body)
                        .submitLabel(.send)
                        .focused($inputFocused)
                        .disabled(isLoading)
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
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            isLoading ? CreamTheme.green.opacity(0.5) : Color.black.opacity(0.08),
                            lineWidth: isLoading ? 1.5 : 1
                        )
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.white.opacity(0.98))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.14), radius: 16, x: 0, y: 6)
        }
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
        store.submitAIText(text)
        rawInput = ""
    }

    private func submitLocal() {
        let text = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        store.submitLocalOnly(text)
        rawInput = ""
    }
}
