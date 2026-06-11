@testable import RightTrain
import XCTest

final class JourneyFormattingTests: XCTestCase {
    func testChronologicalRecommendationsIncludesTopRecommendationInDepartureOrder() {
        let earliest = TestFactory.recommendation(
            rank: 2,
            serviceID: 202,
            journey: TestFactory.journey(
                serviceID: 202,
                scheduledDeparture: "2026-01-10T10:05:00.000Z",
                scheduledArrival: "2026-01-10T10:45:00.000Z"
            )
        )
        let recommended = TestFactory.recommendation(
            rank: 1,
            serviceID: 101,
            journey: TestFactory.journey(
                serviceID: 101,
                scheduledDeparture: "2026-01-10T10:20:00.000Z",
                scheduledArrival: "2026-01-10T11:00:00.000Z"
            )
        )
        let latest = TestFactory.recommendation(
            rank: 3,
            serviceID: 303,
            journey: TestFactory.journey(
                serviceID: 303,
                scheduledDeparture: "2026-01-10T10:35:00.000Z",
                scheduledArrival: "2026-01-10T11:15:00.000Z"
            )
        )

        let recommendations = JourneyFormatting.chronologicalRecommendations(
            topRecommendation: recommended,
            recommendations: [latest, earliest]
        )

        XCTAssertEqual(recommendations.map(\.journey.serviceId), [202, 101, 303])
    }

    func testStationSuggestionStoresSixteenCharacterNameFromFeed() throws {
        let data = try XCTUnwrap("""
        {
            "crs": "MAN",
            "name": "Manchester Piccadilly",
            "sixteenCharacterName": "Man Piccadilly",
            "tpl": "mancr",
            "toc": null
        }
        """.data(using: .utf8))

        let station = try JSONCoding.decoder.decode(StationSuggestion.self, from: data)

        XCTAssertEqual(station.displayName, "Manchester Piccadilly")
        XCTAssertEqual(station.compactDisplayName, "Man Piccadilly")
    }

    func testItineraryConnectionDecodesOptionalFixedLinkMetadata() throws {
        let data = try XCTUnwrap("""
        {
            "fromLegIndex": 0,
            "toLegIndex": 1,
            "atTpl": "STFD",
            "atCrs": "SRA",
            "atName": "Stratford (London)",
            "scheduledArrival": "2026-05-18T09:30:00.000Z",
            "scheduledDeparture": "2026-05-18T09:55:00.000Z",
            "expectedArrival": "2026-05-18T09:30:00.000Z",
            "expectedDeparture": "2026-05-18T09:55:00.000Z",
            "requiredTransferMinutes": 22,
            "scheduledMarginMinutes": 3,
            "expectedMarginMinutes": 3,
            "risk": { "status": "tight" },
            "transferSource": "fixed_links",
            "transferMode": "TUBE",
            "transferAdvice": "Use the signed route.",
            "transferLinesOfRoute": ["Jubilee", "DLR"]
        }
        """.data(using: .utf8))

        let connection = try JSONCoding.decoder.decode(ItineraryConnection.self, from: data)

        XCTAssertEqual(connection.transferSource, "fixed_links")
        XCTAssertEqual(connection.transferMode, "TUBE")
        XCTAssertEqual(connection.transferAdvice, "Use the signed route.")
        XCTAssertEqual(connection.transferLinesOfRoute, ["Jubilee", "DLR"])
        XCTAssertEqual(ItineraryFormatting.connectionTitleText(connection), "Tube journey at Stratford (London)")
        XCTAssertEqual(ItineraryFormatting.connectionDetailText(connection), "Tube 22m · 3 min to change")
        XCTAssertEqual(ItineraryFormatting.connectionText(connection), "Tube journey at Stratford (London) · Tube 22m · 3 min to change")
        XCTAssertEqual(ItineraryFormatting.connectionAdviceText(connection), "Jubilee, DLR · Use the signed route.")
    }

    func testFixedLinkWalkFormattingDoesNotDescribeAChange() {
        let connection = TestFactory.itineraryConnection(
            atName: "Warrington Bank Quay",
            requiredTransferMinutes: 12,
            expectedMarginMinutes: 4,
            transferSource: "fixed_links",
            transferMode: "WALK"
        )

        XCTAssertEqual(ItineraryFormatting.connectionTitleText(connection), "Walk at Warrington Bank Quay")
        XCTAssertEqual(ItineraryFormatting.connectionText(connection), "Walk at Warrington Bank Quay · Walk 12m · 4 min to change")
    }

    func testFixedLinkTransferSummaryDoesNotDescribeAChangeOnActiveCard() {
        let firstLeg = TestFactory.itineraryLeg(
            legIndex: 0,
            journey: TestFactory.journey(
                serviceID: 201,
                scheduledDeparture: "2026-05-21T09:00:00.000Z",
                scheduledArrival: "2026-05-21T09:30:00.000Z",
                originName: "London Euston",
                destinationName: "Stratford (London)",
                originTpl: "EUSTON",
                originCrs: "EUS",
                destinationTpl: "STFD",
                destinationCrs: "SRA"
            )
        )
        let onwardLeg = TestFactory.itineraryLeg(
            legIndex: 1,
            journey: TestFactory.journey(
                serviceID: 202,
                scheduledDeparture: "2026-05-21T09:55:00.000Z",
                scheduledArrival: "2026-05-21T10:20:00.000Z",
                originName: "Stratford (London)",
                destinationName: "Shenfield",
                originTpl: "STFD",
                originCrs: "SRA",
                destinationTpl: "SHENFLD",
                destinationCrs: "SNF"
            )
        )
        let connection = TestFactory.itineraryConnection(
            atTpl: "STFD",
            atCrs: "SRA",
            atName: "Stratford (London)",
            scheduledArrival: "2026-05-21T09:30:00.000Z",
            scheduledDeparture: "2026-05-21T09:55:00.000Z",
            expectedArrival: "2026-05-21T09:30:00.000Z",
            expectedDeparture: "2026-05-21T09:55:00.000Z",
            requiredTransferMinutes: 22,
            expectedMarginMinutes: 3,
            transferSource: "fixed_links",
            transferMode: "TUBE"
        )
        let itinerary = TestFactory.itinerary(legs: [firstLeg, onwardLeg], connections: [connection])
        let subscription = TestFactory.itinerarySubscription(
            phase: ItineraryPhase.approachingInterchange.rawValue,
            currentLegIndex: 0,
            selectedItinerary: itinerary,
            itineraries: [itinerary]
        )
        let presentation = ActiveItineraryPresentation(itinerary: subscription)

        XCTAssertEqual(ItineraryFormatting.transferMetricLabel(itinerary), "Transfer")
        XCTAssertEqual(ItineraryFormatting.transferMetricText(itinerary), "Tube 22m")
        XCTAssertEqual(presentation.subtitleText, "Leg 1 of 2 · Approaching tube journey at Stratford (London)")
        XCTAssertEqual(presentation.pillText, "Tube")
    }

    func testFixedLinkWithoutModeFallsBackToTransferNotChange() {
        let connection = TestFactory.itineraryConnection(
            atName: "Out of station",
            requiredTransferMinutes: 18,
            expectedMarginMinutes: 5,
            transferSource: "fixed_links"
        )

        XCTAssertEqual(ItineraryFormatting.connectionTitleText(connection), "Transfer at Out of station")
        XCTAssertEqual(ItineraryFormatting.connectionText(connection), "Transfer at Out of station · Transfer 18m · 5 min to change")
    }

