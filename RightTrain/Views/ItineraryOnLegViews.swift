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
        ActiveItineraryCard(
            borderColor: approachingInterchange ? Color.rightTrainAmber.opacity(RTOpacity.secondary) : Color.rightTrainInkFaint,
            borderWidth: approachingInterchange ? 2 : 1
        ) {
            ActiveItineraryHeader(presentation: presentation, recoveryFromCrs: presentation.recoveryFromCrs)

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
                .buttonStyle(.plain)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.rightTrainPaperCream)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Color.rightTrainActionInk, in: Capsule())
                .accessibilityIdentifier("active-itinerary-board-onward-leg")
            }
        }
    }

    private var approachingBanner: some View {
        let title = if let connection = itinerary.nextConnection {
            "Get off at \(ItineraryFormatting.approachingConnectionText(connection))"
        } else {
            "Get off at the interchange"
        }

        return HStack(alignment: .center, spacing: RTSpacing.listItem) {
            Image(systemName: "figure.walk.diamond.fill")
                .font(.title3)
                .foregroundStyle(Color.rightTrainAmber)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                if let onward = itinerary.onwardLeg {
                    Text(onwardHeroLine(onward))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(12)
        .background(Color.rightTrainAmber.opacity(0.12), in: RoundedRectangle(cornerRadius: RTRadius.chip))
    }

    private func onwardHeroLine(_ leg: ItineraryLeg) -> String {
        var parts: [String] = []
        if let platform = nonEmptyPlatform(leg.realtimePlatform) ?? nonEmptyPlatform(leg.originPlatform) {
            parts.append("platform \(platform)")
        }
        parts.append(ItineraryFormatting.timeText(leg.expectedDeparture ?? leg.scheduledDeparture))
        if let connection = itinerary.nextConnection {
            parts.append(riskText(connection))
        }
        return "Next: \(parts.joined(separator: " · "))"
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
                    Text(ItineraryFormatting.legSummaryText(leg, includesTimes: false, includesStatus: false))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.rightTrainSurfaceCream, in: RoundedRectangle(cornerRadius: RTRadius.chip))
                .lightSurfaceForeground()
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
        .padding(12)
        .background(Color.rightTrainBackground, in: RoundedRectangle(cornerRadius: RTRadius.chip))
        .lightSurfaceForeground()
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
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.rightTrainSurfaceCream, in: RoundedRectangle(cornerRadius: RTRadius.chip))
            .lightSurfaceForeground()
        }
        .buttonStyle(.plain)
    }

    private func legTitle(_ leg: ItineraryLeg) -> String {
        ItineraryFormatting.legRouteText(leg)
    }

    private func onwardSummary(_ leg: ItineraryLeg) -> String {
        var parts: [String] = []
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
            ActiveItineraryHeader(presentation: presentation)

            if let leg = itinerary.currentLeg {
                arrivalCard(leg)
                finalLegNextStep(leg)
            }
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
                                    secondary: nil
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
                                    secondary: nil
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
            .background(Color.rightTrainSurfaceCream, in: RoundedRectangle(cornerRadius: RTRadius.chip))
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
