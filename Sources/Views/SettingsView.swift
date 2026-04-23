import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    @AppStorage("auth.user") private var user = "Anna"

    @State private var showDeleteConfirm = false

    @State private var editingField: ProfileField?
    @State private var draftValue = ""

    @State private var showCSVImporter = false
    @State private var csvImportMessage = ""
    @State private var showImportResult = false

    @State private var shareURL: URL?
    @State private var showShareSheet = false

    var body: some View {
        NavigationStack {
            List {
                Section("账号信息") {
                    editableProfileRow(title: "昵称", value: user, field: .nickname)
                }

                Section("数据导出导入") {
                    Button("导出 CSV 文件") {
                        if let url = makeCSVExportFile() {
                            shareURL = url
                            showShareSheet = true
                        }
                    }

                    Button("导入 CSV 文件") {
                        showCSVImporter = true
                    }
                }

                Section {
                    Button("清空所有数据", role: .destructive) {
                        showDeleteConfirm = true
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .navigationTitle("关于你")
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("将永久删除本设备上的所有记录，是否继续？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("确认清空", role: .destructive) {
                    wipeAllData()
                }
                Button("取消", role: .cancel) {}
            }
            .sheet(item: $editingField) { field in
                editProfileSheet(field)
            }
            .sheet(isPresented: $showShareSheet) {
                if let url = shareURL {
                    ShareSheet(items: [url])
                }
            }
            .fileImporter(
                isPresented: $showCSVImporter,
                allowedContentTypes: [.commaSeparatedText, .plainText],
                allowsMultipleSelection: false
            ) { result in
                handleCSVImportResult(result)
            }
            .alert("导入结果", isPresented: $showImportResult) {
                Button("知道了", role: .cancel) {}
            } message: {
                Text(csvImportMessage)
            }
            .listStyle(.insetGrouped)
            .tint(CreamTheme.green)
            .scrollContentBackground(.hidden)
            .background(CreamTheme.glassStrong)
        }
        .creamBackground()
    }

    @ViewBuilder
    private func editableProfileRow(title: String, value: String, field: ProfileField) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
            Button {
                draftValue = rawValue(for: field)
                editingField = field
            } label: {
                Image(systemName: "pencil")
                    .foregroundStyle(CreamTheme.green)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func editProfileSheet(_ field: ProfileField) -> some View {
        NavigationStack {
            Form {
                TextField(field.title, text: $draftValue)
            }
            .navigationTitle("修改\(field.title)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { editingField = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        saveDraftValue(for: field)
                        editingField = nil
                    }
                    .disabled(draftValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func rawValue(for field: ProfileField) -> String {
        switch field {
        case .nickname: return user
        }
    }

    private func saveDraftValue(for field: ProfileField) {
        let clean = draftValue.trimmingCharacters(in: .whitespacesAndNewlines)
        switch field {
        case .nickname:
            user = clean.isEmpty ? user : clean
        }
    }

    private func makeCSVExportFile() -> URL? {
        let fileName = "lobster-export-\(timestamp()).csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try store.exportCSVString.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            csvImportMessage = "导出失败：\(error.localizedDescription)"
            showImportResult = true
            return nil
        }
    }

    private func handleCSVImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let err):
            csvImportMessage = "导入失败：\(err.localizedDescription)"
            showImportResult = true

        case .success(let urls):
            guard let url = urls.first else {
                csvImportMessage = "导入失败：未选择文件"
                showImportResult = true
                return
            }

            let scoped = url.startAccessingSecurityScopedResource()
            defer {
                if scoped { url.stopAccessingSecurityScopedResource() }
            }

            do {
                let text = try String(contentsOf: url, encoding: .utf8)
                if let err = store.importCSVString(text) {
                    csvImportMessage = "导入失败：\(err)"
                } else {
                    csvImportMessage = "导入成功"
                }
                showImportResult = true
            } catch {
                csvImportMessage = "导入失败：文件读取错误"
                showImportResult = true
            }
        }
    }

    private func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: Date())
    }

    /// 清空当前设备的全部本地记录。保留 `auth.userId`，继续用同一个身份继续使用。
    private func wipeAllData() {
        store.wipeCurrentUserData()
        UserDefaults.standard.removeObject(forKey: "auth.user")
        user = "Anna"
    }
}

private enum ProfileField: String, Identifiable {
    case nickname

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nickname: return "昵称"
        }
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
