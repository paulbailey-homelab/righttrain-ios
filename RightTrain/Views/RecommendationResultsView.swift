import SwiftUI

struct SearchPinSummary {
    var routeTitle: String
    var windowText: String
    var kind: PinKind
}

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

        VStack(alignment: .leading, spacing: RTSpacing.sectionGap) {
            if recommendations.isEmpty {
                EmptyStateView(
                    title: "No direct trains found",
                    message: "Try widening the departure window or switching to routes with changes."
                )
            } else {
                searchPinHeader(recommendationCount: recommendations.count)

                // Top recommendation with a status rail.
                if let top {
                    SearchDirectJourneyCard(
                        recommendation: top,
                        emphasized: true,
                        isPinned: isJourneyPinned(top),
                        pinJourney: { await toggleJourneyPin(top) }
                    )
                }

                // Remaining direct trains in a shared container.
                if !others.isEmpty {
                    VStack(alignment: .leading, spacing: RTSpacing.compact) {
                        Text("Other direct trains")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.rightTrainInk.opacity(RTOpacity.secondary))

                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(others.enumerated()), id: \.element.id) { index, rec in
                                SearchDirectJourneyCard(
                                    recommendation: rec,
                                    emphasized: false,
                                    isPinned: isJourneyPinned(rec),
                                    pinJourney: { await toggleJourneyPin(rec) },
                                    inContainer: true
                                )

                                if index < others.count - 1 {
                                    Divider()
                                        .background(Color.rightTrainInkFaint)
                                        .padding(.leading, RTSpacing.cardPadding + 4)
                                }
                            }
                        }
                        .background(Color.rightTrainPaperCream)
                        .lightSurfaceForeground()
                        .overlay {
                            RoundedRectangle(cornerRadius: RTRadius.card)
                                .stroke(Color.rightTrainInkFaint, lineWidth: 1)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: RTRadius.card))
                    }
                }

                // If top is nil (all trains at same rank), fall back to showing all
                if top == nil {
                    LazyVStack(alignment: .leading, spacing: RTSpacing.listItem) {
                        ForEach(recommendations) { rec in
                            SearchDirectJourneyCard(
                                recommendation: rec,
                                emphasized: false,
                                isPinned: isJourneyPinned(rec),
                                pinJourney: { await toggleJourneyPin(rec) }
                            )
                        }
                    }
                }
            }
        }
    }

    private func searchPinHeader(recommendationCount: Int) -> some View {
        VStack(alignment: .leading, spacing: RTSpacing.small) {
            HStack(alignment: .firstTextBaseline, spacing: RTSpacing.small) {
                Text("DIRECT TRAINS")
                    .font(RTFont.eyebrow)
                    .tracking(1.6)
                    .foregroundStyle(Color.rightTrainInk.opacity(RTOpacity.secondary))

                Spacer(minLength: RTSpacing.small)

                Text(summary.windowText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.rightTrainInk.opacity(RTOpacity.dim))
                    .monospacedDigit()
                    .lineLimit(1)
            }

            HStack(alignment: .center, spacing: RTSpacing.listItem) {
                Text(summary.routeTitle)
                    .font(.system(size: 22, weight: .bold))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)

                SearchPinButton(
                    recommendationCount: recommendationCount,
                    action: pinWindow
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(summary.routeTitle), direct trains between \(summary.windowText)")
        .accessibilityHint("Creates a Search Pin for \(recommendationCount) direct trains in this departure range.")
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

private struct SearchPinButton: View {
    var recommendationCount: Int
    var action: () async -> Void

    var body: some View {
        Button {
            Task {
                await action()
            }
        } label: {
            Label("Pin search", systemImage: "pin.circle")
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .frame(height: 34)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.rightTrainActionInk)
        .background(Color.rightTrainActionInk.opacity(0.13), in: Capsule())
        .accessibilityLabel("Pin search")
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
        VStack(alignment: .leading, spacing: 14) {
            if itineraries.isEmpty {
                EmptyStateView(
                    title: "No trains found",
                    message: "Try adjusting your departure time or widening the departure window."
                )
            } else {
                itinerarySearchHeader

                Text("Routes with changes")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                LazyVStack(alignment: .leading, spacing: RTSpacing.listItem) {
                    ForEach(itineraries) { itinerary in
                        SearchItineraryJourneyCard(
                            itinerary: itinerary,
                            emphasized: isTopItinerary(itinerary),
                            isPinned: isJourneyPinned(itinerary),
                            pinJourney: {
                                await toggleJourneyPin(itinerary)
                            }
                        )
                    }
                }
            }
        }
    }

    private var itinerarySearchHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(summary.routeTitle)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(summary.windowText) · \(itineraries.count) \(itineraries.count == 1 ? "route" : "routes")")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(RTSpacing.cardPadding)
        .background(Color.rightTrainHighlight.opacity(0.75), in: RoundedRectangle(cornerRadius: RTRadius.card))
        .lightSurfaceForeground()
        .overlay {
            RoundedRectangle(cornerRadius: RTRadius.card)
                .stroke(Color.rightTrainActionInk.opacity(0.35), lineWidth: 1)
        }
    }

    private func isTopItinerary(_ itinerary: ItineraryRecommendation) -> Bool {
        guard let topItinerary = response.topItinerary else {
            return itinerary.recommended
        }
        return itinerary.stableKey == topItinerary.stableKey
    }
}

private struct SearchDirectJourneyCard: View {
    var recommendation: DirectWindowRecommendation
    var emphasized: Bool
    var isPinned: Bool
    var pinJourney: () async -> Void
    /// When true the card is rendered as a plain row inside a shared container
    /// (no card chrome of its own, left strip indicates status).
    var inContainer: Bool = false

    private var journey: JourneyResult { recommendation.journey }

    /// Tone of this specific recommendation, used to tint the left-edge strip.
    private var statusTone: StatusPill.Tone {
        ActiveWindowPresentation.statusDisplay(for: recommendation).tone
    }

    private var stripColor: Color {
        switch statusTone {
        case .red:    return .rightTrainBadBg
        case .amber:  return .rightTrainWarnBg
        default:      return .rightTrainGoodBg
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: RTSpacing.listItem) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(JourneyFormatting.departureText(journey)) → \(JourneyFormatting.arrivalText(journey))")
                        .font(emphasized ? .title3.weight(.semibold) : .headline)
                        .monospacedDigit()
                        .fixedSize(horizontal: false, vertical: true)

                    Text(JourneyFormatting.durationText(journey))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)

                    if let operatorText = JourneyFormatting.operatorSummaryText(journey) {
                        Text(operatorText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 6)

                VStack(alignment: .trailing, spacing: 8) {
                    if !inContainer {
                        StatusPill(text: emphasized ? "Best option" : "Alternative \(recommendation.rank)", tone: .accent)
                    }
                    PinJourneyIconButton(
                        isPinned: isPinned,
                        pinHint: "Pins this train as your current Journey Pin.",
                        unpinHint: "Unpins this train and returns to watching the search.",
                        action: pinJourney
                    )
                }
            }

            LazyVGrid(columns: metricColumns, alignment: .leading, spacing: 8) {
                SearchTimeMetricView(label: "Dep", display: JourneyFormatting.departureDisplay(journey))
                SearchTimeMetricView(label: "Arr", display: JourneyFormatting.arrivalDisplay(journey))
                MetricView(label: "Platform", value: JourneyFormatting.platformMetricText(journey))
            }

            DisruptionLine(journey: journey, score: recommendation.score)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            if let reasonText {
                Text(reasonText)
                    .font(.caption)
                    .foregroundStyle(Color.rightTrainInk.opacity(RTOpacity.dim))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(RTSpacing.compact)
        .padding(.leading, inContainer ? 4 : 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(SearchCardChrome(
            emphasized: emphasized,
            inContainer: inContainer,
            stripColor: stripColor
        ))
        .accessibilityElement(children: .contain)
    }

    private var metricColumns: [GridItem] {
        [GridItem(.adaptive(minimum: emphasized ? 92 : 78), spacing: 8, alignment: .leading)]
    }
    private var reasonText: String? {
        recommendation.score.reasons?
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }
}

private struct SearchTimeMetricView: View {
    var label: String
    var display: JourneyTimeDisplay

    private var primaryText: String {
        display.currentText ?? display.scheduledText
    }

    private var secondaryText: String? {
        guard let current = display.currentText, current != display.scheduledText else {
            return nil
        }
        return "was \(display.scheduledText)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(primaryText)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)

            if let secondaryText {
                Text(secondaryText)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color.rightTrainInk.opacity(RTOpacity.dim))
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        if let secondaryText {
            return "\(primaryText), \(secondaryText)"
        }
        return primaryText
    }
}

/// Applies the right background/border/foreground treatment to a search result card.
private struct SearchCardChrome: ViewModifier {
    var emphasized: Bool
    var inContainer: Bool
    var stripColor: Color

    func body(content: Content) -> some View {
        if emphasized {
            // Top recommendation uses the same neutral card system with a status rail.
            content
                .background(Color.rightTrainPaperCream, in: RoundedRectangle(cornerRadius: RTRadius.card))
                .lightSurfaceForeground()
                .overlay {
                    RoundedRectangle(cornerRadius: RTRadius.card)
                        .stroke(Color.rightTrainActionInk.opacity(0.28), lineWidth: 1)
                }
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(stripColor)
                        .frame(width: 4)
                        .clipShape(.rect(
                            topLeadingRadius: RTRadius.card,
                            bottomLeadingRadius: RTRadius.card,
                            bottomTrailingRadius: 0,
                            topTrailingRadius: 0
                        ))
                }
        } else if inContainer {
            // Inside the other-direct-trains container — plain row + left strip
            content
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(stripColor)
                        .frame(width: 4)
                }
        } else {
            // Standalone non-emphasized card (fallback)
            content
                .background(Color.rightTrainPaperCream, in: RoundedRectangle(cornerRadius: RTRadius.card))
                .lightSurfaceForeground()
                .overlay {
                    RoundedRectangle(cornerRadius: RTRadius.card)
                        .stroke(Color.rightTrainInkFaint, lineWidth: 1)
                }
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(stripColor)
                        .frame(width: 4)
                        .clipShape(.rect(
                            topLeadingRadius: RTRadius.card,
                            bottomLeadingRadius: RTRadius.card,
                            bottomTrailingRadius: 0,
                            topTrailingRadius: 0
                        ))
                }
        }
    }
}

