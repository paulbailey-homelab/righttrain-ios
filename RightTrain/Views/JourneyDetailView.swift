import SwiftUI

struct JourneyDetailView: View {
    @Environment(JourneyDetailViewModel.self) private var viewModel
    @Environment(ActiveWindowViewModel.self) private var activeWindowViewModel
    var identity: JourneyDetailIdentity
    @State private var didAttemptInitialLoad = false

    init(identity: JourneyDetailIdentity) {
        self.identity = identity
    }

    private var detail: JourneyDetail? {
        viewModel.detail(for: identity)
    }

    var body: some View {
        Group {
            if let detail {
                let surface = detailSurface(detail)
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: RTSpacing.sectionGap) {
                        summarySection(detail, surface: surface)
                        // Only the calling-points timeline needs a clock; keeping
                        // the TimelineView this narrow stops the 15s tick from
                        // re-rendering the whole scroll view.
                        TimelineView(.periodic(from: .now, by: 15)) { context in
                            callingPointsSection(detail, surface: surface, now: context.date)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, RTSpacing.pageHorizontal)
                    .padding(.vertical, RTSpacing.cardPadding + 2)
                }
                .readableContentMargins()
                .safeAreaPadding(.bottom, RTSpacing.bottomSafeArea + RTSpacing.sectionGap)
                .scrollBounceBehavior(.always, axes: .vertical)
                .scrollIndicators(.visible)
                .statusSurface(surface)
            } else if didAttemptInitialLoad {
                EmptyStateView(
                    title: "Journey unavailable",
                    message: "RightTrain could not load this journey.",
                    symbolName: "tram.fill",
                    tint: .rightTrainActionInk
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, RTSpacing.pageHorizontal)
            } else {
                ProgressView()
                    .controlSize(.large)
                    .tint(Color.rightTrainActionInk)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("Loading journey")
            }
        }
        .background(Color.rightTrainSurfaceCream.ignoresSafeArea())
        .lightSurfaceForeground()
        .navigationTitle("Journey")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: identity) {
            await refreshDetailPeriodically()
        }
        .task(id: liveDetailRefreshKey) {
            guard liveDetailRefreshKey.hasPrefix("live|") else { return }
            await refreshSelectedJourneyDetail()
        }
    }

    private func refreshDetailPeriodically() async {
        await loadInitialDetailIfNeeded()
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled else {
                return
            }
            await refreshSelectedJourneyDetail()
        }
    }

    private func loadInitialDetailIfNeeded() async {
        if detail == nil {
            await refreshSelectedJourneyDetail()
        }
        didAttemptInitialLoad = true
    }

    private func refreshSelectedJourneyDetail() async {
        await viewModel.loadJourneyDetail(
            serviceID: identity.serviceID,
            originTPL: identity.originTPL,
            destinationTPL: identity.destinationTPL,
            showLoading: false
        )
    }

    private var liveDetailRefreshKey: String {
        if let journey = matchingActiveWindowJourney {
            return "live|window|\(activeWindowViewModel.liveRefreshGeneration)|\(JourneyLiveRefreshSignature.journey(journey))"
        }
        if let leg = matchingActiveItineraryLeg {
            return "live|itinerary|\(activeWindowViewModel.liveRefreshGeneration)|\(JourneyLiveRefreshSignature.leg(leg))"
        }
        return "none|\(identity.serviceID)|\(identity.originTPL ?? "")|\(identity.destinationTPL ?? "")"
    }

    private var matchingActiveWindowJourney: JourneyResult? {
        guard let window = activeWindowViewModel.activeWindow else {
            return nil
        }
        let recommendations = [window.selectedRecommendation] + window.recommendations
        return recommendations
            .map(\.journey)
            .first(where: matchesIdentity)
    }

    private var matchingActiveItineraryLeg: ItineraryLeg? {
        guard let itinerary = activeWindowViewModel.activeItinerary else {
            return nil
        }
        let candidates = itinerary.selectedItinerary.legs + itinerary.itineraries.flatMap { $0.legs }
        return candidates.first(where: matchesIdentity)
    }

    private func matchesIdentity(_ journey: JourneyResult) -> Bool {
        journey.serviceId == identity.serviceID &&
            (identity.originTPL == nil || journey.originTpl == identity.originTPL) &&
            (identity.destinationTPL == nil || journey.destinationTpl == identity.destinationTPL)
    }

    private func matchesIdentity(_ leg: ItineraryLeg) -> Bool {
        leg.serviceId == identity.serviceID &&
            (identity.originTPL == nil || leg.originTpl == identity.originTPL) &&
            (identity.destinationTPL == nil || leg.destinationTpl == identity.destinationTPL)
    }

    /// Nil unless this train is a leg of the itinerary currently being
    /// monitored. Deliberately not `matchingActiveItineraryLeg`, which also
    /// searches the alternatives so live data stays fresh for routes the
    /// traveller might switch to; describing a change from one of those would
    /// be describing a journey they are not on.
    private var activeItineraryLegContext: ItineraryLegContext? {
        guard let itinerary = activeWindowViewModel.activeItinerary else {
            return nil
        }
        return ItineraryFormatting.legContext(
            serviceID: identity.serviceID,
            originTPL: identity.originTPL,
            destinationTPL: identity.destinationTPL,
            in: itinerary
        )
    }

    private func summarySection(_ detail: JourneyDetail, surface: RTSurface) -> some View {
        VStack(alignment: .leading, spacing: RTSpacing.sectionGap) {
            platformIndicator(detail)

            if let legContext = activeItineraryLegContext {
                itineraryLegCard(legContext, surface: surface)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The itinerary this train belongs to: which leg, the change at the end
    /// of it and its risk, and the train being caught.
    private func itineraryLegCard(_ context: ItineraryLegContext, surface: RTSurface) -> some View {
        VStack(alignment: .leading, spacing: RTSpacing.small) {
            // No Spacer in the horizontal branch: a flexible child makes
            // ViewThatFits report a fit at any width, so the stacked
            // fallback would never be reached and the label would truncate.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: RTSpacing.small) {
                    legLabel(context, surface: surface)
                    riskPill(context)
                }
                VStack(alignment: .leading, spacing: RTSpacing.small) {
                    legLabel(context, surface: surface)
                    riskPill(context)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let connection = context.connection {
                Text(ItineraryFormatting.connectionTitleText(connection))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(surface.ink)
                    .fixedSize(horizontal: false, vertical: true)

                if let advice = ItineraryFormatting.connectionAdviceText(connection) {
                    Text(advice)
                        .font(.caption)
                        .foregroundStyle(surface.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let onward = context.onwardLeg {
                Text(onwardLegText(onward))
                    .font(.footnote)
                    .foregroundStyle(surface.dim)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            } else if context.isFinalLeg {
                Text("This is the last leg — you arrive on this train.")
                    .font(.footnote)
                    .foregroundStyle(surface.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .rtCard(padding: RTSpacing.cardPadding)
        // The change and its risk must reach VoiceOver as one statement; the
        // pill's colour is not a status signal on its own.
        .accessibilityElement(children: .combine)
    }

    private func legLabel(_ context: ItineraryLegContext, surface: RTSurface) -> some View {
        Label(
            "Leg \(context.legNumber) of \(context.legCount)",
            systemImage: "arrow.triangle.branch"
        )
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(surface.ink)
    }

    @ViewBuilder
    private func riskPill(_ context: ItineraryLegContext) -> some View {
        if let connection = context.connection {
            StatusPill(
                text: ItineraryFormatting.connectionRiskSummaryText(connection),
                tone: ItineraryFormatting.connectionTone(connection)
            )
            .fixedSize()
        }
    }

    private func onwardLegText(_ leg: ItineraryLeg) -> String {
        let time = ItineraryFormatting.timeText(leg.expectedDeparture ?? leg.scheduledDeparture)
        let destination = JourneyFormatting.stationDisplayName(
            name: leg.destinationName,
            fallback: leg.destinationCrs
        )
        return "Then the \(time) to \(destination)"
    }

    /// The note on the calling point where the traveller leaves this train for
    /// the next one. Without it the interchange is just another stop in the
    /// list of everywhere the train calls.
    private func interchangeStopNote(_ detail: JourneyDetail) -> (text: String, tone: StatusPill.Tone)? {
        guard let context = activeItineraryLegContext,
              let connection = context.connection else {
            return nil
        }
        guard let onward = context.onwardLeg else {
            return ("Change here", ItineraryFormatting.connectionTone(connection))
        }
        let time = ItineraryFormatting.timeText(onward.expectedDeparture ?? onward.scheduledDeparture)
        return ("Change here for the \(time)", ItineraryFormatting.connectionTone(connection))
    }

    // MARK: Platform indicator

    /// The train as the platform indicator at the traveller's station shows
    /// it: the train line with the traveller's arrival under it, a scrolling
    /// message, then the platform at double height.
    private func platformIndicator(_ detail: JourneyDetail) -> some View {
        let time = originStop(detail).map(BoardText.time) ?? "-"
        let destination = finalDestinationName(detail)
        let expected = signExpected(detail)
        let callingAt = signCallingAt(detail)
        let platform = detailPlatform(detail)
        let message = signMessage(detail)
        return DepartureBoard {
            DepartureBoardRow(time: time, destination: destination, expected: expected, callingAt: callingAt)
            BoardScroller(text: message)
            Text(platform.number.map { "Plat \($0)" } ?? "Plat TBC")
                .font(BoardFont.font(.title, weight: .bold))
                .foregroundStyle(
                    platform.state == .confirmed || platform.isChanged
                        ? DepartureBoardStyle.amber
                        : DepartureBoardStyle.dimAmber
                )
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            [
                "\(time) to \(destination), \(expected)",
                callingAt,
                platform.accessibilityLabel(),
                message
            ]
            .compactMap { $0 }
            .joined(separator: ". ")
        )
    }

    private func originStop(_ detail: JourneyDetail) -> JourneyStop? {
        detail.stops.isEmpty ? nil : detail.stops[segmentRange(detail).origin]
    }

    private func destinationStop(_ detail: JourneyDetail) -> JourneyStop? {
        detail.stops.isEmpty ? nil : detail.stops[segmentRange(detail).destination]
    }

    /// Where the train ends up, as boards name it even when the traveller
    /// gets off sooner.
    private func finalDestinationName(_ detail: JourneyDetail) -> String {
        if let last = detail.stops.last {
            return BoardText.station(last)
        }
        return JourneyFormatting.compactStationDisplayName(
            shortName: detail.destinationSixteenCharacterName,
            name: detail.destinationName,
            fallback: detail.destinationCrs
        )
    }

    private func signExpected(_ detail: JourneyDetail) -> String {
        if detail.cancelled {
            return "Cancelled"
        }
        guard let timing = originStop(detail)?.timing else {
            return "On time"
        }
        if timing.status == "actual" {
            return "Departed"
        }
        return timing.delayed ? "Exp \(timing.current.prefix(5))" : "On time"
    }

    /// "Calling at Moorgate 11:58": the traveller's stop and when the train
    /// gets there, unless that's where it ends up anyway.
    private func signCallingAt(_ detail: JourneyDetail) -> String? {
        guard !detail.cancelled,
              let stop = destinationStop(detail),
              stop.id != detail.stops.last?.id else {
            return nil
        }
        let arrival = stop.timing?.current ?? stop.publicArrival ?? stop.publicDeparture
        return ["Calling at \(BoardText.station(stop))", arrival.map { String($0.prefix(5)) }]
            .compactMap { $0 }
            .joined(separator: " ")
    }

    /// Darwin's reason first, since it's news, then who runs the train, how
    /// many coaches it has, and a warning when live running is patchy.
    private func signMessage(_ detail: JourneyDetail) -> String {
        var sentences: [String] = []
        if let reason = disruptionMessage(for: detail) {
            sentences.append(reason.hasSuffix(".") ? reason : "\(reason).")
        }
        let destination = JourneyFormatting.stationDisplayName(
            name: detail.stops.last?.name ?? detail.destinationName,
            fallback: detail.destinationCrs
        )
        let operatorName = JourneyFormatting.operatorDisplayText(detail)
        if operatorName != "Not available" {
            let article = "AEIOU".contains(operatorName.prefix(1).uppercased()) ? "an" : "a"
            sentences.append("This is \(article) \(operatorName) service to \(destination).")
        } else {
            sentences.append("This train is for \(destination).")
        }
        if let count = detail.coachCount, count > 0 {
            let about = detail.coachCountApproximate == true ? "about " : ""
            sentences.append("This train is formed of \(about)\(count) \(count == 1 ? "coach" : "coaches").")
        }
        if !hasLiveData(detail) {
            sentences.append("Live running information is limited for this train.")
        }
        return BoardText.boardSafe(sentences.joined(separator: "  "))
    }

    // MARK: Calling points board

    /// Every stop the train makes, as a calling points board lists them.
    /// The traveller's stretch is lit and the rest unlit, as are stops
    /// already passed; a dot in the margin shows where the train is.
    private func callingPointsSection(_ detail: JourneyDetail, surface: RTSurface, now: Date) -> some View {
        let range = segmentRange(detail)
        let interchange = interchangeStopNote(detail)
        let trainPosition = currentTrainPosition(detail, now: now)
        return DepartureBoard {
            ConcourseBoardHeader(placeTitle: "Calling at")
            ForEach(Array(detail.stops.enumerated()), id: \.element.id) { index, stop in
                let inJourney = index >= range.origin && index <= range.destination
                let isPassed = stopIsPassed(at: index, trainPosition: trainPosition)
                CallingPointBoardRow(
                    time: BoardText.time(stop),
                    station: BoardText.station(stop),
                    // Platforms matter where you board and get off.
                    platform: index == range.origin || index == range.destination ? stopPlatform(stop) : nil,
                    expected: BoardText.expected(stop),
                    note: stopNote(stop, change: index == range.destination ? interchange?.text : nil),
                    isLit: inJourney && !isPassed,
                    marker: marker(at: index, trainPosition: trainPosition)
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(stopAccessibilityLabel(stop, change: index == range.destination ? interchange?.text : nil))
            }
        }
    }

    private func stopPlatform(_ stop: JourneyStop) -> PlatformValue {
        PlatformValue(
            stop.realtime?.platform ?? stop.scheduledPlatform,
            confirmed: stop.realtime?.platform != nil && stop.realtime?.platformConfirmed == true
        )
    }

    /// The change for the next train, then any delay reason for this stop.
    private func stopNote(_ stop: JourneyStop, change: String?) -> String? {
        var notes: [String] = []
        if let change {
            notes.append(change)
        }
        if let reason = stop.realtime?.reasonText, !reason.isEmpty {
            if let location = stop.realtime?.reasonLocationName, !location.isEmpty {
                notes.append("\(reason) near \(location)")
            } else {
                notes.append(reason)
            }
        }
        return notes.isEmpty ? nil : BoardText.boardSafe(notes.joined(separator: ". "))
    }

    private func marker(at index: Int, trainPosition: JourneyTrainPosition) -> CallingPointBoardRow.Marker {
        if trainPosition.stationIndex == index {
            return .here
        }
        if let after = trainPosition.betweenAfterIndex, after + 1 == index {
            return .approaching
        }
        return .none
    }

    private func stopAccessibilityLabel(_ stop: JourneyStop, change: String?) -> String {
        [
            JourneyFormatting.stationDisplayName(name: stop.name, fallback: stop.crs ?? stop.tpl),
            BoardText.time(stop),
            BoardText.expected(stop),
            stopNote(stop, change: change)
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty && $0 != "-" }
        .joined(separator: ", ")
    }

    private func detailSurface(_ detail: JourneyDetail) -> RTSurface {
        if detail.cancelled {
            return .bad
        }
        if let statusKind = detail.statusKind?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            switch statusKind {
            case "cancelled", "missed":
                return .bad
            case "delayed", "unreported", "not_reported", "at_risk":
                return .warn
            default:
                break
            }
        }
        switch detail.displayStatus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "cancelled", "missed":
            return .bad
        case "delayed", "unreported", "not_reported", "at_risk":
            return .warn
        default:
            return .good
        }
    }

    private func disruptionMessage(for detail: JourneyDetail) -> String? {
        if detail.displayStatus == "arrived" {
            return nil
        }
        if detail.cancelled {
            return detail.cancellationReasonText ?? "This service is cancelled."
        }
        if let reason = detail.lateReasonText, !reason.isEmpty {
            return reason
        }
        return nil
    }

    /// The traveller's boarding and alighting stops within the service's
    /// full calling pattern. A train opened from a journey often runs past
    /// the traveller's destination, so the service's last stop is the wrong
    /// place to read the arrival from.
    private func segmentRange(_ detail: JourneyDetail) -> (origin: Int, destination: Int) {
        JourneyFormatting.segmentStopRange(
            detail.stops,
            originTPL: identity.originTPL ?? detail.originTpl,
            destinationTPL: identity.destinationTPL ?? detail.destinationTpl
        )
    }

    private func detailPlatform(_ detail: JourneyDetail) -> PlatformValue {
        guard !detail.stops.isEmpty else { return .unknown }
        let stop = detail.stops[segmentRange(detail).origin]
        let confirmed = stop.realtime?.platform != nil && stop.realtime?.platformConfirmed == true
        return PlatformValue(stop.realtime?.platform ?? stop.scheduledPlatform, confirmed: confirmed)
    }

    private func hasLiveData(_ detail: JourneyDetail) -> Bool {
        detail.reportState == "complete" || detail.realtimeSource?.isEmpty == false
    }

    private func currentTrainPosition(_ detail: JourneyDetail, now: Date) -> JourneyTrainPosition {
        JourneyFormatting.currentTrainPosition(detail, now: now)
    }

    private func stopIsPassed(at index: Int, trainPosition: JourneyTrainPosition) -> Bool {
        if let betweenAfterIndex = trainPosition.betweenAfterIndex {
            return index <= betweenAfterIndex
        }
        if let stationIndex = trainPosition.stationIndex {
            return index < stationIndex
        }
        return false
    }

}
