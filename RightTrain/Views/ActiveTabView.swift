import SwiftUI
import UIKit

private struct ShareSheetItem: Identifiable {
    var id = UUID()
    var url: URL
}

private struct ActivityShareSheet: UIViewControllerRepresentable {
    var activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct ActiveTabView: View {
    @Environment(AppCoordinator.self) private var appCoordinator
    @Environment(ActiveWindowViewModel.self) private var activeWindowViewModel
    @Environment(JourneyDetailViewModel.self) private var journeyDetailViewModel
    @Environment(ConnectivityService.self) private var connectivityService
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var routePath: [AppRoute] = []
    @State private var preparedShareItem: ShareSheetItem?
    @State private var isPreparingShare = false
    @State private var contentWidth: CGFloat = 0

    /// Current surface colour derived from the hero recommendation's live status.
    private var activeSurface: RTSurface {
        guard let window = activeWindowViewModel.activeWindow,
              activeWindowViewModel.activeItinerary == nil else {
            return .neutral
        }
        let presentation = ActiveWindowPresentation(window: window)
        guard presentation.shouldShowHero() else { return .neutral }
        return presentation.heroSurface
    }

    var body: some View {
        NavigationStack(path: $routePath) {
            Group {
                if let boardWindow {
                    // Each column scrolls on its own, so the hero isn't
                    // inside the page-level scroll view.
                    ActiveWindowView(
                        window: boardWindow,
                        showsJustDepartedPrompt: false,
                        layout: .board,
                        boardFooter: AnyView(BetaOnboardingView()),
                        loadDetail: openDetail(for:)
                    )
                    .animation(reduceMotion ? nil : .snappy, value: activeWindowViewModel.liveRefreshGeneration)
                    .padding(.horizontal, RTSpacing.sectionGap)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: RTSpacing.sectionGap) {
                            activeJourneyContent
                                // Live refreshes land outside any transaction, so
                                // without this the numeric content transitions on
                                // times, delays and platforms never play.
                                .animation(reduceMotion ? nil : .snappy, value: activeWindowViewModel.liveRefreshGeneration)

                            // Scrolls with the content: a pinned bottom strip used
                            // to cover a third of the screen and clip the cards.
                            BetaOnboardingView()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, RTSpacing.pageHorizontal)
                        .padding(.vertical, RTSpacing.pageVertical)
                    }
                    .readableContentMargins()
                }
            }
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { width in
                contentWidth = width
            }
            .safeAreaPadding(.bottom, RTSpacing.bottomSafeArea)
            .safeAreaInset(edge: .top, spacing: 0) {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    stickyJustDepartedPrompt(now: context.date)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .refreshable {
                await activeWindowViewModel.refreshActiveWindowFromPullGesture()
            }
            .background(activeSurface.bg.ignoresSafeArea())
            .animation(.easeInOut(duration: 0.4), value: activeSurface)
            .navigationTitle(navigationTitleText)
            // A live journey needs the first screenful for guidance, so the
            // large title only appears when there is nothing pinned.
            .navigationBarTitleDisplayMode(activePrimaryContent == .empty ? .large : .inline)
            .toolbar {
                if activeWindowViewModel.canShareActiveJourney {
                    ToolbarItem(placement: .topBarTrailing) {
                        shareJourneyButton
                    }
                }
            }
            .withAppNavigationDestinations()
            .sheet(item: $preparedShareItem) { item in
                ActivityShareSheet(activityItems: [item.url])
                    .ignoresSafeArea()
            }
            .task(id: activeWindowMonitorTaskID) {
                guard scenePhase == .active else { return }
                await activeWindowViewModel.monitorActiveWindowForegroundUpdates()
            }
            .task(id: appCoordinator.pendingRoute) {
                handlePendingRoute(appCoordinator.pendingRoute)
            }
        }
    }

    /// The Search or Journey Pin to lay out as a board, when the screen is
    /// wide enough. Itineraries and on-board journeys keep the column.
    private var boardWindow: WindowSubscription? {
        guard contentWidth >= RTLayout.boardMinimumWidth,
              activePrimaryContent == .window else {
            return nil
        }
        return activeWindowViewModel.activeWindow
    }

