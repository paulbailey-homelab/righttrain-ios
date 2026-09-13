import Foundation
import SwiftUI
import UserNotifications

struct PreviewSessionStore: SessionStoring {
    var session: StoredSession? = PreviewFixtures.storedSession

    func load() throws -> StoredSession? { session }
    func save(_ session: StoredSession) throws {}
    func clear() throws {}
}

struct PreviewNotificationAuthorizer: NotificationAuthorizing {
    var status: UNAuthorizationStatus = .notDetermined

    func currentStatus() async -> UNAuthorizationStatus { status }
    func requestAuthorization() async throws -> UNAuthorizationStatus { .authorized }
}

@MainActor
final class PreviewStationLocationProvider: StationLocationProviding {
    var result: Result<StationSelectionLocation, Error>
    var delayNanoseconds: UInt64

    init(result: Result<StationSelectionLocation, Error> = .success(StationSelectionLocation(
        latitude: 51.5282,
        longitude: -0.1337,
        horizontalAccuracyMeters: 35,
        capturedAt: PreviewFixtures.baseDate
    )), delayNanoseconds: UInt64 = 0) {
        self.result = result
        self.delayNanoseconds = delayNanoseconds
    }

    func currentLocation() async throws -> StationSelectionLocation {
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        return try result.get()
    }
}

@MainActor
struct PreviewAppContainer<Content: View>: View {
    @State private var appCoordinator: AppCoordinator
    private let content: () -> Content

    init(
        selectedTab: AppTab = .active,
        signedIn: Bool = true,
        @ViewBuilder content: @escaping () -> Content
    ) {
        let coordinator = PreviewFixtures.makeAppCoordinator(signedIn: signedIn)
        coordinator.selectedTab = selectedTab
        _appCoordinator = State(initialValue: coordinator)
        self.content = content
    }

    var body: some View {
        content()
            .rightTrainAppEnvironment(appCoordinator)
            .task {
                await appCoordinator.bootstrap()
            }
    }
}

enum PreviewFixtures {
    static let baseDate: Date = {
        let previewStart = Date().addingTimeInterval(-4 * 60)
        let roundedToMinute = floor(previewStart.timeIntervalSinceReferenceDate / 60) * 60
        return Date(timeIntervalSinceReferenceDate: roundedToMinute)
    }()

    static var user: User {
        User(
            id: "00000000-0000-0000-0000-000000000001",
            displayName: "Preview Rider",
            email: "preview@righttrain.app",
            emailVerified: true,
            isPrivateEmail: false,
            entitlements: UserEntitlements(
                tier: "pro",
                status: "active",
                activeWindowLimit: 10,
                commuteRoutineLimit: 10,
                paidSubscription: PaidSubscriptionEntitlement(
                    state: "active",
                    productId: "righttrain.pro.annual",
                    period: "annual",
                    environment: "preview",
                    expiresAt: baseDate.addingTimeInterval(30 * 24 * 60 * 60),
                    willRenew: true
                )
            ),
            stationDefaults: UserStationDefaults(homeStationCrs: "EUS", workStationCrs: "MAN"),
            createdAt: baseDate,
            updatedAt: baseDate
        )
    }

    static var storedSession: StoredSession {
        StoredSession(
            session: Session(
                id: "preview-session",
                accessToken: "preview-token",
                tokenType: "Bearer",
                expiresAt: baseDate.addingTimeInterval(365 * 24 * 60 * 60),
                createdAt: baseDate
            ),
            user: user
        )
    }

    @MainActor
    static func makeAppCoordinator(
        signedIn: Bool = true,
        activeWindow: WindowSubscription? = PreviewFixtures.activeWindow,
        activeItinerary: ItinerarySubscription? = nil,
        routines: [CommuteRoutine] = PreviewFixtures.commuteRoutines,
        multiLegRoutingEnabled: Bool = false,
        notificationStatus: UNAuthorizationStatus = .notDetermined,
        windowNotificationDetail: WindowSubscriptionNotificationDetail? = nil
    ) -> AppCoordinator {
        AppCoordinator(
            apiClient: PreviewAPIClient(
                activeWindow: activeWindow,
                activeItinerary: activeItinerary,
                routines: routines,
                multiLegRoutingEnabled: multiLegRoutingEnabled,
                windowNotificationDetail: windowNotificationDetail
            ),
            sessionStore: PreviewSessionStore(session: signedIn ? storedSession : nil),
            notificationAuthorizer: PreviewNotificationAuthorizer(status: notificationStatus),
            liveActivityCoordinator: NoopLiveActivityCoordinator(),
            pushNotificationCoordinator: NoopPushNotificationCoordinator(),
            storeKitSubscriptionService: PreviewStoreKitSubscriptionService(),
            stationProximityMonitor: NoopStationProximityMonitor()
        )
    }

    static var stations: [StationSuggestion] {
        [
            StationSuggestion(crs: "EUS", name: "London Euston", tpl: "EUSTON", toc: nil, latitude: 51.5284, longitude: -0.1331),
            StationSuggestion(crs: "MAN", name: "Manchester Piccadilly", tpl: "MNCRPIC", toc: nil, latitude: 53.4774, longitude: -2.2309),
            StationSuggestion(crs: "CRE", name: "Crewe", tpl: "CREWE", toc: nil, latitude: 53.0896, longitude: -2.4329),
            StationSuggestion(crs: "WML", name: "Wilmslow", tpl: "WILMSLW", toc: nil, latitude: 53.3269, longitude: -2.2263)
        ]
    }

    static var nearbyStations: [StationSuggestion] {
        [
            StationSuggestion(crs: "EUS", name: "London Euston", tpl: "EUSTON", toc: nil, latitude: 51.5284, longitude: -0.1331, distanceMeters: 142),
            StationSuggestion(crs: "KGX", name: "London Kings Cross", tpl: "KNGX", toc: nil, latitude: 51.5317, longitude: -0.1235, distanceMeters: 720),
            StationSuggestion(crs: "STP", name: "London St Pancras International", tpl: "STPX", toc: nil, latitude: 51.5321, longitude: -0.1264, distanceMeters: 770)
        ]
    }

    static var stationFavourites: [StationFavourite] {
        StationFavoritesProvider.favourites(
            homeStationCRS: user.stationDefaults.homeStationCrs,
            workStationCRS: user.stationDefaults.workStationCrs,
            routines: commuteRoutines,
            stationResolver: { crs in
                stations.first { $0.crs.caseInsensitiveCompare(crs) == .orderedSame }
            }
        )
    }

    static var previewAPIClient: PreviewAPIClient {
        PreviewAPIClient()
    }

    static var activeWindow: WindowSubscription {
        let first = recommendation(serviceID: 9001, departureOffset: 12, arrivalOffset: 95, rank: 1)
        let second = recommendation(serviceID: 9002, departureOffset: 42, arrivalOffset: 130, rank: 2, delayMinutes: 6)
        let third = recommendation(serviceID: 9003, departureOffset: 72, arrivalOffset: 155, rank: 3)
        return WindowSubscription(
            id: "preview-window",
            userId: user.id,
            status: "active",
            originCrs: "EUS",
            destinationCrs: "MAN",
            departureStart: iso(minutesFromBase: 0),
            windowMinutes: 120,
            selectedRecommendation: first,
            recommendations: [first, second, third],
            pinnedTrainServiceId: nil,
            notificationsEnabled: true,
            entitlement: WindowSubscriptionEntitlementState(
                tier: "pro",
                status: "active",
                activeWindowLimit: 10,
                activeWindowCount: 1
            ),
            createdAt: iso(minutesFromBase: -20),
            deletedAt: nil
        )
    }

    static var journeyPinnedWindow: WindowSubscription {
        var window = activeWindow
        window.pinnedTrainServiceId = window.selectedRecommendation.journey.serviceId
        return window
    }