private struct SearchItineraryJourneyCard: View {
    var itinerary: ItineraryRecommendation
    var emphasized: Bool
    var isPinned: Bool
    var pinJourney: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: RTSpacing.listItem) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(ItineraryFormatting.departureText(itinerary)) → \(ItineraryFormatting.arrivalText(itinerary))")
                        .font(emphasized ? .title3.weight(.semibold) : .headline)
                        .monospacedDigit()
                        .fixedSize(horizontal: false, vertical: true)
                    Text(compactSummaryText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }

                Spacer(minLength: 6)

                StatusPill(text: emphasized ? "Recommended" : "Alternative \(itinerary.rank)", tone: .accent)
                PinJourneyIconButton(
                    isPinned: isPinned,
                    pinHint: "Pins this route as your current Journey Pin.",
                    unpinHint: "Unpins this journey.",
                    action: pinJourney
                )
            }

            LazyVGrid(columns: metricColumns, alignment: .leading, spacing: 8) {
                MetricView(label: "Dep", value: ItineraryFormatting.departureText(itinerary))
                MetricView(label: "Arr", value: ItineraryFormatting.arrivalText(itinerary))
                MetricView(label: "First action", value: firstActionText)
                MetricView(label: "Connection", value: connectionRiskText)
            }

            ItineraryStatusLine(itinerary: itinerary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            if let reasonText {
                Text(reasonText)
                    .font(.caption)
                    .foregroundStyle(Color.rightTrainInk.opacity(RTOpacity.dim))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(emphasized ? Color.rightTrainHighlight : Color.rightTrainBackground, in: RoundedRectangle(cornerRadius: RTRadius.card))
        .lightSurfaceForeground()
        .overlay {
            RoundedRectangle(cornerRadius: RTRadius.card)
                .stroke(emphasized ? Color.rightTrainActionInk.opacity(0.5) : Color.rightTrainBorder, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
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

    private var changeMarginText: String {
        guard itinerary.score.changeCount > 0 else {
            return "Direct route"
        }
        let margin = itinerary.score.minimumConnectionMarginMinutes
        if margin < 0 {
            return "\(abs(margin)) min short"
        }
        return "\(margin) min to change"
    }

    private var metricColumns: [GridItem] {
        [GridItem(.adaptive(minimum: emphasized ? 104 : 86), spacing: 8, alignment: .leading)]
    }

    private var firstActionText: String {
        "Platform \(ItineraryFormatting.firstLegPlatformText(itinerary))"
    }

    private var connectionRiskText: String {
        guard itinerary.score.changeCount > 0 else {
            return "Direct"
        }
        guard let connection = itinerary.connections.first else {
            return changeMarginText
        }
        switch connection.risk.status {
        case "missed":
            return "Missed at \(connection.atCrs)"
        case "at_risk":
            return "At risk · \(max(connection.expectedMarginMinutes, 0)) min"
        case "tight":
            return "Tight · \(connection.expectedMarginMinutes) min"
        default:
            return changeMarginText
        }
    }

    private var reasonText: String? {
        itinerary.score.reasons?
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
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
                .font(.subheadline.weight(.semibold))
                .frame(width: RTSize.tapTarget, height: RTSize.tapTarget)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.rightTrainActionInk)
        .background(Color.rightTrainActionInk.opacity(isSelected ? 0.2 : 0.13), in: Circle())
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
