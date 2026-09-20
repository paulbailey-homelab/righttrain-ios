@testable import RightTrain
import SwiftUI
import UIKit
import XCTest

@MainActor
final class LiveActivityLayoutTests: XCTestCase {
    func testGoShapedLiveActivityContentStateDecodesReferenceDateValues() throws {
        let departureSeconds = 800_000_000.0
        let arrivalSeconds = 800_001_800.0
        let connectionSeconds = 800_001_200.0
        let json = """
        {
          "itinerarySubscriptionID": "itinerary-1",
          "phase": "on_leg",
          "recommendationServiceID": 10,
          "routeTitle": "New Barnet to Kings Cross",
          "originName": "New Barnet",
          "originShortName": "New Barnet",
          "destinationName": "Kings Cross",
          "destinationShortName": "Kings Cross",
          "originCrs": "NBA",
          "destinationCrs": "KGX",
          "departureTime": "18:45",
          "scheduledDepartureDate": \(departureSeconds),
          "departureDate": \(departureSeconds),
          "arrivalTime": "18:58",
          "scheduledArrivalDate": \(arrivalSeconds),
          "arrivalDate": \(arrivalSeconds),
          "platform": "1",
          "platformConfirmed": true,
          "statusText": "On time",
          "statusKind": "good",
          "delayMinutes": 0,
          "nextUpdateText": "",
          "updatedAtText": "Updated now",
          "windowTrainCount": 2,
          "trains": [
            {
              "serviceID": 10,
              "operatorName": "Great Northern",
              "operatorCode": "GN",
              "destinationName": "Finsbury Park",
              "destinationShortName": "Finsbury Park",
              "scheduledDepartureTime": "18:45",
              "departureTime": "18:45",
              "scheduledDepartureDate": \(departureSeconds),
              "departureDate": \(departureSeconds),
              "departureDelayed": false,
              "scheduledArrivalTime": "18:58",
              "arrivalTime": "18:58",
              "scheduledArrivalDate": \(arrivalSeconds),
              "arrivalDate": \(arrivalSeconds),
              "arrivalDelayed": false,
              "departurePlatform": "1",
              "arrivalPlatform": "2",
              "departed": true,
              "recommended": true,
              "statusText": "On time",
              "statusKind": "good",
              "delayMinutes": 0,
              "journeyProgress": 0.5
            }
          ],
          "currentLegIndex": 0,
          "onwardLeg": {
            "serviceID": 20,
            "destinationName": "Kings Cross",
            "scheduledDepartureTime": "19:05",
            "departureTime": "19:05",
            "scheduledDepartureDate": \(connectionSeconds),
            "departureDate": \(connectionSeconds),
            "departureDelayed": false,
            "scheduledArrivalTime": "19:17",
            "arrivalTime": "19:17",
            "scheduledArrivalDate": \(arrivalSeconds),
            "arrivalDate": \(arrivalSeconds),
            "arrivalDelayed": false,
            "departurePlatform": "4",
            "arrivalPlatform": "TBC",
            "departed": false,
            "recommended": false,
            "statusText": "On time",
            "statusKind": "good",
            "delayMinutes": 0,
            "journeyProgress": 0
          },
          "interchange": {
            "crs": "FPK",
            "name": "Finsbury Park",
            "legIndex": 0,
            "scheduledArrivalDate": \(arrivalSeconds),
            "expectedArrivalDate": \(arrivalSeconds),
            "scheduledDepartureDate": \(connectionSeconds),
            "expectedDepartureDate": \(connectionSeconds),
            "requiredTransferMinutes": 2,
            "expectedMarginMinutes": 2,
            "riskStatus": "at_risk",
            "onwardPlatform": "4",
            "onwardPlatformConfirmed": true,
            "transferTitle": "Tight change at Finsbury Park"
          }
        }
        """

        let state = try JSONDecoder().decode(
            RightTrainLiveActivityAttributes.ContentState.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(try XCTUnwrap(state.departureDate).timeIntervalSinceReferenceDate, departureSeconds, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(state.trains.first?.scheduledArrivalDate).timeIntervalSinceReferenceDate, arrivalSeconds, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(state.onwardLeg?.departureDate).timeIntervalSinceReferenceDate, connectionSeconds, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(state.interchange?.expectedDepartureDate).timeIntervalSinceReferenceDate, connectionSeconds, accuracy: 0.001)
    }

    func testRegisterLiveActivityTokenRequestEncodesFrequentUpdatesFlag() throws {
        let request = RegisterLiveActivityTokenRequest(
            token: "token",
            environment: "sandbox",
            activityId: "activity-1",
            activityKind: "window",
            tokenRole: "update",
            pinnedTrainServiceId: nil,
            frequentLiveActivityUpdatesEnabled: true,
            clientDeviceId: "device-1",
            appBundleId: "com.example.RightTrain",
            appVersion: "1.2.3",
            buildNumber: "123",
            deviceModel: "iPhone",
            osVersion: "17.5"
        )

        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any]
        XCTAssertEqual(object?["frequentLiveActivityUpdatesEnabled"] as? Bool, true)
    }

