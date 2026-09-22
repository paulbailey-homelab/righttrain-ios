import CloudKit
import Foundation

/// Names and field keys for the records RightTrain keeps in the user's private
/// CloudKit database.
///
/// These strings are the schema. CloudKit creates record types from the first
/// record saved in the development environment, and that schema then has to be
/// deployed to production by hand before any TestFlight build can use it, so
/// renaming anything here is a schema change and not a refactor.
enum CloudKitSchema {
    static let zoneName = "RightTrainPreferences"

    enum Preferences {
        static let recordType = "Preferences"
        /// There is exactly one preferences record per account.
        static let recordName = "preferences"

        static let homeStationCRS = "homeStationCrs"
        static let workStationCRS = "workStationCrs"
        static let routeSetupDefaults = "routeSetupDefaults"
        static let notificationPreferences = "notificationPreferences"
        static let productPreferences = "productPreferences"
        static let updatedAt = "updatedAt"
    }

    enum Routine {
        static let recordType = "CommuteRoutine"

        static let name = "name"
        static let status = "status"
        static let originCRS = "originCrs"
        static let destinationCRS = "destinationCrs"
        static let departureTime = "departureTime"
        static let windowMinutes = "windowMinutes"
        static let activeWeekdays = "activeWeekdays"
        static let autoArmEnabled = "autoArmEnabled"
        static let autoArmLeadMinutes = "autoArmLeadMinutes"
        static let notificationsEnabled = "notificationsEnabled"
        static let updatedAt = "updatedAt"
    }
}

/// The standing preferences that belong to the person rather than to a journey
/// in progress: which stations are home and work, and how they like the app to
/// behave.
struct CloudKitPreferences: Equatable {
    var homeStationCRS: String?
    var workStationCRS: String?
    var routeSetupDefaults: [String: String]
    var notificationPreferences: AccountNotificationPreferences
    var productPreferences: [String: String]

    init(
        homeStationCRS: String? = nil,
        workStationCRS: String? = nil,
        routeSetupDefaults: [String: String] = [:],
        notificationPreferences: AccountNotificationPreferences = AccountNotificationPreferences(routineNotificationsEnabled: nil),
        productPreferences: [String: String] = [:]
    ) {
        self.homeStationCRS = homeStationCRS
        self.workStationCRS = workStationCRS
        self.routeSetupDefaults = routeSetupDefaults
        self.notificationPreferences = notificationPreferences
        self.productPreferences = productPreferences
    }
}

// MARK: - Record conversion

extension CloudKitPreferences {
    /// Writes the preferences onto a record, leaving any field CloudKit already
    /// holds and this app does not know about untouched.
    func apply(to record: CKRecord, now: Date = Date()) {
        record[CloudKitSchema.Preferences.homeStationCRS] = homeStationCRS
        record[CloudKitSchema.Preferences.workStationCRS] = workStationCRS
        record[CloudKitSchema.Preferences.routeSetupDefaults] = CloudKitJSON.encode(routeSetupDefaults)
        record[CloudKitSchema.Preferences.notificationPreferences] = CloudKitJSON.encode(notificationPreferences)
        record[CloudKitSchema.Preferences.productPreferences] = CloudKitJSON.encode(productPreferences)
        record[CloudKitSchema.Preferences.updatedAt] = now
    }

    /// Reads preferences back out of a record. A field CloudKit has never been
    /// given reads as its empty value rather than failing, because a record
    /// written by an older build will be missing the fields added since.
    init(record: CKRecord) {
        self.init(
            homeStationCRS: record[CloudKitSchema.Preferences.homeStationCRS] as? String,
            workStationCRS: record[CloudKitSchema.Preferences.workStationCRS] as? String,
            routeSetupDefaults: CloudKitJSON.decode(
                record[CloudKitSchema.Preferences.routeSetupDefaults] as? String,
                default: [String: String]()
            ),
            notificationPreferences: CloudKitJSON.decode(
                record[CloudKitSchema.Preferences.notificationPreferences] as? String,
                default: AccountNotificationPreferences(routineNotificationsEnabled: nil)
            ),
            productPreferences: CloudKitJSON.decode(
                record[CloudKitSchema.Preferences.productPreferences] as? String,
                default: [String: String]()
            )
        )
    }
}

extension CommuteRoutine {
    /// Writes the routine onto a record.
    ///
    /// CloudKit has no boolean type, so the flags are stored as 0 or 1.
    func apply(to record: CKRecord, now: Date = Date()) {
        record[CloudKitSchema.Routine.name] = name
        record[CloudKitSchema.Routine.status] = status
        record[CloudKitSchema.Routine.originCRS] = originCrs
        record[CloudKitSchema.Routine.destinationCRS] = destinationCrs
        record[CloudKitSchema.Routine.departureTime] = departureTime
        record[CloudKitSchema.Routine.windowMinutes] = Int64(windowMinutes)
        record[CloudKitSchema.Routine.activeWeekdays] = activeWeekdays.map { Int64($0) }
        record[CloudKitSchema.Routine.autoArmEnabled] = CloudKitBool.encode(autoArmEnabled)
        record[CloudKitSchema.Routine.autoArmLeadMinutes] = Int64(autoArmLeadMinutes)
        record[CloudKitSchema.Routine.notificationsEnabled] = CloudKitBool.encode(notificationsEnabled)
        record[CloudKitSchema.Routine.updatedAt] = now
    }
}

/// CloudKit stores no booleans, so flags travel as 0 or 1.
enum CloudKitBool {
    static func encode(_ value: Bool) -> Int64 {
        value ? 1 : 0
    }

    static func decode(_ value: Any?, default fallback: Bool) -> Bool {
        guard let number = value as? Int64 else { return fallback }
        return number != 0
    }
}

/// CloudKit stores no dictionaries either, so the preference blobs travel as
/// JSON strings, which is also how the backend holds them.
enum CloudKitJSON {
    static func encode<Value: Encodable>(_ value: Value) -> String {
        guard let data = try? JSONEncoder().encode(value) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    static func decode<Value: Decodable>(_ value: String?, default fallback: Value) -> Value {
        guard let value, let data = value.data(using: .utf8) else { return fallback }
        return (try? JSONDecoder().decode(Value.self, from: data)) ?? fallback
    }
}
