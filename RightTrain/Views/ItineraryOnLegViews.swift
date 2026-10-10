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
        TimelineView(.periodic(from: .now, by: 30)) { context in
            ActiveItineraryCard {
                // Approaching the change the onward train's platform
                // indicator is the sign, since its platform is the one to
                // walk to; otherwise it's the carriage display for this leg.
                if approachingInterchange, let onward = itinerary.onwardLeg {
                    legSign(onward) {
                        PlatformIndicatorSign(
                            journey: onward.journeyResult,
                            platform: PlatformValue(onwardPlatform(onward), confirmed: onward.realtimePlatformConfirmed),
                            message: approachingMessage(onward),
                            now: context.date
                        )
                    }
                } else if let leg = itinerary.currentLeg {
                    legSign(leg) {
                        OnBoardSign(
                            journey: leg.journeyResult,
                            message: BoardText.arrivingMessage(leg.journeyResult, extra: changeNote),
                            now: context.date
                        )
                    }
                }

                if let connection = itinerary.nextConnection, !approachingInterchange {
                    connectionCard(connection)
                }

                if let onward = itinerary.onwardLeg, !approachingInterchange {
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
        }
        .background {
            ActiveItineraryHeader(presentation: presentation, recoveryFromCrs: presentation.recoveryFromCrs)
        }
    }

    /// A sign that opens the leg's calling points.
    private func legSign<Sign: View>(_ leg: ItineraryLeg, @ViewBuilder sign: () -> Sign) -> some View {
        Button {
            Task { await loadDetail(leg) }
        } label: {
            sign()
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows the train's calling points")
    }

    /// "Change here for the 10:12 to Leeds, platform 4." on the leg before
    /// a change.
    private var changeNote: String? {
        guard let onward = itinerary.onwardLeg else {
            return nil
        }
        if itinerary.nextConnection?.risk.status == "missed" {
            return "Connection missed."
        }
        let time = ItineraryFormatting.timeText(onward.expectedDeparture ?? onward.scheduledDeparture)
        var note = "Change here for the \(time) to \(BoardText.destination(onward.journeyResult))"
        if let platform = onwardPlatform(onward) {
            note += ", platform \(platform)"
        }
        return note + "."
    }

    /// "Change at Stevenage.  6 min to change." above any delay reason.
    private func approachingMessage(_ onward: ItineraryLeg) -> String {
        var sentences: [String] = []
        if let connection = itinerary.nextConnection {
            sentences.append("Change at \(ItineraryFormatting.approachingConnectionText(connection)).")
            sentences.append(connection.risk.status == "missed" ? "Connection missed." : "\(riskText(connection).prefix(1).uppercased())\(riskText(connection).dropFirst()).")
        }
        if let reason = onward.lateReasonText?.trimmingCharacters(in: .whitespacesAndNewlines), !reason.isEmpty {
            sentences.append(reason.hasSuffix(".") ? reason : "\(reason).")
        }
        return sentences.joined(separator: "  ")
    }

    private func onwardPlatform(_ leg: ItineraryLeg) -> String? {
        nonEmptyPlatform(leg.realtimePlatform) ?? nonEmptyPlatform(leg.originPlatform)
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

/// Final-leg perspective: no more connections to make, so the carriage
/// display for the last train is the whole card.
struct ItineraryOnFinalLegView: View {
    var itinerary: ItinerarySubscription
    var loadDetail: (ItineraryLeg) async -> Void

    private var presentation: ActiveItineraryPresentation {
        ActiveItineraryPresentation(itinerary: itinerary)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            ActiveItineraryCard {
                if let leg = itinerary.currentLeg {
                    Button {
                        Task { await loadDetail(leg) }
                    } label: {
                        OnBoardSign(
                            journey: leg.journeyResult,
                            message: BoardText.arrivingMessage(leg.journeyResult),
                            now: context.date
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Shows the train's calling points")
                }
            }
        }
        .background {
            ActiveItineraryHeader(presentation: presentation)
        }
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