    func testDeviceRegistrationContextFactoryIncludesFrequentUpdateCapability() {
        let context = DeviceRegistrationContextFactory(apiClient: FakeAPIClient()).liveActivityContext(accessToken: "token")

        XCTAssertNotNil(context)
        XCTAssertNotNil(context?.frequentLiveActivityUpdatesEnabled)
    }

    func testWatchSupplementalLiveActivitySurfacesFitConstrainedWidths() {
        assertFits(
            surface: .watchSupplemental,
            activityKind: .window,
            state: stressState(activityKind: .window),
            within: CGSize(width: 184, height: 104)
        )
        assertFits(
            surface: .watchSupplemental,
            activityKind: .train,
            state: stressState(activityKind: .train),
            within: CGSize(width: 184, height: 104)
        )
        assertFits(
            surface: .watchSupplemental,
            activityKind: .itinerary,
            state: stressState(activityKind: .itinerary),
            within: CGSize(width: 184, height: 112)
        )
    }

    func testDynamicIslandCompactLiveActivitySurfaceFitsConstrainedWidth() {
        assertFits(
            surface: .dynamicIslandCompact,
            activityKind: .window,
            state: stressState(activityKind: .window),
            within: CGSize(width: 88, height: 38)
        )
        assertFits(
            surface: .dynamicIslandCompact,
            activityKind: .train,
            state: stressState(activityKind: .train),
            within: CGSize(width: 88, height: 38)
        )
    }

    func testDynamicIslandExpandedLiveActivitySurfaceFitsConstrainedWidth() {
        assertFits(
            surface: .dynamicIslandExpanded,
            activityKind: .window,
            state: stressState(activityKind: .window),
            within: CGSize(width: 340, height: 96)
        )
        assertFits(
            surface: .dynamicIslandExpanded,
            activityKind: .itinerary,
            state: stressState(activityKind: .itinerary),
            within: CGSize(width: 340, height: 108)
        )
        assertFits(
            surface: .dynamicIslandExpanded,
            activityKind: .train,
            state: stressState(activityKind: .train),
            within: CGSize(width: 340, height: 108)
        )
    }

    func testPlatformChangeLiveActivitySurfacesFitConstrainedWidths() {
        var state = stressState(activityKind: .window)
        state.platformChange = RightTrainLiveActivityAttributes.ContentState.PlatformChange(
            serviceID: state.recommendationServiceID,
            previousPlatform: "2",
            currentPlatform: "12",
            changedAtText: "2026-05-08T17:45:00Z"
        )

        assertFits(
            surface: .dynamicIslandCompact,
            activityKind: .window,
            state: state,
            within: CGSize(width: 88, height: 38)
        )
        assertFits(
            surface: .dynamicIslandExpanded,
            activityKind: .window,
            state: state,
            within: CGSize(width: 340, height: 96)
        )
        assertFits(
            surface: .lockScreenStandard,
            activityKind: .window,
            state: state,
            within: CGSize(width: 340, height: 136)
        )
    }

    func testUS3ActionNeededLiveActivityPreviewStatesFitAndPreserveSemantics() {
#if DEBUG
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let scenarios: [LiveActivityPreviewScenario] = [
            .windowPlatformChanged,
            .windowStaleData,
            .windowOffline,
            .windowAlternativeNeeded,
            .legApproachingInterchange
        ]

        for scenario in scenarios {
            let state = scenario.state(now: now)
            switch scenario {
            case .windowPlatformChanged:
                XCTAssertEqual(state.platformChange?.previousPlatform, "2")
                XCTAssertEqual(state.platformChange?.currentPlatform, "12")
                XCTAssertEqual(state.statusKind, .atRisk)
            case .windowStaleData:
                XCTAssertEqual(state.statusText, "Update delayed")
                XCTAssertEqual(state.statusKind, .unreported)
                XCTAssertTrue(state.updatedAtText.contains("18"))
            case .windowOffline:
                XCTAssertEqual(state.statusText, "Offline")
                XCTAssertEqual(state.statusKind, .unreported)
                XCTAssertTrue(state.nextUpdateText.contains("Last known"))
            case .windowAlternativeNeeded:
                XCTAssertEqual(state.statusText, "Use next best")
                XCTAssertEqual(state.statusKind, .cancelled)
                XCTAssertEqual(state.cancelledTrainCount, 1)
                XCTAssertEqual(state.upcomingTrainCount, 1)
            case .legApproachingInterchange:
                XCTAssertEqual(state.phase, ItineraryPhase.approachingInterchange.rawValue)
                XCTAssertEqual(state.interchange?.riskStatus, "at_risk")
                XCTAssertEqual(state.statusKind, .atRisk)
            default:
                XCTFail("Unexpected US3 scenario \(scenario)")
            }

            assertFits(
                surface: .dynamicIslandCompact,
                activityKind: scenario.activityKind,
                state: state,
                within: CGSize(width: 88, height: 38)
            )
            assertFits(
                surface: .dynamicIslandExpanded,
                activityKind: scenario.activityKind,
                state: state,
                within: CGSize(width: 340, height: 108)
            )
            assertFits(
                surface: .lockScreenStandard,
                activityKind: scenario.activityKind,
                state: state,
                within: CGSize(width: 340, height: 148)
            )
        }
#endif
    }