    static var onBoardWindow: WindowSubscription {
        var first = recommendation(serviceID: 9_011, departureOffset: -22, arrivalOffset: 18, rank: 1)
        first.journey.movementPhase = "departed"
        first.journey.displayStatus = "departed"
        first.journey.statusText = "On board"
        first.journey.statusKind = "departed"
        let second = recommendation(serviceID: 9_012, departureOffset: 22, arrivalOffset: 64, rank: 2)
        var window = activeWindow
        window.selectedRecommendation = first
        window.recommendations = [first, second]
        window.pinnedTrainServiceId = first.journey.serviceId
        return window
    }

    static var platformUnknownWindow: WindowSubscription {
        var first = recommendation(serviceID: 9_021, departureOffset: 8, arrivalOffset: 82, rank: 1)
        first.journey.displayStatus = "unreported"
        first.journey.statusText = "Platform TBC"
        first.journey.compactStatusText = "Platform TBC"
        first.journey.statusKind = "unreported"
        first.journey.originPlatform = nil
        first.journey.realtimePlatform = nil
        first.journey.realtimePlatformConfirmed = false
        var window = activeWindow
        window.selectedRecommendation = first
        window.recommendations = [first, recommendation(serviceID: 9_022, departureOffset: 34, arrivalOffset: 116, rank: 2)]
        return window
    }

    static var platformChangedWindow: WindowSubscription {
        var first = recommendation(serviceID: 9_031, departureOffset: 9, arrivalOffset: 88, rank: 1)
        first.journey.statusText = "Platform changed"
        first.journey.compactStatusText = "Platform changed"
        first.journey.statusKind = "at_risk"
        first.journey.originPlatform = "2"
        first.journey.realtimePlatform = "12"
        first.journey.realtimePlatformConfirmed = true
        var window = activeWindow
        window.selectedRecommendation = first
        window.recommendations = [first, recommendation(serviceID: 9_032, departureOffset: 39, arrivalOffset: 121, rank: 2)]
        return window
    }

    static var staleDataWindow: WindowSubscription {
        var first = recommendation(serviceID: 9_041, departureOffset: 14, arrivalOffset: 94, rank: 1)
        first.journey.statusText = "Update delayed"
        first.journey.compactStatusText = "Update delayed"
        first.journey.statusKind = "unreported"
        first.journey.realtimeUpdatedAt = iso(minutesFromBase: -18)
        first.score.staleDataPenaltyMinutes = 8
        var window = activeWindow
        window.selectedRecommendation = first
        window.recommendations = [first, recommendation(serviceID: 9_042, departureOffset: 46, arrivalOffset: 130, rank: 2)]
        return window
    }

    static var offlineWindow: WindowSubscription {
        var first = recommendation(serviceID: 9_051, departureOffset: 11, arrivalOffset: 93, rank: 1)
        first.journey.statusText = "Last known on time"
        first.journey.compactStatusText = "Offline"
        first.journey.statusKind = "unreported"
        var window = activeWindow
        window.selectedRecommendation = first
        window.recommendations = [first, recommendation(serviceID: 9_052, departureOffset: 43, arrivalOffset: 125, rank: 2)]
        return window
    }

    static var cancelledWindow: WindowSubscription {
        let first = recommendation(serviceID: 9_061, departureOffset: 16, arrivalOffset: 98, rank: 1, cancelled: true)
        let second = recommendation(serviceID: 9_062, departureOffset: 36, arrivalOffset: 118, rank: 2)
        var window = activeWindow
        window.selectedRecommendation = first
        window.recommendations = [first, second]
        return window
    }

    static var platformChangeNotificationDetail: WindowSubscriptionNotificationDetail {
        let window = platformChangedWindow
        return WindowSubscriptionNotificationDetail(
            id: "preview-platform-change",
            windowSubscriptionId: window.id,
            eventType: "platform_change",
            deliveryClass: "attention",
            payload: WindowNotificationPayload(
                type: "platform_change",
                occurredAt: iso(minutesFromNow: -1),
                data: WindowNotificationData(
                    reasons: ["platform_change"],
                    topRecommendation: window.selectedRecommendation,
                    previousRecommendation: nil,
                    affectedRecommendation: window.selectedRecommendation,
                    departedRecommendation: nil,
                    nextRecommendation: window.recommendations.dropFirst().first,
                    platform: "12",
                    previousPlatform: "2",
                    delayBand: nil,
                    boundary: nil,
                    scheduledDeparture: nil,
                    scheduledDepartureTime: window.selectedRecommendation.journey.scheduledDepartureRaw,
                    expectedDeparture: nil,
                    expectedDepartureAt: nil,
                    windowStart: window.departureStart,
                    windowEnd: nil,
                    departedTrainServiceId: nil,
                    nextRecommendationServiceId: window.recommendations.dropFirst().first?.journey.serviceId
                )
            ),
            createdAt: iso(minutesFromNow: -1)
        )
    }

    static func activeItinerary(
        phase: ItineraryPhase = .planning,
        currentLegIndex: Int = 0
    ) -> ItinerarySubscription {
        let selected = itineraryRecommendation(stableKey: "preview-selected", rank: 1, serviceBase: 9_101)
        let alternate = itineraryRecommendation(stableKey: "preview-alternate", rank: 2, serviceBase: 9_201)
        return ItinerarySubscription(
            id: "preview-itinerary",
            userId: user.id,
            status: "active",
            phase: phase.rawValue,
            currentLegIndex: currentLegIndex,
            originCrs: "EUS",
            destinationCrs: "MAN",
            departureStart: iso(minutesFromBase: 0),
            windowMinutes: 120,
            maxChanges: 3,
            limit: 5,
            notificationsEnabled: true,
            selectedItinerary: selected,
            itineraries: [selected, alternate],
            createdAt: iso(minutesFromBase: -20),
            deletedAt: nil
        )
    }

    static func itineraryRecommendation(
        stableKey: String,
        rank: Int,
        serviceBase: Int
    ) -> ItineraryRecommendation {
        let firstLeg = itineraryLeg(
            legIndex: 0,
            serviceID: serviceBase,
            originTpl: "EUSTON",
            originCrs: "EUS",
            originName: "London Euston",
            destinationTpl: "CREWE",
            destinationCrs: "CRE",
            destinationName: "Crewe",
            departureOffset: 10 + ((rank - 1) * 12),
            arrivalOffset: 48 + ((rank - 1) * 12),
            originPlatform: "4",
            destinationPlatform: "6"
        )
        let secondLeg = itineraryLeg(
            legIndex: 1,
            serviceID: serviceBase + 1,
            originTpl: "CREWE",
            originCrs: "CRE",
            originName: "Crewe",
            destinationTpl: "MNCRPIC",
            destinationCrs: "MAN",
            destinationName: "Manchester Piccadilly",
            departureOffset: 60 + ((rank - 1) * 12),
            arrivalOffset: 108 + ((rank - 1) * 12),
            originPlatform: "5",
            destinationPlatform: "7"
        )
        let connection = ItineraryConnection(
            fromLegIndex: 0,
            toLegIndex: 1,
            atTpl: "CREWE",
            atCrs: "CRE",
            atName: "Crewe",
            scheduledArrival: firstLeg.scheduledArrival,
            scheduledDeparture: secondLeg.scheduledDeparture,
            expectedArrival: firstLeg.expectedArrival ?? firstLeg.scheduledArrival,
            expectedDeparture: secondLeg.expectedDeparture ?? secondLeg.scheduledDeparture,
            requiredTransferMinutes: 8,
            scheduledMarginMinutes: 4,
            expectedMarginMinutes: rank == 1 ? 4 : 10,
            risk: ConnectionRisk(status: rank == 1 ? "tight" : "ok", reasons: nil)
        )
        return ItineraryRecommendation(
            rank: rank,
            recommended: rank == 1,
            stableKey: stableKey,
            originCrs: firstLeg.originCrs,
            destinationCrs: secondLeg.destinationCrs,
            scheduledDeparture: firstLeg.scheduledDeparture,
            scheduledArrival: secondLeg.scheduledArrival,
            expectedDeparture: firstLeg.expectedDeparture ?? firstLeg.scheduledDeparture,
            expectedArrival: secondLeg.expectedArrival ?? secondLeg.scheduledArrival,
            legs: [firstLeg, secondLeg],
            connections: [connection],
            score: ItineraryScore(
                scoreMinutes: 108 + ((rank - 1) * 12),
                expectedArrival: secondLeg.expectedArrival ?? secondLeg.scheduledArrival,
                reliableArrival: secondLeg.expectedArrival ?? secondLeg.scheduledArrival,
                delayMinutes: 0,
                penaltyMinutes: rank == 1 ? 2 : 0,
                changeCount: 1,
                minimumConnectionMarginMinutes: connection.expectedMarginMinutes,
                transferRiskPenaltyMinutes: rank == 1 ? 2 : nil,
                disruptionPenaltyMinutes: nil,
                usable: true,
                reasons: nil
            ),
            candidateServiceKeys: [
                ItineraryServiceKey(serviceId: firstLeg.serviceId, rid: firstLeg.rid, ssd: firstLeg.ssd),
                ItineraryServiceKey(serviceId: secondLeg.serviceId, rid: secondLeg.rid, ssd: secondLeg.ssd)
            ],
            statusText: rank == 1 ? "Tight connection at Crewe" : nil,
            compactStatusText: rank == 1 ? "Tight connection" : nil,
            statusKind: rank == 1 ? "at_risk" : nil,
            delayMinutes: nil
        )
    }

