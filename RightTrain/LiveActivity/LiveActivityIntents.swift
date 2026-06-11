import AppIntents
import Foundation

enum LiveActivityIntentActionStore {
    static let suiteName = "group.com.righttrain.ios"

    private static let pendingActionsKey = "righttrain.liveActivity.pendingActions"
    private static let alertsSnoozedUntilKey = "righttrain.liveActivity.alertsSnoozedUntil"

    struct PendingAction: Codable, Identifiable, Hashable {
        enum Kind: String, Codable {
            case pinTrain
            case snoozeAlerts
        }

        var id: String
        var kind: Kind
        var createdAt: Date
        var windowSubscriptionID: String?
        var itinerarySubscriptionID: String?
        var serviceID: Int?
        var minutes: Int?
        var snoozedUntil: Date?
    }

    static var alertsSnoozedUntil: Date? {
        get {
            defaults.object(forKey: alertsSnoozedUntilKey) as? Date
        }
        set {
            if let newValue {
                defaults.set(newValue, forKey: alertsSnoozedUntilKey)
            } else {
                defaults.removeObject(forKey: alertsSnoozedUntilKey)
            }
        }
    }

    static var alertsAreSnoozed: Bool {
        guard let alertsSnoozedUntil else {
            return false
        }
        return alertsSnoozedUntil > Date()
    }

    static func enqueue(_ action: PendingAction) {
        var actions = pendingActions()
        actions.append(action)
        save(actions)
    }

    static func drainPendingActions() -> [PendingAction] {
        let actions = pendingActions().sorted { $0.createdAt < $1.createdAt }
        defaults.removeObject(forKey: pendingActionsKey)
        return actions
    }

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }

    private static func pendingActions() -> [PendingAction] {
        guard let data = defaults.data(forKey: pendingActionsKey) else {
            return []
        }
        return (try? JSONDecoder().decode([PendingAction].self, from: data)) ?? []
    }

    private static func save(_ actions: [PendingAction]) {
        guard let data = try? JSONEncoder().encode(actions) else {
            return
        }
        defaults.set(data, forKey: pendingActionsKey)
    }
}

struct PinTrainIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Pin train"
    static var description = IntentDescription("Pins this train as the one you caught.")
    static var openAppWhenRun = false

    @Parameter(title: "Window Subscription ID")
    var windowSubscriptionID: String

    @Parameter(title: "Service ID")
    var serviceID: Int

    init() {
        windowSubscriptionID = ""
        serviceID = 0
    }

    init(windowSubscriptionID: String, serviceID: Int) {
        self.windowSubscriptionID = windowSubscriptionID
        self.serviceID = serviceID
    }

    func perform() async throws -> some IntentResult {
        guard !windowSubscriptionID.isEmpty, serviceID > 0 else {
            return .result()
        }
        LiveActivityIntentActionStore.enqueue(
            LiveActivityIntentActionStore.PendingAction(
                id: UUID().uuidString,
                kind: .pinTrain,
                createdAt: Date(),
                windowSubscriptionID: windowSubscriptionID,
                itinerarySubscriptionID: nil,
                serviceID: serviceID,
                minutes: nil,
                snoozedUntil: nil
            )
        )
        return .result()
    }
}

struct SnoozeAlertsIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Snooze alerts"
    static var description = IntentDescription("Temporarily silences RightTrain alerts on this device.")
    static var openAppWhenRun = false

    @Parameter(title: "Minutes")
    var minutes: Int

    @Parameter(title: "Window Subscription ID")
    var windowSubscriptionID: String

    @Parameter(title: "Itinerary Subscription ID")
    var itinerarySubscriptionID: String

    init() {
        minutes = 10
        windowSubscriptionID = ""
        itinerarySubscriptionID = ""
    }

    init(minutes: Int, windowSubscriptionID: String? = nil, itinerarySubscriptionID: String? = nil) {
        self.minutes = minutes
        self.windowSubscriptionID = windowSubscriptionID ?? ""
        self.itinerarySubscriptionID = itinerarySubscriptionID ?? ""
    }

    func perform() async throws -> some IntentResult {
        let clampedMinutes = min(max(minutes, 1), 120)
        let snoozedUntil = Date().addingTimeInterval(TimeInterval(clampedMinutes) * 60)
        LiveActivityIntentActionStore.alertsSnoozedUntil = snoozedUntil
        LiveActivityIntentActionStore.enqueue(
            LiveActivityIntentActionStore.PendingAction(
                id: UUID().uuidString,
                kind: .snoozeAlerts,
                createdAt: Date(),
                windowSubscriptionID: windowSubscriptionID.isEmpty ? nil : windowSubscriptionID,
                itinerarySubscriptionID: itinerarySubscriptionID.isEmpty ? nil : itinerarySubscriptionID,
                serviceID: nil,
                minutes: clampedMinutes,
                snoozedUntil: snoozedUntil
            )
        )
        return .result()
    }
}
