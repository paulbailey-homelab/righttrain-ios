import Foundation

enum JourneyFormatting {
    struct MovementStatusSummary {
        var text: String
        var compactText: String
        var displayStatus: String
        var statusKind: String
        var movementPhase: String
        var reportState: String
        var delayMinutes: Int
        var departed: Bool
        var reportIncomplete: Bool
    }

    /// Visual route title: "Origin → Destination". Every on-screen route title
    /// uses this one helper so direct and itinerary cards agree. Accessibility
    /// labels should keep the "to" wording (`routeText`) — VoiceOver reads the
    /// arrow glyph literally.
    static func routeTitle(origin: String, destination: String) -> String {
        "\(origin) → \(destination)"
    }

    static func routeTitle(_ journey: JourneyResult) -> String {
        routeTitle(origin: originStationText(journey), destination: destinationStationText(journey))
    }

    static func routeText(_ journey: JourneyResult) -> String {
        "\(originStationText(journey)) to \(destinationStationText(journey))"
    }

    static func compactRouteText(_ journey: JourneyResult) -> String {
        "\(compactOriginStationText(journey)) to \(compactDestinationStationText(journey))"
    }

    static func finalDestinationText(_ journey: JourneyResult) -> String {
        stationDisplayName(
            name: journey.finalDestinationName,
            fallback: destinationStationText(journey)
        )
    }

    static func compactFinalDestinationText(_ journey: JourneyResult) -> String {
        compactStationDisplayName(
            shortName: journey.finalDestinationSixteenCharacterName,
            name: journey.finalDestinationName,
            fallback: compactDestinationStationText(journey)
        )
    }

    static func originStationText(_ journey: JourneyResult) -> String {
        stationDisplayName(
            name: journey.originName,
            fallback: journey.originCrs
        )
    }

    static func destinationStationText(_ journey: JourneyResult) -> String {
        stationDisplayName(
            name: journey.destinationName,
            fallback: journey.destinationCrs
        )
    }

    static func compactOriginStationText(_ journey: JourneyResult) -> String {
        compactStationDisplayName(
            shortName: journey.originSixteenCharacterName,
            name: journey.originName,
            fallback: journey.originCrs
        )
    }

    static func compactDestinationStationText(_ journey: JourneyResult) -> String {
        compactStationDisplayName(
            shortName: journey.destinationSixteenCharacterName,
            name: journey.destinationName,
            fallback: journey.destinationCrs
        )
    }

    static func crsRouteText(_ journey: JourneyResult) -> String {
        crsRouteText(originCrs: journey.originCrs, destinationCrs: journey.destinationCrs)
    }

    static func crsRouteText(originCrs: String, destinationCrs: String) -> String {
        let origin = nonEmpty(originCrs)?.uppercased() ?? "Origin CRS"
        let destination = nonEmpty(destinationCrs)?.uppercased() ?? "Destination CRS"
        return "\(origin) to \(destination)"
    }

    static func stationDisplayName(name: String?, fallback: String) -> String {
        nonEmpty(name) ?? fallback
    }

    static func compactStationDisplayName(shortName: String?, name: String?, fallback: String) -> String {
        nonEmpty(shortName) ?? nonEmpty(name) ?? fallback
    }

    static func departureSignageText(_ journey: JourneyResult) -> String? {
        if let text = nonEmpty(journey.departureSignageText) {
            return text
        }
        let departure = scheduledDepartureRawText(journey) ?? departureText(journey)
        let finalDestination = finalDestinationText(journey)
        guard !departure.isEmpty, !finalDestination.isEmpty else {
            return nil
        }
        let currentDeparture = departureText(journey)
        if currentDeparture != departure {
            return "\(departure) to \(finalDestination) (Expected \(currentDeparture))"
        }
        return "\(departure) to \(finalDestination)"
    }

    static func windowMembershipText(_ journey: JourneyResult) -> String? {
        switch nonEmpty(journey.windowMembership) {
        case "delayed_into_window":
            return "Delayed into window"
        case "delayed_out_of_window":
            return "Delayed out of window"
        case "departed":
            return "Departed"
        default:
            return nil
        }
    }

