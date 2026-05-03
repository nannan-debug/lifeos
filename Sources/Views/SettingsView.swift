import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    @AppStorage("auth.user") private var user = ""

    @State private var showDeleteConfirm = false

    @State private var editingField: ProfileField?
    @State private var draftValue = ""

    var body: some View {
        NavigationStack {
            List {
                iCloudSection

                Section("账号信息") {
                    editableProfileRow(title: "昵称", value: displayNickname, field: .nickname)
                }

                Section {
                    Button("清空所有数据", role: .destructive) {
                        showDeleteConfirm = true
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .navigationTitle("设置")
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
            .listStyle(.insetGrouped)
            .tint(CreamTheme.green)
            .scrollContentBackground(.hidden)
            .background(CreamTheme.glassStrong)
        }
        .creamBackground()
    }

    @ViewBuilder
    private var iCloudSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { store.isICloudSyncEnabled },
                set: { store.setICloudSyncEnabled($0) }
            )) {
                HStack(spacing: 12) {
                    syncGlyph

                    VStack(alignment: .leading, spacing: 3) {
                        Text("iCloud 同步")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(CreamTheme.text)
                        Text(store.iCloudSyncStatusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .tint(CreamTheme.green)
        } header: {
            Text("同步")
        } footer: {
            Text("不需要登录 App；使用系统 iCloud 在同一 Apple ID 的设备间同步。")
        }
    }

    private var syncGlyph: some View {
        ZStack {
            Circle()
                .fill(CreamTheme.green.opacity(0.12))
            Image(systemName: "icloud")
                .font(.system(size: 19, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(CreamTheme.green)
        }
        .frame(width: 36, height: 36)
    }

    private var displayNickname: String {
        let clean = user.trimmingCharacters(in: .whitespacesAndNewlines)
        if !clean.isEmpty { return clean }
        return defaultNickname
    }

    private var defaultNickname: String {
        let raw = store.currentAuthUserId
        let suffixSource = raw.isEmpty ? "LOCAL" : raw
        let suffix = String(suffixSource.suffix(4)).uppercased()
        return "用户-\(suffix)"
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
        case .nickname: return displayNickname
        }
    }

    private func saveDraftValue(for field: ProfileField) {
        let clean = draftValue.trimmingCharacters(in: .whitespacesAndNewlines)
        switch field {
        case .nickname:
            user = clean.isEmpty ? user : clean
        }
    }

    /// 清空当前设备的全部本地记录。保留 `auth.userId`，继续用同一个身份继续使用。
    private func wipeAllData() {
        store.wipeCurrentUserData()
        UserDefaults.standard.removeObject(forKey: "auth.user")
        user = ""
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