    func testUS3LiveActivityStateBuilderPreservesBackendActionNeededMeanings() throws {
        let now = try XCTUnwrap(DateFormatting.date(from: "2026-01-10T10:00:00.000Z"))

        var platformJourney = TestFactory.journey(
            serviceID: 301,
            compactStatusText: "Platform changed",
            statusKind: "at_risk",
            originCrs: "EUS",
            destinationCrs: "MAN",
            originPlatform: "2",
            realtimePlatform: "12",
            realtimePlatformConfirmed: true
        )
        platformJourney.realtimeUpdatedAt = "2026-01-10T09:59:00.000Z"
        let platformState = RightTrainLiveActivityStateBuilder.state(
            for: TestFactory.window(
                selectedRecommendation: TestFactory.recommendation(journey: platformJourney)
            ),
            pinnedTrainServiceID: nil,
            now: now
        )
        XCTAssertEqual(platformState.statusText, "Platform changed")
        XCTAssertEqual(platformState.statusKind, .atRisk)
        XCTAssertEqual(platformState.platform, "12")
        XCTAssertEqual(platformState.updatedAtText, "Updated 09:59")

        var staleJourney = TestFactory.journey(
            serviceID: 302,
            compactStatusText: "Live data stale",
            statusKind: "unreported",
            originCrs: "EUS",
            destinationCrs: "MAN",
            originPlatform: "TBC"
        )
        staleJourney.realtimeUpdatedAt = "2026-01-10T09:42:00.000Z"
        let staleState = RightTrainLiveActivityStateBuilder.state(
            for: TestFactory.window(
                selectedRecommendation: TestFactory.recommendation(journey: staleJourney)
            ),
            pinnedTrainServiceID: nil,
            now: now
        )
        XCTAssertEqual(staleState.statusText, "Live data stale")
        XCTAssertEqual(staleState.statusKind, .unreported)
        XCTAssertEqual(staleState.updatedAtText, "Updated 09:42")

        let offlineJourney = TestFactory.journey(
            serviceID: 303,
            compactStatusText: "Offline",
            statusKind: "unreported",
            originCrs: "EUS",
            destinationCrs: "MAN",
            originPlatform: "4"
        )
        let offlineState = RightTrainLiveActivityStateBuilder.state(
            for: TestFactory.window(
                selectedRecommendation: TestFactory.recommendation(journey: offlineJourney)
            ),
            pinnedTrainServiceID: nil,
            now: now
        )
        XCTAssertEqual(offlineState.statusText, "Offline")
        XCTAssertEqual(offlineState.statusKind, .unreported)

        let cancelled = TestFactory.recommendation(
            rank: 1,
            journey: TestFactory.journey(
                serviceID: 304,
                cancelled: true,
                originCrs: "EUS",
                destinationCrs: "MAN",
                originPlatform: "4"
            )
        )
        let alternative = TestFactory.recommendation(
            rank: 2,
            journey: TestFactory.journey(
                serviceID: 305,
                originCrs: "EUS",
                destinationCrs: "MAN",
                originPlatform: "5"
            )
        )
        let cancelledState = RightTrainLiveActivityStateBuilder.state(
            for: TestFactory.window(
                selectedRecommendation: cancelled,
                recommendations: [cancelled, alternative]
            ),
            pinnedTrainServiceID: nil,
            now: now
        )
        XCTAssertEqual(cancelledState.statusText, "Cancelled")
        XCTAssertEqual(cancelledState.statusKind, .cancelled)
        XCTAssertEqual(cancelledState.cancelledTrainCount, 1)
        XCTAssertEqual(cancelledState.upcomingTrainCount, 1)
    }

    func testDynamicIslandExpandedEdgeMetricsFitLongLabelsAndPlatforms() {
        var state = stressState(activityKind: .leg)
        state.phase = ItineraryPhase.approachingInterchange.rawValue
        state.originName = "London St Pancras International"
        state.destinationName = "Birmingham International"
        state.platform = "Platform 123A"
        state.interchange = RightTrainLiveActivityAttributes.ContentState.Interchange(
            crs: "BHM",
            name: "Birmingham New Street",
            legIndex: 0,
            scheduledArrivalDate: nil,
            expectedArrivalDate: nil,
            scheduledDepartureDate: nil,
            expectedDepartureDate: nil,
            requiredTransferMinutes: 6,
            expectedMarginMinutes: 1,
            riskStatus: "at_risk",
            onwardPlatform: "Platform 123A",
            onwardPlatformConfirmed: true,
            transferTitle: "Tight change at Birmingham New Street"
        )

        assertFits(
            surface: .dynamicIslandExpanded,
            activityKind: .leg,
            state: state,
            within: CGSize(width: 340, height: 108)
        )
    }