    static func itineraryLeg(
        legIndex: Int,
        serviceID: Int,
        originTpl: String,
        originCrs: String,
        originName: String,
        destinationTpl: String,
        destinationCrs: String,
        destinationName: String,
        departureOffset: Int,
        arrivalOffset: Int,
        originPlatform: String,
        destinationPlatform: String
    ) -> ItineraryLeg {
        let departure = iso(minutesFromBase: departureOffset)
        let arrival = iso(minutesFromBase: arrivalOffset)
        return ItineraryLeg(
            legIndex: legIndex,
            serviceId: serviceID,
            rid: "preview-itinerary-\(serviceID)",
            ssd: "2030-01-10",
            uid: nil,
            toc: "VT",
            operatorName: "Avanti West Coast",
            status: "scheduled",
            displayStatus: "on_time",
            realtimeSource: "preview",
            realtimeUpdatedAt: iso(minutesFromBase: 3),
            lateReasonCode: nil,
            lateReasonText: nil,
            lateReasonLocationTpl: nil,
            lateReasonLocationName: nil,
            cancellationReasonCode: nil,
            cancellationReasonText: nil,
            cancellationReasonLocationTpl: nil,
            cancellationReasonLocationName: nil,
            originTpl: originTpl,
            originCrs: originCrs,
            originName: originName,
            destinationTpl: destinationTpl,
            destinationCrs: destinationCrs,
            destinationName: destinationName,
            scheduledDeparture: departure,
            scheduledArrival: arrival,
            scheduledDepartureRaw: clockString(baseDate.addingTimeInterval(TimeInterval(departureOffset) * 60)),
            scheduledArrivalRaw: clockString(baseDate.addingTimeInterval(TimeInterval(arrivalOffset) * 60)),
            originPlatform: originPlatform,
            destinationPlatform: destinationPlatform,
            expectedDeparture: departure,
            expectedArrival: arrival,
            expectedDepartureAt: departure,
            expectedArrivalAt: arrival,
            realtimePlatform: originPlatform,
            realtimePlatformConfirmed: true,
            cancelled: false,
            deactivated: false,
            originRealtime: nil,
            destinationRealtime: nil
        )
    }

    static var commuteRoutines: [CommuteRoutine] {
        [
            CommuteRoutine(
                id: "preview-morning",
                userId: user.id,
                name: "Morning commute",
                status: "active",
                originCrs: "EUS",
                destinationCrs: "MAN",
                departureTime: clockString(baseDate.addingTimeInterval(15 * 60)),
                windowMinutes: 120,
                activeWeekdays: [appWeekday(for: baseDate)],
                autoArmEnabled: true,
                autoArmLeadMinutes: 30,
                notificationsEnabled: true,
                createdAt: baseDate,
                updatedAt: baseDate,
                deletedAt: nil
            ),
            CommuteRoutine(
                id: "preview-evening",
                userId: user.id,
                name: "Evening return",
                status: "paused",
                originCrs: "MAN",
                destinationCrs: "EUS",
                departureTime: "17:45",
                windowMinutes: 90,
                activeWeekdays: [1, 2, 3, 4, 5],
                autoArmEnabled: true,
                autoArmLeadMinutes: 20,
                notificationsEnabled: true,
                createdAt: baseDate,
                updatedAt: baseDate,
                deletedAt: nil
            )
        ]
    }

    static func recommendation(
        serviceID: Int,
        departureOffset: Int,
        arrivalOffset: Int,
        rank: Int,
        delayMinutes: Int = 0,
        cancelled: Bool = false
    ) -> DirectWindowRecommendation {
        let scheduledDeparture = iso(minutesFromBase: departureOffset)
        let scheduledArrival = iso(minutesFromBase: arrivalOffset)
        let expectedDeparture = delayMinutes > 0 ? iso(minutesFromBase: departureOffset + delayMinutes) : nil
        let expectedArrival = delayMinutes > 0 ? iso(minutesFromBase: arrivalOffset + delayMinutes) : nil
        let journey = JourneyResult(
            serviceId: serviceID,
            rid: "preview-\(serviceID)",
            ssd: "2030-01-10",
            uid: nil,
            toc: "VT",
            operatorName: "Avanti West Coast",
            status: cancelled ? "cancelled" : "scheduled",
            displayStatus: cancelled ? "cancelled" : (delayMinutes > 0 ? "delayed" : "on_time"),
            realtimeSource: "preview",
            realtimeUpdatedAt: iso(minutesFromBase: 3),
            lateReasonCode: nil,
            lateReasonText: delayMinutes > 0 ? "A late-running inbound service" : nil,
            lateReasonLocationTpl: nil,
            lateReasonLocationName: nil,
            cancellationReasonCode: nil,
            cancellationReasonText: cancelled ? "Preview cancellation" : nil,
            cancellationReasonLocationTpl: nil,
            cancellationReasonLocationName: nil,
            originTpl: "EUSTON",
            originCrs: "EUS",
            originName: "London Euston",
            destinationTpl: "MNCRPIC",
            destinationCrs: "MAN",
            destinationName: "Manchester Piccadilly",
            scheduledDeparture: scheduledDeparture,
            scheduledArrival: scheduledArrival,
            scheduledDepartureRaw: clockString(baseDate.addingTimeInterval(TimeInterval(departureOffset) * 60)),
            scheduledArrivalRaw: clockString(baseDate.addingTimeInterval(TimeInterval(arrivalOffset) * 60)),
            originPlatform: "4",
            destinationPlatform: "7",
            expectedDeparture: expectedDeparture,
            expectedArrival: expectedArrival,
            realtimePlatform: "4",
            realtimePlatformConfirmed: true,
            cancelled: cancelled,
            deactivated: false,
            originRealtime: nil,
            destinationRealtime: nil
        )
        return DirectWindowRecommendation(
            rank: rank,
            recommended: rank == 1,
            journey: journey,
            score: DirectWindowRecommendationScore(
                scoreMinutes: arrivalOffset + delayMinutes,
                expectedArrival: expectedArrival ?? scheduledArrival,
                reliableArrival: expectedArrival ?? scheduledArrival,
                delayMinutes: delayMinutes,
                penaltyMinutes: delayMinutes,
                cancellationPenaltyMinutes: cancelled ? 10_000 : nil,
                severeDelayPenaltyMinutes: delayMinutes >= 15 ? delayMinutes : nil,
                staleDataPenaltyMinutes: nil,
                lowConfidencePenaltyMinutes: nil,
                usable: !cancelled,
                reasons: nil
            )
        )
    }

