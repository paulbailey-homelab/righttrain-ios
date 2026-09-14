import SwiftUI

struct StationPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: StationPickerViewModel
    @FocusState private var isSearchFocused: Bool
    private let onSelect: (StationSuggestion) -> Void

    init(
        context: StationPickerContext,
        apiClient: any APIClienting,
        favourites: [StationFavourite],
        locationProvider: any StationLocationProviding,
        initialChoice: StationPickerSource = .search,
        initialQuery: String = "",
        onSelect: @escaping (StationSuggestion) -> Void
    ) {
        _viewModel = State(initialValue: StationPickerViewModel(
            context: context,
            apiClient: apiClient,
            favourites: favourites,
            locationProvider: locationProvider,
            initialChoice: initialChoice,
            initialQuery: initialQuery
        ))
        self.onSelect = onSelect
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        return List {
            Section {
                Picker("Station picker source", selection: $viewModel.activeChoice) {
                    ForEach(StationPickerSource.allCases) { source in
                        Text(source.title).tag(source)
                    }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .accessibilityHint("Choose how to find a station.")
            } footer: {
                if let note = viewModel.directDestinationNote {
                    Text(note)
                }
            }
            .listSectionSpacing(.compact)

            if let station = viewModel.context.previousSelection {
                Section("Current \(viewModel.context.selectionRole.fieldTitle.lowercased())") {
                    StationPickerStationRow(station: station, showsChevron: false) {
                        select(station)
                    }
                }
            }

            sourceContent

            if let validationMessage = viewModel.validationMessage {
                Section {
                    Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.rightTrainDanger)
                        .fixedSize(horizontal: false, vertical: true)
                        .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.insetGrouped)
        // Keep the search field visible (inside a tab's navigation stack the
        // automatic placement hides it until you pull down) and focus it on
        // arrival, since typing a station is the usual reason to be here.
        // Typing always switches to the Search source.
        .searchable(
            text: queryBinding,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Station name or code"
        )
        .searchFocused($isSearchFocused)
        .textInputAutocapitalization(.characters)
        .autocorrectionDisabled()
        .navigationTitle(viewModel.context.selectionRole.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if viewModel.activeChoice == .search, viewModel.query.isEmpty {
                isSearchFocused = true
            }
        }
        // One load per source change, owned by the list. Loads used to be
        // started both here and from `.task` on the result sections; a List
        // gives those sections a new identity whenever the loading state
        // flips, which cancelled the nearby request and started another in
        // a loop that ended on "Unavailable".
        .task(id: viewModel.sourceLoadKey) {
            switch viewModel.activeChoice {
            case .search:
                await viewModel.loadSearchIfNeeded()
            case .favourites:
                await viewModel.loadFavourites()
            case .nearest:
                await viewModel.loadNearest()
            }
        }
    }

    @ViewBuilder
    private var sourceContent: some View {
        switch viewModel.activeChoice {
        case .search:
            searchContent
        case .favourites:
            favouritesContent
        case .nearest:
            nearestContent
        }
    }

    @ViewBuilder
    private var searchContent: some View {
        if viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 {
            StateMessage(
                title: "Search for a station",
                message: "Type at least two characters of a station name or three-letter code.",
                symbolName: "magnifyingglass"
            )
        } else {
            resultSection(stations: viewModel.searchResults, title: "Results")
        }
    }

    @ViewBuilder
    private var favouritesContent: some View {
        Group {
            if viewModel.favouriteRows.isEmpty {
                stateMessageFromLoadingState
            } else {
                Section("Favourites") {
                    ForEach(viewModel.favouriteRows) { favourite in
                        StationPickerFavouriteRow(favourite: favourite) {
                            select(favourite.candidate)
                        }
                    }
                }
            }
        }
    }

    private var nearestContent: some View {
        resultSection(stations: viewModel.nearestResults, title: "Nearest stations")
    }

    @ViewBuilder
    private func resultSection(stations: [StationSuggestion], title: String) -> some View {
        if viewModel.loadingState == .loading {
            Section {
                HStack(spacing: RTSpacing.small) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading stations")
                        .foregroundStyle(.secondary)
                }
            }
        } else if stations.isEmpty {
            stateMessageFromLoadingState
        } else {
            Section(title) {
                ForEach(stations) { station in
                    StationPickerStationRow(station: station) {
                        select(station)
                    }
                }
            }
        }
    }

    private var stateMessageFromLoadingState: some View {
        StateMessage(
            title: stateTitle,
            message: viewModel.loadingState.message ?? "Choose another station source.",
            symbolName: stateSymbolName
        )
    }

    private var stateTitle: String {
        switch viewModel.loadingState {
        case .failed:
            return "Unavailable"
        case .unavailable:
            return "Nearest unavailable"
        case .empty:
            return "Nothing to show"
        default:
            return "Choose a station"
        }
    }

    private var stateSymbolName: String {
        switch viewModel.loadingState {
        case .failed, .unavailable:
            return "exclamationmark.triangle"
        case .empty:
            return "tray"
        default:
            return "magnifyingglass"
        }
    }

    private var queryBinding: Binding<String> {
        Binding {
            viewModel.query
        } set: { newValue in
            viewModel.query = newValue
            if !newValue.isEmpty, viewModel.activeChoice != .search {
                viewModel.activeChoice = .search
            }
        }
    }

    private func select(_ station: StationSuggestion) {
        guard viewModel.commit(station) else { return }
        onSelect(station)
        dismiss()
    }
}

