import SwiftUI

struct NotificationDetailView: View {
    @Environment(AppCoordinator.self) private var appCoordinator
    var identity: WindowNotificationDetailIdentity

    var body: some View {
        if let detail = appCoordinator.notificationDetail(for: identity) {
            NotificationDetailContentView(detail: detail)
        } else {
            EmptyStateView(
                title: "Notification unavailable",
                message: "RightTrain could not load this journey update.",
                symbolName: "bell.slash",
                tint: .rightTrainActionInk
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, RTSpacing.pageHorizontal)
            .background(Color.rightTrainBackground.ignoresSafeArea())
            .navigationTitle("Notification")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct NotificationDetailContentView: View {
    @Environment(AppCoordinator.self) private var appCoordinator
    @Environment(\.dismiss) private var dismiss
    var detail: WindowSubscriptionNotificationDetail

    private var data: WindowNotificationData {
        detail.payload.data
    }

    private var affectedRecommendation: DirectWindowRecommendation? {
        data.departedRecommendation ?? data.affectedRecommendation ?? data.topRecommendation
    }

    private var nextRecommendation: DirectWindowRecommendation? {
        data.nextRecommendation ?? data.topRecommendation
    }

    private var isRecommendedDeparted: Bool {
        detail.eventType == "recommended_train_departed" || detail.payload.type == "recommended_train_departed"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RTSpacing.sectionGap) {
                VStack(alignment: .leading, spacing: RTSpacing.small) {
                    HStack(alignment: .firstTextBaseline) {
                        StatusPill(text: notificationPillText, tone: notificationTone)
                        Spacer(minLength: RTSpacing.small)
                        LiveFreshnessText(text: notificationFreshnessText)
                    }

                    Text(title)
                        .font(.title2.weight(.bold))
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                notificationActionPanel

                if let affectedRecommendation {
                    notificationTrainSection(
                        title: isRecommendedDeparted ? "Departed train" : "Affected train",
                        recommendation: affectedRecommendation
                    )
                }

                if isRecommendedDeparted, let nextRecommendation {
                    notificationTrainSection(title: "Next best train", recommendation: nextRecommendation)
                } else if !isRecommendedDeparted,
                          let nextRecommendation,
                          nextRecommendation.journey.serviceId != affectedRecommendation?.journey.serviceId {
                    notificationTrainSection(title: "Current recommendation", recommendation: nextRecommendation)
                }

                if isRecommendedDeparted {
                    VStack(spacing: RTSpacing.listItem) {
                        if let serviceID = data.departedTrainServiceId ?? data.departedRecommendation?.journey.serviceId {
                            Button {
                                completeNotificationAction {
                                    await appCoordinator.pinDepartedTrain(serviceID: serviceID, windowID: detail.windowSubscriptionId)
                                }
                            } label: {
                                Label("Pin this journey", systemImage: "pin")
                                    .frame(maxWidth: .infinity)
                            }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }

                        Button {
                            completeNotificationAction {
                                await appCoordinator.monitorNextBestAfterDepartedTrain(
                                    serviceID: data.departedTrainServiceId ?? data.departedRecommendation?.journey.serviceId,
                                    windowID: detail.windowSubscriptionId
                                )
                            }
                        } label: {
                            Label("Keep search pinned", systemImage: "arrow.forward.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, RTSpacing.pageHorizontal)
            .padding(.vertical, RTSpacing.pageVertical)
            .lightSurfaceForeground()
        }
        .background(Color.rightTrainSurfaceCream.ignoresSafeArea())
        .navigationTitle("Notification")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var notificationActionPanel: some View {
        VStack(alignment: .leading, spacing: RTSpacing.compact) {
            MetricView(label: "What changed", value: whatChangedText)
            MetricView(label: "Why it matters", value: whyItMattersText)
            NextActionCallout(text: nextActionText, tone: notificationTone)
        }
        .padding(RTSpacing.cardPadding)
        .background(Color.rightTrainPaperCream, in: RoundedRectangle(cornerRadius: RTRadius.card))
        .overlay {
            RoundedRectangle(cornerRadius: RTRadius.card)
                .stroke(notificationTone.color.opacity(0.28), lineWidth: 1)
        }
        .lightSurfaceForeground()
        .accessibilityElement(children: .combine)
    }

    private var notificationTone: StatusPill.Tone {
        switch detail.eventType {
        case "cancellation":
            return .red
        case "recommended_train_departed", "delay", "platform_change", "window_train_after_window":
            return .amber
        case "window_guidance_cleared":
            return .green
        default:
            return .accent
        }
    }

    private var notificationPillText: String {
        switch notificationTone {
        case .red, .amber:
            return "Action needed"
        case .green:
            return "Cleared"
        case .accent, .neutral:
            return "Live update"
        }
    }

    private var notificationFreshnessText: String {
        ActiveWindowPresentation.freshnessText(
            updatedAt: DateFormatting.date(from: detail.payload.occurredAt) ?? DateFormatting.date(from: detail.createdAt)
        )
    }

    private var title: String {
        switch detail.eventType {
        case "recommended_train_departed":
            return "Recommended train left"
        case "delay":
            return "Delay update"
        case "platform_change":
            return "Platform changed"
        case "cancellation":
            return "Train cancelled"
        case "window_guidance_cleared":
            return "Disruption cleared"
        case "window_train_entered_window", "window_train_after_window":
            return "Search Pin update"
        default:
            return "Train update"
        }
    }

    private var summary: String {
        whatChangedText
    }

    private var whatChangedText: String {
        if isRecommendedDeparted,
           let departed = data.departedRecommendation,
           let next = nextRecommendation {
            return "\(trainReference(departed)) has left. Next best is \(notificationDepartureText(next))."
        }
        if detail.eventType == "window_train_entered_window" || detail.payload.type == "window_train_entered_window" {
            return "The delayed \(windowBoundaryDepartureText) is now expected to depart during your pinned search."
        }
        if detail.eventType == "window_train_after_window" || detail.payload.type == "window_train_after_window" {
            return "The delayed \(windowBoundaryDepartureText) may now depart after your pinned search."
        }
        if let platform = data.platform, let affected = affectedRecommendation {
            if let previous = data.previousPlatform, !previous.isEmpty, previous != platform {
                return "\(trainReference(affected)) moved from platform \(previous) to platform \(platform)."
            }
            return "\(trainReference(affected)) is now platform \(platform)."
        }
        if detail.eventType == "cancellation", let affected = affectedRecommendation {
            return "\(trainReference(affected)) has been cancelled."
        }
        if detail.eventType == "delay", let affected = affectedRecommendation {
            return "\(trainReference(affected)) is delayed."
        }
        if let affected = affectedRecommendation {
            return "\(trainReference(affected)) changed."
        }
        return "RightTrain updated this Search Pin."
    }

    private var whyItMattersText: String {
        switch detail.eventType {
        case "recommended_train_departed":
            return "Your previous best option has already left, so the pinned search now needs a decision."
        case "delay":
            return "The departure or arrival timing may no longer match the window you chose."
        case "platform_change":
            return "The train may leave from a different platform than the one you were watching."
        case "cancellation":
            return "The selected train is no longer usable for this journey."
        case "window_train_entered_window":
            return "A delayed train has moved into your monitored window and may now be useful."
        case "window_train_after_window":
            return "A delayed train may leave too late for the journey window you pinned."
        case "window_guidance_cleared":
            return "The disruption RightTrain was tracking no longer needs extra action."
        default:
            return "The live recommendation changed since the Pin was last checked."
        }
    }

    private var nextActionText: String {
        switch detail.eventType {
        case "recommended_train_departed":
            return "Pin it if you boarded; otherwise keep the search pinned for the next best train."
        case "delay":
            return "Check the updated departure before leaving."
        case "platform_change":
            return data.platform.map { "Use platform \($0) and keep watching for changes." }
                ?? "Check the platform before boarding."
        case "cancellation":
            return "Avoid this train and use the next recommended option."
        case "window_train_entered_window":
            return "Review whether this delayed train now fits your journey."
        case "window_train_after_window":
            return "Review alternatives before committing to this train."
        case "window_guidance_cleared":
            return "Keep your Pin open; no extra action is needed."
        default:
            return "Open the affected journey and check the latest status."
        }
    }

    private func notificationTrainSection(title: String, recommendation: DirectWindowRecommendation) -> some View {
        let columns = [
            GridItem(.flexible(), alignment: .leading),
            GridItem(.flexible(), alignment: .leading),
            GridItem(.flexible(), alignment: .leading)
        ]
        return VStack(alignment: .leading, spacing: RTSpacing.listItem) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: RTSpacing.small) {
                HStack(alignment: .firstTextBaseline, spacing: RTSpacing.small) {
                    Text(trainReference(recommendation))
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: RTSpacing.small)
                    StatusPill(
                        text: JourneyFormatting.movementStatusText(recommendation.journey, score: recommendation.score),
                        tone: ActiveWindowPresentation.statusDisplay(for: recommendation).tone
                    )
                }

                LazyVGrid(columns: columns, alignment: .leading, spacing: RTSpacing.small) {
                    MetricView(label: "Dep", value: notificationDepartureText(recommendation))
                    MetricView(label: "Arr", value: JourneyFormatting.arrivalText(recommendation.journey))
                    MetricView(label: "Platform", value: JourneyFormatting.platformMetricText(recommendation.journey))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(RTSpacing.cardPadding)
            .background(Color.rightTrainSurface, in: RoundedRectangle(cornerRadius: RTRadius.card))
            .lightSurfaceForeground()
            .overlay {
                RoundedRectangle(cornerRadius: RTRadius.card)
                    .stroke(Color.rightTrainBorder, lineWidth: 1)
            }
        }
    }

    private func trainReference(_ recommendation: DirectWindowRecommendation) -> String {
        let journey = recommendation.journey
        let departure = notificationDepartureText(recommendation)
        return "\(departure) from \(journey.originName) to \(journey.destinationName)"
    }

    private func notificationDepartureText(_ recommendation: DirectWindowRecommendation) -> String {
        if JourneyFormatting.hasDelaySignal(journey: recommendation.journey, score: recommendation.score) {
            return "Delayed \(JourneyFormatting.departureDisplay(recommendation.journey).scheduledText)"
        }
        return JourneyFormatting.departureText(recommendation.journey)
    }

    private var windowBoundaryDepartureText: String {
        if let scheduledDepartureTime = data.scheduledDepartureTime, !scheduledDepartureTime.isEmpty {
            return scheduledDepartureTime
        }
        if let affectedRecommendation {
            return JourneyFormatting.departureDisplay(affectedRecommendation.journey).scheduledText
        }
        return "train"
    }

    private func completeNotificationAction(_ action: @escaping () async -> Void) {
        Task {
            await action()
            await MainActor.run {
                appCoordinator.selectedTab = AppTab.active
                dismiss()
            }
        }
    }
}
