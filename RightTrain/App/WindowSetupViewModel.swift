import Foundation

/// Which search the app runs. This is no longer something the user chooses.
/// The planner returns direct journeys as one-leg itineraries and ranks them
/// against journeys with changes, so it is the search; `.direct` is only the
/// fallback for a backend with multi-leg routing turned off.
enum JourneySearchMode: String, CaseIterable, Identifiable {
    case direct
    case anyRoute

    var id: String { rawValue }
}

@MainActor
@Observable
final class WindowSetupViewModel {
    var origin: StationSuggestion? {
        didSet {
            if origin != oldValue {
                clearSearchResults()
            }
        }
    }
    var destination: StationSuggestion? {
        didSet {
            if destination != oldValue {
                clearSearchResults()
            }
        }
    }
    var canSwapStations: Bool {
        origin != nil || destination != nil
    }

    /// Reverses the route, e.g. for the journey home.
    func swapStations() {
        (origin, destination) = (destination, origin)
    }

    var departureStart: Date = Date() {
        didSet {
            clearSearchResults()
        }
    }
    var windowMinutes: Int = 120 {
        didSet {
            let normalized = Self.normalizedWindowMinutes(windowMinutes)
            if windowMinutes != normalized {
                windowMinutes = normalized
                return
            }
            clearSearchResults()
        }
    }
    private(set) var multiLegRoutingEnabled = false {
        didSet {
            guard multiLegRoutingEnabled != oldValue else {
                return
            }
            clearSearchResults()
        }
    }

    /// Shows only journeys with no changes. This filters what the results
    /// screen leads with; it does not narrow the search, so a journey with a
    /// change can still be offered when it is meaningfully quicker. Off by
    /// default, and remembered once set.
    var directTrainsOnly: Bool = false {
        didSet {
            guard directTrainsOnly != oldValue else {
                return
            }
            preferences.set(directTrainsOnly, forKey: Self.directTrainsOnlyKey)
        }
    }

    static let directTrainsOnlyKey = "rightTrain.search.directTrainsOnly"
    private(set) var recommendationResponse: DirectWindowRecommendationResponse?
    private(set) var journeyPlanResponse: JourneyPlanResponse?

    @ObservationIgnored private let apiClient: any APIClienting
    @ObservationIgnored private let operationState: AppOperationState
    @ObservationIgnored private let activeWindowViewModel: ActiveWindowViewModel
    @ObservationIgnored private let isSignedInProvider: () -> Bool
    @ObservationIgnored private let preferences: UserDefaults

    init(
        apiClient: any APIClienting,
        operationState: AppOperationState,
        activeWindowViewModel: ActiveWindowViewModel,
        isSignedInProvider: @escaping () -> Bool,
        preferences: UserDefaults = .standard
    ) {
        self.apiClient = apiClient
        self.operationState = operationState
        self.activeWindowViewModel = activeWindowViewModel
        self.isSignedInProvider = isSignedInProvider
        self.preferences = preferences
        // Assigned after the store is in place so the didSet that persists it
        // is writing to the right defaults.
        directTrainsOnly = preferences.bool(forKey: Self.directTrainsOnlyKey)
    }

    var canCreateActiveWindow: Bool {
        switch searchMode {
        case .direct:
            return recommendationResponse?.topRecommendation != nil
        case .anyRoute:
            return journeyPlanResponse?.topItinerary != nil
        }
    }

    var isSignedIn: Bool {
        isSignedInProvider()
    }

    /// How many direct trains a Search Pin on the current results would
    /// watch, or nil when the results can't be pinned as a search. A Search
    /// Pin is a window subscription, which watches direct trains only, so a
    /// planner search offers it whenever it found any direct train.
    var searchPinTrainCount: Int? {
        if let response = recommendationResponse {
            guard !response.recommendations.isEmpty || response.topRecommendation != nil else {
                return nil
            }
            return response.recommendations.count
        }
        guard let response = journeyPlanResponse else {
            return nil
        }
        let direct = Self.directItineraries(in: response)
        return direct.isEmpty ? nil : direct.count
    }

    private static func directItineraries(in response: JourneyPlanResponse) -> [ItineraryRecommendation] {
        // A backend that predates the separate direct pass only has the
        // mixed list, where a direct train is a one-leg itinerary.
        response.directItineraries ?? response.itineraries.filter { $0.legs.count == 1 }
    }

