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

    /// Brings the backend's queue in line with the next week of departures:
    /// posts what the routines want, and removes anything queued that they no
    /// longer want. Skipped when the same week was synchronised recently.
    ///
    /// The removal matters as much as the post. The queue outlives the
    /// routines that filled it by up to a week, so a commute deleted, paused
    /// or moved to another time, or a list that came back empty, would
    /// otherwise keep arming windows and sending "your commute is being
    /// watched" for a commute the app no longer shows.
    ///
    /// Failures are swallowed: pre-arming runs behind the user's back, and a
    /// backend that is briefly unreachable is not something to interrupt them
    /// with. The next launch or background refresh tries again.
    func synchronise(routines: [CommuteRoutine], accessToken: String, now: Date = Date()) async {
        guard !isPosting else { return }
        let departures = CommutePreArmPlanner.departures(for: routines, from: now)

        // An empty week has a signature too, so that "nothing wanted" is
        // reconciled once and then left alone, and the first routine added
        // afterwards changes the signature and posts straight away.
        let signature = Self.signature(for: departures)
        if signature == lastPostedSignature,
           let lastPostedAt,
           now.timeIntervalSince(lastPostedAt) < Self.repostInterval {
            return
        }

        isPosting = true
        defer { isPosting = false }

        var succeeded = true
        if !departures.isEmpty {
            do {
                let response = try await apiClient.preArmCommuteDepartures(
                    input: PreArmCommuteDeparturesRequest(departures: departures),
                    accessToken: accessToken
                )
                logger.notice("pre-armed \(response.scheduled.count, privacy: .public) departures, \(response.skipped.count, privacy: .public) skipped")
                if !response.skipped.isEmpty {
                    let reasons = Set(response.skipped.map(\.reason)).sorted().joined(separator: ",")
                    BetaDiagnostics.record("prearm_skipped", details: "count=\(response.skipped.count) reasons=\(reasons)")
                }
            } catch {
                succeeded = false
                logger.error("pre-arm post failed: \(error.localizedDescription, privacy: .public)")
                BetaDiagnostics.record("prearm_failed", details: error.localizedDescription, severity: .warning)
            }
        }

        let reconciled = await removeUnwantedArms(keeping: departures, accessToken: accessToken)
        if !reconciled {
            succeeded = false
        }

        if succeeded {
            lastPostedSignature = signature
            lastPostedAt = now
        }
    }

    /// Deletes queued departures the current routines do not produce. Returns
    /// false when the queue could not be read or a delete failed, so the next
    /// synchronise tries again rather than waiting out the interval.
    ///
    /// Only departures not yet armed are removed. An armed one already has its
    /// window subscription, which deleting the queue row would not stop; that
    /// window is a pin the user can see and cancel like any other.
    private func removeUnwantedArms(keeping departures: [PreArmCommuteDeparture], accessToken: String) async -> Bool {
        let queued: [ScheduledArm]
        do {
            queued = try await apiClient.listScheduledArms(accessToken: accessToken)
        } catch {
            logger.error("pre-arm list failed: \(error.localizedDescription, privacy: .public)")
            BetaDiagnostics.record("prearm_list_failed", details: error.localizedDescription, severity: .warning)
            return false
        }

        let wanted = Set(departures.map {
            Self.queueKey(origin: $0.originCrs, destination: $0.destinationCrs, departureStart: $0.departureStart, windowMinutes: $0.windowMinutes)
        })
        let unwanted = queued.filter { arm in
            arm.armedAt == nil && !wanted.contains(
                Self.queueKey(origin: arm.originCrs, destination: arm.destinationCrs, departureStart: arm.departureStart, windowMinutes: arm.windowMinutes)
            )
        }
        guard !unwanted.isEmpty else { return true }

        var removed = 0
        for arm in unwanted {
            do {
                try await apiClient.deleteScheduledArm(id: arm.id, accessToken: accessToken)
                removed += 1
            } catch APIError.server(let statusCode, _, _, _) where statusCode == 404 {
                // Already gone, armed and pruned, or removed by another device.
                removed += 1
            } catch {
                logger.error("pre-arm delete failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        logger.notice("removed \(removed, privacy: .public) of \(unwanted.count, privacy: .public) unwanted pre-armed departures")
        BetaDiagnostics.record("prearm_removed", details: "removed=\(removed) unwanted=\(unwanted.count) queued=\(queued.count)")
        return removed == unwanted.count
    }

    /// What identifies one queued departure. The backend truncates the start
    /// to the minute and stores it in UTC, so the comparison does the same.
    static func queueKey(origin: String, destination: String, departureStart: Date, windowMinutes: Int) -> String {
        let minute = Int((departureStart.timeIntervalSince1970 / 60).rounded(.down))
        return "\(origin.uppercased())>\(destination.uppercased())@\(minute)/\(windowMinutes)"
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