    @ViewBuilder
    private var activeJourneyContent: some View {
        switch activePrimaryContent {
        case .itinerary:
            if let activeItinerary = activeWindowViewModel.activeItinerary {
                PerspectiveActiveItineraryView(
                    itinerary: activeItinerary,
                    isOffline: connectivityService.backendUnavailable,
                    loadDetail: openDetail(for:)
                )
            }
        case .onBoardWindow:
            if let activeWindow = activeWindowViewModel.activeWindow,
               let onBoardRecommendation = onBoardRecommendation(in: activeWindow) {
                ActiveOnTrainJourneyView(
                    window: activeWindow,
                    recommendation: onBoardRecommendation
                )
            }
        case .window:
            if let activeWindow = activeWindowViewModel.activeWindow {
                ActiveWindowView(
                    window: activeWindow,
                    showsJustDepartedPrompt: false,
                    loadDetail: openDetail(for:)
                )
            }
        case .empty:
            NoActiveJourneyView {
                appCoordinator.startNewJourneyPlan()
            }
        }
    }

    /// The pinned route, "London Euston → Stockport", as a station board
    /// names where it is; "Pinned" when nothing is.
    private var navigationTitleText: String {
        switch activePrimaryContent {
        case .itinerary:
            if let itinerary = activeWindowViewModel.activeItinerary {
                return ActiveItineraryPresentation(itinerary: itinerary).routeTitle
            }
        case .window, .onBoardWindow:
            if let window = activeWindowViewModel.activeWindow {
                return ActiveWindowPresentation(window: window).routeTitle
            }
        case .empty:
            break
        }
        return "Pinned"
    }

    private var activePrimaryContent: ActiveTabPrimaryContent {
        let activeWindow = activeWindowViewModel.activeWindow
        let onBoard = activeWindow.map { onBoardRecommendation(in: $0) != nil } ?? false
        return ActiveTabPrimaryContent.resolve(
            hasItinerary: activeWindowViewModel.activeItinerary != nil,
            hasWindow: activeWindow != nil,
            hasOnBoardWindow: onBoard
        )
    }

    private var shareJourneyButton: some View {
        Button {
            prepareShareLink()
        } label: {
            if isPreparingShare {
                ProgressView()
            } else {
                Label("Share Journey", systemImage: "square.and.arrow.up")
            }
        }
        .disabled(isPreparingShare)
        .accessibilityHint("Creates a private share link and opens the iOS share sheet.")
    }

    private func prepareShareLink() {
        guard !isPreparingShare else { return }
        isPreparingShare = true
        Task {
            defer { isPreparingShare = false }
            guard let url = await activeWindowViewModel.createJourneyShareURL() else {
                return
            }
            preparedShareItem = ShareSheetItem(url: url)
        }
    }

    private var activeWindowMonitorTaskID: String {
        guard scenePhase == .active else {
            return "inactive"
        }
        return "active:\(activeWindowViewModel.activeWindow?.id ?? "none"):\(activeWindowViewModel.activeItinerary?.id ?? "none")"
    }

    @ViewBuilder
    private func stickyJustDepartedPrompt(now: Date) -> some View {
        if activeWindowViewModel.activeItinerary == nil,
           let activeWindow = activeWindowViewModel.activeWindow,
           onBoardRecommendation(in: activeWindow) == nil,
           let recommendation = visibleJustDepartedRecommendation(in: activeWindow, now: now) {
            JustDepartedSection(
                recommendation: recommendation,
                countdown: ActiveWindowPresentation.countdown(for: recommendation, now: now),
                isPinned: activeWindowViewModel.pinnedLiveActivityServiceID == recommendation.journey.serviceId,
                loadDetail: {
                    await openDetail(for: recommendation)
                },
                caughtTrain: {
                    activeWindowViewModel.markDepartedPromptHandled(
                        serviceID: recommendation.journey.serviceId,
                        windowID: activeWindow.id
                    )
                    await activeWindowViewModel.pinTrain(serviceID: recommendation.journey.serviceId)
                },
                notOnTrain: {
                    activeWindowViewModel.markDepartedPromptHandled(
                        serviceID: recommendation.journey.serviceId,
                        windowID: activeWindow.id
                    )
                    await activeWindowViewModel.clearPinnedTrain()
                },
                accessibilityLabel: trainAccessibilityLabel(for: recommendation)
            )
            // Floats over the scrolling Pinned content, so it is a glass
            // control surface rather than a content card.
            .padding(RTSpacing.cardPadding)
            .glassEffect(.regular, in: .rect(cornerRadius: RTRadius.floating))
            .padding(.horizontal, RTSpacing.pageHorizontal)
            .readableWidthFrame()
            .padding(.vertical, RTSpacing.small)
            .accessibilitySortPriority(10)
        }
    }

