import CloudKit
import Foundation
import os

/// Whether the private CloudKit database is usable on this device right now.
enum CloudKitAvailability: Equatable {
    case unknown
    case available
    /// No iCloud account is signed in, or iCloud is switched off for the app.
    case noAccount
    /// Parental controls or a device management profile forbid iCloud.
    case restricted
    /// A transient failure. Worth trying again later.
    case unavailable(String)
}

@MainActor
protocol CloudKitPreferenceStoring: AnyObject {
    var availability: CloudKitAvailability { get }
    func refreshAvailability() async
    func saveStationDefaults(homeStationCRS: String?, workStationCRS: String?) async
    func saveRoutine(_ routine: CommuteRoutine) async
    func deleteRoutine(id: String) async

    /// Everything the zone holds, or nil when CloudKit could not be read at
    /// all. Nil and empty mean different things to the caller: nil is "ask the
    /// server instead", empty is "CloudKit is authoritative and has nothing".
    func loadSnapshot(userID: String) async -> CloudKitSnapshot?

    /// Copies the server's state into the zone and marks the account
    /// migrated. Routines already in the zone are left alone.
    /// Returns false when the copy did not complete, in which case the caller
    /// must not treat CloudKit as authoritative yet.
    func seed(preferences: CloudKitPreferences, routines: [CommuteRoutine], skippingRoutineIDs: Set<String>) async -> Bool
}

/// What the private database holds for this account.
struct CloudKitSnapshot: Equatable {
    var preferences: CloudKitPreferences?
    var routines: [CommuteRoutine]

    /// When the server's copy was first written into this zone, or nil when it
    /// never has been.
    ///
    /// Emptiness is not the same question, and is the wrong one to ask: stage
    /// one already wrote a preferences record on every device it ran on, so a
    /// zone can hold preferences and still be waiting for the routines. This
    /// marker is what decides.
    var seededAt: Date?
}

/// Mirrors standing preferences into the user's own private CloudKit database.
///
/// CloudKit is now the source of truth for this data. The app still writes the
/// same values to the backend, but it reads them from here, and falls back to
/// the backend only when iCloud cannot be reached at all.
///
/// A write failure must still never surface as an error on a save the user has
/// already watched succeed, so writes stay silent and log instead.
///
/// Records are keyed by the identifiers the backend already issues, so seeding
/// an empty zone from the server has nothing to reconcile.
@MainActor
final class CloudKitPreferenceStore: CloudKitPreferenceStoring {
    private(set) var availability: CloudKitAvailability = .unknown

    private let container: CKContainer
    private let database: CKDatabase
    private let zoneID: CKRecordZone.ID
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.righttrain.ios", category: "cloudkit")
    private var zoneEnsured = false

    init(containerIdentifier: String) {
        let container = CKContainer(identifier: containerIdentifier)
        self.container = container
        self.database = container.privateCloudDatabase
        self.zoneID = CKRecordZone.ID(zoneName: CloudKitSchema.zoneName, ownerName: CKCurrentUserDefaultName)
    }

    func refreshAvailability() async {
        do {
            switch try await container.accountStatus() {
            case .available:
                availability = .available
            case .noAccount:
                availability = .noAccount
            case .restricted:
                availability = .restricted
            case .couldNotDetermine:
                availability = .unavailable("could not determine")
            case .temporarilyUnavailable:
                availability = .unavailable("temporarily unavailable")
            @unknown default:
                availability = .unavailable("unrecognised account status")
            }
        } catch {
            availability = .unavailable(error.localizedDescription)
        }
        logger.notice("CloudKit account status: \(String(describing: self.availability), privacy: .public)")
    }

    func saveStationDefaults(homeStationCRS: String?, workStationCRS: String?) async {
        await write("station defaults") {
            let recordID = CKRecord.ID(recordName: CloudKitSchema.Preferences.recordName, zoneID: self.zoneID)
            let record = try await self.existingRecord(
                id: recordID,
                recordType: CloudKitSchema.Preferences.recordType
            )
            var preferences = CloudKitPreferences(record: record)
            preferences.homeStationCRS = homeStationCRS
            preferences.workStationCRS = workStationCRS
            preferences.apply(to: record)
            try await self.save(record)
        }
    }

    func saveRoutine(_ routine: CommuteRoutine) async {
        await write("commute routine") {
            let recordID = CKRecord.ID(recordName: routine.id, zoneID: self.zoneID)
            let record = try await self.existingRecord(
                id: recordID,
                recordType: CloudKitSchema.Routine.recordType
            )
            routine.apply(to: record)
            try await self.save(record)
        }
    }

    func deleteRoutine(id: String) async {
        await write("commute routine deletion") {
            let recordID = CKRecord.ID(recordName: id, zoneID: self.zoneID)
            do {
                _ = try await self.database.deleteRecord(withID: recordID)
            } catch {
                // Already gone is the state we wanted.
                guard let ckError = error as? CKError, ckError.code == .unknownItem else { throw error }
            }
        }
    }