    static func journeyDetail(
        serviceID: Int,
        originTPL: String?,
        destinationTPL: String?
    ) -> JourneyDetail {
        let originName = stationName(forTPL: originTPL, fallback: "London Euston")
        let destinationName = stationName(forTPL: destinationTPL, fallback: "Manchester Piccadilly")
        let isOnBoardPreview = serviceID == onBoardWindow.selectedRecommendation.journey.serviceId

        return JourneyDetail(
            serviceId: serviceID,
            rid: "preview-detail-\(serviceID)",
            ssd: "2030-01-10",
            uid: nil,
            toc: isOnBoardPreview ? "GN" : "VT",
            operatorName: isOnBoardPreview ? "Great Northern" : "Avanti West Coast",
            status: isOnBoardPreview ? "departed" : "scheduled",
            displayStatus: isOnBoardPreview ? "departed" : "on_time",
            statusText: isOnBoardPreview ? "On board" : "On time",
            compactStatusText: isOnBoardPreview ? "On board" : "On time",
            statusKind: isOnBoardPreview ? "departed" : "good",
            movementPhase: isOnBoardPreview ? "departed" : "not_departed",
            reportState: "complete",
            delayMinutes: 0,
            realtimeSource: "preview",
            lateReasonCode: nil,
            lateReasonText: nil,
            lateReasonLocationTpl: nil,
            lateReasonLocationName: nil,
            cancellationReasonCode: nil,
            cancellationReasonText: nil,
            cancellationReasonLocationTpl: nil,
            cancellationReasonLocationName: nil,
            originTpl: originTPL ?? "EUSTON",
            originCrs: "EUS",
            originName: originName,
            destinationTpl: destinationTPL ?? "MNCRPIC",
            destinationCrs: "MAN",
            destinationName: destinationName,
            cancelled: false,
            deactivated: false,
            coachCount: 8,
            coachCountApproximate: nil,
            trainPosition: isOnBoardPreview ? JourneyTrainPosition(stationIndex: nil, betweenAfterIndex: 0, progress: 0.58) : nil,
            stops: previewStops(originName: originName, destinationName: destinationName)
        )
    }

    private static func previewStops(originName: String, destinationName: String) -> [JourneyStop] {
        [
            JourneyStop(
                stopIndex: 0,
                stopType: "origin",
                tpl: "EUSTON",
                crs: "EUS",
                name: originName,
                publicArrival: nil,
                publicDeparture: clockString(baseDate.addingTimeInterval(-22 * 60)),
                scheduledPlatform: "4",
                activities: nil,
                timing: JourneyStopTiming(label: "Dep", scheduled: clockString(baseDate.addingTimeInterval(-22 * 60)), current: clockString(baseDate.addingTimeInterval(-22 * 60)), delayed: false, status: "Departed"),
                realtime: nil
            ),
            JourneyStop(
                stopIndex: 1,
                stopType: "intermediate",
                tpl: "FINSBRY",
                crs: "FPK",
                name: "Finsbury Park",
                publicArrival: clockString(baseDate.addingTimeInterval(-7 * 60)),
                publicDeparture: clockString(baseDate.addingTimeInterval(-6 * 60)),
                scheduledPlatform: "2",
                activities: nil,
                timing: JourneyStopTiming(label: "Dep", scheduled: clockString(baseDate.addingTimeInterval(-6 * 60)), current: clockString(baseDate.addingTimeInterval(-6 * 60)), delayed: false, status: "Departed"),
                realtime: nil
            ),
            JourneyStop(
                stopIndex: 2,
                stopType: "intermediate",
                tpl: "OLDST",
                crs: "OLD",
                name: "Old Street",
                publicArrival: clockString(baseDate.addingTimeInterval(10 * 60)),
                publicDeparture: clockString(baseDate.addingTimeInterval(11 * 60)),
                scheduledPlatform: "1",
                activities: nil,
                timing: JourneyStopTiming(label: "Dep", scheduled: clockString(baseDate.addingTimeInterval(11 * 60)), current: clockString(baseDate.addingTimeInterval(11 * 60)), delayed: false, status: "Expected"),
                realtime: nil
            ),
            JourneyStop(
                stopIndex: 3,
                stopType: "destination",
                tpl: "MNCRPIC",
                crs: "MAN",
                name: destinationName,
                publicArrival: clockString(baseDate.addingTimeInterval(18 * 60)),
                publicDeparture: nil,
                scheduledPlatform: "7",
                activities: nil,
                timing: JourneyStopTiming(label: "Arr", scheduled: clockString(baseDate.addingTimeInterval(18 * 60)), current: clockString(baseDate.addingTimeInterval(18 * 60)), delayed: false, status: "Expected"),
                realtime: nil
            )
        ]
    }

    private static func stationName(forTPL tpl: String?, fallback: String) -> String {
        switch tpl {
        case "EUSTON":
            return "London Euston"
        case "MNCRPIC":
            return "Manchester Piccadilly"
        case "MOORGTE":
            return "Moorgate"
        default:
            return fallback
        }
    }

    static func iso(minutesFromBase minutes: Int) -> String {
        DateFormatting.apiDateTime.string(from: baseDate.addingTimeInterval(TimeInterval(minutes) * 60))
    }

    static func iso(minutesFromNow minutes: Int) -> String {
        DateFormatting.apiDateTime.string(from: Date().addingTimeInterval(TimeInterval(minutes) * 60))
    }

    static func clockString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "Europe/London")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    static func appWeekday(for date: Date) -> Int {
        let weekday = Calendar.current.component(.weekday, from: date)
        return weekday == 1 ? 7 : weekday - 1
    }
}

struct PreviewAPIClient: APIClienting {
    var activeWindow: WindowSubscription? = PreviewFixtures.activeWindow
    var activeItinerary: ItinerarySubscription?
    var routines: [CommuteRoutine] = PreviewFixtures.commuteRoutines
    var multiLegRoutingEnabled = false
    var windowNotificationDetail: WindowSubscriptionNotificationDetail?
    var nearbyResponse: NearbyStationSearchResponse?

    private var previewPrivacyAccount: PrivacyAccount {
        PrivacyAccount(
            id: PreviewFixtures.user.id,
            state: "active",
            createdAt: PreviewFixtures.baseDate,
            updatedAt: PreviewFixtures.baseDate
        )
    }

    private var previewAccountPreferenceSet: AccountPreferenceSet {
        AccountPreferenceSet(
            version: 1,
            updatedAt: PreviewFixtures.baseDate,
            stationDefaults: PreviewFixtures.user.stationDefaults,
            commuteRoutines: [],
            routeSetupDefaults: [:],
            notificationPreferences: AccountNotificationPreferences(routineNotificationsEnabled: true),
            productPreferences: [:]
        )
    }

    func createDeviceChallenge() async throws -> DeviceChallengeResponse {
        DeviceChallengeResponse(attemptId: "preview-attempt", challenge: "Y2hhbGxlbmdl", expiresAt: Date().addingTimeInterval(300))
    }

    func registerDevice(attemptId: String, keyId: String, attestationObject: String) async throws -> AuthResponse {
        AuthResponse(user: PreviewFixtures.user, session: PreviewFixtures.storedSession.session)
    }

    func createAccountRegistrationOptions(accessToken: String) async throws -> AccountRegistrationOptionsResponse {
        AccountRegistrationOptionsResponse(
            attemptId: "preview-account-registration",
            expiresAt: Date().addingTimeInterval(300),
            credentialOptions: AccountCredentialOptions(
                challenge: "preview-challenge",
                relyingPartyId: "righttrain.app",
                userHandle: "preview-user-handle",
                displayName: "RightTrain account"
            )
        )
    }

    func registerAccount(input: RegisterAccountRequest, accessToken: String) async throws -> RegisterAccountResponse {
        RegisterAccountResponse(
            account: previewPrivacyAccount,
            preferenceSet: previewAccountPreferenceSet,
            recoveryCode: "preview-recovery-code"
        )
    }

    func createAccountAssertionOptions(credentialHint: String?) async throws -> AccountAssertionOptionsResponse {
        AccountAssertionOptionsResponse(
            attemptId: "preview-account-assertion",
            expiresAt: Date().addingTimeInterval(300),
            assertionOptions: AccountAssertionOptions(
                challenge: "preview-assertion-challenge",
                relyingPartyId: "righttrain.app",
                allowCredentials: ["preview-credential"]
            )
        )
    }

