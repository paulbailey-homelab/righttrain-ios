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
                TimelineView(.periodic(from: .now, by: 15)) { context in
                    let surface = detailSurface(detail)
                    ScrollView(.vertical) {
                        VStack(alignment: .leading, spacing: RTSpacing.sectionGap) {
                            AppHeader(surface: surface)
                                .padding(.bottom, RTSpacing.small)
                            summarySection(detail, surface: surface)
                            callingPointsSection(detail, surface: surface, now: context.date)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, RTSpacing.pageHorizontal)
                        .padding(.vertical, RTSpacing.cardPadding + 2)
                    }
                    .scrollBounceBehavior(.always, axes: .vertical)
                    .scrollIndicators(.visible)
                    .statusSurface(surface)
                    .toolbarBackground(surface.bg, for: .navigationBar)
                    .toolbarBackground(.visible, for: .navigationBar)
                    .toolbarColorScheme(.light, for: .navigationBar)
                }
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
        .toolbarColorScheme(.light, for: .navigationBar)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: identity) {
            await refreshDetailPeriodically()
        }
        .task(id: liveDetailRefreshKey) {
            guard liveDetailRefreshKey.hasPrefix("live|") else { return }
            await refreshSelectedJourneyDetail()
        }
        .environment(\.colorScheme, .light)
        .preferredColorScheme(.light)
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
            VStack(alignment: .leading, spacing: RTSpacing.compact) {
                RTStatusPill(
                    statusText: JourneyFormatting.displayStatusText(detail),
                    surface: surface
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text("TRAIN DETAILS")
                        .font(RTFont.eyebrow)
                        .tracking(2)
                        .foregroundStyle(surface.dim)

                    Text("\(detail.originName) to \(detail.destinationName)")
                        .font(.title.weight(.bold))
                        .foregroundStyle(surface.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(detail.originName) (\(detail.originCrs)) to \(detail.destinationName) (\(detail.destinationCrs))")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(surface.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            detailGlanceSummary(detail, surface: surface)

            HStack(spacing: 0) {
                detailMetricCell(label: "Operator", value: JourneyFormatting.operatorDisplayText(detail), surface: surface)
                if let coachCountText = JourneyFormatting.coachCountText(detail) {
                    detailMetricCell(label: "Coaches", value: coachCountText, surface: surface)
                }
                detailMetricCell(label: "Stops", value: "\(detail.stops.count)", surface: surface, showsDivider: false)
            }
            .background(surface.softFill, in: RoundedRectangle(cornerRadius: RTRadius.card))
            .overlay {
                RoundedRectangle(cornerRadius: RTRadius.card)
                    .stroke(surface.softBorder, lineWidth: 1)
            }

            if let message = disruptionMessage(for: detail) {
                disruptionBanner(message: message, cancelled: detail.cancelled, surface: surface)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func detailGlanceSummary(_ detail: JourneyDetail, surface: RTSurface) -> some View {
        VStack(alignment: .leading, spacing: RTSpacing.compact) {
            HStack(alignment: .top, spacing: RTSpacing.compact) {
                MetricView(label: "Dep", value: detailDepartureText(detail))
                MetricView(label: "Arr", value: detailArrivalText(detail))
            }
            HStack(alignment: .top, spacing: RTSpacing.compact) {
                MetricView(label: "Platform", value: detailPlatformText(detail))
                MetricView(label: "Freshness", value: detailFreshnessText(detail))
            }
        }
        .padding(RTSpacing.cardPadding)
        .background(surface.softFill, in: RoundedRectangle(cornerRadius: RTRadius.card))
        .overlay {
            RoundedRectangle(cornerRadius: RTRadius.card)
                .stroke(surface.softBorder, lineWidth: 1)
        }
    }

    private func detailMetricCell(
        label: String,
        value: String,
        surface: RTSurface,
        showsDivider: Bool = true
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(surface.dim)
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(surface.ink)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, RTSpacing.compact)
        .padding(.vertical, RTSpacing.compact)
        .overlay(alignment: .trailing) {
            if showsDivider {
                Rectangle()
                    .fill(surface.faint)
                    .frame(width: 1)
                    .padding(.vertical, RTSpacing.compact)
            }
        }
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
        .background(surface.softFill, in: RoundedRectangle(cornerRadius: RTRadius.card))
        .overlay {
            RoundedRectangle(cornerRadius: RTRadius.card)
                .stroke(surface.softBorder, lineWidth: 1)
        }
    }

    private func callingPointsSection(_ detail: JourneyDetail, surface: RTSurface, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Stations")
                .font(.headline)
                .foregroundStyle(surface.ink)

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
                        isLast: index == detail.stops.index(before: detail.stops.endIndex)
                    )
                        .padding(.vertical, 10)
                }
            }
            .padding(.horizontal, RTSpacing.cardPadding)
            .padding(.vertical, 6)
            .background(Color.rightTrainPaperCream, in: RoundedRectangle(cornerRadius: RTRadius.card))
            .lightSurfaceForeground()
            .overlay {
                RoundedRectangle(cornerRadius: RTRadius.card)
                    .stroke(Color.rightTrainInkFaint, lineWidth: 1)
            }
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

    private func detailDepartureText(_ detail: JourneyDetail) -> String {
        guard let stop = detail.stops.first else { return "TBC" }
        return stop.timing?.current ?? stop.publicDeparture ?? "TBC"
    }

    private func detailArrivalText(_ detail: JourneyDetail) -> String {
        guard let stop = detail.stops.last else { return "TBC" }
        return stop.timing?.current ?? stop.publicArrival ?? "TBC"
    }

    private func detailPlatformText(_ detail: JourneyDetail) -> String {
        guard let stop = detail.stops.first else { return "Platform TBC" }
        let platform = stop.realtime?.platform ?? stop.scheduledPlatform
        guard let platform, !platform.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Platform TBC"
        }
        return platform
    }

    private func detailFreshnessText(_ detail: JourneyDetail) -> String {
        if detail.reportState == "complete" {
            return "Live report complete"
        }
        if detail.realtimeSource?.isEmpty == false {
            return "Live data available"
        }
        return "Live data limited"
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

struct JourneyStopRow: View {
    var stop: JourneyStop
    var isCurrent: Bool
    var isBetweenAfter: Bool
    var betweenProgress: Double
    var isPassed: Bool
    var isFirst: Bool
    var isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            JourneyTimelineMarker(
                isCurrent: isCurrent,
                isBetweenAfter: isBetweenAfter,
                betweenProgress: betweenProgress,
                isPassed: isPassed,
                isFirst: isFirst,
                isLast: isLast
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(stopDisplayName)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                if !stopSubtitle.isEmpty {
                    Text(stopSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 12)

            JourneyStopTimeView(timing: timing)
                .layoutPriority(2)
        }
        .accessibilityElement(children: .combine)
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

    private var stopSubtitle: String {
        var parts: [String] = []
        if let platform = stop.realtime?.platform ?? stop.scheduledPlatform, !platform.isEmpty {
            parts.append("Platform \(platform)")
        }
        if let reason = stop.realtime?.reasonText, !reason.isEmpty {
            if let location = stop.realtime?.reasonLocationName, !location.isEmpty {
                parts.append("\(reason) near \(location)")
            } else {
                parts.append(reason)
            }
        }
        return parts.joined(separator: " · ")
    }

}

struct JourneyTimelineMarker: View {
    private let segmentBuffer = 0.16

    var isCurrent: Bool
    var isBetweenAfter: Bool
    var betweenProgress: Double
    var isPassed: Bool
    var isFirst: Bool
    var isLast: Bool

    var body: some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(Color.rightTrainInkFaint)
                .frame(width: 2)
                .padding(.top, isFirst ? 10 : -12)
                .padding(.bottom, isLast ? 58 : -12)

            Circle()
                .fill(markerFill)
                .frame(width: isCurrent ? 18 : 10, height: isCurrent ? 18 : 10)
                .overlay {
                    Circle()
                        .stroke(isCurrent ? Color.rightTrainPaperCream : markerStroke, lineWidth: isCurrent ? 3 : 2)
                }
                .shadow(color: isCurrent ? Color.rightTrainBlue.opacity(0.28) : .clear, radius: 8, y: 4)
                .padding(.top, isCurrent ? 0 : 4)

            if isBetweenAfter {
                Circle()
                    .fill(Color.rightTrainBlue)
                    .frame(width: 18, height: 18)
                    .overlay {
                        Circle()
                            .stroke(Color.rightTrainPaperCream, lineWidth: 3)
                    }
                    .shadow(color: Color.rightTrainBlue.opacity(0.28), radius: 8, y: 4)
                    .padding(.top, CGFloat(5 + (bufferedProgress * 40)))
            }
        }
        .frame(minWidth: 24, idealWidth: 24, maxWidth: 24, minHeight: isBetweenAfter ? 64 : nil, alignment: .top)
        .accessibilityHidden(true)
    }

    private var bufferedProgress: Double {
        let clamped = min(max(betweenProgress, 0), 1)
        return segmentBuffer + (clamped * (1 - (segmentBuffer * 2)))
    }

    private var markerFill: Color {
        if isCurrent {
            return .rightTrainBlue
        }
        if isPassed {
            return .secondary.opacity(0.55)
        }
        return .rightTrainPaperCream
    }

    private var markerStroke: Color {
        isPassed ? .secondary.opacity(0.55) : .rightTrainInkFaint
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
                .foregroundStyle(Color.rightTrainInk.opacity(0.66))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            if timing.delayed, let scheduled = timing.scheduled {
                Text(scheduled)
                    .font(.caption)
                    .foregroundStyle(Color.rightTrainInk.opacity(0.66))
                    .monospacedDigit()
                    .strikethrough(true, color: Color.rightTrainInk.opacity(0.66))
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
