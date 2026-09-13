import SwiftUI

struct LinkedDevicesView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @State private var deviceToRevoke: LinkedDevice?

    var body: some View {
        List {
            Section {
                ForEach(authViewModel.linkedDevices) { device in
                    linkedDeviceRow(device)
                }
            } header: {
                Label("Devices", systemImage: "iphone.gen3")
            } footer: {
                Text("Labels are limited to platform, device class, app version, and recent activity. RightTrain does not show raw device identifiers here.")
            }
        }
        .navigationTitle("Linked Devices")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await authViewModel.refreshLinkedDevices()
        }
        .refreshable {
            await authViewModel.refreshLinkedDevices()
        }
        .confirmationDialog(
            "Revoke this device?",
            isPresented: Binding {
                deviceToRevoke != nil
            } set: { isPresented in
                if !isPresented {
                    deviceToRevoke = nil
                }
            },
            titleVisibility: .visible
        ) {
            Button("Revoke Device", role: .destructive) {
                guard let deviceToRevoke else { return }
                Task { await authViewModel.revokeLinkedDevice(deviceToRevoke) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("That device will need to log in again before it can read or change synced preferences.")
        }
    }

    private func linkedDeviceRow(_ device: LinkedDevice) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: device.deviceClass.localizedCaseInsensitiveContains("pad") ? "ipad" : "iphone")
                .foregroundStyle(Color.rightTrainActionInk)
                .frame(width: RTSize.iconMedium)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(deviceTitle(device))
                        .font(.headline)
                    if device.currentDevice {
                        Text("This device")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.rightTrainActionInk)
                    }
                }

                Text(deviceSubtitle(device))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            if device.state == "revoked" {
                Text("Revoked")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.rightTrainDanger)
            } else if !device.currentDevice {
                Button(role: .destructive) {
                    deviceToRevoke = device
                } label: {
                    Image(systemName: "xmark.circle")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Revoke \(deviceTitle(device))")
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private func deviceTitle(_ device: LinkedDevice) -> String {
        [device.platform, device.deviceClass]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func deviceSubtitle(_ device: LinkedDevice) -> String {
        var parts: [String] = []
        if let appVersion = device.appVersion, !appVersion.isEmpty {
            parts.append("App \(appVersion)")
        }
        if let buildNumber = device.buildNumber, !buildNumber.isEmpty {
            parts.append("Build \(buildNumber)")
        }
        if let lastSeenAt = device.lastSeenAt {
            parts.append("Seen \(lastSeenAt.formatted(date: .abbreviated, time: .shortened))")
        }
        if parts.isEmpty {
            return "No recent activity"
        }
        return parts.joined(separator: " · ")
    }
}
