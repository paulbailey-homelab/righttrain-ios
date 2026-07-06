import Foundation

enum ItineraryFormatting {
    struct StatusDisplay {
        var text: String
        var icon: String
        var tone: StatusPill.Tone
    }

    static func chronologicalItineraries(
        topItinerary: ItineraryRecommendation?,
        itineraries: [ItineraryRecommendation]
    ) -> [ItineraryRecommendation] {
        var candidates = itineraries
        if let topItinerary,
           !candidates.contains(where: { $0.stableKey == topItinerary.stableKey }) {
            candidates.append(topItinerary)
        }
        return candidates.sorted { left, right in
            guard let leftDate = DateFormatting.date(from: left.scheduledDeparture),
                  let rightDate = DateFormatting.date(from: right.scheduledDeparture) else {
                return left.rank < right.rank
            }
            if leftDate != rightDate {
                return leftDate < rightDate
            }
            return left.rank < right.rank
        }
    }

    static func routeText(_ itinerary: ItineraryRecommendation) -> String {
        guard let first = itinerary.legs.first,
              let last = itinerary.legs.last else {
            return "\(itinerary.originCrs) to \(itinerary.destinationCrs)"
        }
        return "\(originStationText(first)) to \(destinationStationText(last))"
    }

    /// Visual title variant — matches the direct-journey "Origin → Destination"
    /// style. Use `routeText` for accessibility labels.
    static func routeTitle(_ itinerary: ItineraryRecommendation) -> String {
        guard let first = itinerary.legs.first,
              let last = itinerary.legs.last else {
            return JourneyFormatting.routeTitle(origin: itinerary.originCrs, destination: itinerary.destinationCrs)
        }
        return JourneyFormatting.routeTitle(
            origin: originStationText(first),
            destination: destinationStationText(last)
        )
    }

    static func departureText(_ itinerary: ItineraryRecommendation) -> String {
        timeText(itinerary.expectedDeparture)
    }

    static func arrivalText(_ itinerary: ItineraryRecommendation) -> String {
        timeText(itinerary.expectedArrival)
    }

    static func durationText(_ itinerary: ItineraryRecommendation) -> String {
        guard let departure = DateFormatting.date(from: itinerary.expectedDeparture),
              let arrival = DateFormatting.date(from: itinerary.expectedArrival) else {
            return "Duration n/a"
        }
        return durationText(from: departure, to: arrival)
    }

    static func changesText(_ itinerary: ItineraryRecommendation) -> String {
        let count = itinerary.score.changeCount
        if count == 0 {
            return "Direct"
        }
        return count == 1 ? "1 change" : "\(count) changes"
    }

    static func transferMetricLabel(_ itinerary: ItineraryRecommendation) -> String {
        let fixedCount = itinerary.connections.filter(isFixedLinkConnection).count
        if fixedCount > 1 || (fixedCount == 1 && itinerary.score.changeCount > 1) {
            return "Transfers"
        }
        return fixedCount == 1 ? "Transfer" : "Changes"
    }

    static func transferMetricText(_ itinerary: ItineraryRecommendation) -> String {
        let count = itinerary.score.changeCount
        guard count > 0 else {
            return "Direct"
        }
        let fixedSummaries = itinerary.connections.compactMap(fixedLinkTransferSummary)
        guard !fixedSummaries.isEmpty else {
            return changesText(itinerary)
        }
        if fixedSummaries.count == 1, count == 1 {
            return fixedSummaries[0].detail
        }
        if fixedSummaries.count == count {
            if fixedSummaries.count <= 2 {
                return fixedSummaries.map { $0.mode }.joined(separator: " + ")
            }
            return "\(fixedSummaries.count) transfers"
        }
        let remainingChanges = max(0, count - fixedSummaries.count)
        let fixedText = fixedSummaries.map { $0.mode }.joined(separator: " + ")
        let changeText = remainingChanges == 1 ? "1 change" : "\(remainingChanges) changes"
        return "\(fixedText) + \(changeText)"
    }

    static func marginText(_ itinerary: ItineraryRecommendation) -> String {
        guard itinerary.score.changeCount > 0 else {
            return "No change"
        }
        let margin = itinerary.score.minimumConnectionMarginMinutes
        if margin < 0 {
            return "Missed"
        }
        return "\(margin)m"
    }

    static func firstLegPlatformText(_ itinerary: ItineraryRecommendation) -> String {
        guard let first = itinerary.legs.first else {
            return "TBC"
        }
        return nonEmpty(first.realtimePlatform)
            ?? nonEmpty(first.originRealtime?.platform)
            ?? nonEmpty(first.originPlatform)
            ?? "TBC"
    }

    static func firstLegPlatformConfirmed(_ itinerary: ItineraryRecommendation) -> Bool {
        guard let first = itinerary.legs.first else {
            return false
        }
        return first.realtimePlatformConfirmed || first.originRealtime?.platformConfirmed == true
    }

    static func legRouteText(_ leg: ItineraryLeg) -> String {
        "\(originStationText(leg)) to \(destinationStationText(leg))"
    }

