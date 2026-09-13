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
            } footer: {
                Text(intentFooterText)
            }

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

    private var intentFooterText: String {
        if viewModel.canUseMultiLegRouting {
            return viewModel.setupIntentContent.detailText
        }
        return "\(viewModel.setupIntentContent.detailText) Routes with changes aren't available yet."
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
            TextField("Station name or code", text: $query)
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
