import SwiftUI

struct AccountPrivacyControlsView: View {
    @Environment(AuthViewModel.self) private var authViewModel

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
        }
        .navigationTitle("Export Data")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(Color.rightTrainSurfaceCream.ignoresSafeArea())
        .lightSurfaceForeground()
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
