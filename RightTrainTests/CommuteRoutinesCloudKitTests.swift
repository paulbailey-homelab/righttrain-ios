@testable import RightTrain
import XCTest

@MainActor
final class FakeCloudKitPreferenceStore: CloudKitPreferenceStoring {
    var availability: CloudKitAvailability = .available

    /// nil means the private database could not be read at all, which is a
    /// different answer from an empty zone.
    var snapshot: CloudKitSnapshot? = CloudKitSnapshot(preferences: nil, routines: [], seededAt: nil)
    var seedSucceeds = true

    private(set) var seedCalls: [(preferences: CloudKitPreferences, routines: [CommuteRoutine], skipped: Set<String>)] = []
    private(set) var savedRoutines: [CommuteRoutine] = []
    private(set) var deletedRoutineIDs: [String] = []
    private(set) var savedStationDefaults: [(home: String?, work: String?)] = []

    func refreshAvailability() async {}

    func saveStationDefaults(homeStationCRS: String?, workStationCRS: String?) async {
        savedStationDefaults.append((homeStationCRS, workStationCRS))
    }

    func saveRoutine(_ routine: CommuteRoutine) async {
        savedRoutines.append(routine)
    }

    func deleteRoutine(id: String) async {
        deletedRoutineIDs.append(id)
    }

    func loadSnapshot(userID: String) async -> CloudKitSnapshot? {
        snapshot
    }

    func seed(preferences: CloudKitPreferences, routines: [CommuteRoutine], skippingRoutineIDs: Set<String>) async -> Bool {
        seedCalls.append((preferences, routines, skippingRoutineIDs))
        return seedSucceeds
    }
}

/// These cover the handover: which copy of the routines the app reads, when the
/// server's copy is migrated into CloudKit, and when the server stops arming.
/// Getting this wrong either loses a user's commutes or arms them twice, and
/// neither shows up until a real morning.
@MainActor
final class CommuteRoutinesCloudKitTests: XCTestCase {
    private func makeViewModel(
        apiClient: FakeAPIClient,
        cloudKitStore: FakeCloudKitPreferenceStore,
        user: User = TestFactory.user()
    ) -> CommuteRoutinesViewModel {
        CommuteRoutinesViewModel(
            apiClient: apiClient,
            operationState: AppOperationState(),
            accessTokenProvider: { "token" },
            userProvider: { user },
            userUpdateHandler: { _ in },
            cloudKitStore: cloudKitStore,
            preArmScheduler: CommutePreArmScheduler(apiClient: apiClient)
        )
    }

    func testAnUnseededZoneIsFilledFromTheServerAndArmingIsHandedOver() async {
        let apiClient = FakeAPIClient()
        let routine = TestFactory.commuteRoutine()
        apiClient.commuteRoutinesResult = .success([routine])
        apiClient.commuteRoutineResult = .success(routine)
        let cloudKit = FakeCloudKitPreferenceStore()

        let viewModel = makeViewModel(apiClient: apiClient, cloudKitStore: cloudKit)
        await viewModel.refresh()

        XCTAssertEqual(cloudKit.seedCalls.count, 1)
        XCTAssertEqual(cloudKit.seedCalls.first?.routines.map(\.id), [routine.id])
        XCTAssertEqual(viewModel.routines.map(\.id), [routine.id])
        XCTAssertTrue(viewModel.isCloudKitAuthoritative)

        // The server must stop arming the routine the app now arms, or both
        // create a window subscription for the same train.
        XCTAssertEqual(apiClient.updateCommuteRoutineRequests.count, 1)
        XCTAssertEqual(apiClient.updateCommuteRoutineRequests.first?.input.autoArmEnabled, false)
        XCTAssertFalse(apiClient.preArmRequests.isEmpty)
    }

    /// Stage one wrote a preferences record on every device it ran on, so an
    /// account can reach stage two with preferences in CloudKit and no
    /// routines. That is not a migrated account, and reading it as one would
    /// make the user's commutes disappear.
    func testAZoneHoldingOnlyStageOnePreferencesIsStillSeeded() async {
        let apiClient = FakeAPIClient()
        let routine = TestFactory.commuteRoutine()
        apiClient.commuteRoutinesResult = .success([routine])
        apiClient.commuteRoutineResult = .success(routine)
        let cloudKit = FakeCloudKitPreferenceStore()
        cloudKit.snapshot = CloudKitSnapshot(
            preferences: CloudKitPreferences(homeStationCRS: "HDW", workStationCRS: "KGX"),
            routines: [],
            seededAt: nil
        )

        let viewModel = makeViewModel(apiClient: apiClient, cloudKitStore: cloudKit)
        await viewModel.refresh()

        XCTAssertEqual(cloudKit.seedCalls.count, 1)
        XCTAssertEqual(viewModel.routines.map(\.id), [routine.id])
        // The station defaults already in CloudKit are the newer copy and are
        // kept rather than overwritten from the account.
        XCTAssertEqual(cloudKit.seedCalls.first?.preferences.homeStationCRS, "HDW")
        XCTAssertEqual(viewModel.stationDefaults.homeStationCrs, "HDW")
    }

