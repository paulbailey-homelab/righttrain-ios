import Foundation
import os

/// Turns commute routines into the concrete departures the backend queues.
///
/// This exists because the routines themselves no longer live on the server.
/// The server can no longer work out that you catch the 07:42 on weekdays, so
/// the app works it out and posts the next week of departures instead. Nothing
/// is monitored by posting: each queued departure becomes a window
/// subscription later, when its lead time arrives.
enum CommutePreArmPlanner {
    /// How far ahead the app queues. Long enough that a phone left in a drawer
    /// over a weekend still has Monday covered, short enough that the backend
    /// is never holding much.
    static let horizonDays = 7

    /// The backend takes at most this many departures in one post.
    static let maximumDepartures = 64

    /// Departure times on a routine are railway clock times, so they are
    /// resolved in the timetable's own zone rather than the device's. A phone
    /// in another time zone still pre-arms the 07:42 from Hadley Wood.
    static var railwayTimeZone: TimeZone {
        TimeZone(identifier: "Europe/London") ?? .current
    }

    static func departures(
        for routines: [CommuteRoutine],
        from now: Date,
        horizonDays: Int = horizonDays,
        timeZone: TimeZone = railwayTimeZone
    ) -> [PreArmCommuteDeparture] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let today = calendar.startOfDay(for: now)
        var departures: [PreArmCommuteDeparture] = []

        for routine in routines where isPreArmable(routine) {
            guard let clock = parseDepartureTime(routine.departureTime) else { continue }
            for dayOffset in 0..<horizonDays {
                guard let serviceDate = calendar.date(byAdding: .day, value: dayOffset, to: today),
                      routine.activeWeekdays.contains(isoWeekday(of: serviceDate, calendar: calendar)) else {
                    continue
                }
                var components = calendar.dateComponents([.year, .month, .day], from: serviceDate)
                components.hour = clock.hour
                components.minute = clock.minute
                // A clock time that does not exist on this date — the hour the
                // clocks go forward — is skipped rather than guessed at.
                guard let departureStart = calendar.date(from: components) else { continue }
                // A window that has already closed would only come back as a
                // skip, so it is not worth posting.
                let windowEnd = departureStart.addingTimeInterval(TimeInterval(routine.windowMinutes * 60))
                guard windowEnd > now else { continue }
                departures.append(
                    PreArmCommuteDeparture(
                        originCrs: routine.originCrs,
                        destinationCrs: routine.destinationCrs,
                        departureStart: departureStart,
                        windowMinutes: routine.windowMinutes,
                        armLeadMinutes: routine.autoArmLeadMinutes,
                        notificationsEnabled: routine.notificationsEnabled
                    )
                )
            }
        }

        // Soonest first, so that if a user has more routines than the post
        // allows, what gets dropped is the far end of the week rather than
        // tomorrow morning.
        return Array(departures.sorted { $0.departureStart < $1.departureStart }.prefix(maximumDepartures))
    }

    static func isPreArmable(_ routine: CommuteRoutine) -> Bool {
        routine.status == "active" && routine.autoArmEnabled && !routine.activeWeekdays.isEmpty
    }

    static func parseDepartureTime(_ value: String) -> (hour: Int, minute: Int)? {
        let parts = value.split(separator: ":")
        guard parts.count >= 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]),
              (0...23).contains(hour),
              (0...59).contains(minute) else {
            return nil
        }
        return (hour, minute)
    }

    /// ISO weekday, 1 for Monday through 7 for Sunday, which is what a routine
    /// stores and what the backend validates against.
    static func isoWeekday(of date: Date, calendar: Calendar) -> Int {
        let weekday = calendar.component(.weekday, from: date)
        return weekday == 1 ? 7 : weekday - 1
    }
}

/// Keeps the backend's queue in step with the routines the app holds.
@MainActor
final class CommutePreArmScheduler {
    /// How long a posted window stays good without being re-posted. The post
    /// is idempotent, so re-posting costs little, but doing it on every
    /// foreground would be noise.
    static let repostInterval: TimeInterval = 6 * 60 * 60

    private let apiClient: any APIClienting
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.righttrain.ios", category: "prearm")

    private var lastPostedSignature: String?
    private var lastPostedAt: Date?
    private var isPosting = false

    init(apiClient: any APIClienting) {
        self.apiClient = apiClient
    }

    /// Posts the next week of departures, unless the same week has already
    /// been posted recently.
    ///
    /// Failures are swallowed: pre-arming runs behind the user's back, and a
    /// backend that is briefly unreachable is not something to interrupt them
    /// with. The next launch or background refresh tries again.
    func synchronise(routines: [CommuteRoutine], accessToken: String, now: Date = Date()) async {
        guard !isPosting else { return }
        let departures = CommutePreArmPlanner.departures(for: routines, from: now)
        guard !departures.isEmpty else {
            // Nothing to arm is a real state — every routine paused, or none
            // yet — and clearing the signature means the next routine added
            // posts immediately rather than waiting out the interval.
            lastPostedSignature = nil
            return
        }

        let signature = Self.signature(for: departures)
        if signature == lastPostedSignature,
           let lastPostedAt,
           now.timeIntervalSince(lastPostedAt) < Self.repostInterval {
            return
        }

        isPosting = true
        defer { isPosting = false }
        do {
            let response = try await apiClient.preArmCommuteDepartures(
                input: PreArmCommuteDeparturesRequest(departures: departures),
                accessToken: accessToken
            )
            lastPostedSignature = signature
            lastPostedAt = now
            logger.notice("pre-armed \(response.scheduled.count, privacy: .public) departures, \(response.skipped.count, privacy: .public) skipped")
            if !response.skipped.isEmpty {
                let reasons = Set(response.skipped.map(\.reason)).sorted().joined(separator: ",")
                BetaDiagnostics.record("prearm_skipped", details: "count=\(response.skipped.count) reasons=\(reasons)")
            }
        } catch {
            logger.error("pre-arm post failed: \(error.localizedDescription, privacy: .public)")
            BetaDiagnostics.record("prearm_failed", details: error.localizedDescription, severity: .warning)
        }
    }

    func clearState() {
        lastPostedSignature = nil
        lastPostedAt = nil
    }

    static func signature(for departures: [PreArmCommuteDeparture]) -> String {
        departures
            .map { "\($0.originCrs)>\($0.destinationCrs)@\(Int($0.departureStart.timeIntervalSince1970))/\($0.windowMinutes)/\($0.armLeadMinutes)/\($0.notificationsEnabled ? 1 : 0)" }
            .joined(separator: "|")
    }
}
