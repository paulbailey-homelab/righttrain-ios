import Foundation
import UIKit
import UserNotifications

protocol NotificationAuthorizing {
    func currentStatus() async -> UNAuthorizationStatus
    func requestAuthorization() async throws -> UNAuthorizationStatus
}

struct SystemNotificationAuthorizer: NotificationAuthorizing {
    func currentStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    func requestAuthorization() async throws -> UNAuthorizationStatus {
        _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
        return await currentStatus()
    }
}

@MainActor
@Observable
final class NotificationViewModel {
    private(set) var notificationStatus: UNAuthorizationStatus = .notDetermined

    @ObservationIgnored private let notificationAuthorizer: NotificationAuthorizing
    @ObservationIgnored private let pushNotificationCoordinator: PushNotificationCoordinating
    @ObservationIgnored private let operationState: AppOperationState
    @ObservationIgnored private let registrationContextFactory: DeviceRegistrationContextFactory
    @ObservationIgnored private let accessTokenProvider: () -> String?
    @ObservationIgnored private var pendingAPNsToken: String?
    @ObservationIgnored private var pushTokenObserverTask: Task<Void, Never>?

    init(
        notificationAuthorizer: NotificationAuthorizing,
        pushNotificationCoordinator: PushNotificationCoordinating,
        operationState: AppOperationState,
        registrationContextFactory: DeviceRegistrationContextFactory,
        accessTokenProvider: @escaping () -> String?
    ) {
        self.notificationAuthorizer = notificationAuthorizer
        self.pushNotificationCoordinator = pushNotificationCoordinator
        self.operationState = operationState
        self.registrationContextFactory = registrationContextFactory
        self.accessTokenProvider = accessTokenProvider
        observePushNotificationTokens()
    }

    func requestNotifications() async {
        do {
            notificationStatus = try await notificationAuthorizer.requestAuthorization()
            requestRemoteNotificationsRegistrationIfAuthorized()
            BetaDiagnostics.record("notification_authorization_updated", details: notificationStatus.diagnosticsName)
        } catch {
            operationState.alertState = .network("Notification permissions could not be updated.")
            BetaDiagnostics.record("notification_authorization_failed", details: error.localizedDescription)
        }
    }

    func refreshStatus() async {
        notificationStatus = await notificationAuthorizer.currentStatus()
    }

    func registerPendingAPNsTokenIfPossible() async {
        guard let token = pendingAPNsToken,
              let context = pushNotificationRegistrationContext() else {
            return
        }
        await pushNotificationCoordinator.register(token: token, context: context)
    }

    func unregisterIfPossible() async {
        guard let context = pushNotificationRegistrationContext() else {
            return
        }
        await pushNotificationCoordinator.unregister(context: context)
    }

    func clearLocalState() {
        pushNotificationCoordinator.clearLocalState()
    }

    func requestRemoteNotificationsRegistrationIfAuthorized() {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral:
            UIApplication.shared.registerForRemoteNotifications()
        default:
            return
        }
    }

    private func observePushNotificationTokens() {
        pushTokenObserverTask?.cancel()
        pushTokenObserverTask = Task { [weak self] in
            let stream = NotificationCenter.default.notifications(named: PushNotificationsAppDelegate.didRegisterTokenNotification)
            for await note in stream {
                guard let self else { return }
                guard let token = note.userInfo?[PushNotificationsAppDelegate.tokenUserInfoKey] as? String, !token.isEmpty else {
                    continue
                }
                await self.handleAPNsTokenUpdate(token)
            }
        }
    }

    private func handleAPNsTokenUpdate(_ token: String) async {
        pendingAPNsToken = token
        await registerPendingAPNsTokenIfPossible()
    }

    private func pushNotificationRegistrationContext() -> PushNotificationRegistrationContext? {
        registrationContextFactory.pushNotificationContext(accessToken: accessTokenProvider())
    }
}

extension UNAuthorizationStatus {
    var diagnosticsName: String {
        switch self {
        case .authorized:
            return "authorized"
        case .denied:
            return "denied"
        case .ephemeral:
            return "ephemeral"
        case .notDetermined:
            return "notDetermined"
        case .provisional:
            return "provisional"
        @unknown default:
            return "unknown"
        }
    }
}
