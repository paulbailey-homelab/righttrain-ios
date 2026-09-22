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
}

/// Mirrors standing preferences into the user's own private CloudKit database.
///
/// At this stage the backend is still the source of truth and these writes are
/// a shadow copy: nothing reads them back yet, and a failure here must never
/// surface as an error on a save the user already watched succeed. The point of
/// writing them now is to prove the container, the entitlement and the
/// production schema are right before anything depends on them.
///
/// Records are keyed by the identifiers the backend already issues, so the
/// migration that makes CloudKit authoritative has nothing to reconcile.
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

    // MARK: - Internals

    /// Runs a CloudKit write, swallowing every failure into the log.
    ///
    /// A shadow write must not be able to fail a save the user has already been
    /// told succeeded, and it must not run at all when iCloud is unavailable,
    /// which for an account-less device is the normal case rather than an error.
    private func write(_ description: String, _ body: @escaping () async throws -> Void) async {
        if availability == .unknown {
            await refreshAvailability()
        }
        guard availability == .available else {
            // Deliberately not debug level: when nothing shows up in the
            // CloudKit Console, this line is the whole explanation.
            logger.notice("skipped CloudKit \(description, privacy: .public): \(String(describing: self.availability), privacy: .public)")
            return
        }
        do {
            try await ensureZone()
            try await body()
            logger.notice("wrote CloudKit \(description, privacy: .public) to \(self.container.containerIdentifier ?? "unknown container", privacy: .public)")
        } catch {
            logger.error("CloudKit \(description, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
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
