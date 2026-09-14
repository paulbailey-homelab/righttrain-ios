import Foundation
import SwiftUI

struct WindowSetupView: View {
    @Environment(WindowSetupViewModel.self) private var viewModel
    var onStationFieldEditingBegan: (ContentScrollTarget) -> Void = { _ in }
    var openStationPicker: (StationPickerSelectionRole) -> Void = { _ in }
    var showSearchResults: () -> Void = {}

    /// 30 min to 6 h in 30 min steps — the range the backend accepts.
    private static let windowOptions = Array(stride(from: 30, through: 360, by: 30))

    var body: some View {
        @Bindable var viewModel = viewModel
        return Form {
            Section {
                Picker("Trip type", selection: intentSelection) {
                    ForEach(availableIntents) { intent in
                        Text(intent.shortTitle).tag(intent)
                    }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .accessibilityHint(viewModel.setupIntentContent.detailText)
            }
            .listSectionSpacing(.compact)

            Section {
                StationFormRow(title: "From", station: viewModel.origin, placeholder: "Choose origin") {
                    onStationFieldEditingBegan(.originStationField)
                    openStationPicker(.origin)
                }
                .id(ContentScrollTarget.originStationField)

                StationFormRow(title: "To", station: viewModel.destination, placeholder: "Choose destination") {
                    onStationFieldEditingBegan(.destinationStationField)
                    openStationPicker(.destination)
                }
                .id(ContentScrollTarget.destinationStationField)
            } footer: {
                if viewModel.canSwapStations {
                    Button {
                        viewModel.swapStations()
                    } label: {
                        Label("Swap From and To", systemImage: "arrow.up.arrow.down")
                            .font(.footnote.weight(.semibold))
                    }
                    .buttonStyle(.borderless)
                    .sensoryFeedback(.selection, trigger: viewModel.origin?.crs)
                }
            }

            Section {
                DatePicker("Depart after", selection: $viewModel.departureStart, in: Date()..., displayedComponents: [.date, .hourAndMinute])

                Picker("Departure window", selection: windowMinutesSelection) {
                    ForEach(Self.windowOptions, id: \.self) { minutes in
                        Text(windowRangeText(minutes)).tag(minutes)
                    }
                }
                .pickerStyle(.menu)
                .sensoryFeedback(.selection, trigger: viewModel.windowMinutes)
            } footer: {
                Text("RightTrain compares trains leaving within this window.")
            }
        }
        .contentMargins(.top, RTSpacing.small, for: .scrollContent)
        .safeAreaBar(edge: .bottom) {
            searchJourneysButton
        }
        .tint(Color.rightTrainActionInk)
        .task {
            await viewModel.loadAppCapabilities()
        }
    }

    private var availableIntents: [JourneySetupIntent] {
        JourneySetupIntent.allCases.filter { intent in
            intent != .connectionSensitive
                || viewModel.canUseMultiLegRouting
                || viewModel.activeSetupIntent == intent
        }
    }

    private var intentSelection: Binding<JourneySetupIntent> {
        Binding {
            viewModel.activeSetupIntent
        } set: { intent in
            viewModel.selectSetupIntent(intent)
        }
    }

    private var windowMinutesSelection: Binding<Int> {
        Binding {
            viewModel.windowMinutes
        } set: { newValue in
            let clamped = WindowSetupViewModel.normalizedWindowMinutes(newValue)
            guard viewModel.windowMinutes != clamped else { return }
            viewModel.windowMinutes = clamped
        }
    }

    private var searchJourneysButton: some View {
        FloatingPrimaryAction {
            Task { await searchJourneys() }
        } label: {
            Text(viewModel.setupIntentContent.primaryActionText)
        }
        .accessibilityHint("Searches journeys in the selected departure range.")
    }

    private func searchJourneys() async {
        guard await viewModel.loadRecommendations() else {
            return
        }
        showSearchResults()
    }

    private func windowRangeText(_ minutes: Int) -> String {
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if hours > 0 && remainingMinutes > 0 {
            return "\(hours)h \(remainingMinutes)m"
        }
        if hours > 0 {
            return "\(hours)h"
        }
        return "\(remainingMinutes)m"
    }
}

/// A form row that opens the station picker: label on the left, the chosen
/// station (or placeholder) and its CRS code on the right, with a chevron —
/// the native Settings-style navigation row.
struct StationFormRow: View {
    var title: String
    var station: StationSuggestion?
    var placeholder: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            StationFormLabel(title: title, station: station, placeholder: placeholder)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens station picker.")
    }
}

/// Content of a station form row. Pass `showsChevron: false` inside a
/// `NavigationLink`, which draws its own disclosure indicator.
struct StationFormLabel: View {
    var title: String
    var station: StationSuggestion?
    var placeholder: String
    var showsChevron = true

    var body: some View {
        HStack(spacing: RTSpacing.small) {
            Text(title)
                .foregroundStyle(.primary)
                .frame(minWidth: 44, alignment: .leading)
            Spacer(minLength: RTSpacing.small)
            if let station {
                Text(station.displayName)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                Text(station.crs.uppercased())
                    .font(.footnote.weight(.semibold))
                    .monospaced()
                    .foregroundStyle(.secondary)
            } else {
                Text(placeholder)
                    .foregroundStyle(.secondary)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(title)
        .accessibilityValue(station.map { "\($0.displayName), \($0.crs.uppercased())" } ?? "No station selected")
    }
}