    func testItineraryConnectionDecodesWithoutFixedLinkMetadata() throws {
        let data = try XCTUnwrap("""
        {
            "fromLegIndex": 0,
            "toLegIndex": 1,
            "atTpl": "CREWE",
            "atCrs": "CRE",
            "atName": "Crewe",
            "scheduledArrival": "2026-05-18T09:30:00.000Z",
            "scheduledDeparture": "2026-05-18T09:45:00.000Z",
            "expectedArrival": "2026-05-18T09:30:00.000Z",
            "expectedDeparture": "2026-05-18T09:45:00.000Z",
            "requiredTransferMinutes": 8,
            "scheduledMarginMinutes": 7,
            "expectedMarginMinutes": 7,
            "risk": { "status": "ok" }
        }
        """.data(using: .utf8))

        let connection = try JSONCoding.decoder.decode(ItineraryConnection.self, from: data)

        XCTAssertNil(connection.transferSource)
        XCTAssertNil(connection.transferMode)
        XCTAssertNil(connection.transferAdvice)
        XCTAssertNil(connection.transferLinesOfRoute)
        XCTAssertEqual(ItineraryFormatting.connectionText(connection), "Change at Crewe · 15 min change · 7 min to change")
    }

    func testStationNameFormattingUsesFullNamesUntilCompactRequested() {
        let journey = TestFactory.journey(
            originName: "London Euston",
            originSixteenCharacterName: "Euston",
            destinationName: "Manchester Piccadilly",
            destinationSixteenCharacterName: "Man Piccadilly",
            finalDestinationName: "Manchester Piccadilly via Milton Keynes Central",
            finalDestinationSixteenCharacterName: "Man Piccadilly"
        )

        XCTAssertEqual(JourneyFormatting.routeText(journey), "London Euston to Manchester Piccadilly")
        XCTAssertEqual(JourneyFormatting.compactRouteText(journey), "Euston to Man Piccadilly")
        XCTAssertEqual(JourneyFormatting.finalDestinationText(journey), "Manchester Piccadilly via Milton Keynes Central")
        XCTAssertEqual(JourneyFormatting.compactFinalDestinationText(journey), "Man Piccadilly")
    }

    func testGlanceTimingShowsExpectedTimesWhenDelayed() {
        let journey = TestFactory.journey(
            scheduledDeparture: "2026-01-10T10:00:00.000Z",
            scheduledArrival: "2026-01-10T11:00:00.000Z",
            scheduledDepartureRaw: "10:00",
            scheduledArrivalRaw: "11:00",
            expectedDeparture: "10:07",
            expectedArrival: "11:10"
        )

        let departure = JourneyFormatting.departureDisplay(journey)
        let arrival = JourneyFormatting.arrivalDisplay(journey)

        XCTAssertEqual(JourneyFormatting.glanceTimingText(departure: departure, arrival: arrival), "Dep 10:07 · Arr 11:10")
        XCTAssertEqual(JourneyFormatting.scheduledExpectedText(departure, label: "Departure"), "Departure 10:07, scheduled 10:00")
        XCTAssertEqual(JourneyFormatting.scheduledExpectedText(arrival, label: "Arrival"), "Arrival 11:10, scheduled 11:00")
    }

    func testPlatformStateTextIncludesUnknownAndChangedPlatformWithoutColourDependency() {
        XCTAssertEqual(JourneyFormatting.platformStateText(primary: "TBC"), "Platform TBC")
        XCTAssertEqual(JourneyFormatting.platformStateText(primary: "-"), "Platform TBC")
        XCTAssertEqual(JourneyFormatting.platformStateText(primary: "P4"), "Platform 4")
        XCTAssertEqual(JourneyFormatting.platformStateText(primary: "P12", secondary: "was 2"), "Platform 12 · was 2")
    }

    func testFreshnessAndAccessibilityLabelsDescribeLiveConfidence() throws {
        let now = try XCTUnwrap(DateFormatting.date(from: "2026-01-10T10:10:00.000Z"))

        XCTAssertEqual(ActiveWindowPresentation.freshnessText(updatedAt: nil, now: now), "Live data not reported yet")
        XCTAssertEqual(ActiveWindowPresentation.freshnessText(updatedAt: now.addingTimeInterval(-45), now: now), "Updated now")
        XCTAssertEqual(ActiveWindowPresentation.freshnessText(updatedAt: now.addingTimeInterval(-90), now: now), "Updated 1 min ago")
        XCTAssertEqual(ActiveWindowPresentation.freshnessText(updatedAt: now.addingTimeInterval(-6 * 60), now: now), "Live data stale")
        XCTAssertEqual(
            JourneyFormatting.accessibilityStatusLabel(
                statusText: "Platform changed",
                platformText: "Platform 12 · was 2",
                freshnessText: "Updated now"
            ),
            "Platform changed, Platform 12 · was 2, Updated now"
        )
    }

    func testNextActionTextCoversActionNeededAndUnavailableStates() {
        let cancelled = TestFactory.journey(cancelled: true)
        let active = TestFactory.journey(originPlatform: "4", realtimePlatform: "4")

        XCTAssertEqual(
            JourneyFormatting.nextActionText(for: cancelled, platform: "4", moment: .disrupted),
            "Choose another train"
        )
        XCTAssertEqual(
            JourneyFormatting.nextActionText(for: active, platform: "TBC", moment: .approachingDeparture),
            "Watch for the platform"
        )
        XCTAssertEqual(
            JourneyFormatting.nextActionText(for: active, platform: "4", moment: .approachingDeparture),
            "Go to platform 4"
        )
        XCTAssertEqual(
            JourneyFormatting.nextActionText(for: active, platform: "4", moment: .offline),
            "Check again when connection returns"
        )
        XCTAssertEqual(
            JourneyFormatting.nextActionText(for: active, platform: "4", moment: .staleData),
            "Refresh before acting"
        )
    }

    func testLiveActivityStateCarriesFullAndCompactStationNames() {
        let journey = TestFactory.journey(
            originName: "London Euston",
            originSixteenCharacterName: "Euston",
            destinationName: "Manchester Piccadilly",
            destinationSixteenCharacterName: "Man Piccadilly",
            finalDestinationName: "Manchester Piccadilly via Milton Keynes Central",
            finalDestinationSixteenCharacterName: "Man Piccadilly"
        )
        let recommendation = TestFactory.recommendation(journey: journey)
        let window = TestFactory.window(selectedRecommendation: recommendation)

        let state = RightTrainLiveActivityStateBuilder.state(
            for: window,
            pinnedTrainServiceID: nil,
            now: Date(timeIntervalSince1970: 1_800_000_000)
        )

        XCTAssertEqual(state.routeTitle, "London Euston to Manchester Piccadilly")
        XCTAssertEqual(state.originName, "London Euston")
        XCTAssertEqual(state.originShortName, "Euston")
        XCTAssertEqual(state.destinationName, "Manchester Piccadilly")
        XCTAssertEqual(state.destinationShortName, "Man Piccadilly")
        XCTAssertEqual(state.trains.first?.destinationName, "Manchester Piccadilly")
        XCTAssertEqual(state.trains.first?.destinationShortName, "Man Piccadilly")
        XCTAssertEqual(state.trains.first?.serviceDestinationName, "Manchester Piccadilly via Milton Keynes Central")
        XCTAssertEqual(state.trains.first?.serviceDestinationShortName, "Man Piccadilly")
    }