    static func legSummaryText(
        _ leg: ItineraryLeg,
        includesTimes: Bool = true,
        includesPlatform: Bool = true,
        includesStatus: Bool = true
    ) -> String {
        let journey = leg.journeyResult
        var parts: [String] = []
        if includesTimes {
            parts.append("\(JourneyFormatting.departureText(journey)) - \(JourneyFormatting.arrivalText(journey))")
        }
        if includesPlatform {
            parts.append(JourneyFormatting.platformText(journey))
        }
        if let operatorText = JourneyFormatting.operatorSummaryText(journey) {
            parts.append(operatorText)
        }
        if let membership = JourneyFormatting.windowMembershipText(journey) {
            parts.append(membership)
        }
        if includesStatus,
           JourneyFormatting.heroStatusSummary(journey) != nil {
            parts.append(JourneyFormatting.movementStatusText(journey))
        }
        return parts.joined(separator: " · ")
    }

    static func connection(afterLegIndex legIndex: Int, in itinerary: ItineraryRecommendation) -> ItineraryConnection? {
        itinerary.connections.first { $0.fromLegIndex == legIndex }
    }

    static func connectionTitleText(_ connection: ItineraryConnection) -> String {
        if let mode = nonEmpty(connection.transferMode) {
            return "\(transferModeTitleText(mode)) at \(connectionStationText(connection))"
        }
        if isFixedLinkConnection(connection) {
            return "Transfer at \(connectionStationText(connection))"
        }
        return "Change at \(connectionStationText(connection))"
    }

    static func connectionTransferText(_ connection: ItineraryConnection) -> String {
        if let mode = nonEmpty(connection.transferMode) {
            return "\(transferModeText(mode)) \(connection.requiredTransferMinutes)m"
        }
        if isFixedLinkConnection(connection) {
            return "Transfer \(connection.requiredTransferMinutes)m"
        }
        return connectionTransferMinutes(connection)
            .map { "\($0) min change" } ?? "change"
    }

    static func connectionMarginText(_ connection: ItineraryConnection) -> String {
        let margin = connection.expectedMarginMinutes
        return margin < 0 ? "\(abs(margin)) min short" : "\(margin) min to change"
    }

    static func connectionRiskSummaryText(_ connection: ItineraryConnection) -> String {
        switch connection.risk.status {
        case "missed":
            return connectionMarginText(connection)
        case "tight":
            return "Tight \(connection.expectedMarginMinutes) min change"
        default:
            return connectionMarginText(connection)
        }
    }

    static func connectionDetailText(_ connection: ItineraryConnection) -> String {
        "\(connectionTransferText(connection)) · \(connectionMarginText(connection))"
    }

    static func connectionText(_ connection: ItineraryConnection) -> String {
        "\(connectionTitleText(connection)) · \(connectionDetailText(connection))"
    }

    static func connectionModeBadgeText(_ connection: ItineraryConnection) -> String? {
        nonEmpty(connection.transferMode).map(transferModeText)
    }

    static func approachingConnectionText(_ connection: ItineraryConnection) -> String {
        if let mode = nonEmpty(connection.transferMode) {
            return "\(lowercaseFirst(transferModeTitleText(mode))) at \(connectionStationText(connection))"
        }
        if isFixedLinkConnection(connection) {
            return "transfer at \(connectionStationText(connection))"
        }
        return connectionStationText(connection)
    }

