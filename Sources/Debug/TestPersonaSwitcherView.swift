#if DEBUG
import SwiftUI

struct TestPersonaSwitcherView: View {
    @EnvironmentObject var store: AppStore
    @State private var message: String?
    @State private var resetCandidate: TestPersona?

    private let defaults = UserDefaults.standard
    private let realUserIdKey = "debug.testPersona.realUserId"
    private let previousICloudKey = "debug.testPersona.previousICloudEnabled"

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label(L.testPersonaSafetyTitle, systemImage: "iphone.gen3")
                        .font(.headline)
                        .foregroundStyle(CreamTheme.text)
                    Text(L.testPersonaSafetyBody)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section {
                ForEach(TestPersonaSeeder.personas) { persona in
                    personaRow(persona)
                }
            } header: {
                Text(L.testPersonaSectionTitle)
            } footer: {
                Text(L.testPersonaDataPersistenceHint)
            }

            if store.isTestPersona {
                Section {
                    Button {
                        resetCandidate = TestPersonaSeeder.persona(id: store.currentAuthUserId)
                    } label: {
                        Label(L.testPersonaResetCurrent, systemImage: "arrow.counterclockwise")
                    }
                    .foregroundStyle(.red)

                    Button {
                        returnToRealUser()
                    } label: {
                        Label(L.testPersonaReturnReal, systemImage: "person.crop.circle")
                    }
                } footer: {
                    Text(L.testPersonaFooter)
                }
            }
        }
        .navigationTitle(L.testPersonaTitle)
        .navigationBarTitleDisplayMode(.inline)
        .alert(L.notice, isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )) {
            Button(L.gotIt) { message = nil }
        } message: {
            Text(message ?? "")
        }
        .confirmationDialog(
            L.testPersonaResetConfirmTitle,
            isPresented: Binding(
                get: { resetCandidate != nil },
                set: { if !$0 { resetCandidate = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(L.testPersonaResetConfirmAction, role: .destructive) {
                if let persona = resetCandidate {
                    reset(persona)
                }
                resetCandidate = nil
            }
            Button(L.cancel, role: .cancel) {
                resetCandidate = nil
            }
        } message: {
            Text(L.testPersonaResetConfirmBody)
        }
    }

    private func personaRow(_ persona: TestPersona) -> some View {
        let isActive = store.currentAuthUserId == persona.id
        return HStack(spacing: 12) {
            Text(persona.emoji)
                .font(.system(size: 28))
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(persona.displayName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(CreamTheme.text)
                    if isActive {
                        Text(L.testPersonaActive)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(CreamTheme.green)
                    }
                }
                Text(persona.displayDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if !isActive {
                Button(L.testPersonaSwitch) {
                    switchTo(persona)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }

    private func switchTo(_ persona: TestPersona) {
        rememberRealUserIfNeeded()
        defaults.set(store.isICloudSyncEnabled, forKey: previousICloudKey)
        store.debugDisableSystemIntegrationsForPersona()
        defaults.set(persona.id, forKey: "auth.userId")
        store.reloadForCurrentUser()
        TestPersonaSeeder.seedIfNeeded(persona, into: store)
        message = L.testPersonaSwitched(persona.displayName)
    }

    private func reset(_ persona: TestPersona) {
        store.debugDisableSystemIntegrationsForPersona()
        defaults.set(persona.id, forKey: "auth.userId")
        store.reloadForCurrentUser()
        store.wipeCurrentUserData()
        TestPersonaSeeder.markUnseeded(persona)
        TestPersonaSeeder.seed(persona, into: store)
        TestPersonaSeeder.markSeeded(persona)
        message = L.testPersonaResetDone(persona.displayName)
    }

    private func returnToRealUser() {
        let realUserId = defaults.string(forKey: realUserIdKey) ?? ""
        defaults.set(realUserId, forKey: "auth.userId")
        store.reloadForCurrentUser()
        let previousICloud = defaults.object(forKey: previousICloudKey) as? Bool ?? false
        store.setICloudSyncEnabled(previousICloud)
        defaults.removeObject(forKey: realUserIdKey)
        defaults.removeObject(forKey: previousICloudKey)
        message = L.testPersonaReturned
    }

    private func rememberRealUserIfNeeded() {
        guard !store.isTestPersona else { return }
        defaults.set(store.currentAuthUserId, forKey: realUserIdKey)
    }
}
#endif
