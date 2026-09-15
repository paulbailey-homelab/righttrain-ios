import SwiftUI
import UIKit

enum ContentScrollTarget: Hashable {
    case originStationField
    case destinationStationField
    case recommendationResults
}

enum ActiveTabPrimaryContent: Equatable {
    case itinerary
    case onBoardWindow
    case window
    case empty

    static func resolve(hasItinerary: Bool, hasWindow: Bool, hasOnBoardWindow: Bool) -> ActiveTabPrimaryContent {
        if hasItinerary {
            return .itinerary
        }
        if hasOnBoardWindow {
            return .onBoardWindow
        }
        if hasWindow {
            return .window
        }
        return .empty
    }
}

struct ContentView: View {
    @Environment(AppCoordinator.self) private var appCoordinator
    @Environment(AppOperationState.self) private var operationState
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(ConnectivityService.self) private var connectivityService
    @Environment(JourneyMutationQueue.self) private var journeyMutationQueue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        @Bindable var operationState = operationState

        return ZStack {
            if authViewModel.isSignedIn {
                MainTabView()
                    .transition(reduceMotion ? .identity : .opacity)
            } else if let shareID = appCoordinator.sharedJourneyID {
                SharedJourneyStandaloneView(shareID: shareID)
                    .transition(reduceMotion ? .identity : .opacity)
            } else {
                SignedOutView()
                    .transition(reduceMotion ? .identity : .opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: authViewModel.isSignedIn)
        // App-wide accent, so glass controls outside the tab view (sign-in,
        // shared journeys) tint green rather than system blue.
        .tint(Color.rightTrainActionInk)
        .overlay {
            LoadingOverlay(isVisible: operationState.isLoading)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if authViewModel.isSignedIn {
                ConnectivityStatusBanner()
                    .transition(reduceMotion ? .identity : .move(edge: .top).combined(with: .opacity))
            }
        }
        .alert(item: $operationState.alertState) { state in
            switch state {
            case .upgrade:
                return Alert(
                    title: Text(state.title),
                    message: Text(state.message),
                    primaryButton: .default(Text("View Plans")) {
                        appCoordinator.selectedTab = .settings
                    },
                    secondaryButton: .cancel(Text("Not Now"))
                )
            default:
                return Alert(title: Text(state.title), message: Text(state.message), dismissButton: .default(Text("OK")))
            }
        }
        .overlay {
            if appCoordinator.isBootstrapping {
                StartupSplashView()
                    .transition(reduceMotion ? .identity : .opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.24), value: appCoordinator.isBootstrapping)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: connectivityService.backendState)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: journeyMutationQueue.pendingCount)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: journeyMutationQueue.failedCount)
    }
}

private struct SignedOutView: View {
    var body: some View {
        SignInView()
    }
}

struct AppNavigationDestinationsModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .navigationDestination(for: AppRoute.self) { route in
                switch route {
                case .journeyDetail(let identity):
                    JourneyDetailView(identity: identity)
                case .notificationDetail(let identity):
                    NotificationDetailView(identity: identity)
                case .sharedJourney(let shareID):
                    SharedJourneyView(shareID: shareID)
                }
            }
    }
}

extension View {
    func withAppNavigationDestinations() -> some View {
        modifier(AppNavigationDestinationsModifier())
    }
}

private struct MainTabView: View {
    @Environment(AppCoordinator.self) private var appCoordinator
    @Environment(ActiveWindowViewModel.self) private var activeWindowViewModel

    var body: some View {
        @Bindable var appCoordinator = appCoordinator

        return TabView(selection: $appCoordinator.selectedTab) {
            Tab("Pinned", systemImage: "pin.fill", value: AppTab.active) {
                ActiveTabView()
            }

            Tab("Commutes", systemImage: "calendar.badge.clock", value: AppTab.commutes) {
                CommuteRoutinesView()
            }

            Tab("Plan", systemImage: "magnifyingglass", value: AppTab.plan) {
                PlanTabView()
            }

            Tab("Settings", systemImage: "person.crop.circle", value: AppTab.settings) {
                SettingsTabView()
            }
        }
        .tint(Color.rightTrainActionInk)
        .tabBarMinimizeBehavior(.onScrollDown)
        .pinnedJourneyAccessory(isEnabled: showsPinnedAccessory) {
            appCoordinator.selectedTab = .active
        }
    }

    private var showsPinnedAccessory: Bool {
        activeWindowViewModel.hasActiveJourney && appCoordinator.selectedTab != .active
    }
}

