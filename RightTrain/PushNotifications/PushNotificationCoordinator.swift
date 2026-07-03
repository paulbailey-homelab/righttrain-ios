import Foundation

protocol PushNotificationCoordinating {
    @MainActor
    func register(token: String, context: PushNotificationRegistrationContext) async
    @MainActor
    func unregister(context: PushNotificationRegistrationContext) async
    @MainActor
    func clearLocalState()
}

struct PushNotificationRegistrationContext {
    var apiClient: any APIClienting
    var accessToken: String
    var environment: String
    var clientDeviceID: String
    var appBundleID: String?
    var appVersion: String?
    var buildNumber: String?
    var deviceModel: String?
    var osVersion: String?
}

struct NoopPushNotificationCoordinator: PushNotificationCoordinating {
    func register(token: String, context: PushNotificationRegistrationContext) async {}
    func unregister(context: PushNotificationRegistrationContext) async {}
    func clearLocalState() {}
}

@MainActor
final class SystemPushNotificationCoordinator: PushNotificationCoordinating {
    private static let lastRegisteredFingerprintKey = "righttrain.push.lastRegisteredFingerprint"

    func register(token: String, context: PushNotificationRegistrationContext) async {
        let fingerprint = Self.fingerprint(token: token, context: context)
        if UserDefaults.standard.string(forKey: Self.lastRegisteredFingerprintKey) == fingerprint {
            return
        }

        // A dropped registration means action-needed alerts silently never
        // arrive, so retry transient failures and leave a diagnostics trail
        // (previously this printed to the console and gave up).
        var delaySeconds = 0.5
        for attempt in 1...3 {
            do {
                try await context.apiClient.registerAPNsAlertToken(
                    clientDeviceID: context.clientDeviceID,
                    input: RegisterAPNsAlertTokenRequest(
                        token: token,
                        environment: context.environment,
                        clientDeviceId: context.clientDeviceID,
                        appBundleId: context.appBundleID,
                        appVersion: context.appVersion,
                        buildNumber: context.buildNumber,
                        deviceModel: context.deviceModel,
                        osVersion: context.osVersion
                    ),
                    accessToken: context.accessToken
                )
                UserDefaults.standard.set(fingerprint, forKey: Self.lastRegisteredFingerprintKey)
                return
            } catch {
                if attempt == 3 {
                    BetaDiagnostics.record("apns_alert_token_registration_failed", details: error.localizedDescription, severity: .error)
                    return
                }
                try? await Task.sleep(for: .seconds(delaySeconds * Double.random(in: 0.8...1.2)))
                delaySeconds *= 2
            }
        }
    }

    func unregister(context: PushNotificationRegistrationContext) async {
        do {
            try await context.apiClient.deleteAPNsAlertToken(
                clientDeviceID: context.clientDeviceID,
                environment: context.environment,
                accessToken: context.accessToken
            )
        } catch {
            BetaDiagnostics.record("apns_alert_token_deletion_failed", details: error.localizedDescription, severity: .warning)
        }
        clearLocalState()
    }

    func clearLocalState() {
        UserDefaults.standard.removeObject(forKey: Self.lastRegisteredFingerprintKey)
    }

    private static func fingerprint(token: String, context: PushNotificationRegistrationContext) -> String {
        "\(context.clientDeviceID)|\(context.environment)|\(token)"
    }
}
