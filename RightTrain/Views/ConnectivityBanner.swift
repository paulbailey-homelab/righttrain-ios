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
            .padding(.horizontal, RTSpacing.pageHorizontal)
            .padding(.vertical, RTSpacing.small)
            .background(content.background)
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
                background: Color.rightTrainDanger,
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
                background: Color.rightTrainHighlight
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
                foreground: .white,
                background: Color.rightTrainDanger
            )
        }
        if connectivityService.looksPatchy {
            let hasActiveJourney = activeWindowViewModel.hasActiveJourney
            return ConnectivityBannerContent(
                title: hasActiveJourney ? "Patchy connection · live data may lag" : "Patchy connection",
                detail: journeyMutationQueue.pendingCount > 0 ? "\(changeText(journeyMutationQueue.pendingCount)) queued." : nil,
                systemImage: "antenna.radiowaves.left.and.right",
                foreground: .primary,
                background: Color.rightTrainAmber.opacity(0.28)
            )
        }
        if journeyMutationQueue.pendingCount > 0 {
            return ConnectivityBannerContent(
                title: "Sync pending",
                detail: "\(changeText(journeyMutationQueue.pendingCount)) queued.",
                systemImage: "clock.arrow.circlepath",
                foreground: .primary,
                background: Color.rightTrainSurface
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
    var background: Color
    var dismissAction: (() -> Void)?
    var retryAction: (() -> Void)?
}