    func testCrsRouteTextKeepsRailIdentifiersVisible() {
        let journey = TestFactory.journey(
            originCrs: "eus",
            destinationCrs: "man"
        )

        XCTAssertEqual(JourneyFormatting.crsRouteText(journey), "EUS to MAN")
        XCTAssertEqual(
            JourneyFormatting.crsRouteText(originCrs: "cre", destinationCrs: "man"),
            "CRE to MAN"
        )
    }

    func testRailDateAdjustsForwardAcrossMidnightWithinTwelveHours() throws {
        let anchor = try XCTUnwrap(DateFormatting.date(from: "2026-01-10T23:55:00.000Z"))
        let date = try XCTUnwrap(JourneyFormatting.railDate(from: "00:03", near: anchor))

        XCTAssertEqual(date, DateFormatting.date(from: "2026-01-11T00:03:00.000Z"))
    }

    func testRailDateAdjustsBackwardAcrossMidnightWithinTwelveHours() throws {
        let anchor = try XCTUnwrap(DateFormatting.date(from: "2026-01-10T00:05:00.000Z"))
        let date = try XCTUnwrap(JourneyFormatting.railDate(from: "23:58", near: anchor))

        XCTAssertEqual(date, DateFormatting.date(from: "2026-01-09T23:58:00.000Z"))
    }

    func testDeparturePhaseComesFromBackendMovementPhaseNotRawActualDeparture() {
        let rawActualOnly = TestFactory.journey(
            scheduledDeparture: "2026-01-10T23:55:00.000Z",
            scheduledArrival: "2026-01-11T00:35:00.000Z",
            originRealtime: TestFactory.realtime(actualDeparture: "00:03")
        )

        XCTAssertFalse(JourneyFormatting.isDeparted(rawActualOnly))
        XCTAssertEqual(JourneyFormatting.movementStatusText(rawActualOnly), "On time")

        let backendDeparted = TestFactory.journey(
            scheduledDeparture: "2026-01-10T23:55:00.000Z",
            scheduledArrival: "2026-01-11T00:35:00.000Z",
            statusText: "Departed",
            compactStatusText: "Departed",
            statusKind: "departed",
            movementPhase: "departed",
            reportState: "origin_reported",
            originRealtime: TestFactory.realtime(actualDeparture: "00:03")
        )

        XCTAssertTrue(JourneyFormatting.isDeparted(backendDeparted))
        XCTAssertEqual(JourneyFormatting.movementStatusText(backendDeparted), "Departed")
        XCTAssertEqual(JourneyFormatting.compactMovementStatusText(backendDeparted), "Departed")

        let cancelled = TestFactory.journey(
            scheduledDeparture: "2026-01-10T23:55:00.000Z",
            scheduledArrival: "2026-01-11T00:35:00.000Z",
            cancelled: true,
            originRealtime: TestFactory.realtime(actualDeparture: "00:03")
        )
        XCTAssertTrue(JourneyFormatting.isCancelled(cancelled))
        XCTAssertFalse(JourneyFormatting.isDeparted(cancelled))
    }

    func testPastDepartureDoesNotBecomeUnreportedWithoutBackendStatus() throws {
        let journey = TestFactory.journey(
            scheduledDeparture: "2026-01-10T10:00:00.000Z",
            scheduledArrival: "2026-01-10T10:45:00.000Z"
        )
        let recommendation = TestFactory.recommendation(journey: journey)

        XCTAssertEqual(JourneyFormatting.displayStatus(journey), "on_time")
        XCTAssertEqual(JourneyFormatting.movementStatusText(journey), "On time")

        let countdown = ActiveWindowPresentation.countdown(
            for: recommendation,
            now: try XCTUnwrap(DateFormatting.date(from: "2026-01-10T10:10:00.000Z"))
        )
        XCTAssertEqual(countdown.text, "Awaiting departure")
        XCTAssertEqual(countdown.tone, .accent)
        XCTAssertFalse(countdown.isDeparted)
    }

    func testStatusDelayMinutesUsesBackendDelayAndScoreOnly() {
        let journey = TestFactory.journey(
            scheduledDeparture: "2026-01-10T10:00:00.000Z",
            scheduledArrival: "2026-01-10T11:00:00.000Z",
            delayMinutes: 8,
            originRealtime: TestFactory.realtime(expectedDeparture: "10:08"),
            destinationRealtime: TestFactory.realtime(expectedArrival: "11:15")
        )

        XCTAssertEqual(JourneyFormatting.statusDelayMinutes(
            journey: journey,
            score: TestFactory.score(delayMinutes: 3)
        ), 8)
        XCTAssertEqual(JourneyFormatting.statusDelayMinutes(
            journey: journey,
            score: TestFactory.score(delayMinutes: 12)
        ), 12)
    }

    func testEarlyRealtimeValuesDisplayAsScheduledTimes() throws {
        let journey = TestFactory.journey(
            scheduledDeparture: "2026-01-10T10:00:00.000Z",
            scheduledArrival: "2026-01-10T11:00:00.000Z",
            expectedDeparture: "09:58",
            expectedArrival: "10:55",
            originRealtime: TestFactory.realtime(actualDeparture: "09:59"),
            destinationRealtime: TestFactory.realtime(expectedArrival: "10:56")
        )

        let departure = JourneyFormatting.departureDisplay(journey)
        let arrival = JourneyFormatting.arrivalDisplay(journey)

        XCTAssertEqual(JourneyFormatting.departureText(journey), "10:00")
        XCTAssertEqual(JourneyFormatting.arrivalText(journey), "11:00")
        XCTAssertNil(departure.currentText)
        XCTAssertNil(arrival.currentText)
        XCTAssertFalse(departure.isDelayed)
        XCTAssertFalse(arrival.isDelayed)
        XCTAssertEqual(JourneyFormatting.durationText(journey), "Scheduled 1h")
        XCTAssertFalse(JourneyFormatting.isDeparted(journey))
    }

    func testJourneyDetailOperatorDisplayPrefersNameThenTOC() {
        var detail = TestFactory.journeyDetail()

        XCTAssertEqual(JourneyFormatting.operatorDisplayText(detail), "Caledonian Sleeper")

        detail.operatorName = " "
        XCTAssertEqual(JourneyFormatting.operatorDisplayText(detail), "CS")

        detail.toc = nil
        XCTAssertEqual(JourneyFormatting.operatorDisplayText(detail), "Not available")
    }

    func testJourneyOperatorDisplayPrefersNameThenTOC() {
        var journey = TestFactory.journey(operatorName: "Caledonian Sleeper")

        XCTAssertEqual(JourneyFormatting.operatorDisplayText(journey), "Caledonian Sleeper")
        XCTAssertEqual(JourneyFormatting.operatorSummaryText(journey), "Caledonian Sleeper")

        journey.operatorName = " "
        XCTAssertEqual(JourneyFormatting.operatorDisplayText(journey), "CS")
        XCTAssertEqual(JourneyFormatting.operatorSummaryText(journey), "CS")

        journey.toc = nil
        XCTAssertEqual(JourneyFormatting.operatorDisplayText(journey), "Not available")
        XCTAssertNil(JourneyFormatting.operatorSummaryText(journey))
    }

