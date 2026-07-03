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
                    Label("Log In with Passkey", systemImage: "key")
                }
                .disabled(!authViewModel.isAccountCredentialSupported)
            } footer: {
                Text("Use this when your passkey is available in iCloud Keychain or another credential provider.")
            }
            .listRowBackground(Color.rightTrainPaperCream)

            Section {
                TextField("Recovery code", text: $recoveryCode)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()

                Button {
                    Task { await authViewModel.recoverPortableAccount(recoveryCode: recoveryCode) }
                } label: {
                    Label("Use Recovery Code", systemImage: "lock.rotation")
                }
                .disabled(recoveryCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } header: {
                Label("Account Recovery", systemImage: "lifepreserver")
            } footer: {
                Text("Recovery adds a replacement passkey. RightTrain does not use email or phone number lookup for this flow.")
            }
            .listRowBackground(Color.rightTrainPaperCream)

            if let preferenceSet = authViewModel.accountPreferenceSet {
                Section {
                    SettingsAccountValueRow(title: "Preference Version", systemImage: "number", value: "\(preferenceSet.version)")
                    SettingsAccountValueRow(title: "Last Synced", systemImage: "clock", value: preferenceSet.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    SettingsAccountValueRow(title: "Saved Routines", systemImage: "tram", value: "\(preferenceSet.commuteRoutines.count)")
                } header: {
                    Label("Synced Preferences", systemImage: "arrow.down.doc")
                }
                .listRowBackground(Color.rightTrainPaperCream)
            }

            if let message = authViewModel.accountStatusMessage {
                Section {
                    Label(message, systemImage: "checkmark.seal")
                }
                .listRowBackground(Color.rightTrainPaperCream)
            }
        }
        .navigationTitle("Log In")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(Color.rightTrainSurfaceCream.ignoresSafeArea())
        .lightSurfaceForeground()
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
