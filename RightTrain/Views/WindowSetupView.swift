import Foundation
import SwiftUI

struct WindowSetupView: View {
    @Environment(WindowSetupViewModel.self) private var viewModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var onStationFieldEditingBegan: (ContentScrollTarget) -> Void = { _ in }
    var openStationPicker: (StationPickerSelectionRole) -> Void = { _ in }
    var showSearchResults: () -> Void = {}

    var body: some View {
        @Bindable var viewModel = viewModel
        return VStack(alignment: .leading, spacing: RTSpacing.compact) {
            setupHeader
            JourneySetupIntentPicker(
                selection: viewModel.activeSetupIntent,
                isEnabled: { intent in
                    intent != .connectionSensitive || viewModel.canUseMultiLegRouting
                },
                onSelect: { viewModel.selectSetupIntent($0) }
            )
            routeModeSummary

            VStack(alignment: .leading, spacing: RTSpacing.compact) {
                StationPickerEntryRow(
                    title: "From",
                    station: viewModel.origin,
                    placeholder: "Choose origin"
                ) {
                    onStationFieldEditingBegan(.originStationField)
                    openStationPicker(.origin)
                }
                .id(ContentScrollTarget.originStationField)
                .frame(maxWidth: .infinity)

                StationPickerEntryRow(
                    title: "To",
                    station: viewModel.destination,
                    placeholder: "Choose destination"
                ) {
                    onStationFieldEditingBegan(.destinationStationField)
                    openStationPicker(.destination)
                }
                .id(ContentScrollTarget.destinationStationField)
                .frame(maxWidth: .infinity)
            }

            VStack(alignment: .leading, spacing: RTSpacing.listItem) {
                DatePicker("Travel from", selection: $viewModel.departureStart, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.compact)

                rangeHeader

                Slider(value: windowMinutesSliderValue, in: 30...360, step: 30) {
                    Text("Departure window")
                } minimumValueLabel: {
                    Text("30m")
                } maximumValueLabel: {
                    Text("6h")
                }
                .accessibilityValue(windowRangeText(viewModel.windowMinutes))
            }
            .sensoryFeedback(.selection, trigger: viewModel.windowMinutes)

            searchJourneysButton
                .controlSize(.large)
        }
        .rtCard()
        .lightSurfaceForeground()
        .tint(Color.rightTrainActionInk)
        .task {
            await viewModel.loadAppCapabilities()
        }
    }

    private var setupHeader: some View {
        let intent = viewModel.setupIntentContent
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                StatusPill(text: intent.title, tone: .accent)
                Spacer()
                Label("Manual setup", systemImage: "slider.horizontal.3")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.rightTrainInk.opacity(RTOpacity.dim))
            }

            Text(intent.detailText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var routeModeSummary: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Route type")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: RTSpacing.small)
            Text(viewModel.routeModeTitle(viewModel.searchMode))
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.rightTrainActionInk)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var rangeHeader: some View {
        if dynamicTypeSize.prefersExpandedLayout {
            VStack(alignment: .leading, spacing: 4) {
                Text("Departure window")
                rangeReadout
            }
        } else {
            HStack(alignment: .firstTextBaseline) {
                Text("Departure window")
                Spacer(minLength: 12)
                rangeReadout
            }
        }
    }

    private var rangeReadout: some View {
        Text(windowRangeText(viewModel.windowMinutes))
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.rightTrainActionInk)
            .contentTransition(.numericText())
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityHidden(true)
    }

    private var windowMinutesSliderValue: Binding<Double> {
        Binding {
            Double(viewModel.windowMinutes)
        } set: { newValue in
            let snapped = Int((newValue / 30).rounded()) * 30
            let clamped = WindowSetupViewModel.normalizedWindowMinutes(snapped)
            guard viewModel.windowMinutes != clamped else { return }
            viewModel.windowMinutes = clamped
        }
    }

    private var searchJourneysButton: some View {
        Button {
            Task { await searchJourneys() }
        } label: {
            HStack {
                Text(viewModel.setupIntentContent.primaryActionText)
                Image(systemName: "arrow.right")
            }
        }
        .buttonStyle(.rtPrimary)
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

private struct JourneySetupIntentPicker: View {
    var selection: JourneySetupIntent
    var isEnabled: (JourneySetupIntent) -> Bool
    var onSelect: (JourneySetupIntent) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(JourneySetupIntent.allCases) { intent in
                Button {
                    onSelect(intent)
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: symbol(for: intent))
                            .font(.caption.weight(.bold))
                        Text(intent.shortTitle)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.84)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(foregroundStyle(for: intent))
                .background(backgroundStyle(for: intent), in: RoundedRectangle(cornerRadius: RTRadius.chip))
                .disabled(!isEnabled(intent))
                .accessibilityLabel(intent.title)
                .accessibilityValue(selection == intent ? "Selected" : "")
                .accessibilityHint(isEnabled(intent) ? intent.detailText : "Routes with changes are not available yet.")
            }
        }
        .padding(4)
        .background(Color.rightTrainSurfaceCream, in: RoundedRectangle(cornerRadius: RTRadius.chip + 4))
        .overlay {
            RoundedRectangle(cornerRadius: RTRadius.chip + 4)
                .stroke(Color.rightTrainInkFaint, lineWidth: 1)
        }
    }

    private func symbol(for intent: JourneySetupIntent) -> String {
        switch intent {
        case .routineCommute:
            return "calendar.badge.clock"
        case .oneOffDirect:
            return "arrow.right"
        case .connectionSensitive:
            return "arrow.triangle.branch"
        }
    }

    private func foregroundStyle(for intent: JourneySetupIntent) -> Color {
        if selection == intent {
            return Color.rightTrainSurfaceCream
        }
        if isEnabled(intent) {
            return Color.rightTrainInk
        }
        return Color.rightTrainInk.opacity(0.36)
    }

    private func backgroundStyle(for intent: JourneySetupIntent) -> Color {
        selection == intent ? Color.rightTrainInk : Color.clear
    }
}