    static func chronologicalRecommendations(_ recommendations: [DirectWindowRecommendation]) -> [DirectWindowRecommendation] {
        recommendations.sorted { left, right in
            guard let leftDate = date(from: left.journey.scheduledDeparture),
                  let rightDate = date(from: right.journey.scheduledDeparture) else {
                return left.journey.serviceId < right.journey.serviceId
            }
            if leftDate != rightDate {
                return leftDate < rightDate
            }
            return left.journey.serviceId < right.journey.serviceId
        }
    }

    static func chronologicalRecommendations(
        topRecommendation: DirectWindowRecommendation?,
        recommendations: [DirectWindowRecommendation]
    ) -> [DirectWindowRecommendation] {
        var candidates = recommendations
        if let topRecommendation,
           !candidates.contains(where: { sameJourney($0, topRecommendation) }) {
            candidates.append(topRecommendation)
        }
        return chronologicalRecommendations(candidates)
    }

    static func departureText(_ journey: JourneyResult) -> String {
        let display = departureDisplay(journey)
        return display.currentText ?? display.scheduledText
    }

    static func arrivalText(_ journey: JourneyResult) -> String {
        let display = arrivalDisplay(journey)
        return display.currentText ?? display.scheduledText
    }

    static func glanceTimingText(departure: JourneyTimeDisplay, arrival: JourneyTimeDisplay) -> String {
        let departureText = departure.currentText ?? departure.scheduledText
        let arrivalText = arrival.currentText ?? arrival.scheduledText
        if departure.isDelayed || arrival.isDelayed {
            return "Dep \(departureText) · Arr \(arrivalText)"
        }
        return "\(departureText) → \(arrivalText)"
    }

    static func scheduledExpectedText(_ display: JourneyTimeDisplay, label: String) -> String {
        if let current = display.currentText, current != display.scheduledText {
            return "\(label) \(current), scheduled \(display.scheduledText)"
        }
        return "\(label) \(display.scheduledText)"
    }

    static func displayStatusText(_ journey: JourneyResult) -> String {
        movementStatusText(journey)
    }

    static func displayStatusText(_ detail: JourneyDetail) -> String {
        nonEmpty(detail.statusText) ?? displayStatusText(detail.displayStatus)
    }

