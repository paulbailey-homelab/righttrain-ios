@testable import RightTrain
import Foundation
import XCTest

final class AppModelTests: XCTestCase {
    override func setUp() {
        super.setUp()
        resetAppModelDefaults()
    }

    override func tearDown() {
        resetAppModelDefaults()
        super.tearDown()
    }

    @MainActor
    func testBootstrapFlagClearsAfterStartupCompletes() async {
        let model = makeModel()

        XCTAssertTrue(model.isBootstrapping)

        await model.bootstrap()

        XCTAssertFalse(model.isBootstrapping)
    }

    @MainActor
    func testForegroundRefreshFlushesStaleConnectionsFirst() async {
        let apiClient = FakeAPIClient()
        let model = makeModel(apiClient: apiClient)

        await model.refreshConnectivityAndFlushQueuedMutations()

        XCTAssertEqual(
            apiClient.resetPooledConnectionsCallCount,
            1,
            "Foreground refresh should drop stale pooled connections before probing the backend"
        )
    }

    @MainActor
    func testSwapStationsReversesRouteAndClearsResults() {
        let model = makeModel()
        let setup = model.windowSetupViewModel
        let origin = TestFactory.station(crs: "EUS", name: "London Euston")
        let destination = TestFactory.station(crs: "MAN", name: "Manchester Piccadilly")
        setup.origin = origin
        setup.destination = destination

        setup.swapStations()

        XCTAssertEqual(setup.origin, destination)
        XCTAssertEqual(setup.destination, origin)
        XCTAssertNil(setup.recommendationResponse)
        XCTAssertNil(setup.journeyPlanResponse)
    }

    @MainActor
    func testStationPickerContextPreservesSetupState() {
        let model = makeModel()
        let setup = model.windowSetupViewModel
        let origin = TestFactory.station(crs: "EUS", name: "London Euston")
        let destination = TestFactory.station(crs: "MAN", name: "Manchester Piccadilly")
        let replacement = TestFactory.station(crs: "CRE", name: "Crewe")
        let departure = Date(timeIntervalSince1970: 1_781_621_600)
        setup.applyAppCapabilities(AppCapabilitiesResponse(multiLegRoutingEnabled: true))
        setup.origin = origin
        setup.destination = destination
        setup.departureStart = departure
        setup.windowMinutes = 180
        setup.setSearchMode(.anyRoute)

        let context = setup.stationPickerContext(for: .destination)
        setup.applyStationPickerSelection(replacement, role: .destination)

        XCTAssertEqual(context.selectionRole, .destination)
        XCTAssertEqual(context.routeMode, .anyRoute)
        XCTAssertEqual(context.selectedCounterpartCRS, "EUS")
        XCTAssertEqual(context.departureStart, departure)
        XCTAssertEqual(context.windowMinutes, 180)
        XCTAssertEqual(context.previousSelection, destination)
        XCTAssertEqual(setup.origin, origin)
        XCTAssertEqual(setup.destination, replacement)
        XCTAssertEqual(setup.departureStart, departure)
        XCTAssertEqual(setup.windowMinutes, 180)
        XCTAssertFalse(setup.directRoutesOnly)
    }

    @MainActor
    func testStationPickerRejectsSameCRSCommit() {
        let viewModel = StationPickerViewModel(
            context: StationPickerContext(
                selectionRole: .destination,
                routeMode: .direct,
                selectedCounterpartCRS: "EUS",
                departureStart: Date(),
                windowMinutes: 120,
                sourceSurface: .journeySetup,
                previousSelection: nil
            ),
            apiClient: FakeAPIClient(),
            favourites: [],
            locationProvider: FakeStationLocationProvider()
        )

        XCTAssertFalse(viewModel.commit(TestFactory.station(crs: "EUS", name: "London Euston")))
        XCTAssertEqual(viewModel.validationMessage, "Origin and destination cannot both be EUS.")
    }

    @MainActor
    func testDirectDestinationPickerExplainsDirectOnlyResults() async {
        let apiClient = FakeAPIClient()
        apiClient.directDestinationStationResult = .success([])
        let viewModel = StationPickerViewModel(
            context: StationPickerContext(
                selectionRole: .destination,
                routeMode: .direct,
                selectedCounterpartCRS: "EUS",
                departureStart: Date(),
                windowMinutes: 120,
                sourceSurface: .journeySetup,
                previousSelection: nil
            ),
            apiClient: apiClient,
            favourites: [],
            locationProvider: FakeStationLocationProvider(),
            initialQuery: "York"
        )

        await viewModel.loadSearchIfNeeded()

        XCTAssertEqual(
            viewModel.directDestinationNote,
            "Only stations with a direct train from EUS are shown. Journeys that need a change aren't supported yet."
        )
        XCTAssertEqual(
            viewModel.loadingState,
            .empty("No station matching YORK has a direct train from EUS in this window.")
        )
    }

    @MainActor
    func testCancelledNearestLoadDoesNotShowFailure() async {
        let apiClient = FakeAPIClient()
        apiClient.nearbyStationResult = .failure(URLError(.cancelled))
        let viewModel = StationPickerViewModel(
            context: StationPickerContext(
                selectionRole: .origin,
                routeMode: .direct,
                selectedCounterpartCRS: nil,
                departureStart: nil,
                windowMinutes: 120,
                sourceSurface: .journeySetup,
                previousSelection: nil
            ),
            apiClient: apiClient,
            favourites: [],
            locationProvider: FakeStationLocationProvider(),
            initialChoice: .nearest
        )

        let load = Task { await viewModel.loadNearest() }
        load.cancel()
        await load.value

        // Switching away from Nearest cancels the load; the next load owns
        // the state, so a cancelled one must not replace it with "Unavailable".
        if case .failed = viewModel.loadingState {
            XCTFail("A cancelled nearest load should not report a failure")
        }
    }

    @MainActor
    func testStationFavoritesDeduplicateByCRS() {
        let favourites = StationFavoritesProvider.favourites(
            homeStationCRS: "eus",
            workStationCRS: "MAN",
            routines: [
                TestFactory.commuteRoutine(id: "routine-1", originCrs: "EUS", destinationCrs: "CRE"),
                TestFactory.commuteRoutine(id: "routine-2", originCrs: "CRE", destinationCrs: "MAN")
            ],
            stationResolver: { TestFactory.station(crs: $0, name: $0) }
        )

        XCTAssertEqual(favourites.map(\.crs), ["EUS", "MAN", "CRE"])
        XCTAssertEqual(Set(favourites.map(\.crs)).count, favourites.count)
    }

    @MainActor
    func testNearestStationsRequestLocationOnlyWhenNearestSelected() async {
        let apiClient = FakeAPIClient()
        apiClient.nearbyStationResult = .success(NearbyStationSearchResponse(
            stations: [TestFactory.station(crs: "EUS", name: "London Euston")],
            generatedAt: Date(timeIntervalSince1970: 0),
            sourceFreshness: StationMetadataFreshness(status: "fresh", lastSuccessfulImportAt: nil, unavailableReason: nil)
        ))
        let locationProvider = FakeStationLocationProvider()
        let viewModel = StationPickerViewModel(
            context: StationPickerContext(
                selectionRole: .origin,
                routeMode: .direct,
                selectedCounterpartCRS: nil,
                departureStart: nil,
                windowMinutes: 120,
                sourceSurface: .journeySetup,
                previousSelection: nil
            ),
            apiClient: apiClient,
            favourites: [],
            locationProvider: locationProvider
        )

        await viewModel.loadSearchIfNeeded()
        await viewModel.loadFavourites()
        XCTAssertEqual(locationProvider.requestCount, 0)

        viewModel.activeChoice = .nearest
        await viewModel.loadNearest()

        XCTAssertEqual(locationProvider.requestCount, 1)
        XCTAssertEqual(apiClient.nearbyStationRequests.count, 1)
        XCTAssertEqual(apiClient.nearbyStationRequests.first?.selectionRole, .origin)
    }

    @MainActor
    func testBootstrapHappyPathRefreshesUserAndLoadsActiveWindow() async {
        let apiClient = FakeAPIClient()
        let sessionStore = FakeSessionStore()
        let liveActivityCoordinator = FakeLiveActivityCoordinator()
        let staleUser = TestFactory.user(id: "stale-user")
        let refreshedUser = TestFactory.user(id: "fresh-user")
        let window = TestFactory.window(id: "active-window")
        sessionStore.session = TestFactory.storedSession(user: staleUser, accessToken: "stored-token")
        apiClient.currentUserResult = .success(refreshedUser)
        apiClient.activeWindowResult = .success(window)

        let model = makeModel(
            apiClient: apiClient,
            sessionStore: sessionStore,
            liveActivityCoordinator: liveActivityCoordinator
        )

        await model.bootstrap()

        XCTAssertEqual(model.notificationStatus, .denied)
        XCTAssertEqual(model.user?.id, "fresh-user")
        XCTAssertEqual(model.activeWindow?.id, "active-window")
        XCTAssertEqual(model.accessToken, "stored-token")
        XCTAssertEqual(sessionStore.savedSessions.last?.user.id, "fresh-user")
        XCTAssertEqual(apiClient.currentUserAccessTokens, ["stored-token"])
        XCTAssertEqual(apiClient.getActiveWindowAccessTokens, ["stored-token"])
        XCTAssertEqual(liveActivityCoordinator.syncCalls.last?.windowID, "active-window")
        XCTAssertTrue(liveActivityCoordinator.syncCalls.last?.hasTokenRegistration == true)
        XCTAssertEqual(liveActivityCoordinator.prepareRemoteStartHasTokenRegistrations, [true])
        XCTAssertNil(model.alertState)
    }

    @MainActor
    func testBootstrapExpiredSessionClearsStoredStateAndLiveActivity() async {
        let apiClient = FakeAPIClient()
        let sessionStore = FakeSessionStore()
        let liveActivityCoordinator = FakeLiveActivityCoordinator()
        sessionStore.session = TestFactory.storedSession(expiresAt: Date().addingTimeInterval(-60))

        let model = makeModel(
            apiClient: apiClient,
            sessionStore: sessionStore,
            liveActivityCoordinator: liveActivityCoordinator
        )

        await model.bootstrap()

        XCTAssertNil(model.user)
        XCTAssertNil(model.accessToken)
        XCTAssertEqual(sessionStore.clearCount, 1)
        XCTAssertEqual(liveActivityCoordinator.endAllCount, 1)
        XCTAssertEqual(liveActivityCoordinator.unregisterRemoteStartHasTokenRegistrations, [false])
        XCTAssertTrue(apiClient.currentUserAccessTokens.isEmpty)
    }

    @MainActor
    func testBootstrapRefreshFailureKeepsStoredSessionAndShowsNetworkAlert() async {
        let apiClient = FakeAPIClient()
        let sessionStore = FakeSessionStore()
        let storedUser = TestFactory.user(id: "stored-user")
        sessionStore.session = TestFactory.storedSession(user: storedUser, accessToken: "stored-token")
        apiClient.currentUserResult = .failure(APIError.transport("offline"))

        let model = makeModel(apiClient: apiClient, sessionStore: sessionStore)

        await model.bootstrap()

        XCTAssertEqual(model.user?.id, "stored-user")
        XCTAssertEqual(model.accessToken, "stored-token")
        XCTAssertEqual(model.alertState, .network("You are signed in, but RightTrain could not refresh your account right now."))
        XCTAssertTrue(sessionStore.savedSessions.isEmpty)
        XCTAssertTrue(apiClient.getActiveWindowAccessTokens.isEmpty)
    }

    @MainActor
    func testBootstrapUnauthorizedRefreshClearsStoredSessionAndLocalState() async {
        let defaults = makeIsolatedDefaults()
        let activeJourneyCache = ActiveJourneyCache(defaults: defaults)
        activeJourneyCache.save(window: TestFactory.window(id: "cached-window", pinnedTrainServiceId: 222))
        let apiClient = FakeAPIClient()
        let sessionStore = FakeSessionStore()
        let liveActivityCoordinator = FakeLiveActivityCoordinator()
        sessionStore.session = TestFactory.storedSession(accessToken: "invalid-token")
        apiClient.currentUserResult = .failure(APIError.server(
            statusCode: 401,
            code: nil,
            message: "session is invalid or expired",
            details: [:]
        ))

        let model = makeModel(
            apiClient: apiClient,
            sessionStore: sessionStore,
            liveActivityCoordinator: liveActivityCoordinator,
            activeJourneyCache: activeJourneyCache
        )

        await model.bootstrap()

        XCTAssertNil(model.user)
        XCTAssertNil(model.accessToken)
        XCTAssertNil(model.activeWindow)
        XCTAssertEqual(sessionStore.clearCount, 1)
        XCTAssertEqual(apiClient.currentUserAccessTokens, ["invalid-token"])
        XCTAssertTrue(apiClient.getActiveWindowAccessTokens.isEmpty)
        XCTAssertEqual(liveActivityCoordinator.endAllCount, 1)
        XCTAssertEqual(model.alertState, .auth(AppOperationState.expiredSessionMessage))
    }

    @MainActor
    func testBootstrapRefreshFailureRestoresCachedActiveJourneyForSignedInSession() async {
        let defaults = makeIsolatedDefaults()
        let activeJourneyCache = ActiveJourneyCache(defaults: defaults)
        let cachedWindow = TestFactory.window(id: "cached-window", pinnedTrainServiceId: 222)
        activeJourneyCache.save(window: cachedWindow)
        let apiClient = FakeAPIClient()
        let sessionStore = FakeSessionStore()
        sessionStore.session = TestFactory.storedSession(accessToken: "offline-token")
        apiClient.currentUserResult = .failure(APIError.transport("offline"))

        let model = makeModel(apiClient: apiClient, sessionStore: sessionStore, activeJourneyCache: activeJourneyCache)

        await model.bootstrap()

        XCTAssertEqual(model.activeWindow?.id, "cached-window")
        XCTAssertEqual(model.pinnedLiveActivityServiceID, 222)
        XCTAssertEqual(model.accessToken, "offline-token")
        XCTAssertTrue(apiClient.getActiveWindowAccessTokens.isEmpty)
    }

    @MainActor
    func testJourneyMutationQueuePersistsAndBacksOffRetries() {
        let suiteName = "righttrain.tests.queue.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let queue = JourneyMutationQueue(defaults: defaults)
        queue.enqueue(JourneyMutation(
            id: "queued-pin",
            kind: .windowPinTrain,
            windowID: "window-1",
            serviceID: 222
        ))

        let reloaded = JourneyMutationQueue(defaults: defaults)

        XCTAssertEqual(reloaded.pendingCount, 1)
        XCTAssertEqual(reloaded.mutations.first?.id, "queued-pin")
        XCTAssertEqual(reloaded.duePendingMutations().map(\.id), ["queued-pin"])

        reloaded.markAttempt(id: "queued-pin")
        reloaded.markDeferred(id: "queued-pin", message: "offline")

        // First-attempt backoff is 5s with deterministic ±20% jitter, so the
        // due time lands somewhere in [4.0, 6.0] seconds after the attempt.
        let delay = reloaded.retryDelay(for: reloaded.mutations[0])
        XCTAssertGreaterThanOrEqual(delay, 4.0)
        XCTAssertLessThanOrEqual(delay, 6.0)
        XCTAssertTrue(reloaded.duePendingMutations(now: Date().addingTimeInterval(3.9)).isEmpty)
        XCTAssertEqual(reloaded.duePendingMutations(now: Date().addingTimeInterval(6.1)).map(\.id), ["queued-pin"])
    }

