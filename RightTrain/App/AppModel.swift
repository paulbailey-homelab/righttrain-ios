import Foundation
import UserNotifications

typealias AppModel = AppCoordinator

enum AppTab: Hashable {
    case active
    case commutes
    case plan
    case settings
}

enum AppRoute: Hashable {
    case journeyDetail(JourneyDetailIdentity)
    case notificationDetail(WindowNotificationDetailIdentity)
    case sharedJourney(String)
}

#if DEBUG
enum DebugPlanPreviewRoute: Hashable {
    case searchResults
}
#endif

struct WindowNotificationDetailIdentity: Hashable {
    var windowSubscriptionID: String
    var notificationID: String

    init(windowSubscriptionID: String, notificationID: String) {
        self.windowSubscriptionID = windowSubscriptionID
        self.notificationID = notificationID
    }

    init(detail: WindowSubscriptionNotificationDetail) {
        self.init(
            windowSubscriptionID: detail.windowSubscriptionId,
            notificationID: detail.id
        )
    }
}

@MainActor
@Observable
final class AppCoordinator {
    private(set) var isBootstrapping = true
    var selectedTab: AppTab = .active
    private(set) var pendingRoute: AppRoute?
    private(set) var planResetRequestID = 0
#if DEBUG
    var debugInitialPlanRoute: DebugPlanPreviewRoute?
#endif
    private(set) var notificationDetails: [WindowNotificationDetailIdentity: WindowSubscriptionNotificationDetail] = [:]
    private(set) var sharedJourneyID: String?
    private(set) var sharedJourneys: [String: PublicJourneyShare] = [:]

    let operationState: AppOperationState
    let connectivityService: ConnectivityService
    let journeyMutationQueue: JourneyMutationQueue
    let authViewModel: AuthViewModel
    let windowSetupViewModel: WindowSetupViewModel
    let commuteRoutinesViewModel: CommuteRoutinesViewModel
    let activeWindowViewModel: ActiveWindowViewModel
    let journeyDetailViewModel: JourneyDetailViewModel
    let notificationViewModel: NotificationViewModel
    let subscriptionViewModel: SubscriptionViewModel
    @ObservationIgnored private let apiClient: any APIClienting
    @ObservationIgnored private var pushNotificationResponseObserverTask: Task<Void, Never>?

