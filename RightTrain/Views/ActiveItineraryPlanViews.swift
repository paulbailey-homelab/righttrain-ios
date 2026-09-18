import SwiftUI

struct ActiveItineraryPresentation {
    var itinerary: ItinerarySubscription
    var phase: ItineraryPhase
    var selectedItinerary: ItineraryRecommendation?
    var alternativeItineraries: [ItineraryRecommendation]

    init(itinerary: ItinerarySubscription) {
        self.itinerary = itinerary
        self.phase = itinerary.resolvedPhase
        self.selectedItinerary = itinerary.selectedItinerary.legs.isEmpty ? nil : itinerary.selectedItinerary

        let selected = itinerary.selectedItinerary
        let selectedStableKey = selected.stableKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.alternativeItineraries = ItineraryFormatting.chronologicalItineraries(
            topItinerary: nil,
            itineraries: itinerary.itineraries
        )
        .filter { candidate in
            if !selectedStableKey.isEmpty {
                return candidate.stableKey != selectedStableKey
            }
            return candidate.id != selected.id
        }
    }

    var routeTitle: String {
        if let selectedItinerary {
            return ItineraryFormatting.routeTitle(selectedItinerary)
        }
        return "\(itinerary.originCrs) to \(itinerary.destinationCrs)"
    }

    var journeyOptions: [ItineraryRecommendation] {
        guard let selectedItinerary else {
            return []
        }
        return [selectedItinerary]
    }

    var subtitleText: String {
        switch phase {
        case .planning:
            return windowTimeRangeText
        case .atOrigin:
            return "At the station"
        case .onLeg:
            return legProgressText
        case .approachingInterchange:
            return legProgressText
        case .onFinalLeg:
            return legProgressText
        }
    }

    var pillText: String {
        let normalizedStatus = itinerary.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalizedStatus != "active", !normalizedStatus.isEmpty {
            return itinerary.status.capitalized
        }
        switch phase {
        case .planning:
            return "Planned"
        case .atOrigin:
            return "At origin"
        case .onLeg:
            return "On train"
        case .approachingInterchange:
            if let connection = itinerary.nextConnection,
               let transferMode = ItineraryFormatting.connectionModeBadgeText(connection) {
                return transferMode
            }
            return "Change"
        case .onFinalLeg:
            return "Final leg"
        }
    }

    var pillTone: StatusPill.Tone {
        let normalizedStatus = itinerary.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalizedStatus != "active", !normalizedStatus.isEmpty {
            return .amber
        }
        switch phase {
        case .planning, .onLeg, .onFinalLeg:
            return .accent
        case .atOrigin:
            return .green
        case .approachingInterchange:
            return .amber
        }
    }

    func liveGlanceContent(now: Date = Date(), isOffline: Bool = false) -> ActiveWindowPresentation.LiveGlanceContent {
        let selected = selectedItinerary ?? itinerary.selectedItinerary
        let status = ItineraryFormatting.statusDisplay(selected)
        let statusText = status.text.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return ActiveWindowPresentation.LiveGlanceContent(
            moment: ActiveWindowPresentation.journeyMoment(for: itinerary, isOffline: isOffline),
            needProfile: .connectionSensitiveTrip,
            routeTitle: routeTitle,
            routeContextText: routeContextText(for: selected),
            statusText: statusText.isEmpty ? pillText : statusText,
            statusTone: isOffline ? .amber : status.tone,
            timingText: "Dep \(ItineraryFormatting.departureText(selected)) · Arr \(ItineraryFormatting.arrivalText(selected))",
            platform: PlatformValue(
                ItineraryFormatting.firstLegPlatformText(selected),
                confirmed: ItineraryFormatting.firstLegPlatformConfirmed(selected)
            ),
            platformText: JourneyFormatting.platformStateText(
                primary: ItineraryFormatting.firstLegPlatformText(selected),
                confirmed: ItineraryFormatting.firstLegPlatformConfirmed(selected)
            ),
            nextActionText: nextActionText(for: selected, isOffline: isOffline),
            freshnessText: isOffline
                ? "Offline · showing saved journey data"
                : ActiveWindowPresentation.freshnessText(updatedAt: latestRealtimeUpdate(in: selected), now: now)
        )
    }

