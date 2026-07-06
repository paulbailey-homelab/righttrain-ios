import SwiftUI
import UIKit
import UserNotifications

struct NotificationPermissionView: View {
    @Environment(NotificationViewModel.self) private var viewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "When journeys change", subtitle: subtitle)

            HStack(spacing: RTSpacing.listItem) {
                Label("Notifications", systemImage: statusIcon)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                StatusPill(text: statusTitle, tone: statusTone)
            }

            if !isEnabledState {
                Button {
                    Task { await handlePrimaryAction() }
                } label: {
                    Label(buttonTitle, systemImage: buttonIcon)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
        .padding(RTSpacing.cardPadding)
        .background(Color.rightTrainSurface, in: RoundedRectangle(cornerRadius: RTRadius.card))
    }

    private var subtitle: String {
        switch viewModel.notificationStatus {
        case .authorized, .provisional:
            return "Get notified about platform changes, cancellations, delays, and better options."
        case .denied:
            return "In-app monitoring still works. Turn notifications back on if you want journey changes to reach you outside the app."
        case .notDetermined:
            return "Allow notifications so journey changes can reach you outside the app."
        case .ephemeral:
            return "Temporary notifications are active for this device."
        @unknown default:
            return "Notification permission state could not be read."
        }
    }

    private var statusTitle: String {
        switch viewModel.notificationStatus {
        case .authorized, .provisional:
            return "Enabled"
        case .denied:
            return "Blocked"
        case .notDetermined:
            return "Not enabled"
        case .ephemeral:
            return "Temporary"
        @unknown default:
            return "Unknown"
        }
    }

    private var statusIcon: String {
        switch viewModel.notificationStatus {
        case .authorized, .provisional, .ephemeral:
            return "bell.badge.fill"
        case .denied:
            return "bell.slash.fill"
        case .notDetermined:
            return "bell"
        @unknown default:
            return "questionmark.circle"
        }
    }

    private var statusTone: StatusPill.Tone {
        switch viewModel.notificationStatus {
        case .authorized, .provisional, .ephemeral:
            return .green
        case .denied:
            return .red
        case .notDetermined:
            return .amber
        @unknown default:
            return .accent
        }
    }

    private var buttonTitle: String {
        switch viewModel.notificationStatus {
        case .authorized, .provisional, .ephemeral:
            return "Enabled"
        case .denied:
            return "Open Settings"
        default:
            return "Allow alerts"
        }
    }

    private var buttonIcon: String {
        viewModel.notificationStatus == .denied ? "gear" : "bell"
    }

    private var isEnabledState: Bool {
        switch viewModel.notificationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        default:
            return false
        }
    }

    private func handlePrimaryAction() async {
        if viewModel.notificationStatus == .denied {
            openApplicationSettings()
            return
        }

        await viewModel.requestNotifications()
    }

    @MainActor
    private func openApplicationSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            return
        }

        UIApplication.shared.open(url)
    }
}
