import SwiftUI
import UIKit

struct ExportView: View {
    @EnvironmentObject var store: AppStore

    @State private var startDate: Date = Self.defaultStart()
    @State private var endDate: Date = Date()

    @State private var alertMessage: String?

    var body: some View {
        Form {
            Section {
                DatePicker("起始日期", selection: $startDate, displayedComponents: .date)
                DatePicker("结束日期", selection: $endDate, in: startDate..., displayedComponents: .date)
            } header: {
                Text("时间区间")
            } footer: {
                Text("将导出区间内的「时间记录」「随手记」「打卡」CSV 文件。")
            }

            Section {
                Button {
                    runExport()
                } label: {
                    HStack {
                        Spacer()
                        Image(systemName: "square.and.arrow.up")
                        Text("导出 CSV").font(.body.weight(.semibold))
                        Spacer()
                    }
                }
                .tint(CreamTheme.green)
            } footer: {
                Text("导出后会弹出系统分享面板，可选择「存到 文件 / iCloud Drive」或其它目标。文件用 UTF-8 BOM 编码，中文 Excel 直接打开不乱码。")
            }
        }
        .navigationTitle("导出")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(CreamTheme.glassStrong)
        .creamBackground()
        .alert("无法导出", isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button("好") { alertMessage = nil }
        } message: {
            Text(alertMessage ?? "")
        }
    }

    private func runExport() {
        let result = store.exportCSVs(from: startDate, to: endDate)
        if let error = result.errorMessage {
            alertMessage = error
            return
        }
        let urls = [result.timeURL, result.inboxURL, result.checkURL].compactMap { $0 }
        guard !urls.isEmpty else {
            alertMessage = "所选区间没有可导出的内容"
            return
        }
        Self.presentShareSheet(items: urls)
    }

    private static func defaultStart() -> Date {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: Date())
        return cal.date(from: comps) ?? Date()
    }

    /// 直接走 UIKit 的 present，绕开 SwiftUI `.sheet` 与 UIActivityViewController 之间的兼容问题
    /// （表现为 share sheet 只显示图标 + X，主体一片空白）。
    private static func presentShareSheet(items: [Any]) {
        guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive })
                ?? (UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first),
              let rootVC = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController
                ?? scene.windows.first?.rootViewController else { return }
        let activityVC = UIActivityViewController(activityItems: items, applicationActivities: nil)
        var topVC = rootVC
        while let presented = topVC.presentedViewController {
            topVC = presented
        }
        // 适配 iPad popover 锚点（iPhone 上忽略）
        if let pop = activityVC.popoverPresentationController {
            pop.sourceView = topVC.view
            pop.sourceRect = CGRect(x: topVC.view.bounds.midX, y: topVC.view.bounds.midY, width: 0, height: 0)
            pop.permittedArrowDirections = []
        }
        topVC.present(activityVC, animated: true)
    }
}
