import Foundation

@MainActor
@Observable
final class CommuteRoutinesViewModel {
    private(set) var routines: [CommuteRoutine] = []
    private(set) var stationsByCRS: [String: StationSuggestion] = [:]

    /// The preferences CloudKit holds, once they have been read successfully.
    private(set) var cloudKitPreferences: CloudKitPreferences?

    /// Whether the private database could be read. There is no longer anywhere
    /// else for commutes to live, so when this is false the app has no
    /// routines to show rather than a server copy to fall back on.
    private(set) var isCloudKitAvailable = false

    @ObservationIgnored private let apiClient: any APIClienting
    @ObservationIgnored private let operationState: AppOperationState
    @ObservationIgnored private let accessTokenProvider: () -> String?
    @ObservationIgnored private let userProvider: () -> User?
    @ObservationIgnored private let cloudKitStore: (any CloudKitPreferenceStoring)?
    @ObservationIgnored private let preArmScheduler: CommutePreArmScheduler?

    init(
        apiClient: any APIClienting,
        operationState: AppOperationState,
        accessTokenProvider: @escaping () -> String?,
        userProvider: @escaping () -> User? = { nil },
        cloudKitStore: (any CloudKitPreferenceStoring)? = nil,
        preArmScheduler: CommutePreArmScheduler? = nil
    ) {
        self.apiClient = apiClient
        self.operationState = operationState
        self.accessTokenProvider = accessTokenProvider
        self.userProvider = userProvider
        self.cloudKitStore = cloudKitStore
        self.preArmScheduler = preArmScheduler
    }

    /// Home and work station, from CloudKit. Empty when iCloud cannot be read,
    /// which is the same answer the rest of this screen gives.
    var stationDefaults: UserStationDefaults {
        cloudKitPreferences?.stationDefaults
            ?? UserStationDefaults(homeStationCrs: nil, workStationCrs: nil)
    }

    /// True when the user's commutes are unreachable because iCloud is off or
    /// signed out, which the screen says out loud rather than showing an empty
    /// list that looks like deleted data.
    var isWaitingOnICloud: Bool {
        cloudKitStore != nil && !isCloudKitAvailable
    }

    func refresh() async {
        await operationState.withLoading {
            let loadedRoutines = await loadRoutines()
            routines = loadedRoutines
            do {
                try await hydrateStations(for: loadedRoutines.flatMap { [$0.originCrs, $0.destinationCrs] })
            } catch {
                operationState.recordSilentOperationError(error)
            }
            await preArm()
        }
    }

    /// Re-posts the rolling week without reloading anything. Cheap enough to
    /// call on foreground and from the background refresh task.
    func refreshPreArmedDepartures() async {
        await preArm()
    }