private struct RouteModePicker: View {
    var selection: JourneySearchMode
    var titleForMode: (JourneySearchMode) -> String
    var isEnabled: (JourneySearchMode) -> Bool
    var onSelect: (JourneySearchMode) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Route type")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 4) {
                ForEach(JourneySearchMode.allCases) { mode in
                    Button {
                        onSelect(mode)
                    } label: {
                        Text(titleForMode(mode))
                            .font(isEnabled(mode) ? .subheadline.weight(.semibold) : .caption.weight(.semibold))
                            .lineLimit(isEnabled(mode) ? 1 : 2)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .padding(.horizontal, 8)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(foregroundStyle(for: mode))
                    .background(backgroundStyle(for: mode), in: RoundedRectangle(cornerRadius: RTRadius.chip))
                    .disabled(!isEnabled(mode))
                    .allowsHitTesting(isEnabled(mode))
                    .accessibilityValue(selection == mode ? "Selected" : "")
                    .accessibilityHint(isEnabled(mode) ? "" : "Routes with changes are not available yet.")
                }
            }
            .padding(4)
            .background(Color.rightTrainSurfaceCream, in: RoundedRectangle(cornerRadius: RTRadius.chip + 4))
            .overlay {
                RoundedRectangle(cornerRadius: RTRadius.chip + 4)
                    .stroke(Color.rightTrainInkFaint, lineWidth: 1)
            }

            if !isEnabled(.anyRoute) {
                Text("Routes with changes are not available yet.")
                    .font(.caption2)
                    .foregroundStyle(Color.rightTrainInk.opacity(RTOpacity.secondary))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityHint("Choose whether to search direct trains only or all routes including changes.")
    }

    private func foregroundStyle(for mode: JourneySearchMode) -> Color {
        if selection == mode {
            return Color.rightTrainSurfaceCream
        }
        if isEnabled(mode) {
            return Color.rightTrainInk
        }
        return Color.rightTrainInk.opacity(0.36)
    }

    private func backgroundStyle(for mode: JourneySearchMode) -> Color {
        if selection == mode {
            return Color.rightTrainInk
        }
        return Color.clear
    }
}

struct StationSearchField: View {
    var title: String
    @Binding var selection: StationSuggestion?
    var minQueryLength: Int = 2
    var onBeginEditing: () -> Void = {}
    var search: (String) async throws -> [StationSuggestion]

    @State private var query = ""
    @State private var suggestions: [StationSuggestion] = []
    @State private var isSearching = false
    @State private var isEditing = true
    @State private var editingFallback: StationSuggestion?
    @State private var errorMessage: String?
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if let selection, !isEditing {
                selectedStationView(selection)
            } else {
                editingField
            }

            if isSearching {
                ProgressView()
                    .controlSize(.small)
            }

