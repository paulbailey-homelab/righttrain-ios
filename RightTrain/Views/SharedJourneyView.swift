import SwiftUI

struct SharedJourneyStandaloneView: View {
    @Environment(AppCoordinator.self) private var appCoordinator
    var shareID: String

    var body: some View {
        NavigationStack {
            SharedJourneyView(shareID: shareID)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            appCoordinator.dismissSharedJourney()
                        }
                    }
                }
        }
    }
}

struct SharedJourneyPresentation {
    var journey: PublicJourneyShare
    var now: Date = Date()

    var isExpired: Bool {
        Self.isExpired(journey, now: now)
    }

    var statusText: String {
        Self.statusText(status: journey.status, statusText: journey.statusText)
    }

    var statusTone: StatusPill.Tone {
        Self.statusTone(status: journey.status, statusText: journey.statusText)
    }

    var freshnessText: String {
        "Updated \(SharedJourneyFormatting.relativeText(journey.refreshedAt))"
    }

    static func isExpired(_ journey: PublicJourneyShare, now: Date = Date()) -> Bool {
        journey.expiresAt <= now
    }

    static func statusText(status: String, statusText: String) -> String {
        let explicit = statusText.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = explicit.isEmpty ? status : explicit
        switch candidate.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "on_time", "on time", "ontime", "scheduled":
            return "On time"
        case "delayed", "late":
            return "Delayed"
        case "cancelled", "canceled":
            return "Cancelled"
        case "departed":
            return "Departed"
        case "arrived", "complete", "completed":
            return "Arrived"
        case "unreported", "unknown":
            return "Status unavailable"
        default:
            break
        }
        if !explicit.isEmpty {
            return explicit
        }

        return "Status unavailable"
    }

    static func statusTone(status: String, statusText: String) -> StatusPill.Tone {
        let value = "\(status) \(statusText)".lowercased()
        if value.contains("cancel") {
            return .red
        }
        if value.contains("delay") || value.contains("late") || value.contains("risk") {
            return .amber
        }
        if value.contains("time") || value.contains("live") || value.contains("arrived") || value.contains("departed") {
            return .green
        }
        return .accent
    }
}

