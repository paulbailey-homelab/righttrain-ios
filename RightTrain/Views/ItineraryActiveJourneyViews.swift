import SwiftUI

private enum ActiveItineraryConfirmation {
    case recovery
    case unpin

    var title: String {
        switch self {
        case .recovery:
            return "Not on this journey?"
        case .unpin:
            return "Unpin this journey?"
        }
    }

    var message: String {
        switch self {
        case .recovery:
            return "RightTrain will look for a replacement journey from your current interchange."
        case .unpin:
            return "This removes the current Journey Pin from RightTrain."
        }
    }
}

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
            return ItineraryFormatting.routeText(selectedItinerary)
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
            routeContextText: JourneyFormatting.crsRouteText(
                originCrs: selected.originCrs,
                destinationCrs: selected.destinationCrs
            ),
            statusText: statusText.isEmpty ? pillText : statusText,
            statusTone: isOffline ? .amber : status.tone,
            timingText: "Dep \(ItineraryFormatting.departureText(selected)) · Arr \(ItineraryFormatting.arrivalText(selected))",
            platformText: JourneyFormatting.platformStateText(primary: ItineraryFormatting.firstLegPlatformText(selected)),
            nextActionText: nextActionText(for: selected, isOffline: isOffline),
            freshnessText: isOffline
                ? "Offline · showing saved journey data"
                : ActiveWindowPresentation.freshnessText(updatedAt: latestRealtimeUpdate(in: selected), now: now)
        )
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
            let platformText = JourneyFormatting.platformStateText(primary: platform)
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
            VStack(alignment: .leading, spacing: RTSpacing.sectionGap) {
                LiveGlancePanel(
                    content: presentation.liveGlanceContent(
                        now: context.date,
                        isOffline: isOffline
                    )
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

/// Planning/at-origin perspective: focuses on the selected monitored itinerary,
/// with alternate options directly available below it.
struct ActiveItineraryView: View {
    @Environment(ActiveWindowViewModel.self) private var activeWindowViewModel
    @State private var expandedItineraryIDs: Set<String> = []
    var itinerary: ItinerarySubscription
    var loadDetail: (ItineraryLeg) async -> Void

    private var presentation: ActiveItineraryPresentation {
        ActiveItineraryPresentation(itinerary: itinerary)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            ActiveItineraryCard {
                ActiveItineraryHeader(presentation: presentation)

                if presentation.phase == .atOrigin {
                    atOriginBanner
                }

                selectedJourneySection(now: context.date)
            }
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
            LazyVStack(alignment: .leading, spacing: 10) {
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
                        .buttonStyle(.plain)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.rightTrainPaperCream)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Color.rightTrainActionInk, in: Capsule())
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
        return HStack(alignment: .center, spacing: 10) {
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
                    emphasized: emphasized,
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
    var emphasized: Bool
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
            secondary: nil
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Text(countdownText)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(countdownTone.color)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(maxWidth: .infinity, alignment: .leading)

                PlatformSquareChip(platform: platform)

                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
                    .accessibilityHidden(true)
            }

            Text(detailLine)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(RTSpacing.cardPadding)
        .background(emphasized ? Color.rightTrainActionInk.opacity(0.10) : Color.rightTrainPaperCream, in: RoundedRectangle(cornerRadius: RTRadius.card))
        .lightSurfaceForeground()
        .overlay {
            RoundedRectangle(cornerRadius: RTRadius.card)
                .stroke(emphasized ? Color.rightTrainActionInk.opacity(0.24) : Color.rightTrainInkFaint, lineWidth: 1)
        }
    }

    private var detailLine: String {
        var parts = [
            "Dep \(ItineraryFormatting.departureText(itinerary))",
            "Final arr \(ItineraryFormatting.arrivalText(itinerary))",
            ItineraryFormatting.durationText(itinerary),
            ItineraryFormatting.changesText(itinerary)
        ]
        if itinerary.score.changeCount > 0 {
            if let connection = itinerary.connections.first {
                parts.append(ItineraryFormatting.connectionRiskSummaryText(connection))
            } else {
                parts.append(changeMarginText)
            }
        }
        if let status = ItineraryFormatting.anomalousStatusDisplay(itinerary),
           !status.text.localizedCaseInsensitiveContains("connection") {
            parts.append(status.text.trimmingCharacters(in: CharacterSet(charactersIn: ".")))
        }
        return parts.joined(separator: " · ")
    }

    private var changeMarginText: String {
        let margin = itinerary.score.minimumConnectionMarginMinutes
        if margin < 0 {
            return "\(abs(margin)) min short"
        }
        return "\(margin) min to change"
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
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.rightTrainSurfaceCream, in: RoundedRectangle(cornerRadius: RTRadius.chip))
        .lightSurfaceForeground()
    }
}

