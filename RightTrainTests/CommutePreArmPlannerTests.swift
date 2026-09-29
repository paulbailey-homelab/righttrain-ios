@testable import RightTrain
import XCTest

/// The planner is the part of pre-arming that decides what the backend is told
/// about, so these pin the rules that decide whether a commute gets watched:
/// which days count, how far ahead, and what is too late to bother with.
final class CommutePreArmPlannerTests: XCTestCase {
    private let londonTimeZone = TimeZone(identifier: "Europe/London")!

    private var londonCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = londonTimeZone
        return calendar
    }

    private func date(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: iso)!
    }

    private func routine(
        id: String = "routine-1",
        status: String = "active",
        departureTime: String = "07:42",
        windowMinutes: Int = 120,
        activeWeekdays: [Int] = [1, 2, 3, 4, 5],
        autoArmEnabled: Bool = true,
        autoArmLeadMinutes: Int = 30,
        notificationsEnabled: Bool = true
    ) -> CommuteRoutine {
        CommuteRoutine(
            id: id,
            userId: "user-1",
            name: "Morning",
            status: status,
            originCrs: "HDW",
            destinationCrs: "KGX",
            departureTime: departureTime,
            windowMinutes: windowMinutes,
            activeWeekdays: activeWeekdays,
            autoArmEnabled: autoArmEnabled,
            autoArmLeadMinutes: autoArmLeadMinutes,
            notificationsEnabled: notificationsEnabled,
            createdAt: date("2026-09-01T00:00:00Z"),
            updatedAt: date("2026-09-01T00:00:00Z"),
            deletedAt: nil
        )
    }

    func testAWeekdayRoutineCoversOnlyItsWeekdaysWithinTheHorizon() {
        // Monday 28 September 2026, before the departure.
        let now = date("2026-09-28T05:00:00Z")
        let departures = CommutePreArmPlanner.departures(for: [routine()], from: now)

        // The horizon runs Monday to Sunday, so the weekend is not in it and
        // neither is the following Monday: five departures.
        XCTAssertEqual(departures.count, 5)

        let weekdays = departures.map {
            CommutePreArmPlanner.isoWeekday(of: $0.departureStart, calendar: londonCalendar)
        }
        XCTAssertEqual(weekdays, [1, 2, 3, 4, 5])

        for departure in departures {
            let components = londonCalendar.dateComponents([.hour, .minute], from: departure.departureStart)
            XCTAssertEqual(components.hour, 7)
            XCTAssertEqual(components.minute, 42)
        }
    }

    func testDeparturesCarryTheRoutinesOwnWindowAndLead() throws {
        let now = date("2026-09-28T05:00:00Z")
        let departures = CommutePreArmPlanner.departures(
            for: [routine(windowMinutes: 90, autoArmLeadMinutes: 45, notificationsEnabled: false)],
            from: now
        )

        let first = try XCTUnwrap(departures.first)
        XCTAssertEqual(first.originCrs, "HDW")
        XCTAssertEqual(first.destinationCrs, "KGX")
        XCTAssertEqual(first.windowMinutes, 90)
        XCTAssertEqual(first.armLeadMinutes, 45)
        XCTAssertFalse(first.notificationsEnabled)
    }

    /// The whole point of pre-arming is that it can be re-posted on every
    /// launch. A departure whose window has closed would only come back as a
    /// skip, so today's is dropped once it is over but tomorrow's is not.
    func testTodaysDepartureIsDroppedOnlyOnceItsWindowHasClosed() throws {
        let routine = routine(windowMinutes: 120)

        let duringWindow = date("2026-09-28T07:30:00Z")
        let stillIncluded = CommutePreArmPlanner.departures(for: [routine], from: duringWindow)
        XCTAssertEqual(
            londonCalendar.component(.day, from: try XCTUnwrap(stillIncluded.first).departureStart),
            28
        )

        let afterWindow = date("2026-09-28T09:00:00Z")
        let dropped = CommutePreArmPlanner.departures(for: [routine], from: afterWindow)
        XCTAssertEqual(
            londonCalendar.component(.day, from: try XCTUnwrap(dropped.first).departureStart),
            29
        )
    }

    func testPausedAndManualRoutinesAreNotPreArmed() {
        let now = date("2026-09-28T05:00:00Z")
        XCTAssertTrue(CommutePreArmPlanner.departures(for: [routine(status: "paused")], from: now).isEmpty)
        XCTAssertTrue(CommutePreArmPlanner.departures(for: [routine(autoArmEnabled: false)], from: now).isEmpty)
        XCTAssertTrue(CommutePreArmPlanner.departures(for: [routine(activeWeekdays: [])], from: now).isEmpty)
    }

    /// A railway clock time is resolved in the railway's own zone, so the same
    /// routine pre-arms the same train whatever the phone's zone is. Without
    /// this a tester in another country would silently queue the wrong train.
    func testDeparturesUseRailwayTimeRatherThanTheDevicesZone() {
        let now = date("2026-09-28T05:00:00Z")
        let departures = CommutePreArmPlanner.departures(
            for: [routine()],
            from: now,
            timeZone: londonTimeZone
        )

        // 28 September is British Summer Time, so 07:42 local is 06:42 UTC.
        XCTAssertEqual(departures.first?.departureStart, date("2026-09-28T06:42:00Z"))
    }

    /// The clocks go back on Sunday 25 October 2026. The week either side of
    /// it must still resolve 07:42 as 07:42 in London rather than sliding by
    /// an hour.
    func testDeparturesHoldTheirClockTimeAcrossTheClocksGoingBack() {
        // Thursday 22 October 2026, in BST; the horizon reaches past the change.
        let now = date("2026-10-22T04:00:00Z")
        let departures = CommutePreArmPlanner.departures(for: [routine()], from: now)

        for departure in departures {
            let components = londonCalendar.dateComponents([.hour, .minute], from: departure.departureStart)
            XCTAssertEqual(components.hour, 7, "07:42 must stay 07:42 in London across the change")
            XCTAssertEqual(components.minute, 42)
        }

        // Before the change 07:42 London is 06:42 UTC; after it, 07:42 UTC.
        XCTAssertEqual(departures.first?.departureStart, date("2026-10-22T06:42:00Z"))
        XCTAssertEqual(departures.last?.departureStart, date("2026-10-28T07:42:00Z"))
    }

    /// The backend takes a bounded post, and soonest-first ordering decides
    /// what survives the cut: the far end of the week, not tomorrow morning.
    func testOversizedPlansKeepTheSoonestDepartures() throws {
        let routines = (0..<12).map {
            routine(id: "routine-\($0)", departureTime: String(format: "%02d:00", $0 + 6), activeWeekdays: [1, 2, 3, 4, 5, 6, 7])
        }
        let now = date("2026-09-28T00:00:00Z")
        let departures = CommutePreArmPlanner.departures(for: routines, from: now)

        XCTAssertEqual(departures.count, CommutePreArmPlanner.maximumDepartures)
        XCTAssertEqual(departures, departures.sorted { $0.departureStart < $1.departureStart })
        XCTAssertEqual(
            londonCalendar.component(.day, from: try XCTUnwrap(departures.first).departureStart),
            28
        )
    }

    func testAMalformedDepartureTimeIsSkippedRatherThanGuessedAt() {
        let now = date("2026-09-28T05:00:00Z")
        XCTAssertTrue(CommutePreArmPlanner.departures(for: [routine(departureTime: "not a time")], from: now).isEmpty)
        XCTAssertTrue(CommutePreArmPlanner.departures(for: [routine(departureTime: "27:99")], from: now).isEmpty)
        XCTAssertEqual(CommutePreArmPlanner.parseDepartureTime("07:42")?.hour, 7)
        XCTAssertEqual(CommutePreArmPlanner.parseDepartureTime("07:42:00")?.minute, 42)
    }
}