private extension View {
    /// While a journey is pinned, keep it glanceable from every other tab in
    /// the Liquid Glass accessory above the tab bar. Hiding the accessory
    /// needs iOS 26.1; on 26.0 it is omitted rather than shown empty.
    @ViewBuilder
    func pinnedJourneyAccessory(isEnabled: Bool, openPinned: @escaping () -> Void) -> some View {
        if #available(iOS 26.1, *) {
            tabViewBottomAccessory(isEnabled: isEnabled) {
                PinnedJourneyAccessory(openPinned: openPinned)
            }
        } else {
            self
        }
    }
}

/// Compact live summary of the pinned journey for the tab view bottom
/// accessory. Shows countdown/status and platform; tapping opens Pinned.
private struct PinnedJourneyAccessory: View {
    @Environment(ActiveWindowViewModel.self) private var activeWindowViewModel
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    var openPinned: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            if let summary = summary(now: context.date) {
                Button(action: openPinned) {
                    HStack(spacing: RTSpacing.small) {
                        Image(systemName: "tram.fill")
                            .foregroundStyle(summary.tone.color)
                            .accessibilityHidden(true)

                        if placement == .inline {
                            Text(summary.headline)
                                .font(.footnote.weight(.semibold))
                                .monospacedDigit()
                                .lineLimit(1)
                        } else {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(summary.headline)
                                    .font(.subheadline.weight(.semibold))
                                    .monospacedDigit()
                                    .lineLimit(1)
                                Text(summary.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: RTSpacing.small)
                            PlatformTile(platform: summary.platform)
                        }
                    }
                    .padding(.horizontal, RTSpacing.cardPadding)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Pinned journey: \(summary.headline), \(summary.detail), \(summary.platform.accessibilityLabel())")
                .accessibilityHint("Opens the Pinned tab.")
            }
        }
    }

    private struct Summary {
        var headline: String
        var detail: String
        var platform: PlatformValue
        var tone: StatusPill.Tone
    }

    private func summary(now: Date) -> Summary? {
        if let itinerary = activeWindowViewModel.activeItinerary {
            let glance = ActiveItineraryPresentation(itinerary: itinerary).liveGlanceContent(now: now)
            return Summary(
                headline: glance.statusText,
                detail: glance.routeTitle,
                platform: glance.platform,
                tone: glance.statusTone
            )
        }
        guard let window = activeWindowViewModel.activeWindow else {
            return nil
        }
        let presentation = ActiveWindowPresentation(window: window, now: now)
        let recommendation = presentation.heroRecommendation
        let countdown = ActiveWindowPresentation.countdown(for: recommendation, now: now)
        let platform = ActiveWindowPresentation.platformDisplay(for: recommendation.journey)
        return Summary(
            headline: countdown.text,
            detail: presentation.routeTitle,
            platform: platform.value,
            tone: countdown.tone
        )
    }
}

private enum PlanRoute: Hashable {
    case searchResults
    case journeyDetail(JourneyDetailIdentity)
    case stationPicker(StationPickerSelectionRole)
}

private enum PendingPinAction {
    case window
    case directJourney(DirectWindowRecommendation)
    case routeJourney(ItineraryRecommendation)
}

private struct PlanTabView: View {
    @Environment(AppCoordinator.self) private var appCoordinator
    @Environment(ActiveWindowViewModel.self) private var activeWindowViewModel
    @Environment(JourneyDetailViewModel.self) private var journeyDetailViewModel
    @State private var routePath: [PlanRoute] = []

    var body: some View {
        NavigationStack(path: $routePath) {
            ScrollViewReader { scrollProxy in
                planContent(scrollProxy)
                .scrollDismissesKeyboard(.interactively)
                .background(Color.rightTrainSurfaceCream.ignoresSafeArea())
                .navigationTitle("Plan")
                .navigationBarTitleDisplayMode(.large)
                .navigationDestination(for: PlanRoute.self) { route in
                    switch route {
                    case .searchResults:
                        PlanSearchResultsView(openItineraryLegDetail: openDetail(for:))
                    case .journeyDetail(let identity):
                        JourneyDetailView(identity: identity)
                    case .stationPicker(let role):
                        StationPickerView(
                            context: appCoordinator.windowSetupViewModel.stationPickerContext(for: role),
                            apiClient: appCoordinator.stationPickerAPIClient,
                            favourites: appCoordinator.stationFavourites(),
                            locationProvider: SystemStationLocationProvider()
                        ) { station in
                            appCoordinator.windowSetupViewModel.applyStationPickerSelection(station, role: role)
                        }
                    }
                }
            }
        }
        .task(id: appCoordinator.planResetRequestID) {
            guard appCoordinator.planResetRequestID > 0 else { return }
            routePath.removeAll()
        }
#if DEBUG
        .task(id: appCoordinator.debugInitialPlanRoute) {
            guard let debugInitialPlanRoute = appCoordinator.debugInitialPlanRoute else { return }
            switch debugInitialPlanRoute {
            case .searchResults:
                routePath = [.searchResults]
            }
        }
#endif
    }

