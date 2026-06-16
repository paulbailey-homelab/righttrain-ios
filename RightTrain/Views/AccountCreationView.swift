import SwiftUI

struct AccountCreationView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @State private var migratePreferences = true

    var body: some View {
        Form {
            Section {
                Label("No email or phone number", systemImage: "person.crop.circle.badge.questionmark")
                Label("A passkey-style credential controls the account", systemImage: "key")
                Label("Station defaults and routines can sync", systemImage: "arrow.triangle.2.circlepath")
            } header: {
                Label("Privacy", systemImage: "hand.raised")
            } footer: {
                Text("RightTrain stores a pseudonymous account record and your synced preferences. The recovery code is shown once and only its verifier is stored by the service.")
            }
            .listRowBackground(Color.rightTrainPaperCream)

            Section {
                Toggle("Sync this device's saved preferences", isOn: $migratePreferences)

                Button {
                    Task { await authViewModel.createPortableAccount(migrateCurrentDevicePreferences: migratePreferences) }
                } label: {
                    Label("Create Account", systemImage: "key.badge.plus")
                }
                .disabled(!authViewModel.isSignedIn || !authViewModel.isAccountCredentialSupported)
            } footer: {
                if !authViewModel.isAccountCredentialSupported {
                    Text("Account credentials are not available on this device.")
                }
            }
            .listRowBackground(Color.rightTrainPaperCream)

            if let recoveryCode = authViewModel.oneTimeRecoveryCode {
                Section {
                    Text(recoveryCode)
                        .font(.system(.title3, design: .monospaced).weight(.semibold))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        authViewModel.acknowledgeRecoveryCode()
                    } label: {
                        Label("I Saved This Code", systemImage: "checkmark.circle")
                    }
                } header: {
                    Label("Recovery Code", systemImage: "lock.rotation")
                } footer: {
                    Text("Save this now. It will not be shown again.")
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
        .navigationTitle("Create Account")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(Color.rightTrainSurfaceCream.ignoresSafeArea())
        .lightSurfaceForeground()
        .environment(\.colorScheme, .light)
    }
}