    init(
        apiClient: any APIClienting,
        sessionStore: SessionStoring,
        notificationAuthorizer: NotificationAuthorizing,
        liveActivityCoordinator: LiveActivityCoordinating = NoopLiveActivityCoordinator(),
        pushNotificationCoordinator: PushNotificationCoordinating = NoopPushNotificationCoordinator(),
        storeKitSubscriptionService: any StoreKitSubscriptionServicing,
        deviceIdentityService: (any DeviceIdentityHandling)? = nil,
        accountCredentialService: (any AccountCredentialHandling)? = nil,
        notificationFeedbackGenerator: any NotificationFeedbackGenerating = SystemNotificationFeedbackGenerator(),
        applicationStateProvider: any ApplicationStateProviding = SystemApplicationStateProvider(),
        stationProximityMonitor: any StationProximityMonitoring = SystemStationProximityMonitor(),
        connectivityService: ConnectivityService? = nil,
        activeJourneyCache: ActiveJourneyCache? = nil,
        journeyMutationQueue: JourneyMutationQueue? = nil
    ) {
        let operationState = AppOperationState()
        let connectivityService = connectivityService ?? ConnectivityService()
        let activeJourneyCache = activeJourneyCache ?? ActiveJourneyCache()
        let journeyMutationQueue = journeyMutationQueue ?? JourneyMutationQueue()
        self.apiClient = apiClient
        self.connectivityService = connectivityService
        self.journeyMutationQueue = journeyMutationQueue
        connectivityService.startMonitoring()
        let registrationContextFactory = DeviceRegistrationContextFactory(apiClient: apiClient)
        let authViewModel = AuthViewModel(
            apiClient: apiClient,
            sessionStore: sessionStore,
            operationState: operationState,
            deviceIdentityService: deviceIdentityService,
            accountCredentialService: accountCredentialService
        )
        let activeWindowViewModel = ActiveWindowViewModel(
            apiClient: apiClient,
            operationState: operationState,
            liveActivityCoordinator: liveActivityCoordinator,
            stationProximityMonitor: stationProximityMonitor,
            registrationContextFactory: registrationContextFactory,
            accessTokenProvider: { authViewModel.usableAccessToken },
            notificationFeedbackGenerator: notificationFeedbackGenerator,
            applicationStateProvider: applicationStateProvider,
            activeJourneyCache: activeJourneyCache,
            mutationQueue: journeyMutationQueue,
            connectivityService: connectivityService
        )
        let journeyDetailViewModel = JourneyDetailViewModel(
            apiClient: apiClient,
            operationState: operationState
        )
        let notificationViewModel = NotificationViewModel(
            notificationAuthorizer: notificationAuthorizer,
            pushNotificationCoordinator: pushNotificationCoordinator,
            operationState: operationState,
            registrationContextFactory: registrationContextFactory,
            accessTokenProvider: { authViewModel.usableAccessToken }
        )
        let commuteRoutinesViewModel = CommuteRoutinesViewModel(
            apiClient: apiClient,
            operationState: operationState,
            accessTokenProvider: { authViewModel.usableAccessToken },
            userUpdateHandler: { authViewModel.replaceCurrentUser($0) }
        )
        let subscriptionViewModel = SubscriptionViewModel(
            apiClient: apiClient,
            storeKitService: storeKitSubscriptionService,
            operationState: operationState,
            accessTokenProvider: { authViewModel.usableAccessToken },
            userProvider: { authViewModel.user },
            userUpdateHandler: { authViewModel.replaceCurrentUser($0) }
        )
        let windowSetupViewModel = WindowSetupViewModel(
            apiClient: apiClient,
            operationState: operationState,
            activeWindowViewModel: activeWindowViewModel,
            isSignedInProvider: { authViewModel.isSignedIn }
        )

        self.operationState = operationState
        self.authViewModel = authViewModel
        self.windowSetupViewModel = windowSetupViewModel
        self.commuteRoutinesViewModel = commuteRoutinesViewModel
        self.activeWindowViewModel = activeWindowViewModel
        self.journeyDetailViewModel = journeyDetailViewModel
        self.notificationViewModel = notificationViewModel
        self.subscriptionViewModel = subscriptionViewModel

        operationState.authFailureHandler = { [weak authViewModel] in
            await authViewModel?.invalidateCurrentSession(reason: "api_session_invalid")
        }
        activeWindowViewModel.didClearActiveWindowState = { [weak windowSetupViewModel] in
            windowSetupViewModel?.clearState()
        }
        authViewModel.lifecycleObserver = self
        observePushNotificationResponses()
    }

    deinit {
        pushNotificationResponseObserverTask?.cancel()
    }

    /// How long the startup splash may block the UI. Bootstrap network calls
    /// (connectivity probe, session refresh) can take multiple 20s request
    /// timeouts back to back when the backend is unreachable; past this point
    /// the app renders whatever state it has and bootstrap finishes behind it.
    static let bootstrapSplashTimeout: Duration = .seconds(5)