    func testDynamicIslandExpandedWindowEdgeMetricsKeepCountdownInset() {
        var state = stressState(activityKind: .window)
        let departureDate = Date().addingTimeInterval(2 * 60)
        let arrivalDate = departureDate.addingTimeInterval(16 * 60)
        state.routeTitle = "New Barnet to Finsbury Park"
        state.originName = "New Barnet"
        state.originShortName = "New Barnet"
        state.destinationName = "Finsbury Park"
        state.destinationShortName = "Finsbury Park"
        state.departureTime = "09:32"
        state.scheduledDepartureDate = departureDate
        state.departureDate = departureDate
        state.arrivalTime = "09:48"
        state.scheduledArrivalDate = arrivalDate
        state.arrivalDate = arrivalDate
        state.platform = "1"
        state.platformConfirmed = true
        state.statusText = "OK"
        state.statusKind = .good
        state.delayMinutes = 0
        state.windowTimeRangeText = "09:12 - 11:12"
        state.otherDeparturesText = "Other trains: 09:30, 09:52, 10:22, 10:52"
        state.trains[0].destinationName = "Finsbury Park"
        state.trains[0].destinationShortName = "Finsbury Park"
        state.trains[0].scheduledDepartureTime = "09:32"
        state.trains[0].departureTime = "09:32"
        state.trains[0].scheduledDepartureDate = departureDate
        state.trains[0].departureDate = departureDate
        state.trains[0].scheduledArrivalTime = "09:48"
        state.trains[0].arrivalTime = "09:48"
        state.trains[0].scheduledArrivalDate = arrivalDate
        state.trains[0].arrivalDate = arrivalDate
        state.trains[0].departurePlatform = "1"
        state.trains[0].arrivalPlatform = "2"
        state.trains[0].statusText = "OK"
        state.trains[0].statusKind = .good
        state.trains[0].delayMinutes = 0

        assertFits(
            surface: .dynamicIslandExpanded,
            activityKind: .window,
            state: state,
            within: CGSize(width: 340, height: 108)
        )
    }

    func testLockScreenOnboardTrainLiveActivityUsesCompactHeight() {
        assertFits(
            surface: .lockScreenStandard,
            activityKind: .train,
            state: stressState(activityKind: .train),
            within: CGSize(width: 340, height: 136)
        )
    }

    func testOnboardTrainLiveActivityTapRoutesToActiveWindow() {
        let state = stressState(activityKind: .train)
        let url = rightTrainActivityURL(
            attributes: trainActivityAttributes(windowSubscriptionID: "tap-window", pinnedTrainServiceID: state.pinnedTrainServiceID),
            state: state
        )

        XCTAssertEqual(url?.absoluteString, "righttrain://windows/direct/subscriptions/tap-window")
    }

    func testOnboardTrainLiveActivityTapFallsBackToActiveTab() {
        let state = stressState(activityKind: .train)
        let url = rightTrainActivityURL(
            attributes: trainActivityAttributes(windowSubscriptionID: nil, pinnedTrainServiceID: state.pinnedTrainServiceID),
            state: state
        )

        XCTAssertEqual(url?.absoluteString, "righttrain://active")
    }

    func testPreDepartureTrainLiveActivityTapStillRoutesToJourneyDetail() {
        var state = stressState(activityKind: .train)
        state.trains[0].departed = false
        state.trains[0].journeyProgress = nil
        state.upcomingTrainCount = 1
        state.departedTrainCount = 0
        let url = rightTrainActivityURL(
            attributes: trainActivityAttributes(windowSubscriptionID: "tap-window", pinnedTrainServiceID: state.pinnedTrainServiceID),
            state: state
        )

        XCTAssertEqual(url?.absoluteString, "righttrain://journeys/9001")
    }

    func testCarPlaySupplementalLiveActivitySurfaceFitsConstrainedWidth() {
        assertFits(
            surface: .carPlaySupplemental,
            activityKind: .window,
            state: stressState(activityKind: .window),
            within: CGSize(width: 340, height: 180)
        )
        assertFits(
            surface: .carPlaySupplemental,
            activityKind: .train,
            state: stressState(activityKind: .train),
            within: CGSize(width: 340, height: 180)
        )
        assertFits(
            surface: .carPlaySupplemental,
            activityKind: .itinerary,
            state: stressState(activityKind: .itinerary),
            within: CGSize(width: 340, height: 180)
        )
    }

    func testActiveTabPrimaryContentPrioritizesItinerary() {
        XCTAssertEqual(
            ActiveTabPrimaryContent.resolve(hasItinerary: true, hasWindow: true, hasOnBoardWindow: true),
            .itinerary
        )
        XCTAssertEqual(
            ActiveTabPrimaryContent.resolve(hasItinerary: false, hasWindow: true, hasOnBoardWindow: true),
            .onBoardWindow
        )
        XCTAssertEqual(
            ActiveTabPrimaryContent.resolve(hasItinerary: false, hasWindow: true, hasOnBoardWindow: false),
            .window
        )
        XCTAssertEqual(
            ActiveTabPrimaryContent.resolve(hasItinerary: false, hasWindow: false, hasOnBoardWindow: false),
            .empty
        )
    }