    private func visibleJustDepartedRecommendation(in window: WindowSubscription, now: Date) -> DirectWindowRecommendation? {
        let presentation = ActiveWindowPresentation(window: window, now: now)
        guard let recommendation = presentation.justDepartedRecommendation(now: now) else {
            return nil
        }
        guard activeWindowViewModel.pinnedLiveActivityServiceID != recommendation.journey.serviceId else {
            return nil
        }
        guard !activeWindowViewModel.hasHandledDepartedPrompt(windowID: window.id, serviceID: recommendation.journey.serviceId) else {
            return nil
        }
        return recommendation
    }

    private func onBoardRecommendation(in window: WindowSubscription) -> DirectWindowRecommendation? {
        let presentation = ActiveWindowPresentation(window: window)
        guard presentation.heroIsPinnedTrain,
              JourneyFormatting.isDeparted(presentation.heroRecommendation.journey) else {
            return nil
        }
        return presentation.heroRecommendation
    }

    private func trainAccessibilityLabel(for recommendation: DirectWindowRecommendation) -> String {
        "\(trainAccessibilityValue(for: recommendation)), \(JourneyFormatting.movementStatusText(recommendation.journey, score: recommendation.score))"
    }

    private func trainAccessibilityValue(for recommendation: DirectWindowRecommendation) -> String {
        let journey = recommendation.journey
        let operatorText = JourneyFormatting.operatorSummaryText(journey).map { ", operated by \($0)" } ?? ""
        return "\(JourneyFormatting.departureText(journey)) to \(JourneyFormatting.arrivalText(journey)), \(JourneyFormatting.routeText(journey))\(operatorText)"
    }

    private func openDetail(for recommendation: DirectWindowRecommendation) async {
        await openDetail(
            serviceID: recommendation.journey.serviceId,
            originTPL: recommendation.journey.originTpl,
            destinationTPL: recommendation.journey.destinationTpl
        )
    }

    private func openDetail(for leg: ItineraryLeg) async {
        await openDetail(
            serviceID: leg.serviceId,
            originTPL: leg.originTpl,
            destinationTPL: leg.destinationTpl
        )
    }

    private func openDetail(
        serviceID: Int,
        originTPL: String?,
        destinationTPL: String?
    ) async {
        guard let detail = await journeyDetailViewModel.loadJourneyDetail(
            serviceID: serviceID,
            originTPL: originTPL,
            destinationTPL: destinationTPL
        ) else {
            return
        }
        routePath.append(.journeyDetail(JourneyDetailIdentity(detail: detail)))
    }

    private func handlePendingRoute(_ route: AppRoute?) {
        guard let route else {
            return
        }
        routePath.append(route)
        appCoordinator.consumePendingRoute(route)
    }
}

private struct NoActiveJourneyView: View {
    var planAction: () -> Void

    private var prompt: ActiveWindowPresentation.SetupPromptContent {
        ActiveWindowPresentation.setupPromptContent(
            isSignedIn: true,
            hasRoutine: false,
            hasActiveItinerary: false
        )
    }

    var body: some View {
        EmptyStateView(
            title: prompt.title,
            message: prompt.detailText,
            symbolName: "tram.fill",
            primaryAction: .init(label: prompt.primaryActionText, systemImage: "magnifyingglass", perform: planAction)
        )
        .accessibilityHint("Opens route and time setup.")
    }
}
