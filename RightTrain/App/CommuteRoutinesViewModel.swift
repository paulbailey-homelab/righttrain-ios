import Foundation

@MainActor
@Observable
final class CommuteRoutinesViewModel {
    private(set) var routines: [CommuteRoutine] = []
    private(set) var stationsByCRS: [String: StationSuggestion] = [:]

    /// The preferences CloudKit holds, once they have been read successfully.
    private(set) var cloudKitPreferences: CloudKitPreferences?

    /// Whether the last read of the private database succeeded. Everything
    /// that moves work off the server is gated on this: when iCloud cannot be
    /// reached the app behaves exactly as it did before, reading routines from
    /// the server and leaving the server's own auto-arm to do the arming.
    private(set) var isCloudKitAuthoritative = false

    @ObservationIgnored private let apiClient: any APIClienting
    @ObservationIgnored private let operationState: AppOperationState
    @ObservationIgnored private let accessTokenProvider: () -> String?
    @ObservationIgnored private let userProvider: () -> User?
    @ObservationIgnored private let userUpdateHandler: (User) -> Void
    @ObservationIgnored private let cloudKitStore: (any CloudKitPreferenceStoring)?
    @ObservationIgnored private let preArmScheduler: CommutePreArmScheduler?

    init(
        apiClient: any APIClienting,
        operationState: AppOperationState,
        accessTokenProvider: @escaping () -> String?,
        userProvider: @escaping () -> User? = { nil },
        userUpdateHandler: @escaping (User) -> Void,
        cloudKitStore: (any CloudKitPreferenceStoring)? = nil,
        preArmScheduler: CommutePreArmScheduler? = nil
    ) {
        self.apiClient = apiClient
        self.operationState = operationState
        self.accessTokenProvider = accessTokenProvider
        self.userProvider = userProvider
        self.userUpdateHandler = userUpdateHandler
        self.cloudKitStore = cloudKitStore
        self.preArmScheduler = preArmScheduler
    }

    /// Home and work station, from CloudKit when it can be read and from the
    /// server account otherwise. Reading through here rather than off the user
    /// is what makes CloudKit the source of truth for them.
    var stationDefaults: UserStationDefaults {
        if let cloudKitPreferences {
            return cloudKitPreferences.stationDefaults
        }
        return userProvider()?.stationDefaults ?? UserStationDefaults(homeStationCrs: nil, workStationCrs: nil)
    }

    func refresh() async {
        guard let accessToken = requireAccessToken() else { return }
        await operationState.withLoading {
            let serverRoutines = try await apiClient.listCommuteRoutines(accessToken: accessToken)
            let loadedRoutines = await resolveRoutines(serverRoutines: serverRoutines)
            routines = loadedRoutines
            await handOverArmingIfNeeded(serverRoutines: serverRoutines, accessToken: accessToken)
            do {
                try await hydrateStations(for: loadedRoutines.flatMap { [$0.originCrs, $0.destinationCrs] })
            } catch {
                operationState.recordSilentOperationError(error)
            }
            await preArm(accessToken: accessToken)
        }
    }

    /// Re-posts the rolling week without reloading anything. Cheap enough to
    /// call on foreground and from the background refresh task.
    func refreshPreArmedDepartures() async {
        guard let accessToken = accessTokenProvider() else { return }
        await preArm(accessToken: accessToken)
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
        guard let accessToken = requireAccessToken() else { return }
        await operationState.withLoading {
            let updatedUser = try await apiClient.updateStationDefaults(
                input: UpdateStationDefaultsRequest(
                    homeStationCrs: normalizedOptionalCRS(homeStationCRS),
                    workStationCrs: normalizedOptionalCRS(workStationCRS)
                ),
                accessToken: accessToken
            )
            userUpdateHandler(updatedUser)
            await cloudKitStore?.saveStationDefaults(
                homeStationCRS: updatedUser.stationDefaults.homeStationCrs,
                workStationCRS: updatedUser.stationDefaults.workStationCrs
            )
            if cloudKitPreferences != nil {
                cloudKitPreferences?.homeStationCRS = updatedUser.stationDefaults.homeStationCrs
                cloudKitPreferences?.workStationCRS = updatedUser.stationDefaults.workStationCrs
            }
        }
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
        guard let accessToken = requireAccessToken() else { return }
        await operationState.withLoading {
            let created = try await apiClient.createCommuteRoutine(
                input: serverCopy(of: input),
                accessToken: accessToken
            )
            let routine = withIntendedAutoArm(created, from: input)
            routines.insert(routine, at: 0)
            await cloudKitStore?.saveRoutine(routine)
            await preArm(accessToken: accessToken)
        }
    }

    func updateRoutine(id: String, input: CommuteRoutineMutationRequest) async {
        guard let accessToken = requireAccessToken() else { return }
        await operationState.withLoading {
            let updated = try await apiClient.updateCommuteRoutine(
                id: id,
                input: serverCopy(of: input),
                accessToken: accessToken
            )
            let routine = withIntendedAutoArm(updated, from: input)
            if let index = routines.firstIndex(where: { $0.id == id }) {
                routines[index] = routine
            } else {
                routines.insert(routine, at: 0)
            }
            await cloudKitStore?.saveRoutine(routine)
            await preArm(accessToken: accessToken)
        }
    }