    func testLiveGlancePanelFitsPhoneWidthAndCarriesAccessibleStatusLabel() throws {
        let journey = TestFactory.journey(
            scheduledDeparture: "2026-01-10T10:00:00.000Z",
            scheduledArrival: "2026-01-10T11:00:00.000Z",
            scheduledDepartureRaw: "10:00",
            scheduledArrivalRaw: "11:00",
            expectedDeparture: "10:04",
            expectedArrival: "11:08",
            statusText: "Platform changed",
            compactStatusText: "Platform changed",
            statusKind: "at_risk",
            originCrs: "EUS",
            destinationCrs: "MAN",
            originPlatform: "2",
            realtimePlatform: "12",
            realtimePlatformConfirmed: true
        )
        var recommendation = TestFactory.recommendation(journey: journey)
        recommendation.journey.realtimeUpdatedAt = "2026-01-10T09:59:30.000Z"
        let now = try XCTUnwrap(DateFormatting.date(from: "2026-01-10T10:00:00.000Z"))
        let content = ActiveWindowPresentation.liveGlanceContent(
            for: recommendation,
            routeTitle: "London Euston to Manchester Piccadilly",
            now: now
        )

        XCTAssertEqual(content.routeContextText, "Caledonian Sleeper")
        XCTAssertEqual(content.platformText, "Platform 12 · was 2")
        XCTAssertEqual(
            JourneyFormatting.accessibilityStatusLabel(
                statusText: content.statusText,
                platformText: content.platformText,
                freshnessText: content.freshnessText
            ),
            "Platform changed, Platform 12 · was 2, Updated now"
        )

        let view = LiveGlancePanel(content: content)
            .environment(\.dynamicTypeSize, .accessibility3)
        let measured = sizeThatFits(view, within: CGSize(width: 340, height: 420))
        XCTAssertLessThanOrEqual(
            measured.width.rounded(.up),
            341,
            "LiveGlancePanel should fit phone width, measured \(measured)"
        )
        XCTAssertGreaterThan(measured.height, 0, "LiveGlancePanel should produce visible content")
    }

    func testActiveItineraryPresentationScopesActionsByPhaseAndAlternatives() {
        let selected = multiLegItinerary(stableKey: "selected-route", rank: 1, serviceBase: 200)
        let alternative = multiLegItinerary(stableKey: "alternate-route", rank: 2, serviceBase: 300)

        let planning = ActiveItineraryPresentation(
            itinerary: TestFactory.itinerarySubscription(
                phase: ItineraryPhase.planning.rawValue,
                selectedItinerary: selected,
                itineraries: [selected, alternative]
            )
        )
        XCTAssertEqual(planning.selectedItinerary?.stableKey, "selected-route")
        XCTAssertEqual(planning.alternativeItineraries.map(\.stableKey), ["alternate-route"])
        XCTAssertEqual(planning.journeyOptions.map(\.stableKey), ["selected-route"])
        XCTAssertTrue(planning.canBoardFirstLeg)
        XCTAssertFalse(planning.canBoardOnwardLeg)
        XCTAssertNil(planning.recoveryFromCrs)
        XCTAssertTrue(planning.canStopMonitoring)

        let onLeg = ActiveItineraryPresentation(
            itinerary: TestFactory.itinerarySubscription(
                phase: ItineraryPhase.onLeg.rawValue,
                currentLegIndex: 0,
                selectedItinerary: selected,
                itineraries: [selected, alternative]
            )
        )
        XCTAssertFalse(onLeg.canBoardFirstLeg)
        XCTAssertFalse(onLeg.canBoardOnwardLeg)
        XCTAssertEqual(onLeg.recoveryFromCrs, "CRE")

        let approaching = ActiveItineraryPresentation(
            itinerary: TestFactory.itinerarySubscription(
                phase: ItineraryPhase.approachingInterchange.rawValue,
                currentLegIndex: 0,
                selectedItinerary: selected,
                itineraries: [selected, alternative]
            )
        )
        XCTAssertTrue(approaching.canBoardOnwardLeg)
        XCTAssertEqual(approaching.recoveryFromCrs, "CRE")

        let finalLeg = ActiveItineraryPresentation(
            itinerary: TestFactory.itinerarySubscription(
                phase: ItineraryPhase.onFinalLeg.rawValue,
                currentLegIndex: 1,
                selectedItinerary: selected,
                itineraries: [selected, alternative]
            )
        )
        XCTAssertFalse(finalLeg.canBoardFirstLeg)
        XCTAssertFalse(finalLeg.canBoardOnwardLeg)
        XCTAssertNil(finalLeg.recoveryFromCrs)
        XCTAssertTrue(finalLeg.canStopMonitoring)
    }

