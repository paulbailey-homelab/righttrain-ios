import SwiftUI

/// Direct-train search results, rendered as inset-grouped list sections.
/// Host inside a `List`.
struct RecommendationResultsView: View {
    var response: DirectWindowRecommendationResponse
    var canSearchRoutesWithChanges: Bool
    var pinWindow: () async -> Void
    var isJourneyPinned: (DirectWindowRecommendation) -> Bool
    var toggleJourneyPin: (DirectWindowRecommendation) async -> Void

    var body: some View {
        let recommendations = JourneyFormatting.chronologicalRecommendations(
            topRecommendation: response.topRecommendation,
            recommendations: response.recommendations
        )

        if recommendations.isEmpty {
            Section {
                EmptyStateView(
                    title: "No direct trains found",
                    message: canSearchRoutesWithChanges
                        ? "Try widening the departure window or switching to routes with changes."
                        : "RightTrain only finds direct trains for now, so journeys that need a change won't appear. Try a wider departure window."
                )
                .listRowInsets(EdgeInsets())
            }
        } else {
            // The route and window live in the navigation bar, and the
            // recommended train is marked in its row, so every train shares
            // one section in departure order.
            Section {
                ForEach(recommendations) { rec in
                    SearchDirectJourneyRow(
                        recommendation: rec,
                        emphasized: isTopRecommendation(rec),
                        isPinned: isJourneyPinned(rec),
                        pinJourney: { await toggleJourneyPin(rec) }
                    )
                }
            } header: {
                Text("\(recommendations.count) direct \(recommendations.count == 1 ? "train" : "trains")")
            }
        }
    }

    private func isTopRecommendation(_ recommendation: DirectWindowRecommendation) -> Bool {
        guard let topRecommendation = response.topRecommendation else {
            return recommendation.recommended
        }
        return recommendation.journey.serviceId == topRecommendation.journey.serviceId &&
            recommendation.journey.rid == topRecommendation.journey.rid &&
            recommendation.journey.ssd == topRecommendation.journey.ssd
    }
}

/// Toolbar button that turns the whole search into a Search Pin.
struct SearchPinToolbarButton: View {
    var recommendationCount: Int
    var action: () async -> Void

    var body: some View {
        Button {
            Task { await action() }
        } label: {
            Label("Pin Search", systemImage: "pin")
        }
        // The one tinted glass control on the results screen: pinning is its
        // primary action.
        .buttonStyle(.glassProminent)
        .accessibilityHint("Creates a Search Pin for \(recommendationCount) direct trains in this departure range.")
    }
}

struct ItineraryResultsView: View {
    var response: JourneyPlanResponse
    var isJourneyPinned: (ItineraryRecommendation) -> Bool
    var toggleJourneyPin: (ItineraryRecommendation) async -> Void
    var openLegDetail: (ItineraryLeg) async -> Void

    private var itineraries: [ItineraryRecommendation] {
        ItineraryFormatting.chronologicalItineraries(
            topItinerary: response.topItinerary,
            itineraries: response.itineraries
        )
    }

    var body: some View {
        if itineraries.isEmpty {
            Section {
                EmptyStateView(
                    title: "No trains found",
                    message: "Try adjusting your departure time or widening the departure window."
                )
                .listRowInsets(EdgeInsets())
            }
        } else {
            Section {
                ForEach(itineraries) { itinerary in
                    SearchItineraryJourneyRow(
                        itinerary: itinerary,
                        emphasized: isTopItinerary(itinerary),
                        isPinned: isJourneyPinned(itinerary),
                        pinJourney: { await toggleJourneyPin(itinerary) }
                    )
                }
            } header: {
                Text("\(itineraries.count) \(itineraries.count == 1 ? "route" : "routes")")
            }
        }
    }

    private func isTopItinerary(_ itinerary: ItineraryRecommendation) -> Bool {
        guard let topItinerary = response.topItinerary else {
            return itinerary.recommended
        }
        return itinerary.stableKey == topItinerary.stableKey
    }
}

// MARK: - Result rows