    var searchMode: JourneySearchMode {
        multiLegRoutingEnabled ? .anyRoute : .direct
    }

    var canUseMultiLegRouting: Bool {
        multiLegRoutingEnabled
    }

    /// The destination list is no longer filtered to stations with a direct
    /// train, so it needs a query like any other search.
    var destinationMinQueryLength: Int {
        searchMode == .direct && origin != nil ? 0 : 2
    }

    func loadAppCapabilities() async {
        do {
            applyAppCapabilities(try await apiClient.appCapabilities())
        } catch {
            applyAppCapabilities(AppCapabilitiesResponse(multiLegRoutingEnabled: false))
        }
    }

    func applyAppCapabilities(_ capabilities: AppCapabilitiesResponse) {
        multiLegRoutingEnabled = capabilities.multiLegRoutingEnabled
    }

    func setWindowMinutes(_ minutes: Int) {
        windowMinutes = Self.normalizedWindowMinutes(minutes)
    }

    func applyRoutinePrefill(
        _ routine: CommuteRoutine,
        originStation: StationSuggestion?,
        destinationStation: StationSuggestion?,
        now: Date = Date()
    ) {
        origin = originStation ?? stationSuggestion(crs: routine.originCrs)
        destination = destinationStation ?? stationSuggestion(crs: routine.destinationCrs)
        departureStart = nextRoutineDeparture(
            clock: routine.departureTime,
            activeWeekdays: routine.activeWeekdays,
            now: now
        )
        setWindowMinutes(routine.windowMinutes)
        operationState.alertState = nil
    }