private struct ActiveItineraryConnectionRow: View {
    var connection: ItineraryConnection

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "arrow.triangle.branch")
                .font(.caption.weight(.semibold))
                .foregroundStyle(ItineraryFormatting.connectionTone(connection).color)
                .frame(width: 22)

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
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: leg.cancelled ? "xmark.octagon.fill" : "tram.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(leg.cancelled ? Color.rightTrainDanger : Color.rightTrainActionInk)
                .frame(width: 22)

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
/// connection to make.
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
            borderColor: approachingInterchange ? Color.rightTrainAmber.opacity(0.55) : Color.rightTrainInkFaint,
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

        return HStack(alignment: .center, spacing: 10) {
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

        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: "figure.walk")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.rightTrainActionInk)
                .frame(width: 22)

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

private struct ActiveItineraryHeader: View {
    @Environment(ActiveWindowViewModel.self) private var activeWindowViewModel
    @State private var confirmation: ActiveItineraryConfirmation?
    @State private var isDeleting = false
    var presentation: ActiveItineraryPresentation
    var recoveryFromCrs: String?

    var body: some View {
        PinnedObjectHeader(
            kind: .journey,
            showsKindBadge: false,
            showsActionMenu: recoveryFromCrs != nil,
            title: presentation.routeTitle,
            summary: presentation.subtitleText,
            statusText: presentation.headerStatusText,
            statusTone: presentation.headerStatusTone,
            primaryAction: PinnedHeaderPrimaryAction(
                title: "Unpin",
                systemImage: "pin.slash",
                role: .destructive,
                accessibilityHint: "Removes this Journey Pin.",
                isDisabled: isDeleting,
                action: { confirmation = .unpin }
            )
        ) {
            menuActions
        }
        .disabled(isDeleting)
        .confirmationDialog("Not on this journey?", isPresented: recoveryConfirmationPresented, titleVisibility: .visible) {
            Button("Replan from current station", role: .destructive) {
                replanFromCurrentStation()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(ActiveItineraryConfirmation.recovery.message)
        }
        .alert("Unpin this journey?", isPresented: unpinAlertPresented) {
            Button("Unpin Journey", role: .destructive) {
                unpinJourney()
            }
            Button("Keep Pin", role: .cancel) {}
        } message: {
            Text(ActiveItineraryConfirmation.unpin.message)
        }
    }

    @ViewBuilder
    private var menuActions: some View {
        if recoveryFromCrs != nil {
            Button(role: .destructive) {
                confirmation = .recovery
            } label: {
                Label("Not on this journey", systemImage: "arrow.triangle.2.circlepath")
            }
        }
    }

    private var recoveryConfirmationPresented: Binding<Bool> {
        Binding {
            confirmation == .recovery
        } set: { isPresented in
            if !isPresented {
                confirmation = nil
            }
        }
    }

    private var unpinAlertPresented: Binding<Bool> {
        Binding {
            confirmation == .unpin
        } set: { isPresented in
            if !isPresented {
                confirmation = nil
            }
        }
    }

    private func replanFromCurrentStation() {
        guard let recoveryFromCrs else { return }
        Task {
            await activeWindowViewModel.replanItineraryFromCurrentStation(
                fromCrs: recoveryFromCrs,
                itineraryID: presentation.itinerary.id
            )
        }
    }

    private func unpinJourney() {
        guard !isDeleting else { return }
        isDeleting = true
        Task {
            await activeWindowViewModel.deleteActiveItinerary()
            await MainActor.run {
                isDeleting = false
            }
        }
    }
}

private struct ActiveItineraryCard<Content: View>: View {
    var borderColor = Color.rightTrainInkFaint
    var borderWidth: CGFloat = 1
    private let content: () -> Content

    init(
        borderColor: Color = Color.rightTrainInkFaint,
        borderWidth: CGFloat = 1,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.borderColor = borderColor
        self.borderWidth = borderWidth
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            content()
        }
        .padding(RTSpacing.cardPadding)
        .background(Color.rightTrainPaperCream, in: RoundedRectangle(cornerRadius: RTRadius.card))
        .lightSurfaceForeground()
        .overlay {
            RoundedRectangle(cornerRadius: RTRadius.card)
                .stroke(borderColor, lineWidth: borderWidth)
        }
    }
}

#Preview("Pinned Itinerary - Planning") {
    PreviewAppContainer {
        ScrollView {
            PerspectiveActiveItineraryView(
                itinerary: PreviewFixtures.activeItinerary(phase: .planning),
                loadDetail: { _ in }
            )
            .padding(RTSpacing.pageHorizontal)
        }
        .background(Color.rightTrainSurfaceCream)
    }
}

#Preview("Pinned Itinerary - Change") {
    PreviewAppContainer {
        ScrollView {
            PerspectiveActiveItineraryView(
                itinerary: PreviewFixtures.activeItinerary(phase: .approachingInterchange, currentLegIndex: 0),
                loadDetail: { _ in }
            )
            .padding(RTSpacing.pageHorizontal)
        }
        .background(Color.rightTrainSurfaceCream)
    }
}

#Preview("Pinned Itinerary - Final") {
    PreviewAppContainer {
        ScrollView {
            PerspectiveActiveItineraryView(
                itinerary: PreviewFixtures.activeItinerary(phase: .onFinalLeg, currentLegIndex: 1),
                loadDetail: { _ in }
            )
            .padding(RTSpacing.pageHorizontal)
        }
        .background(Color.rightTrainSurfaceCream)
    }
}