            if isEditing, isFocused, let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(Color.rightTrainDanger)
            }

            if isEditing, isFocused, !suggestions.isEmpty {
                VStack(spacing: 0) {
                    ForEach(suggestions) { station in
                        Button {
                            choose(station)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(station.displayName)
                                        .foregroundStyle(.primary)
                                    Text(station.crs.uppercased())
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(Color.rightTrainInk.opacity(RTOpacity.secondary))
                                }
                                Spacer()
                            }
                            .contentShape(Rectangle())
                            .padding(.vertical, RTSpacing.listItem)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(station.displayName)
                        .accessibilityHint("Selects this \(title.lowercased()) station.")

                        if station.id != suggestions.last?.id {
                            Divider()
                        }
                    }
                }
                .padding(.horizontal, RTSpacing.compact)
                .background(Color.rightTrainPaperCream, in: RoundedRectangle(cornerRadius: RTRadius.chip))
                .lightSurfaceForeground()
            }
        }
        .onAppear {
            guard let selection else { return }
            query = selection.displayName
            isEditing = false
        }
        .onChange(of: selection) { _, newValue in
            if let newValue {
                query = newValue.displayName
                suggestions = []
                errorMessage = nil
                editingFallback = nil
                isEditing = false
                isFocused = false
            } else if !isEditing {
                query = ""
                suggestions = []
                editingFallback = nil
                isEditing = true
            }
        }
        .onChange(of: isFocused) { _, focused in
            if focused {
                onBeginEditing()
            } else {
                suggestions = []
                errorMessage = nil
            }
        }
        .task(id: suggestionTaskKey) {
            await loadSuggestions()
        }
    }

    private var suggestionTaskKey: String {
        [
            isEditing ? "editing" : "selected",
            isFocused ? "focused" : "unfocused",
            query,
            selection?.id ?? "none"
        ].joined(separator: "|")
    }

    private var editingField: some View {
        HStack(spacing: 8) {
            TextField("Station or CRS", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($isFocused)
                .padding(.horizontal, RTSpacing.compact)
                .frame(minHeight: 52)
                .background(Color.rightTrainPaperCream, in: RoundedRectangle(cornerRadius: RTRadius.chip))
                .lightSurfaceForeground()
                .overlay {
                    RoundedRectangle(cornerRadius: RTRadius.chip)
                        .stroke(isFocused ? Color.rightTrainInk : Color.rightTrainInkFaint, lineWidth: isFocused ? 1.5 : 1)
                }
                .onTapGesture {
                    beginEditing()
                }
                .accessibilityLabel("\(title) station")
                .accessibilityValue(query.isEmpty ? "No station entered" : query)

            if editingFallback != nil {
                Button("Cancel") {
                    cancelEditing()
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
                .accessibilityLabel("Cancel editing \(title.lowercased()) station")
            }
        }
    }

    private func selectedStationView(_ station: StationSuggestion) -> some View {
        HStack(spacing: 12) {
            Text(station.displayName)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Spacer(minLength: 8)

            Text(station.crs.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.rightTrainActionInk)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.rightTrainActionInk.opacity(0.10), in: Capsule())

            Button {
                beginEditing()
            } label: {
                Image(systemName: "pencil")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(width: RTSize.iconButton - 2, height: RTSize.iconButton - 2)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit \(title) station")
            .accessibilityValue(station.displayName)
        }
        .padding(.horizontal, RTSpacing.compact)
        .padding(.vertical, RTSpacing.small)
        .frame(minHeight: 52)
        .background(Color.rightTrainPaperCream, in: RoundedRectangle(cornerRadius: RTRadius.chip))
        .lightSurfaceForeground()
        .overlay {
            RoundedRectangle(cornerRadius: RTRadius.chip)
                .stroke(Color.rightTrainInk, lineWidth: 1.5)
        }
    }

    private func beginEditing() {
        if let selection {
            editingFallback = selection
            isEditing = true
            self.selection = nil
            query = ""
        } else {
            isEditing = true
        }
        suggestions = []
        errorMessage = nil
        isFocused = true
        onBeginEditing()
    }

    private func cancelEditing() {
        if let editingFallback {
            selection = editingFallback
            query = editingFallback.displayName
            isEditing = false
        }
        self.editingFallback = nil
        suggestions = []
        errorMessage = nil
        isFocused = false
    }

    private func choose(_ station: StationSuggestion) {
        selection = station
        query = station.displayName
        suggestions = []
        errorMessage = nil
        editingFallback = nil
        isEditing = false
        isFocused = false
    }

    private func loadSuggestions() async {
        if let selection, query.isEmpty {
            query = selection.displayName
            isEditing = false
            suggestions = []
            errorMessage = nil
            return
        }

        guard isEditing else {
            suggestions = []
            errorMessage = nil
            return
        }

        guard isFocused else {
            suggestions = []
            errorMessage = nil
            return
        }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == selection?.displayName {
            suggestions = []
            errorMessage = nil
            return
        }
        selection = nil
        guard trimmed.count >= minQueryLength else {
            suggestions = []
            errorMessage = nil
            return
        }

        errorMessage = nil

        do {
            try await Task.sleep(for: .milliseconds(250))
            try Task.checkCancellation()
            isSearching = true
            defer { isSearching = false }

            let results = try await search(trimmed)
            try Task.checkCancellation()
            guard isEditing, selection == nil else { return }
            suggestions = results
        } catch is CancellationError {
        } catch let urlError as URLError where urlError.code == .cancelled {
        } catch {
            guard isEditing, selection == nil, !Task.isCancelled else { return }
            errorMessage = "Station search is unavailable."
            suggestions = []
        }
    }
}