    static func displayStatusText(_ status: String) -> String {
        switch status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "arrived":
            return "Arrived"
        case "cancelled":
            return "Cancelled"
        case "delayed":
            return "Delayed"
        case "unreported":
            return "Unreported"
        case "on_time":
            return "On time"
        default:
            if status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "deactivated" {
                return "Checking"
            }
            return status.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Checking" : status.capitalized
        }
    }

    static func displayStatus(_ journey: JourneyResult) -> String {
        knownDisplayStatus(journey.displayStatus) ?? "unknown"
    }

    static func statusKind(_ journey: JourneyResult) -> String {
        nonEmpty(journey.statusKind) ?? statusKind(forDisplayStatus: displayStatus(journey), movementPhase: movementPhase(journey))
    }

    static func movementPhase(_ journey: JourneyResult) -> String {
        nonEmpty(journey.movementPhase) ?? "not_departed"
    }

    static func reportState(_ journey: JourneyResult) -> String {
        nonEmpty(journey.reportState) ?? "pending"
    }

    static func isDeparted(_ journey: JourneyResult) -> Bool {
        let phase = movementPhase(journey)
        return phase == "departed" || phase == "arrived"
    }

    static func isArrived(_ journey: JourneyResult) -> Bool {
        movementPhase(journey) == "arrived" || displayStatus(journey) == "arrived"
    }

    static func isCancelled(_ journey: JourneyResult) -> Bool {
        displayStatus(journey) == "cancelled" || statusKind(journey) == "cancelled"
    }

    private static func knownDisplayStatus(_ value: String?) -> String? {
        guard let value = nonEmpty(value) else {
            return nil
        }
        switch value {
        case "arrived", "cancelled", "delayed", "unreported", "on_time":
            return value
        default:
            return nil
        }
    }

    private static func statusKind(forDisplayStatus status: String, movementPhase: String) -> String {
        switch status {
        case "arrived":
            return "arrived"
        case "cancelled":
            return "cancelled"
        case "delayed":
            return "delayed"
        case "unreported":
            return "unreported"
        case "on_time":
            return movementPhase == "departed" || movementPhase == "arrived" ? "departed" : "good"
        default:
            return "unknown"
        }
    }

    private static func sameJourney(_ left: DirectWindowRecommendation, _ right: DirectWindowRecommendation) -> Bool {
        left.journey.serviceId == right.journey.serviceId &&
            left.journey.rid == right.journey.rid &&
            left.journey.ssd == right.journey.ssd
    }

    static func durationText(_ journey: JourneyResult) -> String {
        let departure = departureDisplay(journey)
        let arrival = arrivalDisplay(journey)
        guard let scheduledDeparture = departure.scheduledDate,
              let scheduledArrival = arrival.scheduledDate else {
            return "Duration n/a"
        }
        let scheduled = durationText(from: scheduledDeparture, to: scheduledArrival)
        let currentDeparture = departure.currentDate ?? scheduledDeparture
        let currentArrival = arrival.currentDate ?? scheduledArrival
        let current = durationText(from: currentDeparture, to: currentArrival)
        return current == scheduled ? "Scheduled \(scheduled)" : "Scheduled \(scheduled) · current \(current)"
    }

    static func movementStatusText(
        _ journey: JourneyResult,
        score: DirectWindowRecommendationScore? = nil,
        now: Date = Date()
    ) -> String {
        movementStatusSummary(journey, score: score).text
    }

    static func compactMovementStatusText(
        _ journey: JourneyResult,
        score: DirectWindowRecommendationScore? = nil,
        now: Date = Date()
    ) -> String {
        movementStatusSummary(journey, score: score).compactText
    }

    static func movementStatusSummary(
        _ journey: JourneyResult,
        score: DirectWindowRecommendationScore? = nil,
        now: Date = Date()
    ) -> MovementStatusSummary {
        let status = displayStatus(journey)
        let kind = statusKind(journey)
        let phase = movementPhase(journey)
        let report = reportState(journey)
        let delay = score.map { statusDelayMinutes(journey: journey, score: $0) } ?? (journey.delayMinutes ?? 0)
        let text = nonEmpty(journey.statusText) ?? displayStatusText(status)
        let compactText = nonEmpty(journey.compactStatusText) ?? text
        return MovementStatusSummary(
            text: text,
            compactText: compactText,
            displayStatus: status,
            statusKind: kind,
            movementPhase: phase,
            reportState: report,
            delayMinutes: delay,
            departed: phase == "departed" || phase == "arrived",
            reportIncomplete: report == "destination_missing"
        )
    }

    static func isHeroAnomalous(_ summary: MovementStatusSummary) -> Bool {
        switch summary.statusKind {
        case "good", "departed", "arrived":
            return false
        default:
            return true
        }
    }

    static func heroStatusSummary(
        _ journey: JourneyResult,
        score: DirectWindowRecommendationScore? = nil,
        now: Date = Date()
    ) -> MovementStatusSummary? {
        let summary = movementStatusSummary(journey, score: score, now: now)
        return isHeroAnomalous(summary) ? summary : nil
    }

    static func departureDisplay(_ journey: JourneyResult) -> JourneyTimeDisplay {
        timeDisplay(
            scheduledDateValue: journey.scheduledDeparture,
            scheduledRawValue: journey.scheduledDepartureRaw,
            realtimeValue: actualDepartureValue(journey)
                ?? expectedDepartureValue(journey)
                ?? journey.expectedDeparture
        )
    }

    static func arrivalDisplay(_ journey: JourneyResult) -> JourneyTimeDisplay {
        timeDisplay(
            scheduledDateValue: journey.scheduledArrival,
            scheduledRawValue: journey.scheduledArrivalRaw,
            realtimeValue: actualArrivalValue(journey)
                ?? actualDepartureAtDestinationValue(journey)
                ?? expectedArrivalValue(journey)
                ?? journey.expectedArrival
        )
    }

    static func journeyProgress(_ journey: JourneyResult, now: Date = Date()) -> Double? {
        if isArrived(journey) {
            return 1
        }
        guard isDeparted(journey) else {
            return nil
        }
        let departure = departureDisplay(journey).currentDate ?? departureDisplay(journey).scheduledDate
        let arrival = arrivalDisplay(journey).currentDate ?? arrivalDisplay(journey).scheduledDate
        guard let departure, let arrival, arrival > departure else {
            return nil
        }
        return min(max(now.timeIntervalSince(departure) / arrival.timeIntervalSince(departure), 0), 1)
    }

    static func statusDelayMinutes(journey: JourneyResult, score: DirectWindowRecommendationScore) -> Int {
        max(score.delayMinutes, journey.delayMinutes ?? 0)
    }

    static func hasDelaySignal(journey: JourneyResult, score: DirectWindowRecommendationScore) -> Bool {
        statusKind(journey) == "delayed" || statusDelayMinutes(journey: journey, score: score) > 0
    }

    static func platformText(_ journey: JourneyResult) -> String {
        journey.realtimePlatform ?? journey.originRealtime?.platform ?? journey.originPlatform ?? "TBC"
    }

    static func arrivalPlatformText(_ journey: JourneyResult) -> String {
        journey.destinationRealtime?.platform ?? journey.destinationPlatform ?? "TBC"
    }

    static func departurePlatformConfirmed(_ journey: JourneyResult) -> Bool {
        journey.realtimePlatformConfirmed || journey.originRealtime?.platformConfirmed == true
    }

    static func arrivalPlatformConfirmed(_ journey: JourneyResult) -> Bool {
        journey.destinationRealtime?.platformConfirmed == true
    }

    /// Bare platform value with an "expected" qualifier when the feed has not
    /// confirmed it, for metric cells whose label already says "Platform".
    static func platformMetricText(_ journey: JourneyResult) -> String {
        qualifiedPlatformValue(platformText(journey), confirmed: departurePlatformConfirmed(journey))
    }

    static func qualifiedPlatformValue(_ value: String, confirmed: Bool) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "-" || trimmed.uppercased() == "TBC" || confirmed {
            return trimmed.isEmpty ? "TBC" : trimmed
        }
        return "Expected \(trimmed)"
    }

    static func platformStateText(primary: String, secondary: String? = nil, confirmed: Bool = true) -> String {
        let trimmed = primary.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "-" || trimmed.uppercased() == "TBC" {
            return "Platform TBC"
        }
        let prefix = confirmed ? "Platform" : "Expected platform"
        if let secondary = nonEmpty(secondary) {
            return "\(prefix) \(readablePlatform(trimmed)) · \(secondary)"
        }
        return "\(prefix) \(readablePlatform(trimmed))"
    }

    static func accessibilityStatusLabel(
        statusText: String,
        platformText: String,
        freshnessText: String
    ) -> String {
        [statusText, platformText, freshnessText]
            .compactMap { nonEmpty($0) }
            .joined(separator: ", ")
    }

    static func nextActionText(
        for journey: JourneyResult,
        platform: String,
        moment: ActiveWindowPresentation.JourneyMomentKind
    ) -> String {
        if isCancelled(journey) {
            return "Choose another train"
        }
        switch moment {
        case .offline:
            return "Check again when connection returns"
        case .staleData:
            return "Refresh before acting"
        case .completed:
            return "Journey complete"
        case .onBoard:
            return "Follow stops and arrival"
        case .approachingDeparture:
            let platformText = platformStateText(primary: platform)
            return platformText == "Platform TBC" ? "Watch for the platform" : "Go to \(platformText.lowercased())"
        case .interchange:
            return "Check the connection"
        case .disrupted:
            return "Review the change"
        case .monitoringBeforeDeparture, .planning:
            return "RightTrain is watching this journey"
        case .noActiveJourney:
            return "Plan and monitor a journey"
        case .signedOut:
            return "Sign in to monitor journeys"
        case .sharedView:
            return "Check shared journey status"
        }
    }

    static func operatorDisplayText(_ detail: JourneyDetail) -> String {
        nonEmpty(detail.operatorName) ?? nonEmpty(detail.operatorShortName) ?? nonEmpty(detail.toc) ?? "Not available"
    }

    static func operatorSummaryText(_ journey: JourneyResult) -> String? {
        nonEmpty(journey.operatorName) ?? nonEmpty(journey.operatorShortName) ?? nonEmpty(journey.toc)
    }

    static func operatorSummaryText(_ leg: ItineraryLeg) -> String? {
        nonEmpty(leg.operatorName) ?? nonEmpty(leg.operatorShortName) ?? nonEmpty(leg.toc)
    }

    static func operatorDisplayText(_ journey: JourneyResult) -> String {
        operatorSummaryText(journey) ?? "Not available"
    }

    private static func scheduledDepartureRawText(_ journey: JourneyResult) -> String? {
        nonEmpty(journey.scheduledDepartureRaw)
    }

    private static func readablePlatform(_ value: String) -> String {
        if value.uppercased().hasPrefix("P"), value.count > 1 {
            return String(value.dropFirst())
        }
        return value
    }

    static func coachCountText(_ detail: JourneyDetail) -> String? {
        guard let count = detail.coachCount, count > 0 else {
            return nil
        }
        let noun = count == 1 ? "coach" : "coaches"
        return "\(count) \(noun)"
    }

    static func currentTrainPosition(_ detail: JourneyDetail, now: Date = Date()) -> JourneyTrainPosition {
        guard !detail.stops.isEmpty else {
            return JourneyTrainPosition(stationIndex: nil, betweenAfterIndex: nil, progress: 0)
        }
        if detail.displayStatus == "arrived" {
            return JourneyTrainPosition(
                stationIndex: detail.stops.index(before: detail.stops.endIndex),
                betweenAfterIndex: nil,
                progress: 1
            )
        }

        if let inferred = inferredTrainPosition(from: detail.stops, now: now) {
            return inferred
        }
        if let trainPosition = detail.trainPosition {
            return trainPosition
        }
        return JourneyTrainPosition(
            stationIndex: detail.stops.indices.first,
            betweenAfterIndex: nil,
            progress: 0
        )
    }

    private static func inferredTrainPosition(from stops: [JourneyStop], now: Date) -> JourneyTrainPosition? {
        for index in stops.indices.reversed() {
            let isFinal = index == stops.index(before: stops.endIndex)
            let stop = stops[index]
            if !isFinal, let departure = actualDepartureTime(stop) {
                let nextStop = stops[stops.index(after: index)]
                return JourneyTrainPosition(
                    stationIndex: nil,
                    betweenAfterIndex: index,
                    progress: segmentProgress(
                        departure: departure,
                        arrival: expectedArrivalTime(nextStop),
                        now: now
                    )
                )
            }
            if hasActualArrival(stop) {
                return JourneyTrainPosition(stationIndex: index, betweenAfterIndex: nil, progress: 1)
            }
        }
        return nil
    }

    private static func actualDepartureTime(_ stop: JourneyStop) -> String? {
        nonEmpty(stop.realtime?.actualDeparture)
    }

    private static func expectedArrivalTime(_ stop: JourneyStop) -> String {
        nonEmpty(stop.realtime?.expectedArrival) ?? nonEmpty(stop.publicArrival) ?? nonEmpty(stop.publicDeparture) ?? ""
    }

    private static func hasActualArrival(_ stop: JourneyStop) -> Bool {
        nonEmpty(stop.realtime?.actualArrival) != nil
    }

    private static func segmentProgress(departure: String, arrival: String, now: Date) -> Double {
        guard let departureMinutes = clockMinutes(departure),
              var arrivalMinutes = clockMinutes(arrival) else {
            return 0.5
        }
        if arrivalMinutes <= departureMinutes {
            arrivalMinutes += 24 * 60
        }
        let duration = arrivalMinutes - departureMinutes
        guard duration > 0 else {
            return 0.5
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London") ?? .current
        let components = calendar.dateComponents([.hour, .minute], from: now)
        var currentMinutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        if currentMinutes < departureMinutes {
            currentMinutes += 24 * 60
        }
        return min(max(Double(currentMinutes - departureMinutes) / Double(duration), 0), 1)
    }

    private static func clockMinutes(_ value: String) -> Int? {
        let parts = value.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count >= 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]),
              (0...47).contains(hour),
              (0...59).contains(minute) else {
            return nil
        }
        return hour * 60 + minute
    }

    private static func actualDepartureValue(_ journey: JourneyResult) -> String? {
        nonEmpty(journey.originRealtime?.actualDeparture)
    }

    private static func expectedDepartureValue(_ journey: JourneyResult) -> String? {
        nonEmpty(journey.originRealtime?.expectedDeparture)
    }

    private static func actualArrivalValue(_ journey: JourneyResult) -> String? {
        nonEmpty(journey.destinationRealtime?.actualArrival)
    }

    private static func actualDepartureAtDestinationValue(_ journey: JourneyResult) -> String? {
        nonEmpty(journey.destinationRealtime?.actualDeparture)
    }

    private static func expectedArrivalValue(_ journey: JourneyResult) -> String? {
        nonEmpty(journey.destinationRealtime?.expectedArrival)
    }

    private static func durationText(from start: Date, to end: Date) -> String {
        let minutes = max(Int((end.timeIntervalSince(start) / 60).rounded()), 0)
        let hours = minutes / 60
        let remaining = minutes % 60
        if hours > 0 && remaining > 0 {
            return "\(hours)h \(remaining)m"
        }
        if hours > 0 {
            return "\(hours)h"
        }
        return "\(remaining)m"
    }

    private static func timeDisplay(
        scheduledDateValue: String,
        scheduledRawValue: String?,
        realtimeValue: String?
    ) -> JourneyTimeDisplay {
        let scheduledDate = date(from: scheduledDateValue)
        let scheduledText = nonEmpty(scheduledRawValue) ?? timeText(scheduledDateValue)
        guard let realtimeValue = nonEmpty(realtimeValue),
              let scheduledDate,
              let realtimeDate = railDate(from: realtimeValue, near: scheduledDate) else {
            return JourneyTimeDisplay(
                scheduledText: scheduledText,
                currentText: nil,
                isDelayed: false,
                scheduledDate: scheduledDate,
                currentDate: nil
            )
        }

        guard realtimeDate >= scheduledDate else {
            return JourneyTimeDisplay(
                scheduledText: scheduledText,
                currentText: nil,
                isDelayed: false,
                scheduledDate: scheduledDate,
                currentDate: nil
            )
        }

        let currentText = timeText(realtimeValue)
        let isDelayed = realtimeDate.timeIntervalSince(scheduledDate) >= 60
        return JourneyTimeDisplay(
            scheduledText: scheduledText,
            currentText: isDelayed && currentText != scheduledText ? currentText : nil,
            isDelayed: isDelayed,
            scheduledDate: scheduledDate,
            currentDate: isDelayed ? realtimeDate : nil
        )
    }

    private static func timeText(_ rawValue: String) -> String {
        guard let date = DateFormatting.date(from: rawValue) else {
            return rawValue
        }
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "Europe/London")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private static func date(from rawValue: String) -> Date? {
        DateFormatting.date(from: rawValue)
    }

    static func railDate(from rawValue: String, near anchor: Date) -> Date? {
        if let date = DateFormatting.date(from: rawValue) {
            return date
        }

        let parts = rawValue.split(separator: ":")
        guard parts.count >= 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1].prefix(2)),
              (0...23).contains(hour),
              (0...59).contains(minute) else {
            return nil
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London") ?? .current

        var components = calendar.dateComponents([.year, .month, .day], from: anchor)
        components.hour = hour
        components.minute = minute
        components.second = 0

        guard var date = calendar.date(from: components) else {
            return nil
        }
        if date < anchor.addingTimeInterval(-12 * 60 * 60) {
            date = calendar.date(byAdding: .day, value: 1, to: date) ?? date
        } else if date > anchor.addingTimeInterval(12 * 60 * 60) {
            date = calendar.date(byAdding: .day, value: -1, to: date) ?? date
        }
        return date
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }
}

struct JourneyTimeDisplay {
    var scheduledText: String
    var currentText: String?
    var isDelayed: Bool
    var scheduledDate: Date?
    var currentDate: Date?
}