    /// Matches the direct Pin: realtime older than five minutes shouldn't be
    /// presented as live.
    func isDataStale(now: Date = Date()) -> Bool {
        let selected = selectedItinerary ?? itinerary.selectedItinerary
        guard let updatedAt = latestRealtimeUpdate(in: selected) else {
            return false
        }
        return now.timeIntervalSince(updatedAt) > 5 * 60
    }

    func routeContextText(for selected: ItineraryRecommendation) -> String? {
        guard selected.score.changeCount > 0 else {
            return nil
        }
        if let connection = selected.connections.first {
            let station = JourneyFormatting.stationDisplayName(
                name: connection.atName,
                fallback: connection.atCrs
            )
            return "\(ItineraryFormatting.changesText(selected)) via \(station)"
        }
        return ItineraryFormatting.changesText(selected)
    }

    var headerStatusText: String? {
        let normalizedStatus = itinerary.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalizedStatus != "active", !normalizedStatus.isEmpty else {
            return nil
        }
        return itinerary.status.capitalized
    }

    var headerStatusTone: StatusPill.Tone {
        headerStatusText == nil ? .accent : .amber
    }

    var canBoardFirstLeg: Bool {
        phase == .planning || phase == .atOrigin
    }

    var canBoardOnwardLeg: Bool {
        phase == .approachingInterchange && itinerary.onwardLeg != nil
    }

    var canStopMonitoring: Bool {
        true
    }

    var recoveryFromCrs: String? {
        guard phase == .onLeg || phase == .approachingInterchange else {
            return nil
        }
        return itinerary.currentLeg?.destinationCrs ?? itinerary.destinationCrs
    }

    var legProgressText: String {
        let total = max(selectedItinerary?.legs.count ?? itinerary.selectedItinerary.legs.count, 1)
        let progress = "Leg \(itinerary.currentLegIndex + 1) of \(total)"
        if phase == .approachingInterchange, let connection = itinerary.nextConnection {
            return "\(progress) · Approaching \(lowercaseInitial(ItineraryFormatting.connectionTitleText(connection)))"
        }
        return progress
    }

    private var windowTimeRangeText: String {
        guard let start = DateFormatting.date(from: itinerary.departureStart) else {
            return "\(itinerary.windowMinutes) min"
        }
        let end = start.addingTimeInterval(TimeInterval(itinerary.windowMinutes) * 60)
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "Europe/London")
        formatter.dateFormat = "HH:mm"
        return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
    }

    private func lowercaseInitial(_ value: String) -> String {
        guard let first = value.first else {
            return value
        }
        return first.lowercased() + value.dropFirst()
    }

    private func nextActionText(for selected: ItineraryRecommendation, isOffline: Bool) -> String {
        if isOffline {
            return "Check again when connection returns"
        }
        let platform = ItineraryFormatting.firstLegPlatformText(selected)
        switch phase {
        case .planning, .atOrigin:
            let platformText = JourneyFormatting.platformStateText(
                primary: platform,
                confirmed: ItineraryFormatting.firstLegPlatformConfirmed(selected)
            )
            return platformText == "Platform TBC" ? "Watch for the first platform" : "Go to \(platformText.lowercased())"
        case .onLeg:
            return "Follow this leg and next change"
        case .approachingInterchange:
            return "Check the connection"
        case .onFinalLeg:
            return "Follow stops and arrival"
        }
    }

    private func latestRealtimeUpdate(in selected: ItineraryRecommendation) -> Date? {
        selected.legs
            .compactMap { $0.realtimeUpdatedAt.flatMap(DateFormatting.date(from:)) }
            .max()
    }
}

