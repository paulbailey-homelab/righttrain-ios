import SwiftUI

struct AccountRestoreView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @State private var recoveryCode = ""

    var body: some View {
        Form {
            Section {
                Button {
                    Task { await authViewModel.restorePortableAccount() }
                } label: {
                    Label("Log in with passkey", systemImage: "key")
                }
                .disabled(!authViewModel.isAccountCredentialSupported)
            } footer: {
                Text("Use this when your passkey is available in iCloud Keychain or another credential provider.")
            }

            Section {
                TextField("Recovery code", text: $recoveryCode)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()

                Button {
                    Task { await authViewModel.recoverPortableAccount(recoveryCode: recoveryCode) }
                } label: {
                    Label("Use recovery code", systemImage: "lock.rotation")
                }
                .disabled(recoveryCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } header: {
                Label("Account recovery", systemImage: "lifepreserver")
            } footer: {
                Text("Recovery adds a replacement passkey. RightTrain does not use email or phone number lookup for this flow.")
            }

            if let preferenceSet = authViewModel.accountPreferenceSet {
                Section {
                    SettingsAccountValueRow(title: "Preference version", systemImage: "number", value: "\(preferenceSet.version)")
                    SettingsAccountValueRow(title: "Last synced", systemImage: "clock", value: preferenceSet.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    SettingsAccountValueRow(title: "Saved commutes", systemImage: "tram", value: "\(preferenceSet.commuteRoutines.count)")
                } header: {
                    Label("Synced preferences", systemImage: "arrow.down.doc")
                }
            }

            if let message = authViewModel.accountStatusMessage {
                Section {
                    Label(message, systemImage: "checkmark.seal")
                }
            }
        }
        .readableContentMargins()
        .navigationTitle("Log in")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct SettingsAccountValueRow: View {
    var title: String
    var systemImage: String
    var value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Label(title, systemImage: systemImage)
                .foregroundStyle(.primary, Color.rightTrainActionInk)
            Spacer(minLength: 12)
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }
}
