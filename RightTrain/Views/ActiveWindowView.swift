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
    var loadDetail: (DirectWindowRecommendation) async -> Void

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
            Text("This removes the current \(unpinTargetName.capitalized) Pin from RightTrain.")
        }
    }

    @ViewBuilder
    private func content(presentation: ActiveWindowPresentation, now: Date) -> some View {
        let surface = presentation.heroSurface
        let heroCountdown = ActiveWindowPresentation.countdown(for: presentation.heroRecommendation, now: now)

        VStack(alignment: .leading, spacing: 0) {
            statusPillRow(
                presentation: presentation,
                surface: surface
            )
            .padding(.bottom, RTSpacing.compact)

            // The hero block below is the single source for route, timing,
            // platform, and next action. While it is visible the old summary
            // card would repeat all of it, so it collapses to a slim context
            // strip (CRS route + freshness); the full panel only renders when
            // there is no hero.
            let glance = ActiveWindowPresentation.liveGlanceContent(
                for: presentation.heroRecommendation,
                routeTitle: presentation.routeTitle,
                needProfile: .oneOffDirectTrip,
                now: now,
                isOffline: shouldPresentOfflineGlance(for: presentation.heroRecommendation)
            )
            if presentation.shouldShowHero(now: now) {
                heroContextStrip(glance: glance, surface: surface)
                    .padding(.bottom, RTSpacing.sectionGap)
            } else {
                LiveGlancePanel(content: glance)
                    .padding(.bottom, RTSpacing.sectionGap)
            }

            // ── Hero block ────────────────────────────────────────────────
            if presentation.shouldShowHero(now: now) {
                StatusFirstHeroBlock(
                    presentation: presentation,
                    countdown: heroCountdown,
                    surface: surface,
                    now: now,
                    loadDetail: { await loadDetail(presentation.heroRecommendation) },
                    requestUnpin: requestDeleteConfirmation
                )
                .padding(.bottom, RTSpacing.sectionGap)
            }

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

    /// Slim replacement for the summary card while the hero owns the detail:
    /// keeps CRS context and data freshness in the first screenful without
    /// repeating route, timing, platform, and next action.
    private func heroContextStrip(
        glance: ActiveWindowPresentation.LiveGlanceContent,
        surface: RTSurface
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: RTSpacing.small) {
            if let routeContextText = glance.routeContextText {
                Text(routeContextText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(surface.dim)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            Spacer(minLength: RTSpacing.small)
            LiveFreshnessText(text: glance.freshnessText)
        }
        .accessibilityElement(children: .combine)
    }

    private func statusPillRow(
        presentation: ActiveWindowPresentation,
        surface: RTSurface
    ) -> some View {
        HStack(alignment: .center, spacing: 0) {
            RTStatusPill(
                statusText: pillStatusText(presentation: presentation),
                surface: surface
            )

            Spacer(minLength: RTSpacing.small)

            if !presentation.heroIsPinnedTrain {
                Text("\(presentation.recommendations.count) train\(presentation.recommendations.count == 1 ? "" : "s")")
                    .font(RTFont.eyebrow)
                    .tracking(2)
                    .foregroundStyle(surface.dim)
            }

            statusUnpinButton(presentation: presentation, surface: surface)
        }
    }

    private func statusUnpinButton(
        presentation: ActiveWindowPresentation,
        surface: RTSurface
    ) -> some View {
        Button(role: .destructive) {
            requestDeleteConfirmation()
        } label: {
            Label("Unpin", systemImage: "pin.slash")
                .font(RTFont.eyebrow)
                .tracking(1.2)
                .lineLimit(1)
        }
        .buttonStyle(.plain)
        .foregroundStyle(surface.ink)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(surface.softFill, in: Capsule())
        .overlay {
            Capsule()
                .stroke(surface.softBorder, lineWidth: 1)
        }
        .disabled(isDeleting)
        .accessibilityLabel(presentation.heroIsPinnedTrain ? "Unpin journey" : "Unpin search")
        .accessibilityHint("Removes this \(presentation.heroIsPinnedTrain ? "Journey" : "Search") Pin.")
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
        VStack(alignment: .leading, spacing: RTSpacing.compact) {
            Text("Other trains in this search")
                .font(.caption.weight(.semibold))
                .foregroundStyle(surface.dim)

            VStack(alignment: .leading, spacing: 0) {
                let all = future + cancelled
                ForEach(Array(all.enumerated()), id: \.element.id) { index, recommendation in
                    StatusFirstTrainRow(
                        recommendation: recommendation,
                        surface: surface,
                        isPinned: activeWindowViewModel.pinnedLiveActivityServiceID == recommendation.journey.serviceId,
                        now: now,
                        loadDetail: { await loadDetail(recommendation) },
                        togglePinned: { await activeWindowViewModel.togglePinnedLiveActivity(for: recommendation) }
                    )
                    if index < all.count - 1 {
                        Divider()
                            .background(surface.faint)
                    }
                }
            }
            .padding(RTSpacing.cardPadding)
            .background(surface.softFill, in: RoundedRectangle(cornerRadius: RTRadius.card))
            .overlay {
                RoundedRectangle(cornerRadius: RTRadius.card)
                    .stroke(surface.softBorder, lineWidth: 1)
            }
        }
    }

    private func pinnedNextStepCard(
        presentation: ActiveWindowPresentation,
        countdown: ActiveWindowPresentation.CountdownDisplay,
        surface: RTSurface
    ) -> some View {
        let journey = presentation.heroRecommendation.journey

        return VStack(alignment: .leading, spacing: RTSpacing.compact) {
            HStack(alignment: .top, spacing: RTSpacing.listItem) {
                Image(systemName: countdown.isDeparted ? "tram.fill" : "figure.walk")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(surface.accent)
                    .frame(width: RTSize.iconSmall)

                VStack(alignment: .leading, spacing: 4) {
                    Text(pinnedNextStepTitle(journey: journey, countdown: countdown))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.rightTrainInk)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(pinnedNextStepMessage(countdown: countdown))
                        .font(.caption)
                        .foregroundStyle(Color.rightTrainInk.opacity(RTOpacity.dim))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button {
                Task { await loadDetail(presentation.heroRecommendation) }
            } label: {
                Label("View stops", systemImage: "list.bullet")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.rightTrainPaperCream)
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(Color.rightTrainActionInk, in: Capsule())
        }
        .padding(RTSpacing.cardPadding)
        .background(surface.softFill, in: RoundedRectangle(cornerRadius: RTRadius.card))
        .overlay {
            RoundedRectangle(cornerRadius: RTRadius.card)
                .stroke(surface.softBorder, lineWidth: 1)
        }
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
                summarySection

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
            Text("This removes the current Journey Pin from RightTrain.")
        }
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: RTSpacing.cardPadding) {
            PinnedObjectHeader(
                kind: .journey,
                showsActionMenu: false,
                title: "\(JourneyFormatting.isArrived(journey) ? "Arrived at" : "On board to") \(JourneyFormatting.destinationStationText(journey))",
                summary: journeyPinSummary,
                statusText: anomalousStatus?.text,
                statusTone: anomalousStatus?.tone ?? .accent,
                updatedAt: journey.realtimeUpdatedAt.flatMap(DateFormatting.date(from:)),
                now: Date(),
                primaryAction: PinnedHeaderPrimaryAction(
                    title: "Unpin",
                    systemImage: "pin.slash",
                    role: .destructive,
                    accessibilityHint: "Removes this Journey Pin.",
                    isDisabled: isClearingPinned,
                    action: requestUnpinConfirmation
                )
            ) {
                EmptyView()
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .bottom, spacing: 14) {
                    arrivalHero
                        .layoutPriority(1)
                    Spacer(minLength: 8)
                    arrivalPlatformSummary
                }

                VStack(alignment: .leading, spacing: 12) {
                    arrivalHero
                    arrivalPlatformSummary
                }
            }
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

    private var arrivalHero: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(JourneyFormatting.isArrived(journey) ? "Arrived" : "Arrives")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            CompactTrainTime(
                display: JourneyFormatting.arrivalDisplay(journey),
                primaryFont: .largeTitle.weight(.bold),
                secondaryFont: .subheadline.weight(.semibold)
            )
        }
    }

    private var arrivalPlatformSummary: some View {
        let platform = ActiveWindowPresentation.arrivalPlatformDisplay(for: journey)
        return VStack(alignment: .trailing, spacing: 5) {
            Text("Arrival platform")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .multilineTextAlignment(.trailing)

            PlatformSquareChip(platform: platform, label: nil)

            if let secondary = platform.secondary {
                Text(secondary)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .multilineTextAlignment(.trailing)
            }
        }
        .frame(alignment: .trailing)
    }

    private func stationsSection(detail: JourneyDetail, now: Date) -> some View {
        let entries = segmentStopEntries(for: detail)
        let trainPosition = adjustedPosition(
            JourneyFormatting.currentTrainPosition(detail, now: now),
            entries: entries
        )

        return VStack(alignment: .leading, spacing: RTSpacing.listItem) {
            Text("Stations")
                .font(.headline)

            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(entries) { entry in
                    JourneyStopRow(
                        stop: entry.stop,
                        isCurrent: trainPosition.stationIndex == entry.localIndex,
                        isBetweenAfter: trainPosition.betweenAfterIndex == entry.localIndex,
                        betweenProgress: trainPosition.progress,
                        isPassed: stopIsPassed(at: entry.localIndex, trainPosition: trainPosition),
                        isFirst: entry.localIndex == 0,
                        isLast: entry.localIndex == entries.count - 1
                    )
                    .padding(.vertical, 10)
                }
            }
            .padding(.horizontal, RTSpacing.cardPadding)
            .padding(.vertical, 6)
            .background(Color.rightTrainSurface, in: RoundedRectangle(cornerRadius: RTRadius.card))
            .lightSurfaceForeground()
            .overlay {
                RoundedRectangle(cornerRadius: RTRadius.card)
                    .stroke(Color.rightTrainBorder, lineWidth: 1)
            }
        }
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
            .background(Color.rightTrainSurface, in: RoundedRectangle(cornerRadius: RTRadius.card))
            .lightSurfaceForeground()
            .overlay {
                RoundedRectangle(cornerRadius: RTRadius.card)
                    .stroke(Color.rightTrainBorder, lineWidth: 1)
            }
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