    func testJourneyDetailCoachCountTextPluralizesAndHidesUnknown() {
        var detail = TestFactory.journeyDetail()

        XCTAssertEqual(JourneyFormatting.coachCountText(detail), "8 coaches")

        detail.coachCount = 1
        XCTAssertEqual(JourneyFormatting.coachCountText(detail), "1 coach")

        detail.coachCountApproximate = true
        XCTAssertEqual(JourneyFormatting.coachCountText(detail), "1 coach")

        detail.coachCount = 8
        XCTAssertEqual(JourneyFormatting.coachCountText(detail), "8 coaches")

        detail.coachCount = nil
        XCTAssertNil(JourneyFormatting.coachCountText(detail))

        detail.coachCount = 0
        XCTAssertNil(JourneyFormatting.coachCountText(detail))
    }

    func testJourneyDetailTrainPositionAdvancesFromStopTimes() throws {
        var detail = TestFactory.journeyDetail()
        detail.stops[0].realtime = TestFactory.realtime(actualDeparture: "10:00")
        detail.stops[1].realtime = TestFactory.realtime(expectedArrival: "11:00")
        let now = try XCTUnwrap(DateFormatting.date(from: "2026-01-10T10:30:00.000Z"))

        let position = JourneyFormatting.currentTrainPosition(detail, now: now)

        XCTAssertNil(position.stationIndex)
        XCTAssertEqual(position.betweenAfterIndex, 0)
        XCTAssertEqual(position.progress, 0.5, accuracy: 0.01)
    }

    func testHasDelaySignalUsesBackendPresentationNotRawRealtimeFlags() {
        let rawDelayedOnly = TestFactory.journey(
            originRealtime: TestFactory.realtime(delayed: true),
            destinationRealtime: TestFactory.realtime(delayed: false)
        )

        XCTAssertFalse(JourneyFormatting.hasDelaySignal(journey: rawDelayedOnly, score: TestFactory.score(delayMinutes: 0)))
        XCTAssertTrue(JourneyFormatting.hasDelaySignal(
            journey: TestFactory.journey(statusKind: "delayed"),
            score: TestFactory.score(delayMinutes: 0)
        ))
        XCTAssertTrue(JourneyFormatting.hasDelaySignal(
            journey: TestFactory.journey(delayMinutes: 4),
            score: TestFactory.score(delayMinutes: 0)
        ))
        XCTAssertFalse(JourneyFormatting.hasDelaySignal(journey: TestFactory.journey(), score: TestFactory.score(delayMinutes: 0)))
    }

    func testDisplayStatusUsesBackendEnumWithoutRawRealtimeInference() {
        XCTAssertEqual(
            JourneyFormatting.displayStatus(
                TestFactory.journey(displayStatus: "", destinationRealtime: TestFactory.realtime(actualDeparture: "11:01"))
            ),
            "unknown"
        )
        XCTAssertEqual(
            JourneyFormatting.displayStatus(
                TestFactory.journey(displayStatus: "arrived", destinationRealtime: TestFactory.realtime(actualDeparture: "11:01"))
            ),
            "arrived"
        )
        XCTAssertEqual(
            JourneyFormatting.displayStatus(
                TestFactory.journey(displayStatus: "unreported")
            ),
            "unreported"
        )
        XCTAssertEqual(
            JourneyFormatting.displayStatus(
                TestFactory.journey(displayStatus: "delayed", destinationRealtime: TestFactory.realtime(expectedArrival: "11:08"))
            ),
            "delayed"
        )
    }

    func testDurationTextShowsScheduledAndCurrentDuration() {
        let journey = TestFactory.journey(
            scheduledDeparture: "2026-01-10T10:00:00.000Z",
            scheduledArrival: "2026-01-10T11:00:00.000Z",
            originRealtime: TestFactory.realtime(expectedDeparture: "10:05"),
            destinationRealtime: TestFactory.realtime(expectedArrival: "11:15")
        )

        XCTAssertEqual(JourneyFormatting.durationText(journey), "Scheduled 1h · current 1h 10m")
    }

    func testMovementStatusTextRendersBackendProvidedFields() {
        let rawActualOnly = TestFactory.journey(
            originRealtime: TestFactory.realtime(actualDeparture: "10:00")
        )
        XCTAssertEqual(JourneyFormatting.movementStatusText(rawActualOnly), "On time")
        XCTAssertEqual(JourneyFormatting.compactMovementStatusText(rawActualOnly), "On time")

        let onTime = TestFactory.journey(
            statusText: "Departed",
            compactStatusText: "Departed",
            statusKind: "departed",
            movementPhase: "departed",
            reportState: "origin_reported",
            originRealtime: TestFactory.realtime(actualDeparture: "10:00")
        )
        XCTAssertEqual(JourneyFormatting.movementStatusText(onTime), "Departed")
        XCTAssertEqual(JourneyFormatting.compactMovementStatusText(onTime), "Departed")

        let late = TestFactory.journey(
            statusText: "Departed 5 min late",
            compactStatusText: "Dep +5",
            statusKind: "delayed",
            movementPhase: "departed",
            reportState: "origin_reported",
            delayMinutes: 5,
            originRealtime: TestFactory.realtime(actualDeparture: "10:05")
        )
        XCTAssertEqual(JourneyFormatting.movementStatusText(late), "Departed 5 min late")
        XCTAssertEqual(JourneyFormatting.compactMovementStatusText(late), "Dep +5")
    }

    func testMovementStatusTextKeepsDepartedPhaseWhenReportIsIncomplete() {
        let onTime = TestFactory.journey(
            displayStatus: "unreported",
            statusText: "Departed · report incomplete",
            compactStatusText: "Dep · report",
            statusKind: "unreported",
            movementPhase: "departed",
            reportState: "destination_missing",
            originRealtime: TestFactory.realtime(actualDeparture: "10:00")
        )
        XCTAssertEqual(JourneyFormatting.movementStatusText(onTime), "Departed · report incomplete")
        XCTAssertEqual(JourneyFormatting.compactMovementStatusText(onTime), "Dep · report")

        let late = TestFactory.journey(
            displayStatus: "unreported",
            statusText: "Departed 5 min late · report incomplete",
            compactStatusText: "Dep +5 · report",
            statusKind: "unreported",
            movementPhase: "departed",
            reportState: "destination_missing",
            delayMinutes: 5,
            originRealtime: TestFactory.realtime(actualDeparture: "10:05")
        )
        XCTAssertEqual(JourneyFormatting.movementStatusText(late), "Departed 5 min late · report incomplete")
        XCTAssertEqual(JourneyFormatting.compactMovementStatusText(late), "Dep +5 · report")
    }

    func testActiveWindowPresentationFallsBackToSelectedRecommendation() {
        let selected = TestFactory.recommendation(serviceID: 101)
        let window = TestFactory.window(selectedRecommendation: selected, recommendations: [])

        let presentation = ActiveWindowPresentation(
            window: window,
            now: DateFormatting.date(from: "2026-01-10T09:00:00.000Z")!
        )

        XCTAssertEqual(presentation.recommendations.map(\.journey.serviceId), [101])
        XCTAssertEqual(presentation.routeTitle, "Origin → Destination")
        XCTAssertEqual(presentation.summaryText, "Plan 1/1")
        XCTAssertEqual(presentation.compactSummaryText, "")
    }