    func testASeededZoneIsReadInsteadOfTheServer() async {
        let apiClient = FakeAPIClient()
        apiClient.commuteRoutinesResult = .success([TestFactory.commuteRoutine(id: "server-only")])
        let cloudKit = FakeCloudKitPreferenceStore()
        cloudKit.snapshot = CloudKitSnapshot(
            preferences: CloudKitPreferences(homeStationCRS: "HDW", workStationCRS: nil),
            routines: [TestFactory.commuteRoutine(id: "cloudkit-one")],
            seededAt: Date()
        )

        let viewModel = makeViewModel(apiClient: apiClient, cloudKitStore: cloudKit)
        await viewModel.refresh()

        XCTAssertTrue(cloudKit.seedCalls.isEmpty)
        XCTAssertEqual(viewModel.routines.map(\.id), ["cloudkit-one"])
    }

    /// With iCloud unreachable the app has to behave exactly as it did before
    /// stage two: read the server's routines and leave the server arming them.
    /// Pre-arming as well would double up.
    func testAnUnreadableDatabaseLeavesEverythingOnTheServer() async {
        let apiClient = FakeAPIClient()
        let routine = TestFactory.commuteRoutine()
        apiClient.commuteRoutinesResult = .success([routine])
        let cloudKit = FakeCloudKitPreferenceStore()
        cloudKit.snapshot = nil

        let viewModel = makeViewModel(apiClient: apiClient, cloudKitStore: cloudKit)
        await viewModel.refresh()

        XCTAssertFalse(viewModel.isCloudKitAuthoritative)
        XCTAssertEqual(viewModel.routines.map(\.id), [routine.id])
        XCTAssertTrue(cloudKit.seedCalls.isEmpty)
        XCTAssertTrue(apiClient.updateCommuteRoutineRequests.isEmpty)
        XCTAssertTrue(apiClient.preArmRequests.isEmpty)
    }

    /// A seed that fails must not hand arming over, or the account ends up
    /// with a server that has stopped arming and a CloudKit zone that does not
    /// hold the routines.
    func testAFailedSeedDoesNotHandOverArming() async {
        let apiClient = FakeAPIClient()
        apiClient.commuteRoutinesResult = .success([TestFactory.commuteRoutine()])
        let cloudKit = FakeCloudKitPreferenceStore()
        cloudKit.seedSucceeds = false

        let viewModel = makeViewModel(apiClient: apiClient, cloudKitStore: cloudKit)
        await viewModel.refresh()

        XCTAssertFalse(viewModel.isCloudKitAuthoritative)
        XCTAssertTrue(apiClient.updateCommuteRoutineRequests.isEmpty)
        XCTAssertTrue(apiClient.preArmRequests.isEmpty)
    }

    /// The user's auto-arm setting lives in CloudKit from here on. The server
    /// copy is written with it off, because the server must not arm; the app's
    /// own copy has to keep what the user actually asked for.
    func testCreatingARoutineKeepsAutoArmLocallyAndClearsItOnTheServer() async {
        let apiClient = FakeAPIClient()
        apiClient.commuteRoutinesResult = .success([])
        let created = TestFactory.commuteRoutine(id: "new-routine")
        apiClient.commuteRoutineResult = .success(created)
        let cloudKit = FakeCloudKitPreferenceStore()

        let viewModel = makeViewModel(apiClient: apiClient, cloudKitStore: cloudKit)
        await viewModel.refresh()
        await viewModel.createRoutine(CommuteRoutineMutationRequest(routine: created))

        XCTAssertEqual(apiClient.createCommuteRoutineRequests.first?.input.autoArmEnabled, false)
        XCTAssertEqual(cloudKit.savedRoutines.first?.autoArmEnabled, true)
        XCTAssertEqual(viewModel.routines.first?.autoArmEnabled, true)
    }
}