    func testItineraryFormattingShowsActiveSummaryDetails() {
        let selected = multiLegItinerary()
        XCTAssertEqual(ItineraryFormatting.changesText(selected), "1 change")
        XCTAssertEqual(ItineraryFormatting.arrivalText(selected), "11:40")
        XCTAssertEqual(ItineraryFormatting.firstLegPlatformText(selected), "4")

        let realtimePlatform = TestFactory.itinerary(
            legs: [
                TestFactory.itineraryLeg(
                    journey: TestFactory.journey(
                        originPlatform: "4",
                        realtimePlatform: "8"
                    )
                )
            ]
        )
        XCTAssertEqual(ItineraryFormatting.firstLegPlatformText(realtimePlatform), "8")

        let realtimeOriginPlatform = TestFactory.itinerary(
            legs: [
                TestFactory.itineraryLeg(
                    journey: TestFactory.journey(
                        originRealtime: TestFactory.realtime(platform: "9"),
                        originPlatform: "4"
                    )
                )
            ]
        )
        XCTAssertEqual(ItineraryFormatting.firstLegPlatformText(realtimeOriginPlatform), "9")

        let missingPlatform = TestFactory.itinerary(
            legs: [
                TestFactory.itineraryLeg(
                    journey: TestFactory.journey(originPlatform: nil)
                )
            ]
        )
        XCTAssertEqual(ItineraryFormatting.firstLegPlatformText(missingPlatform), "TBC")
    }

    func testActiveItineraryPhaseViewsFitPhoneWidth() {
        let viewModel = activeWindowViewModel()
        let selected = multiLegItinerary()
        let alternative = multiLegItinerary(stableKey: "alternate-route", rank: 2, serviceBase: 300)
        let phases: [(ItineraryPhase, Int)] = [
            (.planning, 0),
            (.atOrigin, 0),
            (.onLeg, 0),
            (.approachingInterchange, 0),
            (.onFinalLeg, 1)
        ]

        for dynamicTypeSize in [DynamicTypeSize.large, .accessibility3] {
            for (phase, currentLegIndex) in phases {
                let view = PerspectiveActiveItineraryView(
                    itinerary: TestFactory.itinerarySubscription(
                        phase: phase.rawValue,
                        currentLegIndex: currentLegIndex,
                        selectedItinerary: selected,
                        itineraries: [selected, alternative]
                    ),
                    loadDetail: { _ in }
                )
                .environment(viewModel)
                .environment(\.dynamicTypeSize, dynamicTypeSize)

                let measured = sizeThatFits(view, within: CGSize(width: 340, height: 1_200))
                XCTAssertLessThanOrEqual(
                    measured.width.rounded(.up),
                    341,
                    "\(phase.rawValue) \(dynamicTypeSize) should fit phone width, measured \(measured)"
                )
                XCTAssertGreaterThan(
                    measured.height,
                    0,
                    "\(phase.rawValue) \(dynamicTypeSize) should produce visible content"
                )
            }
        }
    }

    private func assertFits(
        surface: LiveActivityLayoutTestSurface,
        activityKind: RightTrainLiveActivityAttributes.ActivityKind,
        state: RightTrainLiveActivityAttributes.ContentState,
        within bounds: CGSize,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let probe = LiveActivityLayoutProbe(
            surface: surface,
            state: state,
            activityKind: activityKind
        )
        .environment(\.dynamicTypeSize, .large)
        .environment(\.colorScheme, .dark)

        let measured = sizeThatFits(probe, within: bounds)
        XCTAssertLessThanOrEqual(
            measured.width.rounded(.up),
            bounds.width + 1,
            "\(surface) \(activityKind) should fit width \(bounds.width), measured \(measured)",
            file: file,
            line: line
        )
        XCTAssertLessThanOrEqual(
            measured.height.rounded(.up),
            bounds.height + 1,
            "\(surface) \(activityKind) should fit height \(bounds.height), measured \(measured)",
            file: file,
            line: line
        )
    }

    private func sizeThatFits<Content: View>(_ content: Content, within bounds: CGSize) -> CGSize {
        let host = UIHostingController(rootView: content)
        host.view.backgroundColor = .clear
        host.view.bounds = CGRect(origin: .zero, size: bounds)
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        return host.sizeThatFits(in: bounds)
    }

    private func activeWindowViewModel() -> ActiveWindowViewModel {
        let apiClient = FakeAPIClient()
        return ActiveWindowViewModel(
            apiClient: apiClient,
            operationState: AppOperationState(),
            liveActivityCoordinator: FakeLiveActivityCoordinator(),
            stationProximityMonitor: NoopStationProximityMonitor(),
            registrationContextFactory: DeviceRegistrationContextFactory(apiClient: apiClient),
            accessTokenProvider: { "token" },
            notificationFeedbackGenerator: FakeNotificationFeedbackGenerator(),
            applicationStateProvider: FakeApplicationStateProvider()
        )
    }

