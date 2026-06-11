import Foundation

@MainActor
@Observable
final class CommuteRoutinesViewModel {
    private(set) var routines: [CommuteRoutine] = []
    private(set) var stationsByCRS: [String: StationSuggestion] = [:]

    @ObservationIgnored private let apiClient: any APIClienting
    @ObservationIgnored private let operationState: AppOperationState
    @ObservationIgnored private let accessTokenProvider: () -> String?
    @ObservationIgnored private let userUpdateHandler: (User) -> Void

    init(
        apiClient: any APIClienting,
        operationState: AppOperationState,
        accessTokenProvider: @escaping () -> String?,
        userUpdateHandler: @escaping (User) -> Void
    ) {
        self.apiClient = apiClient
        self.operationState = operationState
        self.accessTokenProvider = accessTokenProvider
        self.userUpdateHandler = userUpdateHandler
    }

    func refresh() async {
        guard let accessToken = requireAccessToken() else { return }
        await operationState.withLoading {
            let loadedRoutines = try await apiClient.listCommuteRoutines(accessToken: accessToken)
            routines = loadedRoutines
            do {
                try await hydrateStations(for: loadedRoutines.flatMap { [$0.originCrs, $0.destinationCrs] })
            } catch {
                operationState.recordSilentOperationError(error)
            }
        }
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
            let routine = try await apiClient.createCommuteRoutine(input: input, accessToken: accessToken)
            routines.insert(routine, at: 0)
        }
    }

    func updateRoutine(id: String, input: CommuteRoutineMutationRequest) async {
        guard let accessToken = requireAccessToken() else { return }
        await operationState.withLoading {
            let routine = try await apiClient.updateCommuteRoutine(id: id, input: input, accessToken: accessToken)
            if let index = routines.firstIndex(where: { $0.id == id }) {
                routines[index] = routine
            } else {
                routines.insert(routine, at: 0)
            }
        }
    }

    func deleteRoutine(id: String) async {
        guard let accessToken = requireAccessToken() else { return }
        await operationState.withLoading {
            try await apiClient.deleteCommuteRoutine(id: id, accessToken: accessToken)
            routines.removeAll { $0.id == id }
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
    }

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