private struct StationPickerStationRow: View {
    var station: StationSuggestion
    var showsChevron = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: RTSpacing.compact) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(station.displayName)
                        .foregroundStyle(.primary)
                    if let distance = station.distanceMeters {
                        Text(distanceText(distance))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: RTSpacing.small)
                CRSBadge(crs: station.crs)
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(station.displayName), \(station.crs.uppercased())")
        .accessibilityHint("Selects this station.")
    }

    private func distanceText(_ meters: Int) -> String {
        if meters >= 1_000 {
            let kilometres = Double(meters) / 1_000
            return String(format: "%.1f km", kilometres)
        }
        return "\(meters)m"
    }
}

private struct StationPickerFavouriteRow: View {
    var favourite: StationFavourite
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: RTSpacing.compact) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(favourite.displayLabel)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.rightTrainActionInk)
                    Text(favourite.candidate.displayName)
                        .foregroundStyle(.primary)
                    if let unavailableReason = favourite.unavailableReason {
                        Text(unavailableReason)
                            .font(.caption)
                            .foregroundStyle(Color.rightTrainDanger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: RTSpacing.small)
                CRSBadge(crs: favourite.crs)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(favourite.unavailableReason != nil)
        .accessibilityLabel("\(favourite.displayLabel), \(favourite.candidate.displayName), \(favourite.crs.uppercased())")
        .accessibilityHint(favourite.unavailableReason ?? "Selects this favourite station.")
    }
}

private struct CRSBadge: View {
    var crs: String

    var body: some View {
        Text(crs.uppercased())
            .font(.footnote.weight(.semibold))
            .monospaced()
            .foregroundStyle(.secondary)
            .accessibilityLabel("Station code \(crs.uppercased())")
    }
}

private struct StateMessage: View {
    var title: String
    var message: String
    var symbolName: String

    var body: some View {
        Section {
            ContentUnavailableView(title, systemImage: symbolName, description: Text(message))
                .listRowBackground(Color.clear)
        }
    }
}

#Preview("Station picker search") {
    NavigationStack {
        StationPickerView(
            context: StationPickerContext(
                selectionRole: .origin,
                routeMode: .direct,
                selectedCounterpartCRS: "MAN",
                departureStart: PreviewFixtures.baseDate,
                windowMinutes: 120,
                sourceSurface: .journeySetup,
                previousSelection: nil
            ),
            apiClient: PreviewFixtures.previewAPIClient,
            favourites: PreviewFixtures.stationFavourites,
            locationProvider: PreviewStationLocationProvider()
        ) { _ in }
    }
}
