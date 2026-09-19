import Foundation

enum JourneySearchMode: String, CaseIterable, Identifiable {
    case direct
    case anyRoute

    var id: String { rawValue }

    func title(multiLegRoutingEnabled: Bool) -> String {
        switch self {
        case .direct:
            return "Direct trains"
        case .anyRoute:
            return "All routes"
        }
    }
}

enum JourneySetupIntent: String, CaseIterable, Identifiable {
    case routineCommute
    case oneOffDirect
    case connectionSensitive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .routineCommute:
            return "Commute"
        case .oneOffDirect:
            return "One-off direct"
        case .connectionSensitive:
            return "Connection-sensitive"
        }
    }

    var shortTitle: String {
        switch self {
        case .routineCommute:
            return "Commute"
        case .oneOffDirect:
            return "Direct"
        case .connectionSensitive:
            return "Changes"
        }
    }

    var detailText: String {
        switch self {
        case .routineCommute:
            return "Start from a known route and adjust the live window before monitoring."
        case .oneOffDirect:
            return "Pick a route and compare direct trains by catchability and live confidence."
        case .connectionSensitive:
            return "Compare routes with changes by first action and transfer risk."
        }
    }

    var primaryActionText: String {
        switch self {
        case .routineCommute:
            return "Find commute options"
        case .oneOffDirect:
            return "Find direct trains"
        case .connectionSensitive:
            return "Find routes with changes"
        }
    }

    var defaultWindowMinutes: Int {
        switch self {
        case .routineCommute, .oneOffDirect:
            return 120
        case .connectionSensitive:
            return 180
        }
    }

    var searchMode: JourneySearchMode {
        switch self {
        case .routineCommute, .oneOffDirect:
            return .direct
        case .connectionSensitive:
            return .anyRoute
        }
    }
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
    var directRoutesOnly: Bool = true {
        didSet {
            if !directRoutesOnly && !multiLegRoutingEnabled {
                directRoutesOnly = true
            }
            guard directRoutesOnly != oldValue else {
                return
            }
            if directRoutesOnly {
                if activeSetupIntent == .connectionSensitive {
                    activeSetupIntent = .oneOffDirect
                }
            } else {
                activeSetupIntent = .connectionSensitive
            }
            clearSearchResults()
            operationState.alertState = nil
        }
    }
    private(set) var multiLegRoutingEnabled = false {
        didSet {
            if !multiLegRoutingEnabled {
                directRoutesOnly = true
                if activeSetupIntent == .connectionSensitive {
                    activeSetupIntent = .oneOffDirect
                }
            }
        }
    }
    private(set) var activeSetupIntent: JourneySetupIntent = .oneOffDirect
    private(set) var recommendationResponse: DirectWindowRecommendationResponse?
    private(set) var journeyPlanResponse: JourneyPlanResponse?

    @ObservationIgnored private let apiClient: any APIClienting
    @ObservationIgnored private let operationState: AppOperationState
    @ObservationIgnored private let activeWindowViewModel: ActiveWindowViewModel
    @ObservationIgnored private let isSignedInProvider: () -> Bool

    init(
        apiClient: any APIClienting,
        operationState: AppOperationState,
        activeWindowViewModel: ActiveWindowViewModel,
        isSignedInProvider: @escaping () -> Bool
    ) {
        self.apiClient = apiClient
        self.operationState = operationState
        self.activeWindowViewModel = activeWindowViewModel
        self.isSignedInProvider = isSignedInProvider
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

    var searchMode: JourneySearchMode {
        directRoutesOnly ? .direct : .anyRoute
    }

    var setupIntentContent: JourneySetupIntent {
        activeSetupIntent
    }

    var canUseMultiLegRouting: Bool {
        multiLegRoutingEnabled
    }

    var destinationMinQueryLength: Int {
        directRoutesOnly && origin != nil ? 0 : 2
    }

    func routeModeTitle(_ mode: JourneySearchMode) -> String {
        mode.title(multiLegRoutingEnabled: multiLegRoutingEnabled)
    }

    func isRouteModeEnabled(_ mode: JourneySearchMode) -> Bool {
        mode == .direct || multiLegRoutingEnabled
    }

    func setSearchMode(_ mode: JourneySearchMode) {
        guard isRouteModeEnabled(mode) else {
            directRoutesOnly = true
            activeSetupIntent = .oneOffDirect
            operationState.alertState = .validation("All routes are coming soon.")
            return
        }
        directRoutesOnly = mode == .direct
        if mode == .anyRoute {
            activeSetupIntent = .connectionSensitive
        } else if activeSetupIntent == .connectionSensitive {
            activeSetupIntent = .oneOffDirect
        }
    }

    func selectSetupIntent(_ intent: JourneySetupIntent) {
        guard intent != .connectionSensitive || multiLegRoutingEnabled else {
            activeSetupIntent = .oneOffDirect
            directRoutesOnly = true
            operationState.alertState = .validation("Routes with changes are coming soon.")
            return
        }
        activeSetupIntent = intent
        directRoutesOnly = intent.searchMode == .direct
        windowMinutes = intent.defaultWindowMinutes
        operationState.alertState = nil
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
        activeSetupIntent = .routineCommute
        directRoutesOnly = true
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
        guard directRoutesOnly, let origin else {
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
            routeMode: directRoutesOnly ? .direct : .anyRoute,
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
        guard searchMode == .direct || multiLegRoutingEnabled else {
            operationState.alertState = .validation("All routes are coming soon.")
            directRoutesOnly = true
            return false
        }

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

    /// Runs the same route again allowing changes. The direct results screen
    /// offers this when it finds nothing, so a dead end does not send the
    /// user back to the setup form to flip the trip type by hand.
    @discardableResult
    func searchRoutesWithChanges() async -> Bool {
        guard multiLegRoutingEnabled else {
            operationState.alertState = .validation("All routes are coming soon.")
            return false
        }
        directRoutesOnly = false
        return await loadRecommendations()
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
        guard searchMode == .direct || multiLegRoutingEnabled else {
            operationState.alertState = .validation("All routes are coming soon.")
            directRoutesOnly = true
            return
        }
        let searchDepartureStart = effectiveDepartureStart()

        await operationState.withLoading {
            if replacingActiveJourney {
                try await activeWindowViewModel.replaceActiveJourneyIfNeeded()
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
            directRoutesOnly = true
            return
        }
        let searchDepartureStart = effectiveDepartureStart()
        let selectedStableKey = itinerary.stableKey.trimmingCharacters(in: .whitespacesAndNewlines)

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
        directRoutesOnly = true
        activeSetupIntent = .oneOffDirect
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