    private func multiLegItinerary(
        stableKey: String = "selected-route",
        rank: Int = 1,
        serviceBase: Int = 200
    ) -> ItineraryRecommendation {
        let firstLeg = TestFactory.itineraryLeg(
            legIndex: 0,
            journey: TestFactory.journey(
                serviceID: serviceBase,
                scheduledDeparture: "2026-01-10T10:00:00.000Z",
                scheduledArrival: "2026-01-10T10:40:00.000Z",
                scheduledDepartureRaw: "10:00",
                scheduledArrivalRaw: "10:40",
                originName: "London Euston",
                destinationName: "Crewe",
                originTpl: "EUSTON",
                originCrs: "EUS",
                destinationTpl: "CREWE",
                destinationCrs: "CRE",
                originPlatform: "4",
                destinationPlatform: "6"
            )
        )
        let secondLeg = TestFactory.itineraryLeg(
            legIndex: 1,
            journey: TestFactory.journey(
                serviceID: serviceBase + 1,
                scheduledDeparture: "2026-01-10T10:55:00.000Z",
                scheduledArrival: "2026-01-10T11:40:00.000Z",
                scheduledDepartureRaw: "10:55",
                scheduledArrivalRaw: "11:40",
                originName: "Crewe",
                destinationName: "Manchester Piccadilly",
                originTpl: "CREWE",
                originCrs: "CRE",
                destinationTpl: "MNCRPIC",
                destinationCrs: "MAN",
                originPlatform: "5",
                destinationPlatform: "7"
            )
        )
        let connection = TestFactory.itineraryConnection(
            atTpl: "CREWE",
            atCrs: "CRE",
            atName: "Crewe",
            scheduledArrival: firstLeg.scheduledArrival,
            scheduledDeparture: secondLeg.scheduledDeparture,
            expectedArrival: firstLeg.expectedArrival ?? firstLeg.scheduledArrival,
            expectedDeparture: secondLeg.expectedDeparture ?? secondLeg.scheduledDeparture,
            requiredTransferMinutes: 8,
            scheduledMarginMinutes: 7,
            expectedMarginMinutes: 7
        )
        return TestFactory.itinerary(
            rank: rank,
            stableKey: stableKey,
            legs: [firstLeg, secondLeg],
            connections: [connection]
        )
    }

    private func trainActivityAttributes(
        windowSubscriptionID: String?,
        pinnedTrainServiceID: Int?
    ) -> RightTrainLiveActivityAttributes {
        RightTrainLiveActivityAttributes(
            windowSubscriptionID: windowSubscriptionID,
            itinerarySubscriptionID: nil,
            activityKind: .train,
            pinnedTrainServiceID: pinnedTrainServiceID,
            originCrs: "EUS",
            destinationCrs: "MAN",
            startedAtText: "Test"
        )
    }

    private func stressState(
        activityKind: RightTrainLiveActivityAttributes.ActivityKind
    ) -> RightTrainLiveActivityAttributes.ContentState {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var first = stressTrain(
            serviceID: 9_001,
            destinationName: "Manchester Piccadilly via Milton Keynes Central",
            destinationShortName: "Man Piccadilly",
            scheduledDepartureDate: now.addingTimeInterval(8 * 60),
            departureDate: now.addingTimeInterval(37 * 60),
            scheduledArrivalDate: now.addingTimeInterval(72 * 60),
            arrivalDate: now.addingTimeInterval(104 * 60),
            departurePlatform: "12",
            arrivalPlatform: "14",
            statusText: "+29 Late - report incomplete",
            statusKind: .delayed,
            delayMinutes: 29,
            recommended: true
        )
        if activityKind == .train {
            first.departed = true
            first.statusText = "Departed - report incomplete"
            first.statusKind = .unreported
            first.journeyProgress = 0.42
        }

        let second = stressTrain(
            serviceID: 9_002,
            destinationName: "Manchester Piccadilly",
            destinationShortName: "Man Piccadilly",
            scheduledDepartureDate: now.addingTimeInterval(52 * 60),
            departureDate: now.addingTimeInterval(52 * 60),
            scheduledArrivalDate: now.addingTimeInterval(118 * 60),
            arrivalDate: now.addingTimeInterval(118 * 60),
            departurePlatform: "TBC",
            arrivalPlatform: "3",
            statusText: "On time",
            statusKind: .good,
            delayMinutes: 0
        )
        let trains = activityKind == .itinerary ? [first, second] : [first]

        return RightTrainLiveActivityAttributes.ContentState(
            windowSubscriptionID: activityKind == .itinerary ? nil : "layout-window",
            itinerarySubscriptionID: activityKind == .itinerary ? "layout-itinerary" : nil,
            phase: activityKind == .itinerary ? "pinned_first_leg" : "layout",
            recommendationServiceID: first.serviceID,
            routeTitle: "London Euston to Manchester Piccadilly via Milton Keynes Central",
            originName: "London Euston",
            originShortName: "Euston",
            destinationName: "Manchester Piccadilly",
            destinationShortName: "Man Piccadilly",
            originCrs: "EUS",
            destinationCrs: "MAN",
            departureTime: first.departureTime,
            scheduledDepartureDate: first.scheduledDepartureDate,
            departureDate: first.departureDate,
            arrivalTime: trains.last?.arrivalTime ?? first.arrivalTime,
            scheduledArrivalDate: trains.last?.scheduledArrivalDate,
            arrivalDate: trains.last?.arrivalDate,
            platform: first.departurePlatform,
            platformConfirmed: false,
            statusText: first.statusText,
            statusKind: first.statusKind,
            delayMinutes: first.delayMinutes,
            nextUpdateText: "Delayed 29 min - reports still incomplete",
            updatedAtText: "Updated 9 minutes ago",
            emptyStateText: nil,
            windowTimeRangeText: "09:30 - 11:30 (9 trains)",
            windowTrainCount: trains.count,
            upcomingTrainCount: trains.filter { !$0.departed && $0.statusKind != .cancelled && $0.statusKind != .arrived }.count,
            departedTrainCount: trains.filter(\.departed).count,
            cancelledTrainCount: trains.filter { $0.statusKind == .cancelled }.count,
            otherDeparturesText: activityKind == .itinerary ? "Change at Milton Keynes Central - 3 min" : "5 later, 2 already departed, 1 cancelled",
            trains: trains,
            pinnedTrainServiceID: activityKind == .train ? first.serviceID : nil,
            pinnedFirstLeg: nil
        )
    }

