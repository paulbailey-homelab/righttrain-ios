import SwiftUI

struct JourneyDetailView: View {
    @Environment(JourneyDetailViewModel.self) private var viewModel
    @Environment(ActiveWindowViewModel.self) private var activeWindowViewModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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

    private func summarySection(_ detail: JourneyDetail, surface: RTSurface) -> some View {
        VStack(alignment: .leading, spacing: RTSpacing.sectionGap) {
            journeyOverviewCard(detail, surface: surface)

            if let message = disruptionMessage(for: detail) {
                disruptionBanner(message: message, cancelled: detail.cancelled, surface: surface)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func journeyOverviewCard(_ detail: JourneyDetail, surface: RTSurface) -> some View {
        VStack(alignment: .leading, spacing: RTSpacing.cardPadding) {
            HStack(alignment: .center, spacing: RTSpacing.small) {
                RTStatusPill(
                    statusText: JourneyFormatting.displayStatusText(detail),
                    surface: surface
                )

                Spacer(minLength: RTSpacing.small)

                JourneyDetailFreshnessBadge(text: detailFreshnessText(detail), surface: surface)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("\(segmentOriginName(detail)) to \(segmentDestinationName(detail))")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(surface.ink)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                Text(operatorSummaryText(detail))
                    .font(.subheadline)
                    .foregroundStyle(surface.dim)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            JourneyDetailTimeStrip(
                departure: detailDepartureText(detail),
                arrival: detailArrivalText(detail),
                platform: detailPlatform(detail),
                surface: surface,
                prefersStackedLayout: dynamicTypeSize.prefersExpandedLayout
            )
        }
        .rtCard(padding: RTSpacing.cardPadding, radius: RTRadius.heroCard)
        .accessibilityElement(children: .contain)
    }

    private func operatorSummaryText(_ detail: JourneyDetail) -> String {
        var parts = [JourneyFormatting.operatorDisplayText(detail)]
        if let coachCountText = JourneyFormatting.coachCountText(detail) {
            parts.append(coachCountText)
        }
        if let continuesToText = continuesToText(detail) {
            parts.append(continuesToText)
        }
        return parts.joined(separator: " · ")
    }

    private func disruptionBanner(message: String, cancelled: Bool, surface: RTSurface) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: cancelled ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(surface.accent)
            Text(message)
                .font(.footnote.weight(.medium))
                .foregroundStyle(surface.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(RTSpacing.compact)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(surface.softFill, in: RoundedRectangle(cornerRadius: RTRadius.card, style: .continuous))
    }

    private func callingPointsSection(_ detail: JourneyDetail, surface: RTSurface, now: Date) -> some View {
        VStack(alignment: .leading, spacing: RTSpacing.small) {
            Text("Calling points")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, RTSpacing.cardPadding)

            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(detail.stops.enumerated()), id: \.element.id) { index, stop in
                    let trainPosition = currentTrainPosition(detail, now: now)
                    JourneyStopRow(
                        stop: stop,
                        isCurrent: trainPosition.stationIndex == index,
                        isBetweenAfter: trainPosition.betweenAfterIndex == index,
                        betweenProgress: trainPosition.progress,
                        isPassed: stopIsPassed(at: index, trainPosition: trainPosition),
                        isFirst: index == detail.stops.startIndex,
                        isLast: index == detail.stops.index(before: detail.stops.endIndex),
                        // Platforms matter where you board and get off; the
                        // stops in between only need a time.
                        showsPlatform: index == segmentRange(detail).origin || index == segmentRange(detail).destination
                    )
                        .padding(.vertical, 10)
                }
            }
            .padding(.horizontal, RTSpacing.cardPadding)
            .padding(.vertical, RTSpacing.small)
            .background(Color.rightTrainPaperCream, in: RoundedRectangle(cornerRadius: RTRadius.card, style: .continuous))
            .lightSurfaceForeground()
        }
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

    private func segmentOriginName(_ detail: JourneyDetail) -> String {
        guard !detail.stops.isEmpty else { return detail.originName }
        let stop = detail.stops[segmentRange(detail).origin]
        return JourneyFormatting.stationDisplayName(name: stop.name, fallback: stop.crs ?? stop.tpl)
    }

    private func segmentDestinationName(_ detail: JourneyDetail) -> String {
        guard !detail.stops.isEmpty else { return detail.destinationName }
        let stop = detail.stops[segmentRange(detail).destination]
        return JourneyFormatting.stationDisplayName(name: stop.name, fallback: stop.crs ?? stop.tpl)
    }

    /// "Continues to Edinburgh" when the train runs beyond the traveller's stop.
    private func continuesToText(_ detail: JourneyDetail) -> String? {
        guard let last = detail.stops.last,
              segmentRange(detail).destination < detail.stops.index(before: detail.stops.endIndex) else {
            return nil
        }
        return "Continues to \(JourneyFormatting.stationDisplayName(name: last.name, fallback: last.crs ?? last.tpl))"
    }

    private func detailDepartureText(_ detail: JourneyDetail) -> String {
        guard !detail.stops.isEmpty else { return "TBC" }
        let stop = detail.stops[segmentRange(detail).origin]
        return stop.timing?.current ?? stop.publicDeparture ?? "TBC"
    }

    private func detailArrivalText(_ detail: JourneyDetail) -> String {
        guard !detail.stops.isEmpty else { return "TBC" }
        let stop = detail.stops[segmentRange(detail).destination]
        return stop.timing?.current ?? stop.publicArrival ?? "TBC"
    }

    private func detailPlatform(_ detail: JourneyDetail) -> PlatformValue {
        guard !detail.stops.isEmpty else { return .unknown }
        let stop = detail.stops[segmentRange(detail).origin]
        let confirmed = stop.realtime?.platform != nil && stop.realtime?.platformConfirmed == true
        return PlatformValue(stop.realtime?.platform ?? stop.scheduledPlatform, confirmed: confirmed)
    }

    private func detailFreshnessText(_ detail: JourneyDetail) -> String {
        if detail.reportState == "complete" {
            return "Live data"
        }
        if detail.realtimeSource?.isEmpty == false {
            return "Live data"
        }
        return "Limited live data"
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

private struct JourneyDetailFreshnessBadge: View {
    var text: String
    var surface: RTSurface

    var body: some View {
        Label(text, systemImage: "dot.radiowaves.left.and.right")
            .font(.caption.weight(.semibold))
            .foregroundStyle(surface.dim)
            .lineLimit(1)
            .minimumScaleFactor(0.76)
            .labelStyle(.titleAndIcon)
            .accessibilityLabel(text)
    }
}

private struct JourneyDetailTimeStrip: View {
    var departure: String
    var arrival: String
    var platform: PlatformValue
    var surface: RTSurface
    var prefersStackedLayout: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: RTSpacing.compact) {
            if prefersStackedLayout {
                VStack(alignment: .leading, spacing: RTSpacing.compact) {
                    timePoint(label: "Departs", value: departure, textAlignment: .leading, frameAlignment: .leading)
                    Divider()
                        .background(surface.faint)
                    timePoint(label: "Arrives", value: arrival, textAlignment: .leading, frameAlignment: .leading)
                }
            } else {
                HStack(alignment: .center, spacing: RTSpacing.compact) {
                    timePoint(label: "Departs", value: departure, textAlignment: .leading, frameAlignment: .leading)

                    HStack(spacing: RTSpacing.small) {
                        Rectangle()
                            .fill(surface.faint)
                            .frame(height: 1)
                        Image(systemName: "arrow.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(surface.accent)
                        Rectangle()
                            .fill(surface.faint)
                            .frame(height: 1)
                    }
                    .frame(minWidth: 56, maxWidth: 92)
                    .accessibilityHidden(true)

                    timePoint(label: "Arrives", value: arrival, textAlignment: .trailing, frameAlignment: .trailing)
                }
            }

            JourneyDetailPlatformLine(platform: platform, surface: surface)
        }
        // Sits directly in the overview card, divided by a hairline, rather
        // than in a filled box inside the card.
        .padding(.top, RTSpacing.compact)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private func timePoint(
        label: String,
        value: String,
        textAlignment: HorizontalAlignment,
        frameAlignment: Alignment
    ) -> some View {
        VStack(alignment: textAlignment, spacing: 3) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(surface.dim)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
            Text(value)
                .font(.title2.weight(.bold))
                .foregroundStyle(surface.ink)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: frameAlignment)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }
}

private struct JourneyDetailPlatformLine: View {
    var platform: PlatformValue
    var surface: RTSurface

    var body: some View {
        Label {
            HStack(spacing: RTSpacing.small) {
                Text(platform.caption())
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(surface.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                PlatformTile(platform: platform)
            }
        } icon: {
            Image(systemName: "tram.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(surface.accent)
        }
        .labelStyle(.titleAndIcon)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, RTSpacing.small)
        .overlay(alignment: .top) {
            Divider()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(platform.accessibilityLabel())
    }
}

struct JourneyStopRow: View {
    var stop: JourneyStop
    var isCurrent: Bool
    var isBetweenAfter: Bool
    var betweenProgress: Double
    var isPassed: Bool
    var isFirst: Bool
    var isLast: Bool
    var showsPlatform = true

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            JourneyTimelineMarker(
                isCurrent: isCurrent,
                isPassed: isPassed,
                isFirst: isFirst,
                isLast: isLast
            )

            VStack(alignment: .leading, spacing: 4) {
                // The platform tile rides on the station line, so most stops
                // take one line; only a delay reason adds a second.
                stationLine
                if let reasonText {
                    Text(reasonText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 12)

            JourneyStopTimeView(timing: timing)
                .layoutPriority(2)
        }
        // Each row draws the rail down to the next stop's marker, so the line
        // follows the real row heights; a single rail with fixed insets fell
        // short of the last stop once rows got shorter.
        .background(alignment: .topLeading) {
            if !isLast {
                GeometryReader { proxy in
                    Rectangle()
                        .fill(Color.rightTrainInkFaint)
                        .frame(width: 2, height: proxy.size.height + Self.rowGap)
                        .offset(x: Self.markerCenterX - 1, y: Self.markerCenterY)
                }
                .accessibilityHidden(true)
            }
        }
        // The between-stops dot travels from this stop's marker towards the
        // next row's, drawing into the row gap rather than stretching this
        // row (a fixed minimum height left a hole under one-line stops).
        .overlay(alignment: .topLeading) {
            if isBetweenAfter {
                GeometryReader { proxy in
                    Circle()
                        .fill(Color.rightTrainBlue)
                        .frame(width: 18, height: 18)
                        .overlay {
                            Circle()
                                .stroke(Color.rightTrainPaperCream, lineWidth: 3)
                        }
                        .shadow(color: Color.rightTrainBlue.opacity(0.28), radius: 8, y: 4)
                        .position(
                            x: Self.markerCenterX,
                            y: Self.markerCenterY + (proxy.size.height + Self.rowGap) * bufferedProgress
                        )
                }
                .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Centre of the 24pt-wide marker column and of a 10pt stop circle with
    /// its 4pt top padding.
    private static let markerCenterX: CGFloat = 12
    private static let markerCenterY: CGFloat = 9
    /// Space between rows: callers pad each row by 10pt top and bottom.
    private static let rowGap: CGFloat = 20
    private static let segmentBuffer = 0.16

    private var bufferedProgress: Double {
        let clamped = min(max(betweenProgress, 0), 1)
        return Self.segmentBuffer + (clamped * (1 - (Self.segmentBuffer * 2)))
    }

    private var stopDisplayName: String {
        JourneyFormatting.stationDisplayName(
            name: stop.name,
            fallback: stop.crs ?? stop.tpl
        )
    }

    private var timing: StopTiming {
        if let timing = stop.timing {
            return StopTiming(
                label: timing.label,
                scheduled: timing.scheduled,
                current: timing.current,
                delayed: timing.delayed
            )
        }
        let scheduled = isLast ? stop.publicArrival : stop.publicDeparture
        return StopTiming(
            label: isLast ? "Arrives" : "Departs",
            scheduled: scheduled,
            current: scheduled ?? "TBC",
            delayed: false
        )
    }

    private var stationLine: some View {
        let platform = PlatformValue(
            stop.realtime?.platform ?? stop.scheduledPlatform,
            confirmed: stop.realtime?.platformConfirmed == true
        )
        return HStack(alignment: .firstTextBaseline, spacing: RTSpacing.small) {
            Text(stopDisplayName)
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            // Unknown platforms are left off: a TBC on every calling point
            // would drown out the ones that matter.
            if showsPlatform, platform.number != nil {
                PlatformTile(platform: platform)
            }
        }
    }

    private var reasonText: String? {
        guard let reason = stop.realtime?.reasonText, !reason.isEmpty else {
            return nil
        }
        if let location = stop.realtime?.reasonLocationName, !location.isEmpty {
            return "\(reason) near \(location)"
        }
        return reason
    }

}

struct JourneyTimelineMarker: View {
    var isCurrent: Bool
    var isPassed: Bool
    var isFirst: Bool
    var isLast: Bool

    var body: some View {
        ZStack(alignment: .top) {
            Circle()
                .fill(markerFill)
                .frame(width: isCurrent ? 18 : 10, height: isCurrent ? 18 : 10)
                .overlay {
                    Circle()
                        .stroke(isCurrent ? Color.rightTrainPaperCream : markerStroke, lineWidth: isCurrent ? 3 : 2)
                }
                .shadow(color: isCurrent ? Color.rightTrainBlue.opacity(0.28) : .clear, radius: 8, y: 4)
                .padding(.top, isCurrent ? 0 : 4)

        }
        .frame(minWidth: 24, idealWidth: 24, maxWidth: 24, alignment: .top)
        .accessibilityHidden(true)
    }

    private var markerFill: Color {
        if isCurrent {
            return .rightTrainBlue
        }
        if isPassed {
            return .secondary.opacity(RTOpacity.secondary)
        }
        return .rightTrainPaperCream
    }

    private var markerStroke: Color {
        isPassed ? .secondary.opacity(RTOpacity.secondary) : .rightTrainInkFaint
    }
}

struct StopTiming {
    var label: String
    var scheduled: String?
    var current: String
    var delayed: Bool
}

struct JourneyStopTimeView: View {
    var timing: StopTiming

    var body: some View {
        HStack(spacing: 8) {
            Text(timing.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.rightTrainInk.opacity(RTOpacity.dim))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            if timing.delayed, let scheduled = timing.scheduled {
                Text(scheduled)
                    .font(.caption)
                    .foregroundStyle(Color.rightTrainInk.opacity(RTOpacity.dim))
                    .monospacedDigit()
                    .strikethrough(true, color: Color.rightTrainInk.opacity(RTOpacity.dim))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }

            Text(timing.current)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(timing.delayed ? Color.rightTrainWarnBg : Color.rightTrainInk)
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .combine)
    }
}