    @ViewBuilder
    private func planContent(_ scrollProxy: ScrollViewProxy) -> some View {
        if let activeWindow = activeWindowViewModel.activeWindow,
           ActiveWindowPresentation.shouldCollapseSetup(for: activeWindow) {
            ScrollView {
                CollapsedWindowSetupView(state: ActiveWindowPresentation.collapsedSetupState(for: activeWindow))
                    .padding(.horizontal, RTSpacing.pageHorizontal)
                    .padding(.vertical, RTSpacing.pageVertical)
            }
            .readableContentMargins()
        } else {
            WindowSetupView(
                onStationFieldEditingBegan: { target in
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(80))
                        scrollProxy.scrollTo(target, anchor: .top)
                    }
                },
                openStationPicker: { role in
                    routePath.append(.stationPicker(role))
                },
                showSearchResults: {
                    routePath.append(.searchResults)
                }
            )
        }
    }

    private func openDetail(for journey: JourneyResult) async {
        guard let detail = await journeyDetailViewModel.loadJourneyDetail(
            serviceID: journey.serviceId,
            originTPL: journey.originTpl,
            destinationTPL: journey.destinationTpl
        ) else {
            return
        }
        routePath.append(.journeyDetail(JourneyDetailIdentity(detail: detail)))
    }

    private func openDetail(for leg: ItineraryLeg) async {
        guard let detail = await journeyDetailViewModel.loadJourneyDetail(
            serviceID: leg.serviceId,
            originTPL: leg.originTpl,
            destinationTPL: leg.destinationTpl
        ) else {
            return
        }
        routePath.append(.journeyDetail(JourneyDetailIdentity(detail: detail)))
    }
}

private struct PlanSearchResultsView: View {
    @Environment(AppCoordinator.self) private var appCoordinator
    @Environment(ActiveWindowViewModel.self) private var activeWindowViewModel
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(WindowSetupViewModel.self) private var viewModel
    @State private var pendingPinAction: PendingPinAction?

    var openItineraryLegDetail: (ItineraryLeg) async -> Void

