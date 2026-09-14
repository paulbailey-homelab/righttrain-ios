import Foundation

enum StationPickerSelectionRole: String, CaseIterable, Identifiable, Hashable {
    case origin
    case destination

    var id: String { rawValue }

    var title: String {
        switch self {
        case .origin:
            return "Choose origin"
        case .destination:
            return "Choose destination"
        }
    }

    var fieldTitle: String {
        switch self {
        case .origin:
            return "From"
        case .destination:
            return "To"
        }
    }
}

enum StationPickerRouteMode: String, Hashable {
    case direct
    case anyRoute = "any_route"
}

enum StationPickerSource: String, CaseIterable, Identifiable {
    case search
    case favourites
    case nearest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .search:
            return "Search"
        case .favourites:
            return "Favourites"
        case .nearest:
            return "Nearest"
        }
    }
}

enum StationPickerLoadingState: Equatable {
    case idle
    case loading
    case loaded
    case empty(String)
    case unavailable(String)
    case failed(String)

    var message: String? {
        switch self {
        case .idle, .loading, .loaded:
            return nil
        case .empty(let message), .unavailable(let message), .failed(let message):
            return message
        }
    }
}

enum StationPickerSourceSurface: String, Hashable {
    case journeySetup
    case commuteDefaults
    case routineEditor
}

struct StationPickerContext: Equatable {
    var selectionRole: StationPickerSelectionRole
    var routeMode: StationPickerRouteMode
    var selectedCounterpartCRS: String?
    var departureStart: Date?
    var windowMinutes: Int
    var sourceSurface: StationPickerSourceSurface
    var previousSelection: StationSuggestion?
}

@MainActor
@Observable
final class StationPickerViewModel {
    var activeChoice: StationPickerSource = .search
    var query = ""
    private(set) var searchResults: [StationSuggestion] = []
    private(set) var favouriteRows: [StationFavourite] = []
    private(set) var nearestResults: [StationSuggestion] = []
    private(set) var loadingState: StationPickerLoadingState = .idle
    var validationMessage: String?

    let context: StationPickerContext
    @ObservationIgnored private let apiClient: any APIClienting
    @ObservationIgnored private let locationProvider: any StationLocationProviding
    @ObservationIgnored private let favourites: [StationFavourite]

    init(
        context: StationPickerContext,
        apiClient: any APIClienting,
        favourites: [StationFavourite],
        locationProvider: any StationLocationProviding,
        initialChoice: StationPickerSource = .search,
        initialQuery: String = ""
    ) {
        activeChoice = initialChoice
        query = initialQuery
        self.context = context
        self.apiClient = apiClient
        self.favourites = favourites
        self.locationProvider = locationProvider
    }

    var requiresDirectDestinationEligibility: Bool {
        context.selectionRole == .destination &&
            context.routeMode == .direct &&
            normalizedCRS(context.selectedCounterpartCRS) != nil
    }

    /// Destination results are limited to stations with a direct train from
    /// the origin; say so, or a station that needs a change just seems missing.
    var directDestinationNote: String? {
        guard requiresDirectDestinationEligibility,
              let originCRS = normalizedCRS(context.selectedCounterpartCRS) else {
            return nil
        }
        return "Only stations with a direct train from \(originCRS) are shown. Journeys that need a change aren't supported yet."
    }

    var sourceLoadKey: String {
        "\(activeChoice.rawValue)|\(query)|\(context.selectionRole.rawValue)|\(context.selectedCounterpartCRS ?? "")|\(context.routeMode.rawValue)"
    }

    func loadSearchIfNeeded() async {
        guard activeChoice == .search else { return }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        searchResults = []
        validationMessage = nil
        guard trimmed.count >= 2 else {
            loadingState = .idle
            return
        }
        do {
            try await Task.sleep(for: .milliseconds(250))
            try Task.checkCancellation()
            loadingState = .loading
            let results: [StationSuggestion]
            if requiresDirectDestinationEligibility, let originCRS = normalizedCRS(context.selectedCounterpartCRS) {
                results = try await apiClient.searchDirectDestinationStations(
                    originCRS: originCRS,
                    query: trimmed,
                    departureStart: context.departureStart ?? Date(),
                    windowMinutes: context.windowMinutes,
                    limit: 8
                )
            } else {
                results = try await apiClient.searchStations(query: trimmed, limit: 8)
            }
            try Task.checkCancellation()
            searchResults = results
            if results.isEmpty {
                if requiresDirectDestinationEligibility, let originCRS = normalizedCRS(context.selectedCounterpartCRS) {
                    loadingState = .empty("No station matching \(trimmed.uppercased()) has a direct train from \(originCRS) in this window.")
                } else {
                    loadingState = .empty("No station found for \(trimmed.uppercased()).")
                }
            } else {
                loadingState = .loaded
            }
        } catch is CancellationError {
        } catch let urlError as URLError where urlError.code == .cancelled {
        } catch {
            searchResults = []
            loadingState = .failed("Station search is unavailable. Try again in a moment.")
        }
    }