    func testActiveWindowPresentationDeduplicatesSelectedRecommendation() {
        let selected = TestFactory.recommendation(serviceID: 101)
        let later = TestFactory.recommendation(
            rank: 2,
            serviceID: 202,
            journey: TestFactory.journey(
                serviceID: 202,
                scheduledDeparture: "2026-01-10T10:20:00.000Z",
                scheduledArrival: "2026-01-10T11:20:00.000Z"
            )
        )
        let window = TestFactory.window(
            selectedRecommendation: selected,
            recommendations: [later, selected]
        )

        let presentation = ActiveWindowPresentation(
            window: window,
            now: DateFormatting.date(from: "2026-01-10T09:00:00.000Z")!
        )

        XCTAssertEqual(presentation.recommendations.map(\.journey.serviceId), [101, 202])
    }

    func testActiveWindowPresentationBuildsBestTrainAndChronologicalDepartures() {
        let now = DateFormatting.date(from: "2026-01-10T10:12:00.000Z")!
        let delayed = TestFactory.recommendation(
            rank: 1,
            serviceID: 202,
            journey: TestFactory.journey(
                serviceID: 202,
                scheduledDeparture: "2026-01-10T10:05:00.000Z",
                scheduledArrival: "2026-01-10T11:05:00.000Z",
                originRealtime: TestFactory.realtime(expectedDeparture: "10:30")
            ),
            score: TestFactory.score(delayMinutes: 6)
        )
        let departed = TestFactory.recommendation(
            rank: 2,
            serviceID: 303,
            journey: TestFactory.journey(
                serviceID: 303,
                scheduledDeparture: "2026-01-10T09:00:00.000Z",
                scheduledArrival: "2026-01-10T10:00:00.000Z",
                statusText: "Departed",
                compactStatusText: "Departed",
                statusKind: "departed",
                movementPhase: "departed",
                reportState: "origin_reported",
                originRealtime: TestFactory.realtime(actualDeparture: "09:02")
            )
        )
        let later = TestFactory.recommendation(
            rank: 3,
            serviceID: 606,
            journey: TestFactory.journey(
                serviceID: 606,
                scheduledDeparture: "2026-01-10T10:20:00.000Z",
                scheduledArrival: "2026-01-10T11:20:00.000Z"
            )
        )
        let window = TestFactory.window(
            selectedRecommendation: delayed,
            recommendations: [later, departed, delayed]
        )

        let presentation = ActiveWindowPresentation(
            window: window,
            now: now
        )

        XCTAssertEqual(presentation.bestRecommendation.journey.serviceId, 202)
        XCTAssertEqual(presentation.compactSummaryText, "10:00 - 12:00 · 3 trains")

        let itemDescriptions = presentation.departureItems.map { item in
            switch item {
            case .nowMarker(let text):
                return text
            case .train(let recommendation):
                return "train-\(recommendation.journey.serviceId)"
            }
        }
        XCTAssertEqual(itemDescriptions, ["train-303", "Now 10:12", "train-606", "train-202"])
    }

    func testActiveWindowCompactStatusDisplay() {
        let now = DateFormatting.date(from: "2026-01-10T09:30:00.000Z")!

        let compactTexts = [
            ActiveWindowPresentation.statusDisplay(for: TestFactory.recommendation(), now: now).text,
            ActiveWindowPresentation.statusDisplay(
                for: TestFactory.recommendation(
                    journey: TestFactory.journey(
                        displayStatus: "delayed",
                        compactStatusText: "+6",
                        statusKind: "delayed",
                        delayMinutes: 6
                    ),
                    score: TestFactory.score(delayMinutes: 6)
                ),
                now: now
            ).text,
            ActiveWindowPresentation.statusDisplay(
                for: TestFactory.recommendation(
                    journey: TestFactory.journey(
                        statusText: "Departed 8 min late",
                        compactStatusText: "Dep +8",
                        statusKind: "delayed",
                        movementPhase: "departed",
                        reportState: "origin_reported",
                        delayMinutes: 8,
                        originRealtime: TestFactory.realtime(actualDeparture: "10:08")
                    )
                ),
                now: DateFormatting.date(from: "2026-01-10T10:09:00.000Z")!
            ).text,
            ActiveWindowPresentation.statusDisplay(
                for: TestFactory.recommendation(journey: TestFactory.journey(cancelled: true)),
                now: now
            ).text,
            ActiveWindowPresentation.statusDisplay(
                for: TestFactory.recommendation(journey: TestFactory.journey(displayStatus: "arrived")),
                now: now
            ).text,
            ActiveWindowPresentation.statusDisplay(
                for: TestFactory.recommendation(journey: TestFactory.journey(displayStatus: "unreported")),
                now: now
            ).text
        ]

        XCTAssertEqual(compactTexts, ["On time", "+6", "Dep +8", "Cancelled", "Arrived", "Unreported"])
        XCTAssertFalse(compactTexts.contains { $0.contains("...") || $0.contains("…") })
    }

    func testActiveWindowCompactStatusShowsDepartedReportIncomplete() {
        let now = DateFormatting.date(from: "2026-01-10T10:05:00.000Z")!
        let status = ActiveWindowPresentation.statusDisplay(
            for: TestFactory.recommendation(
                journey: TestFactory.journey(
                    displayStatus: "unreported",
                    statusText: "Departed · report incomplete",
                    compactStatusText: "Dep · report",
                    statusKind: "unreported",
                    movementPhase: "departed",
                    reportState: "destination_missing",
                    originRealtime: TestFactory.realtime(actualDeparture: "10:00")
                )
            ),
            now: now
        )

        XCTAssertEqual(status.text, "Dep · report")
        XCTAssertEqual(status.tone, .amber)
    }

    func testActiveWindowPlatformDisplaysKeepDepartureAndArrivalSeparate() {
        let journey = TestFactory.journey(
            originPlatform: "1",
            destinationPlatform: "7"
        )

        XCTAssertEqual(ActiveWindowPresentation.platformDisplay(for: journey).primary, "P1")
        XCTAssertEqual(ActiveWindowPresentation.arrivalPlatformDisplay(for: journey).primary, "P7")
    }

    func testActiveWindowArrivalPlatformDisplayPrefersDestinationRealtime() {
        let journey = TestFactory.journey(
            destinationRealtime: TestFactory.realtime(platform: "8"),
            destinationPlatform: "7"
        )

        let platform = ActiveWindowPresentation.arrivalPlatformDisplay(for: journey)

        XCTAssertEqual(platform.primary, "P8")
        XCTAssertEqual(platform.secondary, "was 7")
    }

    func testActiveWindowCompactSummaryOmitsSingleTrainWindowMetadata() {
        let window = TestFactory.window()

        let presentation = ActiveWindowPresentation(
            window: window,
            now: TestFactory.now
        )

        XCTAssertEqual(presentation.summaryText, "Plan 1/1")
        XCTAssertEqual(presentation.compactSummaryText, "")
    }

    func testActiveWindowSummaryFallsBackToDurationWhenWindowStartCannotBeParsed() {
        let window = TestFactory.window(departureStart: "not-a-date")

        let presentation = ActiveWindowPresentation(
            window: window,
            now: TestFactory.now
        )

        XCTAssertEqual(presentation.summaryText, "Plan 1/1")
        XCTAssertEqual(presentation.compactSummaryText, "")
    }

    func testLiveActivityStateIncludesOperatorForVisibleTrain() {
        let recommendation = TestFactory.recommendation(
            journey: TestFactory.journey(operatorName: "Great Northern")
        )
        let window = TestFactory.window(
            selectedRecommendation: recommendation,
            recommendations: [recommendation]
        )

        let state = RightTrainLiveActivityStateBuilder.state(
            for: window,
            pinnedTrainServiceID: nil
        )

        XCTAssertEqual(state.trains.first?.operatorName, "Great Northern")
        XCTAssertEqual(state.trains.first?.operatorCode, "CS")
    }

