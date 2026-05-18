import SwiftUI

/// 首次使用 AI 时弹出的同意书
/// - 触发时机：用户在全局输入框触发聊天/拆解时，检查 `ai.consent.v1` 未同意 → 弹此 sheet
/// - 同意后写入 UserDefaults；下次不再弹
struct AIConsentSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onAccept: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Hero
                    HStack(spacing: 12) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(CreamTheme.green)
                        Text("首次使用 AI")
                            .font(.title2.weight(.bold))
                    }

                    Text("LifeOS 的 AI 功能会在你主动发送时，把输入框内的文字发送到我们的服务器，用于陪聊引导或拆解成待办 / 时间 / 随记建议。使用前请先阅读以下说明。")
                        .font(.body)
                        .foregroundStyle(.primary)

                    // 要点卡
                    VStack(alignment: .leading, spacing: 14) {
                        bullet(icon: "arrow.up.right",
                               title: "发送内容",
                               body: "聊天或拆解时的当次输入文本、当前日期时间；聊天模式还会带上本轮对话与近期记录摘要")
                        bullet(icon: "tray.and.arrow.down",
                               title: "处理方式",
                               body: "请求通过 ai.dogdada.com 转发给大模型服务（DeepSeek）处理后返回；我们的服务器不持久化你的请求内容")
                        bullet(icon: "lock.shield",
                               title: "不收集",
                               body: "不会上传设备信息、账号信息；聊天记录只保存在本机，不同步到 CloudKit")
                        bullet(icon: "bolt.fill",
                               title: "不想发送",
                               body: "拆解可改用 ⚡ 按钮走纯本地解析；不使用 AI 发送时，你仍可继续手动记录，不会发送任何内容")
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.white.opacity(0.85))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(CreamTheme.green.opacity(0.2), lineWidth: 1)
                    )

                    HStack(spacing: 4) {
                        Text("详细内容请查看")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("隐私政策")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(CreamTheme.green)
                    }
                }
                .padding(20)
            }
            .scrollContentBackground(.hidden)
            .background(CreamTheme.glassStrong)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    Button {
                        UserDefaults.standard.set(true, forKey: "ai.consent.v1")
                        onAccept()
                        dismiss()
                    } label: {
                        Text("同意并开始使用")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(CreamTheme.green)
                            )
                    }
                    .buttonStyle(.plain)

                    Button("暂不使用 AI") {
                        dismiss()
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
                .background(CreamTheme.glassStrong)
            }
            .toolbar(.hidden, for: .navigationBar)
            .creamBackground()
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(true)
    }

    @ViewBuilder
    private func bullet(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(CreamTheme.green)
                .frame(width: 22, height: 22)
                .background(
                    Circle().fill(CreamTheme.green.opacity(0.12))
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(body)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// 全局查询/写入 AI 同意状态
enum AIConsent {
    static var hasAccepted: Bool {
        UserDefaults.standard.bool(forKey: "ai.consent.v1")
    }
    static func revoke() {
        UserDefaults.standard.removeObject(forKey: "ai.consent.v1")
    }
}