    func searchStations(query: String) async throws -> [StationSuggestion] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            return []
        }
        return try await apiClient.searchStations(query: trimmed, limit: 8)
    }

    func searchDestinationStations(query: String) async throws -> [StationSuggestion] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard searchMode == .direct, let origin else {
            guard trimmed.count >= 2 else {
                return []
            }
            return try await apiClient.searchStations(query: trimmed, limit: 8)
        }
        return try await apiClient.searchDirectDestinationStations(
            originCRS: origin.crs,
            query: trimmed,
            departureStart: effectiveDepartureStart(),
            windowMinutes: windowMinutes,
            limit: trimmed.isEmpty ? 25 : 8
        )
    }

    func stationPickerContext(for role: StationPickerSelectionRole) -> StationPickerContext {
        StationPickerContext(
            selectionRole: role,
            routeMode: searchMode == .direct ? .direct : .anyRoute,
            selectedCounterpartCRS: role == .origin ? destination?.crs : origin?.crs,
            departureStart: departureStart,
            windowMinutes: windowMinutes,
            sourceSurface: .journeySetup,
            previousSelection: role == .origin ? origin : destination
        )
    }

    func applyStationPickerSelection(_ station: StationSuggestion, role: StationPickerSelectionRole) {
        switch role {
        case .origin:
            origin = station
        case .destination:
            destination = station
        }
        operationState.alertState = nil
    }

    @discardableResult
    func loadRecommendations() async -> Bool {
        guard let origin, let destination else {
            operationState.alertState = .validation("Choose both stations to search.")
            return false
        }
        let searchDepartureStart = effectiveDepartureStart()
        operationState.alertState = nil
        var didLoadResults = false

        await operationState.withLoading {
            switch searchMode {
            case .direct:
                let response = try await apiClient.recommendDirectWindow(
                    originCRS: origin.crs,
                    destinationCRS: destination.crs,
                    departureStart: searchDepartureStart,
                    windowMinutes: windowMinutes
                )
                recommendationResponse = response
                journeyPlanResponse = nil
                didLoadResults = true
            case .anyRoute:
                let response = try await apiClient.planJourney(
                    originCRS: origin.crs,
                    destinationCRS: destination.crs,
                    departureStart: searchDepartureStart,
                    windowMinutes: windowMinutes,
                    maxChanges: 3,
                    limit: 5
                )
                journeyPlanResponse = response
                recommendationResponse = nil
                didLoadResults = true
            }
        }
        return didLoadResults
    }

    func createActiveWindow(replacingActiveJourney: Bool = false) async {
        guard let origin, let destination else {
            operationState.alertState = .validation("Choose both stations before creating a Pin.")
            return
        }
        guard isSignedInProvider() else {
            operationState.alertState = .auth("Sign in to create a Pin.")
            return
        }
        let searchDepartureStart = effectiveDepartureStart()
        // Pinning the whole search watches its direct trains, whichever
        // search found them. Only a planner search with no direct train at
        // all falls back to monitoring its top route.
        let pinsDirectTrains = searchMode == .direct
            || journeyPlanResponse.map { !Self.directItineraries(in: $0).isEmpty } == true

        await operationState.withLoading {
            if replacingActiveJourney {
                try await activeWindowViewModel.replaceActiveJourneyIfNeeded()
            }
            if pinsDirectTrains, searchMode == .anyRoute {
                _ = try await activeWindowViewModel.createWindow(
                    input: CreateWindowSubscriptionRequest(
                        originCrs: origin.crs,
                        destinationCrs: destination.crs,
                        originTpl: origin.tpl,
                        destinationTpl: destination.tpl,
                        departureStart: searchDepartureStart,
                        windowMinutes: windowMinutes
                    )
                )
                // The planner results stay on screen, as they do when a
                // single direct train from them is pinned.
                return
            }
            switch searchMode {
            case .direct:
                let subscription = try await activeWindowViewModel.createWindow(
                    input: CreateWindowSubscriptionRequest(
                        originCrs: origin.crs,
                        destinationCrs: destination.crs,
                        originTpl: origin.tpl,
                        destinationTpl: destination.tpl,
                        departureStart: searchDepartureStart,
                        windowMinutes: windowMinutes
                    )
                )
                recommendationResponse = DirectWindowRecommendationResponse(
                    topRecommendation: subscription.selectedRecommendation,
                    recommendations: subscription.recommendations
                )
                journeyPlanResponse = nil
            case .anyRoute:
                let subscription = try await activeWindowViewModel.createItinerary(
                    input: CreateItinerarySubscriptionRequest(
                        originCrs: origin.crs,
                        destinationCrs: destination.crs,
                        departureStart: searchDepartureStart,
                        windowMinutes: windowMinutes,
                        maxChanges: 3,
                        limit: 5
                    )
                )
                journeyPlanResponse = JourneyPlanResponse(
                    topItinerary: subscription.selectedItinerary,
                    itineraries: subscription.itineraries,
                    topDirectItinerary: journeyPlanResponse?.topDirectItinerary,
                    directItineraries: journeyPlanResponse?.directItineraries,
                    timetableId: journeyPlanResponse?.timetableId,
                    generatedAt: subscription.createdAt
                )
                recommendationResponse = nil
            }
        }
    }

    func createActiveWindow(for recommendation: DirectWindowRecommendation, replacingActiveJourney: Bool = false) async {
        guard isSignedInProvider() else {
            operationState.alertState = .auth("Sign in to create a Pin.")
            return
        }
        let journey = recommendation.journey

        await operationState.withLoading {
            if replacingActiveJourney {
                try await activeWindowViewModel.replaceActiveJourneyIfNeeded()
            }
            let subscription = try await activeWindowViewModel.createWindow(
                input: CreateWindowSubscriptionRequest(
                    originCrs: journey.originCrs,
                    destinationCrs: journey.destinationCrs,
                    originTpl: journey.originTpl,
                    destinationTpl: journey.destinationTpl,
                    departureStart: departureStart,
                    windowMinutes: windowMinutes,
                    selectedTrainServiceId: journey.serviceId
                )
            )
            recommendationResponse = DirectWindowRecommendationResponse(
                topRecommendation: subscription.selectedRecommendation,
                recommendations: subscription.recommendations
            )
            journeyPlanResponse = nil
        }
    }

    func createActiveItinerary(for itinerary: ItineraryRecommendation, replacingActiveJourney: Bool = false) async {
        guard let origin, let destination else {
            operationState.alertState = .validation("Choose both stations before creating a Pin.")
            return
        }
        guard isSignedInProvider() else {
            operationState.alertState = .auth("Sign in to create a Pin.")
            return
        }
        guard multiLegRoutingEnabled else {
            operationState.alertState = .validation("All routes are coming soon.")
            return
        }
        let searchDepartureStart = effectiveDepartureStart()
        let selectedStableKey = itinerary.stableKey.trimmingCharacters(in: .whitespacesAndNewlines)

        // A result with no changes is a direct train, whatever search found
        // it, so it is monitored as one. The user is not shown this branch:
        // they picked a journey, not a subscription kind.
        if itinerary.legs.count == 1, let leg = itinerary.legs.first {
            await operationState.withLoading {
                if replacingActiveJourney {
                    try await activeWindowViewModel.replaceActiveJourneyIfNeeded()
                }
                _ = try await activeWindowViewModel.createWindow(
                    input: CreateWindowSubscriptionRequest(
                        originCrs: leg.originCrs,
                        destinationCrs: leg.destinationCrs,
                        originTpl: leg.originTpl,
                        destinationTpl: leg.destinationTpl,
                        departureStart: searchDepartureStart,
                        windowMinutes: windowMinutes,
                        selectedTrainServiceId: leg.serviceId
                    )
                )
                // The itinerary list stays on screen with the pinned row
                // marked; swapping it for the direct results would redraw
                // every row for a journey the user has already chosen.
            }
            return
        }

        await operationState.withLoading {
            if replacingActiveJourney {
                try await activeWindowViewModel.replaceActiveJourneyIfNeeded()
            }
            let subscription = try await activeWindowViewModel.createItinerary(
                input: CreateItinerarySubscriptionRequest(
                    originCrs: origin.crs,
                    destinationCrs: destination.crs,
                    departureStart: searchDepartureStart,
                    windowMinutes: windowMinutes,
                    maxChanges: 3,
                    limit: 5,
                    selectedItineraryStableKey: selectedStableKey.isEmpty ? nil : selectedStableKey
                )
            )
            journeyPlanResponse = JourneyPlanResponse(
                topItinerary: subscription.selectedItinerary,
                itineraries: subscription.itineraries,
                topDirectItinerary: journeyPlanResponse?.topDirectItinerary,
                directItineraries: journeyPlanResponse?.directItineraries,
                timetableId: journeyPlanResponse?.timetableId,
                generatedAt: subscription.createdAt
            )
            recommendationResponse = nil
        }
    }

    func clearState() {
        clearSearchResults()
    }

    func resetForNewJourneyPlan() {
        origin = nil
        destination = nil
        departureStart = Date()
        windowMinutes = 120
        operationState.alertState = nil
        clearSearchResults()
    }

    private func clearSearchResults() {
        recommendationResponse = nil
        journeyPlanResponse = nil
    }

    static func normalizedWindowMinutes(_ minutes: Int) -> Int {
        let snapped = Int((Double(minutes) / 30.0).rounded()) * 30
        return min(max(snapped, 30), 360)
    }

    private func effectiveDepartureStart(now: Date = Date()) -> Date {
        if departureStart < now {
            departureStart = now
            return now
        }
        return departureStart
    }

    private func nextRoutineDeparture(clock: String, activeWeekdays: [Int], now: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London") ?? .current
        let parts = clock.split(separator: ":").compactMap { Int($0) }
        let hour = parts.first ?? calendar.component(.hour, from: now)
        let minute = parts.dropFirst().first ?? calendar.component(.minute, from: now)
        let activeDays = Set(activeWeekdays.isEmpty ? Array(1...7) : activeWeekdays)

        for dayOffset in 0...14 {
            guard let candidateDay = calendar.date(byAdding: .day, value: dayOffset, to: now) else {
                continue
            }
            var components = calendar.dateComponents([.year, .month, .day], from: candidateDay)
            components.hour = min(max(hour, 0), 23)
            components.minute = min(max(minute, 0), 59)
            components.second = 0
            guard let candidate = calendar.date(from: components),
                  activeDays.contains(appWeekday(for: candidate, calendar: calendar)),
                  candidate >= now else {
                continue
            }
            return candidate
        }

        return now
    }

    private func appWeekday(for date: Date, calendar: Calendar) -> Int {
        let calendarWeekday = calendar.component(.weekday, from: date)
        return calendarWeekday == 1 ? 7 : calendarWeekday - 1
    }

    private func stationSuggestion(crs: String) -> StationSuggestion {
        let normalized = crs.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return StationSuggestion(
            crs: normalized,
            name: normalized,
            sixteenCharacterName: nil,
            tpl: normalized,
            toc: nil
        )
    }
}
