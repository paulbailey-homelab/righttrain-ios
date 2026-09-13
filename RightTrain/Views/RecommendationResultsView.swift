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

struct ItineraryRecommendationRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var itinerary: ItineraryRecommendation
    var emphasized: Bool
    var showsRouteTitle = true
    var showsLegs = true
    var showsDisclosure = false
    var isExpanded = true
    var loadDetail: (ItineraryLeg) async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            metrics
            ItineraryStatusLine(itinerary: itinerary)
            if showsLegs {
                ItineraryLegList(itinerary: itinerary, loadDetail: loadDetail)
            }
        }
        .padding(emphasized ? RTSpacing.cardPadding : 12)
        .background(emphasized ? Color.rightTrainHighlight : Color.rightTrainBackground, in: RoundedRectangle(cornerRadius: RTRadius.card))
        .lightSurfaceForeground()
        .overlay {
            RoundedRectangle(cornerRadius: RTRadius.card)
                .stroke(emphasized ? Color.rightTrainActionInk.opacity(0.5) : Color.rightTrainBorder, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var header: some View {
        if dynamicTypeSize.prefersExpandedLayout {
            VStack(alignment: .leading, spacing: 8) {
                titleBlock
                HStack(spacing: 8) {
                    StatusPill(text: emphasized ? "Recommended" : "Alternative \(itinerary.rank)", tone: .accent)
                    disclosureIcon
                }
            }
        } else {
            HStack(alignment: .top) {
                titleBlock
                Spacer()
                StatusPill(text: emphasized ? "Recommended" : "Alternative \(itinerary.rank)", tone: .accent)
                disclosureIcon
            }
        }
    }

    @ViewBuilder
    private var disclosureIcon: some View {
        if showsDisclosure {
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.top, dynamicTypeSize.prefersExpandedLayout ? 0 : 8)
                .accessibilityHidden(true)
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            if showsRouteTitle {
                Text(ItineraryFormatting.routeTitle(itinerary))
                    .font(emphasized ? .title3.weight(.semibold) : .headline)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(ItineraryFormatting.departureText(itinerary)) to \(ItineraryFormatting.arrivalText(itinerary))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("\(ItineraryFormatting.departureText(itinerary)) → \(ItineraryFormatting.arrivalText(itinerary))")
                    .font(emphasized ? .title3.weight(.semibold) : .headline)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
                Text(compactSummaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var metrics: some View {
        LazyVGrid(columns: metricColumns, alignment: .leading, spacing: RTSpacing.listItem) {
            metricViews
        }
    }

    private var metricColumns: [GridItem] {
        let minimumWidth: CGFloat = dynamicTypeSize.prefersExpandedLayout ? 220 : 82
        return [GridItem(.adaptive(minimum: minimumWidth), spacing: RTSpacing.listItem, alignment: .leading)]
    }

    @ViewBuilder
    private var metricViews: some View {
        if showsRouteTitle {
            MetricView(label: "Departs", value: ItineraryFormatting.departureText(itinerary))
            MetricView(label: "Final arr", value: ItineraryFormatting.arrivalText(itinerary))
        }
        MetricView(label: "Duration", value: ItineraryFormatting.durationText(itinerary))
        MetricView(label: ItineraryFormatting.transferMetricLabel(itinerary), value: ItineraryFormatting.transferMetricText(itinerary))
        MetricView(label: "First platform", value: ItineraryFormatting.firstLegPlatformText(itinerary))
        MetricView(label: "Change time", value: changeMarginText)
    }

    private var compactSummaryText: String {
        guard itinerary.score.changeCount > 0 else {
            return "Direct route"
        }
        if let connection = itinerary.connections.first {
            let station = connection.atName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? connection.atCrs
                : connection.atName
            return "\(ItineraryFormatting.changesText(itinerary)) via \(station)"
        }
        return ItineraryFormatting.changesText(itinerary)
    }

    private var changeMarginText: String {
        guard itinerary.score.changeCount > 0 else {
            return "Direct"
        }
        let margin = itinerary.score.minimumConnectionMarginMinutes
        if margin < 0 {
            return "\(abs(margin)) min short"
        }
        return "\(margin) min"
    }
}

struct ItineraryLegList: View {
    var itinerary: ItineraryRecommendation
    var loadDetail: (ItineraryLeg) async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(itinerary.legs.enumerated()), id: \.element.id) { index, leg in
                Button {
                    Task { await loadDetail(leg) }
                } label: {
                    ItineraryLegRow(leg: leg)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Shows the full journey calling points.")

                if let connection = ItineraryFormatting.connection(afterLegIndex: leg.legIndex, in: itinerary) {
                    ItineraryConnectionRow(connection: connection)
                }

                if index != itinerary.legs.indices.last {
                    Divider()
                        .padding(.leading, 32)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.rightTrainSurface.opacity(0.8), in: RoundedRectangle(cornerRadius: RTRadius.chip))
        .lightSurfaceForeground()
    }
}

private struct ItineraryLegRow: View {
    var leg: ItineraryLeg

    var body: some View {
        HStack(alignment: .center, spacing: RTSpacing.listItem) {
            Image(systemName: leg.cancelled ? "xmark.octagon.fill" : "tram.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(leg.cancelled ? Color.rightTrainDanger : Color.rightTrainActionInk)
                .frame(width: RTSize.iconSmall)

            VStack(alignment: .leading, spacing: 3) {
                Text(ItineraryFormatting.legRouteText(leg))
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(ItineraryFormatting.legSummaryText(leg))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

private struct ItineraryConnectionRow: View {
    var connection: ItineraryConnection

    var body: some View {
        HStack(alignment: .center, spacing: RTSpacing.listItem) {
            Image(systemName: "arrow.triangle.branch")
                .font(.caption.weight(.semibold))
                .foregroundStyle(ItineraryFormatting.connectionTone(connection).color)
                .frame(width: RTSize.iconSmall)

            VStack(alignment: .leading, spacing: 2) {
                Text(ItineraryFormatting.connectionText(connection))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let advice = ItineraryFormatting.connectionAdviceText(connection) {
                    Text(advice)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()
        }
        .padding(.vertical, 6)
    }
}

private struct ItineraryStatusLine: View {
    var itinerary: ItineraryRecommendation

    var body: some View {
        let display = ItineraryFormatting.statusDisplay(itinerary)
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: display.icon)
                .foregroundStyle(display.tone.color)
            Text(display.text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct RecommendationRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var recommendation: DirectWindowRecommendation
    var emphasized: Bool
    var showsDisclosure = false
    var showsRouteTitle = true
    var showsJourneyStrip = true

    var body: some View {
        let journey = recommendation.journey
        VStack(alignment: .leading, spacing: 12) {
            header(journey: journey)

            metrics(journey: journey)

            if showsJourneyStrip {
                DirectJourneyStrip(journey: journey)
            }

            DisruptionLine(journey: journey, score: recommendation.score)
        }
        .padding(emphasized ? RTSpacing.cardPadding : 12)
        .background(emphasized ? Color.rightTrainHighlight : Color.rightTrainBackground, in: RoundedRectangle(cornerRadius: RTRadius.card))
        .lightSurfaceForeground()
        .overlay {
            RoundedRectangle(cornerRadius: RTRadius.card)
                .stroke(emphasized ? Color.rightTrainActionInk.opacity(0.5) : Color.rightTrainBorder, lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: RTRadius.card))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private func header(journey: JourneyResult) -> some View {
        if dynamicTypeSize.prefersExpandedLayout {
            VStack(alignment: .leading, spacing: 8) {
                titleBlock(journey: journey)
                StatusPill(text: emphasized ? "Recommended" : "Alternative \(recommendation.rank)", tone: .accent)
            }
        } else {
            HStack(alignment: .top) {
                titleBlock(journey: journey)
                Spacer()
                StatusPill(text: emphasized ? "Recommended" : "Alternative \(recommendation.rank)", tone: .accent)
                if showsDisclosure {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                }
            }
        }
    }

    private func titleBlock(journey: JourneyResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if showsRouteTitle {
                Text(JourneyFormatting.routeText(journey))
                    .font(emphasized ? .title3.weight(.semibold) : .headline)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(JourneyFormatting.departureText(journey)) to \(JourneyFormatting.arrivalText(journey))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("\(JourneyFormatting.departureText(journey)) → \(JourneyFormatting.arrivalText(journey))")
                    .font(emphasized ? .title3.weight(.semibold) : .headline)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
                Text(JourneyFormatting.durationText(journey))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if journey.operatorName != nil || journey.operatorShortName != nil || journey.toc != nil {
                AdaptiveOperatorText(
                    full: journey.operatorName,
                    short: journey.operatorShortName,
                    code: journey.toc
                )
            }
        }
    }

    @ViewBuilder
    private func metrics(journey: JourneyResult) -> some View {
        if dynamicTypeSize.prefersExpandedLayout {
            VStack(alignment: .leading, spacing: RTSpacing.listItem) {
                metricViews(journey: journey)
            }
        } else {
            HStack(spacing: 18) {
                metricViews(journey: journey)
            }
        }
    }

    @ViewBuilder
    private func metricViews(journey: JourneyResult) -> some View {
        if showsRouteTitle {
            MetricView(label: "Departs", value: JourneyFormatting.departureText(journey))
            MetricView(label: "Arrives", value: JourneyFormatting.arrivalText(journey))
            MetricView(label: "Duration", value: JourneyFormatting.durationText(journey))
        }
        MetricView(label: "Dep platform", value: JourneyFormatting.platformMetricText(journey))
        MetricView(label: "Arr platform", value: JourneyFormatting.qualifiedPlatformValue(
            JourneyFormatting.arrivalPlatformText(journey),
            confirmed: JourneyFormatting.arrivalPlatformConfirmed(journey)
        ))
    }

    private var accessibilityLabel: String {
        let journey = recommendation.journey
        let rank = emphasized ? "Recommended train" : "Candidate \(recommendation.rank)"
        let operatorText = JourneyFormatting.operatorSummaryText(journey).map { ", operated by \($0)" } ?? ""
        return "\(rank), \(JourneyFormatting.routeText(journey))\(operatorText), departs \(JourneyFormatting.departureText(journey)), arrives \(JourneyFormatting.arrivalText(journey)), \(JourneyFormatting.movementStatusText(journey, score: recommendation.score))"
    }
}

private struct DirectJourneyStrip: View {
    var journey: JourneyResult

    var body: some View {
        HStack(alignment: .center, spacing: RTSpacing.listItem) {
            Image(systemName: journey.cancelled ? "xmark.octagon.fill" : "tram.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(journey.cancelled ? Color.rightTrainDanger : Color.rightTrainActionInk)
                .frame(width: RTSize.iconSmall)

            VStack(alignment: .leading, spacing: 3) {
                Text("Direct service")
                    .font(.subheadline.weight(.semibold))
                Text(summaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.rightTrainSurface.opacity(0.8), in: RoundedRectangle(cornerRadius: RTRadius.chip))
        .lightSurfaceForeground()
    }

    private var summaryText: String {
        var parts = [
            "\(JourneyFormatting.departureText(journey)) - \(JourneyFormatting.arrivalText(journey))",
            JourneyFormatting.platformText(journey)
        ]
        if let operatorText = JourneyFormatting.operatorSummaryText(journey) {
            parts.append(operatorText)
        }
        parts.append(JourneyFormatting.movementStatusText(journey))
        return parts.joined(separator: " · ")
    }
}