    func loadSnapshot(userID: String) async -> CloudKitSnapshot? {
        if availability == .unknown {
            await refreshAvailability()
        }
        guard availability == .available else {
            logger.notice("skipped CloudKit read: \(String(describing: self.availability), privacy: .public)")
            return nil
        }
        do {
            let records = try await allRecordsInZone()
            let preferencesRecord = records.first {
                $0.recordType == CloudKitSchema.Preferences.recordType
            }
            let routines = records
                .filter { $0.recordType == CloudKitSchema.Routine.recordType }
                .compactMap { CommuteRoutine(record: $0, userID: userID) }
                .sorted { $0.createdAt > $1.createdAt }
            let snapshot = CloudKitSnapshot(
                preferences: preferencesRecord.map { CloudKitPreferences(record: $0) },
                routines: routines,
                seededAt: preferencesRecord?[CloudKitSchema.Preferences.seededAt] as? Date
            )
            logger.notice("read CloudKit zone: \(snapshot.routines.count, privacy: .public) routines, preferences \(snapshot.preferences == nil ? "absent" : "present", privacy: .public)")
            return snapshot
        } catch {
            // A zone that does not exist yet is an empty zone, not a failure:
            // it is exactly the state a fresh account is in before seeding.
            if let ckError = error as? CKError, ckError.code == .zoneNotFound {
                return CloudKitSnapshot(preferences: nil, routines: [], seededAt: nil)
            }
            logger.error("CloudKit read failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    @discardableResult
    func seed(preferences: CloudKitPreferences, routines: [CommuteRoutine], skippingRoutineIDs: Set<String>) async -> Bool {
        await write("seed") {
            // Routines first: the marker is written last, so a seed that dies
            // halfway is retried on the next launch rather than left as a
            // half-migrated account that looks finished.
            for routine in routines where !skippingRoutineIDs.contains(routine.id) {
                let routineRecord = try await self.existingRecord(
                    id: CKRecord.ID(recordName: routine.id, zoneID: self.zoneID),
                    recordType: CloudKitSchema.Routine.recordType
                )
                routine.apply(to: routineRecord)
                try await self.save(routineRecord)
            }

            let recordID = CKRecord.ID(recordName: CloudKitSchema.Preferences.recordName, zoneID: self.zoneID)
            let record = try await self.existingRecord(
                id: recordID,
                recordType: CloudKitSchema.Preferences.recordType
            )
            preferences.apply(to: record)
            record[CloudKitSchema.Preferences.seededAt] = Date()
            try await self.save(record)
        }
    }

    // MARK: - Internals

    /// Every record in the zone, read through the change feed rather than a
    /// query. A query would depend on the record type carrying a queryable
    /// index, which the auto-created schema does not promise; the change feed
    /// needs no index and is what a full sync would use anyway.
    private func allRecordsInZone() async throws -> [CKRecord] {
        var records: [CKRecord] = []
        var token: CKServerChangeToken?
        while true {
            let changes = try await database.recordZoneChanges(inZoneWith: zoneID, since: token)
            records.append(contentsOf: changes.modificationResultsByID.values.compactMap { try? $0.get().record })
            guard changes.moreComing else { return records }
            token = changes.changeToken
        }
    }

    /// Runs a CloudKit write, swallowing every failure into the log.
    ///
    /// A shadow write must not be able to fail a save the user has already been
    /// told succeeded, and it must not run at all when iCloud is unavailable,
    /// which for an account-less device is the normal case rather than an error.
    @discardableResult
    private func write(_ description: String, _ body: @escaping () async throws -> Void) async -> Bool {
        if availability == .unknown {
            await refreshAvailability()
        }
        guard availability == .available else {
            // Deliberately not debug level: when nothing shows up in the
            // CloudKit Console, this line is the whole explanation.
            logger.notice("skipped CloudKit \(description, privacy: .public): \(String(describing: self.availability), privacy: .public)")
            return false
        }
        do {
            try await ensureZone()
            try await body()
            logger.notice("wrote CloudKit \(description, privacy: .public) to \(self.container.containerIdentifier ?? "unknown container", privacy: .public)")
            return true
        } catch {
            logger.error("CloudKit \(description, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func ensureZone() async throws {
        guard !zoneEnsured else { return }
        _ = try await database.save(CKRecordZone(zoneID: zoneID))
        zoneEnsured = true
    }

    /// Returns the record CloudKit already holds, or a new one when it holds
    /// none. Saving a freshly built record over an existing one is rejected,
    /// because it carries no change tag, so an update has to start from the
    /// stored record.
    private func existingRecord(id: CKRecord.ID, recordType: String) async throws -> CKRecord {
        do {
            return try await database.record(for: id)
        } catch {
            guard let ckError = error as? CKError, ckError.code == .unknownItem else { throw error }
            return CKRecord(recordType: recordType, recordID: id)
        }
    }

    /// Saves a record, and on a conflicting concurrent change replays the
    /// intended fields onto the server's copy once rather than giving up.
    private func save(_ record: CKRecord) async throws {
        do {
            _ = try await database.save(record)
        } catch {
            guard let ckError = error as? CKError,
                  ckError.code == .serverRecordChanged,
                  let serverRecord = ckError.serverRecord else { throw error }
            for key in record.allKeys() {
                serverRecord[key] = record[key]
            }
            _ = try await database.save(serverRecord)
        }
    }
}
