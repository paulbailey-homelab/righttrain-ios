import SwiftUI

struct CommuteRoutinesView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppCoordinator.self) private var appCoordinator
    @Environment(ActiveWindowViewModel.self) private var activeWindowViewModel
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(CommuteRoutinesViewModel.self) private var viewModel
    @State private var homeStation: StationSuggestion?
    @State private var workStation: StationSuggestion?
    @State private var editorSheet: RoutineEditorSheet?
    @State private var routineToDelete: CommuteRoutine?

    var body: some View {
        NavigationStack {
            commuteContent
        }
    }

    private var commuteContent: some View {
        scrollContent
            .navigationTitle("Commutes")
            .navigationBarTitleDisplayMode(.large)
            .toolbar { addToolbarItem }
            .refreshable { await refreshRoutines() }
            .task { await loadInitialData() }
            .onChange(of: currentHomeDefault) { _, _ in syncDefaultsFromUser() }
            .onChange(of: currentWorkDefault) { _, _ in syncDefaultsFromUser() }
            .sheet(item: $editorSheet) { sheet in
                RoutineEditorView(sheet: sheet)
            }
            .confirmationDialog("Delete commute?", isPresented: deleteDialogPresented, titleVisibility: .visible) {
                deleteDialogButtons
            }
    }

    private var scrollContent: some View {
        // Saved commutes are what people open this tab for, so they lead;
        // Home & Work is set once and sits below.
        List {
            routinesSection
            defaultsSection
        }
        .listStyle(.insetGrouped)
    }

    @ToolbarContentBuilder
    private var addToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            if let homeStation, let workStation {
                Menu {
                    Button {
                        editorSheet = RoutineEditorSheet(originStation: homeStation, destinationStation: workStation)
                    } label: {
                        Label("Home to Work", systemImage: "arrow.right")
                    }
                    Button {
                        editorSheet = RoutineEditorSheet(originStation: workStation, destinationStation: homeStation)
                    } label: {
                        Label("Work to Home", systemImage: "arrow.left")
                    }
                    Button {
                        editorSheet = RoutineEditorSheet()
                    } label: {
                        Label("Other Route", systemImage: "plus")
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add commute")
            } else {
                Button {
                    editorSheet = RoutineEditorSheet()
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add commute")
            }
        }
    }

    private var deleteDialogButtons: some View {
        Group {
            Button("Delete Commute", role: .destructive) {
                if let routine = routineToDelete {
                    Task { await viewModel.deleteRoutine(id: routine.id) }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var deleteDialogPresented: Binding<Bool> {
        Binding {
            routineToDelete != nil
        } set: { isPresented in
            if !isPresented {
                routineToDelete = nil
            }
        }
    }

    private var defaultsSection: some View {
        Section {
            NavigationLink {
                StationPickerView(
                    context: defaultPickerContext(role: .origin, previousSelection: homeStation, counterpart: workStation),
                    apiClient: appCoordinator.stationPickerAPIClient,
                    favourites: localStationFavourites,
                    locationProvider: SystemStationLocationProvider()
                ) { station in
                    homeStation = station
                    saveDefaults()
                }
            } label: {
                StationFormLabel(title: "Home", station: homeStation, placeholder: "Choose station", showsChevron: false)
            }

            NavigationLink {
                StationPickerView(
                    context: defaultPickerContext(role: .destination, previousSelection: workStation, counterpart: homeStation),
                    apiClient: appCoordinator.stationPickerAPIClient,
                    favourites: localStationFavourites,
                    locationProvider: SystemStationLocationProvider()
                ) { station in
                    workStation = station
                    saveDefaults()
                }
            } label: {
                StationFormLabel(title: "Work", station: workStation, placeholder: "Choose station", showsChevron: false)
            }
        } header: {
            Text("Home & Work")
        } footer: {
            Text("Shown first in the station picker, and in the + menu for new commutes.")
        }
    }

    /// Saves as soon as a station is picked, so there's no separate Save row
    /// that looks like placeholder text while disabled.
    private func saveDefaults() {
        guard hasUnsavedDefaults else { return }
        Task {
            await viewModel.updateStationDefaults(
                homeStation: homeStation,
                workStation: workStation
            )
        }
    }

    private var hasUnsavedDefaults: Bool {
        homeStation?.crs != currentHomeDefault || workStation?.crs != currentWorkDefault
    }

    private var routinesSection: some View {
        Section {
            if viewModel.routines.isEmpty {
                EmptyStateView(
                    title: "No saved commutes",
                    message: "Add a commute to auto-pin journeys on your regular routes.",
                    symbolName: "calendar.badge.clock",
                    tint: .rightTrainActionInk,
                    primaryAction: .init(label: "Add Commute", systemImage: "plus") {
                        editorSheet = RoutineEditorSheet()
                    }
                )
                .listRowInsets(EdgeInsets())
            } else {
                // One TimelineView per row: wrapping the ForEach would collapse
                // every commute into a single list row.
                ForEach(viewModel.routines) { routine in
                    TimelineView(.periodic(from: .now, by: 60)) { timeline in
                        routineRow(routine, now: timeline.date)
                    }
                }
            }
        } header: {
            Text("Saved · \(viewModel.routines.count) of \(authViewModel.user?.entitlements.commuteRoutineLimit ?? 2)")
        } footer: {
            if !viewModel.routines.isEmpty {
                Text("Tap a commute to edit it. Swipe for pause and delete.")
            }
        }
    }

    private func routineRow(_ routine: CommuteRoutine, now: Date) -> some View {
        let isScheduledNow = isCurrentRoutine(routine, now: now)
        let isLive = isLiveActivityRunning(for: routine)
        let statusTone = routineStatusTone(routine, isScheduledNow: isScheduledNow, isLive: isLive)

        return HStack(alignment: .center, spacing: RTSpacing.compact) {
            Button {
                editorSheet = RoutineEditorSheet(routine: routine)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: RTSpacing.small - 2) {
                        Text(routine.name)
                            .font(.headline)
                            .foregroundStyle(.primary)

                        if isLive {
                            Image(systemName: "dot.radiowaves.left.and.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Color.rightTrainActionInk)
                                .symbolEffect(.variableColor.iterative, options: .repeating, isActive: !reduceMotion)
                                .accessibilityLabel("Live now")
                        }
                    }

                    Text("\(viewModel.stationName(for: routine.originCrs)) → \(viewModel.stationName(for: routine.destinationCrs))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    // Window and lead time are editor details; the row keeps
                    // to status and when it runs.
                    Text("\(Text(routineStatusText(routine, isScheduledNow: isScheduledNow, isLive: isLive)).fontWeight(.semibold).foregroundStyle(statusTone.color)) · \(weekdayText(routine.activeWeekdays)) at \(routine.departureTime)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Edits this commute.")

            Button {
                appCoordinator.startJourneyPlan(from: routine)
            } label: {
                Image(systemName: "arrow.up.right.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.rightTrainActionInk)
                    .frame(width: RTSize.tapTarget, height: RTSize.tapTarget)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Plan \(routine.name)")
            .accessibilityHint("Prefills the Plan tab with this commute route and departure window.")
        }
        .opacity(routine.isPaused ? 0.7 : 1)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                routineToDelete = routine
            } label: {
                Label("Delete", systemImage: "trash")
            }

            Button {
                Task { await viewModel.setPaused(routine, paused: !routine.isPaused) }
            } label: {
                Label(routine.isPaused ? "Resume" : "Pause", systemImage: routine.isPaused ? "play.fill" : "pause.fill")
            }
            .tint(Color.rightTrainAmber)
        }
        .contextMenu {
            Button {
                appCoordinator.startJourneyPlan(from: routine)
            } label: {
                Label("Plan Journey", systemImage: "arrow.up.right")
            }
            Button {
                editorSheet = RoutineEditorSheet(routine: routine)
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            Button {
                Task { await viewModel.setPaused(routine, paused: !routine.isPaused) }
            } label: {
                Label(routine.isPaused ? "Resume" : "Pause", systemImage: routine.isPaused ? "play.fill" : "pause.fill")
            }
            Button(role: .destructive) {
                routineToDelete = routine
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .accessibilityAction(named: routine.isPaused ? "Resume \(routine.name)" : "Pause \(routine.name)") {
            Task { await viewModel.setPaused(routine, paused: !routine.isPaused) }
        }
        .accessibilityAction(named: "Delete \(routine.name)") {
            routineToDelete = routine
        }
    }

    private func syncDefaultsFromUser() {
        homeStation = viewModel.stationSuggestion(for: authViewModel.user?.stationDefaults.homeStationCrs)
        workStation = viewModel.stationSuggestion(for: authViewModel.user?.stationDefaults.workStationCrs)
    }

    private func refreshRoutines() async {
        await viewModel.refresh()
    }

    private func loadInitialData() async {
        syncDefaultsFromUser()
        await viewModel.refresh()
        await viewModel.hydrateDefaultStations(
            homeStationCRS: authViewModel.user?.stationDefaults.homeStationCrs,
            workStationCRS: authViewModel.user?.stationDefaults.workStationCrs
        )
        syncDefaultsFromUser()
    }

    private var currentHomeDefault: String? {
        authViewModel.user?.stationDefaults.homeStationCrs
    }

    private var currentWorkDefault: String? {
        authViewModel.user?.stationDefaults.workStationCrs
    }

    private var localStationFavourites: [StationFavourite] {
        StationFavoritesProvider.favourites(
            homeStationCRS: homeStation?.crs ?? currentHomeDefault,
            workStationCRS: workStation?.crs ?? currentWorkDefault,
            routines: viewModel.routines,
            stationResolver: { crs in viewModel.stationSuggestion(for: crs) }
        )
    }

    private func defaultPickerContext(
        role: StationPickerSelectionRole,
        previousSelection: StationSuggestion?,
        counterpart: StationSuggestion?
    ) -> StationPickerContext {
        StationPickerContext(
            selectionRole: role,
            routeMode: .direct,
            selectedCounterpartCRS: counterpart?.crs,
            departureStart: nil,
            windowMinutes: 180,
            sourceSurface: .commuteDefaults,
            previousSelection: previousSelection
        )
    }

    private func weekdayText(_ weekdays: [Int]) -> String {
        switch Set(weekdays) {
        case Set(1...5):
            return "Weekdays"
        case Set(6...7):
            return "Weekends"
        case Set(1...7):
            return "Every day"
        default:
            let labels = [1: "Mon", 2: "Tue", 3: "Wed", 4: "Thu", 5: "Fri", 6: "Sat", 7: "Sun"]
            return weekdays.sorted().compactMap { labels[$0] }.joined(separator: ", ")
        }
    }

    private func routineStatusText(_ routine: CommuteRoutine, isScheduledNow: Bool, isLive: Bool) -> String {
        if isLive {
            return "Live now"
        }
        if routine.isPaused {
            return "Paused"
        }
        if isScheduledNow {
            return "Auto-pin due"
        }
        return routine.autoArmEnabled ? "Auto-pin" : "Manual"
    }

    private func routineStatusTone(_ routine: CommuteRoutine, isScheduledNow: Bool, isLive: Bool) -> StatusPill.Tone {
        if isLive || isScheduledNow {
            return .accent
        }
        return routine.isPaused ? .amber : .green
    }

    private func isLiveActivityRunning(for routine: CommuteRoutine) -> Bool {
        let origin = normalizedCRS(routine.originCrs)
        let destination = normalizedCRS(routine.destinationCrs)

        if let window = activeWindowViewModel.activeWindow,
           isActiveSubscription(status: window.status, deletedAt: window.deletedAt),
           normalizedCRS(window.originCrs) == origin,
           normalizedCRS(window.destinationCrs) == destination {
            return true
        }

        if let itinerary = activeWindowViewModel.activeItinerary,
           isActiveSubscription(status: itinerary.status, deletedAt: itinerary.deletedAt),
           normalizedCRS(itinerary.originCrs) == origin,
           normalizedCRS(itinerary.destinationCrs) == destination {
            return true
        }

        return false
    }

    private func isCurrentRoutine(_ routine: CommuteRoutine, now: Date) -> Bool {
        guard !routine.isPaused,
              routine.activeWeekdays.contains(appWeekday(for: now)),
              let departure = clockDate(routine.departureTime, on: now) else {
            return false
        }

        let leadMinutes = routine.autoArmEnabled ? routine.autoArmLeadMinutes : 0
        let startsAt = departure.addingTimeInterval(TimeInterval(-max(leadMinutes, 0)) * 60)
        let endsAt = departure.addingTimeInterval(TimeInterval(max(routine.windowMinutes, 0)) * 60)
        return startsAt <= now && now <= endsAt
    }

    private func appWeekday(for date: Date) -> Int {
        let calendarWeekday = Calendar.current.component(.weekday, from: date)
        return calendarWeekday == 1 ? 7 : calendarWeekday - 1
    }

    private func clockDate(_ value: String, on date: Date) -> Date? {
        let parts = value.split(separator: ":").compactMap { Int($0) }
        guard let hour = parts.first else { return nil }

        var components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        components.hour = hour
        components.minute = parts.dropFirst().first ?? 0
        return Calendar.current.date(from: components)
    }

    private func normalizedCRS(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private func isActiveSubscription(status: String, deletedAt: String?) -> Bool {
        status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "active" && deletedAt == nil
    }
}

struct RoutineEditorSheet: Identifiable {
    var id = UUID()
    var routine: CommuteRoutine?
    var originStation: StationSuggestion?
    var destinationStation: StationSuggestion?
}

private struct RoutineEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppCoordinator.self) private var appCoordinator
    @Environment(CommuteRoutinesViewModel.self) private var viewModel
    var sheet: RoutineEditorSheet

    @State private var name = ""
    @State private var origin: StationSuggestion?
    @State private var destination: StationSuggestion?
    @State private var departureTime = Date()
    @State private var windowMinutes = 120
    @State private var activeWeekdays = Set([1, 2, 3, 4, 5])
    @State private var autoArmEnabled = true
    @State private var autoArmLeadMinutes = 30
    @State private var notificationsEnabled = true
    @State private var status = "active"

    var body: some View {
        NavigationStack {
            Form {
                Section("Route") {
                    TextField("Name", text: $name)
                    NavigationLink {
                        StationPickerView(
                            context: routinePickerContext(role: .origin, previousSelection: origin, counterpart: destination),
                            apiClient: appCoordinator.stationPickerAPIClient,
                            favourites: appCoordinator.stationFavourites(),
                            locationProvider: SystemStationLocationProvider()
                        ) { station in
                            origin = station
                        }
                    } label: {
                        StationFormLabel(title: "From", station: origin, placeholder: "Choose origin", showsChevron: false)
                    }

                    NavigationLink {
                        StationPickerView(
                            context: routinePickerContext(role: .destination, previousSelection: destination, counterpart: origin),
                            apiClient: appCoordinator.stationPickerAPIClient,
                            favourites: appCoordinator.stationFavourites(),
                            locationProvider: SystemStationLocationProvider()
                        ) { station in
                            destination = station
                        }
                    } label: {
                        StationFormLabel(title: "To", station: destination, placeholder: "Choose destination", showsChevron: false)
                    }
                }

                Section("Schedule") {
                    DatePicker("Departure", selection: $departureTime, displayedComponents: [.hourAndMinute])
                    Stepper(value: $windowMinutes, in: 30...360, step: 30) {
                        LabeledContent("Window", value: "\(windowMinutes)m")
                    }
                    weekdayPicker
                }

                Section("Auto-pin") {
                    Toggle("Auto-pin", isOn: $autoArmEnabled)
                    Stepper(value: $autoArmLeadMinutes, in: 0...180, step: 15) {
                        LabeledContent("Lead Time", value: "\(autoArmLeadMinutes)m")
                    }
                    Toggle("Notifications", isOn: $notificationsEnabled)
                }
            }
            .navigationTitle(sheet.routine == nil ? "New Commute" : "Edit Commute")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await save()
                            dismiss()
                        }
                    }
                    .disabled(origin == nil || destination == nil || activeWeekdays.isEmpty)
                }
            }
            .onAppear(perform: loadInitialState)
        }
    }

    private var weekdayPicker: some View {
        HStack {
            ForEach(dayOptions, id: \.value) { day in
                if day.value > 1 { Spacer(minLength: 0) }
                Button {
                    if activeWeekdays.contains(day.value) {
                        activeWeekdays.remove(day.value)
                    } else {
                        activeWeekdays.insert(day.value)
                    }
                } label: {
                    Text(day.label)
                        .font(.caption.weight(.semibold))
                        .frame(width: RTSize.avatarSmall, height: RTSize.avatarSmall)
                        .background(activeWeekdays.contains(day.value) ? Color.rightTrainActionInk : Color.rightTrainInsetFill, in: Circle())
                        .foregroundStyle(activeWeekdays.contains(day.value) ? Color.rightTrainOnAccent : Color.primary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    private func loadInitialState() {
        if let routine = sheet.routine {
            name = routine.name
            origin = station(crs: routine.originCrs)
            destination = station(crs: routine.destinationCrs)
            departureTime = date(fromClock: routine.departureTime)
            windowMinutes = routine.windowMinutes
            activeWeekdays = Set(routine.activeWeekdays)
            autoArmEnabled = routine.autoArmEnabled
            autoArmLeadMinutes = routine.autoArmLeadMinutes
            notificationsEnabled = routine.notificationsEnabled
            status = routine.status
        } else {
            origin = sheet.originStation
            destination = sheet.destinationStation
        }
    }

    private func save() async {
        guard let origin, let destination else { return }
        let input = CommuteRoutineMutationRequest(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            status: status,
            originCrs: origin.crs,
            destinationCrs: destination.crs,
            departureTime: clockString(from: departureTime),
            windowMinutes: windowMinutes,
            activeWeekdays: activeWeekdays.sorted(),
            autoArmEnabled: autoArmEnabled,
            autoArmLeadMinutes: autoArmLeadMinutes,
            notificationsEnabled: notificationsEnabled
        )
        if let routine = sheet.routine {
            await viewModel.updateRoutine(id: routine.id, input: input)
        } else {
            await viewModel.createRoutine(input)
        }
    }

    private func station(crs: String?) -> StationSuggestion? {
        viewModel.stationSuggestion(for: crs)
    }

    private func routinePickerContext(
        role: StationPickerSelectionRole,
        previousSelection: StationSuggestion?,
        counterpart: StationSuggestion?
    ) -> StationPickerContext {
        StationPickerContext(
            selectionRole: role,
            routeMode: .direct,
            selectedCounterpartCRS: counterpart?.crs,
            departureStart: departureTime,
            windowMinutes: windowMinutes,
            sourceSurface: .routineEditor,
            previousSelection: previousSelection
        )
    }

    private func date(fromClock value: String) -> Date {
        let parts = value.split(separator: ":").compactMap { Int($0) }
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = parts.first ?? 8
        components.minute = parts.dropFirst().first ?? 0
        return Calendar.current.date(from: components) ?? Date()
    }

    private func clockString(from date: Date) -> String {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
    }

    private var dayOptions: [(value: Int, label: String)] {
        [(1, "M"), (2, "T"), (3, "W"), (4, "T"), (5, "F"), (6, "S"), (7, "S")]
    }
}
