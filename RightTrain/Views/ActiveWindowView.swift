import CoreLocation
import SwiftUI

struct ActiveWindowView: View {
    @Environment(ActiveWindowViewModel.self) private var activeWindowViewModel
    @Environment(ConnectivityService.self) private var connectivityService
    @State private var showCancelledTrains = false
    @State private var showDepartedTrains = false
    @State private var isConfirmingDelete = false
    @State private var isDeleting = false
    var window: WindowSubscription
    var showsJustDepartedPrompt = true
    var layout: PinnedLayout = .column
    /// Shown under the trailing column in the board layout, where the page
    /// no longer scrolls as one.
    var boardFooter: AnyView? = nil
    var loadDetail: (DirectWindowRecommendation) async -> Void

    enum PinnedLayout {
        /// One column inside the tab's scroll view.
        case column
        /// Wide screens: the countdown and platform stay put on the left
        /// while the rest of the search scrolls on the right.
        case board
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let presentation = ActiveWindowPresentation(window: window, now: context.date)
            content(presentation: presentation, now: context.date)
        }
        .accessibilityAction(named: unpinActionLabel) {
            requestDeleteConfirmation()
        }
        .alert("Unpin this \(unpinTargetName)?", isPresented: $isConfirmingDelete) {
            Button("Unpin \(unpinTargetName.capitalized)", role: .destructive) {
                deleteActiveWindow()
            }
            Button("Keep Pin", role: .cancel) {}
        } message: {
            Text(unpinTargetName == "search" ? "RightTrain will stop watching these trains." : "RightTrain will stop watching this journey.")
        }
    }

    @ViewBuilder
    private func content(presentation: ActiveWindowPresentation, now: Date) -> some View {
        let surface = presentation.heroSurface
        let heroCountdown = ActiveWindowPresentation.countdown(for: presentation.heroRecommendation, now: now)
        let showsHero = presentation.shouldShowHero(now: now)
        let glance = ActiveWindowPresentation.liveGlanceContent(
            for: presentation.heroRecommendation,
            routeTitle: presentation.routeTitle,
            needProfile: .oneOffDirectTrip,
            now: now,
            isOffline: shouldPresentOfflineGlance(for: presentation.heroRecommendation)
        )

        let isStale = glance.moment == .staleData || glance.moment == .offline

        switch layout {
        case .column:
            VStack(alignment: .leading, spacing: 0) {
                leadingColumn(presentation: presentation, now: now, surface: surface, countdown: heroCountdown, showsHero: showsHero, glance: glance, isStale: isStale)
                trailingColumn(presentation: presentation, now: now, surface: surface, countdown: heroCountdown)
            }
        case .board:
            HStack(alignment: .top, spacing: RTSpacing.sectionGap) {
                ScrollView {
                    leadingColumn(presentation: presentation, now: now, surface: surface, countdown: heroCountdown, showsHero: showsHero, glance: glance, isStale: isStale)
                        .padding(.vertical, RTSpacing.pageVertical)
                }
                .frame(width: RTLayout.boardLeadingWidth)
                .scrollBounceBehavior(.basedOnSize)

                ScrollView {
                    VStack(alignment: .leading, spacing: RTSpacing.sectionGap) {
                        trailingColumn(presentation: presentation, now: now, surface: surface, countdown: heroCountdown)
                        boardFooter
                    }
                    .padding(.vertical, RTSpacing.pageVertical)
                }
            }
        }
    }

    @ViewBuilder
    private func leadingColumn(
        presentation: ActiveWindowPresentation,
        now: Date,
        surface: RTSurface,
        countdown heroCountdown: ActiveWindowPresentation.CountdownDisplay,
        showsHero: Bool,
        glance: ActiveWindowPresentation.LiveGlanceContent,
        isStale: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            statusPillRow(
                presentation: presentation,
                surface: surface,
                freshnessText: showsHero ? glance.freshnessText : nil,
                isStale: isStale
            )
            .padding(.bottom, showsHero ? RTSpacing.small : RTSpacing.compact)

            if !showsHero {
                LiveGlancePanel(content: glance)
                    .padding(.bottom, RTSpacing.sectionGap)
            }

            // ── Hero block ────────────────────────────────────────────────
            if showsHero {
                StatusFirstHeroBlock(
                    presentation: presentation,
                    countdown: heroCountdown,
                    surface: surface,
                    now: now,
                    freshnessText: glance.freshnessText,
                    isStale: isStale,
                    loadDetail: { await loadDetail(presentation.heroRecommendation) },
                    requestUnpin: requestDeleteConfirmation
                )
                .padding(.bottom, RTSpacing.sectionGap)
            }
        }
    }

    @ViewBuilder
    private func trailingColumn(
        presentation: ActiveWindowPresentation,
        now: Date,
        surface: RTSurface,
        countdown heroCountdown: ActiveWindowPresentation.CountdownDisplay
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if presentation.heroIsPinnedTrain {
                pinnedNextStepCard(
                    presentation: presentation,
                    countdown: heroCountdown,
                    surface: surface
                )
                .padding(.bottom, RTSpacing.sectionGap)
            }

            // ── "Or any of these" list (window mode only) ─────────────────
            if !presentation.heroIsPinnedTrain {
                let future = presentation.futureDepartures(now: now)
                let cancelled = presentation.cancelledDepartures(now: now)

                if !future.isEmpty || !cancelled.isEmpty {
                    upcomingListSection(
                        presentation: presentation,
                        future: future,
                        cancelled: cancelled,
                        surface: surface,
                        now: now
                    )
                }
            }
        }
    }

    /// One line for what RightTrain is doing and how fresh the data is,
    /// instead of separate rows around the hero.
    private func statusPillRow(
        presentation: ActiveWindowPresentation,
        surface: RTSurface,
        freshnessText: String?,
        isStale: Bool
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: RTSpacing.small) {
                statusPill(presentation: presentation, surface: surface)
                Spacer(minLength: RTSpacing.small)
                if let freshnessText {
                    freshnessLabel(freshnessText, isStale: isStale)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                statusPill(presentation: presentation, surface: surface)
                if let freshnessText {
                    freshnessLabel(freshnessText, isStale: isStale)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pinnedActionsToolbar(
            primaryAction: PinnedHeaderPrimaryAction(
                title: presentation.heroIsPinnedTrain ? "Unpin Journey" : "Unpin Search",
                systemImage: "pin.slash",
                role: .destructive,
                accessibilityHint: "Removes this \(presentation.heroIsPinnedTrain ? "Journey" : "Search") Pin.",
                isDisabled: isDeleting,
                action: requestDeleteConfirmation
            ),
            showsMenu: false
        ) {
            EmptyView()
        }
    }

    private func statusPill(presentation: ActiveWindowPresentation, surface: RTSurface) -> some View {
        StatusPill(
            text: pillStatusText(presentation: presentation),
            tone: surface.pillTone,
            style: .dot
        )
        .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder
    private func freshnessLabel(_ text: String, isStale: Bool) -> some View {
        if isStale {
            Label(text, systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.rightTrainAmber)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .accessibilityLabel("Live data may be out of date. \(text)")
        } else {
            LiveFreshnessText(text: text)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private func pillStatusText(presentation: ActiveWindowPresentation) -> String {
        if presentation.heroIsPinnedTrain {
            if let statusDisplay = ActiveWindowPresentation.heroStatusDisplay(for: presentation.heroRecommendation) {
                return "\(statusDisplay.text) · live"
            }
            return "On time · live"
        }
        return "Watching \(windowDurationText)"
    }

    @ViewBuilder
    private func upcomingListSection(
        presentation: ActiveWindowPresentation,
        future: [DirectWindowRecommendation],
        cancelled: [DirectWindowRecommendation],
        surface: RTSurface,
        now: Date
    ) -> some View {
        VStack(alignment: .leading, spacing: RTSpacing.small) {
            Text("Other trains in this search")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 2)

            // A concourse board: chronological, cancelled trains in place,
            // as the station shows them.
            DepartureBoard {
                ConcourseBoardHeader()
                ForEach(JourneyFormatting.chronologicalRecommendations(future + cancelled)) { recommendation in
                    StatusFirstTrainRow(
                        recommendation: recommendation,
                        surface: surface,
                        isPinned: activeWindowViewModel.pinnedLiveActivityServiceID == recommendation.journey.serviceId,
                        now: now,
                        loadDetail: { await loadDetail(recommendation) },
                        togglePinned: { await activeWindowViewModel.togglePinnedLiveActivity(for: recommendation) }
                    )
                }
            }
        }
    }

    private func pinnedNextStepCard(
        presentation: ActiveWindowPresentation,
        countdown: ActiveWindowPresentation.CountdownDisplay,
        surface: RTSurface
    ) -> some View {
        let journey = presentation.heroRecommendation.journey

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: RTSpacing.compact) {
                Image(systemName: countdown.isDeparted ? "tram.fill" : "figure.walk")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(surface.accent)
                    .frame(width: RTSize.iconMedium)

                VStack(alignment: .leading, spacing: 4) {
                    Text(pinnedNextStepTitle(journey: journey, countdown: countdown))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.rightTrainInk)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(pinnedNextStepMessage(countdown: countdown))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, RTSpacing.compact)

            Divider()
                .padding(.leading, RTSize.iconMedium + RTSpacing.compact)

            Button {
                Task { await loadDetail(presentation.heroRecommendation) }
            } label: {
                HStack(spacing: RTSpacing.compact) {
                    Image(systemName: "list.bullet")
                        .frame(width: RTSize.iconMedium)
                    Text("View stops")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .font(.body)
                .foregroundStyle(Color.rightTrainActionInk)
                .frame(minHeight: RTSize.tapTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, RTSpacing.cardPadding)
        .background(Color.rightTrainPaperCream, in: RoundedRectangle(cornerRadius: RTRadius.card, style: .continuous))
    }

    private func pinnedNextStepTitle(
        journey: JourneyResult,
        countdown: ActiveWindowPresentation.CountdownDisplay
    ) -> String {
        if countdown.isDeparted {
            return "Follow the stops for this journey"
        }
        let departure = JourneyFormatting.departureText(journey)
        let platform = ActiveWindowPresentation.platformDisplay(for: journey).primary
        if let readablePlatform = readablePlatform(platform) {
            return "Go to platform \(readablePlatform) for \(departure)"
        }
        return "Watch for the platform before \(departure)"
    }

    private func pinnedNextStepMessage(countdown: ActiveWindowPresentation.CountdownDisplay) -> String {
        if countdown.isDeparted {
            return "RightTrain will keep this Journey Pin live while you travel. If you are not on board, unpin and choose another train."
        }
        return "RightTrain will keep watching this train and alert you if the platform, time, or status changes."
    }

    private func readablePlatform(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed != "-",
              trimmed.uppercased() != "TBC" else {
            return nil
        }
        if trimmed.uppercased().hasPrefix("P"), trimmed.count > 1 {
            return String(trimmed.dropFirst())
        }
        return trimmed
    }

    private var windowDurationText: String {
        let minutes = window.windowMinutes
        guard minutes >= 60 else {
            return "\(minutes)m window"
        }
        let hours = minutes / 60
        let remainder = minutes % 60
        if remainder == 0 {
            return "\(hours)h window"
        }
        return "\(hours)h \(remainder)m window"
    }

    private func shouldPresentOfflineGlance(for recommendation: DirectWindowRecommendation) -> Bool {
        if connectivityService.backendUnavailable {
            return true
        }
        let offlineFields: [String?] = [
            recommendation.journey.status,
            recommendation.journey.statusText,
            recommendation.journey.compactStatusText,
            recommendation.journey.statusKind
        ]
        return offlineFields.contains { value in
            value?.range(of: "offline", options: .caseInsensitive) != nil
        }
    }

    private func unpinButton(for presentation: ActiveWindowPresentation) -> some View {
        Button(role: .destructive) {
            requestDeleteConfirmation()
        } label: {
            Label("Unpin this \(presentation.heroIsPinnedTrain ? "journey" : "search")", systemImage: "pin.slash")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(Color.rightTrainDanger)
        .controlSize(.large)
        .disabled(isDeleting)
        .padding(.top, 4)
        .accessibilityHint("Removes this \(presentation.heroIsPinnedTrain ? "Journey" : "Search") Pin.")
    }

    private var unpinTargetName: String {
        window.pinnedTrainServiceId == nil ? "search" : "journey"
    }

    private var unpinActionLabel: String {
        "Unpin \(unpinTargetName)"
    }

    private func trainAccessibilityLabel(for recommendation: DirectWindowRecommendation) -> String {
        "\(trainAccessibilityValue(for: recommendation)), \(JourneyFormatting.movementStatusText(recommendation.journey, score: recommendation.score))"
    }

    private func heroAccessibilityLabel(
        title: String?,
        for recommendation: DirectWindowRecommendation,
        countdown: ActiveWindowPresentation.CountdownDisplay
    ) -> String {
        [
            title,
            countdown.text.lowercased(),
            trainAccessibilityValue(for: recommendation),
            JourneyFormatting.movementStatusText(recommendation.journey, score: recommendation.score)
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }

    private func visibleHeroTitle(for presentation: ActiveWindowPresentation) -> String? {
        guard !(presentation.heroTitle == "Recommended train" && presentation.recommendations.count == 1) else {
            return nil
        }
        return presentation.heroTitle
    }

    private func trainAccessibilityValue(for recommendation: DirectWindowRecommendation) -> String {
        let journey = recommendation.journey
        let operatorText = JourneyFormatting.operatorSummaryText(journey).map { ", operated by \($0)" } ?? ""
        return "\(JourneyFormatting.departureText(journey)) to \(JourneyFormatting.arrivalText(journey)), \(JourneyFormatting.routeText(journey))\(operatorText)"
    }

    private func requestDeleteConfirmation() {
        guard !isDeleting else { return }
        isConfirmingDelete = true
    }

    private func deleteActiveWindow() {
        guard !isDeleting else { return }
        isDeleting = true
        Task {
            await activeWindowViewModel.deleteActiveWindow()
            await MainActor.run {
                isDeleting = false
            }
        }
    }
}

struct ActiveOnTrainJourneyView: View {
    @Environment(JourneyDetailViewModel.self) private var journeyDetailViewModel
    @Environment(ActiveWindowViewModel.self) private var activeWindowViewModel
    @State private var isClearingPinned = false
    @State private var isConfirmingUnpin = false
    @State private var locationFeed = OnTrainLocationFeed()
    @State private var riderLocation: CLLocation?

    var window: WindowSubscription
    var recommendation: DirectWindowRecommendation

    private var identity: JourneyDetailIdentity {
        JourneyDetailIdentity(
            serviceID: recommendation.journey.serviceId,
            originTPL: recommendation.journey.originTpl,
            destinationTPL: recommendation.journey.destinationTpl
        )
    }

    private var journey: JourneyResult {
        matchingActiveWindowJourney ?? recommendation.journey
    }

    private var detail: JourneyDetail? {
        journeyDetailViewModel.detail(for: identity)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            VStack(alignment: .leading, spacing: 18) {
                summarySection(now: context.date)

                if let detail {
                    stationsSection(detail: detail, now: context.date)
                } else {
                    loadingStationsSection
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: identity) {
            await refreshDetailPeriodically()
        }
        .onAppear {
            locationFeed.onUpdate = { riderLocation = $0 }
            locationFeed.start()
        }
        .onDisappear {
            locationFeed.stop()
        }
        .task(id: liveDetailRefreshKey) {
            guard liveDetailRefreshKey.hasPrefix("live|") else { return }
            await refreshSelectedJourneyDetail()
        }
        .alert("Unpin this journey?", isPresented: $isConfirmingUnpin) {
            Button("Unpin Journey", role: .destructive) {
                clearPinnedTrain()
            }
            Button("Keep Pin", role: .cancel) {}
        } message: {
            Text("RightTrain will stop watching this journey.")
        }
    }

    private func summarySection(now: Date) -> some View {
        VStack(alignment: .leading, spacing: RTSpacing.cardPadding) {
            PinnedObjectHeader(
                kind: .journey,
                showsKindBadge: false,
                showsActionMenu: false,
                title: "\(JourneyFormatting.isArrived(journey) ? "Arrived at" : "On board to") \(JourneyFormatting.destinationStationText(journey))",
                summary: journeyPinSummary,
                statusText: anomalousStatus?.text,
                statusTone: anomalousStatus?.tone ?? .accent,
                updatedAt: journey.realtimeUpdatedAt.flatMap(DateFormatting.date(from:)),
                now: Date(),
                primaryAction: PinnedHeaderPrimaryAction(
                    title: "Unpin Journey",
                    systemImage: "pin.slash",
                    role: .destructive,
                    accessibilityHint: "Removes this Journey Pin.",
                    isDisabled: isClearingPinned,
                    action: requestUnpinConfirmation
                )
            ) {
                EmptyView()
            }

            onBoardSign(now: now)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var journeyPinSummary: String {
        let origin = JourneyFormatting.originStationText(journey)
        var parts = ["From \(origin)"]
        if let operatorText = JourneyFormatting.operatorSummaryText(journey) {
            parts.append(operatorText)
        }
        return parts.joined(separator: " · ")
    }

    private var anomalousStatus: ActiveWindowPresentation.StatusDisplay? {
        ActiveWindowPresentation.heroStatusDisplay(for: recommendation)
    }

    // MARK: On-board sign

    /// The traveller's stop as the display in the carriage shows it. The
    /// boarded train's own details (its time, where it ends up, who runs
    /// it) have done their job: the sign gives the stop with Expected and
    /// the next stop under it, a message line, then the arrival time and
    /// time left at double height. The arrival platform is only a mention
    /// in the message.
    private func onBoardSign(now: Date) -> some View {
        let arrival = JourneyFormatting.arrivalDisplay(journey)
        let arrivalTime = arrival.currentText ?? arrival.scheduledText
        let nextStop = detail.flatMap { nextStopText($0, now: now) }
        let countdown = arrivalCountdownText(now: now)
        let message = onBoardMessage
        let isCancelled = JourneyFormatting.isCancelled(journey)
        return DepartureBoard {
            DepartureBoardRow(
                time: nil,
                destination: JourneyFormatting.compactDestinationStationText(journey),
                expected: arrivalExpected,
                callingAt: nextStop
            )
            BoardScroller(text: message)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .lastTextBaseline, spacing: RTSpacing.small) {
                    if !isCancelled {
                        bigLine(arrivalTime)
                    }
                    Spacer(minLength: RTSpacing.small)
                    bigLine(countdown)
                }
                VStack(alignment: .leading, spacing: 2) {
                    if !isCancelled {
                        bigLine(arrivalTime)
                    }
                    bigLine(countdown)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            [
                "Your stop \(JourneyFormatting.destinationStationText(journey))",
                arrivalExpected,
                isCancelled ? nil : "Arrives \(arrivalTime)",
                isCancelled ? nil : countdown,
                nextStop,
                message
            ]
            .compactMap { $0 }
            .joined(separator: ". ")
        )
    }

    /// The arrival time is in double height, so a late arrival says how
    /// late rather than repeating it.
    private var arrivalExpected: String {
        if JourneyFormatting.isCancelled(journey) {
            return "Cancelled"
        }
        if JourneyFormatting.isArrived(journey) {
            return "Arrived"
        }
        let arrival = JourneyFormatting.arrivalDisplay(journey)
        if let current = arrival.currentDate, let scheduled = arrival.scheduledDate {
            let minutesLate = Int((current.timeIntervalSince(scheduled) / 60).rounded())
            if minutesLate > 0 {
                return "\(minutesLate) min late"
            }
        }
        if let current = arrival.currentText, current != arrival.scheduledText {
            return "Exp \(current)"
        }
        return "On time"
    }

    /// "Next stop Finsbury Park 11:41", or "Now at Finsbury Park" while
    /// the train is standing there. Nil once it has reached the
    /// traveller's stop.
    private func nextStopText(_ detail: JourneyDetail, now: Date) -> String? {
        guard !JourneyFormatting.isArrived(journey) else {
            return nil
        }
        let entries = segmentStopEntries(for: detail)
        let position = adjustedPosition(JourneyFormatting.currentTrainPosition(detail, now: now), entries: entries)
        if let index = position.stationIndex, index > 0, index < entries.count - 1 {
            return "Now at \(BoardText.station(entries[index].stop))"
        }
        let nextIndex: Int
        if let index = position.stationIndex {
            nextIndex = index + 1
        } else if let after = position.betweenAfterIndex {
            nextIndex = after + 1
        } else {
            return nil
        }
        guard nextIndex < entries.count else {
            return nil
        }
        let stop = entries[nextIndex].stop
        let time = stop.timing?.current ?? stop.publicArrival ?? stop.publicDeparture
        return ["Next stop \(BoardText.station(stop))", time.map { String($0.prefix(5)) }]
            .compactMap { $0 }
            .joined(separator: " ")
    }

    /// Time left to the traveller's stop ("24 min", "1 hr 12 min"), then
    /// "Arriving" and "Arrived".
    private func arrivalCountdownText(now: Date) -> String {
        if JourneyFormatting.isCancelled(journey) {
            return "Cancelled"
        }
        if JourneyFormatting.isArrived(journey) {
            return "Arrived"
        }
        let arrival = JourneyFormatting.arrivalDisplay(journey)
        guard let date = arrival.currentDate ?? arrival.scheduledDate else {
            return ""
        }
        let seconds = date.timeIntervalSince(now)
        if seconds <= 60 {
            return "Arriving"
        }
        let minutes = Int((seconds / 60).rounded(.up))
        if minutes >= 60 {
            let rest = minutes % 60
            return rest == 0 ? "\(minutes / 60) hr" : "\(minutes / 60) hr \(rest) min"
        }
        return "\(minutes) min"
    }

    private func bigLine(_ text: String) -> some View {
        Text(text)
            .font(BoardFont.font(.title, weight: .bold))
            .lineLimit(1)
            .fixedSize()
    }

    /// Darwin's delay reason, then the arrival platform as a mention.
    private var onBoardMessage: String {
        var sentences: [String] = []
        if let reason = journey.lateReasonText?.trimmingCharacters(in: .whitespacesAndNewlines), !reason.isEmpty {
            sentences.append(reason.hasSuffix(".") ? reason : "\(reason).")
        }
        let verb = JourneyFormatting.isArrived(journey) ? "Arrived" : "Arriving"
        if let number = ActiveWindowPresentation.arrivalPlatformDisplay(for: journey).value.number {
            sentences.append("\(verb) at platform \(number).")
        } else {
            sentences.append("\(verb) at \(JourneyFormatting.destinationStationText(journey)).")
        }
        return BoardText.boardSafe(sentences.joined(separator: "  "))
    }

    private func stationsSection(detail: JourneyDetail, now: Date) -> some View {
        let entries = segmentStopEntries(for: detail)
        let trainPosition = adjustedPosition(
            JourneyFormatting.currentTrainPosition(detail, now: now),
            entries: entries
        )

        return VStack(alignment: .leading, spacing: RTSpacing.listItem) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Stations")
                    .font(.headline)

                if let distance = stationDistanceSummary(entries: entries, now: now) {
                    Text(distance.text)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(distance.text.replacingOccurrences(of: " mi", with: " miles"))
                }
            }

            // The calling points board for the traveller's stretch: passed
            // stops go unlit and a dot in the margin marks the train.
            DepartureBoard {
                ConcourseBoardHeader(placeTitle: "Calling at")
                ForEach(entries) { entry in
                    let isEnd = entry.localIndex == 0 || entry.localIndex == entries.count - 1
                    CallingPointBoardRow(
                        time: BoardText.time(entry.stop),
                        station: BoardText.station(entry.stop),
                        platform: isEnd ? stopPlatform(entry.stop) : nil,
                        expected: BoardText.expected(entry.stop),
                        note: stopReason(entry.stop),
                        isLit: !stopIsPassed(at: entry.localIndex, trainPosition: trainPosition),
                        marker: marker(at: entry.localIndex, trainPosition: trainPosition)
                    )
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(
                        [
                            JourneyFormatting.stationDisplayName(name: entry.stop.name, fallback: entry.stop.crs ?? entry.stop.tpl),
                            BoardText.time(entry.stop),
                            BoardText.expected(entry.stop),
                            stopReason(entry.stop)
                        ]
                        .compactMap { $0 }
                        .filter { !$0.isEmpty && $0 != "-" }
                        .joined(separator: ", ")
                    )
                }
            }
        }
    }

    private func stopPlatform(_ stop: JourneyStop) -> PlatformValue {
        PlatformValue(
            stop.realtime?.platform ?? stop.scheduledPlatform,
            confirmed: stop.realtime?.platform != nil && stop.realtime?.platformConfirmed == true
        )
    }

    private func stopReason(_ stop: JourneyStop) -> String? {
        guard let reason = stop.realtime?.reasonText, !reason.isEmpty else {
            return nil
        }
        if let location = stop.realtime?.reasonLocationName, !location.isEmpty {
            return BoardText.boardSafe("\(reason) near \(location)")
        }
        return BoardText.boardSafe(reason)
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

    /// How far the rider is from the stations either side, from a location
    /// fix no more than five minutes old. Hidden once the train has arrived.
    private func stationDistanceSummary(entries: [OnTrainStopEntry], now: Date) -> StationDistanceSummary? {
        guard !JourneyFormatting.isArrived(journey),
              let riderLocation,
              now.timeIntervalSince(riderLocation.timestamp) <= 5 * 60 else {
            return nil
        }
        let stops = entries.compactMap { entry -> StationDistanceCalculator.StopPoint? in
            guard let latitude = entry.stop.latitude,
                  let longitude = entry.stop.longitude else {
                return nil
            }
            return StationDistanceCalculator.StopPoint(name: entry.stop.name, latitude: latitude, longitude: longitude)
        }
        return StationDistanceCalculator.summary(
            latitude: riderLocation.coordinate.latitude,
            longitude: riderLocation.coordinate.longitude,
            stops: stops
        )
    }

    private var loadingStationsSection: some View {
        VStack(alignment: .leading, spacing: RTSpacing.listItem) {
            Text("Stations")
                .font(.headline)

            HStack(spacing: RTSpacing.listItem) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading stations")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(RTSpacing.cardPadding)
            .background(Color.rightTrainSurface, in: RoundedRectangle(cornerRadius: RTRadius.card, style: .continuous))
            .lightSurfaceForeground()
        }
    }

    private var matchingActiveWindowJourney: JourneyResult? {
        let recommendations = [window.selectedRecommendation] + window.recommendations
        return recommendations
            .map(\.journey)
            .first { journey in
                journey.serviceId == recommendation.journey.serviceId &&
                    journey.originTpl == recommendation.journey.originTpl &&
                    journey.destinationTpl == recommendation.journey.destinationTpl
            }
    }

    private var liveDetailRefreshKey: String {
        guard let matchingActiveWindowJourney else {
            return "none|\(identity.serviceID)|\(identity.originTPL ?? "")|\(identity.destinationTPL ?? "")"
        }
        return "live|window|\(activeWindowViewModel.liveRefreshGeneration)|\(JourneyLiveRefreshSignature.journey(matchingActiveWindowJourney))"
    }

    private func refreshDetailPeriodically() async {
        await refreshSelectedJourneyDetail()
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled else {
                return
            }
            await refreshSelectedJourneyDetail()
        }
    }

    private func refreshSelectedJourneyDetail() async {
        await journeyDetailViewModel.loadJourneyDetail(
            serviceID: recommendation.journey.serviceId,
            originTPL: recommendation.journey.originTpl,
            destinationTPL: recommendation.journey.destinationTpl,
            showLoading: false
        )
    }

    private func segmentStopEntries(for detail: JourneyDetail) -> [OnTrainStopEntry] {
        guard !detail.stops.isEmpty else {
            return []
        }
        let originTPL = identity.originTPL ?? detail.originTpl
        let destinationTPL = identity.destinationTPL ?? detail.destinationTpl
        let startIndex = detail.stops.firstIndex { $0.tpl == originTPL } ?? detail.stops.startIndex
        let endIndex = detail.stops.lastIndex { $0.tpl == destinationTPL } ?? detail.stops.index(before: detail.stops.endIndex)
        let indices = startIndex <= endIndex ? Array(startIndex...endIndex) : Array(detail.stops.indices)
        return indices.enumerated().map { localIndex, originalIndex in
            OnTrainStopEntry(
                localIndex: localIndex,
                originalIndex: originalIndex,
                stop: detail.stops[originalIndex]
            )
        }
    }

    private func adjustedPosition(
        _ position: JourneyTrainPosition,
        entries: [OnTrainStopEntry]
    ) -> JourneyTrainPosition {
        guard let first = entries.first,
              let last = entries.last else {
            return position
        }
        if let stationIndex = position.stationIndex {
            if stationIndex < first.originalIndex {
                return JourneyTrainPosition(stationIndex: 0, betweenAfterIndex: nil, progress: 0)
            }
            if stationIndex > last.originalIndex {
                return JourneyTrainPosition(stationIndex: last.localIndex, betweenAfterIndex: nil, progress: 1)
            }
            return JourneyTrainPosition(
                stationIndex: stationIndex - first.originalIndex,
                betweenAfterIndex: nil,
                progress: position.progress
            )
        }
        if let betweenAfterIndex = position.betweenAfterIndex {
            if betweenAfterIndex < first.originalIndex {
                return JourneyTrainPosition(stationIndex: 0, betweenAfterIndex: nil, progress: 0)
            }
            if betweenAfterIndex >= last.originalIndex {
                return JourneyTrainPosition(stationIndex: last.localIndex, betweenAfterIndex: nil, progress: 1)
            }
            return JourneyTrainPosition(
                stationIndex: nil,
                betweenAfterIndex: betweenAfterIndex - first.originalIndex,
                progress: position.progress
            )
        }
        return position
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

    private func clearPinnedTrain() {
        guard !isClearingPinned else { return }
        isClearingPinned = true
        Task {
            await activeWindowViewModel.clearPinnedTrainOrDeleteArrivedJourney(
                windowID: window.id,
                serviceID: journey.serviceId
            )
            await MainActor.run {
                isClearingPinned = false
            }
        }
    }

    private func requestUnpinConfirmation() {
        guard !isClearingPinned else { return }
        isConfirmingUnpin = true
    }
}

private struct OnTrainStopEntry: Identifiable {
    var localIndex: Int
    var originalIndex: Int
    var stop: JourneyStop

    var id: String { stop.id }
}

#Preview("Pinned - Search Pin") {
    PreviewAppContainer {
        ScrollView {
            ActiveWindowView(
                window: PreviewFixtures.activeWindow,
                loadDetail: { _ in }
            )
            .padding(RTSpacing.pageHorizontal)
        }
        .background(Color.rightTrainBackground)
    }
}

#Preview("Pinned - Journey Pin") {
    PreviewAppContainer {
        ScrollView {
            ActiveWindowView(
                window: PreviewFixtures.journeyPinnedWindow,
                loadDetail: { _ in }
            )
            .padding(RTSpacing.pageHorizontal)
        }
        .background(Color.rightTrainBackground)
    }
}

#Preview("Pinned - On Board") {
    PreviewAppContainer {
        ScrollView {
            ActiveOnTrainJourneyView(
                window: PreviewFixtures.journeyPinnedWindow,
                recommendation: PreviewFixtures.journeyPinnedWindow.selectedRecommendation
            )
            .padding(RTSpacing.pageHorizontal)
        }
        .background(Color.rightTrainBackground)
    }
}