/// Switches between the active multi-leg journey perspectives.
struct PerspectiveActiveItineraryView: View {
    var itinerary: ItinerarySubscription
    var isOffline = false
    var loadDetail: (ItineraryLeg) async -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let presentation = ActiveItineraryPresentation(itinerary: itinerary)
            VStack(alignment: .leading, spacing: RTSpacing.compact) {
                // Status, route and freshness sit on the page like the direct
                // Pin's hero; the phase card below carries the timings and
                // actions, so a separate glance card would only repeat them.
                ActiveItineraryStatusHeader(
                    content: presentation.liveGlanceContent(now: context.date, isOffline: isOffline),
                    isStale: isOffline || presentation.isDataStale(now: context.date)
                )
                phaseView
            }
        }
    }

    @ViewBuilder
    private var phaseView: some View {
        switch itinerary.resolvedPhase {
        case .planning, .atOrigin:
            ActiveItineraryView(itinerary: itinerary, loadDetail: loadDetail)
        case .onLeg:
            ItineraryOnLegView(itinerary: itinerary, approachingInterchange: false, loadDetail: loadDetail)
        case .approachingInterchange:
            ItineraryOnLegView(itinerary: itinerary, approachingInterchange: true, loadDetail: loadDetail)
        case .onFinalLeg:
            ItineraryOnFinalLegView(itinerary: itinerary, loadDetail: loadDetail)
        }
    }
}