    func signInWithAccount(input: AccountSignInRequest) async throws -> AuthResponse {
        AuthResponse(user: PreviewFixtures.user, session: PreviewFixtures.storedSession.session)
    }

    func recoverAccount(input: AccountRecoveryRequest) async throws -> AuthResponse {
        AuthResponse(user: PreviewFixtures.user, session: PreviewFixtures.storedSession.session)
    }

    func serviceStatus() async throws -> ServiceStatus {
        ServiceStatus(status: "operational", checkedAt: PreviewFixtures.baseDate, components: [], message: "Operational")
    }

    func resetPooledConnections() async {}

    func appCapabilities() async throws -> AppCapabilitiesResponse {
        AppCapabilitiesResponse(multiLegRoutingEnabled: multiLegRoutingEnabled)
    }

    func currentUser(accessToken: String) async throws -> User { PreviewFixtures.user }
    func updateStationDefaults(input: UpdateStationDefaultsRequest, accessToken: String) async throws -> User { PreviewFixtures.user }
    func deleteCurrentUser(accessToken: String) async throws {}

    func getAccountPreferenceSet(accessToken: String) async throws -> AccountPreferenceSet {
        previewAccountPreferenceSet
    }

    func updateAccountPreferenceSet(input: UpdateAccountPreferenceSetRequest, accessToken: String) async throws -> UpdateAccountPreferenceSetResponse {
        UpdateAccountPreferenceSetResponse(version: input.baseVersion + 1, updatedAt: PreviewFixtures.baseDate, conflict: nil)
    }

    func listLinkedDevices(accessToken: String) async throws -> LinkedDevicesResponse {
        LinkedDevicesResponse(devices: [
            LinkedDevice(
                id: "preview-linked-device",
                platform: "iOS",
                deviceClass: "iPhone",
                appVersion: "0.1",
                buildNumber: "1",
                lastSeenAt: PreviewFixtures.baseDate,
                currentDevice: true,
                state: "active"
            )
        ])
    }

    func revokeLinkedDevice(id: String, accessToken: String) async throws {}

    func exportAccountPreferences(accessToken: String) async throws -> AccountExportResponse {
        AccountExportResponse(
            generatedAt: PreviewFixtures.baseDate,
            account: previewPrivacyAccount,
            preferenceSet: previewAccountPreferenceSet,
            linkedDevices: [
                ExportLinkedDevice(platform: "iOS", deviceClass: "iPhone", lastSeenAt: PreviewFixtures.baseDate, state: "active")
            ],
            retainedRecords: nil
        )
    }

    func billingProducts(accessToken: String) async throws -> BillingProductsResponse {
        BillingProductsResponse(
            products: [BillingProduct(productId: "righttrain.pro.annual", tier: "pro", period: "annual")],
            entitlements: PreviewFixtures.user.entitlements
        )
    }

    func syncStoreKitTransactions(signedTransactions: [String], accessToken: String) async throws -> User { PreviewFixtures.user }

    func searchStations(query: String, limit: Int) async throws -> [StationSuggestion] {
        PreviewFixtures.stations.filter {
            query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.crs.localizedCaseInsensitiveContains(query)
        }
    }

    func searchDirectDestinationStations(originCRS: String, query: String, departureStart: Date, windowMinutes: Int, limit: Int) async throws -> [StationSuggestion] {
        try await searchStations(query: query, limit: limit)
    }

    func searchNearbyStations(
        latitude: Double,
        longitude: Double,
        selectionRole: StationPickerSelectionRole,
        routeMode: StationPickerRouteMode,
        originCRS: String?,
        departureStart: Date?,
        windowMinutes: Int,
        limit: Int
    ) async throws -> NearbyStationSearchResponse {
        if let nearbyResponse {
            return nearbyResponse
        }
        return NearbyStationSearchResponse(
            stations: Array(PreviewFixtures.nearbyStations.prefix(limit)),
            generatedAt: PreviewFixtures.baseDate,
            sourceFreshness: StationMetadataFreshness(status: "fresh", lastSuccessfulImportAt: PreviewFixtures.baseDate, unavailableReason: nil)
        )
    }

    func recommendDirectWindow(originCRS: String, destinationCRS: String, departureStart: Date, windowMinutes: Int) async throws -> DirectWindowRecommendationResponse {
        let window = activeWindow ?? PreviewFixtures.activeWindow
        return DirectWindowRecommendationResponse(
            topRecommendation: window.selectedRecommendation,
            recommendations: window.recommendations
        )
    }

    func planJourney(originCRS: String, destinationCRS: String, departureStart: Date, windowMinutes: Int, maxChanges: Int, limit: Int) async throws -> JourneyPlanResponse {
        let itinerary = activeItinerary ?? PreviewFixtures.activeItinerary()
        return JourneyPlanResponse(
            topItinerary: itinerary.selectedItinerary,
            itineraries: itinerary.itineraries,
            timetableId: "preview",
            generatedAt: PreviewFixtures.iso(minutesFromBase: 0)
        )
    }

    func getJourneyDetail(serviceID: Int, originTPL: String?, destinationTPL: String?) async throws -> JourneyDetail {
        PreviewFixtures.journeyDetail(
            serviceID: serviceID,
            originTPL: originTPL,
            destinationTPL: destinationTPL
        )
    }

    func createWindowSubscription(input: CreateWindowSubscriptionRequest, accessToken: String) async throws -> WindowSubscription {
        var window = activeWindow ?? PreviewFixtures.activeWindow
        if let selectedTrainServiceId = input.selectedTrainServiceId {
            window.pinnedTrainServiceId = selectedTrainServiceId
            let recommendations = [window.selectedRecommendation] + window.recommendations
            if let selected = recommendations.first(where: { $0.journey.serviceId == selectedTrainServiceId }) {
                window.selectedRecommendation = selected
            }
        }
        return window
    }

