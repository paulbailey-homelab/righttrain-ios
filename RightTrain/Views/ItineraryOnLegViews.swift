import SwiftUI

struct ItineraryOnLegView: View {
    @Environment(ActiveWindowViewModel.self) private var activeWindowViewModel
    var itinerary: ItinerarySubscription
    var approachingInterchange: Bool
    var loadDetail: (ItineraryLeg) async -> Void

    private var presentation: ActiveItineraryPresentation {
        ActiveItineraryPresentation(itinerary: itinerary)
    }

    var body: some View {
        ActiveItineraryCard {
            if approachingInterchange {
                approachingBanner
            }

            currentTrainCard

            if let connection = itinerary.nextConnection, !approachingInterchange {
                connectionCard(connection)
            }

            if let onward = itinerary.onwardLeg {
                onwardCard(onward)
            }

            if presentation.canBoardOnwardLeg, let onwardLeg = itinerary.onwardLeg {
                Button {
                    Task {
                        await activeWindowViewModel.boardItineraryLeg(onwardLeg.legIndex, itineraryID: itinerary.id)
                    }
                } label: {
                    Label("I'm on the next train", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.rtPrimary)
                .accessibilityIdentifier("active-itinerary-board-onward-leg")
            }
        }
        .background {
            ActiveItineraryHeader(presentation: presentation, recoveryFromCrs: presentation.recoveryFromCrs)
        }
    }

    /// The one thing to do next, at the same scale as the direct Pin's
    /// hero: where to get off, and the platform to walk to.
    private var approachingBanner: some View {
        let title = if let connection = itinerary.nextConnection {
            "Get off at \(ItineraryFormatting.approachingConnectionText(connection))"
        } else {
            "Get off at the interchange"
        }
        let onward = itinerary.onwardLeg
        let onwardPlatform = onward.flatMap { nonEmptyPlatform($0.realtimePlatform) ?? nonEmptyPlatform($0.originPlatform) }

        return HStack(alignment: .lastTextBaseline, spacing: RTSpacing.compact) {
            VStack(alignment: .leading, spacing: 2) {
                Label(title, systemImage: "figure.walk.diamond.fill")
                    .font(.headline)
                    .labelStyle(.titleAndIcon)
                    .fixedSize(horizontal: false, vertical: true)
                if let onward {
                    Text(onwardHeroLine(onward))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(connectionTint)
                        .monospacedDigit()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let onwardPlatform {
                VStack(alignment: .trailing, spacing: 0) {
                    Text("Next platform")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(onwardPlatform)
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.rightTrainAmber)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                .fixedSize(horizontal: true, vertical: false)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var connectionTint: Color {
        guard let connection = itinerary.nextConnection else {
            return .secondary
        }
        switch connection.risk.status {
        case "missed":
            return .rightTrainDanger
        case "at_risk", "tight":
            return .rightTrainAmber
        default:
            return .secondary
        }
    }

    private func onwardHeroLine(_ leg: ItineraryLeg) -> String {
        var parts = ["Next \(ItineraryFormatting.timeText(leg.expectedDeparture ?? leg.scheduledDeparture))"]
        if let connection = itinerary.nextConnection {
            parts.append(riskText(connection))
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var currentTrainCard: some View {
        if let leg = itinerary.currentLeg {
            Button {
                Task { await loadDetail(leg) }
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(legTitle(leg))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                            Spacer()
                            Text("Arr \(ItineraryFormatting.timeText(leg.expectedArrival ?? leg.scheduledArrival))")
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                                .foregroundStyle(.primary)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(legTitle(leg))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text("Arr \(ItineraryFormatting.timeText(leg.expectedArrival ?? leg.scheduledArrival))")
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                                .foregroundStyle(.primary)
                        }
                    }
                    Text(currentLegSummary(leg))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                .itineraryLegRowChrome(systemImage: "tram.fill", showsDivider: approachingInterchange)
            }
            .buttonStyle(.plain)
        }
    }

    private func connectionCard(_ connection: ItineraryConnection) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    connectionTitle(connection)
                    Spacer()
                    StatusPill(text: riskBadge(connection), tone: ItineraryFormatting.connectionTone(connection))
                        .fixedSize()
                }
                VStack(alignment: .leading, spacing: 6) {
                    connectionTitle(connection)
                    StatusPill(text: riskBadge(connection), tone: ItineraryFormatting.connectionTone(connection))
                        .fixedSize()
                }
            }
            Text(ItineraryFormatting.connectionTransferText(connection))
                .font(.caption)
                .foregroundStyle(.secondary)
            if let advice = ItineraryFormatting.connectionAdviceText(connection) {
                Text(advice)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.top, RTSpacing.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Divider() }
        .lightSurfaceForeground()
        // Interchange risk must reach VoiceOver as text — the pill colour
        // alone is not a status signal.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(connectionAccessibilityLabel(connection))
    }

    private func connectionAccessibilityLabel(_ connection: ItineraryConnection) -> String {
        var parts = [
            "Connection: \(riskBadge(connection))",
            riskText(connection),
            ItineraryFormatting.connectionTransferText(connection)
        ]
        if let advice = ItineraryFormatting.connectionAdviceText(connection) {
            parts.append(advice)
        }
        return parts.joined(separator: ", ")
    }

    private func connectionTitle(_ connection: ItineraryConnection) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.swap")
                .foregroundStyle(ItineraryFormatting.connectionTone(connection).color)
            Text(approachingInterchange ? "Connection margin" : ItineraryFormatting.connectionTitleText(connection))
                .font(.subheadline.weight(.semibold))
        }
    }

    private func onwardCard(_ leg: ItineraryLeg) -> some View {
        Button {
            Task { await loadDetail(leg) }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Then to \(JourneyFormatting.stationDisplayName(name: leg.destinationName, fallback: leg.destinationCrs))")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Spacer()
                        Text("Arr \(ItineraryFormatting.timeText(leg.expectedArrival ?? leg.scheduledArrival))")
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Then to \(JourneyFormatting.stationDisplayName(name: leg.destinationName, fallback: leg.destinationCrs))")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("Arr \(ItineraryFormatting.timeText(leg.expectedArrival ?? leg.scheduledArrival))")
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                    }
                }
                Text(onwardSummary(leg))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
            .itineraryLegRowChrome(systemImage: "tram")
        }
        .buttonStyle(.plain)
    }

    private func legTitle(_ leg: ItineraryLeg) -> String {
        ItineraryFormatting.legRouteText(leg)
    }

    /// Platforms are labelled: a bare "4" beside an operator name reads as
    /// anything but a platform.
    private func currentLegSummary(_ leg: ItineraryLeg) -> String {
        var parts: [String] = []
        if let platform = nonEmptyPlatform(leg.destinationRealtime?.platform) ?? nonEmptyPlatform(leg.destinationPlatform) {
            parts.append("Arrives platform \(platform)")
        }
        if let op = JourneyFormatting.operatorSummaryText(leg.journeyResult) {
            parts.append(op)
        }
        return parts.joined(separator: " · ")
    }

    private func onwardSummary(_ leg: ItineraryLeg) -> String {
        var parts = ["Dep \(ItineraryFormatting.timeText(leg.expectedDeparture ?? leg.scheduledDeparture))"]
        if let platform = nonEmptyPlatform(leg.realtimePlatform) ?? nonEmptyPlatform(leg.originPlatform) {
            parts.append("Platform \(platform)")
        }
        if let op = JourneyFormatting.operatorSummaryText(leg.journeyResult) {
            parts.append(op)
        }
        return parts.joined(separator: " · ")
    }

    private func riskText(_ connection: ItineraryConnection) -> String {
        switch connection.risk.status {
        case "missed":
            return "missed"
        case "at_risk":
            return "\(max(connection.expectedMarginMinutes, 0)) min to change"
        case "tight":
            return "Tight \(connection.expectedMarginMinutes) min change"
        default:
            return "\(connection.expectedMarginMinutes) min to change"
        }
    }

    private func riskBadge(_ connection: ItineraryConnection) -> String {
        switch connection.risk.status {
        case "missed":
            return "Missed"
        case "at_risk":
            return "At risk"
        case "tight":
            return "Tight"
        default:
            return "On time"
        }
    }

    private func nonEmptyPlatform(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

/// Final-leg perspective: no more connections to make, so keep the focus on
/// arrival while retaining stop-monitoring in the common menu.
struct ItineraryOnFinalLegView: View {
    var itinerary: ItinerarySubscription
    var loadDetail: (ItineraryLeg) async -> Void

    private var presentation: ActiveItineraryPresentation {
        ActiveItineraryPresentation(itinerary: itinerary)
    }

    var body: some View {
        ActiveItineraryCard {
            if let leg = itinerary.currentLeg {
                arrivalCard(leg)
                finalLegNextStep(leg)
            }
        }
        .background {
            ActiveItineraryHeader(presentation: presentation)
        }
    }

    private func arrivalCard(_ leg: ItineraryLeg) -> some View {
        Button {
            Task { await loadDetail(leg) }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Arriving at \(JourneyFormatting.stationDisplayName(name: leg.destinationName, fallback: leg.destinationCrs))")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Spacer()
                        HStack(alignment: .center, spacing: 8) {
                            Text(ItineraryFormatting.timeText(leg.expectedArrival ?? leg.scheduledArrival))
                                .font(.title3.weight(.semibold).monospacedDigit())
                                .foregroundStyle(.primary)
                            PlatformSquareChip(
                                platform: ActiveWindowPresentation.PlatformDisplay(
                                    primary: nonEmptyPlatform(leg.destinationRealtime?.platform) ?? nonEmptyPlatform(leg.destinationPlatform) ?? "TBC",
                                    secondary: nil,
                                    confirmed: leg.destinationRealtime?.platformConfirmed == true
                                ),
                                style: .compact,
                                label: "Arr"
                            )
                        }
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Arriving at \(JourneyFormatting.stationDisplayName(name: leg.destinationName, fallback: leg.destinationCrs))")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        HStack(alignment: .center, spacing: 8) {
                            Text(ItineraryFormatting.timeText(leg.expectedArrival ?? leg.scheduledArrival))
                                .font(.title3.weight(.semibold).monospacedDigit())
                                .foregroundStyle(.primary)
                            PlatformSquareChip(
                                platform: ActiveWindowPresentation.PlatformDisplay(
                                    primary: nonEmptyPlatform(leg.destinationRealtime?.platform) ?? nonEmptyPlatform(leg.destinationPlatform) ?? "TBC",
                                    secondary: nil,
                                    confirmed: leg.destinationRealtime?.platformConfirmed == true
                                ),
                                style: .compact,
                                label: "Arr"
                            )
                        }
                    }
                }
                if !arrivalSummary(leg).isEmpty {
                    Text(arrivalSummary(leg))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.rightTrainInsetFill, in: RoundedRectangle(cornerRadius: RTRadius.chip))
            .lightSurfaceForeground()
        }
        .buttonStyle(.plain)
    }

    private func arrivalSummary(_ leg: ItineraryLeg) -> String {
        ItineraryFormatting.legSummaryText(
            leg,
            includesTimes: false,
            includesPlatform: false,
            includesStatus: false
        )
    }

    private func finalLegNextStep(_ leg: ItineraryLeg) -> some View {
        let destination = JourneyFormatting.stationDisplayName(name: leg.destinationName, fallback: leg.destinationCrs)
        let arrival = ItineraryFormatting.timeText(leg.expectedArrival ?? leg.scheduledArrival)
        let platform = nonEmptyPlatform(leg.destinationRealtime?.platform) ?? nonEmptyPlatform(leg.destinationPlatform)

        return HStack(alignment: .top, spacing: RTSpacing.listItem) {
            Image(systemName: "figure.walk")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.rightTrainActionInk)
                .frame(width: RTSize.iconSmall)

            VStack(alignment: .leading, spacing: 4) {
                Text(finalLegNextStepTitle(destination: destination, platform: platform))
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text("Arrival is due at \(arrival). RightTrain will keep this Journey Pin live until you arrive.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(Color.rightTrainActionInk.opacity(0.08), in: RoundedRectangle(cornerRadius: RTRadius.chip))
    }

    private func finalLegNextStepTitle(destination: String, platform: String?) -> String {
        if let platform {
            return "Get ready to leave at \(destination), platform \(platform)"
        }
        return "Get ready to leave at \(destination)"
    }

    private func nonEmptyPlatform(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

private extension View {
    /// A tappable leg inside an itinerary card: icon column, content, chevron,
    /// separated from the row above by a hairline instead of a filled box.
    func itineraryLegRowChrome(systemImage: String, showsDivider: Bool = true) -> some View {
        HStack(alignment: .center, spacing: RTSpacing.compact) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.rightTrainActionInk)
                .frame(width: RTSize.iconSmall)
                .accessibilityHidden(true)
            self
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.top, showsDivider ? RTSpacing.small : 0)
        .overlay(alignment: .top) {
            if showsDivider { Divider() }
        }
        .contentShape(Rectangle())
        .lightSurfaceForeground()
    }
}