    func bootstrap() async {
        isBootstrapping = true
        defer { isBootstrapping = false }

        let splashWatchdog = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.bootstrapSplashTimeout)
            guard let self, !Task.isCancelled, self.isBootstrapping else { return }
            self.isBootstrapping = false
            BetaDiagnostics.record("bootstrap_splash_timeout", severity: .warning)
        }
        defer { splashWatchdog.cancel() }

        await notificationViewModel.refreshStatus()
        await connectivityService.refreshBackendStatus(apiClient: apiClient)
        BetaDiagnostics.record("bootstrap_started", details: "notificationStatus=\(notificationViewModel.notificationStatus.diagnosticsName)")
        await authViewModel.bootstrap()
        if authViewModel.isSignedIn {
            activeWindowViewModel.restoreCachedActiveJourneyIfPossible()
            await activeWindowViewModel.flushQueuedMutations()
        }
    }

    func refreshConnectivityAndFlushQueuedMutations() async {
        // Drop stale pooled sockets first so the connectivity probe (and the
        // requests that follow) open fresh connections instead of failing on a
        // socket the load balancer closed while we were backgrounded. Without
        // this, the banner briefly flashes "patchy" on every foreground.
        await apiClient.resetPooledConnections()
        await connectivityService.refreshBackendStatus(apiClient: apiClient)
        await activeWindowViewModel.flushQueuedMutations()
    }

    func flushQueuedMutationsForBackground() async {
        guard authViewModel.usableAccessToken != nil else {
            return
        }
        await refreshConnectivityAndFlushQueuedMutations()
    }

    func openDeepLink(_ url: URL) async {
        guard let scheme = url.scheme,
              let host = url.host else {
            return
        }
        let path = url.pathComponents.filter { $0 != "/" }

        if scheme.caseInsensitiveCompare("https") == .orderedSame {
            await openHTTPSDeepLink(host: host, path: path)
            return
        }

        guard scheme.caseInsensitiveCompare("righttrain") == .orderedSame else {
            return
        }

        switch host.lowercased() {
        case "active":
            selectedTab = .active
        case "windows":
            await openWindowDeepLink(path)
        case "journeys":
            await openJourneyDeepLink(path)
        case "journey-shares":
            await openSharedJourneyDeepLink(path)
        default:
            return
        }
    }

    private func openHTTPSDeepLink(host: String, path: [String]) async {
        guard host.caseInsensitiveCompare("righttrain.app") == .orderedSame ||
              host.caseInsensitiveCompare("www.righttrain.app") == .orderedSame else {
            return
        }
        guard path.count == 2,
              path[0].caseInsensitiveCompare("j") == .orderedSame else {
            return
        }
        await loadSharedJourney(shareID: path[1])
    }

    private func openWindowDeepLink(_ path: [String]) async {
        guard path.count >= 3,
              path[0].caseInsensitiveCompare("direct") == .orderedSame,
              path[1].caseInsensitiveCompare("subscriptions") == .orderedSame else {
            return
        }
        let windowID = path[2]
        if path.count == 5,
           path[3].caseInsensitiveCompare("notifications") == .orderedSame {
            await openWindowNotificationDetail(windowID: windowID, notificationID: path[4])
            return
        }
        guard path.count == 3 else {
            return
        }
        selectedTab = .active
        await activeWindowViewModel.openWindowDeepLink(windowID: windowID)
    }

    private func openJourneyDeepLink(_ path: [String]) async {
        guard path.count == 1,
              let serviceID = Int(path[0]) else {
            return
        }
        if let detail = await journeyDetailViewModel.loadJourneyDetail(
            serviceID: serviceID
        ) {
            selectedTab = .active
            pendingRoute = .journeyDetail(JourneyDetailIdentity(detail: detail))
        }
    }

    private func openSharedJourneyDeepLink(_ path: [String]) async {
        guard path.count == 1 else {
            return
        }
        await loadSharedJourney(shareID: path[0])
    }

    private func loadSharedJourney(shareID: String) async {
        do {
            let journey = try await apiClient.getJourneyShare(id: shareID)
            sharedJourneys[shareID] = journey
            sharedJourneyID = shareID
            selectedTab = .active
            if authViewModel.isSignedIn {
                pendingRoute = .sharedJourney(shareID)
            }
        } catch {
            sharedJourneys.removeValue(forKey: shareID)
            sharedJourneyID = shareID
            selectedTab = .active
            if authViewModel.isSignedIn {
                pendingRoute = .sharedJourney(shareID)
            }
            if (error as? APIError)?.isNotFound != true {
                operationState.handleOperationError(error)
            }
        }
    }

    func sharedJourney(for shareID: String) -> PublicJourneyShare? {
        sharedJourneys[shareID]
    }

    func dismissSharedJourney() {
        sharedJourneyID = nil
    }

    func consumePendingRoute(_ route: AppRoute? = nil) {
        guard route == nil || pendingRoute == route else {
            return
        }
        pendingRoute = nil
    }

    private func openWindowNotificationDetail(windowID: String, notificationID: String) async {
        selectedTab = .active
        await activeWindowViewModel.openWindowDeepLink(windowID: windowID)
        let fallbackIdentity = WindowNotificationDetailIdentity(
            windowSubscriptionID: windowID,
            notificationID: notificationID
        )
        guard let accessToken = authViewModel.usableAccessToken else {
            pendingRoute = .notificationDetail(fallbackIdentity)
            return
        }
        do {
            let detail = try await apiClient.getWindowSubscriptionNotification(
                windowSubscriptionID: windowID,
                notificationID: notificationID,
                accessToken: accessToken
            )
            let identity = WindowNotificationDetailIdentity(detail: detail)
            notificationDetails[identity] = detail
            pendingRoute = .notificationDetail(identity)
        } catch {
            operationState.recordSilentOperationError(error)
            pendingRoute = .notificationDetail(fallbackIdentity)
        }
    }

    func notificationDetail(for identity: WindowNotificationDetailIdentity) -> WindowSubscriptionNotificationDetail? {
        notificationDetails[identity]
    }

    private func clearNavigationState() {
        pendingRoute = nil
        notificationDetails = [:]
        sharedJourneyID = nil
        sharedJourneys = [:]
    }

    private func observePushNotificationResponses() {
        pushNotificationResponseObserverTask?.cancel()
        pushNotificationResponseObserverTask = Task { [weak self] in
            let stream = NotificationCenter.default.notifications(named: PushNotificationsAppDelegate.didReceiveResponseNotification)
            for await note in stream {
                await self?.handlePushNotificationResponse(note)
            }
        }
    }

    private func handlePushNotificationResponse(_ note: Notification) async {
        let userInfo = note.userInfo ?? [:]
        let actionIdentifier = userInfo[PushNotificationsAppDelegate.actionIdentifierUserInfoKey] as? String
        let windowID = userInfo[PushNotificationsAppDelegate.windowSubscriptionIDUserInfoKey] as? String
        let notificationID = userInfo[PushNotificationsAppDelegate.notificationIDUserInfoKey] as? String
        switch actionIdentifier {
        case PushNotificationsAppDelegate.pinDepartedTrainActionIdentifier:
            guard let windowID,
                  let serviceID = userInfo[PushNotificationsAppDelegate.departedTrainServiceIDUserInfoKey] as? Int else {
                return
            }
            selectedTab = .active
            await pinDepartedTrain(serviceID: serviceID, windowID: windowID)
        case PushNotificationsAppDelegate.monitorNextBestActionIdentifier:
            selectedTab = .active
            let serviceID = userInfo[PushNotificationsAppDelegate.departedTrainServiceIDUserInfoKey] as? Int
            await monitorNextBestAfterDepartedTrain(serviceID: serviceID, windowID: windowID)
        default:
            if let urlString = userInfo[PushNotificationsAppDelegate.urlUserInfoKey] as? String,
               let url = URL(string: urlString) {
                await openDeepLink(url)
                return
            }
            if let windowID, let notificationID {
                await openWindowNotificationDetail(windowID: windowID, notificationID: notificationID)
            }
        }
    }
}

