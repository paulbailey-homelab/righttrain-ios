import SwiftUI

/// Direct-train search results, rendered as inset-grouped list sections.
/// Host inside a `List`.
///
/// Only reached when the backend has multi-leg routing turned off; otherwise
/// every search returns itineraries and `ItineraryResultsView` renders them.
struct RecommendationResultsView: View {
    var response: DirectWindowRecommendationResponse
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
                    message: "RightTrain only finds direct trains for now, so journeys that need a change won't appear. Try a wider departure window."
                )
                .listRowInsets(EdgeInsets())
            }
        } else {
            // The route and window live in the navigation bar, and the
            // recommended train is marked in its row, so every train shares
            // one section in departure order.
            Section {
                DepartureBoard {
                    DepartureBoardHeader()
                    ForEach(recommendations) { rec in
                        SearchDirectJourneyRow(
                            recommendation: rec,
                            emphasized: isTopRecommendation(rec),
                            isPinned: isJourneyPinned(rec),
                            pinJourney: { await toggleJourneyPin(rec) }
                        )
                    }
                }
                .searchBoardListRow()
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
        .accessibilityHint("Creates a Search Pin for \(recommendationCount) direct trains in this departure window.")
    }
}

struct ItineraryResultsView: View {
    var presentation: ItinerarySearchPresentation
    var isJourneyPinned: (ItineraryRecommendation) -> Bool
    var toggleJourneyPin: (ItineraryRecommendation) async -> Void
    var openLegDetail: (ItineraryLeg) async -> Void

    private var itineraries: [ItineraryRecommendation] {
        ItineraryFormatting.chronologicalItineraries(
            topItinerary: presentation.topItinerary,
            itineraries: presentation.itineraries
        )
    }

    var body: some View {
        if itineraries.isEmpty {
            Section {
                EmptyStateView(
                    title: "No journeys found",
                    message: presentation.quickerWithChange == nil
                        ? "Nothing runs between these stations in this departure window. Try a later departure or a wider window."
                        : "No direct trains in this departure window, but there is a route with a change below."
                )
                .listRowInsets(EdgeInsets())
            }
        } else {
            Section {
                DepartureBoard {
                    DepartureBoardHeader()
                    ForEach(itineraries) { itinerary in
                        SearchItineraryJourneyRow(
                            itinerary: itinerary,
                            emphasized: isTopItinerary(itinerary),
                            isPinned: isJourneyPinned(itinerary),
                            pinJourney: { await toggleJourneyPin(itinerary) }
                        )
                    }
                }
                .searchBoardListRow()
            } header: {
                Text("\(itineraries.count) \(itineraries.count == 1 ? "journey" : "journeys")")
            }
        }

        // Only present when the user asked for direct trains and a journey
        // with a change still beats the best of them by a wide margin, so
        // hiding changes never hides a much faster way home.
        if let quicker = presentation.quickerWithChange {
            Section {
                DepartureBoard {
                    SearchItineraryJourneyRow(
                        itinerary: quicker,
                        emphasized: false,
                        isPinned: isJourneyPinned(quicker),
                        pinJourney: { await toggleJourneyPin(quicker) }
                    )
                }
                .searchBoardListRow()
            } header: {
                Text(presentation.quickerWithChangeSavingMinutes > 0
                    ? "\(presentation.quickerWithChangeSavingMinutes) min sooner with a change"
                    : "With a change")
            }
        }
    }

    private func isTopItinerary(_ itinerary: ItineraryRecommendation) -> Bool {
        guard let topItinerary = presentation.topItinerary else {
            return itinerary.recommended
        }
        return itinerary.stableKey == topItinerary.stableKey
    }
}

// MARK: - Result rows

private extension View {
    /// A board is its own panel, so the list row around it is bare.
    func searchBoardListRow() -> some View {
        listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
    }
}

/// One result as a line on a departure board: the first train's time,
/// destination, platform and Expected, then a dim line with when the
/// journey gets in, how long it takes and any change. Tapping the line pins
/// or unpins it.
private struct SearchBoardRow: View {
    /// The train the traveller boards first.
    var journey: JourneyResult
    var detail: String
    var accessibilityText: String
    var isPinned: Bool
    var pinHint: String
    var unpinHint: String
    var pinJourney: () async -> Void

    var body: some View {
        Button {
            Task { await pinJourney() }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                DepartureBoardRow(
                    time: JourneyFormatting.departureDisplay(journey).scheduledText,
                    destination: BoardText.destination(journey),
                    platform: ActiveWindowPresentation.platformDisplay(for: journey).value,
                    expected: BoardText.expected(journey),
                    isPinned: isPinned
                )
                Text(BoardText.boardSafe(detail))
                    .foregroundStyle(DepartureBoardStyle.dimAmber)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(trigger: isPinned) { _, pinned in
            pinned ? .success : .selection
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isPinned ? "Pinned. \(accessibilityText)" : accessibilityText)
        .accessibilityHint(isPinned ? unpinHint : pinHint)
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isPinned ? .isSelected : [])
    }
}

