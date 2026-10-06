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

/// CloudKit is the only store for commutes now. These pin the two things that
/// would be invisible until a real morning: that the backend is not consulted
/// once an account has migrated, and that an account which never migrated
/// still gets its routines copied across rather than silently losing them.
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
            cloudKitStore: cloudKitStore,
            preArmScheduler: CommutePreArmScheduler(apiClient: apiClient)
        )
    }

    private func seededSnapshot(routines: [CommuteRoutine]) -> CloudKitSnapshot {
        CloudKitSnapshot(
            preferences: CloudKitPreferences(homeStationCRS: "HDW", workStationCRS: "KGX"),
            routines: routines,
            seededAt: Date()
        )
    }

    func testAMigratedAccountNeverAsksTheBackendForRoutines() async {
        let apiClient = FakeAPIClient()
        apiClient.commuteRoutinesResult = .success([TestFactory.commuteRoutine(id: "server-only")])
        let cloudKit = FakeCloudKitPreferenceStore()
        cloudKit.snapshot = seededSnapshot(routines: [TestFactory.commuteRoutine(id: "cloudkit-one")])

        let viewModel = makeViewModel(apiClient: apiClient, cloudKitStore: cloudKit)
        await viewModel.refresh()

        XCTAssertEqual(viewModel.routines.map(\.id), ["cloudkit-one"])
        XCTAssertTrue(apiClient.listCommuteRoutineAccessTokens.isEmpty)
        XCTAssertTrue(cloudKit.seedCalls.isEmpty)
        XCTAssertEqual(viewModel.stationDefaults.homeStationCrs, "HDW")
        XCTAssertFalse(apiClient.preArmRequests.isEmpty)
    }

    func testAnUnmigratedAccountIsMigratedFromTheBackendOnce() async {
        let apiClient = FakeAPIClient()
        let routine = TestFactory.commuteRoutine()
        apiClient.commuteRoutinesResult = .success([routine])
        let cloudKit = FakeCloudKitPreferenceStore()

        let viewModel = makeViewModel(apiClient: apiClient, cloudKitStore: cloudKit)
        await viewModel.refresh()

        XCTAssertEqual(cloudKit.seedCalls.count, 1)
        XCTAssertEqual(cloudKit.seedCalls.first?.routines.map(\.id), [routine.id])
        XCTAssertEqual(viewModel.routines.map(\.id), [routine.id])
    }

    /// The backend drops the routine endpoints after this ships. A migration
    /// that cannot reach them has nothing to copy, which is correct by then —
    /// but it must not take the whole screen down with it.
    func testMigrationSurvivesTheBackendEndpointBeingGone() async {
        let apiClient = FakeAPIClient()
        apiClient.commuteRoutinesResult = .failure(
            APIError.server(statusCode: 404, code: nil, message: "not found", details: [:])
        )
        let cloudKit = FakeCloudKitPreferenceStore()
        cloudKit.snapshot = CloudKitSnapshot(
            preferences: nil,
            routines: [TestFactory.commuteRoutine(id: "already-here")],
            seededAt: nil
        )

        let viewModel = makeViewModel(apiClient: apiClient, cloudKitStore: cloudKit)
        await viewModel.refresh()

        XCTAssertEqual(cloudKit.seedCalls.count, 1)
        XCTAssertEqual(cloudKit.seedCalls.first?.routines, [])
        XCTAssertEqual(viewModel.routines.map(\.id), ["already-here"])
    }

    /// A seed that fails leaves the account unmigrated so the next launch
    /// tries again, rather than marking it done with nothing copied.
    func testAFailedSeedLeavesTheAccountUnmigrated() async {
        let apiClient = FakeAPIClient()
        apiClient.commuteRoutinesResult = .success([TestFactory.commuteRoutine()])
        let cloudKit = FakeCloudKitPreferenceStore()
        cloudKit.seedSucceeds = false

        let viewModel = makeViewModel(apiClient: apiClient, cloudKitStore: cloudKit)
        await viewModel.refresh()

        XCTAssertTrue(viewModel.routines.isEmpty)
        XCTAssertEqual(cloudKit.seedCalls.count, 1)
    }

    func testWithoutICloudThereAreNoRoutinesAndTheScreenSaysSo() async {
        let apiClient = FakeAPIClient()
        apiClient.commuteRoutinesResult = .success([TestFactory.commuteRoutine()])
        let cloudKit = FakeCloudKitPreferenceStore()
        cloudKit.snapshot = nil

        let viewModel = makeViewModel(apiClient: apiClient, cloudKitStore: cloudKit)
        await viewModel.refresh()

        XCTAssertTrue(viewModel.routines.isEmpty)
        XCTAssertTrue(viewModel.isWaitingOnICloud)
        XCTAssertTrue(apiClient.preArmRequests.isEmpty)
        XCTAssertTrue(cloudKit.seedCalls.isEmpty)
    }

    func testCreatingARoutineWritesOnlyToCloudKitAndMintsItsOwnID() async {
        let apiClient = FakeAPIClient()
        apiClient.commuteRoutinesResult = .success([])
        let cloudKit = FakeCloudKitPreferenceStore()
        cloudKit.snapshot = seededSnapshot(routines: [])

        let viewModel = makeViewModel(apiClient: apiClient, cloudKitStore: cloudKit)
        await viewModel.refresh()
        await viewModel.createRoutine(CommuteRoutineMutationRequest(routine: TestFactory.commuteRoutine()))

        XCTAssertTrue(apiClient.createCommuteRoutineRequests.isEmpty)
        XCTAssertEqual(cloudKit.savedRoutines.count, 1)
        let saved = cloudKit.savedRoutines[0]
        XCTAssertNotNil(UUID(uuidString: saved.id))
        XCTAssertEqual(viewModel.routines.map(\.id), [saved.id])
    }

    func testDeletingARoutineWritesOnlyToCloudKit() async {
        let apiClient = FakeAPIClient()
        let routine = TestFactory.commuteRoutine(id: "routine-to-go")
        let cloudKit = FakeCloudKitPreferenceStore()
        cloudKit.snapshot = seededSnapshot(routines: [routine])

        let viewModel = makeViewModel(apiClient: apiClient, cloudKitStore: cloudKit)
        await viewModel.refresh()
        await viewModel.deleteRoutine(id: routine.id)

        XCTAssertEqual(cloudKit.deletedRoutineIDs, [routine.id])
        XCTAssertTrue(apiClient.deleteCommuteRoutineRequests.isEmpty)
        XCTAssertTrue(viewModel.routines.isEmpty)
    }

    func testStationDefaultsGoToCloudKitRatherThanTheAccount() async {
        let apiClient = FakeAPIClient()
        let cloudKit = FakeCloudKitPreferenceStore()
        cloudKit.snapshot = seededSnapshot(routines: [])

        let viewModel = makeViewModel(apiClient: apiClient, cloudKitStore: cloudKit)
        await viewModel.refresh()
        await viewModel.updateStationDefaults(homeStationCRS: "fin", workStationCRS: nil)

        XCTAssertTrue(apiClient.updateStationDefaultsRequests.isEmpty)
        XCTAssertEqual(cloudKit.savedStationDefaults.last?.home, "FIN")
        XCTAssertNil(cloudKit.savedStationDefaults.last?.work)
        XCTAssertEqual(viewModel.stationDefaults.homeStationCrs, "FIN")
    }

    /// The Settings row reports the iCloud account status, which is a different
    /// question from whether the zone read succeeded: being signed out needs an
    /// instruction, a failed read needs patience.
    func testCloudKitAvailabilityIsReportedForSettings() async {
        let apiClient = FakeAPIClient()
        let cloudKit = FakeCloudKitPreferenceStore()
        cloudKit.availability = .noAccount
        cloudKit.snapshot = nil

        let viewModel = makeViewModel(apiClient: apiClient, cloudKitStore: cloudKit)
        await viewModel.refreshCloudKitAvailability()

        XCTAssertEqual(viewModel.cloudKitAvailability, .noAccount)

        cloudKit.availability = .available
        cloudKit.snapshot = seededSnapshot(routines: [])
        await viewModel.refresh()

        XCTAssertEqual(viewModel.cloudKitAvailability, .available)
        XCTAssertFalse(viewModel.isWaitingOnICloud)
    }
}