    private func stressTrain(
        serviceID: Int,
        destinationName: String,
        destinationShortName: String? = nil,
        scheduledDepartureDate: Date,
        departureDate: Date,
        scheduledArrivalDate: Date,
        arrivalDate: Date,
        departurePlatform: String,
        arrivalPlatform: String,
        statusText: String,
        statusKind: RightTrainLiveActivityAttributes.StatusKind,
        delayMinutes: Int,
        recommended: Bool = false
    ) -> RightTrainLiveActivityAttributes.ContentState.Train {
        RightTrainLiveActivityAttributes.ContentState.Train(
            serviceID: serviceID,
            operatorName: "London North Eastern Railway",
            operatorCode: "LNER",
            destinationName: destinationName,
            destinationShortName: destinationShortName,
            scheduledDepartureTime: clockText(scheduledDepartureDate),
            departureTime: clockText(departureDate),
            scheduledDepartureDate: scheduledDepartureDate,
            departureDate: departureDate,
            departureDelayed: departureDate != scheduledDepartureDate,
            scheduledArrivalTime: clockText(scheduledArrivalDate),
            arrivalTime: clockText(arrivalDate),
            scheduledArrivalDate: scheduledArrivalDate,
            arrivalDate: arrivalDate,
            arrivalDelayed: arrivalDate != scheduledArrivalDate,
            departurePlatform: departurePlatform,
            arrivalPlatform: arrivalPlatform,
            departed: false,
            recommended: recommended,
            statusText: statusText,
            statusKind: statusKind,
            delayMinutes: delayMinutes,
            journeyProgress: nil
        )
    }

    private func clockText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "Europe/London")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    // MARK: - Live Activity payload size

    /// ActivityKit rejects a content state over roughly 4 KB and `Activity.request`
    /// then throws, so an oversized itinerary state shows up as no Live Activity at
    /// all rather than as an error. A direct window ships one train; an itinerary
    /// ships one per leg, so this is the shape that can outgrow the budget.
    func testItineraryLiveActivityStateFitsActivityKitBudget() throws {
        let selected = multiLegItinerary(stableKey: "selected-route", rank: 1, serviceBase: 200)
        let alternatives = (1...4).map { index in
            multiLegItinerary(
                stableKey: "alternative-\(index)",
                rank: index + 1,
                serviceBase: 300 + index * 10
            )
        }
        let subscription = TestFactory.itinerarySubscription(
            phase: ItineraryPhase.onLeg.rawValue,
            currentLegIndex: 0,
            selectedItinerary: selected,
            itineraries: [selected] + alternatives
        )

        let state = RightTrainLiveActivityStateBuilder.state(for: subscription)
        let encoded = try JSONEncoder().encode(state)

        XCTAssertLessThan(
            encoded.count,
            4096,
            "A multi-leg itinerary's content state must fit ActivityKit's budget, or no Live Activity starts"
        )
    }

    /// The alternatives the search returned are not part of the Live Activity.
    /// They were once packed into every state and nothing ever rendered them,
    /// which is what pushed the payload over the limit.
    func testItineraryLiveActivityStateCarriesOnlyTheSelectedRoutesLegs() {
        let selected = multiLegItinerary(stableKey: "selected-route", rank: 1, serviceBase: 200)
        let alternative = multiLegItinerary(stableKey: "alternative-1", rank: 2, serviceBase: 400)
        let subscription = TestFactory.itinerarySubscription(
            selectedItinerary: selected,
            itineraries: [selected, alternative]
        )

        let state = RightTrainLiveActivityStateBuilder.state(for: subscription)

        XCTAssertEqual(state.trains.count, selected.legs.count)
        let carried = Set(state.trains.map(\.serviceID))
        for leg in alternative.legs {
            XCTAssertFalse(carried.contains(leg.serviceId), "An alternative route's leg must not ride along")
        }
    }
}
