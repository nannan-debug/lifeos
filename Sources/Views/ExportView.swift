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
                DatePicker(L.startDate, selection: $startDate, displayedComponents: .date)
                DatePicker(L.endDate, selection: $endDate, in: startDate..., displayedComponents: .date)
            } header: {
                Text(L.exportDateSection)
            } footer: {
                Text(L.exportDateFooter)
            }

            Section {
                Button {
                    runExport()
                } label: {
                    HStack {
                        Spacer()
                        Image(systemName: "square.and.arrow.up")
                        Text(L.exportCSVButton).font(.body.weight(.semibold))
                        Spacer()
                    }
                }
                .tint(CreamTheme.green)
            } footer: {
                Text(L.exportShareFooter)
            }

            Section {
                Button {
                    runFullExport()
                } label: {
                    HStack {
                        Spacer()
                        Image(systemName: "tray.and.arrow.up")
                        Text(L.exportAll).font(.body.weight(.semibold))
                        Spacer()
                    }
                }
                .tint(CreamTheme.green)
            } header: {
                Text(L.fullBackup)
            } footer: {
                Text(L.exportAllFooter)
            }
        }
        .navigationTitle(L.exportTitle)
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(CreamTheme.glassStrong)
        .creamBackground()
        .alert(L.cannotExport, isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button(L.ok) { alertMessage = nil }
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
            alertMessage = L.noExportData
            return
        }
        Self.presentShareSheet(items: urls)
    }

    private func runFullExport() {
        guard let url = store.exportFullDataFile() else {
            alertMessage = L.noExportData
            return
        }
        Self.presentShareSheet(items: [url])
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
