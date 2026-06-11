import Foundation
import UIKit
import UserNotifications

final class PushNotificationsAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    static let didRegisterTokenNotification = Notification.Name("righttrain.push.didRegisterToken")
    static let didFailToRegisterNotification = Notification.Name("righttrain.push.didFailToRegister")
    static let didReceiveResponseNotification = Notification.Name("righttrain.push.didReceiveResponse")
    static let tokenUserInfoKey = "token"
    static let errorUserInfoKey = "error"
    static let actionIdentifierUserInfoKey = "actionIdentifier"
    static let urlUserInfoKey = "url"
    static let windowSubscriptionIDUserInfoKey = "windowSubscriptionId"
    static let notificationIDUserInfoKey = "notificationId"
    static let departedTrainServiceIDUserInfoKey = "departedTrainServiceId"
    static let nextRecommendationServiceIDUserInfoKey = "nextRecommendationServiceId"
    private static let alternateWindowSubscriptionIDKeys = ["windowSubscriptionID", "window_subscription_id"]
    private static let alternateNotificationIDKeys = ["notificationID", "notification_id"]
    private static let alternateURLKeys = ["deepLinkURL", "deep_link_url", "deeplink_url"]
    static let recommendedDepartedCategoryIdentifier = "WINDOW_RECOMMENDED_DEPARTED"
    static let pinDepartedTrainActionIdentifier = "PIN_DEPARTED_TRAIN"
    static let monitorNextBestActionIdentifier = "MONITOR_NEXT_BEST"

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.setNotificationCategories(Self.notificationCategories)
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        NotificationCenter.default.post(
            name: Self.didRegisterTokenNotification,
            object: nil,
            userInfo: [Self.tokenUserInfoKey: hex]
        )
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        NotificationCenter.default.post(
            name: Self.didFailToRegisterNotification,
            object: nil,
            userInfo: [Self.errorUserInfoKey: error]
        )
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        if LiveActivityIntentActionStore.alertsAreSnoozed {
            return []
        }
        return [.banner, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        var info = response.notification.request.content.userInfo
        info[Self.actionIdentifierUserInfoKey] = response.actionIdentifier
        canonicalizeStringValue(in: &info, canonicalKey: Self.windowSubscriptionIDUserInfoKey, alternateKeys: Self.alternateWindowSubscriptionIDKeys)
        canonicalizeStringValue(in: &info, canonicalKey: Self.notificationIDUserInfoKey, alternateKeys: Self.alternateNotificationIDKeys)
        canonicalizeStringValue(in: &info, canonicalKey: Self.urlUserInfoKey, alternateKeys: Self.alternateURLKeys)
        if let departed = intValue(info[Self.departedTrainServiceIDUserInfoKey]) {
            info[Self.departedTrainServiceIDUserInfoKey] = departed
        }
        if let next = intValue(info[Self.nextRecommendationServiceIDUserInfoKey]) {
            info[Self.nextRecommendationServiceIDUserInfoKey] = next
        }
        NotificationCenter.default.post(
            name: Self.didReceiveResponseNotification,
            object: nil,
            userInfo: info
        )
    }

    private static var notificationCategories: Set<UNNotificationCategory> {
        let pin = UNNotificationAction(
            identifier: pinDepartedTrainActionIdentifier,
            title: "Pin this journey",
            options: [.authenticationRequired]
        )
        let next = UNNotificationAction(
            identifier: monitorNextBestActionIdentifier,
            title: "Keep search pinned",
            options: [.authenticationRequired]
        )
        return [
            UNNotificationCategory(
                identifier: recommendedDepartedCategoryIdentifier,
                actions: [pin, next],
                intentIdentifiers: [],
                options: []
            )
        ]
    }

    private func canonicalizeStringValue(
        in info: inout [AnyHashable: Any],
        canonicalKey: String,
        alternateKeys: [String]
    ) {
        guard stringValue(info[canonicalKey]) == nil else {
            return
        }
        for key in alternateKeys {
            if let value = stringValue(info[key]) {
                info[canonicalKey] = value
                return
            }
        }
    }

    private func stringValue(_ raw: Any?) -> String? {
        guard let value = raw as? String else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func intValue(_ raw: Any?) -> Int? {
        switch raw {
        case let value as Int:
            return value
        case let value as Int64:
            return Int(value)
        case let value as Double:
            return Int(value)
        case let value as NSNumber:
            return value.intValue
        case let value as String:
            return Int(value)
        default:
            return nil
        }
    }
}
