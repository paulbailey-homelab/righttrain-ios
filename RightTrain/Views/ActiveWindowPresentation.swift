import Foundation

struct ActiveWindowPresentation {
    private static let justDepartedVisibilityInterval: TimeInterval = 5 * 60
    private static let staleDataInterval: TimeInterval = 5 * 60

    enum JourneyMomentKind: String, Equatable {
        case noActiveJourney
        case planning
        case monitoringBeforeDeparture
        case approachingDeparture
        case onBoard
        case interchange
        case completed
        case disrupted
        case staleData
        case offline
        case signedOut
        case sharedView
    }

    enum NeedProfileKind: String, Equatable {
        case routineCommute
        case oneOffDirectTrip
        case connectionSensitiveTrip
        case liveAlertReturn
        case sharedJourneyCheck
    }

    struct StatusDisplay {
        var text: String
        var tone: StatusPill.Tone
    }

    struct PlatformDisplay {
        var primary: String
        var secondary: String?
        var confirmed: Bool = false
    }

    struct CollapsedSetupState {
        var title: String
        var statusText: String
        var message: String
    }

    struct CountdownDisplay {
        var text: String
        var tone: StatusPill.Tone
        var isDeparted: Bool
        var targetDate: Date?
    }

    struct LiveGlanceContent {
        var moment: JourneyMomentKind
        var needProfile: NeedProfileKind
        var routeTitle: String
        var routeContextText: String? = nil
        var statusText: String
        var statusTone: StatusPill.Tone
        var timingText: String
        var platformText: String
        var nextActionText: String
        var freshnessText: String
    }

    struct SetupPromptContent {
        var moment: JourneyMomentKind
        var needProfile: NeedProfileKind
        var title: String
        var statusText: String
        var primaryActionText: String
        var detailText: String
    }

    enum DepartureListItem: Identifiable {
        case nowMarker(String)
        case train(DirectWindowRecommendation)

        var id: String {
            switch self {
            case .nowMarker:
                return "now-marker"
            case .train(let recommendation):
                return recommendation.id
            }
        }

    }

    var routeTitle: String
    var summaryText: String
    var compactSummaryText: String
    var statusText: String
    var recommendations: [DirectWindowRecommendation]
    var bestRecommendation: DirectWindowRecommendation
    var heroRecommendation: DirectWindowRecommendation
    var heroTitle: String
    var heroIsPinnedTrain: Bool
    var departureItems: [DepartureListItem]
    var lastUpdatedDate: Date?

    init(window: WindowSubscription, now: Date = Date()) {
        recommendations = Self.deduplicatedRecommendations(for: window)
        let routeJourney = recommendations.first?.journey ?? window.selectedRecommendation.journey
        routeTitle = Self.routeTitle(for: routeJourney)
        summaryText = Self.summaryText(for: window, recommendationCount: recommendations.count)
        compactSummaryText = Self.compactSummaryText(for: window, recommendationCount: recommendations.count)
        statusText = window.status.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Active" : window.status.capitalized
        let best = Self.bestRecommendation(
            for: window,
            recommendations: recommendations
        )
        bestRecommendation = best
        if let pinnedRecommendation = Self.pinnedRecommendation(for: window, recommendations: recommendations),
           !Self.isCancelled(pinnedRecommendation, now: now) {
            heroRecommendation = pinnedRecommendation
            heroTitle = JourneyFormatting.isDeparted(pinnedRecommendation.journey) ? "On board" : "Pinned train"
            heroIsPinnedTrain = true
        } else {
            heroRecommendation = Self.heroRecommendation(
                best: best,
                recommendations: recommendations,
                now: now
            )
            heroTitle = "Recommended train"
            heroIsPinnedTrain = false
        }
        departureItems = Self.departureItems(
            for: recommendations,
            now: now
        )
        lastUpdatedDate = Self.latestRealtimeUpdateDate(in: recommendations)
    }

    static func routeTitle(for journey: JourneyResult) -> String {
        JourneyFormatting.routeTitle(journey)
    }