    func testLiveActivityStateFormatsOtherTrainTimes() {
        let selected = TestFactory.recommendation(
            rank: 1,
            serviceID: 101,
            journey: TestFactory.journey(
                serviceID: 101,
                scheduledDeparture: "2026-01-10T10:00:00.000Z",
                scheduledDepartureRaw: "10:00"
            )
        )
        let firstOther = TestFactory.recommendation(
            rank: 2,
            serviceID: 202,
            journey: TestFactory.journey(
                serviceID: 202,
                scheduledDeparture: "2026-01-10T10:30:00.000Z",
                scheduledDepartureRaw: "10:30"
            )
        )
        let secondOther = TestFactory.recommendation(
            rank: 3,
            serviceID: 303,
            journey: TestFactory.journey(
                serviceID: 303,
                scheduledDeparture: "2026-01-10T10:45:00.000Z",
                scheduledDepartureRaw: "10:45"
            )
        )
        let window = TestFactory.window(
            selectedRecommendation: selected,
            recommendations: [selected, secondOther, firstOther]
        )

        let state = RightTrainLiveActivityStateBuilder.state(
            for: window,
            pinnedTrainServiceID: nil
        )

        XCTAssertEqual(state.otherDeparturesText, "Other trains: 10:30, 10:45")
    }

    func testLiveActivityStateKeepsOnJourneyStatusAfterDeparture() throws {
        let now = try XCTUnwrap(DateFormatting.date(from: "2026-01-10T10:30:00.000Z"))
        let recommendation = TestFactory.recommendation(
            journey: TestFactory.journey(
                scheduledDeparture: "2026-01-10T10:00:00.000Z",
                scheduledArrival: "2026-01-10T11:00:00.000Z",
                statusText: "Departed",
                compactStatusText: "Departed",
                statusKind: "departed",
                movementPhase: "departed",
                reportState: "origin_reported",
                originRealtime: TestFactory.realtime(actualDeparture: "10:00")
            )
        )
        let window = TestFactory.window(
            selectedRecommendation: recommendation,
            recommendations: [recommendation],
            pinnedTrainServiceId: 101
        )

        let state = RightTrainLiveActivityStateBuilder.state(
            for: window,
            pinnedTrainServiceID: 101,
            activityKind: .train,
            now: now
        )
        let train = try XCTUnwrap(state.trains.first)

        XCTAssertEqual(train.statusKind, .departed)
        XCTAssertEqual(train.statusText, "Departed")
        XCTAssertTrue(train.departed)
        XCTAssertEqual(try XCTUnwrap(train.journeyProgress), 0.5, accuracy: 0.001)
    }

    func testLiveActivityStateShowsDelayedAfterLateDeparture() throws {
        let now = try XCTUnwrap(DateFormatting.date(from: "2026-01-10T10:30:00.000Z"))
        let recommendation = TestFactory.recommendation(
            journey: TestFactory.journey(
                scheduledDeparture: "2026-01-10T10:00:00.000Z",
                scheduledArrival: "2026-01-10T11:00:00.000Z",
                statusText: "Departed 5 min late",
                compactStatusText: "Dep +5",
                statusKind: "delayed",
                movementPhase: "departed",
                reportState: "origin_reported",
                delayMinutes: 5,
                originRealtime: TestFactory.realtime(actualDeparture: "10:05")
            )
        )
        let window = TestFactory.window(
            selectedRecommendation: recommendation,
            recommendations: [recommendation],
            pinnedTrainServiceId: 101
        )

        let state = RightTrainLiveActivityStateBuilder.state(
            for: window,
            pinnedTrainServiceID: 101,
            activityKind: .train,
            now: now
        )
        let train = try XCTUnwrap(state.trains.first)

        XCTAssertEqual(train.statusKind, .delayed)
        XCTAssertEqual(train.statusText, "Dep +5")
        XCTAssertTrue(train.departed)
        XCTAssertEqual(try XCTUnwrap(train.journeyProgress), 25.0 / 55.0, accuracy: 0.001)
    }

    func testLiveActivityStateShowsDepartedReportIncompleteWhenUnreported() throws {
        let now = try XCTUnwrap(DateFormatting.date(from: "2026-01-10T10:30:00.000Z"))
        let recommendation = TestFactory.recommendation(
            journey: TestFactory.journey(
                scheduledDeparture: "2026-01-10T10:00:00.000Z",
                scheduledArrival: "2026-01-10T11:00:00.000Z",
                displayStatus: "unreported",
                statusText: "Departed · report incomplete",
                compactStatusText: "Dep · report",
                statusKind: "unreported",
                movementPhase: "departed",
                reportState: "destination_missing",
                originRealtime: TestFactory.realtime(actualDeparture: "10:00")
            )
        )
        let window = TestFactory.window(
            selectedRecommendation: recommendation,
            recommendations: [recommendation],
            pinnedTrainServiceId: 101
        )

        let state = RightTrainLiveActivityStateBuilder.state(
            for: window,
            pinnedTrainServiceID: 101,
            activityKind: .train,
            now: now
        )
        let train = try XCTUnwrap(state.trains.first)

        XCTAssertEqual(train.statusKind, .unreported)
        XCTAssertEqual(train.statusText, "Dep · report")
        XCTAssertTrue(train.departed)
        XCTAssertEqual(state.statusText, "Dep · report")
        XCTAssertEqual(state.nextUpdateText, "Report incomplete")
    }

    func testActiveWindowCountdownFarFuture() {
        let now = DateFormatting.date(from: "2026-01-10T09:55:00.000Z")!
        let rec = TestFactory.recommendation(
            journey: TestFactory.journey(scheduledDeparture: "2026-01-10T10:03:00.000Z")
        )

        let countdown = ActiveWindowPresentation.countdown(for: rec, now: now)

        XCTAssertEqual(countdown.text, "Leaves in 8 min")
        XCTAssertEqual(countdown.tone, .green)
        XCTAssertFalse(countdown.isDeparted)
    }

    func testActiveWindowCountdownLeavesNow() {
        let now = DateFormatting.date(from: "2026-01-10T10:00:00.000Z")!
        let rec = TestFactory.recommendation(
            journey: TestFactory.journey(scheduledDeparture: "2026-01-10T10:00:30.000Z")
        )

        let countdown = ActiveWindowPresentation.countdown(for: rec, now: now)

        XCTAssertEqual(countdown.text, "Leaves now")
        XCTAssertEqual(countdown.tone, .accent)
        XCTAssertFalse(countdown.isDeparted)
    }

    func testActiveWindowCountdownDoesNotShowDepartedWithoutActualDeparture() {
        let now = DateFormatting.date(from: "2026-01-10T10:03:00.000Z")!
        let rec = TestFactory.recommendation(
            journey: TestFactory.journey(scheduledDeparture: "2026-01-10T10:00:00.000Z")
        )

        let countdown = ActiveWindowPresentation.countdown(for: rec, now: now)

        XCTAssertEqual(countdown.text, "Awaiting departure")
        XCTAssertEqual(countdown.tone, .accent)
        XCTAssertFalse(countdown.isDeparted)
    }