extension AppCoordinator {
    var user: User? { authViewModel.user }
    var activeWindow: WindowSubscription? { activeWindowViewModel.activeWindow }
    var activeItinerary: ItinerarySubscription? { activeWindowViewModel.activeItinerary }
    var commuteRoutines: [CommuteRoutine] { commuteRoutinesViewModel.routines }
    var recommendationResponse: DirectWindowRecommendationResponse? { windowSetupViewModel.recommendationResponse }
    var journeyPlanResponse: JourneyPlanResponse? { windowSetupViewModel.journeyPlanResponse }
    var selectedJourneyDetail: JourneyDetail? { journeyDetailViewModel.selectedJourneyDetail }
    var selectedSharedJourney: PublicJourneyShare? {
        guard let sharedJourneyID else { return nil }
        return sharedJourneys[sharedJourneyID]
    }
    var notificationStatus: UNAuthorizationStatus { notificationViewModel.notificationStatus }
    var pinnedLiveActivityServiceID: Int? { activeWindowViewModel.pinnedLiveActivityServiceID }
    var isSignedIn: Bool { authViewModel.isSignedIn }
    var accessToken: String? { authViewModel.accessToken }

    var stationPickerAPIClient: any APIClienting { apiClient }

    func stationFavourites() -> [StationFavourite] {
        StationFavoritesProvider.favourites(
            homeStationCRS: user?.stationDefaults.homeStationCrs,
            workStationCRS: user?.stationDefaults.workStationCrs,
            routines: commuteRoutines,
            stationResolver: { [commuteRoutinesViewModel] crs in
                commuteRoutinesViewModel.stationSuggestion(for: crs)
            }
        )
    }