    func createItinerarySubscription(input: CreateItinerarySubscriptionRequest, accessToken: String) async throws -> ItinerarySubscription {
        var itinerary = activeItinerary ?? PreviewFixtures.activeItinerary()
        if let selectedStableKey = input.selectedItineraryStableKey,
           let selected = itinerary.itineraries.first(where: { $0.stableKey == selectedStableKey }) {
            itinerary.selectedItinerary = selected
        }
        return itinerary
    }
    func createJourneyShare(input: CreateJourneyShareRequest, accessToken: String) async throws -> JourneyShareResponse {
        JourneyShareResponse(
            shareId: "preview-share",
            shareUrl: "https://righttrain.app/j/preview-share",
            appUrl: "righttrain://journey-shares/preview-share",
            expiresAt: PreviewFixtures.baseDate.addingTimeInterval(3 * 60 * 60)
        )
    }
    func getJourneyShare(id: String) async throws -> PublicJourneyShare {
        if id == "preview-missing-share" {
            throw APIError.server(statusCode: 404, code: nil, message: "Shared journey not found", details: [:])
        }
        let journey = (activeWindow ?? PreviewFixtures.activeWindow).selectedRecommendation.journey
        var share = PublicJourneyShare(
            shareId: id,
            kind: "window",
            routeTitle: "\(journey.originName) to \(journey.destinationName)",
            status: journey.status,
            statusText: journey.statusText ?? journey.displayStatus,
            originName: journey.originName,
            originCrs: journey.originCrs,
            destinationName: journey.destinationName,
            destinationCrs: journey.destinationCrs,
            scheduledDeparture: PreviewFixtures.baseDate.addingTimeInterval(-8 * 60),
            scheduledArrival: PreviewFixtures.baseDate.addingTimeInterval(32 * 60),
            expectedDeparture: PreviewFixtures.baseDate.addingTimeInterval(-8 * 60),
            expectedArrival: PreviewFixtures.baseDate.addingTimeInterval(36 * 60),
            currentPosition: JourneySharePosition(
                description: "Between Eastfield and Northbridge",
                progress: 0.42,
                currentStopName: "Eastfield",
                upcomingStopName: "Northbridge"
            ),
            legs: [],
            disruptions: journey.lateReasonText.map { [$0] },
            refreshedAt: PreviewFixtures.baseDate,
            expiresAt: PreviewFixtures.baseDate.addingTimeInterval(3 * 60 * 60),
            appUrl: "righttrain://journey-shares/\(id)",
            appStoreUrl: nil
        )
        if id == "preview-expired-share" {
            share.refreshedAt = PreviewFixtures.baseDate.addingTimeInterval(-2 * 60 * 60)
            share.expiresAt = PreviewFixtures.baseDate.addingTimeInterval(-10 * 60)
        }
        return share
    }
    func getWindowSubscription(id: String, accessToken: String) async throws -> WindowSubscription {
        guard let activeWindow else { throw previewNotFound }
        return activeWindow
    }
    func getActiveWindowSubscription(accessToken: String) async throws -> WindowSubscription {
        guard let activeWindow else { throw previewNotFound }
        return activeWindow
    }
    func getActiveItinerarySubscription(accessToken: String) async throws -> ItinerarySubscription {
        guard let activeItinerary else { throw previewNotFound }
        return activeItinerary
    }
    func getItinerarySubscription(id: String, accessToken: String) async throws -> ItinerarySubscription {
        guard let activeItinerary else { throw previewNotFound }
        return activeItinerary
    }
    func pinItineraryFirstLeg(id: String, input: PinItineraryFirstLegRequest, accessToken: String, idempotencyKey: String? = nil) async throws -> ItinerarySubscription { throw PreviewError.unavailable }
    func clearItineraryPinnedFirstLeg(id: String, accessToken: String, idempotencyKey: String? = nil) async throws -> ItinerarySubscription { throw PreviewError.unavailable }
    func reportItineraryOriginArrival(id: String, accessToken: String, idempotencyKey: String? = nil) async throws -> ItinerarySubscription { throw PreviewError.unavailable }
    func reportItineraryInterchangeArrival(id: String, atCrs: String, legIndex: Int, accessToken: String, idempotencyKey: String? = nil) async throws -> ItinerarySubscription { throw PreviewError.unavailable }
    func boardItineraryLeg(id: String, legIndex: Int, pinFirstLeg: Bool, accessToken: String, idempotencyKey: String? = nil) async throws -> ItinerarySubscription { throw PreviewError.unavailable }
    func replanItineraryFromCurrentStation(id: String, fromCrs: String, accessToken: String, idempotencyKey: String? = nil) async throws -> ItinerarySubscription { throw PreviewError.unavailable }
    func pinWindowSubscriptionTrain(id: String, serviceID: Int, accessToken: String, idempotencyKey: String? = nil) async throws -> WindowSubscription {
        var window = activeWindow ?? PreviewFixtures.activeWindow
        window.pinnedTrainServiceId = serviceID
        let recommendations = [window.selectedRecommendation] + window.recommendations
        if let selected = recommendations.first(where: { $0.journey.serviceId == serviceID }) {
            window.selectedRecommendation = selected
        }
        return window
    }

    func clearWindowSubscriptionPinnedTrain(id: String, accessToken: String, idempotencyKey: String? = nil) async throws -> WindowSubscription {
        var window = activeWindow ?? PreviewFixtures.activeWindow
        window.pinnedTrainServiceId = nil
        return window
    }
    func getWindowSubscriptionNotification(windowSubscriptionID: String, notificationID: String, accessToken: String) async throws -> WindowSubscriptionNotificationDetail {
        guard let windowNotificationDetail else {
            throw PreviewError.unavailable
        }
        return windowNotificationDetail
    }

    func streamWindowSubscriptionEvents(windowSubscriptionID: String, accessToken: String, lastEventID: String?) -> AsyncThrowingStream<SubscriptionStreamEvent, Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func streamItinerarySubscriptionEvents(itinerarySubscriptionID: String, accessToken: String, lastEventID: String?) -> AsyncThrowingStream<SubscriptionStreamEvent, Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func deleteWindowSubscription(id: String, accessToken: String, idempotencyKey: String? = nil) async throws {}
    func deleteItinerarySubscription(id: String, accessToken: String, idempotencyKey: String? = nil) async throws {}
    func listCommuteRoutines(accessToken: String) async throws -> [CommuteRoutine] { routines }
    func createCommuteRoutine(input: CommuteRoutineMutationRequest, accessToken: String) async throws -> CommuteRoutine { routines[0] }
    func updateCommuteRoutine(id: String, input: CommuteRoutineMutationRequest, accessToken: String) async throws -> CommuteRoutine { routines[0] }
    func deleteCommuteRoutine(id: String, accessToken: String) async throws {}
    func registerLiveActivityToken(windowSubscriptionID: String, activityKind: String, input: RegisterLiveActivityTokenRequest, accessToken: String) async throws {}
    func registerItineraryLiveActivityToken(itinerarySubscriptionID: String, activityKind: String, input: RegisterLiveActivityTokenRequest, accessToken: String) async throws {}
    func registerLiveActivityPushToStartToken(clientDeviceID: String, input: RegisterLiveActivityTokenRequest, accessToken: String) async throws {}
    func deleteLiveActivityPushToStartToken(clientDeviceID: String, activityID: String, environment: String?, accessToken: String) async throws {}
    func deleteLiveActivityToken(windowSubscriptionID: String, activityKind: String, activityID: String, environment: String?, accessToken: String) async throws {}
    func deleteItineraryLiveActivityToken(itinerarySubscriptionID: String, activityKind: String, activityID: String, environment: String?, accessToken: String) async throws {}
    func registerAPNsAlertToken(clientDeviceID: String, input: RegisterAPNsAlertTokenRequest, accessToken: String) async throws {}
    func deleteAPNsAlertToken(clientDeviceID: String, environment: String?, accessToken: String) async throws {}

    private var previewNotFound: APIError {
        APIError.server(statusCode: 404, code: nil, message: "No preview Pin", details: [:])
    }
}

#if DEBUG
struct PreviewNotificationPermissionReviewScreen: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: RTSpacing.sectionGap) {
                    VStack(alignment: .leading, spacing: RTSpacing.compact) {
                        StatusPill(text: "Alerts blocked", tone: .red)
                        Text("Keep monitoring in the app")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(Color.rightTrainInk)
                        Text("RightTrain can still watch the journey. Re-enable alerts when you want action-needed changes to interrupt you outside the app.")
                            .font(.body)
                            .foregroundStyle(Color.rightTrainInk.opacity(0.68))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    NotificationPermissionView()
                }
                .padding(.horizontal, RTSpacing.pageHorizontal)
                .padding(.top, RTSpacing.pageVertical)
                .padding(.bottom, RTSpacing.bottomSafeArea)
            }
            .background(Color.rightTrainSurfaceCream.ignoresSafeArea())
            .lightSurfaceForeground()
            .toolbarColorScheme(.light, for: .navigationBar)
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
        }
        .environment(\.colorScheme, .light)
    }
}

struct PreviewOnboardingReviewScreen: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: RTSpacing.sectionGap) {
                    AppHeader(surface: .neutral)
                    BetaOnboardingView(forceExpanded: true)
                }
                .padding(.horizontal, RTSpacing.pageHorizontal)
                .padding(.top, RTSpacing.pageVertical)
                .padding(.bottom, RTSpacing.bottomSafeArea)
            }
            .background(Color.rightTrainSurfaceCream.ignoresSafeArea())
            .lightSurfaceForeground()
            .toolbarColorScheme(.light, for: .navigationBar)
            .navigationTitle("Onboarding")
            .navigationBarTitleDisplayMode(.inline)
        }
        .environment(\.colorScheme, .light)
    }
}