    func deleteRoutine(id: String) async {
        guard let accessToken = requireAccessToken() else { return }
        await operationState.withLoading {
            try await apiClient.deleteCommuteRoutine(id: id, accessToken: accessToken)
            routines.removeAll { $0.id == id }
            await cloudKitStore?.deleteRoutine(id: id)
            await preArm(accessToken: accessToken)
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
        isCloudKitAuthoritative = false
        preArmScheduler?.clearState()
    }

    // MARK: - CloudKit

    /// Decides which copy of the routines the app is going to use, and copies
    /// the server's into CloudKit the first time round.
    ///
    /// The migration runs once per account, not once per device, and is marked
    /// in CloudKit itself. Afterwards the zone is authoritative and the server
    /// copy is never read again, so that a routine deleted on one device is
    /// not resurrected by the next launch of another.
    private func resolveRoutines(serverRoutines: [CommuteRoutine]) async -> [CommuteRoutine] {
        guard let cloudKitStore, let userID = userProvider()?.id else {
            isCloudKitAuthoritative = false
            return serverRoutines
        }
        guard let snapshot = await cloudKitStore.loadSnapshot(userID: userID) else {
            // iCloud is off, signed out or unreachable. Nothing changes: the
            // server copy is read as before and keeps arming itself.
            isCloudKitAuthoritative = false
            cloudKitPreferences = nil
            return serverRoutines
        }

        guard snapshot.seededAt == nil else {
            cloudKitPreferences = snapshot.preferences
            isCloudKitAuthoritative = true
            return snapshot.routines
        }

        // Never migrated. Copy the server's state in, keeping anything the
        // zone already holds: stage one wrote station defaults here, and a
        // value already in CloudKit is the newer of the two.
        let serverDefaults = userProvider()?.stationDefaults
            ?? UserStationDefaults(homeStationCrs: nil, workStationCrs: nil)
        var preferences = snapshot.preferences ?? CloudKitPreferences()
        preferences.homeStationCRS = preferences.homeStationCRS ?? serverDefaults.homeStationCrs
        preferences.workStationCRS = preferences.workStationCRS ?? serverDefaults.workStationCrs

        let existingRoutineIDs = Set(snapshot.routines.map(\.id))
        let seeded = await cloudKitStore.seed(
            preferences: preferences,
            routines: serverRoutines,
            skippingRoutineIDs: existingRoutineIDs
        )
        guard seeded else {
            // The copy did not finish. Nothing may move off the server until
            // it does, or arming would be handed over to a CloudKit zone that
            // does not hold the routines.
            isCloudKitAuthoritative = false
            cloudKitPreferences = nil
            return serverRoutines
        }
        cloudKitPreferences = preferences
        isCloudKitAuthoritative = true
        let copied = serverRoutines.filter { !existingRoutineIDs.contains($0.id) }
        return (snapshot.routines + copied).sorted { $0.createdAt > $1.createdAt }
    }

    /// Turns the server's own auto-arm off, once the app is doing the arming.
    ///
    /// Both would otherwise arm the same departure, and each window
    /// subscription spends the account's active-window entitlement, so the
    /// second one either fails or crowds out a window the user set by hand.
    /// The routine's real auto-arm setting lives in CloudKit from here on; the
    /// server row keeps only what the server still needs.
    ///
    /// This runs on every refresh and is a no-op once every routine is off,
    /// which also repairs a handover that was interrupted halfway.
    private func handOverArmingIfNeeded(serverRoutines: [CommuteRoutine], accessToken: String) async {
        guard isCloudKitAuthoritative else { return }
        for routine in serverRoutines where routine.autoArmEnabled {
            do {
                _ = try await apiClient.updateCommuteRoutine(
                    id: routine.id,
                    input: serverCopy(of: CommuteRoutineMutationRequest(routine: routine)),
                    accessToken: accessToken
                )
            } catch {
                operationState.recordSilentOperationError(error)
            }
        }
    }

    private func preArm(accessToken: String) async {
        guard isCloudKitAuthoritative else { return }
        await preArmScheduler?.synchronise(routines: routines, accessToken: accessToken)
    }

    /// The routine as the server should hold it: auto-arm off, because the app
    /// arms now. Every other field is unchanged, since the server still needs
    /// them until stage 4 removes the table.
    private func serverCopy(of input: CommuteRoutineMutationRequest) -> CommuteRoutineMutationRequest {
        guard isCloudKitAuthoritative else { return input }
        var copy = input
        copy.autoArmEnabled = false
        return copy
    }

    private func withIntendedAutoArm(
        _ routine: CommuteRoutine,
        from input: CommuteRoutineMutationRequest
    ) -> CommuteRoutine {
        var routine = routine
        routine.autoArmEnabled = input.autoArmEnabled
        return routine
    }

    // MARK: - Internals

    private func requireAccessToken() -> String? {
        guard let accessToken = accessTokenProvider() else {
            operationState.alertState = .auth("Sign in to manage commutes.")
            return nil
        }
        return accessToken
    }

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

private func normalizedOptionalCRS(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    return trimmed.isEmpty ? nil : trimmed
}
