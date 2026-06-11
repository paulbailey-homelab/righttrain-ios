import Foundation
import UserNotifications

/// Local interchange alert posted when iOS detects the user
/// has entered the interchange-station geofence during an active
/// multi-leg journey. Stays out of the APNs path so it doesn't need
/// server-side routing.
enum LocalInterchangeNotification {
    static let categoryIdentifier = "RT_INTERCHANGE"

    /// Posts (or replaces) a local notification for the given interchange.
    /// The request identifier is keyed by itinerary + leg so successive
    /// interchanges on the same journey replace each other rather than
    /// stacking. Errors are recorded to `BetaDiagnostics` and otherwise
    /// swallowed: the in-app banner and haptic remain the primary signal.
    static func schedule(
        itineraryID: String,
        legIndex: Int,
        stationName: String,
        title: String? = nil,
        onwardPlatform: String?,
        onwardDeparture: String?
    ) {
        let content = UNMutableNotificationContent()
        content.title = title ?? "Change at \(stationName)"
        content.body = bodyText(onwardPlatform: onwardPlatform, onwardDeparture: onwardDeparture)
        content.sound = .default
        content.categoryIdentifier = categoryIdentifier
        content.userInfo = [
            "kind": "itinerary_interchange",
            "itinerarySubscriptionId": itineraryID,
            "legIndex": legIndex
        ]

        let identifier = "righttrain.itinerary.interchange.\(itineraryID).\(legIndex)"
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                BetaDiagnostics.record(
                    "itinerary_interchange_notification_failed",
                    details: error.localizedDescription
                )
            }
        }
    }

    static func bodyText(onwardPlatform: String?, onwardDeparture: String?) -> String {
        let platform = onwardPlatform?.trimmingCharacters(in: .whitespacesAndNewlines)
        let departure = onwardDeparture?.trimmingCharacters(in: .whitespacesAndNewlines)
        switch (platform, departure) {
        case let (p?, t?) where !p.isEmpty && !t.isEmpty:
            return "Action needed: use platform \(p) for the \(t) onward train."
        case let (p?, _) where !p.isEmpty:
            return "Action needed: use platform \(p) for your onward train."
        case let (_, t?) where !t.isEmpty:
            return "Action needed: onward train departs \(t)."
        default:
            return "Action needed: get ready to change trains."
        }
    }
}
