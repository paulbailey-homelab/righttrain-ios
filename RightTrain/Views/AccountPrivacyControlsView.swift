import SwiftUI

struct AccountPrivacyControlsView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @State private var isGeneratingExport = false
    @State private var exportStatusText: String?

    var body: some View {
        Form {
            Section {
                Button {
                    generateExport()
                } label: {
                    HStack {
                        Label(authViewModel.accountExport == nil ? "Generate export" : "Regenerate export", systemImage: "square.and.arrow.down")
                        Spacer()
                        if isGeneratingExport {
                            ProgressView()
                                .controlSize(.small)
                        } else if authViewModel.accountExport != nil {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.rightTrainActionInk)
                        }
                    }
                }
                .disabled(isGeneratingExport)
                .accessibilityHint("Builds a JSON export of the data RightTrain holds about your account.")
                .accessibilityValue(isGeneratingExport ? "Generating" : "")
            } header: {
                Label("Export", systemImage: "doc.text")
            } footer: {
                Text(exportStatusText ?? "The export contains the journeys RightTrain is watching for you, your notification history, linked-device categories, and retained-record explanations. It excludes access tokens, raw device identifiers, notification tokens, and credential material. Your commutes are not in it because the service does not hold them — they are in your own iCloud.")
            }

            if let export = authViewModel.accountExport {
                exportActions(export)
                exportSummary(export)
            }
        }
        .readableContentMargins()
        .navigationTitle("Export data")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func generateExport() {
        guard !isGeneratingExport else { return }
        isGeneratingExport = true
        exportStatusText = nil
        Task {
            let didExport = await authViewModel.exportPortableAccountData()
            await MainActor.run {
                isGeneratingExport = false
                exportStatusText = didExport ? "Export generated. You can now share or preview the JSON export." : nil
            }
        }
    }

    private func exportActions(_ export: AccountExportResponse) -> some View {
        Section {
            if let exportJSON = exportJSONString(for: export) {
                ShareLink(
                    item: exportJSON,
                    subject: Text("RightTrain account export"),
                    message: Text("RightTrain account preference export generated \(export.generatedAt.formatted(date: .abbreviated, time: .shortened)).")
                ) {
                    Label("Share JSON Export", systemImage: "square.and.arrow.up")
                }

                DisclosureGroup {
                    Text(exportJSON)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Label("Preview JSON", systemImage: "doc.text.magnifyingglass")
                }
            } else {
                Label("Export generated, but the JSON preview could not be prepared.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Color.rightTrainDanger)
            }
        } header: {
            Label("Ready", systemImage: "checkmark.circle")
        } footer: {
            Text("Share or save this JSON export for your records.")
        }
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
                    title: "Linked Devices",
                    systemImage: "iphone.gen3",
                    value: "\(export.linkedDevices.count)"
                )
            } header: {
                Label("Export Summary", systemImage: "checklist")
            }

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
            }
        }
    }

    private func exportJSONString(for export: AccountExportResponse) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(DateFormatting.apiDateTime.string(from: date))
        }
        guard let data = try? encoder.encode(export) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}