struct SharedJourneyView: View {
    @Environment(AppCoordinator.self) private var appCoordinator
    var shareID: String

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            if let journey = appCoordinator.sharedJourney(for: shareID) {
                let presentation = SharedJourneyPresentation(journey: journey, now: context.date)
                if presentation.isExpired {
                    sharedUnavailableState(
                        title: "Shared journey expired",
                        message: "This public journey view is no longer available. Ask the sender for a fresh RightTrain link.",
                        symbolName: "clock.badge.exclamationmark"
                    )
                } else {
                    sharedJourneyContent(journey, presentation: presentation)
                }
            } else {
                sharedUnavailableState(
                    title: "Journey unavailable",
                    message: "RightTrain could not load this shared journey. The link may be expired, removed, or unsafe to show publicly.",
                    symbolName: "link"
                )
            }
        }
    }

    private func sharedJourneyContent(
        _ journey: PublicJourneyShare,
        presentation: SharedJourneyPresentation
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RTSpacing.sectionGap) {
                VStack(alignment: .leading, spacing: RTSpacing.compact) {
                    HStack(alignment: .firstTextBaseline) {
                        StatusPill(text: presentation.statusText, tone: presentation.statusTone)
                        Spacer(minLength: RTSpacing.small)
                        LiveFreshnessText(text: presentation.freshnessText)
                    }

                    Text(journey.routeTitle)
                        .font(.title.weight(.bold))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(alignment: .top, spacing: RTSpacing.compact) {
                    MetricView(label: "Dep", value: SharedJourneyFormatting.timeText(journey.expectedDeparture ?? journey.scheduledDeparture))
                    MetricView(label: "Arr", value: SharedJourneyFormatting.timeText(journey.expectedArrival ?? journey.scheduledArrival))
                }

                NextActionCallout(text: "Use this as a read-only live check.", tone: presentation.statusTone)

                if let position = journey.currentPosition {
                    VStack(alignment: .leading, spacing: RTSpacing.small) {
                        SectionHeader(
                            title: "Current position",
                            subtitle: position.description,
                            tone: presentation.statusTone
                        )
                        ProgressView(value: SharedJourneyFormatting.progressValue(position.progress))
                            .tint(presentation.statusTone.color)
                        if let upcomingStopName = position.upcomingStopName {
                            Text("Next: \(upcomingStopName)")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .rtCard()
                }

                if let disruptions = journey.disruptions, !disruptions.isEmpty {
                    VStack(alignment: .leading, spacing: RTSpacing.small) {
                        Text("Updates")
                            .font(.headline)
                        ForEach(disruptions, id: \.self) { disruption in
                            Label(disruption, systemImage: "exclamationmark.triangle.fill")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Color.rightTrainWarnInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                if let legs = journey.legs, !legs.isEmpty {
                    sharedLegsSection(legs)
                }

                Text("Link expires \(SharedJourneyFormatting.timeText(journey.expiresAt)).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, RTSpacing.pageHorizontal)
            .padding(.vertical, RTSpacing.pageVertical)
            .lightSurfaceForeground()
        }
        .background(Color.rightTrainSurfaceCream.ignoresSafeArea())
        .safeAreaBar(edge: .bottom) {
            sharedLinkActions(journey)
        }
        .navigationTitle("Shared Journey")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func sharedLegsSection(_ legs: [JourneyShareLeg]) -> some View {
        VStack(alignment: .leading, spacing: RTSpacing.listItem) {
            Text("Journey legs")
                .font(.headline)
            ForEach(legs) { leg in
                let tone = statusTone(for: leg)
                VStack(alignment: .leading, spacing: RTSpacing.small) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(leg.originName) to \(leg.destinationName)")
                            .font(.subheadline.weight(.semibold))
                        Spacer(minLength: RTSpacing.small)
                        StatusPill(text: SharedJourneyPresentation.statusText(status: leg.status, statusText: leg.statusText), tone: tone)
                    }
                    HStack(alignment: .top, spacing: RTSpacing.compact) {
                        MetricView(label: "Dep", value: SharedJourneyFormatting.timeText(leg.expectedDeparture ?? leg.scheduledDeparture))
                        MetricView(label: "Arr", value: SharedJourneyFormatting.timeText(leg.expectedArrival ?? leg.scheduledArrival))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .rtCard(padding: RTSpacing.compact)
            }
        }
    }

    /// Open/Install float above the shared journey on Liquid Glass; opening
    /// in the app is the tinted primary action.
    private func sharedLinkActions(_ journey: PublicJourneyShare) -> some View {
        GlassEffectContainer(spacing: RTSpacing.small) {
            HStack(spacing: RTSpacing.small) {
                if let appStoreURL = journey.appStoreUrl.flatMap(URL.init(string:)) {
                    Link(destination: appStoreURL) {
                        Label("Install", systemImage: "arrow.down.app")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                }
                if let appURL = URL(string: journey.appUrl) {
                    Link(destination: appURL) {
                        Label("Open in RightTrain", systemImage: "arrow.up.forward.app")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Color.rightTrainOnAccent)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .layoutPriority(1)
                }
            }
            .controlSize(.extraLarge)
            .padding(.horizontal, RTSpacing.pageHorizontal + 4)
            .padding(.bottom, RTSpacing.small)
        }
    }

    private func sharedUnavailableState(title: String, message: String, symbolName: String) -> some View {
        ContentUnavailableView(title, systemImage: symbolName, description: Text(message))
        .background(Color.rightTrainSurfaceCream.ignoresSafeArea())
        .navigationTitle("Shared Journey")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func statusTone(for journey: PublicJourneyShare) -> StatusPill.Tone {
        SharedJourneyPresentation.statusTone(status: journey.status, statusText: journey.statusText)
    }

    private func statusTone(for leg: JourneyShareLeg) -> StatusPill.Tone {
        SharedJourneyPresentation.statusTone(status: leg.status, statusText: leg.statusText)
    }
}

private enum SharedJourneyFormatting {
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    static func timeText(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }

    static func relativeText(_ date: Date) -> String {
        relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    static func progressValue(_ progress: Double) -> Double {
        min(max(progress, 0), 1)
    }
}