private struct SearchDirectJourneyRow: View {
    var recommendation: DirectWindowRecommendation
    var emphasized: Bool
    var isPinned: Bool
    var pinJourney: () async -> Void

    private var journey: JourneyResult { recommendation.journey }

    var body: some View {
        SearchBoardRow(
            journey: journey,
            detail: detail,
            accessibilityText: accessibilityText,
            isPinned: isPinned,
            pinHint: "Pins this train as your current Journey Pin.",
            unpinHint: "Unpins this train and returns to watching the search.",
            pinJourney: pinJourney
        )
    }

    /// "Recommended. Arr 09:12, 47m, direct." plus Darwin's reason for a
    /// delay or cancellation.
    private var detail: String {
        var sentences: [String] = []
        if emphasized {
            sentences.append("Recommended.")
        }
        let arrival = JourneyFormatting.arrivalDisplay(journey)
        var facts = ["Arr \(arrival.currentText ?? arrival.scheduledText)"]
        if let duration {
            facts.append(duration)
        }
        facts.append("direct")
        sentences.append(facts.joined(separator: ", ") + ".")
        if ActiveWindowPresentation.heroStatusDisplay(for: recommendation) != nil, let reason {
            sentences.append(reason.hasSuffix(".") ? reason : "\(reason).")
        }
        return sentences.joined(separator: " ")
    }

    private var duration: String? {
        let departure = JourneyFormatting.departureDisplay(journey)
        let arrival = JourneyFormatting.arrivalDisplay(journey)
        guard let start = departure.currentDate ?? departure.scheduledDate,
              let end = arrival.currentDate ?? arrival.scheduledDate else {
            return nil
        }
        return ItineraryFormatting.durationText(from: start, to: end)
    }

    private var reason: String? {
        let text = JourneyFormatting.isCancelled(journey) ? journey.cancellationReasonText : journey.lateReasonText
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }
        return text
    }

    private var accessibilityText: String {
        let departure = JourneyFormatting.departureDisplay(journey)
        let platform = ActiveWindowPresentation.platformDisplay(for: journey).value
        return [
            "\(departure.scheduledText) to \(JourneyFormatting.finalDestinationText(journey))",
            BoardText.expected(journey),
            platform.accessibilityLabel(),
            detail
        ].joined(separator: ", ")
    }
}

private struct SearchItineraryJourneyRow: View {
    var itinerary: ItineraryRecommendation
    var emphasized: Bool
    var isPinned: Bool
    var pinJourney: () async -> Void

    var body: some View {
        if let first = itinerary.legs.first {
            let journey = first.journeyResult
            SearchBoardRow(
                journey: journey,
                detail: detail,
                accessibilityText: accessibilityText(journey),
                isPinned: isPinned,
                pinHint: "Pins this route as your current Journey Pin.",
                unpinHint: "Unpins this journey.",
                pinJourney: pinJourney
            )
        }
    }

    /// "Recommended. Arr 10:42, 1h 52m. Change at York, 6 min." The board
    /// line above is the first train, so this line says where the journey
    /// gets to and what happens on the way.
    private var detail: String {
        var sentences: [String] = []
        if emphasized {
            sentences.append("Recommended.")
        }
        let duration = ItineraryFormatting.durationText(itinerary)
        if itinerary.score.changeCount == 0 {
            sentences.append("Arr \(ItineraryFormatting.arrivalText(itinerary)), \(duration), direct.")
        } else {
            sentences.append("Arr \(ItineraryFormatting.arrivalText(itinerary)), \(duration).")
            sentences.append(changeText)
        }
        if let status = ItineraryFormatting.anomalousStatusDisplay(itinerary),
           !status.text.localizedCaseInsensitiveContains("connection") {
            sentences.append(status.text)
        }
        return sentences.joined(separator: " ")
    }

    /// The first change and how it's looking.
    private var changeText: String {
        let count = itinerary.score.changeCount
        guard let connection = itinerary.connections.first else {
            let margin = itinerary.score.minimumConnectionMarginMinutes
            let changes = count == 1 ? "1 change" : "\(count) changes"
            return margin < 0 ? "\(changes), \(abs(margin)) min short." : "\(changes), \(margin) min."
        }
        let station = [connection.atSixteenCharacterName, connection.atName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? connection.atCrs
        let lead = count > 1 ? "\(count) changes, first at \(station)" : "Change at \(station)"
        let margin = connection.expectedMarginMinutes
        switch connection.risk.status {
        case "missed":
            return "Connection missed at \(station)."
        case "at_risk":
            return "\(lead), at risk, \(max(margin, 0)) min."
        case "tight":
            return "\(lead), tight, \(margin) min."
        default:
            return "\(lead), \(margin) min."
        }
    }

    private func accessibilityText(_ journey: JourneyResult) -> String {
        let platform = ActiveWindowPresentation.platformDisplay(for: journey).value
        return [
            "\(JourneyFormatting.departureDisplay(journey).scheduledText) to \(JourneyFormatting.finalDestinationText(journey))",
            BoardText.expected(journey),
            platform.accessibilityLabel(),
            detail
        ].joined(separator: ", ")
    }
}