    @MainActor
    func testJourneyMutationQueuePurgesExpiredMutations() {
        let suiteName = "righttrain.tests.queue.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let queue = JourneyMutationQueue(defaults: defaults)
        var staleFailure = JourneyMutation(
            id: "stale-failure",
            kind: .windowPinTrain,
            windowID: "window-1",
            serviceID: 222
        )
        staleFailure.createdAt = Date().addingTimeInterval(-3 * 24 * 60 * 60)
        queue.enqueue(staleFailure)
        queue.markFailed(id: "stale-failure", message: "conflict")
        queue.enqueue(JourneyMutation(
            id: "fresh-pin",
            kind: .windowPinTrain,
            windowID: "window-1",
            serviceID: 333
        ))

        let reloaded = JourneyMutationQueue(defaults: defaults)

        XCTAssertEqual(reloaded.mutations.map(\.id), ["fresh-pin"])
        XCTAssertFalse(reloaded.needsAttention)
        XCTAssertEqual(reloaded.pendingCount, 1)
    }

    @MainActor
    func testJourneyMutationQueueSurfacesExpiredMutationsAsFailedBeforeHardPurge() {
        let suiteName = "righttrain.tests.queue.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let queue = JourneyMutationQueue(defaults: defaults)
        var agedPin = JourneyMutation(
            id: "aged-pin",
            kind: .windowPinTrain,
            windowID: "window-1",
            serviceID: 222
        )
        // Older than maxMutationAge (24h) but younger than hardPurgeAge (48h):
        // must surface as a visible failure, not vanish.
        agedPin.createdAt = Date().addingTimeInterval(-30 * 60 * 60)
        queue.enqueue(agedPin)

        queue.purgeExpired()

        XCTAssertEqual(queue.mutations.map(\.id), ["aged-pin"])
        XCTAssertTrue(queue.needsAttention)
        XCTAssertEqual(queue.failedCount, 1)
        XCTAssertEqual(queue.mutations.first?.lastError, JourneyMutationQueue.expiredErrorMessage)
        // Expired failures are dismiss-only; retry would replay a stale action.
        XCTAssertEqual(queue.retryableFailedCount, 0)
        queue.retryFailed()
        XCTAssertEqual(queue.failedCount, 1)
    }

    @MainActor
    func testJourneyMutationQueueRetryFailedRestoresPendingForServerRejections() {
        let suiteName = "righttrain.tests.queue.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let queue = JourneyMutationQueue(defaults: defaults)
        queue.enqueue(JourneyMutation(
            id: "rejected-pin",
            kind: .windowPinTrain,
            windowID: "window-1",
            serviceID: 222
        ))
        queue.markFailed(id: "rejected-pin", message: "conflict")

        XCTAssertEqual(queue.retryableFailedCount, 1)

        queue.retryFailed()

        XCTAssertEqual(queue.pendingCount, 1)
        XCTAssertEqual(queue.failedCount, 0)
        XCTAssertNil(queue.mutations.first?.lastError)

        let reloaded = JourneyMutationQueue(defaults: defaults)
        XCTAssertEqual(reloaded.pendingCount, 1)
    }

    @MainActor
    func testActiveJourneyCachePersistsAndPrunesStreamCursors() {
        let defaults = makeIsolatedDefaults()
        let cache = ActiveJourneyCache(defaults: defaults)

        cache.saveStreamCursor("cursor-1", forWindow: "window-1")
        XCTAssertEqual(ActiveJourneyCache(defaults: defaults).streamCursor(forWindow: "window-1"), "cursor-1")

        // Saving for a different window prunes the stale entry.
        cache.saveStreamCursor("cursor-2", forWindow: "window-2")
        XCTAssertNil(cache.streamCursor(forWindow: "window-1"))
        XCTAssertEqual(cache.streamCursor(forWindow: "window-2"), "cursor-2")

        // Itinerary cursors live independently of window cursors.
        cache.saveStreamCursor("it-cursor", forItinerary: "itinerary-1")
        XCTAssertEqual(cache.streamCursor(forWindow: "window-2"), "cursor-2")

        cache.clearWindowStreamCursors()
        XCTAssertNil(cache.streamCursor(forWindow: "window-2"))
        XCTAssertEqual(cache.streamCursor(forItinerary: "itinerary-1"), "it-cursor")

        // clear() drops only the journey snapshot; cursors survive because
        // clear() also runs during window↔itinerary transitions.
        cache.clear()
        XCTAssertEqual(cache.streamCursor(forItinerary: "itinerary-1"), "it-cursor")

        cache.clearItineraryStreamCursors()
        XCTAssertNil(cache.streamCursor(forItinerary: "itinerary-1"))
    }