    static func summaryText(for window: WindowSubscription, recommendationCount: Int) -> String {
        guard recommendationCount > 1 else {
            return "Plan \(window.entitlement.activeWindowCount)/\(window.entitlement.activeWindowLimit)"
        }
        let trainText = recommendationCount == 1 ? "train" : "trains"
        return "\(windowTimeRangeText(for: window)) · \(recommendationCount) \(trainText) · Plan \(window.entitlement.activeWindowCount)/\(window.entitlement.activeWindowLimit)"
    }

    static func compactSummaryText(for window: WindowSubscription, recommendationCount: Int) -> String {
        guard recommendationCount > 1 else {
            return ""
        }
        let trainText = recommendationCount == 1 ? "train" : "trains"
        return "\(windowTimeRangeText(for: window)) · \(recommendationCount) \(trainText)"
    }

    static func windowTimeRangeText(for window: WindowSubscription) -> String {
        guard let start = DateFormatting.date(from: window.departureStart) else {
            return "\(window.windowMinutes) min"
        }

        let end = start.addingTimeInterval(TimeInterval(window.windowMinutes) * 60)
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "Europe/London")
        formatter.dateFormat = "HH:mm"
        return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
    }

    static func needProfileForFirstScreen(
        hasRoutine: Bool,
        hasActiveItinerary: Bool,
        isSharedJourney: Bool = false
    ) -> NeedProfileKind {
        if isSharedJourney {
            return .sharedJourneyCheck
        }
        if hasActiveItinerary {
            return .connectionSensitiveTrip
        }
        if hasRoutine {
            return .routineCommute
        }
        return .oneOffDirectTrip
    }

    static func setupPromptContent(
        isSignedIn: Bool,
        hasRoutine: Bool,
        hasActiveItinerary: Bool,
        isSharedJourney: Bool = false
    ) -> SetupPromptContent {
        if !isSignedIn {
            return SetupPromptContent(
                moment: .signedOut,
                needProfile: .oneOffDirectTrip,
                title: "Monitor the journey that matters now",
                statusText: "Signed out",
                primaryActionText: "Sign in",
                detailText: "RightTrain can watch live changes and keep setup focused on the trip you need."
            )
        }

        if isSharedJourney {
            return SetupPromptContent(
                moment: .sharedView,
                needProfile: .sharedJourneyCheck,
                title: "Shared journey",
                statusText: "Public live view",
                primaryActionText: "Check status",
                detailText: "Open the shared journey without mixing it into your own monitoring setup."
            )
        }

        let needProfile = needProfileForFirstScreen(
            hasRoutine: hasRoutine,
            hasActiveItinerary: hasActiveItinerary
        )
        switch needProfile {
        case .routineCommute:
            return SetupPromptContent(
                moment: .noActiveJourney,
                needProfile: needProfile,
                title: "Start from your routine",
                statusText: "No active journey",
                primaryActionText: "Plan and monitor",
                detailText: "Use your saved commute details, then adjust the live window before monitoring."
            )
        case .connectionSensitiveTrip:
            return SetupPromptContent(
                moment: .planning,
                needProfile: needProfile,
                title: "Plan the connection",
                statusText: "Route with changes",
                primaryActionText: "Find live options",
                detailText: "Compare routes by first action, transfer risk, and live confidence."
            )
        case .oneOffDirectTrip, .liveAlertReturn, .sharedJourneyCheck:
            return SetupPromptContent(
                moment: .noActiveJourney,
                needProfile: needProfile,
                title: "Plan and monitor a journey",
                statusText: "No active journey",
                primaryActionText: "Choose route and time",
                detailText: "Pick origin, destination, and travel window; RightTrain watches the live service after that."
            )
        }
    }

    static func journeyMoment(
        for recommendation: DirectWindowRecommendation,
        now: Date = Date(),
        isOffline: Bool = false
    ) -> JourneyMomentKind {
        if isOffline {
            return .offline
        }
        if let updatedAt = recommendation.journey.realtimeUpdatedAt.flatMap(DateFormatting.date(from:)),
           now.timeIntervalSince(updatedAt) > staleDataInterval {
            return .staleData
        }
        if JourneyFormatting.isCancelled(recommendation.journey) ||
            recommendation.score.cancellationPenaltyMinutes != nil ||
            recommendation.score.severeDelayPenaltyMinutes != nil {
            return .disrupted
        }
        if JourneyFormatting.isArrived(recommendation.journey) {
            return .completed
        }
        if JourneyFormatting.isDeparted(recommendation.journey) {
            return .onBoard
        }
        if let departure = currentDepartureDate(for: recommendation),
           departure.timeIntervalSince(now) <= 10 * 60 {
            return .approachingDeparture
        }
        return .monitoringBeforeDeparture
    }

    static func journeyMoment(for itinerary: ItinerarySubscription, isOffline: Bool = false) -> JourneyMomentKind {
        if isOffline {
            return .offline
        }
        let normalizedStatus = itinerary.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalizedStatus != "active", !normalizedStatus.isEmpty {
            return .disrupted
        }
        switch itinerary.resolvedPhase {
        case .planning, .atOrigin:
            return .monitoringBeforeDeparture
        case .onLeg:
            return .onBoard
        case .approachingInterchange:
            return .interchange
        case .onFinalLeg:
            return .onBoard
        }
    }

    static func freshnessText(updatedAt: Date?, now: Date = Date()) -> String {
        guard let updatedAt else {
            return "Live data pending"
        }
        let seconds = max(0, now.timeIntervalSince(updatedAt))
        if seconds < 60 {
            return "Updated now"
        }
        let minutes = Int((seconds / 60).rounded(.down))
        if minutes <= 1 {
            return "Updated 1 min ago"
        }
        if minutes < 60 {
            return "Updated \(minutes) min ago"
        }
        let hours = minutes / 60
        if hours == 1 {
            return "Updated 1 hr ago"
        }
        return "Updated \(hours) hr ago"
    }

    static func liveGlanceContent(
        for recommendation: DirectWindowRecommendation,
        routeTitle: String? = nil,
        needProfile: NeedProfileKind = .oneOffDirectTrip,
        now: Date = Date(),
        isOffline: Bool = false
    ) -> LiveGlanceContent {
        let journey = recommendation.journey
        let moment = journeyMoment(for: recommendation, now: now, isOffline: isOffline)
        let status = statusDisplay(for: recommendation, now: now)
        let departure = JourneyFormatting.departureDisplay(journey)
        let arrival = JourneyFormatting.arrivalDisplay(journey)
        let platform = platformDisplay(for: journey)
        let updatedAt = journey.realtimeUpdatedAt.flatMap(DateFormatting.date(from:))
        return LiveGlanceContent(
            moment: moment,
            needProfile: needProfile,
            routeTitle: routeTitle ?? Self.routeTitle(for: journey),
            routeContextText: JourneyFormatting.operatorSummaryText(journey),
            statusText: status.text,
            statusTone: status.tone,
            timingText: JourneyFormatting.glanceTimingText(departure: departure, arrival: arrival),
            platformText: JourneyFormatting.platformStateText(primary: platform.primary, secondary: platform.secondary, confirmed: platform.confirmed),
            nextActionText: JourneyFormatting.nextActionText(for: journey, platform: platform.primary, moment: moment),
            freshnessText: isOffline ? "Offline · showing saved journey data" : freshnessText(updatedAt: updatedAt, now: now)
        )
    }

    static func shouldCollapseSetup(for window: WindowSubscription?) -> Bool {
        guard let window else {
            return false
        }
        return window.entitlement.activeWindowCount >= window.entitlement.activeWindowLimit
    }

    static func collapsedSetupState(for window: WindowSubscription) -> CollapsedSetupState {
        CollapsedSetupState(
            title: "Create Pin",
            statusText: "Pin \(window.entitlement.activeWindowCount)/\(window.entitlement.activeWindowLimit) in use",
            message: "Unpin the current journey before creating another Pin."
        )
    }

    static func deduplicatedRecommendations(for window: WindowSubscription) -> [DirectWindowRecommendation] {
        var seen = Set<String>()
        var unique: [DirectWindowRecommendation] = []

        for recommendation in [window.selectedRecommendation] + window.recommendations {
            let key = journeyKey(recommendation.journey)
            guard !seen.contains(key) else {
                continue
            }
            seen.insert(key)
            unique.append(recommendation)
        }

        return JourneyFormatting.chronologicalRecommendations(unique)
    }

    static func bestRecommendation(
        for window: WindowSubscription,
        recommendations: [DirectWindowRecommendation]
    ) -> DirectWindowRecommendation {
        if let selected = recommendations.first(where: { journeyKey($0.journey) == journeyKey(window.selectedRecommendation.journey) }) {
            return selected
        }
        return recommendations.first ?? window.selectedRecommendation
    }

    static func pinnedRecommendation(
        for window: WindowSubscription,
        recommendations: [DirectWindowRecommendation]
    ) -> DirectWindowRecommendation? {
        guard let serviceID = window.pinnedTrainServiceId, serviceID > 0 else {
            return nil
        }
        return recommendations.first { $0.journey.serviceId == serviceID }
    }

    /// Picks the train that should be displayed as the hero. Prefers the
    /// recommended best train, but if it has already departed we promote the
    /// next future train so the hero stays actionable.
    static func heroRecommendation(
        best: DirectWindowRecommendation,
        recommendations: [DirectWindowRecommendation],
        now: Date = Date()
    ) -> DirectWindowRecommendation {
        if !JourneyFormatting.isDeparted(best.journey),
           !isCancelled(best, now: now) {
            return best
        }
        let chronological = currentDepartureRecommendations(recommendations)
        if let nextFuture = chronological.first(where: { rec in
            guard let date = currentDepartureDate(for: rec) else { return false }
            return date >= now &&
                !JourneyFormatting.isDeparted(rec.journey) &&
                !isCancelled(rec, now: now)
        }) {
            return nextFuture
        }
        if let nextActionable = chronological.first(where: { rec in
            !JourneyFormatting.isDeparted(rec.journey) &&
                !isCancelled(rec, now: now)
        }) {
            return nextActionable
        }
        return best
    }

    /// Returns the upcoming (not-yet-departed) trains, in chronological order,
    /// excluding the hero so it isn't duplicated.
    func futureDepartures(now: Date = Date()) -> [DirectWindowRecommendation] {
        let heroKey = Self.journeyKey(heroRecommendation.journey)
        return Self.currentDepartureRecommendations(recommendations).filter { rec in
            guard Self.journeyKey(rec.journey) != heroKey else { return false }
            return !JourneyFormatting.isDeparted(rec.journey) &&
                !Self.isCancelled(rec, now: now)
        }
    }

    /// Returns cancelled services in chronological order. These are kept out
    /// of upcoming and departed sections because they are no longer actionable.
    func cancelledDepartures(now: Date = Date()) -> [DirectWindowRecommendation] {
        Self.currentDepartureRecommendations(recommendations).filter { rec in
            Self.isCancelled(rec, now: now)
        }
    }

    /// Returns the most recent train that has actually departed within the
    /// short catch-confirmation window.
    func justDepartedRecommendation(now: Date = Date()) -> DirectWindowRecommendation? {
        Self.currentDepartureRecommendations(recommendations)
            .reversed()
            .first { Self.isJustDeparted($0, now: now) }
    }

    /// The hero should stay focused on an actionable train. Departed trains only
    /// stay in the hero once the user has pinned them as caught.
    func shouldShowHero(now: Date = Date()) -> Bool {
        if Self.isCancelled(heroRecommendation, now: now) {
            return false
        }
        return heroIsPinnedTrain || !JourneyFormatting.isDeparted(heroRecommendation.journey)
    }

    /// Returns trains that have already departed, in reverse chronological
    /// order (most recently departed first), excluding the hero and the
    /// temporary just-departed prompt.
    func pastDepartures(now: Date = Date(), excludingJustDeparted: Bool = true) -> [DirectWindowRecommendation] {
        let heroKey = shouldShowHero(now: now) ? Self.journeyKey(heroRecommendation.journey) : nil
        let justDepartedKey = excludingJustDeparted ? justDepartedRecommendation(now: now).map { Self.journeyKey($0.journey) } : nil
        return Self.currentDepartureRecommendations(recommendations)
            .filter { rec in
                let key = Self.journeyKey(rec.journey)
                if let heroKey, key == heroKey { return false }
                if let justDepartedKey, key == justDepartedKey { return false }
                return JourneyFormatting.isDeparted(rec.journey) &&
                    !Self.isCancelled(rec, now: now)
            }
            .reversed()
    }

    /// Produces a live countdown string for the hero card.
    static func countdown(
        for recommendation: DirectWindowRecommendation,
        now: Date = Date()
    ) -> CountdownDisplay {
        let journey = recommendation.journey
        let status = JourneyFormatting.displayStatus(journey)

        if status == "cancelled" {
            return CountdownDisplay(text: "Cancelled", tone: .red, isDeparted: false, targetDate: nil)
        }

        guard let departure = currentDepartureDate(for: recommendation) else {
            return CountdownDisplay(text: "Departure unknown", tone: .amber, isDeparted: false, targetDate: nil)
        }

        let secondsUntil = departure.timeIntervalSince(now)

        if secondsUntil > 60 {
            let minutes = Int((secondsUntil / 60).rounded(.up))
            return CountdownDisplay(text: "Leaves in \(minutes) min", tone: .green, isDeparted: false, targetDate: departure)
        }
        if secondsUntil >= 0 {
            return CountdownDisplay(text: "Leaves now", tone: .accent, isDeparted: false, targetDate: departure)
        }

        guard JourneyFormatting.isDeparted(journey) else {
            return CountdownDisplay(text: "Awaiting departure", tone: .accent, isDeparted: false, targetDate: departure)
        }

        let secondsSince = -secondsUntil
        if secondsSince < 5 * 60 {
            let minutes = max(1, Int((secondsSince / 60).rounded(.down)))
            return CountdownDisplay(text: "Departed \(minutes) min ago", tone: .accent, isDeparted: true, targetDate: departure)
        }

        let arrivalDisplay = JourneyFormatting.arrivalDisplay(journey)
        let arrivalText = arrivalDisplay.currentText ?? arrivalDisplay.scheduledText
        return CountdownDisplay(text: "Departed · arr \(arrivalText)", tone: .accent, isDeparted: true, targetDate: departure)
    }

    static func departureItems(
        for recommendations: [DirectWindowRecommendation],
        now: Date = Date()
    ) -> [DepartureListItem] {
        let departures = currentDepartureRecommendations(recommendations)
        let nowMarker = DepartureListItem.nowMarker(nowMarkerText(now))
        var items: [DepartureListItem] = []
        var insertedNow = false

        for recommendation in departures {
            if !insertedNow,
               let departureDate = currentDepartureDate(for: recommendation),
               departureDate >= now {
                items.append(nowMarker)
                insertedNow = true
            }
            items.append(.train(recommendation))
        }

        if !insertedNow, !departures.isEmpty {
            items.append(nowMarker)
        }

        return items
    }

    static func currentDepartureRecommendations(_ recommendations: [DirectWindowRecommendation]) -> [DirectWindowRecommendation] {
        recommendations.sorted { left, right in
            let leftDate = currentDepartureDate(for: left)
            let rightDate = currentDepartureDate(for: right)
            switch (leftDate, rightDate) {
            case let (leftDate?, rightDate?) where leftDate != rightDate:
                return leftDate < rightDate
            case (.some, nil):
                return true
            case (nil, .some):
                return false
            default:
                return left.journey.serviceId < right.journey.serviceId
            }
        }
    }

    static func currentDepartureDate(for recommendation: DirectWindowRecommendation) -> Date? {
        let display = JourneyFormatting.departureDisplay(recommendation.journey)
        return display.currentDate ?? display.scheduledDate
    }

    private static func isJustDeparted(_ recommendation: DirectWindowRecommendation, now: Date) -> Bool {
        guard JourneyFormatting.isDeparted(recommendation.journey),
              let departureDate = currentDepartureDate(for: recommendation) else {
            return false
        }
        let secondsSinceDeparture = now.timeIntervalSince(departureDate)
        return secondsSinceDeparture >= 0 && secondsSinceDeparture < justDepartedVisibilityInterval
    }

    private static func isCancelled(_ recommendation: DirectWindowRecommendation, now: Date) -> Bool {
        JourneyFormatting.isCancelled(recommendation.journey)
    }

    static func nowMarkerText(_ now: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "Europe/London")
        formatter.dateFormat = "HH:mm"
        return "Now \(formatter.string(from: now))"
    }

    static func statusDisplay(
        for recommendation: DirectWindowRecommendation,
        now: Date = Date()
    ) -> StatusDisplay {
        let journey = recommendation.journey
        let summary = JourneyFormatting.movementStatusSummary(journey, score: recommendation.score, now: now)
        return StatusDisplay(text: summary.compactText, tone: tone(for: summary.statusKind))
    }

    static func heroStatusDisplay(
        for recommendation: DirectWindowRecommendation,
        now: Date = Date()
    ) -> StatusDisplay? {
        guard let summary = JourneyFormatting.heroStatusSummary(
            recommendation.journey,
            score: recommendation.score,
            now: now
        ) else {
            return nil
        }
        return StatusDisplay(text: summary.compactText, tone: tone(for: summary.statusKind))
    }

    private static func tone(for statusKind: String) -> StatusPill.Tone {
        switch statusKind {
        case "arrived", "good":
            return .green
        case "cancelled", "missed":
            return .red
        case "delayed", "unreported", "not_reported", "at_risk":
            return .amber
        case "departed":
            return .accent
        default:
            return .amber
        }
    }

    // MARK: - RTSurface derivation

    /// The full-bleed status surface for the hero recommendation.
    /// Defaults to `.good` (emerald) when no anomalous status is present
    /// (pre-live data, on-time, departing-now).
    var heroSurface: RTSurface {
        guard let display = Self.heroStatusDisplay(for: heroRecommendation) else {
            return .good
        }
        switch display.tone {
        case .red:   return .bad
        case .amber: return .warn
        default:     return .good
        }
    }

    // MARK: - Platform display

    static func platformDisplay(for journey: JourneyResult) -> PlatformDisplay {
        platformDisplay(
            current: JourneyFormatting.platformText(journey),
            scheduled: journey.originPlatform,
            confirmed: JourneyFormatting.departurePlatformConfirmed(journey)
        )
    }

    static func arrivalPlatformDisplay(for journey: JourneyResult) -> PlatformDisplay {
        platformDisplay(
            current: JourneyFormatting.arrivalPlatformText(journey),
            scheduled: journey.destinationPlatform,
            confirmed: JourneyFormatting.arrivalPlatformConfirmed(journey)
        )
    }

    private static func platformDisplay(current: String?, scheduled: String?, confirmed: Bool) -> PlatformDisplay {
        let currentPlatform = compactPlatform(current)
        let scheduledPlatform = compactPlatform(scheduled)
        let secondary: String?

        if currentPlatform != "TBC",
           currentPlatform != "-",
           scheduledPlatform != "-",
           scheduledPlatform != currentPlatform {
            secondary = "was \(readablePlatform(scheduledPlatform))"
        } else {
            secondary = nil
        }

        return PlatformDisplay(primary: currentPlatform, secondary: secondary, confirmed: confirmed)
    }

    private static func journeyKey(_ journey: JourneyResult) -> String {
        "\(journey.serviceId)|\(journey.rid)|\(journey.ssd)"
    }

    private static func compactPlatform(_ value: String?) -> String {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return "-"
        }

        if value.uppercased() == "TBC" {
            return "TBC"
        }

        if value.uppercased().hasPrefix("P") {
            return value.uppercased()
        }

        return "P\(value)"
    }

    private static func readablePlatform(_ value: String) -> String {
        if value.uppercased().hasPrefix("P"), value.count > 1 {
            return String(value.dropFirst())
        }
        return value
    }

    private static func latestRealtimeUpdateDate(in recommendations: [DirectWindowRecommendation]) -> Date? {
        recommendations
            .compactMap { $0.journey.realtimeUpdatedAt.flatMap(DateFormatting.date(from:)) }
            .max()
    }
}
