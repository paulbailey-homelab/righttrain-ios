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
        .environment(\.colorScheme, .light)
    }

    private var commuteContent: some View {
        scrollContent
            .background(Color.rightTrainSurfaceCream.ignoresSafeArea())
            .lightSurfaceForeground()
            .toolbarColorScheme(.light, for: .navigationBar)
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
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                defaultsSection
                routinesSection
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, RTSpacing.pageHorizontal)
            .padding(.vertical, RTSpacing.pageVertical)
        }
        .safeAreaPadding(.bottom, RTSpacing.bottomSafeArea)
    }

    @ToolbarContentBuilder
    private var addToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                editorSheet = RoutineEditorSheet()
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("Add commute")
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
        VStack(alignment: .leading, spacing: RTSpacing.compact) {
            Text("HOME & WORK")
                .font(RTFont.eyebrow)
                .tracking(2)
                .foregroundStyle(Color.rightTrainInk.opacity(0.55))

            VStack(spacing: RTSpacing.listItem) {
                StationSearchField(title: "Home", selection: $homeStation) { query in
                    try await viewModel.searchStations(query: query)
                }
                StationSearchField(title: "Work", selection: $workStation) { query in
                    try await viewModel.searchStations(query: query)
                }
            }

            VStack(spacing: RTSpacing.listItem) {
                saveDefaultsButton
                HStack(spacing: RTSpacing.listItem) {
                    homeToWorkButton
                    workToHomeButton
                }
            }
        }
        .padding(RTSpacing.cardPadding)
        .background(Color.rightTrainPaperCream, in: RoundedRectangle(cornerRadius: RTRadius.card))
        .lightSurfaceForeground()
        .overlay {
            RoundedRectangle(cornerRadius: RTRadius.card)
                .stroke(Color.rightTrainInkFaint, lineWidth: 1)
        }
    }

    private var routinesSection: some View {
        VStack(alignment: .leading, spacing: RTSpacing.compact) {
            Text("SAVED · \(viewModel.routines.count) OF \(authViewModel.user?.entitlements.commuteRoutineLimit ?? 2)")
                .font(RTFont.eyebrow)
                .tracking(2)
                .foregroundStyle(Color.rightTrainInk.opacity(0.55))

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
            } else {
                TimelineView(.periodic(from: .now, by: 60)) { timeline in
                    ForEach(viewModel.routines) { routine in
                        routineRow(routine, now: timeline.date)
                    }
                }
            }
        }
    }

    private var saveDefaultsButton: some View {
        Button {
            Task {
                await viewModel.updateStationDefaults(
                    homeStation: homeStation,
                    workStation: workStation
                )
            }
        } label: {
            Label("Save", systemImage: "checkmark")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    private var homeToWorkButton: some View {
        Button {
            editorSheet = RoutineEditorSheet(
                originStation: homeStation,
                destinationStation: workStation
            )
        } label: {
            Label("Home to Work", systemImage: "arrow.right")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .disabled(homeStation == nil || workStation == nil)
    }

    private var workToHomeButton: some View {
        Button {
            editorSheet = RoutineEditorSheet(
                originStation: workStation,
                destinationStation: homeStation
            )
        } label: {
            Label("Work to Home", systemImage: "arrow.left")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .disabled(homeStation == nil || workStation == nil)
    }

    private func routineRow(_ routine: CommuteRoutine, now: Date) -> some View {
        let isScheduledNow = isCurrentRoutine(routine, now: now)
        let isLive = isLiveActivityRunning(for: routine)
        let stripColor = routineStripColor(isScheduledNow: isScheduledNow, isLive: isLive, isPaused: routine.isPaused)

        return VStack(alignment: .leading, spacing: RTSpacing.compact) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: RTSpacing.small / 2) {
                    HStack(spacing: RTSpacing.small - 2) {
                        Text(routine.name)
                            .font(.headline)

                        if isLive {
                            Image(systemName: "dot.radiowaves.left.and.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Color.rightTrainActionInk)
                                .symbolEffect(.variableColor.iterative, options: .repeating, isActive: !reduceMotion)
                                .accessibilityLabel("Live now")
                        }
                    }

                    Text("\(viewModel.stationName(for: routine.originCrs)) to \(viewModel.stationName(for: routine.destinationCrs)) at \(routine.departureTime)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(routineAutoPinSummary(routine))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatusPill(
                    text: routineStatusText(routine, isScheduledNow: isScheduledNow, isLive: isLive),
                    tone: routineStatusTone(routine, isScheduledNow: isScheduledNow, isLive: isLive)
                )
            }

            HStack(spacing: RTSpacing.listItem) {
                Button {
                    appCoordinator.startJourneyPlan(from: routine)
                } label: {
                    Label("Plan", systemImage: "arrow.up.right")
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.rightTrainActionInk)
                .accessibilityHint("Prefills the Plan tab with this commute route and departure window.")

                Button {
                    Task { await viewModel.setPaused(routine, paused: !routine.isPaused) }
                } label: {
                    Label(routine.isPaused ? "Resume" : "Pause", systemImage: routine.isPaused ? "play.fill" : "pause.fill")
                }
                .buttonStyle(.bordered)

                Button {
                    editorSheet = RoutineEditorSheet(routine: routine)
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .buttonStyle(.bordered)

                Spacer()

                Button(role: .destructive) {
                    routineToDelete = routine
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Delete \(routine.name)")
            }
        }
        .padding(RTSpacing.cardPadding)
        .padding(.leading, 4)
        .background {
            HStack(spacing: 0) {
                Rectangle()
                    .fill(stripColor)
                    .frame(width: 4)
                Spacer()
            }
        }
        .background(Color.rightTrainPaperCream)
        .lightSurfaceForeground()
        .overlay {
            RoundedRectangle(cornerRadius: RTRadius.card)
                .stroke(Color.rightTrainInkFaint, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: RTRadius.card))
        .accessibilityElement(children: .combine)
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

    private func weekdayText(_ weekdays: [Int]) -> String {
        let labels = [1: "Mon", 2: "Tue", 3: "Wed", 4: "Thu", 5: "Fri", 6: "Sat", 7: "Sun"]
        return weekdays.compactMap { labels[$0] }.joined(separator: ", ")
    }

    private func routineAutoPinSummary(_ routine: CommuteRoutine) -> String {
        let autoPin = routine.autoArmEnabled
            ? "Auto-pin \(routine.autoArmLeadMinutes)m before"
            : "Manual pin"
        return "\(weekdayText(routine.activeWeekdays)) • \(routine.windowMinutes)m window • \(autoPin)"
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
        return routine.autoArmEnabled ? "Auto-pin on" : "Manual"
    }

    private func routineStatusTone(_ routine: CommuteRoutine, isScheduledNow: Bool, isLive: Bool) -> StatusPill.Tone {
        if isLive || isScheduledNow {
            return .accent
        }
        return routine.isPaused ? .amber : .green
    }

    /// 4pt left-edge strip colour for a commute card.
    private func routineStripColor(isScheduledNow: Bool, isLive: Bool, isPaused: Bool) -> Color {
        if isLive || isScheduledNow { return .rightTrainGoodBg }
        if isPaused { return .rightTrainWarnBg }
        return .rightTrainInkFaint
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
                    StationSearchField(title: "From", selection: $origin) { query in
                        try await viewModel.searchStations(query: query)
                    }
                    StationSearchField(title: "To", selection: $destination) { query in
                        try await viewModel.searchStations(query: query)
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
                Button {
                    if activeWeekdays.contains(day.value) {
                        activeWeekdays.remove(day.value)
                    } else {
                        activeWeekdays.insert(day.value)
                    }
                } label: {
                    Text(day.label)
                        .font(.caption.weight(.semibold))
                        .frame(width: 32, height: 32)
                        .background(activeWeekdays.contains(day.value) ? Color.rightTrainActionInk : Color.rightTrainBackground, in: Circle())
                        .foregroundStyle(activeWeekdays.contains(day.value) ? Color.white : Color.primary)
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