struct PreviewFeedbackReviewScreen: View {
    private let supportURL = URL(string: "mailto:support@righttrain.app")!

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: RTSpacing.sectionGap) {
                    VStack(alignment: .leading, spacing: RTSpacing.compact) {
                        StatusPill(text: "Feedback", tone: .accent)
                        Text("Tell us what the live feed got wrong")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(Color.rightTrainInk)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Journey feedback works best with the route, train time, platform, and what RightTrain showed when you made a decision.")
                            .font(.body)
                            .foregroundStyle(Color.rightTrainInk.opacity(0.68))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: RTSpacing.compact) {
                        SectionHeader(
                            title: "What to include",
                            subtitle: "Route, station code if you have it, departure time, platform, and whether the app was late, stale, or wrong.",
                            tone: .accent
                        )
                        Link(destination: supportURL) {
                            Label("Email RightTrain support", systemImage: "envelope")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color.rightTrainOnAccent)
                                .frame(maxWidth: .infinity)
                                .frame(height: RTSize.buttonHeight)
                                .background(Color.rightTrainActionInk, in: RoundedRectangle(cornerRadius: RTRadius.button))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(RTSpacing.cardPadding)
                    .background(Color.rightTrainPaperCream, in: RoundedRectangle(cornerRadius: RTRadius.card))
                    .overlay {
                        RoundedRectangle(cornerRadius: RTRadius.card)
                            .stroke(Color.rightTrainActionInk.opacity(0.18), lineWidth: 1)
                    }
                }
                .padding(.horizontal, RTSpacing.pageHorizontal)
                .padding(.top, RTSpacing.pageVertical)
                .padding(.bottom, RTSpacing.bottomSafeArea)
            }
            .background(Color.rightTrainSurfaceCream.ignoresSafeArea())
            .lightSurfaceForeground()
            .toolbarColorScheme(.light, for: .navigationBar)
            .navigationTitle("Feedback")
            .navigationBarTitleDisplayMode(.inline)
        }
        .environment(\.colorScheme, .light)
    }
}

@MainActor
struct PreviewStationPickerReviewScreen: View {
    var surface: RightTrainPreviewLaunch.Surface

    var body: some View {
        NavigationStack {
            StationPickerView(
                context: context,
                apiClient: apiClient,
                favourites: favourites,
                locationProvider: locationProvider,
                initialChoice: initialChoice,
                initialQuery: initialQuery
            ) { _ in }
        }
        .environment(\.colorScheme, .light)
    }

    private var context: StationPickerContext {
        StationPickerContext(
            selectionRole: selectionRole,
            routeMode: routeMode,
            selectedCounterpartCRS: selectedCounterpartCRS,
            departureStart: PreviewFixtures.baseDate,
            windowMinutes: 120,
            sourceSurface: .journeySetup,
            previousSelection: previousSelection
        )
    }

    private var selectionRole: StationPickerSelectionRole {
        switch surface {
        case .stationPickerSelectedDestination, .stationPickerCancelBack:
            return .destination
        default:
            return .origin
        }
    }

    private var routeMode: StationPickerRouteMode {
        surface == .stationPickerCancelBack ? .anyRoute : .direct
    }

    private var selectedCounterpartCRS: String? {
        selectionRole == .destination ? "EUS" : "MAN"
    }

    private var previousSelection: StationSuggestion? {
        switch surface {
        case .stationPickerSelectedOrigin:
            return PreviewFixtures.stations[0]
        case .stationPickerSelectedDestination, .stationPickerCancelBack:
            return PreviewFixtures.stations[1]
        default:
            return nil
        }
    }

    private var initialChoice: StationPickerSource {
        switch surface {
        case .stationPickerFavourites, .stationPickerNoFavourites:
            return .favourites
        case .stationPickerNearestLoading, .stationPickerNearestResults, .stationPickerLocationDenied, .stationPickerNearbyUnavailable:
            return .nearest
        default:
            return .search
        }
    }

    private var initialQuery: String {
        switch surface {
        case .stationPickerSearch:
            return "London"
        case .stationPickerCancelBack:
            return "Cre"
        default:
            return ""
        }
    }

    private var favourites: [StationFavourite] {
        surface == .stationPickerNoFavourites ? [] : PreviewFixtures.stationFavourites
    }

    private var apiClient: PreviewAPIClient {
        switch surface {
        case .stationPickerNearbyUnavailable:
            return PreviewAPIClient(nearbyResponse: NearbyStationSearchResponse(
                stations: [],
                generatedAt: PreviewFixtures.baseDate,
                sourceFreshness: StationMetadataFreshness(
                    status: "unavailable",
                    lastSuccessfulImportAt: PreviewFixtures.baseDate.addingTimeInterval(-90 * 60),
                    unavailableReason: "station_metadata_stale"
                )
            ))
        default:
            return PreviewFixtures.previewAPIClient
        }
    }

    private var locationProvider: PreviewStationLocationProvider {
        switch surface {
        case .stationPickerNearestLoading:
            return PreviewStationLocationProvider(delayNanoseconds: 8_000_000_000)
        case .stationPickerLocationDenied:
            return PreviewStationLocationProvider(result: .failure(StationLocationProviderError.denied))
        default:
            return PreviewStationLocationProvider()
        }
    }
}

@MainActor
struct RightTrainPreviewLaunch {
    enum Surface: String {
        case signedOut
        case empty
        case plan
        case window
        case journey
        case onboard
        case search
        case itinerarySearch
        case itinerarySearchPinned
        case searchPinned
        case commute
        case settings
        case itinerary
        case itineraryPlanning
        case itineraryFinal
        case platformUnknown
        case platformChanged
        case staleData
        case offline
        case cancelled
        case sharedJourney
        case firstScreenManual
        case firstScreenDirect
        case firstScreenItinerary
        case firstScreenStale
        case firstScreenOffline
        case us2SetupManual
        case us2SetupRoutine
        case us2SetupDirect
        case us2SetupConnection
        case us2ResultsDirect
        case us2ResultsChanges
        case us3PushPlatformChange
        case us3PushUnavailable
        case us3PermissionDenied
        case us4Onboarding
        case us4SignedOut
        case us4Settings
        case us4Feedback
        case us4JourneyDetail
        case us4SharedJourney
        case us4SharedExpired
        case us4SharedUnavailable
        case stationPickerSearch
        case stationPickerSelectedOrigin
        case stationPickerSelectedDestination
        case stationPickerCancelBack
        case stationPickerFavourites
        case stationPickerNoFavourites
        case stationPickerNearestLoading
        case stationPickerNearestResults
        case stationPickerLocationDenied
        case stationPickerNearbyUnavailable
    }

    var surface: Surface

    init?(arguments: [String]) {
        guard arguments.contains("--righttrain-preview") else {
            return nil
        }
        let rawSurface = arguments
            .first { $0.hasPrefix("--righttrain-preview-surface=") }
            .flatMap { $0.split(separator: "=", maxSplits: 1).last }
            .map(String.init)
        surface = rawSurface.flatMap(Surface.init(rawValue:)) ?? .window
    }

    func makeAppCoordinator() -> AppCoordinator {
        let coordinator = PreviewFixtures.makeAppCoordinator(
            signedIn: !usesSignedOutSession,
            activeWindow: activeWindow,
            activeItinerary: activeItinerary,
            multiLegRoutingEnabled: multiLegRoutingEnabled,
            notificationStatus: notificationStatus,
            windowNotificationDetail: windowNotificationDetail
        )
        coordinator.selectedTab = selectedTab
#if DEBUG
        if opensPlanSearchResults {
            coordinator.debugInitialPlanRoute = .searchResults
        }
#endif
        return coordinator
    }

    var usesNotificationPermissionReview: Bool {
        surface == .us3PermissionDenied
    }

    var usesOnboardingReview: Bool {
        surface == .us4Onboarding
    }

    var usesFeedbackReview: Bool {
        surface == .us4Feedback
    }

    var stationPickerReviewSurface: Surface? {
        switch surface {
        case .stationPickerSearch, .stationPickerSelectedOrigin, .stationPickerSelectedDestination,
                .stationPickerCancelBack, .stationPickerFavourites, .stationPickerNoFavourites,
                .stationPickerNearestLoading, .stationPickerNearestResults, .stationPickerLocationDenied,
                .stationPickerNearbyUnavailable:
            return surface
        default:
            return nil
        }
    }

    private var usesSignedOutSession: Bool {
        switch surface {
        case .signedOut, .sharedJourney, .us4SignedOut, .us4SharedJourney, .us4SharedExpired, .us4SharedUnavailable:
            return true
        default:
            return false
        }
    }