/// Icon + footnote status text with tight spacing (a list `Label` reserves a
/// wide icon column that looks detached inside a compact row).
private struct StatusIconText: View {
    var text: String
    var systemImage: String
    var color: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: systemImage)
                .accessibilityHidden(true)
            Text(text)
                .lineLimit(2)
        }
        .font(.footnote)
        .foregroundStyle(color)
    }
}

/// Departure-board style row: times, duration/operator, platform, pin toggle,
/// and a status line only when something is worth reading.
private struct SearchResultRowLayout<Status: View>: View {
    var departure: JourneyTimeDisplay
    var arrival: JourneyTimeDisplay
    var subtitle: String
    var isRecommended = false
    var platform: ActiveWindowPresentation.PlatformDisplay
    var isPinned: Bool
    var pinHint: String
    var unpinHint: String
    var pinJourney: () async -> Void
    @ViewBuilder var status: () -> Status

    var body: some View {
        HStack(alignment: .center, spacing: RTSpacing.compact) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    timeText(departure)
                    Image(systemName: "arrow.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                    timeText(arrival)
                }

                Text(subtitleText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                status()
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // A "P4" chip instead of a stacked "Platform / 4" column keeps
            // the times wide enough for delays.
            PlatformSquareChip(platform: platform, style: .compact)
                .fixedSize()

            PinJourneyIconButton(
                isPinned: isPinned,
                pinHint: pinHint,
                unpinHint: unpinHint,
                action: pinJourney
            )
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
    }

    private var subtitleText: AttributedString {
        var text = AttributedString()
        if isRecommended {
            var tag = AttributedString("Recommended")
            tag.foregroundColor = .rightTrainActionInk
            tag.font = .subheadline.weight(.semibold)
            text += tag
            if !subtitle.isEmpty {
                text += AttributedString(" · ")
            }
        }
        text += AttributedString(subtitle)
        return text
    }

    private func timeText(_ display: JourneyTimeDisplay) -> some View {
        let current = display.currentText ?? display.scheduledText
        let changed = display.currentText != nil && display.currentText != display.scheduledText
        return HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(current)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(changed ? Color.rightTrainAmber : Color.primary)
            if changed {
                Text(display.scheduledText)
                    .font(.footnote)
                    .monospacedDigit()
                    .strikethrough()
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct SearchDirectJourneyRow: View {
    var recommendation: DirectWindowRecommendation
    var emphasized: Bool
    var isPinned: Bool
    var pinJourney: () async -> Void

    private var journey: JourneyResult { recommendation.journey }

    var body: some View {
        SearchResultRowLayout(
            departure: JourneyFormatting.departureDisplay(journey),
            arrival: JourneyFormatting.arrivalDisplay(journey),
            subtitle: subtitle,
            isRecommended: emphasized,
            platform: ActiveWindowPresentation.platformDisplay(for: journey),
            isPinned: isPinned,
            pinHint: "Pins this train as your current Journey Pin.",
            unpinHint: "Unpins this train and returns to watching the search.",
            pinJourney: pinJourney
        ) {
            if ActiveWindowPresentation.heroStatusDisplay(for: recommendation) != nil {
                DisruptionLine(journey: journey, score: recommendation.score)
                    .font(.footnote)
                    .lineLimit(2)
            } else if emphasized, let reasonText {
                Text(reasonText)
                    .font(.footnote)
                    .foregroundStyle(Color.rightTrainActionInk)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var subtitle: String {
        let duration = JourneyFormatting.durationText(journey)
            .replacingOccurrences(of: "Scheduled ", with: "")
        return [duration, JourneyFormatting.operatorSummaryText(journey)]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private var reasonText: String? {
        recommendation.score.reasons?
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .compactMap(JourneyFormatting.customerFacingRecommendationReason)
            .first { !$0.isEmpty }
    }
}

private struct SearchItineraryJourneyRow: View {
    var itinerary: ItineraryRecommendation
    var emphasized: Bool
    var isPinned: Bool
    var pinJourney: () async -> Void

    var body: some View {
        SearchResultRowLayout(
            departure: JourneyTimeDisplay(scheduledText: ItineraryFormatting.departureText(itinerary), isDelayed: false),
            arrival: JourneyTimeDisplay(scheduledText: ItineraryFormatting.arrivalText(itinerary), isDelayed: false),
            subtitle: compactSummaryText,
            isRecommended: emphasized,
            platform: ActiveWindowPresentation.PlatformDisplay(
                primary: ItineraryFormatting.firstLegPlatformText(itinerary),
                secondary: nil,
                confirmed: ItineraryFormatting.firstLegPlatformConfirmed(itinerary)
            ),
            isPinned: isPinned,
            pinHint: "Pins this route as your current Journey Pin.",
            unpinHint: "Unpins this journey.",
            pinJourney: pinJourney
        ) {
            if itinerary.score.changeCount > 0 {
                StatusIconText(text: connectionRiskText, systemImage: connectionIcon, color: connectionTone.color)
                    .fontWeight(.medium)
            }
            if let status = ItineraryFormatting.anomalousStatusDisplay(itinerary),
               !status.text.localizedCaseInsensitiveContains("connection") {
                StatusIconText(text: status.text, systemImage: status.icon, color: status.tone.color)
            } else if emphasized, let reasonText {
                Text(reasonText)
                    .font(.footnote)
                    .foregroundStyle(Color.rightTrainActionInk)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var compactSummaryText: String {
        var parts = [
            ItineraryFormatting.durationText(itinerary),
            ItineraryFormatting.changesText(itinerary)
        ]
        if let connection = itinerary.connections.first {
            let station = connection.atName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? connection.atCrs
                : connection.atName
            parts.append("via \(station)")
        }
        return parts.joined(separator: " · ")
    }

    private var connectionStatus: String {
        itinerary.connections.first?.risk.status ?? ""
    }

    private var connectionTone: StatusPill.Tone {
        switch connectionStatus {
        case "missed": return .red
        case "at_risk", "tight": return .amber
        default: return .green
        }
    }

    private var connectionIcon: String {
        switch connectionStatus {
        case "missed": return "xmark.octagon.fill"
        case "at_risk", "tight": return "exclamationmark.triangle.fill"
        default: return "arrow.triangle.branch"
        }
    }

    private var connectionRiskText: String {
        guard let connection = itinerary.connections.first else {
            let margin = itinerary.score.minimumConnectionMarginMinutes
            return margin < 0 ? "\(abs(margin)) min short to change" : "\(margin) min to change"
        }
        switch connection.risk.status {
        case "missed":
            return "Connection missed at \(connection.atCrs)"
        case "at_risk":
            return "Connection at risk · \(max(connection.expectedMarginMinutes, 0)) min"
        case "tight":
            return "Tight connection · \(connection.expectedMarginMinutes) min"
        default:
            return "\(connection.expectedMarginMinutes) min to change"
        }
    }

    private var reasonText: String? {
        itinerary.score.reasons?
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .compactMap(JourneyFormatting.customerFacingRecommendationReason)
            .first { !$0.isEmpty }
    }
}

private struct PinJourneyIconButton: View {
    var isPinned: Bool
    var pinHint: String
    var unpinHint: String
    var action: () async -> Void

    var body: some View {
        PinIconButton(
            systemImage: isPinned ? "pin.fill" : "pin",
            accessibilityLabel: isPinned ? "Unpin journey" : "Pin journey",
            hint: isPinned ? unpinHint : pinHint,
            isSelected: isPinned,
            action: action
        )
    }
}

private struct PinIconButton: View {
    var systemImage = "pin"
    var accessibilityLabel: String
    var hint: String
    var isSelected = false
    var action: () async -> Void

    var body: some View {
        Button {
            Task {
                await action()
            }
        } label: {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                // Pin and pin.fill share a shape, so Magic Replace fills the
                // outline in place instead of cutting between them.
                .contentTransition(.symbolEffect(.replace))
                .frame(width: RTSize.tapTarget, height: RTSize.tapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .foregroundStyle(Color.rightTrainActionInk)
        .sensoryFeedback(trigger: isSelected) { _, pinned in
            pinned ? .success : .selection
        }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(hint)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
