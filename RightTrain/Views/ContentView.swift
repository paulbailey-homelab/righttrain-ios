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

    var body: some View {
        @Bindable var appCoordinator = appCoordinator

        return TabView(selection: $appCoordinator.selectedTab) {
            ActiveTabView()
                .tabItem {
                    Label("Pinned", systemImage: "pin.fill")
                }
                .tag(AppTab.active)

            CommuteRoutinesView()
                .tabItem {
                    Label("Commutes", systemImage: "calendar.badge.clock")
                }
                .tag(AppTab.commutes)

            PlanTabView()
                .tabItem {
                    Label("Plan", systemImage: "magnifyingglass")
                }
                .tag(AppTab.plan)

            SettingsTabView()
                .tabItem {
                    Label("Settings", systemImage: "person.crop.circle")
                }
                .tag(AppTab.settings)
        }
        .tint(Color.rightTrainActionInk)
        .toolbarBackground(Color.rightTrainPaperCream, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
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
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        planContent(scrollProxy)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, RTSpacing.pageHorizontal)
                    .padding(.vertical, RTSpacing.pageVertical)
                    .lightSurfaceForeground()
                }
                .safeAreaPadding(.bottom, RTSpacing.bottomSafeArea)
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
            CollapsedWindowSetupView(state: ActiveWindowPresentation.collapsedSetupState(for: activeWindow))
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
        ScrollView {
            VStack(alignment: .leading, spacing: RTSpacing.sectionGap) {
                if let response = viewModel.recommendationResponse {
                    RecommendationResultsView(
                        response: response,
                        summary: searchSummary(kind: .window),
                        pinWindow: requestPinDirectWindow,
                        isJourneyPinned: isPinnedDirectJourney,
                        toggleJourneyPin: toggleDirectJourneyPin
                    )
                } else if let response = viewModel.journeyPlanResponse {
                    ItineraryResultsView(
                        response: response,
                        summary: searchSummary(kind: .journey),
                        isJourneyPinned: isPinnedRouteJourney,
                        toggleJourneyPin: toggleRouteJourneyPin,
                        openLegDetail: openItineraryLegDetail
                    )
                } else {
                    EmptyStateView(
                        title: "No results",
                        message: "Adjust your route or departure time and search again.",
                        symbolName: "magnifyingglass",
                        tint: .rightTrainActionInk
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, RTSpacing.pageHorizontal)
            .padding(.vertical, RTSpacing.pageVertical)
            .lightSurfaceForeground()
        }
        .safeAreaPadding(.bottom, RTSpacing.bottomSafeArea)
        .background(Color.rightTrainSurfaceCream.ignoresSafeArea())
        .navigationTitle("Search Results")
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
            Text("RightTrain can keep one live Pin at a time. This removes your current Pin and pins this instead.")
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

    private func searchSummary(kind: PinKind) -> SearchPinSummary {
        SearchPinSummary(
            routeTitle: "\(viewModel.origin?.displayName ?? "Origin") → \(viewModel.destination?.displayName ?? "Destination")",
            windowText: searchWindowText,
            kind: kind
        )
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
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: RTRadius.card, style: .continuous))
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
