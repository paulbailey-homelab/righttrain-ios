import OSLog
import SwiftUI

@main
struct RightTrainApp: App {
    @UIApplicationDelegateAdaptor(PushNotificationsAppDelegate.self) private var pushNotificationsDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var appCoordinator: AppCoordinator
#if DEBUG
    private let previewLaunch: RightTrainPreviewLaunch?
    private let liveActivityPreviewLaunch: LiveActivityPreviewLaunch?
#endif

    init() {
        BetaDiagnostics.configure()

#if DEBUG
        let previewLaunch = RightTrainPreviewLaunch(arguments: ProcessInfo.processInfo.arguments)
        let liveActivityPreviewLaunch = LiveActivityPreviewLaunch(arguments: ProcessInfo.processInfo.arguments)
        self.previewLaunch = previewLaunch
        self.liveActivityPreviewLaunch = liveActivityPreviewLaunch
        if let previewLaunch {
            let coordinator = previewLaunch.makeAppCoordinator()
            BackgroundSyncScheduler.shared.register {
                await coordinator.flushQueuedMutationsForBackground()
            }
            _appCoordinator = State(initialValue: coordinator)
            return
        }
#endif

        let apiClient = APIClient(baseURL: AppConfig.apiBaseURL)
        let coordinator = AppCoordinator(
            apiClient: apiClient,
            sessionStore: KeychainSessionStore(),
            notificationAuthorizer: SystemNotificationAuthorizer(),
            liveActivityCoordinator: SystemLiveActivityCoordinator(),
            pushNotificationCoordinator: SystemPushNotificationCoordinator(),
            storeKitSubscriptionService: StoreKitSubscriptionService()
        )
        BackgroundSyncScheduler.shared.register {
            await coordinator.flushQueuedMutationsForBackground()
        }
        _appCoordinator = State(
            initialValue: coordinator
        )
    }

    var body: some Scene {
        WindowGroup {
            rootContent
                .rightTrainAppEnvironment(appCoordinator)
                .task {
                    await appCoordinator.bootstrap()
#if DEBUG
                    await previewLaunch?.prepare(appCoordinator)
                    await liveActivityPreviewLaunch?.start()
#endif
                }
                .onOpenURL { url in
                    Task { await appCoordinator.openDeepLink(url) }
                }
                .onChange(of: scenePhase) { _, phase in
                    BetaDiagnostics.recordScenePhase(phase)
                    guard phase == .active else {
                        return
                    }
                    Task {
                        await appCoordinator.refreshConnectivityAndFlushQueuedMutations()
                        await appCoordinator.refreshActiveWindow(showLoading: false)
                        await appCoordinator.subscriptionViewModel.syncCurrentEntitlementsSilently()
                    }
                }
        }
    }

    @ViewBuilder
    private var rootContent: some View {
#if DEBUG
        if previewLaunch?.usesNotificationPermissionReview == true {
            PreviewNotificationPermissionReviewScreen()
        } else if previewLaunch?.usesOnboardingReview == true {
            PreviewOnboardingReviewScreen()
        } else if previewLaunch?.usesFeedbackReview == true {
            PreviewFeedbackReviewScreen()
        } else {
            ContentView()
        }
#else
        ContentView()
#endif
    }
}

enum BetaDiagnostics {
    private static let previousCrashKey = "righttrain.ios.betaDiagnostics.previousCrash"
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.righttrain.ios",
        category: "beta"
    )
    private static var didConfigure = false

    static func configure(bundle: Bundle = .main, apiBaseURL: URL = AppConfig.apiBaseURL) {
        guard !didConfigure else {
            return
        }
        didConfigure = true

        if let previousCrash = UserDefaults.standard.string(forKey: previousCrashKey), !previousCrash.isEmpty {
            logger.fault("Previous launch ended unexpectedly: \(previousCrash, privacy: .public)")
            UserDefaults.standard.removeObject(forKey: previousCrashKey)
        }

        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        let apnsEnvironment = APNsEnvironment.current(bundle: bundle, fallback: "production")
        logger.notice("RightTrain launch version \(version, privacy: .public) build \(build, privacy: .public) api \(apiBaseURL.absoluteString, privacy: .public) apns \(apnsEnvironment, privacy: .public)")

        NSSetUncaughtExceptionHandler(handleUncaughtBetaException)
    }

    static func record(_ event: String, details: String? = nil) {
        if let details, !details.isEmpty {
            logger.notice("Beta event \(event, privacy: .public): \(details, privacy: .public)")
        } else {
            logger.notice("Beta event \(event, privacy: .public)")
        }
    }

    static func recordScenePhase(_ phase: ScenePhase) {
        let value: String
        switch phase {
        case .active:
            value = "active"
        case .inactive:
            value = "inactive"
        case .background:
            value = "background"
        @unknown default:
            value = "unknown"
        }
        logger.debug("Scene phase changed: \(value, privacy: .public)")
    }

    fileprivate static func recordUncaughtException(_ exception: NSException) {
        let name = exception.name.rawValue
        let reason = exception.reason ?? "No reason"
        let summary = "\(name): \(reason)"
        UserDefaults.standard.set(summary, forKey: previousCrashKey)
        UserDefaults.standard.synchronize()
        logger.fault("Unhandled exception \(name, privacy: .public): \(reason, privacy: .public)")
    }
}

private func handleUncaughtBetaException(_ exception: NSException) {
    BetaDiagnostics.recordUncaughtException(exception)
}