    static func connectionAdviceText(_ connection: ItineraryConnection) -> String? {
        var parts: [String] = []
        let lines = (connection.transferLinesOfRoute ?? [])
            .compactMap(nonEmpty)
        if !lines.isEmpty {
            parts.append(lines.joined(separator: ", "))
        }
        if let advice = nonEmpty(connection.transferAdvice) {
            parts.append(advice)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func connectionTone(_ connection: ItineraryConnection) -> StatusPill.Tone {
        switch connection.risk.status {
        case "missed":
            return .red
        case "at_risk", "tight":
            return .amber
        default:
            return .green
        }
    }

    static func statusDisplay(_ itinerary: ItineraryRecommendation) -> StatusDisplay {
        if let text = nonEmpty(itinerary.statusText) {
            return StatusDisplay(text: sentence(text), icon: icon(forStatusKind: itinerary.statusKind), tone: tone(forStatusKind: itinerary.statusKind))
        }
        if itinerary.legs.contains(where: { $0.cancelled }) {
            return StatusDisplay(text: "One or more legs are cancelled.", icon: "xmark.octagon.fill", tone: .red)
        }
        if let missed = itinerary.connections.first(where: { $0.risk.status == "missed" }) {
            return StatusDisplay(text: "Connection missed at \(connectionStationText(missed)); \(abs(missed.expectedMarginMinutes)) min short.", icon: "xmark.octagon.fill", tone: .red)
        }
        if let atRisk = itinerary.connections.first(where: { $0.risk.status == "at_risk" }) {
            return StatusDisplay(text: "Connection at risk at \(connectionStationText(atRisk)); \(max(atRisk.expectedMarginMinutes, 0)) min to change.", icon: "exclamationmark.triangle.fill", tone: .amber)
        }
        if let tight = itinerary.connections.first(where: { $0.risk.status == "tight" }) {
            return StatusDisplay(text: "Tight connection at \(connectionStationText(tight)); \(tight.expectedMarginMinutes) min to change.", icon: "exclamationmark.triangle.fill", tone: .amber)
        }
        if itinerary.score.delayMinutes > 0 {
            return StatusDisplay(text: "Delayed \(itinerary.score.delayMinutes) min.", icon: "clock.fill", tone: .amber)
        }
        if !itinerary.score.usable {
            let reason = itinerary.score.reasons?.first ?? "This journey is not currently usable."
            return StatusDisplay(text: reason, icon: "exclamationmark.triangle.fill", tone: .amber)
        }
        return StatusDisplay(text: "On time.", icon: "checkmark.circle.fill", tone: .green)
    }

    static func anomalousStatusDisplay(_ itinerary: ItineraryRecommendation) -> StatusDisplay? {
        let display = statusDisplay(itinerary)
        guard !(display.tone == .green && display.text == "On time.") else {
            return nil
        }
        return display
    }

    private static func icon(forStatusKind statusKind: String?) -> String {
        switch statusKind {
        case "cancelled", "missed":
            return "xmark.octagon.fill"
        case "delayed", "unreported", "at_risk":
            return "exclamationmark.triangle.fill"
        default:
            return "checkmark.circle.fill"
        }
    }

    private static func tone(forStatusKind statusKind: String?) -> StatusPill.Tone {
        switch statusKind {
        case "cancelled", "missed":
            return .red
        case "delayed", "unreported", "at_risk":
            return .amber
        default:
            return .green
        }
    }

    private static func sentence(_ value: String) -> String {
        value.hasSuffix(".") ? value : "\(value)."
    }

    private static func originStationText(_ leg: ItineraryLeg) -> String {
        JourneyFormatting.stationDisplayName(
            name: leg.originName,
            fallback: leg.originCrs
        )
    }

    private static func destinationStationText(_ leg: ItineraryLeg) -> String {
        JourneyFormatting.stationDisplayName(
            name: leg.destinationName,
            fallback: leg.destinationCrs
        )
    }

    private static func connectionStationText(_ connection: ItineraryConnection) -> String {
        JourneyFormatting.stationDisplayName(
            name: connection.atName,
            fallback: connection.atCrs
        )
    }

    private static func transferModeText(_ value: String) -> String {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
        case "BUS":
            return "Bus"
        case "FERRY":
            return "Ferry"
        case "METRO":
            return "Metro"
        case "TAXI":
            return "Taxi"
        case "TRAM":
            return "Tram"
        case "TRANSFER":
            return "Transfer"
        case "TUBE":
            return "Tube"
        case "WALK":
            return "Walk"
        default:
            return value.capitalized
        }
    }

    private static func transferModeTitleText(_ value: String) -> String {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
        case "BUS":
            return "Bus journey"
        case "FERRY":
            return "Ferry crossing"
        case "METRO":
            return "Metro journey"
        case "TAXI":
            return "Taxi transfer"
        case "TRAM":
            return "Tram journey"
        case "TRANSFER":
            return "Transfer"
        case "TUBE":
            return "Tube journey"
        case "WALK":
            return "Walk"
        default:
            return value.capitalized
        }
    }

    private static func fixedLinkTransferSummary(_ connection: ItineraryConnection) -> (mode: String, detail: String)? {
        guard isFixedLinkConnection(connection) else {
            return nil
        }
        let mode = nonEmpty(connection.transferMode).map(transferModeText) ?? "Transfer"
        return (mode, "\(mode) \(connection.requiredTransferMinutes)m")
    }

    private static func isFixedLinkConnection(_ connection: ItineraryConnection) -> Bool {
        nonEmpty(connection.transferSource)?.lowercased() == "fixed_links" ||
            nonEmpty(connection.transferMode) != nil
    }

    private static func lowercaseFirst(_ value: String) -> String {
        guard let first = value.first else {
            return value
        }
        return first.lowercased() + value.dropFirst()
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    static func timeText(_ rawValue: String) -> String {
        guard let date = DateFormatting.date(from: rawValue) else {
            return rawValue
        }
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "Europe/London")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    static func durationText(from start: Date, to end: Date) -> String {
        let minutes = max(0, Int(end.timeIntervalSince(start) / 60))
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if hours > 0 && remainingMinutes > 0 {
            return "\(hours)h \(remainingMinutes)m"
        }
        if hours > 0 {
            return "\(hours)h"
        }
        return "\(remainingMinutes)m"
    }

    private static func connectionTransferMinutes(_ connection: ItineraryConnection) -> Int? {
        guard let arrival = DateFormatting.date(from: connection.expectedArrival),
              let departure = DateFormatting.date(from: connection.expectedDeparture) else {
            return nil
        }
        return max(0, Int(departure.timeIntervalSince(arrival) / 60))
    }
}
