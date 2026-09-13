import SwiftUI

struct SearchPinSummary {
    var routeTitle: String
    var windowText: String
    var kind: PinKind
}

/// Direct-train search results, rendered as inset-grouped list sections.
/// Host inside a `List`.
struct RecommendationResultsView: View {
    var response: DirectWindowRecommendationResponse
    var summary: SearchPinSummary
    var pinWindow: () async -> Void
    var isJourneyPinned: (DirectWindowRecommendation) -> Bool
    var toggleJourneyPin: (DirectWindowRecommendation) async -> Void

    var body: some View {
        let recommendations = JourneyFormatting.chronologicalRecommendations(
            topRecommendation: response.topRecommendation,
            recommendations: response.recommendations
        )
        let top    = recommendations.first { isTopRecommendation($0) }
        let others = recommendations.filter { !isTopRecommendation($0) }

        if recommendations.isEmpty {
            Section {
                EmptyStateView(
                    title: "No direct trains found",
                    message: "Try widening the departure window or switching to routes with changes."
                )
                .listRowInsets(EdgeInsets())
            }
        } else {
            Section {
                SearchResultsHeader(
                    summary: summary,
                    detailText: "\(summary.windowText) · \(recommendations.count) direct \(recommendations.count == 1 ? "train" : "trains")"
                )
            }
            .listSectionSpacing(.compact)

            if let top {
                Section {
                    SearchDirectJourneyRow(
                        recommendation: top,
                        emphasized: true,
                        isPinned: isJourneyPinned(top),
                        pinJourney: { await toggleJourneyPin(top) }
                    )
                } header: {
                    Text("Recommended")
                }
            }

            if !others.isEmpty {
                Section {
                    ForEach(others) { rec in
                        SearchDirectJourneyRow(
                            recommendation: rec,
                            emphasized: false,
                            isPinned: isJourneyPinned(rec),
                            pinJourney: { await toggleJourneyPin(rec) }
                        )
                    }
                } header: {
                    Text(top == nil ? "Direct trains" : "Other direct trains")
                }
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

/// Route title and window summary shown as the first, background-less list row.
private struct SearchResultsHeader: View {
    var summary: SearchPinSummary
    var detailText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(summary.routeTitle)
                .font(.title3.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
            Text(detailText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .listRowInsets(EdgeInsets(top: 4, leading: RTSpacing.cardPadding, bottom: 0, trailing: RTSpacing.cardPadding))
        .listRowBackground(Color.clear)
        .accessibilityElement(children: .combine)
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
    var summary: SearchPinSummary
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
            let top = itineraries.first { isTopItinerary($0) }
            let others = itineraries.filter { !isTopItinerary($0) }

            Section {
                SearchResultsHeader(
                    summary: summary,
                    detailText: "\(summary.windowText) · \(itineraries.count) \(itineraries.count == 1 ? "route" : "routes")"
                )
            }
            .listSectionSpacing(.compact)

            if let top {
                Section {
                    SearchItineraryJourneyRow(
                        itinerary: top,
                        emphasized: true,
                        isPinned: isJourneyPinned(top),
                        pinJourney: { await toggleJourneyPin(top) }
                    )
                } header: {
                    Text("Recommended")
                }
            }

            if !others.isEmpty {
                Section {
                    ForEach(others) { itinerary in
                        SearchItineraryJourneyRow(
                            itinerary: itinerary,
                            emphasized: false,
                            isPinned: isJourneyPinned(itinerary),
                            pinJourney: { await toggleJourneyPin(itinerary) }
                        )
                    }
                } header: {
                    Text(top == nil ? "Routes with changes" : "Other routes")
                }
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
    var platformLabel: String
    var platformValue: String
    var platformExpected: Bool
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

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                status()
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 0) {
                Text(platformLabel)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(platformValue)
                    .font(.title3.weight(.semibold))
                    .italic(platformExpected)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .fixedSize()
            .accessibilityElement(children: .combine)

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
        let platform = JourneyFormatting.platformText(journey)
        let hasPlatform = !["", "-", "TBC"].contains(platform.trimmingCharacters(in: .whitespaces).uppercased())
        let expected = hasPlatform && !JourneyFormatting.departurePlatformConfirmed(journey)

        SearchResultRowLayout(
            departure: JourneyFormatting.departureDisplay(journey),
            arrival: JourneyFormatting.arrivalDisplay(journey),
            subtitle: subtitle,
            platformLabel: expected ? "Exp. plat" : "Platform",
            platformValue: hasPlatform ? platform : "TBC",
            platformExpected: expected,
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
        let platform = ItineraryFormatting.firstLegPlatformText(itinerary)
        let hasPlatform = !["", "-", "TBC"].contains(platform.trimmingCharacters(in: .whitespaces).uppercased())
        let expected = hasPlatform && !ItineraryFormatting.firstLegPlatformConfirmed(itinerary)

        SearchResultRowLayout(
            departure: JourneyTimeDisplay(scheduledText: ItineraryFormatting.departureText(itinerary), isDelayed: false),
            arrival: JourneyTimeDisplay(scheduledText: ItineraryFormatting.arrivalText(itinerary), isDelayed: false),
            subtitle: compactSummaryText,
            platformLabel: expected ? "Exp. plat" : "Platform",
            platformValue: hasPlatform ? platform : "TBC",
            platformExpected: expected,
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
                .frame(width: RTSize.tapTarget, height: RTSize.tapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .foregroundStyle(Color.rightTrainActionInk)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(hint)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