    var body: some View {
        List {
            if let response = viewModel.recommendationResponse {
                RecommendationResultsView(
                    response: response,
                    canSearchRoutesWithChanges: viewModel.canUseMultiLegRouting,
                    pinWindow: requestPinDirectWindow,
                    isJourneyPinned: isPinnedDirectJourney,
                    toggleJourneyPin: toggleDirectJourneyPin
                )
            } else if let response = viewModel.journeyPlanResponse {
                ItineraryResultsView(
                    response: response,
                    isJourneyPinned: isPinnedRouteJourney,
                    toggleJourneyPin: toggleRouteJourneyPin,
                    openLegDetail: openItineraryLegDetail
                )
            } else {
                Section {
                    EmptyStateView(
                        title: "No results",
                        message: "Adjust your route or departure time and search again.",
                        symbolName: "magnifyingglass",
                        tint: .rightTrainActionInk
                    )
                    .listRowInsets(EdgeInsets())
                }
            }
        }
        .listStyle(.insetGrouped)
        .readableContentMargins()
        .toolbar {
            if let response = viewModel.recommendationResponse,
               !response.recommendations.isEmpty || response.topRecommendation != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    SearchPinToolbarButton(
                        recommendationCount: response.recommendations.count,
                        action: requestPinDirectWindow
                    )
                }
            }
        }
        // The route is the title so it isn't repeated as a two-line row
        // under a generic "Direct Trains" bar.
        .navigationTitle(resultsRouteTitle)
        .navigationSubtitle(resultsSubtitle)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Replace current Pin?", isPresented: replaceConfirmationPresented, titleVisibility: .visible) {
            Button("Replace Pin", role: .destructive) {
                guard let action = pendingPinAction else { return }
                pendingPinAction = nil
                Task {
                    await performPin(action, replacingActiveJourney: true)
                }
            }
            Button("Cancel", role: .cancel) {
                pendingPinAction = nil
            }
        } message: {
            Text("You can have one Pin at a time, so your current Pin will be removed.")
        }
    }

    private var replaceConfirmationPresented: Binding<Bool> {
        Binding {
            pendingPinAction != nil
        } set: { isPresented in
            if !isPresented {
                pendingPinAction = nil
            }
        }
    }

    private func requestPinDirectWindow() async {
        await requestPin(.window)
    }

    private func requestPinTrain(_ recommendation: DirectWindowRecommendation) async {
        await requestPin(.directJourney(recommendation))
    }

    private func requestPinRoute(_ itinerary: ItineraryRecommendation) async {
        await requestPin(.routeJourney(itinerary))
    }

    private func toggleDirectJourneyPin(_ recommendation: DirectWindowRecommendation) async {
        if isPinnedDirectJourney(recommendation) {
            await activeWindowViewModel.clearPinnedTrain(windowID: activeWindowViewModel.activeWindow?.id)
        } else {
            await requestPinTrain(recommendation)
        }
    }

    private func toggleRouteJourneyPin(_ itinerary: ItineraryRecommendation) async {
        if isPinnedRouteJourney(itinerary) {
            await activeWindowViewModel.deleteActiveItinerary()
        } else {
            await requestPinRoute(itinerary)
        }
    }

    private func isPinnedDirectJourney(_ recommendation: DirectWindowRecommendation) -> Bool {
        guard let activeWindow = activeWindowViewModel.activeWindow,
              activeWindowViewModel.activeItinerary == nil,
              let pinnedServiceID = activeWindow.pinnedTrainServiceId else {
            return false
        }
        return pinnedServiceID == recommendation.journey.serviceId
    }

    private func isPinnedRouteJourney(_ itinerary: ItineraryRecommendation) -> Bool {
        guard activeWindowViewModel.activeWindow == nil,
              let activeItinerary = activeWindowViewModel.activeItinerary else {
            return false
        }
        return activeItinerary.selectedItinerary.stableKey == itinerary.stableKey
    }

    private func requestPin(_ action: PendingPinAction) async {
        guard authViewModel.isSignedIn else {
            await performPin(action, replacingActiveJourney: false)
            return
        }
        guard activeWindowViewModel.hasActiveJourney else {
            await performPin(action, replacingActiveJourney: false)
            return
        }
        pendingPinAction = action
    }

    private func performPin(_ action: PendingPinAction, replacingActiveJourney: Bool) async {
        switch action {
        case .window:
            await viewModel.createActiveWindow(replacingActiveJourney: replacingActiveJourney)
        case .directJourney(let recommendation):
            await viewModel.createActiveWindow(for: recommendation, replacingActiveJourney: replacingActiveJourney)
        case .routeJourney(let itinerary):
            await viewModel.createActiveItinerary(for: itinerary, replacingActiveJourney: replacingActiveJourney)
        }
        if activeWindowViewModel.hasActiveJourney {
            appCoordinator.selectedTab = AppTab.active
        }
    }

    // A full "Origin → Destination" title truncates beside the Pin button,
    // so the destination leads and the origin moves to the subtitle.
    private var resultsRouteTitle: String {
        "To \(viewModel.destination?.displayName ?? "Destination")"
    }

    private var resultsSubtitle: String {
        "From \(viewModel.origin?.displayName ?? "Origin") · \(searchWindowText)"
    }

    private var searchWindowText: String {
        let start = viewModel.departureStart
        let end = start.addingTimeInterval(TimeInterval(viewModel.windowMinutes) * 60)
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "Europe/London")
        formatter.dateFormat = "HH:mm"
        return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
    }
}

private struct SettingsTabView: View {
    var body: some View {
        NavigationStack {
            SettingsProfileView()
        }
    }
}

/// Dispatcher that renders the active itinerary using one of four
private struct LoadingOverlay: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var isVisible: Bool

    var body: some View {
        ZStack {
            if isVisible {
                Color.black.opacity(0.18)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .accessibilityHidden(true)

                ProgressView()
                    .controlSize(.large)
                    .tint(Color.rightTrainActionInk)
                    .padding(22)
                    .glassEffect(.regular, in: .rect(cornerRadius: RTRadius.floating))
                    .accessibilityLabel("Loading")
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: isVisible)
    }
}

#Preview("Pinned AX5") {
    PreviewAppContainer(selectedTab: .active) {
        ContentView()
    }
    .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("Plan AX5") {
    PreviewAppContainer(selectedTab: .plan) {
        ContentView()
    }
    .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("Commutes AX5") {
    PreviewAppContainer(selectedTab: .commutes) {
        ContentView()
    }
    .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("Settings AX5") {
    PreviewAppContainer(selectedTab: .settings) {
        ContentView()
    }
    .environment(\.dynamicTypeSize, .accessibility5)
}