    func loadFavourites() async {
        guard activeChoice == .favourites else { return }
        validationMessage = nil
        guard !favourites.isEmpty else {
            favouriteRows = []
            loadingState = .empty("No favourite stations yet. Add home, work, or commute stations to see them here.")
            return
        }
        loadingState = .loading
        do {
            favouriteRows = try await favouritesWithEligibility()
            loadingState = .loaded
        } catch is CancellationError {
        } catch {
            favouriteRows = favourites
            loadingState = .failed("Favourite eligibility is unavailable. Search is still available.")
        }
    }

    func loadNearest() async {
        guard activeChoice == .nearest else { return }
        validationMessage = nil
        nearestResults = []
        loadingState = .loading
        do {
            let location = try await locationProvider.currentLocation()
            let response = try await apiClient.searchNearbyStations(
                latitude: location.latitude,
                longitude: location.longitude,
                selectionRole: context.selectionRole,
                routeMode: context.routeMode,
                originCRS: requiresDirectDestinationEligibility ? normalizedCRS(context.selectedCounterpartCRS) : nil,
                departureStart: requiresDirectDestinationEligibility ? context.departureStart : nil,
                windowMinutes: context.windowMinutes,
                limit: 8
            )
            guard response.sourceFreshness.isFresh else {
                nearestResults = []
                loadingState = .unavailable(Self.nearestUnavailableMessage(reason: response.sourceFreshness.unavailableReason))
                return
            }
            nearestResults = response.stations
            loadingState = response.stations.isEmpty
                ? .empty("No nearby stations were found. Search and favourites are still available.")
                : .loaded
        } catch let error as StationLocationProviderError {
            guard !Task.isCancelled else { return }
            nearestResults = []
            loadingState = .unavailable(error.localizedDescription)
        } catch {
            // Leaving Nearest cancels the request; that isn't a failure to show.
            guard !Task.isCancelled else { return }
            nearestResults = []
            loadingState = .failed("Nearest stations are unavailable. Search and favourites are still available.")
        }
    }

    func commit(_ station: StationSuggestion) -> Bool {
        let selectedCRS = normalizedCRS(station.crs)
        let counterpartCRS = normalizedCRS(context.selectedCounterpartCRS)
        if selectedCRS != nil, selectedCRS == counterpartCRS {
            validationMessage = "Origin and destination cannot both be \(station.crs.uppercased())."
            return false
        }
        validationMessage = nil
        return true
    }

    private func favouritesWithEligibility() async throws -> [StationFavourite] {
        guard requiresDirectDestinationEligibility,
              let originCRS = normalizedCRS(context.selectedCounterpartCRS) else {
            return favourites
        }

        var resolved: [StationFavourite] = []
        for favourite in favourites {
            try Task.checkCancellation()
            let matches = try await apiClient.searchDirectDestinationStations(
                originCRS: originCRS,
                query: favourite.crs,
                departureStart: context.departureStart ?? Date(),
                windowMinutes: context.windowMinutes,
                limit: 1
            )
            var row = favourite
            if let exact = matches.first(where: { normalizedCRS($0.crs) == normalizedCRS(favourite.crs) }) {
                row.candidate = exact
                row.unavailableReason = nil
            } else {
                row.unavailableReason = "No direct service from \(originCRS) in this window."
            }
            resolved.append(row)
        }
        return resolved
    }

    private static func nearestUnavailableMessage(reason: String?) -> String {
        switch reason {
        case "station_lookup_unavailable":
            return "Nearest stations are unavailable while station data refreshes. Search and favourites are still available."
        case "coordinate_coverage_unavailable":
            return "Nearest stations need station coordinates that are not available right now."
        case "direct_destination_index_unavailable":
            return "Nearest direct destinations are unavailable right now. Search is still available."
        case "station_metadata_stale":
            return "Nearest stations are paused because station metadata is stale."
        default:
            return "Nearest stations are unavailable right now. Search and favourites are still available."
        }
    }

    private func normalizedCRS(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return trimmed.isEmpty ? nil : trimmed
    }
}
