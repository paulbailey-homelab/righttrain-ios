import SwiftUI

struct StationPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: StationPickerViewModel
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

        return ScrollView {
            VStack(alignment: .leading, spacing: RTSpacing.sectionGap) {
                header

                Picker("Station picker source", selection: $viewModel.activeChoice) {
                    ForEach(StationPickerSource.allCases) { source in
                        Text(source.title).tag(source)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityHint("Choose how to find a station.")

                sourceContent
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, RTSpacing.pageHorizontal)
            .padding(.vertical, RTSpacing.pageVertical)
            .lightSurfaceForeground()
        }
        .background(Color.rightTrainSurfaceCream.ignoresSafeArea())
        .navigationTitle(viewModel.context.selectionRole.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
        }
        .task(id: viewModel.searchTaskKey) {
            await viewModel.loadSearchIfNeeded()
        }
        .onChange(of: viewModel.activeChoice) { _, choice in
            Task {
                switch choice {
                case .search:
                    await viewModel.loadSearchIfNeeded()
                case .favourites:
                    await viewModel.loadFavourites()
                case .nearest:
                    await viewModel.loadNearest()
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: RTSpacing.compact) {
            if let station = viewModel.context.previousSelection {
                StationPickerSelectedSummary(role: viewModel.context.selectionRole, station: station)
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

    private var searchContent: some View {
        VStack(alignment: .leading, spacing: RTSpacing.compact) {
            TextField("Station name or code", text: queryBinding)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .padding(.horizontal, RTSpacing.compact)
                .frame(minHeight: 52)
                .background(Color.rightTrainPaperCream, in: RoundedRectangle(cornerRadius: RTRadius.chip))
                .overlay {
                    RoundedRectangle(cornerRadius: RTRadius.chip)
                        .stroke(Color.rightTrainInkFaint, lineWidth: 1)
                }
                .accessibilityLabel("\(viewModel.context.selectionRole.fieldTitle) station search")

            if viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 {
                StateMessage(
                    title: "Type at least two characters",
                    message: "Use a station name or three-letter station code.",
                    symbolName: "magnifyingglass"
                )
            } else {
                resultList(stations: viewModel.searchResults)
            }
        }
    }

    private var favouritesContent: some View {
        VStack(alignment: .leading, spacing: RTSpacing.compact) {
            if viewModel.favouriteRows.isEmpty {
                stateMessageFromLoadingState
            } else {
                ForEach(viewModel.favouriteRows) { favourite in
                    StationPickerFavouriteRow(favourite: favourite) {
                        select(favourite.candidate)
                    }
                }
            }
        }
        .task {
            await viewModel.loadFavourites()
        }
    }

    private var nearestContent: some View {
        VStack(alignment: .leading, spacing: RTSpacing.compact) {
            resultList(stations: viewModel.nearestResults)
        }
        .task {
            await viewModel.loadNearest()
        }
    }

    @ViewBuilder
    private func resultList(stations: [StationSuggestion]) -> some View {
        if viewModel.loadingState == .loading {
            HStack(spacing: RTSpacing.small) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading stations")
                    .font(.subheadline.weight(.semibold))
            }
            .padding(RTSpacing.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.rightTrainPaperCream, in: RoundedRectangle(cornerRadius: RTRadius.card))
        } else if stations.isEmpty {
            stateMessageFromLoadingState
        } else {
            VStack(spacing: 0) {
                ForEach(stations) { station in
                    StationPickerStationRow(station: station) {
                        select(station)
                    }
                    if station.id != stations.last?.id {
                        Divider()
                    }
                }
            }
            .background(Color.rightTrainPaperCream, in: RoundedRectangle(cornerRadius: RTRadius.card))
            .overlay {
                RoundedRectangle(cornerRadius: RTRadius.card)
                    .stroke(Color.rightTrainInkFaint, lineWidth: 1)
            }
        }

        if let validationMessage = viewModel.validationMessage {
            Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.rightTrainDanger)
                .fixedSize(horizontal: false, vertical: true)
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
        }
    }

    private func select(_ station: StationSuggestion) {
        guard viewModel.commit(station) else { return }
        onSelect(station)
        dismiss()
    }
}

struct StationPickerEntryLabel: View {
    var title: String
    var station: StationSuggestion?
    var placeholder: String

    var body: some View {
        HStack(spacing: RTSpacing.compact) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(station?.displayName ?? placeholder)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(station == nil ? Color.rightTrainInk.opacity(RTOpacity.secondary) : Color.rightTrainInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            Spacer(minLength: RTSpacing.small)
            if let station {
                CRSBadge(crs: station.crs)
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.rightTrainInk.opacity(0.42))
        }
        .padding(.horizontal, RTSpacing.compact)
        .padding(.vertical, RTSpacing.small)
        .frame(minHeight: 56)
        .background(Color.rightTrainPaperCream, in: RoundedRectangle(cornerRadius: RTRadius.chip))
        .overlay {
            RoundedRectangle(cornerRadius: RTRadius.chip)
                .stroke(Color.rightTrainInkFaint, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

struct StationPickerEntryRow: View {
    var title: String
    var station: StationSuggestion?
    var placeholder: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            StationPickerEntryLabel(title: title, station: station, placeholder: placeholder)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(station.map { "\($0.displayName), \($0.crs.uppercased())" } ?? "No station selected")
        .accessibilityHint("Opens station picker.")
    }
}

private struct StationPickerSelectedSummary: View {
    var role: StationPickerSelectionRole
    var station: StationSuggestion

    var body: some View {
        HStack(spacing: RTSpacing.compact) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Current \(role.fieldTitle.lowercased())")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(station.displayName)
                    .font(.headline)
            }
            Spacer(minLength: RTSpacing.small)
            CRSBadge(crs: station.crs)
        }
        .padding(RTSpacing.cardPadding)
        .background(Color.rightTrainPaperCream, in: RoundedRectangle(cornerRadius: RTRadius.card))
        .overlay {
            RoundedRectangle(cornerRadius: RTRadius.card)
                .stroke(Color.rightTrainInkFaint, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct StationPickerStationRow: View {
    var station: StationSuggestion
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: RTSpacing.compact) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(station.displayName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.rightTrainInk)
                    if let distance = station.distanceMeters {
                        HStack(spacing: RTSpacing.small) {
                            Text(distanceText(distance))
                        }
                        .font(.caption)
                        .foregroundStyle(Color.rightTrainInk.opacity(RTOpacity.dim))
                    }
                }
                Spacer(minLength: RTSpacing.small)
                CRSBadge(crs: station.crs)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.rightTrainInk.opacity(0.42))
            }
            .padding(RTSpacing.cardPadding)
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
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.rightTrainActionInk)
                    Text(favourite.candidate.displayName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.rightTrainInk)
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
            .padding(RTSpacing.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.rightTrainPaperCream, in: RoundedRectangle(cornerRadius: RTRadius.card))
            .overlay {
                RoundedRectangle(cornerRadius: RTRadius.card)
                    .stroke(favourite.unavailableReason == nil ? Color.rightTrainInkFaint : Color.rightTrainDanger.opacity(0.35), lineWidth: 1)
            }
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
            .font(.caption.weight(.bold))
            .foregroundStyle(Color.rightTrainActionInk)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.rightTrainActionInk.opacity(0.10), in: Capsule())
            .accessibilityLabel("Station code \(crs.uppercased())")
    }
}

private struct StateMessage: View {
    var title: String
    var message: String
    var symbolName: String

    var body: some View {
        VStack(alignment: .leading, spacing: RTSpacing.small) {
            Label(title, systemImage: symbolName)
                .font(.subheadline.weight(.semibold))
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(RTSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.rightTrainPaperCream, in: RoundedRectangle(cornerRadius: RTRadius.card))
        .overlay {
            RoundedRectangle(cornerRadius: RTRadius.card)
                .stroke(Color.rightTrainInkFaint, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
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
