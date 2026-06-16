import SwiftUI

struct AccountPrivacyControlsView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirmation = false

    var body: some View {
        Form {
            Section {
                Button {
                    Task { await authViewModel.exportPortableAccountData() }
                } label: {
                    Label("Generate Export", systemImage: "square.and.arrow.down")
                }
            } header: {
                Label("Export", systemImage: "doc.text")
            } footer: {
                Text("The export contains account preferences, linked-device categories, and retained-record explanations. It excludes access tokens, raw device identifiers, notification tokens, and credential material.")
            }
            .listRowBackground(Color.rightTrainPaperCream)

            if let export = authViewModel.accountExport {
                exportSummary(export)
            }

            Section {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("Delete Account", systemImage: "person.crop.circle.badge.xmark")
                }
                .foregroundStyle(Color.rightTrainDanger)
            } header: {
                Label("Deletion", systemImage: "trash")
            } footer: {
                Text("Deletion removes synced preferences from account surfaces, revokes account sessions, and may retain a minimal audit record for a limited period.")
                    .foregroundStyle(Color.rightTrainDanger)
            }
            .listRowBackground(Color.rightTrainPaperCream)
        }
        .navigationTitle("Privacy Controls")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(Color.rightTrainSurfaceCream.ignoresSafeArea())
        .lightSurfaceForeground()
        .confirmationDialog("Delete account?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete Account", role: .destructive) {
                Task {
                    if await authViewModel.deleteAccount() {
                        dismiss()
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes synced account preferences and signs out linked devices.")
        }
        .environment(\.colorScheme, .light)
    }

    private func exportSummary(_ export: AccountExportResponse) -> some View {
        Group {
            Section {
                SettingsAccountValueRow(
                    title: "Generated",
                    systemImage: "clock",
                    value: export.generatedAt.formatted(date: .abbreviated, time: .shortened)
                )
                SettingsAccountValueRow(
                    title: "Preference Version",
                    systemImage: "number",
                    value: "\(export.preferenceSet.version)"
                )
                SettingsAccountValueRow(
                    title: "Saved Routines",
                    systemImage: "tram",
                    value: "\(export.preferenceSet.commuteRoutines.count)"
                )
                SettingsAccountValueRow(
                    title: "Linked Devices",
                    systemImage: "iphone.gen3",
                    value: "\(export.linkedDevices.count)"
                )
            } header: {
                Label("Export Summary", systemImage: "checklist")
            }
            .listRowBackground(Color.rightTrainPaperCream)

            if let retainedRecords = export.retainedRecords, !retainedRecords.isEmpty {
                Section {
                    ForEach(retainedRecords.indices, id: \.self) { index in
                        let record = retainedRecords[index]
                        VStack(alignment: .leading, spacing: 4) {
                            Text(record.purpose)
                                .font(.headline)
                            Text("Retained until \(record.retentionUntil.formatted(date: .abbreviated, time: .omitted))")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(record.dataCategories.joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Label("Retained Records", systemImage: "archivebox")
                }
                .listRowBackground(Color.rightTrainPaperCream)
            }
        }
    }
}