    var origin: StationSuggestion? {
        get { windowSetupViewModel.origin }
        set { windowSetupViewModel.origin = newValue }
    }

    var destination: StationSuggestion? {
        get { windowSetupViewModel.destination }
        set { windowSetupViewModel.destination = newValue }
    }

    var departureStart: Date {
        get { windowSetupViewModel.departureStart }
        set { windowSetupViewModel.departureStart = newValue }
    }

    var windowMinutes: Int {
        get { windowSetupViewModel.windowMinutes }
        set { windowSetupViewModel.windowMinutes = newValue }
    }

    var isLoading: Bool {
        get { operationState.isLoading }
        set { operationState.isLoading = newValue }
    }

    var alertState: AppAlertState? {
        get { operationState.alertState }
        set { operationState.alertState = newValue }
    }

    func registerDevice() async {
        await authViewModel.registerDevice()
    }

    var isDeviceAttestationSupported: Bool {
        authViewModel.isDeviceAttestationSupported
    }

    func signOut() async {
        await authViewModel.signOut()
    }

    @discardableResult
    func deleteAccount() async -> Bool {
        await authViewModel.deleteAccount()
    }

    func searchStations(query: String) async throws -> [StationSuggestion] {
        try await windowSetupViewModel.searchStations(query: query)
    }

    func loadRecommendations() async {
        await windowSetupViewModel.loadRecommendations()
    }

    func createActiveWindow(replacingActiveJourney: Bool = false) async {
        await windowSetupViewModel.createActiveWindow(replacingActiveJourney: replacingActiveJourney)
    }

    func createActiveWindow(for recommendation: DirectWindowRecommendation, replacingActiveJourney: Bool = false) async {
        await windowSetupViewModel.createActiveWindow(for: recommendation, replacingActiveJourney: replacingActiveJourney)
    }

    func createActiveItinerary(for itinerary: ItineraryRecommendation, replacingActiveJourney: Bool = false) async {
        await windowSetupViewModel.createActiveItinerary(for: itinerary, replacingActiveJourney: replacingActiveJourney)
    }

    func togglePinnedLiveActivity(for recommendation: DirectWindowRecommendation) async {
        await activeWindowViewModel.togglePinnedLiveActivity(for: recommendation)
    }

    func pinTrain(serviceID: Int, windowID: String? = nil) async {
        await activeWindowViewModel.pinTrain(serviceID: serviceID, windowID: windowID)
    }

    func clearPinnedTrain(windowID: String? = nil) async {
        await activeWindowViewModel.clearPinnedTrain(windowID: windowID)
    }

    func pinDepartedTrain(serviceID: Int, windowID: String? = nil) async {
        activeWindowViewModel.markDepartedPromptHandled(serviceID: serviceID, windowID: windowID)
        await activeWindowViewModel.pinTrain(serviceID: serviceID, windowID: windowID)
    }

