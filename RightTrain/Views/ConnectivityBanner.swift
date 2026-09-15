import SwiftUI

struct ConnectivityStatusBanner: View {
    @Environment(ConnectivityService.self) private var connectivityService
    @Environment(JourneyMutationQueue.self) private var journeyMutationQueue
    @Environment(ActiveWindowViewModel.self) private var activeWindowViewModel

    var body: some View {
        if let content {
            HStack(spacing: RTSpacing.small) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(content.title)
                            .font(.footnote.weight(.semibold))
                        if let detail = content.detail {
                            Text(detail)
                                .font(.caption2)
                        }
                    }
                    .lineLimit(2)
                    .minimumScaleFactor(0.88)
                } icon: {
                    Image(systemName: content.systemImage)
                        .font(.footnote.weight(.semibold))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                if let retry = content.retryAction {
                    Button("Retry") {
                        retry()
                    }
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.plain)
                    .accessibilityLabel("Retry failed changes")
                }
                if let dismiss = content.dismissAction {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.footnote.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss")
                }
            }
            .foregroundStyle(content.foreground)
            .padding(.horizontal, RTSpacing.cardPadding)
            .padding(.vertical, RTSpacing.small + 2)
            // Floats above the app as a Liquid Glass capsule; failures and
            // offline state tint the glass so they read as status at a glance.
            .glassEffect(content.glass, in: .capsule)
            .padding(.horizontal, RTSpacing.pageHorizontal)
            .readableWidthFrame()
            .padding(.vertical, RTSpacing.xs)
        }
    }

    private var content: ConnectivityBannerContent? {
        if journeyMutationQueue.needsAttention {
            let retryableCount = journeyMutationQueue.retryableFailedCount
            let expiredCount = journeyMutationQueue.failedCount - retryableCount
            let detail = expiredCount > 0 && retryableCount == 0
                ? "\(changeText(expiredCount)) expired before syncing."
                : "\(changeText(journeyMutationQueue.failedCount)) couldn't be saved."
            return ConnectivityBannerContent(
                title: "Changes didn't save",
                detail: detail,
                systemImage: "exclamationmark.triangle.fill",
                foreground: .white,
                tint: Color.rightTrainDanger,
                dismissAction: { journeyMutationQueue.clearFailed() },
                retryAction: retryableCount > 0 ? {
                    journeyMutationQueue.retryFailed()
                    Task { await activeWindowViewModel.flushQueuedMutations() }
                } : nil
            )
        }
        if journeyMutationQueue.isSyncing {
            return ConnectivityBannerContent(
                title: "Syncing changes",
                detail: "\(changeText(journeyMutationQueue.pendingCount)) pending.",
                systemImage: "arrow.triangle.2.circlepath",
                foreground: .primary,
                tint: nil
            )
        }
        if connectivityService.backendUnavailable {
            let hasActiveJourney = activeWindowViewModel.hasActiveJourney
            let detail: String? = if journeyMutationQueue.pendingCount > 0 {
                "\(changeText(journeyMutationQueue.pendingCount)) queued."
            } else if hasActiveJourney {
                nil
            } else {
                "Showing saved journey data."
            }
            return ConnectivityBannerContent(
                title: hasActiveJourney ? "Offline · saved journey data" : "Offline",
                detail: detail,
                systemImage: "wifi.slash",
                // Amber, not red: tunnels make offline routine on a train,
                // and red stays reserved for changes that need a retry.
                foreground: .rightTrainOnAccent,
                tint: Color.rightTrainAmber
            )
        }
        if connectivityService.looksPatchy {
            let hasActiveJourney = activeWindowViewModel.hasActiveJourney
            return ConnectivityBannerContent(
                title: hasActiveJourney ? "Patchy connection · live data may lag" : "Patchy connection",
                detail: journeyMutationQueue.pendingCount > 0 ? "\(changeText(journeyMutationQueue.pendingCount)) queued." : nil,
                systemImage: "antenna.radiowaves.left.and.right",
                foreground: .primary,
                tint: Color.rightTrainAmber.opacity(0.6)
            )
        }
        if journeyMutationQueue.pendingCount > 0 {
            return ConnectivityBannerContent(
                title: "Sync pending",
                detail: "\(changeText(journeyMutationQueue.pendingCount)) queued.",
                systemImage: "clock.arrow.circlepath",
                foreground: .primary,
                tint: nil
            )
        }
        return nil
    }

    private func changeText(_ count: Int) -> String {
        count == 1 ? "1 journey change" : "\(count) journey changes"
    }
}

private struct ConnectivityBannerContent {
    var title: String
    var detail: String?
    var systemImage: String
    var foreground: Color
    /// Glass tint; nil keeps plain regular glass for informational states.
    var tint: Color?
    var dismissAction: (() -> Void)?
    var retryAction: (() -> Void)?

    var glass: Glass {
        guard let tint else { return .regular }
        return .regular.tint(tint)
    }
}
