import SwiftUI

struct BetaOnboardingView: View {
    @Environment(NotificationViewModel.self) private var notificationViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("righttrain.ios.betaOnboardingDismissed") private var isDismissed = false
    @AppStorage("righttrain.ios.betaOnboardingAutoCollapsed") private var hasAutoCollapsed = false
    @State private var isExpanded = false
    var forceExpanded = false

    var body: some View {
        if forceExpanded {
            expandedBanner
        } else if !isDismissed {
            Group {
                if isExpanded {
                    expandedBanner
                        .transition(reduceMotion ? .identity : .opacity.combined(with: .move(edge: .top)))
                } else {
                    collapsedChip
                        .transition(reduceMotion ? .identity : .opacity)
                }
            }
            .onAppear(perform: prepareInitialState)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: isExpanded)
        }
    }

    private var collapsedChip: some View {
        Button {
            isExpanded = true
        } label: {
            Label("Beta live guidance", systemImage: "testtube.2")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, RTSpacing.compact)
                .padding(.vertical, RTSpacing.small)
                .foregroundStyle(Color.rightTrainActionInk)
                .background(Color.rightTrainActionInk.opacity(0.10), in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(Color.rightTrainActionInk.opacity(0.26), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows beta guidance.")
    }

    private var expandedBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Label("Beta live guidance", systemImage: "testtube.2")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 12)
                Button {
                    isDismissed = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
                .accessibilityLabel("Dismiss beta guidance")
            }

            Text("RightTrain is in beta. Treat it as live guidance: useful for action-needed changes, still secondary to station boards and operator advice.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: RTSpacing.listItem) {
                BetaGuidanceRow(
                    title: "Action-needed alerts",
                    systemImage: "bell.badge",
                    message: notificationGuidance
                )
                BetaGuidanceRow(
                    title: "Travel checks",
                    systemImage: "exclamationmark.triangle",
                    message: "Check station boards and operator guidance before changing travel plans."
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .rtCard()
        .lightSurfaceForeground()
    }

    private func prepareInitialState() {
        isExpanded = !hasAutoCollapsed
        guard !hasAutoCollapsed else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !isDismissed, !hasAutoCollapsed else { return }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                isExpanded = false
            }
            hasAutoCollapsed = true
        }
    }

    private var notificationGuidance: String {
        switch notificationViewModel.notificationStatus {
        case .authorized, .provisional, .ephemeral:
            return "This device can receive platform, cancellation, delay, interchange-risk, and better-option alerts."
        case .denied:
            return "Notifications are blocked. In-app monitoring still works, but action-needed changes may wait until you reopen RightTrain."
        case .notDetermined:
            return "Allow alerts after sign-in if you want action-needed journey changes outside the app."
        @unknown default:
            return "Notification permission could not be read on this device."
        }
    }
}

private struct BetaGuidanceRow: View {
    var title: String
    var systemImage: String
    var message: String

    var body: some View {
        HStack(alignment: .top, spacing: RTSpacing.listItem) {
            Image(systemName: systemImage)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.rightTrainActionInk)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.footnote.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
