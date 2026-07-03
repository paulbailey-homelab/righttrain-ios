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
    @State private var routePath: [AppRoute] = []
    @State private var preparedShareItem: ShareSheetItem?
    @State private var isPreparingShare = false

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
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 24) {
                        activeJourneyContent
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, RTSpacing.pageHorizontal)
                    .padding(.top, RTSpacing.pageVertical)
                    .padding(.bottom, RTSpacing.pageVertical)
                }
            }
            .safeAreaPadding(.bottom, RTSpacing.bottomSafeArea)
            .safeAreaInset(edge: .top, spacing: 0) {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    stickyJustDepartedPrompt(now: context.date)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                // Full-width opaque strip: scroll content must never show
                // through around the chip (it used to float on a chip-width
                // translucent patch, visually colliding with cards).
                BetaOnboardingView()
                    .padding(.horizontal, RTSpacing.pageHorizontal)
                    .padding(.vertical, RTSpacing.small)
                    .frame(maxWidth: .infinity)
                    .background(activeSurface.bg)
            }
            .scrollDismissesKeyboard(.interactively)
            .refreshable {
                await activeWindowViewModel.refreshActiveWindowFromPullGesture()
            }
            .background(activeSurface.bg.ignoresSafeArea())
            .animation(.easeInOut(duration: 0.4), value: activeSurface)
            .toolbarBackground(Color.rightTrainPaperCream, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
            .navigationBarHidden(activeSurface.isStatus)
            .navigationTitle("Pinned")
            .navigationBarTitleDisplayMode(.large)
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

        if activeWindowViewModel.canShareActiveJourney {
            shareJourneyButton
        }
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
            HStack(spacing: RTSpacing.small) {
                Image(systemName: "square.and.arrow.up")
                    .font(.subheadline.weight(.semibold))
                Text(isPreparingShare ? "Preparing Share Link" : "Share Journey")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: RTSpacing.small)
                if isPreparingShare {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, RTSpacing.cardPadding)
            .padding(.vertical, RTSpacing.compact)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.rightTrainSurface, in: RoundedRectangle(cornerRadius: RTRadius.chip))
            .overlay {
                RoundedRectangle(cornerRadius: RTRadius.chip)
                    .stroke(Color.rightTrainBorder, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
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
            .padding(RTSpacing.cardPadding)
            .background(Color.rightTrainSurface, in: RoundedRectangle(cornerRadius: RTRadius.card))
            .overlay {
                RoundedRectangle(cornerRadius: RTRadius.card)
                    .stroke(Color.rightTrainBorder, lineWidth: 1)
            }
            .padding(.horizontal, RTSpacing.pageHorizontal)
            .padding(.vertical, RTSpacing.small)
            .background(Color.rightTrainBackground.opacity(0.96))
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
        VStack(alignment: .leading, spacing: RTSpacing.sectionGap) {
            VStack(alignment: .leading, spacing: RTSpacing.compact) {
                HStack(alignment: .center, spacing: RTSpacing.small) {
                    StatusPill(text: prompt.statusText, tone: .neutral)
                    Spacer(minLength: RTSpacing.small)
                    Label("Manual setup", systemImage: "slider.horizontal.3")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.rightTrainInk.opacity(RTOpacity.dim))
                        .lineLimit(1)
                }

                Text(prompt.title)
                    .font(.title.weight(.bold))
                    .foregroundStyle(Color.rightTrainInk)
                    .fixedSize(horizontal: false, vertical: true)

                Text(prompt.detailText)
                    .font(.body)
                    .foregroundStyle(Color.rightTrainInk.opacity(0.68))
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: RTSpacing.listItem) {
                setupRow(systemImage: "mappin.and.ellipse", title: "Route", value: "Origin and destination")
                setupRow(systemImage: "clock", title: "Window", value: "When you need to travel")
                setupRow(systemImage: "arrow.triangle.branch", title: "Route type", value: "Direct or with changes")
            }

            Button(action: planAction) {
                Label(prompt.primaryActionText, systemImage: "arrow.right.circle.fill")
            }
            .buttonStyle(.rtPrimary)
            .accessibilityHint("Opens route and time setup.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .rtCard()
        .lightSurfaceForeground()
    }

    private func setupRow(systemImage: String, title: String, value: String) -> some View {
        HStack(alignment: .center, spacing: RTSpacing.small) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.rightTrainActionInk)
                .frame(width: RTSize.iconMedium)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.rightTrainInk.opacity(RTOpacity.dim))
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.rightTrainInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: RTSpacing.small)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }
}