    @MainActor
    func testStreamReconnectResumesFromPersistedCursor() async {
        let apiClient = FakeAPIClient()
        let sessionStore = FakeSessionStore()
        let window = TestFactory.window(id: "stream-window")
        sessionStore.session = TestFactory.storedSession(accessToken: "stream-token")
        apiClient.currentUserResult = .success(TestFactory.user())
        apiClient.activeWindowResult = .success(window)
        apiClient.windowResult = .success(window)
        let defaults = makeIsolatedDefaults()
        let cache = ActiveJourneyCache(defaults: defaults)
        cache.saveStreamCursor("cursor-42", forWindow: "stream-window")
        let model = makeModel(apiClient: apiClient, sessionStore: sessionStore, activeJourneyCache: cache)
        await model.bootstrap()

        XCTAssertEqual(model.activeWindow?.id, "stream-window")
        // The bootstrap state transitions must not wipe the persisted cursor.
        XCTAssertEqual(cache.streamCursor(forWindow: "stream-window"), "cursor-42")

        let monitorTask = Task { await model.monitorActiveWindowForegroundUpdates() }
        for _ in 0..<100 {
            if !apiClient.streamWindowRequests.isEmpty {
                break
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        monitorTask.cancel()
        await monitorTask.value

        XCTAssertEqual(apiClient.streamWindowRequests.first?.lastEventID, "cursor-42")
    }

    @MainActor
    func testSessionExpiryMidRunInvalidatesSessionAndClearsState() async {
        let apiClient = FakeAPIClient()
        let sessionStore = FakeSessionStore()
        sessionStore.session = TestFactory.storedSession(
            accessToken: "short-token",
            expiresAt: Date().addingTimeInterval(0.2)
        )
        apiClient.currentUserResult = .success(TestFactory.user())
        apiClient.activeWindowResult = .success(TestFactory.window(id: "expiry-window"))
        let model = makeModel(apiClient: apiClient, sessionStore: sessionStore)
        await model.bootstrap()

        XCTAssertTrue(model.isSignedIn)
        // Token still stored but past its window: providers must stop using it.
        try? await Task.sleep(for: .milliseconds(400))
        XCTAssertNil(model.authViewModel.usableAccessToken)

        // The expiry watchdog fires and runs the full invalidation cascade.
        for _ in 0..<50 {
            if !model.isSignedIn {
                break
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertFalse(model.isSignedIn)
        XCTAssertNil(sessionStore.session)
    }

    @MainActor
    func testPendingPinKeepsOptimisticStateWhenRefreshReturnsStaleWindow() async {
        let apiClient = FakeAPIClient()
        let sessionStore = FakeSessionStore()
        let recommendation = TestFactory.recommendation(rank: 1, serviceID: 222)
        let window = TestFactory.window(
            id: "pin-window",
            selectedRecommendation: recommendation,
            recommendations: [recommendation]
        )
        sessionStore.session = TestFactory.storedSession(accessToken: "pin-token")
        apiClient.currentUserResult = .success(TestFactory.user())
        apiClient.activeWindowResult = .success(window)
        // Refresh returns the pre-pin server state; the pin call itself fails
        // so the mutation stays queued.
        apiClient.windowResult = .success(window)
        let model = makeModel(apiClient: apiClient, sessionStore: sessionStore)
        await model.bootstrap()

        await model.activeWindowViewModel.pinTrain(serviceID: 222, windowID: "pin-window")
        XCTAssertEqual(model.activeWindow?.pinnedTrainServiceId, 222)

        await model.refreshActiveWindow(showLoading: false)

        XCTAssertEqual(model.activeWindow?.pinnedTrainServiceId, 222)
    }

    @MainActor
    func testJourneyMutationQueueClearFailedKeepsPendingMutations() {
        let suiteName = "righttrain.tests.queue.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let queue = JourneyMutationQueue(defaults: defaults)
        queue.enqueue(JourneyMutation(
            id: "failed-pin",
            kind: .windowPinTrain,
            windowID: "window-1",
            serviceID: 222
        ))
        queue.markFailed(id: "failed-pin", message: "conflict")
        queue.enqueue(JourneyMutation(
            id: "pending-pin",
            kind: .windowPinTrain,
            windowID: "window-1",
            serviceID: 333
        ))

        queue.clearFailed()

        XCTAssertFalse(queue.needsAttention)
        XCTAssertEqual(queue.mutations.map(\.id), ["pending-pin"])

        let reloaded = JourneyMutationQueue(defaults: defaults)
        XCTAssertEqual(reloaded.mutations.map(\.id), ["pending-pin"])
    }

    @MainActor
    func testOptimisticPinUnauthorizedClearsSessionAndLocalJourneyState() async {
        let first = TestFactory.recommendation(rank: 1, serviceID: 111)
        let second = TestFactory.recommendation(rank: 2, serviceID: 222)
        let window = TestFactory.window(
            id: "offline-window",
            selectedRecommendation: first,
            recommendations: [first, second]
        )
        let apiClient = FakeAPIClient()
        let sessionStore = FakeSessionStore()
        sessionStore.session = TestFactory.storedSession(accessToken: "offline-token")
        apiClient.currentUserResult = .success(TestFactory.user())
        apiClient.activeWindowResult = .success(window)
        apiClient.pinWindowResult = .failure(APIError.server(statusCode: 401, code: nil, message: "unauthorized", details: [:]))
        let model = makeModel(apiClient: apiClient, sessionStore: sessionStore)
        await model.bootstrap()

        await model.pinTrain(serviceID: 222, windowID: "offline-window")
        await waitForAuthInvalidation(model)

        XCTAssertEqual(apiClient.pinWindowRequests.last?.id, "offline-window")
        XCTAssertEqual(apiClient.pinWindowRequests.last?.serviceID, 222)
        XCTAssertEqual(apiClient.pinWindowRequests.last?.accessToken, "offline-token")
        XCTAssertNotNil(apiClient.pinWindowRequests.last?.idempotencyKey)
        XCTAssertNil(model.accessToken)
        XCTAssertNil(model.activeWindow)
        XCTAssertNil(model.pinnedLiveActivityServiceID)
        XCTAssertEqual(model.alertState, .auth(AppOperationState.expiredSessionMessage))
        XCTAssertEqual(model.journeyMutationQueue.pendingCount, 0)
        XCTAssertEqual(model.journeyMutationQueue.failedCount, 0)
    }

    @MainActor
    func testRegisterDeviceSavesSessionAndLoadsActiveWindow() async {
        let apiClient = FakeAPIClient()
        let sessionStore = FakeSessionStore()
        let liveActivityCoordinator = FakeLiveActivityCoordinator()
        let user = TestFactory.user(id: "signed-in-user")
        let window = TestFactory.window(id: "signed-in-window")
        apiClient.registerDeviceResult = .success(TestFactory.authResponse(user: user, accessToken: "new-token"))
        apiClient.activeWindowResult = .success(window)

        let model = makeModel(
            apiClient: apiClient,
            sessionStore: sessionStore,
            liveActivityCoordinator: liveActivityCoordinator
        )

        await model.registerDevice()

        XCTAssertEqual(apiClient.deviceChallengeCallCount, 1)
        XCTAssertEqual(apiClient.registerDeviceRequests.last?.attemptId, "attempt-1")
        XCTAssertEqual(apiClient.registerDeviceRequests.last?.keyId, "fake-key-id")
        XCTAssertFalse(apiClient.registerDeviceRequests.last?.attestationObject.isEmpty ?? true)
        XCTAssertEqual(model.user?.id, "signed-in-user")
        XCTAssertEqual(model.accessToken, "new-token")
        XCTAssertEqual(model.activeWindow?.id, "signed-in-window")
        XCTAssertEqual(sessionStore.savedSessions.last?.user.id, "signed-in-user")
        XCTAssertEqual(liveActivityCoordinator.syncCalls.last?.windowID, "signed-in-window")
        XCTAssertEqual(liveActivityCoordinator.prepareRemoteStartHasTokenRegistrations, [true])
        XCTAssertNil(model.alertState)
    }

    @MainActor
    func testCreatePortableAccountStoresMetadataAndOneTimeRecoveryCode() async {
        let apiClient = FakeAPIClient()
        let sessionStore = FakeSessionStore()
        let credentialService = FakeAccountCredentialService()
        sessionStore.session = TestFactory.storedSession(accessToken: "device-token")
        apiClient.currentUserResult = .success(TestFactory.user(id: "user-123"))
        apiClient.registerAccountResult = .success(TestFactory.registerAccountResponse())
        apiClient.linkedDevicesResult = .success(LinkedDevicesResponse(devices: [TestFactory.linkedDevice()]))
        let model = makeModel(
            apiClient: apiClient,
            sessionStore: sessionStore,
            accountCredentialService: credentialService
        )
        await model.bootstrap()

        let didCreate = await model.authViewModel.createPortableAccount(migrateCurrentDevicePreferences: true)

        XCTAssertTrue(didCreate)
        XCTAssertEqual(credentialService.createCredentialOptions.count, 1)
        XCTAssertEqual(apiClient.registerAccountRequests.last?.accessToken, "device-token")
        XCTAssertTrue(apiClient.registerAccountRequests.last?.input.migrateCurrentDevicePreferences == true)
        XCTAssertEqual(model.authViewModel.portableAccount?.account.state, "active")
        XCTAssertEqual(model.authViewModel.portableAccount?.lastSyncedPreferenceVersion, 1)
        XCTAssertEqual(model.authViewModel.oneTimeRecoveryCode, "shown-once-to-user")
        XCTAssertEqual(model.authViewModel.accountStatusMessage, "Account preferences are ready to use on another device.")
        XCTAssertEqual(sessionStore.session?.portableAccount?.account.state, "active")
        XCTAssertFalse(String(describing: sessionStore.session).contains("shown-once-to-user"))

        model.authViewModel.acknowledgeRecoveryCode()

        XCTAssertNil(model.authViewModel.oneTimeRecoveryCode)
        XCTAssertNotNil(sessionStore.session?.portableAccount?.recovery?.acknowledgedAt)
    }

    @MainActor
    func testCreatePortableAccountFailureLeavesDeviceSessionOnly() async {
        let apiClient = FakeAPIClient()
        let sessionStore = FakeSessionStore()
        sessionStore.session = TestFactory.storedSession(accessToken: "device-token")
        apiClient.currentUserResult = .success(TestFactory.user(id: "user-123"))
        apiClient.registerAccountResult = .failure(APIError.transport("offline"))
        let model = makeModel(apiClient: apiClient, sessionStore: sessionStore)
        await model.bootstrap()

        let didCreate = await model.authViewModel.createPortableAccount()

        XCTAssertFalse(didCreate)
        XCTAssertEqual(model.accessToken, "device-token")
        XCTAssertNil(model.authViewModel.portableAccount)
        XCTAssertNil(sessionStore.session?.portableAccount)
    }

    @MainActor
    func testRestorePortableAccountInstallsSessionAndPreferenceFreshness() async {
        let apiClient = FakeAPIClient()
        let sessionStore = FakeSessionStore()
        let credentialService = FakeAccountCredentialService()
        let restoredUser = TestFactory.user(id: "portable-user")
        apiClient.accountSignInResult = .success(TestFactory.authResponse(user: restoredUser, accessToken: "portable-token"))
        apiClient.accountPreferenceSetResult = .success(TestFactory.accountPreferenceSet(version: 4))
        apiClient.linkedDevicesResult = .success(LinkedDevicesResponse(devices: [TestFactory.linkedDevice()]))
        let model = makeModel(
            apiClient: apiClient,
            sessionStore: sessionStore,
            accountCredentialService: credentialService
        )

        let didRestore = await model.authViewModel.restorePortableAccount()

        XCTAssertTrue(didRestore)
        XCTAssertEqual(credentialService.assertionOptions.count, 1)
        XCTAssertEqual(apiClient.accountSignInRequests.count, 1)
        XCTAssertEqual(model.accessToken, "portable-token")
        XCTAssertEqual(model.user?.id, "portable-user")
        XCTAssertEqual(model.authViewModel.portableAccount?.lastSyncedPreferenceVersion, 4)
        XCTAssertEqual(model.authViewModel.linkedDevices.count, 1)
        XCTAssertEqual(sessionStore.session?.portableAccount?.account.id, "portable-user")
    }

    @MainActor
    func testLinkedDeviceRevocationUpdatesAccountState() async {
        let apiClient = FakeAPIClient()
        let sessionStore = FakeSessionStore()
        sessionStore.session = TestFactory.storedSession(
            accessToken: "portable-token",
            portableAccount: PortableAccountSessionMetadata(
                account: TestFactory.privacyAccount(),
                lastSyncedPreferenceVersion: 1,
                lastSyncedAt: TestFactory.now,
                recovery: nil
            )
        )
        apiClient.currentUserResult = .success(TestFactory.user())
        apiClient.linkedDevicesResult = .success(LinkedDevicesResponse(devices: [
            TestFactory.linkedDevice(id: "linked-device-1", currentDevice: false)
        ]))
        let model = makeModel(apiClient: apiClient, sessionStore: sessionStore)
        await model.bootstrap()

        guard let device = model.authViewModel.linkedDevices.first else {
            return XCTFail("expected linked device")
        }
        await model.authViewModel.revokeLinkedDevice(device)

        XCTAssertEqual(apiClient.revokedLinkedDevices.last?.id, "linked-device-1")
        XCTAssertEqual(apiClient.revokedLinkedDevices.last?.accessToken, "portable-token")
        XCTAssertEqual(model.authViewModel.linkedDevices.first?.state, "revoked")
    }

    @MainActor
    func testExportAndDeletePortableAccountState() async {
        let apiClient = FakeAPIClient()
        let sessionStore = FakeSessionStore()
        sessionStore.session = TestFactory.storedSession(
            accessToken: "portable-token",
            portableAccount: PortableAccountSessionMetadata(
                account: TestFactory.privacyAccount(),
                lastSyncedPreferenceVersion: 1,
                lastSyncedAt: TestFactory.now,
                recovery: nil
            )
        )
        apiClient.currentUserResult = .success(TestFactory.user())
        apiClient.accountExportResult = .success(TestFactory.accountExportResponse())
        let model = makeModel(apiClient: apiClient, sessionStore: sessionStore)
        await model.bootstrap()

        await model.authViewModel.exportPortableAccountData()

        XCTAssertEqual(apiClient.accountExportAccessTokens, ["portable-token"])
        XCTAssertNotNil(model.authViewModel.accountExport)

        let didDelete = await model.deleteAccount()

        XCTAssertTrue(didDelete)
        XCTAssertEqual(apiClient.deleteCurrentUserAccessTokens, ["portable-token"])
        XCTAssertNil(model.authViewModel.portableAccount)
        XCTAssertNil(model.authViewModel.accountExport)
        XCTAssertEqual(sessionStore.clearCount, 1)
    }

    @MainActor
    func testSignInRegistersLiveActivityRemoteStartWithoutActiveWindow() async {
        let apiClient = FakeAPIClient()
        let sessionStore = FakeSessionStore()
        let liveActivityCoordinator = FakeLiveActivityCoordinator()
        apiClient.registerDeviceResult = .success(TestFactory.authResponse(accessToken: "new-token"))
        apiClient.activeWindowResult = .failure(TestFactory.notFoundError())

        let model = makeModel(
            apiClient: apiClient,
            sessionStore: sessionStore,
            liveActivityCoordinator: liveActivityCoordinator
        )

        await model.registerDevice()

        XCTAssertNil(model.activeWindow)
        XCTAssertEqual(liveActivityCoordinator.endAllCount, 1)
        XCTAssertEqual(liveActivityCoordinator.prepareRemoteStartHasTokenRegistrations, [true])
    }

    @MainActor
    func testSignOutUnregistersNotificationsAndClearsLocalState() async {
        let apiClient = FakeAPIClient()
        let sessionStore = FakeSessionStore()
        let liveActivityCoordinator = FakeLiveActivityCoordinator()
        let pushNotificationCoordinator = FakePushNotificationCoordinator()
        let user = TestFactory.user(id: "signed-in-user")
        apiClient.registerDeviceResult = .success(TestFactory.authResponse(user: user, accessToken: "signout-token"))
        apiClient.activeWindowResult = .success(TestFactory.window(id: "signout-window"))
        let model = makeModel(
            apiClient: apiClient,
            sessionStore: sessionStore,
            liveActivityCoordinator: liveActivityCoordinator,
            pushNotificationCoordinator: pushNotificationCoordinator
        )
        await model.registerDevice()

        await model.signOut()

        XCTAssertNil(model.user)
        XCTAssertNil(model.accessToken)
        XCTAssertNil(model.activeWindow)
        XCTAssertNil(model.recommendationResponse)
        XCTAssertEqual(sessionStore.clearCount, 1)
        XCTAssertEqual(pushNotificationCoordinator.unregisterAccessTokens, ["signout-token"])
        XCTAssertEqual(pushNotificationCoordinator.clearLocalStateCount, 1)
        XCTAssertEqual(liveActivityCoordinator.unregisterRemoteStartHasTokenRegistrations, [true])
        XCTAssertEqual(liveActivityCoordinator.endAllCount, 1)
        XCTAssertEqual(liveActivityCoordinator.endAllHasTokenRegistrations, [true])
    }

    @MainActor
    func testSignOutWaitsForLiveActivityTeardownBeforeClearingSession() async {
        let apiClient = FakeAPIClient()
        let sessionStore = FakeSessionStore()
        let liveActivityCoordinator = FakeLiveActivityCoordinator()
        let endAllStarted = expectation(description: "Live Activity teardown started")
        liveActivityCoordinator.pauseEndAll = true
        liveActivityCoordinator.onEndAllStarted = {
            endAllStarted.fulfill()
        }
        apiClient.registerDeviceResult = .success(TestFactory.authResponse(accessToken: "signout-token"))
        apiClient.activeWindowResult = .success(TestFactory.window(id: "signout-window"))
        let model = makeModel(
            apiClient: apiClient,
            sessionStore: sessionStore,
            liveActivityCoordinator: liveActivityCoordinator
        )
        await model.registerDevice()

        let signOutTask = Task {
            await model.signOut()
        }

        await fulfillment(of: [endAllStarted], timeout: 1.0)
        XCTAssertEqual(sessionStore.clearCount, 0)
        XCTAssertNotNil(model.user)

        liveActivityCoordinator.resumeEndAll()
        await signOutTask.value

        XCTAssertEqual(sessionStore.clearCount, 1)
        XCTAssertNil(model.user)
        XCTAssertNil(model.activeWindow)
    }

    @MainActor
    func testSignOutSurfacesSessionClearFailureAndStillClearsUIState() async {
        let apiClient = FakeAPIClient()
        let sessionStore = FakeSessionStore()
        let liveActivityCoordinator = FakeLiveActivityCoordinator()
        apiClient.registerDeviceResult = .success(TestFactory.authResponse(accessToken: "signout-token"))
        apiClient.activeWindowResult = .success(TestFactory.window(id: "signout-window"))
        let model = makeModel(
            apiClient: apiClient,
            sessionStore: sessionStore,
            liveActivityCoordinator: liveActivityCoordinator
        )
        await model.registerDevice()
        sessionStore.clearError = TestFailure.unimplemented

        await model.signOut()

        XCTAssertNil(model.user)
        XCTAssertNil(model.accessToken)
        XCTAssertNil(model.activeWindow)
        XCTAssertEqual(sessionStore.clearCount, 0)
        XCTAssertEqual(liveActivityCoordinator.endAllCount, 1)
        XCTAssertEqual(
            model.alertState,
            .storage("RightTrain could not remove the saved session from this device. Try signing out again before handing off this device.")
        )
    }

    func testAPNsEnvironmentMapsConfiguredValueToBackendRoutingValue() {
        XCTAssertEqual(APNsEnvironment.backendValue(forConfiguredValue: "development", fallback: "production"), "sandbox")
        XCTAssertEqual(APNsEnvironment.backendValue(forConfiguredValue: "sandbox", fallback: "production"), "sandbox")
        XCTAssertEqual(APNsEnvironment.backendValue(forConfiguredValue: "production", fallback: "sandbox"), "production")
        XCTAssertEqual(APNsEnvironment.backendValue(forConfiguredValue: " DEVELOPMENT ", fallback: "production"), "sandbox")
        XCTAssertEqual(APNsEnvironment.backendValue(forConfiguredValue: nil, fallback: "production"), "production")
        XCTAssertEqual(APNsEnvironment.backendValue(forConfiguredValue: "unexpected", fallback: "sandbox"), "sandbox")
    }

    @MainActor
    func testDeleteActiveWindowDeletesRemoteWindowAndClearsLocalWindowState() async {
        let apiClient = FakeAPIClient()
        let sessionStore = FakeSessionStore()
        let liveActivityCoordinator = FakeLiveActivityCoordinator()
        let window = TestFactory.window(id: "delete-window")
        sessionStore.session = TestFactory.storedSession(accessToken: "delete-token")
        apiClient.currentUserResult = .success(TestFactory.user())
        apiClient.activeWindowResult = .success(window)
        apiClient.clearPinnedWindowResult = .success(window)
        let model = makeModel(
            apiClient: apiClient,
            sessionStore: sessionStore,
            liveActivityCoordinator: liveActivityCoordinator
        )
        await model.bootstrap()

        await model.deleteActiveWindow()

        XCTAssertEqual(apiClient.deleteWindowRequests.first?.id, "delete-window")
        XCTAssertEqual(apiClient.deleteWindowRequests.first?.accessToken, "delete-token")
        XCTAssertNil(model.activeWindow)
        XCTAssertNil(model.recommendationResponse)
        XCTAssertNil(model.pinnedLiveActivityServiceID)
        XCTAssertEqual(liveActivityCoordinator.endAllCount, 1)
        XCTAssertEqual(liveActivityCoordinator.endAllHasTokenRegistrations, [true])
    }

    @MainActor
    func testPendingActiveWindowDeletePreventsRefreshFromReapplyingStaleWindow() async {
        let apiClient = FakeAPIClient()
        let sessionStore = FakeSessionStore()
        let window = TestFactory.window(id: "delete-window")
        sessionStore.session = TestFactory.storedSession(accessToken: "delete-token")
        apiClient.currentUserResult = .success(TestFactory.user())
        apiClient.activeWindowResult = .success(window)
        apiClient.deleteWindowError = APIError.transport("offline")
        let model = makeModel(apiClient: apiClient, sessionStore: sessionStore)
        await model.bootstrap()

        await model.deleteActiveWindow()
        await model.refreshActiveWindow(showLoading: false)

        XCTAssertEqual(apiClient.deleteWindowRequests.last?.id, "delete-window")
        XCTAssertNil(model.activeWindow)
        XCTAssertNil(model.pinnedLiveActivityServiceID)
    }

    @MainActor
    func testPendingActiveItineraryDeletePreventsRefreshFromReapplyingStaleItinerary() async {
        let apiClient = FakeAPIClient()
        let sessionStore = FakeSessionStore()
        let itinerary = TestFactory.itinerarySubscription(id: "delete-itinerary")
        sessionStore.session = TestFactory.storedSession(accessToken: "delete-token")
        apiClient.currentUserResult = .success(TestFactory.user())
        apiClient.activeWindowResult = .failure(TestFactory.notFoundError())
        apiClient.activeItineraryResult = .success(itinerary)
        apiClient.deleteItineraryError = APIError.transport("offline")
        let model = makeModel(apiClient: apiClient, sessionStore: sessionStore)
        await model.bootstrap()

        await model.activeWindowViewModel.deleteActiveItinerary()
        await model.refreshActiveWindow(showLoading: false)

        XCTAssertEqual(apiClient.deleteItineraryRequests.last?.id, "delete-itinerary")
        XCTAssertNil(model.activeItinerary)
    }

    @MainActor
    func testLoadRecommendationsHandlesEmptyAndPopulatedResponses() async {
        let apiClient = FakeAPIClient()
        let model = makeModel(apiClient: apiClient)
        model.origin = TestFactory.station(crs: "AAA", name: "Origin")
        model.destination = TestFactory.station(crs: "BBB", name: "Destination")
        model.departureStart = TestFactory.now
        model.windowMinutes = 90
        apiClient.recommendationsResult = .success(TestFactory.emptyRecommendationResponse())

        await model.loadRecommendations()

        XCTAssertEqual(apiClient.recommendationRequests.last?.originCRS, "AAA")
        XCTAssertEqual(apiClient.recommendationRequests.last?.destinationCRS, "BBB")
        XCTAssertEqual(apiClient.recommendationRequests.last?.windowMinutes, 90)
        XCTAssertEqual(model.recommendationResponse?.recommendations.count, 0)
        XCTAssertNil(model.alertState)

        let recommendation = TestFactory.recommendation(serviceID: 202)
        apiClient.recommendationsResult = .success(TestFactory.recommendationResponse([recommendation]))

        await model.loadRecommendations()

        XCTAssertEqual(model.recommendationResponse?.topRecommendation?.journey.serviceId, 202)
        XCTAssertEqual(model.recommendationResponse?.recommendations.count, 1)
        XCTAssertNil(model.alertState)
    }

    @MainActor
    func testLoadRecommendationsClampsStaleDepartureStartToNow() async {
        let apiClient = FakeAPIClient()
        let model = makeModel(apiClient: apiClient)
        model.origin = TestFactory.station(crs: "AAA", name: "Origin")
        model.destination = TestFactory.station(crs: "BBB", name: "Destination")
        model.departureStart = Date(timeIntervalSinceNow: -300)
        apiClient.recommendationsResult = .success(TestFactory.emptyRecommendationResponse())

        let beforeSearch = Date()
        await model.loadRecommendations()

        guard let requestedStart = apiClient.recommendationRequests.last?.departureStart else {
            XCTFail("missing recommendation request")
            return
        }
        XCTAssertGreaterThanOrEqual(requestedStart, beforeSearch)
    }

    @MainActor
    func testAnyRouteModeUsesGeneralDestinationSearchAndJourneyPlanner() async throws {
        let apiClient = FakeAPIClient()
        let model = makeModel(apiClient: apiClient)
        model.windowSetupViewModel.applyAppCapabilities(AppCapabilitiesResponse(multiLegRoutingEnabled: true))
        model.directRoutesOnly = false
        model.origin = TestFactory.station(crs: "AAA", name: "Origin")
        model.destination = TestFactory.station(crs: "ZZZ", name: "Indirect Destination")
        model.departureStart = TestFactory.now
        model.windowMinutes = 90
        apiClient.stationSearchResultsByQuery["ZZZ"] = [TestFactory.station(crs: "ZZZ", name: "Indirect Destination")]
        let itinerary = TestFactory.itinerary(stableKey: "route-1")
        apiClient.journeyPlanResult = .success(TestFactory.journeyPlanResponse([itinerary]))

        let destinations = try await model.windowSetupViewModel.searchDestinationStations(query: "zzz")
        await model.loadRecommendations()

        XCTAssertEqual(destinations.first?.crs, "ZZZ")
        XCTAssertEqual(apiClient.stationSearchRequests.last?.query, "zzz")
        XCTAssertTrue(apiClient.directDestinationStationRequests.isEmpty)
        XCTAssertTrue(apiClient.recommendationRequests.isEmpty)
        XCTAssertEqual(apiClient.journeyPlanRequests.last?.originCRS, "AAA")
        XCTAssertEqual(apiClient.journeyPlanRequests.last?.destinationCRS, "ZZZ")
        XCTAssertEqual(apiClient.journeyPlanRequests.last?.maxChanges, 3)
        XCTAssertEqual(apiClient.journeyPlanRequests.last?.limit, 5)
        XCTAssertEqual(model.journeyPlanResponse?.topItinerary?.stableKey, "route-1")
        XCTAssertNil(model.recommendationResponse)
        XCTAssertNil(model.alertState)
    }

    @MainActor
    func testMultiLegRoutingDisabledKeepsDirectModeAndSkipsJourneyPlanner() async {
        let apiClient = FakeAPIClient()
        let model = makeModel(apiClient: apiClient)
        model.windowSetupViewModel.applyAppCapabilities(AppCapabilitiesResponse(multiLegRoutingEnabled: false))
        model.windowSetupViewModel.setSearchMode(.anyRoute)
        model.origin = TestFactory.station(crs: "AAA", name: "Origin")
        model.destination = TestFactory.station(crs: "ZZZ", name: "Indirect Destination")
        apiClient.recommendationsResult = .success(TestFactory.emptyRecommendationResponse())

        await model.loadRecommendations()

        XCTAssertTrue(model.directRoutesOnly)
        XCTAssertTrue(apiClient.journeyPlanRequests.isEmpty)
        XCTAssertEqual(apiClient.recommendationRequests.last?.originCRS, "AAA")
        XCTAssertNil(model.alertState)
    }

    @MainActor
    func testLoadAppCapabilitiesDefaultsDisabledOnFailure() async {
        let apiClient = FakeAPIClient()
        apiClient.appCapabilitiesResult = .failure(TestFailure.unimplemented)
        let model = makeModel(apiClient: apiClient)
        model.windowSetupViewModel.applyAppCapabilities(AppCapabilitiesResponse(multiLegRoutingEnabled: true))
        model.directRoutesOnly = false

        await model.windowSetupViewModel.loadAppCapabilities()

        XCTAssertEqual(apiClient.appCapabilitiesCallCount, 1)
        XCTAssertTrue(model.directRoutesOnly)
        XCTAssertFalse(model.windowSetupViewModel.canUseMultiLegRouting)
    }

    @MainActor
    func testCreateActiveWindowCreatesItinerarySubscriptionInAnyRouteMode() async {
        let apiClient = FakeAPIClient()
        let sessionStore = FakeSessionStore()
        sessionStore.session = TestFactory.storedSession(accessToken: "create-token")
        apiClient.currentUserResult = .success(TestFactory.user())
        apiClient.activeWindowResult = .failure(TestFactory.notFoundError())
        let itinerary = TestFactory.itinerary(stableKey: "route-1")
        apiClient.createItineraryResult = .success(TestFactory.itinerarySubscription(id: "itinerary-1", selectedItinerary: itinerary))
        let model = makeModel(apiClient: apiClient, sessionStore: sessionStore)
        await model.bootstrap()
        model.windowSetupViewModel.applyAppCapabilities(AppCapabilitiesResponse(multiLegRoutingEnabled: true))
        model.directRoutesOnly = false
        model.origin = TestFactory.station(crs: "AAA", name: "Origin")
        model.destination = TestFactory.station(crs: "ZZZ", name: "Indirect Destination")

        await model.createActiveWindow()

        XCTAssertEqual(apiClient.createItineraryRequests.last?.accessToken, "create-token")
        XCTAssertEqual(apiClient.createItineraryRequests.last?.input.originCrs, "AAA")
        XCTAssertEqual(apiClient.createItineraryRequests.last?.input.destinationCrs, "ZZZ")
        XCTAssertEqual(apiClient.createItineraryRequests.last?.input.maxChanges, 3)
        XCTAssertEqual(apiClient.createItineraryRequests.last?.input.limit, 5)
        XCTAssertNil(apiClient.createItineraryRequests.last?.input.selectedItineraryStableKey)
        XCTAssertEqual(model.activeItinerary?.id, "itinerary-1")
        XCTAssertEqual(model.journeyPlanResponse?.topItinerary?.stableKey, "route-1")
        XCTAssertNil(model.activeWindow)
    }

    @MainActor
    func testCreateActiveItineraryForSelectedRouteReplacesExistingActiveWindow() async {
        let apiClient = FakeAPIClient()
        let sessionStore = FakeSessionStore()
        sessionStore.session = TestFactory.storedSession(accessToken: "create-token")
        apiClient.currentUserResult = .success(TestFactory.user())
        apiClient.activeWindowResult = .success(TestFactory.window(id: "old-window"))
        let selectedRoute = TestFactory.itinerary(stableKey: "route-2")
        apiClient.createItineraryResult = .success(TestFactory.itinerarySubscription(id: "itinerary-2", selectedItinerary: selectedRoute))
        let model = makeModel(apiClient: apiClient, sessionStore: sessionStore)
        await model.bootstrap()
        model.windowSetupViewModel.applyAppCapabilities(AppCapabilitiesResponse(multiLegRoutingEnabled: true))
        model.directRoutesOnly = false
        model.origin = TestFactory.station(crs: "AAA", name: "Origin")
        model.destination = TestFactory.station(crs: "ZZZ", name: "Indirect Destination")

        await model.createActiveItinerary(for: selectedRoute, replacingActiveJourney: true)

        XCTAssertEqual(apiClient.deleteWindowRequests.last?.id, "old-window")
        XCTAssertEqual(apiClient.deleteWindowRequests.last?.accessToken, "create-token")
        XCTAssertEqual(apiClient.createItineraryRequests.last?.input.selectedItineraryStableKey, "route-2")
        XCTAssertEqual(model.activeItinerary?.id, "itinerary-2")
        XCTAssertNil(model.activeWindow)
        XCTAssertEqual(model.journeyPlanResponse?.topItinerary?.stableKey, "route-2")
    }

    @MainActor
    func testCreateDirectWindowReplacesExistingActiveItineraryWithoutSelectingTrain() async {
        let apiClient = FakeAPIClient()
        let sessionStore = FakeSessionStore()
        sessionStore.session = TestFactory.storedSession(accessToken: "create-token")
        apiClient.currentUserResult = .success(TestFactory.user())
        apiClient.activeWindowResult = .failure(TestFactory.notFoundError())
        apiClient.activeItineraryResult = .success(TestFactory.itinerarySubscription(id: "old-itinerary"))
        let recommendation = TestFactory.recommendation(serviceID: 202)
        apiClient.createWindowResult = .success(TestFactory.window(
            id: "direct-window",
            selectedRecommendation: recommendation,
            recommendations: [recommendation]
        ))
        let model = makeModel(apiClient: apiClient, sessionStore: sessionStore)
        await model.bootstrap()
        model.origin = TestFactory.station(crs: "AAA", name: "Origin")
        model.destination = TestFactory.station(crs: "BBB", name: "Destination")

        await model.createActiveWindow(replacingActiveJourney: true)

        XCTAssertEqual(apiClient.deleteItineraryRequests.last?.id, "old-itinerary")
        XCTAssertEqual(apiClient.deleteItineraryRequests.last?.accessToken, "create-token")
        XCTAssertNil(apiClient.createWindowRequests.last?.input.selectedTrainServiceId)
        XCTAssertEqual(model.activeWindow?.id, "direct-window")
        XCTAssertNil(model.activeItinerary)
        XCTAssertEqual(model.recommendationResponse?.topRecommendation?.journey.serviceId, 202)
    }

    @MainActor
    func testCreateActiveWindowForSelectedRecommendationCreatesSelectedTrainWindow() async {
        let apiClient = FakeAPIClient()
        let sessionStore = FakeSessionStore()
        sessionStore.session = TestFactory.storedSession(accessToken: "create-token")
        apiClient.currentUserResult = .success(TestFactory.user())
        apiClient.activeWindowResult = .failure(TestFactory.notFoundError())
        let recommendation = TestFactory.recommendation(serviceID: 202)
        apiClient.createWindowResult = .success(TestFactory.window(
            id: "selected-window",
            departureStart: "2026-01-10T09:00:00.000Z",
            windowMinutes: 90,
            selectedRecommendation: recommendation,
            recommendations: [recommendation],
            selectedTrainServiceId: 202
        ))
        let model = makeModel(apiClient: apiClient, sessionStore: sessionStore)
        await model.bootstrap()
        model.origin = TestFactory.station(crs: "AAA", name: "Origin")
        model.destination = TestFactory.station(crs: "BBB", name: "Destination")
        model.departureStart = TestFactory.now
        model.windowMinutes = 90

        await model.createActiveWindow(for: recommendation)

        XCTAssertEqual(apiClient.createWindowRequests.last?.accessToken, "create-token")
        XCTAssertEqual(apiClient.createWindowRequests.last?.input.originCrs, "AAA")
        XCTAssertEqual(apiClient.createWindowRequests.last?.input.destinationCrs, "BBB")
        XCTAssertEqual(apiClient.createWindowRequests.last?.input.originTpl, "orig")
        XCTAssertEqual(apiClient.createWindowRequests.last?.input.destinationTpl, "dest")
        XCTAssertEqual(apiClient.createWindowRequests.last?.input.departureStart, TestFactory.now)
        XCTAssertEqual(apiClient.createWindowRequests.last?.input.windowMinutes, 90)
        XCTAssertEqual(apiClient.createWindowRequests.last?.input.selectedTrainServiceId, 202)
        XCTAssertEqual(model.activeWindow?.id, "selected-window")
        XCTAssertEqual(model.recommendationResponse?.topRecommendation?.journey.serviceId, 202)
        XCTAssertEqual(model.recommendationResponse?.recommendations.map(\.journey.serviceId), [202])
        XCTAssertNil(model.alertState)
    }

    @MainActor
    func testCreateActiveWindowSurfacesEntitlementLimitAndMissingEndpointErrors() async {
        let apiClient = FakeAPIClient()
        let sessionStore = FakeSessionStore()
        sessionStore.session = TestFactory.storedSession(accessToken: "create-token")
        apiClient.currentUserResult = .success(TestFactory.user())
        apiClient.activeWindowResult = .failure(TestFactory.notFoundError())
        let model = makeModel(apiClient: apiClient, sessionStore: sessionStore)
        await model.bootstrap()
        model.origin = TestFactory.station(crs: "AAA", name: "Origin")
        model.destination = TestFactory.station(crs: "BBB", name: "Destination")

        apiClient.createWindowResult = .failure(TestFactory.entitlementLimitError())
        await model.createActiveWindow()

        XCTAssertEqual(apiClient.createWindowRequests.last?.accessToken, "create-token")
        XCTAssertEqual(model.alertState?.title, "Upgrade to Pro")
        XCTAssertNil(model.activeWindow)

        apiClient.createWindowResult = .failure(TestFactory.notFoundError(message: "404 page not found"))
        await model.createActiveWindow()

        XCTAssertEqual(model.alertState, .backendVersion("This backend does not expose the requested API yet. Deploy a compatible API image."))
        XCTAssertNil(model.activeWindow)
    }

    @MainActor
    func testCreateActiveWindowUnauthorizedClearsStoredSession() async {
        let apiClient = FakeAPIClient()
        let sessionStore = FakeSessionStore()
        sessionStore.session = TestFactory.storedSession(accessToken: "create-token")
        apiClient.currentUserResult = .success(TestFactory.user())
        apiClient.activeWindowResult = .failure(TestFactory.notFoundError())
        apiClient.createWindowResult = .failure(APIError.server(
            statusCode: 401,
            code: nil,
            message: "session is invalid or expired",
            details: [:]
        ))
        let model = makeModel(apiClient: apiClient, sessionStore: sessionStore)
        await model.bootstrap()
        model.origin = TestFactory.station(crs: "AAA", name: "Origin")
        model.destination = TestFactory.station(crs: "BBB", name: "Destination")

        await model.createActiveWindow()
        await waitForAuthInvalidation(model)

        XCTAssertEqual(apiClient.createWindowRequests.last?.accessToken, "create-token")
        XCTAssertNil(model.user)
        XCTAssertNil(model.accessToken)
        XCTAssertNil(model.activeWindow)
        XCTAssertEqual(sessionStore.clearCount, 1)
        XCTAssertEqual(model.alertState, .auth(AppOperationState.expiredSessionMessage))
    }

    @MainActor
    func testUS2SetupModelCoversIntentWindowValidationAndRoutingCapabilities() {
        let model = makeModel()

        XCTAssertEqual(model.windowSetupViewModel.activeSetupIntent, .oneOffDirect)
        model.windowSetupViewModel.setWindowMinutes(5)
        XCTAssertEqual(model.windowMinutes, 30)
        model.windowSetupViewModel.setWindowMinutes(377)
        XCTAssertEqual(model.windowMinutes, 360)

        model.windowSetupViewModel.setSearchMode(.anyRoute)
        XCTAssertTrue(model.directRoutesOnly)
        XCTAssertEqual(model.windowSetupViewModel.activeSetupIntent, .oneOffDirect)
        XCTAssertEqual(model.alertState, .validation("All routes are coming soon."))

        model.windowSetupViewModel.applyAppCapabilities(AppCapabilitiesResponse(multiLegRoutingEnabled: true))
        model.windowSetupViewModel.selectSetupIntent(.connectionSensitive)
        XCTAssertFalse(model.directRoutesOnly)
        XCTAssertEqual(model.windowSetupViewModel.activeSetupIntent, .connectionSensitive)
        XCTAssertEqual(model.windowMinutes, JourneySetupIntent.connectionSensitive.defaultWindowMinutes)
        XCTAssertEqual(model.windowSetupViewModel.setupIntentContent.primaryActionText, "Find routes with changes")

        model.windowSetupViewModel.selectSetupIntent(.oneOffDirect)
        XCTAssertTrue(model.directRoutesOnly)
        XCTAssertEqual(model.windowSetupViewModel.activeSetupIntent, .oneOffDirect)
        XCTAssertEqual(model.windowSetupViewModel.setupIntentContent.primaryActionText, "Find direct trains")
    }

    @MainActor
    func testUS2RoutinePrefillAppliesRouteWindowAndNextDeparture() {
        let model = makeModel()
        let now = DateFormatting.date(from: "2026-01-05T07:00:00.000Z")!
        let expectedDeparture = DateFormatting.date(from: "2026-01-05T08:15:00.000Z")!
        var routine = TestFactory.commuteRoutine(
            id: "morning-route",
            originCrs: "eus",
            destinationCrs: "man"
        )
        routine.windowMinutes = 95

        model.windowSetupViewModel.applyRoutinePrefill(
            routine,
            originStation: TestFactory.station(crs: "EUS", name: "London Euston"),
            destinationStation: TestFactory.station(crs: "MAN", name: "Manchester Piccadilly"),
            now: now
        )

        XCTAssertEqual(model.windowSetupViewModel.activeSetupIntent, .routineCommute)
        XCTAssertTrue(model.directRoutesOnly)
        XCTAssertEqual(model.origin?.crs, "EUS")
        XCTAssertEqual(model.origin?.displayName, "London Euston")
        XCTAssertEqual(model.destination?.crs, "MAN")
        XCTAssertEqual(model.destination?.displayName, "Manchester Piccadilly")
        XCTAssertEqual(model.departureStart, expectedDeparture)
        XCTAssertEqual(model.windowMinutes, 90)

        model.startJourneyPlan(from: routine)

        XCTAssertEqual(model.selectedTab, .plan)
        XCTAssertEqual(model.windowSetupViewModel.activeSetupIntent, .routineCommute)
        XCTAssertEqual(model.origin?.crs, "EUS")
        XCTAssertEqual(model.destination?.crs, "MAN")
    }

    @MainActor
    func testTogglePinnedLiveActivityPinsUnpinsAndClearsWithoutActiveWindow() async {
        let first = TestFactory.recommendation(rank: 1, serviceID: 111)
        let second = TestFactory.recommendation(rank: 2, serviceID: 222)
        let window = TestFactory.window(id: "pin-window", selectedRecommendation: first, recommendations: [first, second])
        let apiClient = FakeAPIClient()
        let sessionStore = FakeSessionStore()
        let liveActivityCoordinator = FakeLiveActivityCoordinator()
        sessionStore.session = TestFactory.storedSession(accessToken: "pin-token")
        apiClient.currentUserResult = .success(TestFactory.user())
        apiClient.activeWindowResult = .success(window)
        apiClient.pinWindowResult = .success(TestFactory.window(
            id: "pin-window",
            selectedRecommendation: first,
            recommendations: [first, second],
            pinnedTrainServiceId: 222
        ))
        apiClient.clearPinnedWindowResult = .success(window)
        let model = makeModel(
            apiClient: apiClient,
            sessionStore: sessionStore,
            liveActivityCoordinator: liveActivityCoordinator
        )
        await model.bootstrap()

        await model.togglePinnedLiveActivity(for: second)

        XCTAssertEqual(apiClient.pinWindowRequests.last?.id, "pin-window")
        XCTAssertEqual(apiClient.pinWindowRequests.last?.serviceID, 222)
        XCTAssertEqual(apiClient.pinWindowRequests.last?.accessToken, "pin-token")
        XCTAssertEqual(model.pinnedLiveActivityServiceID, 222)
        XCTAssertEqual(liveActivityCoordinator.syncCalls.last?.windowID, "pin-window")
        XCTAssertEqual(liveActivityCoordinator.syncCalls.last?.pinnedTrainServiceID, 222)

        await model.togglePinnedLiveActivity(for: second)

        XCTAssertEqual(apiClient.clearPinnedWindowRequests.last?.id, "pin-window")
        XCTAssertEqual(apiClient.clearPinnedWindowRequests.last?.accessToken, "pin-token")
        XCTAssertNil(model.pinnedLiveActivityServiceID)
        XCTAssertNil(liveActivityCoordinator.syncCalls.last?.pinnedTrainServiceID)

        let emptyLiveActivityCoordinator = FakeLiveActivityCoordinator()
        let emptyModel = makeModel(liveActivityCoordinator: emptyLiveActivityCoordinator)
        await emptyModel.togglePinnedLiveActivity(for: first)

        XCTAssertNil(emptyModel.pinnedLiveActivityServiceID)
        XCTAssertEqual(emptyLiveActivityCoordinator.endAllCount, 1)
    }

    @MainActor
    func testClearingArrivedPinnedJourneyDeletesActiveWindow() async {
        let arrived = TestFactory.recommendation(
            serviceID: 303,
            journey: TestFactory.journey(
                serviceID: 303,
                scheduledArrival: DateFormatting.apiDateTime.string(from: Date().addingTimeInterval(30 * 60)),
                displayStatus: "arrived",
                statusKind: "arrived",
                movementPhase: "arrived"
            )
        )
        let window = TestFactory.window(
            id: "arrived-pin-window",
            selectedRecommendation: arrived,
            recommendations: [arrived],
            pinnedTrainServiceId: 303
        )
        let apiClient = FakeAPIClient()
        let sessionStore = FakeSessionStore()
        let liveActivityCoordinator = FakeLiveActivityCoordinator()
        sessionStore.session = TestFactory.storedSession(accessToken: "arrived-pin-token")
        apiClient.currentUserResult = .success(TestFactory.user())
        apiClient.activeWindowResult = .success(window)
        let model = makeModel(
            apiClient: apiClient,
            sessionStore: sessionStore,
            liveActivityCoordinator: liveActivityCoordinator
        )
        await model.bootstrap()

        await model.activeWindowViewModel.clearPinnedTrainOrDeleteArrivedJourney(
            windowID: "arrived-pin-window",
            serviceID: 303
        )

        XCTAssertEqual(apiClient.deleteWindowRequests.last?.id, "arrived-pin-window")
        XCTAssertEqual(apiClient.deleteWindowRequests.last?.accessToken, "arrived-pin-token")
        XCTAssertTrue(apiClient.clearPinnedWindowRequests.isEmpty)
        XCTAssertNil(model.activeWindow)
        XCTAssertEqual(liveActivityCoordinator.endAllCount, 1)
    }

    @MainActor
    func testClearingNonArrivedPinnedJourneyOnlyClearsPinnedTrain() async {
        let pinned = TestFactory.recommendation(serviceID: 303)
        let clearedWindow = TestFactory.window(
            id: "active-pin-window",
            selectedRecommendation: pinned,
            recommendations: [pinned],
            pinnedTrainServiceId: nil
        )
        let window = TestFactory.window(
            id: "active-pin-window",
            selectedRecommendation: pinned,
            recommendations: [pinned],
            pinnedTrainServiceId: 303
        )
        let apiClient = FakeAPIClient()
        let sessionStore = FakeSessionStore()
        sessionStore.session = TestFactory.storedSession(accessToken: "active-pin-token")
        apiClient.currentUserResult = .success(TestFactory.user())
        apiClient.activeWindowResult = .success(window)
        apiClient.clearPinnedWindowResult = .success(clearedWindow)
        let model = makeModel(apiClient: apiClient, sessionStore: sessionStore)
        await model.bootstrap()

        await model.activeWindowViewModel.clearPinnedTrainOrDeleteArrivedJourney(
            windowID: "active-pin-window",
            serviceID: 303
        )

        XCTAssertEqual(apiClient.clearPinnedWindowRequests.last?.id, "active-pin-window")
        XCTAssertEqual(apiClient.clearPinnedWindowRequests.last?.accessToken, "active-pin-token")
        XCTAssertTrue(apiClient.deleteWindowRequests.isEmpty)
        XCTAssertNotNil(model.activeWindow)
        XCTAssertNil(model.pinnedLiveActivityServiceID)
    }

    @MainActor
    func testLiveActivityIntentPinActionIsReconciledIntoPinRequest() async {
        let first = TestFactory.recommendation(rank: 1, serviceID: 111)
        let second = TestFactory.recommendation(rank: 2, serviceID: 222)
        let window = TestFactory.window(id: "intent-window", selectedRecommendation: first, recommendations: [first, second])
        let apiClient = FakeAPIClient()
        let sessionStore = FakeSessionStore()
        sessionStore.session = TestFactory.storedSession(accessToken: "intent-token")
        apiClient.currentUserResult = .success(TestFactory.user())
        apiClient.activeWindowResult = .success(window)
        apiClient.pinWindowResult = .success(TestFactory.window(
            id: "intent-window",
            selectedRecommendation: first,
            recommendations: [first, second],
            pinnedTrainServiceId: 222
        ))
        let model = makeModel(apiClient: apiClient, sessionStore: sessionStore)
        await model.bootstrap()

        LiveActivityIntentActionStore.enqueue(
            LiveActivityIntentActionStore.PendingAction(
                id: "queued-pin",
                kind: .pinTrain,
                createdAt: Date(),
                windowSubscriptionID: "intent-window",
                itinerarySubscriptionID: nil,
                serviceID: 222,
                minutes: nil,
                snoozedUntil: nil
            )
        )

        await model.activeWindowViewModel.reconcileLiveActivityIntentActions()

        XCTAssertEqual(apiClient.pinWindowRequests.last?.id, "intent-window")
        XCTAssertEqual(apiClient.pinWindowRequests.last?.serviceID, 222)
        XCTAssertEqual(apiClient.pinWindowRequests.last?.accessToken, "intent-token")
        XCTAssertEqual(model.pinnedLiveActivityServiceID, 222)
        XCTAssertTrue(LiveActivityIntentActionStore.drainPendingActions().isEmpty)
    }

    @MainActor
    func testWindowNotificationDeepLinkFetchesDetail() async {
        let apiClient = FakeAPIClient()
        let sessionStore = FakeSessionStore()
        let window = TestFactory.window(id: "deep-window")
        let detail = TestFactory.windowNotificationDetail(id: "notification-1", windowID: "deep-window")
        sessionStore.session = TestFactory.storedSession(accessToken: "deep-token")
        apiClient.currentUserResult = .success(TestFactory.user())
        apiClient.activeWindowResult = .failure(TestFactory.notFoundError())
        apiClient.windowResult = .success(window)
        apiClient.windowNotificationResult = .success(detail)
        let model = makeModel(apiClient: apiClient, sessionStore: sessionStore)
        await model.bootstrap()

        await model.openDeepLink(URL(string: "righttrain://windows/direct/subscriptions/deep-window/notifications/notification-1")!)

        XCTAssertEqual(model.selectedTab, .active)
        XCTAssertEqual(apiClient.getWindowRequests.last?.id, "deep-window")
        XCTAssertEqual(apiClient.windowNotificationRequests.last?.windowSubscriptionID, "deep-window")
        XCTAssertEqual(apiClient.windowNotificationRequests.last?.notificationID, "notification-1")
        XCTAssertEqual(apiClient.windowNotificationRequests.last?.accessToken, "deep-token")
        let identity = WindowNotificationDetailIdentity(windowSubscriptionID: "deep-window", notificationID: "notification-1")
        XCTAssertEqual(model.pendingRoute, .notificationDetail(identity))
        XCTAssertEqual(model.notificationDetail(for: identity)?.id, "notification-1")

        model.consumePendingRoute(.journeyDetail(JourneyDetailIdentity(serviceID: 999)))
        XCTAssertEqual(model.pendingRoute, .notificationDetail(identity))

        model.consumePendingRoute(.notificationDetail(identity))
        XCTAssertNil(model.pendingRoute)
        XCTAssertEqual(model.notificationDetail(for: identity)?.id, "notification-1")
    }

    @MainActor
    func testUS3ActionNeededPushPayloadsOpenAffectedWindowNotificationContext() async {
        let events = [
            "platform_change",
            "delay",
            "cancellation",
            "recommended_train_departed"
        ]

        for eventType in events {
            let apiClient = FakeAPIClient()
            let sessionStore = FakeSessionStore()
            let affected = TestFactory.recommendation(rank: 1, serviceID: 111)
            let next = TestFactory.recommendation(rank: 2, serviceID: 222)
            let notificationID = "\(eventType)-notification"
            var detail = TestFactory.windowNotificationDetail(
                id: notificationID,
                windowID: "push-window",
                eventType: eventType,
                departed: affected,
                next: next
            )
            if eventType == "platform_change" {
                detail.payload.data.platform = "12"
                detail.payload.data.previousPlatform = "2"
            }

            sessionStore.session = TestFactory.storedSession(accessToken: "push-token")
            apiClient.currentUserResult = .success(TestFactory.user())
            apiClient.activeWindowResult = .failure(TestFactory.notFoundError())
            apiClient.windowResult = .success(TestFactory.window(id: "push-window"))
            apiClient.windowNotificationResult = .success(detail)
            let model = makeModel(apiClient: apiClient, sessionStore: sessionStore)
            await model.bootstrap()

            NotificationCenter.default.post(
                name: PushNotificationsAppDelegate.didReceiveResponseNotification,
                object: nil,
                userInfo: [
                    PushNotificationsAppDelegate.windowSubscriptionIDUserInfoKey: "push-window",
                    PushNotificationsAppDelegate.notificationIDUserInfoKey: notificationID
                ]
            )

            let identity = WindowNotificationDetailIdentity(
                windowSubscriptionID: "push-window",
                notificationID: notificationID
            )
            await waitForPendingRoute(model, route: .notificationDetail(identity))

            XCTAssertEqual(model.selectedTab, .active, eventType)
            XCTAssertEqual(apiClient.getWindowRequests.last?.id, "push-window", eventType)
            XCTAssertEqual(apiClient.windowNotificationRequests.last?.notificationID, notificationID, eventType)
            XCTAssertEqual(model.pendingRoute, .notificationDetail(identity), eventType)
            XCTAssertEqual(model.notificationDetail(for: identity)?.eventType, eventType)
        }
    }

    @MainActor
    func testUS3UnavailablePushNotificationStillRoutesToExplicitUnavailableState() async {
        let apiClient = FakeAPIClient()
        let sessionStore = FakeSessionStore()
        sessionStore.session = TestFactory.storedSession(accessToken: "push-token")
        apiClient.currentUserResult = .success(TestFactory.user())
        apiClient.activeWindowResult = .failure(TestFactory.notFoundError())
        apiClient.windowResult = .failure(TestFactory.notFoundError())
        apiClient.windowNotificationResult = .failure(TestFactory.notFoundError())
        let model = makeModel(apiClient: apiClient, sessionStore: sessionStore)
        await model.bootstrap()

        NotificationCenter.default.post(
            name: PushNotificationsAppDelegate.didReceiveResponseNotification,
            object: nil,
            userInfo: [
                PushNotificationsAppDelegate.windowSubscriptionIDUserInfoKey: "missing-window",
                PushNotificationsAppDelegate.notificationIDUserInfoKey: "missing-notification"
            ]
        )

        let identity = WindowNotificationDetailIdentity(
            windowSubscriptionID: "missing-window",
            notificationID: "missing-notification"
        )
        await waitForPendingRoute(model, route: .notificationDetail(identity))

        XCTAssertEqual(model.selectedTab, .active)
        XCTAssertEqual(model.pendingRoute, .notificationDetail(identity))
        XCTAssertNil(model.notificationDetail(for: identity))
    }

    func testUS3LocalInterchangeNotificationCopyUsesActionNeededWording() {
        XCTAssertEqual(
            LocalInterchangeNotification.bodyText(onwardPlatform: " 5 ", onwardDeparture: " 10:42 "),
            "Action needed: use platform 5 for the 10:42 onward train."
        )
        XCTAssertEqual(
            LocalInterchangeNotification.bodyText(onwardPlatform: "5", onwardDeparture: nil),
            "Action needed: use platform 5 for your onward train."
        )
        XCTAssertEqual(
            LocalInterchangeNotification.bodyText(onwardPlatform: nil, onwardDeparture: "10:42"),
            "Action needed: onward train departs 10:42."
        )
        XCTAssertEqual(
            LocalInterchangeNotification.bodyText(onwardPlatform: nil, onwardDeparture: nil),
            "Action needed: get ready to change trains."
        )
    }

    @MainActor
    func testNotificationActionsPinAndMonitorNextBest() async {
        let apiClient = FakeAPIClient()
        let sessionStore = FakeSessionStore()
        let first = TestFactory.recommendation(rank: 1, serviceID: 111)
        let next = TestFactory.recommendation(rank: 2, serviceID: 222)
        let window = TestFactory.window(id: "action-window", selectedRecommendation: next, recommendations: [next, first])
        sessionStore.session = TestFactory.storedSession(accessToken: "action-token")
        apiClient.currentUserResult = .success(TestFactory.user())
        apiClient.activeWindowResult = .success(window)
        apiClient.pinWindowResult = .success(TestFactory.window(
            id: "action-window",
            selectedRecommendation: next,
            recommendations: [next, first],
            pinnedTrainServiceId: 111
        ))
        apiClient.clearPinnedWindowResult = .success(window)
        let model = makeModel(apiClient: apiClient, sessionStore: sessionStore)
        await model.bootstrap()

        NotificationCenter.default.post(
            name: PushNotificationsAppDelegate.didReceiveResponseNotification,
            object: nil,
            userInfo: [
                PushNotificationsAppDelegate.actionIdentifierUserInfoKey: PushNotificationsAppDelegate.pinDepartedTrainActionIdentifier,
                PushNotificationsAppDelegate.windowSubscriptionIDUserInfoKey: "action-window",
                PushNotificationsAppDelegate.departedTrainServiceIDUserInfoKey: 111
            ]
        )
        for _ in 0..<20 {
            if !apiClient.pinWindowRequests.isEmpty { break }
            await Task.yield()
        }

        XCTAssertEqual(apiClient.pinWindowRequests.last?.id, "action-window")
        XCTAssertEqual(apiClient.pinWindowRequests.last?.serviceID, 111)
        XCTAssertTrue(model.activeWindowViewModel.hasHandledDepartedPrompt(windowID: "action-window", serviceID: 111))

        NotificationCenter.default.post(
            name: PushNotificationsAppDelegate.didReceiveResponseNotification,
            object: nil,
            userInfo: [
                PushNotificationsAppDelegate.actionIdentifierUserInfoKey: PushNotificationsAppDelegate.monitorNextBestActionIdentifier,
                PushNotificationsAppDelegate.windowSubscriptionIDUserInfoKey: "action-window",
                PushNotificationsAppDelegate.departedTrainServiceIDUserInfoKey: 111
            ]
        )
        for _ in 0..<20 {
            if !apiClient.clearPinnedWindowRequests.isEmpty { break }
            await Task.yield()
        }

        XCTAssertEqual(apiClient.clearPinnedWindowRequests.last?.id, "action-window")
        XCTAssertTrue(model.activeWindowViewModel.hasHandledDepartedPrompt(windowID: "action-window", serviceID: 111))
    }

    @MainActor
    func testPullRefreshChecksForActiveWindowFromEmptyState() async {
        let apiClient = FakeAPIClient()
        let sessionStore = FakeSessionStore()
        sessionStore.session = TestFactory.storedSession(accessToken: "pull-token")
        apiClient.currentUserResult = .success(TestFactory.user())
        apiClient.activeWindowResult = .failure(TestFactory.notFoundError())
        let model = makeModel(apiClient: apiClient, sessionStore: sessionStore)
        await model.bootstrap()

        XCTAssertNil(model.activeWindow)
        XCTAssertEqual(apiClient.getActiveWindowAccessTokens, ["pull-token"])

        await model.refreshActiveWindowFromPullGesture()

        XCTAssertEqual(apiClient.getActiveWindowAccessTokens, ["pull-token", "pull-token"])
        XCTAssertNil(model.alertState)
    }

    @MainActor
    func testPullRefreshSuppressesTransientConnectionAlerts() async {
        let apiClient = FakeAPIClient()
        let sessionStore = FakeSessionStore()
        let window = TestFactory.window(id: "pull-window")
        sessionStore.session = TestFactory.storedSession(accessToken: "pull-token")
        apiClient.currentUserResult = .success(TestFactory.user())
        apiClient.activeWindowResult = .success(window)
        let model = makeModel(apiClient: apiClient, sessionStore: sessionStore)
        await model.bootstrap()

        apiClient.windowResult = .failure(APIError.transport("offline"))

        await model.refreshActiveWindowFromPullGesture()

        XCTAssertEqual(apiClient.getWindowRequests.last?.id, "pull-window")
        XCTAssertEqual(model.activeWindow?.id, "pull-window")
        XCTAssertNil(model.alertState)
    }

    @MainActor
    func testForegroundRefreshReloadsActiveWindowWithoutShowingSpinner() async {
        let apiClient = FakeAPIClient()
        let sessionStore = FakeSessionStore()
        let initialWindow = TestFactory.window(id: "foreground-window")
        let updatedRecommendation = TestFactory.recommendation(rank: 1, serviceID: 222)
        let updatedWindow = TestFactory.window(
            id: "foreground-window",
            selectedRecommendation: updatedRecommendation,
            recommendations: [updatedRecommendation]
        )
        sessionStore.session = TestFactory.storedSession(accessToken: "foreground-token")
        apiClient.currentUserResult = .success(TestFactory.user())
        apiClient.activeWindowResult = .success(initialWindow)
        let model = makeModel(apiClient: apiClient, sessionStore: sessionStore)
        await model.bootstrap()
        apiClient.windowResult = .success(updatedWindow)

        await model.refreshActiveWindow(showLoading: false)

        XCTAssertEqual(apiClient.getWindowRequests.last?.id, "foreground-window")
        XCTAssertEqual(apiClient.getWindowRequests.last?.accessToken, "foreground-token")
        XCTAssertEqual(model.activeWindow?.selectedRecommendation.journey.serviceId, 222)
        XCTAssertFalse(model.isLoading)
    }

    @MainActor
    func testActiveWindowPollingIntervalScalesByDepartureTiming() {
        let now = DateFormatting.date(from: "2026-01-10T09:00:00.000Z")!

        XCTAssertEqual(
            ActiveWindowViewModel.activeWindowPollingInterval(
                for: TestFactory.window(
                    id: "far-window",
                    departureStart: "2026-01-10T10:01:00.000Z"
                ),
                activeWindowID: "far-window",
                now: now
            ),
            Duration.seconds(300)
        )
        XCTAssertEqual(
            ActiveWindowViewModel.activeWindowPollingInterval(
                for: TestFactory.window(
                    id: "approaching-window",
                    departureStart: "2026-01-10T09:45:00.000Z"
                ),
                activeWindowID: "approaching-window",
                now: now
            ),
            Duration.seconds(60)
        )
        XCTAssertEqual(
            ActiveWindowViewModel.activeWindowPollingInterval(
                for: TestFactory.window(
                    id: "imminent-window",
                    departureStart: "2026-01-10T09:10:00.000Z"
                ),
                activeWindowID: "imminent-window",
                now: now
            ),
            Duration.seconds(20)
        )
        XCTAssertEqual(
            ActiveWindowViewModel.activeWindowPollingInterval(
                for: TestFactory.window(
                    id: "departed-window",
                    departureStart: "2026-01-10T08:30:00.000Z",
                    windowMinutes: 60
                ),
                activeWindowID: "departed-window",
                now: now
            ),
            Duration.seconds(20)
        )
        XCTAssertNil(
            ActiveWindowViewModel.activeWindowPollingInterval(
                for: TestFactory.window(
                    id: "expired-window",
                    departureStart: "2026-01-10T07:00:00.000Z",
                    windowMinutes: 60
                ),
                activeWindowID: "expired-window",
                now: now
            )
        )
        XCTAssertNil(
            ActiveWindowViewModel.activeWindowPollingInterval(
                for: TestFactory.window(id: "cleared-window"),
                activeWindowID: nil,
                now: now
            )
        )
        XCTAssertEqual(
            ActiveWindowViewModel.activeWindowPollingInterval(
                for: nil,
                activeWindowID: "persisted-window",
                now: now
            ),
            Duration.seconds(120)
        )
    }

    @MainActor
    func testOnboardArrivalClearDateUsesPinnedArrivedTrainGrace() {
        let arrival = DateFormatting.date(from: "2026-01-10T11:00:00.000Z")!
        let arrived = TestFactory.recommendation(
            serviceID: 303,
            journey: TestFactory.journey(
                serviceID: 303,
                scheduledArrival: "2026-01-10T11:00:00.000Z",
                displayStatus: "arrived",
                statusKind: "arrived",
                movementPhase: "arrived"
            )
        )
        let other = TestFactory.recommendation(rank: 2, serviceID: 404)
        let window = TestFactory.window(
            id: "arrived-window",
            selectedRecommendation: other,
            recommendations: [other, arrived],
            pinnedTrainServiceId: 303
        )

        XCTAssertEqual(
            ActiveWindowViewModel.onboardArrivalClearDate(for: window),
            arrival.addingTimeInterval(ActiveWindowViewModel.onboardArrivalClearGraceSeconds)
        )
    }

    @MainActor
    func testArrivedPinnedActiveWindowClearsImmediatelyAfterGraceOnRefresh() async {
        let apiClient = FakeAPIClient()
        let sessionStore = FakeSessionStore()
        let liveActivityCoordinator = FakeLiveActivityCoordinator()
        let arrival = Date().addingTimeInterval(-(ActiveWindowViewModel.onboardArrivalClearGraceSeconds + 30))
        let departure = arrival.addingTimeInterval(-15 * 60)
        let arrived = TestFactory.recommendation(
            serviceID: 303,
            journey: TestFactory.journey(
                serviceID: 303,
                scheduledDeparture: DateFormatting.apiDateTime.string(from: departure),
                scheduledArrival: DateFormatting.apiDateTime.string(from: arrival),
                displayStatus: "arrived",
                statusKind: "arrived",
                movementPhase: "arrived"
            )
        )
        let window = TestFactory.window(
            id: "arrived-window",
            selectedRecommendation: arrived,
            recommendations: [arrived],
            pinnedTrainServiceId: 303
        )
        sessionStore.session = TestFactory.storedSession(accessToken: "arrival-token")
        apiClient.currentUserResult = .success(TestFactory.user())
        apiClient.activeWindowResult = .success(window)
        let model = makeModel(
            apiClient: apiClient,
            sessionStore: sessionStore,
            liveActivityCoordinator: liveActivityCoordinator
        )

        await model.bootstrap()

        XCTAssertEqual(apiClient.deleteWindowRequests.last?.id, "arrived-window")
        XCTAssertEqual(apiClient.deleteWindowRequests.last?.accessToken, "arrival-token")
        XCTAssertNil(model.activeWindow)
        XCTAssertEqual(liveActivityCoordinator.endAllCount, 1)
    }

    @MainActor
    func testForegroundStreamEventRefreshesActiveWindow() async {
        let apiClient = FakeAPIClient()
        let sessionStore = FakeSessionStore()
        let initialWindow = TestFactory.window(id: "stream-window")
        let updatedRecommendation = TestFactory.recommendation(rank: 1, serviceID: 222)
        let updatedWindow = TestFactory.window(
            id: "stream-window",
            selectedRecommendation: updatedRecommendation,
            recommendations: [updatedRecommendation]
        )
        sessionStore.session = TestFactory.storedSession(accessToken: "stream-token")
        apiClient.currentUserResult = .success(TestFactory.user())
        apiClient.activeWindowResult = .success(initialWindow)
        apiClient.windowResult = .success(updatedWindow)
        apiClient.streamEvents = [
            SubscriptionStreamEvent(
                id: "cursor-1",
                event: "subscription_event",
                envelope: SubscriptionStreamEnvelope(
                    stream: "state_update",
                    notification: SubscriptionStreamNotification(
                        id: "window-note-1",
                        subscriptionId: nil,
                        windowSubscriptionId: "stream-window",
                        eventType: "window_state",
                        deliveryClass: "state_update",
                        createdAt: "2026-03-29T18:05:00Z"
                    )
                )
            )
        ]
        let model = makeModel(apiClient: apiClient, sessionStore: sessionStore)
        await model.bootstrap()

        let monitorTask = Task { await model.monitorActiveWindowForegroundUpdates() }
        for _ in 0..<20 {
            if apiClient.streamWindowRequests.contains(where: { $0.windowSubscriptionID == "stream-window" }) &&
                model.activeWindow?.selectedRecommendation.journey.serviceId == 222 {
                break
            }
            await Task.yield()
        }
        monitorTask.cancel()
        await monitorTask.value

        XCTAssertEqual(apiClient.streamWindowRequests.first?.windowSubscriptionID, "stream-window")
        XCTAssertEqual(apiClient.streamWindowRequests.first?.accessToken, "stream-token")
        XCTAssertEqual(apiClient.getWindowRequests.last?.id, "stream-window")
        XCTAssertEqual(model.activeWindow?.selectedRecommendation.journey.serviceId, 222)
    }

    @MainActor
    func testForegroundMonitorDiscoversAutoArmedWindowFromEmptyState() async {
        let apiClient = FakeAPIClient()
        let sessionStore = FakeSessionStore()
        let window = TestFactory.window(id: "auto-armed-window")
        sessionStore.session = TestFactory.storedSession(accessToken: "monitor-token")
        apiClient.currentUserResult = .success(TestFactory.user())
        apiClient.activeWindowResult = .failure(TestFactory.notFoundError())
        let model = makeModel(apiClient: apiClient, sessionStore: sessionStore)
        await model.bootstrap()
        XCTAssertNil(model.activeWindow)

        apiClient.activeWindowResult = .success(window)

        await model.monitorActiveWindowForegroundUpdates()

        XCTAssertEqual(apiClient.getActiveWindowAccessTokens, ["monitor-token", "monitor-token"])
        XCTAssertEqual(model.activeWindow?.id, "auto-armed-window")
    }

    @MainActor
    func testJourneyDeepLinkLoadsJourneyDetail() async {
        let apiClient = FakeAPIClient()
        let detail = TestFactory.journeyDetail(serviceID: 333)
        apiClient.journeyDetailResult = .success(detail)
        let model = makeModel(apiClient: apiClient)

        await model.openDeepLink(URL(string: "righttrain://journeys/333")!)

        XCTAssertEqual(apiClient.journeyDetailRequests.last?.serviceID, 333)
        XCTAssertNil(apiClient.journeyDetailRequests.last?.originTPL)
        XCTAssertNil(apiClient.journeyDetailRequests.last?.destinationTPL)
        XCTAssertEqual(model.selectedJourneyDetail?.serviceId, 333)
        let identity = JourneyDetailIdentity(detail: detail)
        XCTAssertEqual(model.pendingRoute, .journeyDetail(identity))
        XCTAssertEqual(model.journeyDetailViewModel.detail(for: identity)?.serviceId, 333)
        XCTAssertEqual(model.selectedTab, .active)

        model.consumePendingRoute(.notificationDetail(WindowNotificationDetailIdentity(windowSubscriptionID: "window", notificationID: "other")))
        XCTAssertEqual(model.pendingRoute, .journeyDetail(identity))

        model.consumePendingRoute(.journeyDetail(identity))
        XCTAssertNil(model.pendingRoute)
    }

    @MainActor
    func testActiveDeepLinkSelectsActiveTabWithoutLoadingJourneyDetail() async {
        let apiClient = FakeAPIClient()
        let model = makeModel(apiClient: apiClient)
        model.selectedTab = .plan

        await model.openDeepLink(URL(string: "righttrain://active")!)

        XCTAssertEqual(model.selectedTab, .active)
        XCTAssertTrue(apiClient.journeyDetailRequests.isEmpty)
    }

    func testUS1FirstScreenSelectionCoversEmptyActiveStaleAndOfflineStates() throws {
        let now = try XCTUnwrap(DateFormatting.date(from: "2026-01-10T10:10:00.000Z"))

        XCTAssertEqual(
            ActiveTabPrimaryContent.resolve(hasItinerary: false, hasWindow: false, hasOnBoardWindow: false),
            .empty
        )
        XCTAssertEqual(
            ActiveWindowPresentation.setupPromptContent(
                isSignedIn: true,
                hasRoutine: false,
                hasActiveItinerary: false
            ).moment,
            .noActiveJourney
        )
        XCTAssertEqual(
            ActiveTabPrimaryContent.resolve(hasItinerary: false, hasWindow: true, hasOnBoardWindow: false),
            .window
        )
        XCTAssertEqual(
            ActiveWindowPresentation.journeyMoment(
                for: TestFactory.recommendation(
                    journey: TestFactory.journey(
                        scheduledDeparture: "2026-01-10T10:30:00.000Z",
                        scheduledArrival: "2026-01-10T11:20:00.000Z"
                    )
                ),
                now: now
            ),
            .monitoringBeforeDeparture
        )
        XCTAssertEqual(
            ActiveTabPrimaryContent.resolve(hasItinerary: true, hasWindow: true, hasOnBoardWindow: false),
            .itinerary
        )
        XCTAssertEqual(
            ActiveWindowPresentation.journeyMoment(
                for: TestFactory.itinerarySubscription(phase: ItineraryPhase.planning.rawValue),
                isOffline: false
            ),
            .monitoringBeforeDeparture
        )

        var staleJourney = TestFactory.journey(
            scheduledDeparture: "2026-01-10T10:30:00.000Z",
            scheduledArrival: "2026-01-10T11:20:00.000Z",
            originPlatform: "4",
            realtimePlatform: "4"
        )
        staleJourney.realtimeUpdatedAt = "2026-01-10T10:00:00.000Z"
        let staleRecommendation = TestFactory.recommendation(journey: staleJourney)
        XCTAssertEqual(
            ActiveWindowPresentation.journeyMoment(for: staleRecommendation, now: now),
            .staleData
        )
        XCTAssertEqual(
            ActiveWindowPresentation.journeyMoment(for: staleRecommendation, now: now, isOffline: true),
            .offline
        )
    }

    @MainActor
    func testSharedJourneyCustomDeepLinkLoadsPublicShareWhenSignedOut() async {
        let apiClient = FakeAPIClient()
        apiClient.publicJourneyShareResult = .success(TestFactory.publicJourneyShare(shareID: "share-1"))
        let model = makeModel(apiClient: apiClient)

        await model.openDeepLink(URL(string: "righttrain://journey-shares/share-1")!)

        XCTAssertEqual(apiClient.publicJourneyShareRequests, ["share-1"])
        XCTAssertEqual(model.sharedJourneyID, "share-1")
        XCTAssertEqual(model.selectedSharedJourney?.shareId, "share-1")
        XCTAssertEqual(model.selectedTab, .active)
        XCTAssertNil(model.pendingRoute)
    }

    @MainActor
    func testSharedJourneyUniversalLinkRoutesInsideSignedInApp() async {
        let apiClient = FakeAPIClient()
        let user = TestFactory.user()
        apiClient.currentUserResult = .success(user)
        apiClient.publicJourneyShareResult = .success(TestFactory.publicJourneyShare(shareID: "share-web"))
        let sessionStore = FakeSessionStore()
        sessionStore.session = TestFactory.storedSession(user: user, accessToken: "token")
        let model = makeModel(apiClient: apiClient, sessionStore: sessionStore)
        await model.bootstrap()

        await model.openDeepLink(URL(string: "https://righttrain.app/j/share-web")!)

        XCTAssertEqual(apiClient.publicJourneyShareRequests, ["share-web"])
        XCTAssertEqual(model.sharedJourneyID, "share-web")
        XCTAssertEqual(model.pendingRoute, .sharedJourney("share-web"))
        XCTAssertEqual(model.selectedTab, .active)
    }

    @MainActor
    func testUS4SharedJourneyUnavailableDeepLinkShowsScopedUnavailableState() async {
        let apiClient = FakeAPIClient()
        apiClient.publicJourneyShareResult = .failure(TestFactory.notFoundError(message: "Shared journey not found"))
        let model = makeModel(apiClient: apiClient)

        await model.openDeepLink(URL(string: "righttrain://journey-shares/missing-share")!)

        XCTAssertEqual(apiClient.publicJourneyShareRequests, ["missing-share"])
        XCTAssertEqual(model.sharedJourneyID, "missing-share")
        XCTAssertNil(model.selectedSharedJourney)
        XCTAssertEqual(model.selectedTab, .active)
        XCTAssertNil(model.pendingRoute)
        XCTAssertNil(model.alertState)
    }

    func testUS4SharedJourneyExpiredPublicViewUsesUnavailableState() {
        var share = TestFactory.publicJourneyShare(shareID: "expired-share")
        share.expiresAt = TestFactory.now.addingTimeInterval(-60)

        XCTAssertTrue(SharedJourneyPresentation.isExpired(share, now: TestFactory.now))
    }

    func testUS4SharedJourneyPublicStatusLabelsStayConsistent() {
        XCTAssertEqual(
            SharedJourneyPresentation.statusText(status: "on_time", statusText: ""),
            "On time"
        )
        XCTAssertEqual(
            SharedJourneyPresentation.statusText(status: "delayed", statusText: "Delayed 8 min"),
            "Delayed 8 min"
        )
        XCTAssertEqual(
            SharedJourneyPresentation.statusText(status: "cancelled", statusText: ""),
            "Cancelled"
        )
        XCTAssertEqual(
            SharedJourneyPresentation.statusTone(status: "delayed", statusText: "Delayed 8 min"),
            .amber
        )
    }

    @MainActor
    func testJourneyDetailLoadsKeepSameServiceSegmentsDistinct() async {
        let apiClient = FakeAPIClient()
        var firstDetail = TestFactory.journeyDetail(serviceID: 333)
        firstDetail.originTpl = "orig-a"
        firstDetail.destinationTpl = "dest-a"
        firstDetail.originName = "Origin A"
        firstDetail.destinationName = "Destination A"
        var secondDetail = TestFactory.journeyDetail(serviceID: 333)
        secondDetail.originTpl = "orig-b"
        secondDetail.destinationTpl = "dest-b"
        secondDetail.originName = "Origin B"
        secondDetail.destinationName = "Destination B"
        apiClient.journeyDetailResults = [.success(firstDetail), .success(secondDetail)]
        let model = makeModel(apiClient: apiClient)

        await model.loadJourneyDetail(serviceID: 333, originTPL: "orig-a", destinationTPL: "dest-a")
        await model.loadJourneyDetail(serviceID: 333, originTPL: "orig-b", destinationTPL: "dest-b")

        XCTAssertEqual(apiClient.journeyDetailRequests.count, 2)
        XCTAssertEqual(
            model.journeyDetailViewModel.detail(
                for: JourneyDetailIdentity(serviceID: 333, originTPL: "orig-a", destinationTPL: "dest-a")
            )?.originName,
            "Origin A"
        )
        XCTAssertEqual(
            model.journeyDetailViewModel.detail(
                for: JourneyDetailIdentity(serviceID: 333, originTPL: "orig-b", destinationTPL: "dest-b")
            )?.originName,
            "Origin B"
        )
    }

    @MainActor
    func testJourneyDetailStaleResponseDoesNotReplaceNewerDetail() async {
        let apiClient = FakeAPIClient()
        let firstRequestStarted = expectation(description: "first detail request started")
        var firstContinuation: CheckedContinuation<JourneyDetail, Never>?
        var requestCount = 0
        var staleDetail = TestFactory.journeyDetail(serviceID: 333)
        staleDetail.destinationName = "Stale Destination"
        var freshDetail = TestFactory.journeyDetail(serviceID: 333)
        freshDetail.destinationName = "Fresh Destination"
        apiClient.journeyDetailHandler = { _, _, _ in
            requestCount += 1
            if requestCount == 1 {
                firstRequestStarted.fulfill()
                return await withCheckedContinuation { continuation in
                    firstContinuation = continuation
                }
            }
            return freshDetail
        }
        let model = makeModel(apiClient: apiClient)

        let staleLoad = Task {
            await model.loadJourneyDetail(
                serviceID: 333,
                originTPL: "orig",
                destinationTPL: "dest",
                showLoading: false
            )
        }
        await fulfillment(of: [firstRequestStarted], timeout: 1.0)

        let freshLoad = await model.loadJourneyDetail(
            serviceID: 333,
            originTPL: "orig",
            destinationTPL: "dest",
            showLoading: false
        )
        firstContinuation?.resume(returning: staleDetail)
        let staleLoadResult = await staleLoad.value

        XCTAssertEqual(freshLoad?.destinationName, "Fresh Destination")
        XCTAssertNil(staleLoadResult)
        XCTAssertEqual(model.selectedJourneyDetail?.destinationName, "Fresh Destination")
        XCTAssertEqual(
            model.journeyDetailViewModel.detail(
                for: JourneyDetailIdentity(serviceID: 333, originTPL: "orig", destinationTPL: "dest")
            )?.destinationName,
            "Fresh Destination"
        )
    }

    @MainActor
    func testJourneyDetailRefreshUpdatesSelectionWithoutLoadingOverlay() async {
        let apiClient = FakeAPIClient()
        apiClient.journeyDetailResult = .success(TestFactory.journeyDetail(serviceID: 333))
        let model = makeModel(apiClient: apiClient)

        await model.loadJourneyDetail(
            serviceID: 333,
            showLoading: false
        )

        XCTAssertEqual(model.selectedJourneyDetail?.serviceId, 333)
        XCTAssertFalse(model.isLoading)
    }

    @MainActor
    func testWindowDeepLinkStillRefreshesWindowSubscription() async {
        let apiClient = FakeAPIClient()
        let sessionStore = FakeSessionStore()
        sessionStore.session = TestFactory.storedSession(accessToken: "deep-link-token")
        apiClient.currentUserResult = .success(TestFactory.user())
        apiClient.activeWindowResult = .failure(TestFactory.notFoundError())
        apiClient.windowResult = .success(TestFactory.window(id: "deep-window"))
        let model = makeModel(apiClient: apiClient, sessionStore: sessionStore)
        await model.bootstrap()

        await model.openDeepLink(URL(string: "righttrain://windows/direct/subscriptions/deep-window")!)

        XCTAssertEqual(apiClient.getWindowRequests.last?.id, "deep-window")
        XCTAssertEqual(apiClient.getWindowRequests.last?.accessToken, "deep-link-token")
        XCTAssertEqual(model.activeWindow?.id, "deep-window")
    }

    @MainActor
    func testActiveWindowRefreshHapticsSkipFirstLoadAndFireForDelayCancellationAndRecommendationSwitch() async {
        let apiClient = FakeAPIClient()
        let sessionStore = FakeSessionStore()
        let feedbackGenerator = FakeNotificationFeedbackGenerator()
        let firstRecommendation = TestFactory.recommendation(rank: 1, serviceID: 111)
        let firstWindow = TestFactory.window(
            id: "haptic-window",
            selectedRecommendation: firstRecommendation,
            recommendations: [firstRecommendation]
        )
        sessionStore.session = TestFactory.storedSession(accessToken: "haptic-token")
        apiClient.currentUserResult = .success(TestFactory.user())
        apiClient.activeWindowResult = .success(firstWindow)
        let model = makeModel(
            apiClient: apiClient,
            sessionStore: sessionStore,
            notificationFeedbackGenerator: feedbackGenerator
        )

        await model.bootstrap()

        XCTAssertTrue(feedbackGenerator.types.isEmpty)

        let delayedRecommendation = TestFactory.recommendation(
            rank: 1,
            serviceID: 111,
            journey: TestFactory.journey(serviceID: 111, displayStatus: "delayed"),
            score: TestFactory.score(delayMinutes: 12)
        )
        apiClient.windowResult = .success(TestFactory.window(
            id: "haptic-window",
            selectedRecommendation: delayedRecommendation,
            recommendations: [delayedRecommendation]
        ))

        await model.refreshActiveWindow()

        XCTAssertEqual(feedbackGenerator.types, [.warning])

        let cancelledRecommendation = TestFactory.recommendation(
            rank: 1,
            serviceID: 111,
            journey: TestFactory.journey(serviceID: 111, cancelled: true),
            score: TestFactory.score(delayMinutes: 12)
        )
        apiClient.windowResult = .success(TestFactory.window(
            id: "haptic-window",
            selectedRecommendation: cancelledRecommendation,
            recommendations: [cancelledRecommendation]
        ))

        await model.refreshActiveWindow()

        XCTAssertEqual(feedbackGenerator.types, [.warning, .error])

        let alternateRecommendation = TestFactory.recommendation(rank: 1, serviceID: 222)
        apiClient.windowResult = .success(TestFactory.window(
            id: "haptic-window",
            selectedRecommendation: alternateRecommendation,
            recommendations: [alternateRecommendation]
        ))

        await model.refreshActiveWindow()

        XCTAssertEqual(feedbackGenerator.types, [.warning, .error, .success])
    }

    @MainActor
    func testActiveWindowRefreshDoesNotFireHapticsWhileBackgrounded() async {
        let apiClient = FakeAPIClient()
        let sessionStore = FakeSessionStore()
        let feedbackGenerator = FakeNotificationFeedbackGenerator()
        let applicationStateProvider = FakeApplicationStateProvider()
        let firstRecommendation = TestFactory.recommendation(rank: 1, serviceID: 111)
        let firstWindow = TestFactory.window(
            id: "background-haptic-window",
            selectedRecommendation: firstRecommendation,
            recommendations: [firstRecommendation]
        )
        sessionStore.session = TestFactory.storedSession(accessToken: "background-token")
        apiClient.currentUserResult = .success(TestFactory.user())
        apiClient.activeWindowResult = .success(firstWindow)
        let model = makeModel(
            apiClient: apiClient,
            sessionStore: sessionStore,
            notificationFeedbackGenerator: feedbackGenerator,
            applicationStateProvider: applicationStateProvider
        )
        await model.bootstrap()

        applicationStateProvider.applicationState = .background
        let delayedRecommendation = TestFactory.recommendation(
            rank: 1,
            serviceID: 111,
            journey: TestFactory.journey(serviceID: 111, displayStatus: "delayed"),
            score: TestFactory.score(delayMinutes: 8)
        )
        apiClient.windowResult = .success(TestFactory.window(
            id: "background-haptic-window",
            selectedRecommendation: delayedRecommendation,
            recommendations: [delayedRecommendation]
        ))

        await model.refreshActiveWindow()

        XCTAssertTrue(feedbackGenerator.types.isEmpty)
    }

    @MainActor
    func testCommuteRoutinesRefreshAndCreateUseBearerToken() async {
        let apiClient = FakeAPIClient()
        let sessionStore = FakeSessionStore()
        let routine = TestFactory.commuteRoutine(id: "routine-create")
        sessionStore.session = TestFactory.storedSession(accessToken: "commute-token")
        apiClient.currentUserResult = .success(TestFactory.user())
        apiClient.activeWindowResult = .failure(TestFactory.notFoundError())
        apiClient.commuteRoutinesResult = .success([routine])
        apiClient.commuteRoutineResult = .success(routine)
        apiClient.stationSearchResultsByQuery = [
            "AAA": [TestFactory.station(crs: "AAA", name: "Origin")],
            "BBB": [TestFactory.station(crs: "BBB", name: "Destination")]
        ]
        let model = makeModel(apiClient: apiClient, sessionStore: sessionStore)

        await model.bootstrap()

        XCTAssertEqual(model.commuteRoutines.map(\.id), ["routine-create"])
        XCTAssertEqual(apiClient.listCommuteRoutineAccessTokens.last, "commute-token")
        XCTAssertEqual(model.commuteRoutinesViewModel.stationName(for: "AAA"), "Origin")
        XCTAssertEqual(model.commuteRoutinesViewModel.stationName(for: "BBB"), "Destination")

        let input = CommuteRoutineMutationRequest(
            name: "Morning",
            status: "active",
            originCrs: "AAA",
            destinationCrs: "BBB",
            departureTime: "08:15",
            windowMinutes: 120,
            activeWeekdays: [1, 2, 3, 4, 5],
            autoArmEnabled: true,
            autoArmLeadMinutes: 30,
            notificationsEnabled: true
        )
        await model.commuteRoutinesViewModel.createRoutine(input)

        XCTAssertEqual(apiClient.createCommuteRoutineRequests.last?.accessToken, "commute-token")
        XCTAssertEqual(apiClient.createCommuteRoutineRequests.last?.input.autoArmLeadMinutes, 30)
    }

    @MainActor
    func testCommuteStationDefaultsUpdateReplacesStoredUser() async {
        let apiClient = FakeAPIClient()
        let sessionStore = FakeSessionStore()
        sessionStore.session = TestFactory.storedSession(accessToken: "defaults-token")
        apiClient.currentUserResult = .success(TestFactory.user())
        apiClient.activeWindowResult = .failure(TestFactory.notFoundError())
        apiClient.commuteRoutinesResult = .success([])
        var updatedUser = TestFactory.user()
        updatedUser.stationDefaults = UserStationDefaults(homeStationCrs: "BTN", workStationCrs: "LBG")
        apiClient.updateStationDefaultsResult = .success(updatedUser)
        let model = makeModel(apiClient: apiClient, sessionStore: sessionStore)
        await model.bootstrap()

        await model.commuteRoutinesViewModel.updateStationDefaults(homeStationCRS: "btn", workStationCRS: "lbg")

        XCTAssertEqual(apiClient.updateStationDefaultsRequests.last?.accessToken, "defaults-token")
        XCTAssertEqual(apiClient.updateStationDefaultsRequests.last?.input.homeStationCrs, "BTN")
        XCTAssertEqual(model.user?.stationDefaults.workStationCrs, "LBG")
        XCTAssertEqual(sessionStore.session?.user.stationDefaults.homeStationCrs, "BTN")
    }

    @MainActor
    func testBoardItineraryLegPinsFirstLegForExplicitBoarding() async {
        let apiClient = FakeAPIClient()
        apiClient.boardItineraryLegResult = .success(TestFactory.itinerarySubscription())
        let viewModel = makeActiveWindowViewModel(apiClient: apiClient)

        await viewModel.boardItineraryLeg(0, itineraryID: "itinerary-1")

        XCTAssertEqual(apiClient.boardItineraryLegRequests.last?.id, "itinerary-1")
        XCTAssertEqual(apiClient.boardItineraryLegRequests.last?.legIndex, 0)
        XCTAssertEqual(apiClient.boardItineraryLegRequests.last?.pinFirstLeg, true)
    }

    @MainActor
    func testCreateJourneyShareURLUsesActiveWindowSubscription() async {
        let apiClient = FakeAPIClient()
        apiClient.windowResult = .success(TestFactory.window(id: "window-share"))
        apiClient.createJourneyShareResult = .success(JourneyShareResponse(
            shareId: "share-window",
            shareUrl: "https://righttrain.app/j/share-window",
            appUrl: "righttrain://journey-shares/share-window",
            expiresAt: TestFactory.now.addingTimeInterval(3600)
        ))
        let viewModel = makeActiveWindowViewModel(apiClient: apiClient)

        await viewModel.openWindowDeepLink(windowID: "window-share")
        let url = await viewModel.createJourneyShareURL()

        XCTAssertEqual(url?.absoluteString, "https://righttrain.app/j/share-window")
        XCTAssertEqual(apiClient.createJourneyShareRequests.last?.input.windowSubscriptionId, "window-share")
        XCTAssertNil(apiClient.createJourneyShareRequests.last?.input.itinerarySubscriptionId)
        XCTAssertEqual(apiClient.createJourneyShareRequests.last?.accessToken, "token")
    }

    @MainActor
    func testCreateJourneyShareURLUsesActiveItinerarySubscription() async {
        let apiClient = FakeAPIClient()
        apiClient.activeItineraryResult = .success(TestFactory.itinerarySubscription(id: "itinerary-share"))
        apiClient.createJourneyShareResult = .success(JourneyShareResponse(
            shareId: "share-itinerary",
            shareUrl: "https://righttrain.app/j/share-itinerary",
            appUrl: "righttrain://journey-shares/share-itinerary",
            expiresAt: TestFactory.now.addingTimeInterval(3600)
        ))
        let viewModel = makeActiveWindowViewModel(apiClient: apiClient)

        await viewModel.refreshActiveWindow(showLoading: false)
        let url = await viewModel.createJourneyShareURL()

        XCTAssertEqual(url?.absoluteString, "https://righttrain.app/j/share-itinerary")
        XCTAssertEqual(apiClient.createJourneyShareRequests.last?.input.itinerarySubscriptionId, "itinerary-share")
        XCTAssertNil(apiClient.createJourneyShareRequests.last?.input.windowSubscriptionId)
        XCTAssertEqual(apiClient.createJourneyShareRequests.last?.accessToken, "token")
    }

    @MainActor
    func testBoardItineraryLegCanSkipPinningForAutomaticDetection() async {
        let apiClient = FakeAPIClient()
        apiClient.boardItineraryLegResult = .success(TestFactory.itinerarySubscription())
        let viewModel = makeActiveWindowViewModel(apiClient: apiClient)

        await viewModel.boardItineraryLeg(0, itineraryID: "itinerary-1", pinFirstLeg: false)

        XCTAssertEqual(apiClient.boardItineraryLegRequests.last?.id, "itinerary-1")
        XCTAssertEqual(apiClient.boardItineraryLegRequests.last?.legIndex, 0)
        XCTAssertEqual(apiClient.boardItineraryLegRequests.last?.pinFirstLeg, false)
    }

    func testItineraryInterchangeRegionIdentifierRoundTripsCRS() {
        let identifier = SystemStationProximityMonitor.itineraryInterchangeRegionIdentifier(
            itineraryID: "itinerary-1",
            legIndex: 2,
            crs: " cre "
        )

        let parsed = SystemStationProximityMonitor.parseItineraryInterchangeRegionIdentifier(identifier)

        XCTAssertEqual(parsed?.itineraryID, "itinerary-1")
        XCTAssertEqual(parsed?.legIndex, 2)
        XCTAssertEqual(parsed?.crs, "CRE")
    }

    func testItineraryInterchangeRegionIdentifierParsesLegacyIdentifierWithoutCRS() {
        let parsed = SystemStationProximityMonitor.parseItineraryInterchangeRegionIdentifier(
            "righttrain.itinerary.interchange.itinerary-1.2"
        )

        XCTAssertEqual(parsed?.itineraryID, "itinerary-1")
        XCTAssertEqual(parsed?.legIndex, 2)
        XCTAssertEqual(parsed?.crs, "")
    }

    @MainActor
    private func makeModel(
        apiClient: FakeAPIClient = FakeAPIClient(),
        sessionStore: FakeSessionStore = FakeSessionStore(),
        notificationAuthorizer: FakeNotificationAuthorizer = FakeNotificationAuthorizer(),
        liveActivityCoordinator: FakeLiveActivityCoordinator = FakeLiveActivityCoordinator(),
        pushNotificationCoordinator: FakePushNotificationCoordinator = FakePushNotificationCoordinator(),
        storeKitSubscriptionService: FakeStoreKitSubscriptionService? = nil,
        deviceIdentityService: FakeDeviceIdentityService? = nil,
        accountCredentialService: FakeAccountCredentialService? = nil,
        notificationFeedbackGenerator: FakeNotificationFeedbackGenerator = FakeNotificationFeedbackGenerator(),
        applicationStateProvider: FakeApplicationStateProvider = FakeApplicationStateProvider(),
        activeJourneyCache: ActiveJourneyCache? = nil,
        journeyMutationQueue: JourneyMutationQueue? = nil
    ) -> AppModel {
        let storeKitSubscriptionService = storeKitSubscriptionService ?? FakeStoreKitSubscriptionService()
        let journeyMutationQueue = journeyMutationQueue ?? JourneyMutationQueue(defaults: makeIsolatedDefaults())
        return AppModel(
            apiClient: apiClient,
            sessionStore: sessionStore,
            notificationAuthorizer: notificationAuthorizer,
            liveActivityCoordinator: liveActivityCoordinator,
            pushNotificationCoordinator: pushNotificationCoordinator,
            storeKitSubscriptionService: storeKitSubscriptionService,
            deviceIdentityService: deviceIdentityService ?? FakeDeviceIdentityService(),
            accountCredentialService: accountCredentialService ?? FakeAccountCredentialService(),
            notificationFeedbackGenerator: notificationFeedbackGenerator,
            applicationStateProvider: applicationStateProvider,
            activeJourneyCache: activeJourneyCache,
            journeyMutationQueue: journeyMutationQueue
        )
    }

    @MainActor
    private func makeActiveWindowViewModel(
        apiClient: FakeAPIClient = FakeAPIClient(),
        liveActivityCoordinator: FakeLiveActivityCoordinator = FakeLiveActivityCoordinator()
    ) -> ActiveWindowViewModel {
        ActiveWindowViewModel(
            apiClient: apiClient,
            operationState: AppOperationState(),
            liveActivityCoordinator: liveActivityCoordinator,
            stationProximityMonitor: NoopStationProximityMonitor(),
            registrationContextFactory: DeviceRegistrationContextFactory(apiClient: apiClient),
            accessTokenProvider: { "token" },
            notificationFeedbackGenerator: FakeNotificationFeedbackGenerator(),
            applicationStateProvider: FakeApplicationStateProvider()
        )
    }

    @MainActor
    private func waitForAuthInvalidation(_ model: AppModel) async {
        for _ in 0..<20 {
            if model.accessToken == nil {
                return
            }
            await Task.yield()
        }
    }

    @MainActor
    private func waitForPendingRoute(_ model: AppModel, route: AppRoute) async {
        for _ in 0..<40 {
            if model.pendingRoute == route {
                return
            }
            await Task.yield()
        }
    }

    private func resetAppModelDefaults() {
        UserDefaults.standard.removeObject(forKey: "righttrain.ios.activeWindowID")
        UserDefaults.standard.removeObject(forKey: "righttrain.ios.activeItineraryID")
        UserDefaults.standard.removeObject(forKey: "righttrain.ios.pinnedLiveActivityServiceID")
        UserDefaults.standard.removeObject(forKey: "righttrain.ios.handledDepartedPromptKeys")
        UserDefaults.standard.removeObject(forKey: "righttrain.ios.activeJourneyCache")
        UserDefaults.standard.removeObject(forKey: "righttrain.ios.journeyMutationQueue")
        UserDefaults.standard.removeObject(forKey: "righttrain.ios.clientDeviceID")
        _ = LiveActivityIntentActionStore.drainPendingActions()
        LiveActivityIntentActionStore.alertsSnoozedUntil = nil
    }

    private func makeIsolatedDefaults() -> UserDefaults {
        let suiteName = "RightTrainTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