    func monitorNextBestAfterDepartedTrain(serviceID: Int?, windowID: String? = nil) async {
        if let serviceID {
            activeWindowViewModel.markDepartedPromptHandled(serviceID: serviceID, windowID: windowID)
        }
        await activeWindowViewModel.clearPinnedTrain(windowID: windowID)
    }

    @discardableResult
    func loadJourneyDetail(
        serviceID: Int,
        originTPL: String? = nil,
        destinationTPL: String? = nil,
        showLoading: Bool = true
    ) async -> JourneyDetail? {
        await journeyDetailViewModel.loadJourneyDetail(
            serviceID: serviceID,
            originTPL: originTPL,
            destinationTPL: destinationTPL,
            showLoading: showLoading
        )
    }

    func dismissJourneyDetail() {
        journeyDetailViewModel.dismiss()
    }

    func refreshActiveWindow(showLoading: Bool = true) async {
        await activeWindowViewModel.refreshActiveWindow(showLoading: showLoading)
    }

    func refreshActiveWindowFromPullGesture() async {
        await activeWindowViewModel.refreshActiveWindowFromPullGesture()
    }

    func monitorActiveWindowForegroundUpdates() async {
        await activeWindowViewModel.monitorActiveWindowForegroundUpdates()
    }

    func deleteActiveWindow() async {
        await activeWindowViewModel.deleteActiveWindow()
    }

    func startNewJourneyPlan() {
        windowSetupViewModel.resetForNewJourneyPlan()
        planResetRequestID += 1
        selectedTab = .plan
    }

    func startJourneyPlan(from routine: CommuteRoutine) {
        windowSetupViewModel.applyRoutinePrefill(
            routine,
            originStation: commuteRoutinesViewModel.stationSuggestion(for: routine.originCrs),
            destinationStation: commuteRoutinesViewModel.stationSuggestion(for: routine.destinationCrs)
        )
        planResetRequestID += 1
        selectedTab = .plan
    }

    func requestNotifications() async {
        await notificationViewModel.requestNotifications()
    }

    func refreshNotificationStatus() async {
        await notificationViewModel.refreshStatus()
    }
}

// MARK: - Session lifecycle

extension AppCoordinator: SessionLifecycleObserver {
    func sessionDidAuthenticate() async {
        activeWindowViewModel.restoreCachedActiveJourneyIfPossible()
        await connectivityService.refreshBackendStatus(apiClient: apiClient)
        await activeWindowViewModel.flushQueuedMutations()
        await activeWindowViewModel.refreshActiveWindow()
        await activeWindowViewModel.prepareLiveActivityRemoteStartRegistration()
        await commuteRoutinesViewModel.refresh()
        await subscriptionViewModel.syncCurrentEntitlementsSilently()
        subscriptionViewModel.startTransactionObserver()
        notificationViewModel.requestRemoteNotificationsRegistrationIfAuthorized()
        await notificationViewModel.registerPendingAPNsTokenIfPossible()
    }

    /// Runs while the session credentials still exist, so remote teardown
    /// (notification unregister, Live Activity token deletion) can authenticate.
    func sessionWillSignOut() async {
        await notificationViewModel.unregisterIfPossible()
        await activeWindowViewModel.endAllLiveActivitiesWithTokenIfPossible()
    }

    /// The one place signed-in state is cleared, whatever ended the session.
    /// Sign-out has already torn down Live Activities in sessionWillSignOut;
    /// the other reasons still hold activities that must be ended here.
    func sessionDidEnd(reason: SessionEndReason) async {
        notificationViewModel.clearLocalState()
        journeyMutationQueue.clear()
        switch reason {
        case .expired, .accountDeleted:
            await activeWindowViewModel.clearStateAndEndLiveActivities()
        case .signedOut:
            activeWindowViewModel.clearState()
        }
        windowSetupViewModel.clearState()
        commuteRoutinesViewModel.clearState()
        subscriptionViewModel.stopTransactionObserver()
        journeyDetailViewModel.dismiss()
        clearNavigationState()
    }
}