    func prepare(_ coordinator: AppCoordinator) async {
        switch surface {
        case .search, .searchPinned, .itinerarySearch, .itinerarySearchPinned, .us2ResultsDirect, .us2ResultsChanges:
            coordinator.origin = PreviewFixtures.stations[0]
            coordinator.destination = PreviewFixtures.stations[1]
            coordinator.departureStart = PreviewFixtures.baseDate
            coordinator.windowMinutes = 120
            coordinator.windowSetupViewModel.applyAppCapabilities(AppCapabilitiesResponse(multiLegRoutingEnabled: multiLegRoutingEnabled))
            coordinator.directRoutesOnly = surface != .itinerarySearch &&
                surface != .itinerarySearchPinned &&
                surface != .us2ResultsChanges
            await coordinator.loadRecommendations()
        case .us2SetupRoutine:
            coordinator.windowSetupViewModel.applyRoutinePrefill(
                PreviewFixtures.commuteRoutines[0],
                originStation: PreviewFixtures.stations[0],
                destinationStation: PreviewFixtures.stations[1],
                now: PreviewFixtures.baseDate
            )
        case .us2SetupDirect:
            coordinator.windowSetupViewModel.selectSetupIntent(.oneOffDirect)
            coordinator.origin = PreviewFixtures.stations[0]
            coordinator.destination = PreviewFixtures.stations[1]
            coordinator.departureStart = PreviewFixtures.baseDate
            coordinator.windowMinutes = 120
        case .us2SetupConnection:
            coordinator.windowSetupViewModel.applyAppCapabilities(AppCapabilitiesResponse(multiLegRoutingEnabled: true))
            coordinator.windowSetupViewModel.selectSetupIntent(.connectionSensitive)
            coordinator.origin = PreviewFixtures.stations[0]
            coordinator.destination = PreviewFixtures.stations[1]
            coordinator.departureStart = PreviewFixtures.baseDate
            coordinator.windowMinutes = 180
        case .offline, .firstScreenOffline:
            coordinator.connectivityService.recordBackendFailure(PreviewError.unavailable)
            coordinator.connectivityService.recordBackendFailure(PreviewError.unavailable)
        case .sharedJourney:
            if let url = URL(string: "righttrain://journey-shares/preview-share") {
                await coordinator.openDeepLink(url)
            }
        case .us4JourneyDetail:
            if let url = URL(string: "righttrain://journeys/\(PreviewFixtures.onBoardWindow.selectedRecommendation.journey.serviceId)") {
                await coordinator.openDeepLink(url)
            }
        case .us4SharedJourney:
            if let url = URL(string: "righttrain://journey-shares/preview-share") {
                await coordinator.openDeepLink(url)
            }
        case .us4SharedExpired:
            if let url = URL(string: "righttrain://journey-shares/preview-expired-share") {
                await coordinator.openDeepLink(url)
            }
        case .us4SharedUnavailable:
            if let url = URL(string: "righttrain://journey-shares/preview-missing-share") {
                await coordinator.openDeepLink(url)
            }
        case .us3PushPlatformChange:
            if let url = URL(string: "righttrain://windows/direct/subscriptions/\(PreviewFixtures.platformChangedWindow.id)/notifications/\(PreviewFixtures.platformChangeNotificationDetail.id)") {
                await coordinator.openDeepLink(url)
            }
        case .us3PushUnavailable:
            if let url = URL(string: "righttrain://windows/direct/subscriptions/missing-window/notifications/missing-notification") {
                await coordinator.openDeepLink(url)
            }
        default:
            return
        }
    }

    private var multiLegRoutingEnabled: Bool {
        surface == .itinerarySearch ||
            surface == .itinerarySearchPinned ||
            surface == .us2SetupConnection ||
            surface == .us2ResultsChanges
    }

    private var selectedTab: AppTab {
        switch surface {
        case .plan, .search, .searchPinned, .itinerarySearch, .itinerarySearchPinned,
                .us2SetupManual, .us2SetupRoutine, .us2SetupDirect, .us2SetupConnection,
                .us2ResultsDirect, .us2ResultsChanges:
            return .plan
        case .commute:
            return .commutes
        case .settings:
            return .settings
        case .us4Settings:
            return .settings
        case .us3PermissionDenied:
            return .settings
        default:
            return .active
        }
    }

    private var opensPlanSearchResults: Bool {
        switch surface {
        case .search, .searchPinned, .itinerarySearch, .itinerarySearchPinned, .us2ResultsDirect, .us2ResultsChanges:
            return true
        default:
            return false
        }
    }

    private var activeWindow: WindowSubscription? {
        switch surface {
        case .signedOut, .us4SignedOut, .empty, .plan, .itinerary, .itineraryPlanning, .itineraryFinal, .search, .itinerarySearch, .itinerarySearchPinned, .settings, .us4Settings, .sharedJourney, .us4SharedJourney, .us4SharedExpired, .us4SharedUnavailable, .firstScreenManual, .firstScreenItinerary, .us2SetupManual, .us2SetupRoutine, .us2SetupDirect, .us2SetupConnection, .us2ResultsDirect, .us2ResultsChanges, .us3PermissionDenied, .us3PushUnavailable, .us4Onboarding, .us4Feedback:
            return nil
        case .us4JourneyDetail:
            return PreviewFixtures.journeyPinnedWindow
        case .us3PushPlatformChange:
            return PreviewFixtures.platformChangedWindow
        case .platformUnknown:
            return PreviewFixtures.platformUnknownWindow
        case .platformChanged:
            return PreviewFixtures.platformChangedWindow
        case .staleData, .firstScreenStale:
            return PreviewFixtures.staleDataWindow
        case .offline, .firstScreenOffline:
            return PreviewFixtures.offlineWindow
        case .cancelled:
            return PreviewFixtures.cancelledWindow
        case .onboard:
            return PreviewFixtures.onBoardWindow
        case .journey, .searchPinned:
            return PreviewFixtures.journeyPinnedWindow
        case .firstScreenDirect:
            return PreviewFixtures.activeWindow
        default:
            return PreviewFixtures.activeWindow
        }
    }

    private var activeItinerary: ItinerarySubscription? {
        switch surface {
        case .firstScreenItinerary:
            return PreviewFixtures.activeItinerary(phase: .planning)
        case .itineraryPlanning:
            return PreviewFixtures.activeItinerary(phase: .planning)
        case .itineraryFinal:
            return PreviewFixtures.activeItinerary(phase: .onFinalLeg, currentLegIndex: 1)
        case .itinerary:
            return PreviewFixtures.activeItinerary(phase: .approachingInterchange)
        case .itinerarySearchPinned:
            return PreviewFixtures.activeItinerary(phase: .planning)
        default:
            return nil
        }
    }

    private var notificationStatus: UNAuthorizationStatus {
        surface == .us3PermissionDenied ? .denied : .notDetermined
    }

    private var windowNotificationDetail: WindowSubscriptionNotificationDetail? {
        surface == .us3PushPlatformChange ? PreviewFixtures.platformChangeNotificationDetail : nil
    }
}
#endif

@MainActor
private struct PreviewStoreKitSubscriptionService: StoreKitSubscriptionServicing {
    func loadProducts(_ billingProducts: [BillingProduct]) async throws -> [SubscriptionProduct] {
        billingProducts.map {
            SubscriptionProduct(
                productID: $0.productId,
                displayName: $0.period.humanizedIdentifier,
                displayPrice: $0.period == "annual" ? "£19.99" : "£2.99",
                period: $0.period
            )
        }
    }

    func purchase(productID: String, appAccountToken: UUID) async throws -> StoreKitPurchaseOutcome { .cancelled }
    func restore(productIDs: [String]) async throws -> [PendingStoreKitTransaction] { [] }
    func currentEntitlements(productIDs: [String]) async -> [PendingStoreKitTransaction] { [] }
    func transactionUpdates(productIDs: [String]) -> AsyncStream<PendingStoreKitTransaction> { AsyncStream { $0.finish() } }
    func finishTransactions(ids: [UInt64]) async {}
    func openManageSubscriptions() async {}
}

private enum PreviewError: Error {
    case unavailable
}