private struct ActiveItineraryStatusHeader: View {
    var content: ActiveWindowPresentation.LiveGlanceContent
    var isStale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: RTSpacing.small) {
                    StatusPill(text: content.statusText, tone: content.statusTone)
                        .fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: RTSpacing.small)
                    freshness
                }
                VStack(alignment: .leading, spacing: 4) {
                    StatusPill(text: content.statusText, tone: content.statusTone)
                    freshness
                }
            }

            Text(content.routeTitle)
                .font(.title3.weight(.bold))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)

            if let routeContextText = content.routeContextText {
                Text(routeContextText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var freshness: some View {
        if isStale {
            Label(content.freshnessText, systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.rightTrainAmber)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .accessibilityLabel("Live data may be out of date. \(content.freshnessText)")
        } else {
            LiveFreshnessText(text: content.freshnessText)
        }
    }
}

/// Planning/at-origin perspective: focuses on the selected monitored itinerary,
/// with alternate options directly available below it.
struct ActiveItineraryView: View {
    @Environment(ActiveWindowViewModel.self) private var activeWindowViewModel
    @State private var expandedItineraryIDs: Set<String> = []
    @State private var showsAlternatives = false
    @State private var pendingSwitch: ItineraryRecommendation?
    var itinerary: ItinerarySubscription
    var loadDetail: (ItineraryLeg) async -> Void

    private var presentation: ActiveItineraryPresentation {
        ActiveItineraryPresentation(itinerary: itinerary)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            ActiveItineraryCard {
                if presentation.phase == .atOrigin {
                    atOriginBanner
                }

                selectedJourneySection(now: context.date)

                alternativesSection
            }
        }
        .background {
            ActiveItineraryHeader(presentation: presentation)
        }
        .onAppear {
            expandSelectedItineraryIfNeeded()
        }
        .onChange(of: presentation.selectedItinerary?.id) { _, selectedID in
            expandSelectedItinerary(selectedID)
        }
    }

    @ViewBuilder
    private func selectedJourneySection(now: Date) -> some View {
        if !presentation.journeyOptions.isEmpty {
            LazyVStack(alignment: .leading, spacing: RTSpacing.listItem) {
                ForEach(presentation.journeyOptions) { option in
                    let isSelected = option.id == presentation.selectedItinerary?.id
                    ActiveItineraryOptionCard(
                        itinerary: option,
                        emphasized: isSelected,
                        isExpanded: isExpanded(option),
                        now: now,
                        toggleExpanded: {
                            toggleExpanded(option)
                        },
                        loadDetail: loadDetail
                    )

                    if isSelected, presentation.canBoardFirstLeg, let firstLeg = option.legs.first {
                        Button {
                            Task {
                                await activeWindowViewModel.boardItineraryLeg(firstLeg.legIndex, itineraryID: itinerary.id)
                            }
                        } label: {
                            Label("I'm on this train", systemImage: "checkmark.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.rtPrimary)
                        .accessibilityIdentifier("active-itinerary-board-first-leg")
                    }
                }
            }
        } else {
            EmptyStateView(
                title: "No connections",
                message: "RightTrain could not find a usable journey for this window."
            )
        }
    }

    /// Before boarding, the other routes this search returned are the only
    /// way out of a journey whose change has gone tight — without them the
    /// screen is a dead end until the Pin is deleted and rebuilt.
    @ViewBuilder
    private var alternativesSection: some View {
        let alternatives = presentation.alternativeItineraries
        if !alternatives.isEmpty {
            VStack(alignment: .leading, spacing: RTSpacing.listItem) {
                Divider()

                Button {
                    withAnimation(.snappy) {
                        showsAlternatives.toggle()
                    }
                } label: {
                    HStack(spacing: RTSpacing.small) {
                        Text(alternatives.count == 1 ? "1 other route" : "\(alternatives.count) other routes")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Image(systemName: showsAlternatives ? "chevron.up" : "chevron.down")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(showsAlternatives
                    ? "Hides the other routes from this search."
                    : "Shows the other routes from this search, which you can monitor instead.")

                if showsAlternatives {
                    ForEach(alternatives) { alternative in
                        ActiveItineraryAlternativeRow(itinerary: alternative) {
                            pendingSwitch = alternative
                        }
                    }
                }
            }
            .lightSurfaceForeground()
            .confirmationDialog(
                "Monitor this route instead?",
                isPresented: switchConfirmationPresented,
                titleVisibility: .visible
            ) {
                Button("Monitor this route") {
                    switchToPendingItinerary()
                }
                Button("Cancel", role: .cancel) {
                    pendingSwitch = nil
                }
            } message: {
                Text("RightTrain will follow this route instead. Your current Journey Pin is replaced.")
            }
        }
    }

    private var switchConfirmationPresented: Binding<Bool> {
        Binding {
            pendingSwitch != nil
        } set: { isPresented in
            if !isPresented {
                pendingSwitch = nil
            }
        }
    }

    private func switchToPendingItinerary() {
        guard let alternative = pendingSwitch else {
            return
        }
        pendingSwitch = nil
        Task {
            await activeWindowViewModel.switchSelectedItinerary(to: alternative)
        }
    }

    private func expandSelectedItineraryIfNeeded() {
        guard expandedItineraryIDs.isEmpty,
              let selectedID = presentation.selectedItinerary?.id else {
            return
        }
        expandSelectedItinerary(selectedID)
    }

    private func expandSelectedItinerary(_ selectedID: String?) {
        guard let selectedID else {
            return
        }
        expandedItineraryIDs.insert(selectedID)
    }

    private func isExpanded(_ option: ItineraryRecommendation) -> Bool {
        expandedItineraryIDs.contains(option.id)
    }

    private func toggleExpanded(_ option: ItineraryRecommendation) {
        if expandedItineraryIDs.contains(option.id) {
            expandedItineraryIDs.remove(option.id)
        } else {
            expandedItineraryIDs.insert(option.id)
        }
    }

    private var atOriginBanner: some View {
        let title: String = {
            if let firstLeg = itinerary.selectedItinerary.legs.first {
                let station = JourneyFormatting.stationDisplayName(name: firstLeg.originName, fallback: firstLeg.originCrs)
                return "You're at \(station)"
            }
            return "You're at the station"
        }()
        return HStack(alignment: .center, spacing: RTSpacing.listItem) {
            Image(systemName: "figure.walk.diamond.fill")
                .foregroundStyle(Color.rightTrainActionInk)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text("Tap I'm on this train once boarded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(Color.rightTrainActionInk.opacity(0.08), in: RoundedRectangle(cornerRadius: RTRadius.chip))
        .lightSurfaceForeground()
    }
}

/// One alternative route, compact enough to scan several at once: the times
/// that decide it, and the state of its change, which is the thing that makes
/// an alternative worth taking.
private struct ActiveItineraryAlternativeRow: View {
    var itinerary: ItineraryRecommendation
    var monitor: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: RTSpacing.listItem) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(ItineraryFormatting.departureText(itinerary)) - \(ItineraryFormatting.arrivalText(itinerary))")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()

                Text(summaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if itinerary.score.changeCount > 0 {
                    Label(connectionText, systemImage: connectionIcon)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(connectionTone.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: RTSpacing.small)

            Button("Monitor", action: monitor)
                .buttonStyle(.rtSecondary)
                .fixedSize()
                .accessibilityLabel("Monitor the \(ItineraryFormatting.departureText(itinerary)) route instead")
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
    }

    private var summaryText: String {
        var parts = [
            ItineraryFormatting.durationText(itinerary),
            ItineraryFormatting.changesText(itinerary)
        ]
        if let connection = itinerary.connections.first {
            let station = JourneyFormatting.stationDisplayName(
                name: connection.atName,
                fallback: connection.atCrs
            )
            parts.append("via \(station)")
        }
        return parts.joined(separator: " \u{00B7} ")
    }

    private var connection: ItineraryConnection? {
        itinerary.connections.first
    }

    private var connectionTone: StatusPill.Tone {
        guard let connection else {
            return .green
        }
        return ItineraryFormatting.connectionTone(connection)
    }

    private var connectionIcon: String {
        switch connection?.risk.status ?? "" {
        case "missed":
            return "xmark.octagon.fill"
        case "at_risk", "tight":
            return "exclamationmark.triangle.fill"
        default:
            return "arrow.triangle.branch"
        }
    }

    private var connectionText: String {
        guard let connection else {
            let margin = itinerary.score.minimumConnectionMarginMinutes
            return margin < 0 ? "\(abs(margin)) min short to change" : "\(margin) min to change"
        }
        return ItineraryFormatting.connectionRiskSummaryText(connection)
    }
}

private struct ActiveItineraryOptionCard: View {
    var itinerary: ItineraryRecommendation
    var emphasized: Bool
    var isExpanded: Bool
    var now: Date
    var toggleExpanded: () -> Void
    var loadDetail: (ItineraryLeg) async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                toggleExpanded()
            } label: {
                ActiveItineraryPlanHeroCard(
                    itinerary: itinerary,
                    now: now,
                    isExpanded: isExpanded
                )
            }
            .buttonStyle(.plain)
            .accessibilityHint(isExpanded ? "Hides the train legs for this journey." : "Shows each train leg for this journey.")

            if isExpanded {
                ActiveItineraryLegList(itinerary: itinerary, loadDetail: loadDetail)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .accessibilityIdentifier(emphasized ? "active-itinerary-recommended-option" : "active-itinerary-option")
    }
}

private struct ActiveItineraryPlanHeroCard: View {
    var itinerary: ItineraryRecommendation
    var now: Date
    var isExpanded: Bool

    private var firstLeg: ItineraryLeg? {
        itinerary.legs.first
    }

    private var departureDate: Date? {
        DateFormatting.date(from: firstLeg?.expectedDeparture ?? itinerary.expectedDeparture)
    }

    private var countdownText: String {
        guard let departureDate else {
            return "Dep \(ItineraryFormatting.departureText(itinerary))"
        }
        let seconds = departureDate.timeIntervalSince(now)
        if seconds > 60 {
            return "Leaves in \(Int((seconds / 60).rounded(.up))) min"
        }
        if seconds >= -60 {
            return "Leaves now"
        }
        return "Departed"
    }

    private var countdownTone: StatusPill.Tone {
        guard let departureDate else {
            return .amber
        }
        return departureDate < now ? .accent : .green
    }

    private var platform: ActiveWindowPresentation.PlatformDisplay {
        ActiveWindowPresentation.PlatformDisplay(
            primary: ItineraryFormatting.firstLegPlatformText(itinerary),
            secondary: nil,
            confirmed: ItineraryFormatting.firstLegPlatformConfirmed(itinerary)
        )
    }

    // Sits directly in the itinerary card: a filled box inside the card was
    // card-in-card chrome. The change and its risk are in the header and the
    // leg list, so the detail line keeps to times.
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .lastTextBaseline, spacing: RTSpacing.compact) {
                Text(countdownText)
                    .font(.title.weight(.bold))
                    .foregroundStyle(countdownTone.color)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(maxWidth: .infinity, alignment: .leading)

                CaptionedPlatformTile(platform: platform.value, size: .medium)
            }

            HStack(spacing: RTSpacing.small) {
                Text(detailLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                Spacer(minLength: 0)
                Label(isExpanded ? "Hide legs" : "Show legs", systemImage: isExpanded ? "chevron.up" : "chevron.down")
                    .labelStyle(.iconOnly)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
        .lightSurfaceForeground()
    }

    private var detailLine: String {
        [
            "Dep \(ItineraryFormatting.departureText(itinerary))",
            "Arr \(ItineraryFormatting.arrivalText(itinerary))",
            ItineraryFormatting.durationText(itinerary)
        ]
        .joined(separator: " · ")
    }
}

private struct ActiveItineraryLegList: View {
    var itinerary: ItineraryRecommendation
    var loadDetail: (ItineraryLeg) async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(itinerary.legs.enumerated()), id: \.element.id) { index, leg in
                Button {
                    Task { await loadDetail(leg) }
                } label: {
                    ActiveItineraryLegRow(
                        leg: leg,
                        isFirstLeg: index == 0,
                        isLastLeg: index == itinerary.legs.indices.last
                    )
                }
                .buttonStyle(.plain)
                .accessibilityHint("Shows the full journey calling points.")

                if let connection = ItineraryFormatting.connection(afterLegIndex: leg.legIndex, in: itinerary) {
                    ActiveItineraryConnectionRow(connection: connection)
                }

                if index != itinerary.legs.indices.last {
                    Divider()
                        .padding(.leading, 32)
                }
            }
        }
        .padding(.horizontal, 4)
        .lightSurfaceForeground()
    }
}

private struct ActiveItineraryConnectionRow: View {
    var connection: ItineraryConnection

    var body: some View {
        HStack(alignment: .center, spacing: RTSpacing.listItem) {
            Image(systemName: "arrow.triangle.branch")
                .font(.caption.weight(.semibold))
                .foregroundStyle(ItineraryFormatting.connectionTone(connection).color)
                .frame(width: RTSize.iconSmall)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(ItineraryFormatting.connectionTitleText(connection)) · \(ItineraryFormatting.connectionTransferText(connection))")
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

private struct ActiveItineraryLegRow: View {
    var leg: ItineraryLeg
    var isFirstLeg: Bool
    var isLastLeg: Bool

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
                Text(summaryText)
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

    private var summaryText: String {
        if isFirstLeg {
            return ItineraryFormatting.legSummaryText(leg, includesTimes: false, includesPlatform: false)
        }
        var parts = [
            "Dep \(ItineraryFormatting.timeText(leg.expectedDeparture ?? leg.scheduledDeparture))"
        ]
        if !isLastLeg {
            parts.append("Arr \(ItineraryFormatting.timeText(leg.expectedArrival ?? leg.scheduledArrival))")
        }
        if let platform = nonEmpty(leg.realtimePlatform) ?? nonEmpty(leg.originPlatform) {
            parts.append("Platform \(platform)")
        }
        if let operatorText = JourneyFormatting.operatorSummaryText(leg.journeyResult) {
            parts.append(operatorText)
        }
        return parts.joined(separator: " · ")
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

/// On-leg perspective: the user has boarded a non-final leg and has a