    func testActiveWindowCountdownKeepsAwaitingDepartureAfterScheduledTimeWithoutBackendDeparture() {
        let now = DateFormatting.date(from: "2026-01-10T10:10:00.000Z")!
        let rec = TestFactory.recommendation(
            journey: TestFactory.journey(scheduledDeparture: "2026-01-10T10:00:00.000Z")
        )

        let countdown = ActiveWindowPresentation.countdown(for: rec, now: now)

        XCTAssertEqual(countdown.text, "Awaiting departure")
        XCTAssertEqual(countdown.tone, .accent)
        XCTAssertFalse(countdown.isDeparted)
    }

    func testActiveWindowCountdownJustDeparted() {
        let now = DateFormatting.date(from: "2026-01-10T10:02:00.000Z")!
        let rec = TestFactory.recommendation(
            journey: TestFactory.journey(
                scheduledDeparture: "2026-01-10T10:00:00.000Z",
                statusText: "Departed",
                compactStatusText: "Departed",
                statusKind: "departed",
                movementPhase: "departed",
                reportState: "origin_reported",
                originRealtime: TestFactory.realtime(actualDeparture: "10:00")
            )
        )

        let countdown = ActiveWindowPresentation.countdown(for: rec, now: now)

        XCTAssertEqual(countdown.text, "Departed 2 min ago")
        XCTAssertEqual(countdown.tone, .accent)
        XCTAssertTrue(countdown.isDeparted)
    }

    func testActiveWindowCountdownLongDeparted() {
        let now = DateFormatting.date(from: "2026-01-10T10:30:00.000Z")!
        let rec = TestFactory.recommendation(
            journey: TestFactory.journey(
                scheduledDeparture: "2026-01-10T10:00:00.000Z",
                scheduledArrival: "2026-01-10T11:00:00.000Z",
                scheduledArrivalRaw: "11:00",
                statusText: "Departed",
                compactStatusText: "Departed",
                statusKind: "departed",
                movementPhase: "departed",
                reportState: "origin_reported",
                originRealtime: TestFactory.realtime(actualDeparture: "10:00")
            )
        )

        let countdown = ActiveWindowPresentation.countdown(for: rec, now: now)

        XCTAssertTrue(countdown.text.hasPrefix("Departed · arr"))
        XCTAssertTrue(countdown.isDeparted)
    }

    func testActiveWindowCountdownCancelled() {
        let rec = TestFactory.recommendation(
            journey: TestFactory.journey(cancelled: true)
        )

        let countdown = ActiveWindowPresentation.countdown(for: rec, now: TestFactory.now)

        XCTAssertEqual(countdown.text, "Cancelled")
        XCTAssertEqual(countdown.tone, .red)
    }

    func testActiveWindowHeroFallsBackWhenBestHasDeparted() {
        let now = DateFormatting.date(from: "2026-01-10T10:10:00.000Z")!
        let departed = TestFactory.recommendation(
            rank: 1,
            serviceID: 202,
            journey: TestFactory.journey(
                serviceID: 202,
                scheduledDeparture: "2026-01-10T10:00:00.000Z",
                statusText: "Departed",
                compactStatusText: "Departed",
                statusKind: "departed",
                movementPhase: "departed",
                reportState: "origin_reported",
                originRealtime: TestFactory.realtime(actualDeparture: "10:00")
            )
        )
        let future = TestFactory.recommendation(
            rank: 2,
            serviceID: 303,
            journey: TestFactory.journey(
                serviceID: 303,
                scheduledDeparture: "2026-01-10T10:30:00.000Z"
            )
        )
        let window = TestFactory.window(
            selectedRecommendation: departed,
            recommendations: [departed, future]
        )

        let presentation = ActiveWindowPresentation(window: window, now: now)

        XCTAssertEqual(presentation.bestRecommendation.journey.serviceId, 202)
        XCTAssertEqual(presentation.heroRecommendation.journey.serviceId, 303)
        XCTAssertEqual(presentation.pastDepartures(now: now).map(\.journey.serviceId), [202])
        XCTAssertEqual(presentation.futureDepartures(now: now).map(\.journey.serviceId), [])
    }

    func testActiveWindowCancelledTrainIsNotUpcomingOrDeparted() {
        let now = DateFormatting.date(from: "2026-01-10T09:55:00.000Z")!
        let cancelled = TestFactory.recommendation(
            rank: 1,
            serviceID: 202,
            journey: TestFactory.journey(
                serviceID: 202,
                scheduledDeparture: "2026-01-10T10:00:00.000Z",
                cancelled: true
            )
        )
        let future = TestFactory.recommendation(
            rank: 2,
            serviceID: 303,
            journey: TestFactory.journey(
                serviceID: 303,
                scheduledDeparture: "2026-01-10T10:30:00.000Z"
            )
        )
        let laterFuture = TestFactory.recommendation(
            rank: 4,
            serviceID: 505,
            journey: TestFactory.journey(
                serviceID: 505,
                scheduledDeparture: "2026-01-10T10:45:00.000Z"
            )
        )
        let departed = TestFactory.recommendation(
            rank: 3,
            serviceID: 404,
            journey: TestFactory.journey(
                serviceID: 404,
                scheduledDeparture: "2026-01-10T09:40:00.000Z",
                statusText: "Departed",
                compactStatusText: "Departed",
                statusKind: "departed",
                movementPhase: "departed",
                reportState: "origin_reported",
                originRealtime: TestFactory.realtime(actualDeparture: "09:40")
            )
        )
        let window = TestFactory.window(
            selectedRecommendation: cancelled,
            recommendations: [cancelled, future, departed, laterFuture]
        )

        let presentation = ActiveWindowPresentation(window: window, now: now)

        XCTAssertEqual(presentation.heroRecommendation.journey.serviceId, 303)
        XCTAssertEqual(presentation.cancelledDepartures(now: now).map(\.journey.serviceId), [202])
        XCTAssertEqual(presentation.futureDepartures(now: now).map(\.journey.serviceId), [505])
        XCTAssertEqual(presentation.pastDepartures(now: now).map(\.journey.serviceId), [404])
    }

    func testActiveWindowCancelledBestDoesNotBecomeHero() {
        let now = DateFormatting.date(from: "2026-01-10T09:55:00.000Z")!
        let cancelled = TestFactory.recommendation(
            rank: 1,
            serviceID: 202,
            journey: TestFactory.journey(
                serviceID: 202,
                scheduledDeparture: "2026-01-10T10:00:00.000Z",
                cancelled: true
            )
        )
        let future = TestFactory.recommendation(
            rank: 2,
            serviceID: 303,
            journey: TestFactory.journey(
                serviceID: 303,
                scheduledDeparture: "2026-01-10T10:30:00.000Z"
            )
        )
        let window = TestFactory.window(
            selectedRecommendation: cancelled,
            recommendations: [cancelled, future]
        )

        let presentation = ActiveWindowPresentation(window: window, now: now)

        XCTAssertEqual(presentation.bestRecommendation.journey.serviceId, 202)
        XCTAssertEqual(presentation.heroRecommendation.journey.serviceId, 303)
        XCTAssertTrue(presentation.shouldShowHero(now: now))
    }