    func searchStations(query: String) async throws -> [StationSuggestion] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            return []
        }
        let stations = try await apiClient.searchStations(query: trimmed, limit: 8)
        remember(stations)
        return stations
    }

    func updateStationDefaults(homeStation: StationSuggestion?, workStation: StationSuggestion?) async {
        remember([homeStation, workStation].compactMap { $0 })
        await updateStationDefaults(
            homeStationCRS: homeStation?.crs,
            workStationCRS: workStation?.crs
        )
    }

    func updateStationDefaults(homeStationCRS: String?, workStationCRS: String?) async {
        guard requireCloudKit() else { return }
        let home = normalizedOptionalCRS(homeStationCRS)
        let work = normalizedOptionalCRS(workStationCRS)
        await cloudKitStore?.saveStationDefaults(homeStationCRS: home, workStationCRS: work)
        var preferences = cloudKitPreferences ?? CloudKitPreferences()
        preferences.homeStationCRS = home
        preferences.workStationCRS = work
        cloudKitPreferences = preferences
    }

    func hydrateDefaultStations(homeStationCRS: String?, workStationCRS: String?) async {
        do {
            try await hydrateStations(for: [homeStationCRS, workStationCRS].compactMap { $0 })
        } catch {
            operationState.recordSilentOperationError(error)
        }
    }

    func stationSuggestion(for crs: String?) -> StationSuggestion? {
        guard let crs = normalizedOptionalCRS(crs), !crs.isEmpty else {
            return nil
        }
        if let station = stationsByCRS[crs] {
            return station
        }
        return StationSuggestion(crs: crs, name: crs, sixteenCharacterName: nil, tpl: crs, toc: nil)
    }

    func stationName(for crs: String) -> String {
        let normalized = normalizedOptionalCRS(crs) ?? crs
        return stationsByCRS[normalized]?.displayName ?? normalized
    }

    func createRoutine(_ input: CommuteRoutineMutationRequest) async {
        guard requireCloudKit() else { return }
        // The backend no longer issues routine ids, because it no longer holds
        // routines. A UUID made here is the record name in CloudKit and the
        // only identity the routine has.
        let routine = CommuteRoutine(input: input, id: UUID().uuidString, userID: userProvider()?.id ?? "")
        await operationState.withLoading {
            await cloudKitStore?.saveRoutine(routine)
            routines.insert(routine, at: 0)
            await preArm()
        }
    }

    func updateRoutine(id: String, input: CommuteRoutineMutationRequest) async {
        guard requireCloudKit() else { return }
        let existing = routines.first { $0.id == id }
        let routine = CommuteRoutine(
            input: input,
            id: id,
            userID: existing?.userId ?? userProvider()?.id ?? "",
            createdAt: existing?.createdAt
        )
        await operationState.withLoading {
            await cloudKitStore?.saveRoutine(routine)
            if let index = routines.firstIndex(where: { $0.id == id }) {
                routines[index] = routine
            } else {
                routines.insert(routine, at: 0)
            }
            await preArm()
        }
    }

    func deleteRoutine(id: String) async {
        guard requireCloudKit() else { return }
        await operationState.withLoading {
            await cloudKitStore?.deleteRoutine(id: id)
            routines.removeAll { $0.id == id }
            await preArm()
        }
    }

    func setPaused(_ routine: CommuteRoutine, paused: Bool) async {
        var input = CommuteRoutineMutationRequest(routine: routine)
        input.status = paused ? "paused" : "active"
        await updateRoutine(id: routine.id, input: input)
    }

    func clearState() {
        routines = []
        stationsByCRS = [:]
        cloudKitPreferences = nil
        isCloudKitAvailable = false
        preArmScheduler?.clearState()
    }

    // MARK: - CloudKit

    /// Reads the routines out of the private database, migrating an account
    /// that has never been migrated.
    ///
    /// The migration is the only thing left that asks the backend about
    /// routines, and it runs once per account. It tolerates the endpoint being
    /// gone: by the time the backend drops it, every account that had routines
    /// to migrate has migrated, and an account that reaches here afterwards
    /// genuinely has nothing to copy.
    private func loadRoutines() async -> [CommuteRoutine] {
        guard let cloudKitStore, let userID = userProvider()?.id else {
            isCloudKitAvailable = false
            return []
        }
        guard let snapshot = await cloudKitStore.loadSnapshot(userID: userID) else {
            isCloudKitAvailable = false
            cloudKitPreferences = nil
            return []
        }
        isCloudKitAvailable = true

        guard snapshot.seededAt == nil else {
            cloudKitPreferences = snapshot.preferences
            return snapshot.routines
        }

        let serverRoutines = await legacyServerRoutines()
        var preferences = snapshot.preferences ?? CloudKitPreferences()
        let serverDefaults = userProvider()?.stationDefaults
        preferences.homeStationCRS = preferences.homeStationCRS ?? serverDefaults?.homeStationCrs
        preferences.workStationCRS = preferences.workStationCRS ?? serverDefaults?.workStationCrs

        let existingRoutineIDs = Set(snapshot.routines.map(\.id))
        let seeded = await cloudKitStore.seed(
            preferences: preferences,
            routines: serverRoutines,
            skippingRoutineIDs: existingRoutineIDs
        )
        guard seeded else {
            // Leave the account unmigrated so the next launch tries again,
            // rather than marking it done with nothing copied.
            cloudKitPreferences = snapshot.preferences
            return snapshot.routines
        }
        cloudKitPreferences = preferences
        let copied = serverRoutines.filter { !existingRoutineIDs.contains($0.id) }
        return (snapshot.routines + copied).sorted { $0.createdAt > $1.createdAt }
    }

    /// The backend's copy of the routines, for the one-time migration only.
    /// Any failure, including the endpoint no longer existing, means there is
    /// nothing to migrate.
    private func legacyServerRoutines() async -> [CommuteRoutine] {
        guard let accessToken = accessTokenProvider() else { return [] }
        do {
            return try await apiClient.listCommuteRoutines(accessToken: accessToken)
        } catch {
            operationState.recordSilentOperationError(error)
            return []
        }
    }

    private func preArm() async {
        guard isCloudKitAvailable, let accessToken = accessTokenProvider() else { return }
        await preArmScheduler?.synchronise(routines: routines, accessToken: accessToken)
    }

    /// Commutes cannot be edited without somewhere to put them.
    private func requireCloudKit() -> Bool {
        guard isCloudKitAvailable else {
            operationState.alertState = .network(
                "Sign in to iCloud to use commutes. RightTrain keeps them in your own iCloud account rather than on its servers."
            )
            return false
        }
        return true
    }

    // MARK: - Internals

    private func hydrateStations(for codes: [String]) async throws {
        let uniqueCodes = Set(codes.compactMap { normalizedOptionalCRS($0) })
        for code in uniqueCodes where stationsByCRS[code] == nil {
            let stations = try await apiClient.searchStations(query: code, limit: 1)
            if let exact = stations.first(where: { $0.crs.caseInsensitiveCompare(code) == .orderedSame }) {
                remember([exact])
            }
        }
    }

    private func remember(_ stations: [StationSuggestion]) {
        for station in stations {
            guard let code = normalizedOptionalCRS(station.crs) else { continue }
            stationsByCRS[code] = station
        }
    }
}

