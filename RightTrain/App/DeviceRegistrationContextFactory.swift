import ActivityKit
import Foundation
import UIKit

struct DeviceRegistrationContextFactory {
    var apiClient: any APIClienting

    func pushNotificationContext(accessToken: String?) -> PushNotificationRegistrationContext? {
        guard let accessToken else { return nil }
        let bundle = Bundle.main
        return PushNotificationRegistrationContext(
            apiClient: apiClient,
            accessToken: accessToken,
            environment: APNsEnvironment.current,
            clientDeviceID: Self.clientDeviceID,
            appBundleID: bundle.bundleIdentifier,
            appVersion: bundle.infoDictionary?["CFBundleShortVersionString"] as? String,
            buildNumber: bundle.infoDictionary?["CFBundleVersion"] as? String,
            deviceModel: UIDevice.current.model,
            osVersion: UIDevice.current.systemVersion
        )
    }

    func liveActivityContext(accessToken: String?) -> LiveActivityTokenRegistrationContext? {
        guard let accessToken else { return nil }
        let bundle = Bundle.main
        return LiveActivityTokenRegistrationContext(
            apiClient: apiClient,
            accessToken: accessToken,
            environment: APNsEnvironment.current,
            clientDeviceID: Self.clientDeviceID,
            appBundleID: bundle.bundleIdentifier,
            appVersion: bundle.infoDictionary?["CFBundleShortVersionString"] as? String,
            buildNumber: bundle.infoDictionary?["CFBundleVersion"] as? String,
            deviceModel: UIDevice.current.model,
            osVersion: UIDevice.current.systemVersion,
            frequentLiveActivityUpdatesEnabled: ActivityAuthorizationInfo().frequentPushesEnabled
        )
    }

    static var accountClientDeviceID: String {
        clientDeviceID
    }

    private static var clientDeviceID: String {
        let key = "righttrain.ios.clientDeviceID"
        if let existing = UserDefaults.standard.string(forKey: key), !existing.isEmpty {
            return existing
        }
        let value = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        UserDefaults.standard.set(value, forKey: key)
        return value
    }
}

enum APNsEnvironment {
    private static let infoPlistKey = "RightTrainAPNsEnvironment"

    static var current: String {
        current(bundle: .main, fallback: fallback)
    }

    static func current(bundle: Bundle, fallback: String) -> String {
        backendValue(forConfiguredValue: bundle.object(forInfoDictionaryKey: infoPlistKey) as? String, fallback: fallback)
    }

    static func backendValue(forConfiguredValue value: String?, fallback: String) -> String {
        switch value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "development", "sandbox":
            return "sandbox"
        case "production":
            return "production"
        default:
            return fallback
        }
    }

    private static var fallback: String {
        #if DEBUG
        "sandbox"
        #else
        "production"
        #endif
    }
}