    func testActiveWindowJustDepartedPromptUsesFiveMinuteWindow() {
        let now = DateFormatting.date(from: "2026-01-10T10:02:00.000Z")!
        let departed = TestFactory.recommendation(
            rank: 1,
            serviceID: 202,
            journey: TestFactory.journey(
                serviceID: 202,
                scheduledDeparture: "2026-01-10T10:00:00.000Z",
                statusText: "Departed",
                compactStatusText: "Departed",
                statusKind: "departed",
                movementPhase: "departed",
                reportState: "origin_reported",
                originRealtime: TestFactory.realtime(actualDeparture: "10:00")
            )
        )
        let future = TestFactory.recommendation(
            rank: 2,
            serviceID: 303,
            journey: TestFactory.journey(
                serviceID: 303,
                scheduledDeparture: "2026-01-10T10:30:00.000Z"
            )
        )
        let window = TestFactory.window(
            selectedRecommendation: departed,
            recommendations: [departed, future]
        )

        let presentation = ActiveWindowPresentation(window: window, now: now)

        XCTAssertEqual(presentation.heroRecommendation.journey.serviceId, 303)
        XCTAssertTrue(presentation.shouldShowHero(now: now))
        XCTAssertEqual(presentation.justDepartedRecommendation(now: now)?.journey.serviceId, 202)
        XCTAssertTrue(presentation.pastDepartures(now: now).isEmpty)
        XCTAssertEqual(presentation.pastDepartures(now: now, excludingJustDeparted: false).map(\.journey.serviceId), [202])

        let afterPromptWindow = ActiveWindowPresentation(
            window: window,
            now: DateFormatting.date(from: "2026-01-10T10:06:00.000Z")!
        )

        XCTAssertNil(afterPromptWindow.justDepartedRecommendation(now: DateFormatting.date(from: "2026-01-10T10:06:00.000Z")!))
        XCTAssertEqual(afterPromptWindow.pastDepartures(now: DateFormatting.date(from: "2026-01-10T10:06:00.000Z")!).map(\.journey.serviceId), [202])
    }

    func testActiveWindowPinnedDepartedTrainBecomesOnBoardHero() {
        let now = DateFormatting.date(from: "2026-01-10T10:02:00.000Z")!
        let departed = TestFactory.recommendation(
            rank: 1,
            serviceID: 202,
            journey: TestFactory.journey(
                serviceID: 202,
                scheduledDeparture: "2026-01-10T10:00:00.000Z",
                statusText: "Departed",
                compactStatusText: "Departed",
                statusKind: "departed",
                movementPhase: "departed",
                reportState: "origin_reported",
                originRealtime: TestFactory.realtime(actualDeparture: "10:00")
            )
        )
        let future = TestFactory.recommendation(
            rank: 2,
            serviceID: 303,
            journey: TestFactory.journey(
                serviceID: 303,
                scheduledDeparture: "2026-01-10T10:30:00.000Z"
            )
        )
        let window = TestFactory.window(
            selectedRecommendation: departed,
            recommendations: [departed, future],
            pinnedTrainServiceId: 202
        )

        let presentation = ActiveWindowPresentation(window: window, now: now)

        XCTAssertEqual(presentation.heroTitle, "On board")
        XCTAssertEqual(presentation.heroRecommendation.journey.serviceId, 202)
        XCTAssertTrue(presentation.heroIsPinnedTrain)
        XCTAssertTrue(presentation.shouldShowHero(now: now))
        XCTAssertEqual(presentation.futureDepartures(now: now).map(\.journey.serviceId), [303])
        XCTAssertEqual(presentation.justDepartedRecommendation(now: now)?.journey.serviceId, 202)
    }

    func testActiveWindowHidesHeroWhenOnlyHeroCandidateJustDeparted() {
        let now = DateFormatting.date(from: "2026-01-10T10:02:00.000Z")!
        let departed = TestFactory.recommendation(
            rank: 1,
            serviceID: 202,
            journey: TestFactory.journey(
                serviceID: 202,
                scheduledDeparture: "2026-01-10T10:00:00.000Z",
                statusText: "Departed",
                compactStatusText: "Departed",
                statusKind: "departed",
                movementPhase: "departed",
                reportState: "origin_reported",
                originRealtime: TestFactory.realtime(actualDeparture: "10:00")
            )
        )
        let window = TestFactory.window(
            selectedRecommendation: departed,
            recommendations: [departed]
        )

        let presentation = ActiveWindowPresentation(window: window, now: now)

        XCTAssertEqual(presentation.heroRecommendation.journey.serviceId, 202)
        XCTAssertFalse(presentation.shouldShowHero(now: now))
        XCTAssertEqual(presentation.justDepartedRecommendation(now: now)?.journey.serviceId, 202)
        XCTAssertTrue(presentation.pastDepartures(now: now).isEmpty)
    }

    func testActiveWindowMovesDepartedHeroToPastAfterJustDepartedWindow() {
        let now = DateFormatting.date(from: "2026-01-10T10:06:00.000Z")!
        let departed = TestFactory.recommendation(
            rank: 1,
            serviceID: 202,
            journey: TestFactory.journey(
                serviceID: 202,
                scheduledDeparture: "2026-01-10T10:00:00.000Z",
                statusText: "Departed",
                compactStatusText: "Departed",
                statusKind: "departed",
                movementPhase: "departed",
                reportState: "origin_reported",
                originRealtime: TestFactory.realtime(actualDeparture: "10:00")
            )
        )
        let window = TestFactory.window(
            selectedRecommendation: departed,
            recommendations: [departed]
        )

        let presentation = ActiveWindowPresentation(window: window, now: now)

        XCTAssertEqual(presentation.heroRecommendation.journey.serviceId, 202)
        XCTAssertFalse(presentation.shouldShowHero(now: now))
        XCTAssertNil(presentation.justDepartedRecommendation(now: now))
        XCTAssertEqual(presentation.pastDepartures(now: now).map(\.journey.serviceId), [202])
    }

    func testActiveWindowFutureAndPastSplitsExcludeHero() {
        let now = DateFormatting.date(from: "2026-01-10T09:55:00.000Z")!
        let best = TestFactory.recommendation(
            rank: 1,
            serviceID: 101,
            journey: TestFactory.journey(
                serviceID: 101,
                scheduledDeparture: "2026-01-10T10:00:00.000Z"
            )
        )
        let later = TestFactory.recommendation(
            rank: 2,
            serviceID: 202,
            journey: TestFactory.journey(
                serviceID: 202,
                scheduledDeparture: "2026-01-10T10:20:00.000Z"
            )
        )
        let window = TestFactory.window(
            selectedRecommendation: best,
            recommendations: [best, later]
        )

        let presentation = ActiveWindowPresentation(window: window, now: now)

        XCTAssertEqual(presentation.heroRecommendation.journey.serviceId, 101)
        XCTAssertEqual(presentation.futureDepartures(now: now).map(\.journey.serviceId), [202])
        XCTAssertTrue(presentation.pastDepartures(now: now).isEmpty)
    }

    func testActiveWindowPresentationCollapsedSetupState() {
        let fullPlanWindow = TestFactory.window()

        XCTAssertTrue(ActiveWindowPresentation.shouldCollapseSetup(for: fullPlanWindow))

        let state = ActiveWindowPresentation.collapsedSetupState(for: fullPlanWindow)
        XCTAssertEqual(state.title, "Create Pin")
        XCTAssertEqual(state.statusText, "Pin 1/1 in use")
        XCTAssertEqual(state.message, "Unpin the current journey before creating another Pin.")

        var availablePlanWindow = fullPlanWindow
        availablePlanWindow.entitlement.activeWindowLimit = 2
        XCTAssertFalse(ActiveWindowPresentation.shouldCollapseSetup(for: availablePlanWindow))
        XCTAssertFalse(ActiveWindowPresentation.shouldCollapseSetup(for: nil))
    }
}