extension CommuteRoutineMutationRequest {
    init(routine: CommuteRoutine) {
        self.init(
            name: routine.name,
            status: routine.status,
            originCrs: routine.originCrs,
            destinationCrs: routine.destinationCrs,
            departureTime: routine.departureTime,
            windowMinutes: routine.windowMinutes,
            activeWeekdays: routine.activeWeekdays,
            autoArmEnabled: routine.autoArmEnabled,
            autoArmLeadMinutes: routine.autoArmLeadMinutes,
            notificationsEnabled: routine.notificationsEnabled
        )
    }
}

extension CommuteRoutine {
    /// Builds the routine the app is about to store. Timestamps are the app's
    /// own now that no server issues them; CloudKit keeps its own record
    /// metadata alongside.
    init(input: CommuteRoutineMutationRequest, id: String, userID: String, createdAt: Date? = nil) {
        let now = Date()
        self.init(
            id: id,
            userId: userID,
            name: input.name,
            status: input.status ?? "active",
            originCrs: normalizedOptionalCRS(input.originCrs) ?? input.originCrs,
            destinationCrs: normalizedOptionalCRS(input.destinationCrs) ?? input.destinationCrs,
            departureTime: input.departureTime,
            windowMinutes: input.windowMinutes,
            activeWeekdays: input.activeWeekdays,
            autoArmEnabled: input.autoArmEnabled,
            autoArmLeadMinutes: input.autoArmLeadMinutes,
            notificationsEnabled: input.notificationsEnabled,
            createdAt: createdAt ?? now,
            updatedAt: now,
            deletedAt: nil
        )
    }
}

private func normalizedOptionalCRS(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    return trimmed.isEmpty ? nil : trimmed
}
