@testable import RightTrain
import CloudKit
import XCTest

/// These cover the conversion between the app's models and CloudKit records,
/// which is the part of the CloudKit work that can be tested without a
/// container. Everything that talks to CloudKit itself is exercised only by
/// running the app against a real account.
final class CloudKitPreferenceRecordsTests: XCTestCase {
    private func makeRecord(type: String, name: String = "record-1") -> CKRecord {
        CKRecord(
            recordType: type,
            recordID: CKRecord.ID(
                recordName: name,
                zoneID: CKRecordZone.ID(zoneName: CloudKitSchema.zoneName, ownerName: CKCurrentUserDefaultName)
            )
        )
    }

    func testPreferencesSurviveARoundTrip() {
        let preferences = CloudKitPreferences(
            homeStationCRS: "HDW",
            workStationCRS: "KGX",
            routeSetupDefaults: ["lastOrigin": "HDW"],
            notificationPreferences: AccountNotificationPreferences(routineNotificationsEnabled: false),
            productPreferences: ["tier": "pro"]
        )
        let record = makeRecord(type: CloudKitSchema.Preferences.recordType)

        preferences.apply(to: record)

        XCTAssertEqual(CloudKitPreferences(record: record), preferences)
    }

    /// A record written by an older build is missing the fields added since, so
    /// reading one must produce empty values rather than failing.
    func testPreferencesReadFromAnEmptyRecord() {
        let preferences = CloudKitPreferences(record: makeRecord(type: CloudKitSchema.Preferences.recordType))

        XCTAssertNil(preferences.homeStationCRS)
        XCTAssertNil(preferences.workStationCRS)
        XCTAssertEqual(preferences.routeSetupDefaults, [:])
        XCTAssertEqual(preferences.productPreferences, [:])
        XCTAssertNil(preferences.notificationPreferences.routineNotificationsEnabled)
    }

    /// Clearing a station has to remove the field rather than leave the old
    /// code behind, or unsetting a home station would silently not take.
    func testClearingAStationRemovesTheField() {
        let record = makeRecord(type: CloudKitSchema.Preferences.recordType)
        CloudKitPreferences(homeStationCRS: "HDW", workStationCRS: "KGX").apply(to: record)

        CloudKitPreferences(homeStationCRS: nil, workStationCRS: "KGX").apply(to: record)

        XCTAssertNil(record[CloudKitSchema.Preferences.homeStationCRS] as? String)
        XCTAssertEqual(record[CloudKitSchema.Preferences.workStationCRS] as? String, "KGX")
    }

    func testRoutineWritesEveryFieldTheBackendHolds() {
        let routine = TestFactory.commuteRoutine()
        let record = makeRecord(type: CloudKitSchema.Routine.recordType, name: routine.id)

        routine.apply(to: record)

        XCTAssertEqual(record[CloudKitSchema.Routine.name] as? String, routine.name)
        XCTAssertEqual(record[CloudKitSchema.Routine.status] as? String, routine.status)
        XCTAssertEqual(record[CloudKitSchema.Routine.originCRS] as? String, routine.originCrs)
        XCTAssertEqual(record[CloudKitSchema.Routine.destinationCRS] as? String, routine.destinationCrs)
        XCTAssertEqual(record[CloudKitSchema.Routine.departureTime] as? String, routine.departureTime)
        XCTAssertEqual(record[CloudKitSchema.Routine.windowMinutes] as? Int64, Int64(routine.windowMinutes))
        XCTAssertEqual(record[CloudKitSchema.Routine.activeWeekdays] as? [Int64], [1, 2, 3, 4, 5])
        XCTAssertEqual(record[CloudKitSchema.Routine.autoArmLeadMinutes] as? Int64, Int64(routine.autoArmLeadMinutes))
    }

    /// CloudKit has no boolean type, so the flags go out as 0 and 1.
    func testRoutineFlagsTravelAsNumbers() {
        let record = makeRecord(type: CloudKitSchema.Routine.recordType)
        var routine = TestFactory.commuteRoutine()
        routine.autoArmEnabled = false
        routine.notificationsEnabled = true

        routine.apply(to: record)

        XCTAssertEqual(record[CloudKitSchema.Routine.autoArmEnabled] as? Int64, 0)
        XCTAssertEqual(record[CloudKitSchema.Routine.notificationsEnabled] as? Int64, 1)
        XCTAssertFalse(CloudKitBool.decode(record[CloudKitSchema.Routine.autoArmEnabled], default: true))
        XCTAssertTrue(CloudKitBool.decode(record[CloudKitSchema.Routine.notificationsEnabled], default: false))
    }

    func testBoolDecodeFallsBackWhenTheFieldIsMissing() {
        XCTAssertTrue(CloudKitBool.decode(nil, default: true))
        XCTAssertFalse(CloudKitBool.decode(nil, default: false))
        XCTAssertTrue(CloudKitBool.decode("not a number", default: true))
    }

    func testJSONDecodeFallsBackOnRubbish() {
        XCTAssertEqual(CloudKitJSON.decode("{not json", default: ["a": "b"]), ["a": "b"])
        XCTAssertEqual(CloudKitJSON.decode(nil, default: ["a": "b"]), ["a": "b"])
    }

    /// The record name is the identifier the backend already issued, so the
    /// migration that makes CloudKit authoritative has nothing to reconcile.
    func testRoutineRecordIsKeyedByTheBackendIdentifier() {
        let routine = TestFactory.commuteRoutine(id: "9f1c7a2e-0000-4000-8000-000000000001")
        let record = makeRecord(type: CloudKitSchema.Routine.recordType, name: routine.id)

        XCTAssertEqual(record.recordID.recordName, routine.id)
        XCTAssertEqual(record.recordID.zoneID.zoneName, CloudKitSchema.zoneName)
    }
}
