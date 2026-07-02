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

private struct ConnectivityStatusBanner: View {
    @Environment(ConnectivityService.self) private var connectivityService
    @Environment(JourneyMutationQueue.self) private var journeyMutationQueue
    @Environment(ActiveWindowViewModel.self) private var activeWindowViewModel

    var body: some View {
        if let content {
            HStack(spacing: RTSpacing.small) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(content.title)
                            .font(.footnote.weight(.semibold))
                        if let detail = content.detail {
                            Text(detail)
                                .font(.caption2)
                        }
                    }
                    .lineLimit(2)
                    .minimumScaleFactor(0.88)
                } icon: {
                    Image(systemName: content.systemImage)
                        .font(.footnote.weight(.semibold))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                if let retry = content.retryAction {
                    Button("Retry") {
                        retry()
                    }
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.plain)
                    .accessibilityLabel("Retry failed changes")
                }
                if let dismiss = content.dismissAction {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.footnote.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss")
                }
            }
            .foregroundStyle(content.foreground)
            .padding(.horizontal, RTSpacing.pageHorizontal)
            .padding(.vertical, RTSpacing.small)
            .background(content.background)
        }
    }

    private var content: ConnectivityBannerContent? {
        if journeyMutationQueue.needsAttention {
            let retryableCount = journeyMutationQueue.retryableFailedCount
            let expiredCount = journeyMutationQueue.failedCount - retryableCount
            let detail = expiredCount > 0 && retryableCount == 0
                ? "\(changeText(expiredCount)) expired before syncing."
                : "\(changeText(journeyMutationQueue.failedCount)) couldn't be saved."
            return ConnectivityBannerContent(
                title: "Changes didn't save",
                detail: detail,
                systemImage: "exclamationmark.triangle.fill",
                foreground: .white,
                background: Color.rightTrainDanger,
                dismissAction: { journeyMutationQueue.clearFailed() },
                retryAction: retryableCount > 0 ? {
                    journeyMutationQueue.retryFailed()
                    Task { await activeWindowViewModel.flushQueuedMutations() }
                } : nil
            )
        }
        if journeyMutationQueue.isSyncing {
            return ConnectivityBannerContent(
                title: "Syncing changes",
                detail: "\(changeText(journeyMutationQueue.pendingCount)) pending.",
                systemImage: "arrow.triangle.2.circlepath",
                foreground: .primary,
                background: Color.rightTrainHighlight
            )
        }
        if connectivityService.backendUnavailable {
            let hasActiveJourney = activeWindowViewModel.hasActiveJourney
            let detail: String? = if journeyMutationQueue.pendingCount > 0 {
                "\(changeText(journeyMutationQueue.pendingCount)) queued."
            } else if hasActiveJourney {
                nil
            } else {
                "Showing saved journey data."
            }
            return ConnectivityBannerContent(
                title: hasActiveJourney ? "Offline · saved journey data" : "Offline",
                detail: detail,
                systemImage: "wifi.slash",
                foreground: .white,
                background: Color.rightTrainDanger
            )
        }
        if connectivityService.looksPatchy {
            let hasActiveJourney = activeWindowViewModel.hasActiveJourney
            return ConnectivityBannerContent(
                title: hasActiveJourney ? "Patchy connection · live data may lag" : "Patchy connection",
                detail: journeyMutationQueue.pendingCount > 0 ? "\(changeText(journeyMutationQueue.pendingCount)) queued." : nil,
                systemImage: "antenna.radiowaves.left.and.right",
                foreground: .primary,
                background: Color.rightTrainAmber.opacity(0.28)
            )
        }
        if journeyMutationQueue.pendingCount > 0 {
            return ConnectivityBannerContent(
                title: "Sync pending",
                detail: "\(changeText(journeyMutationQueue.pendingCount)) queued.",
                systemImage: "clock.arrow.circlepath",
                foreground: .primary,
                background: Color.rightTrainSurface
            )
        }
        return nil
    }

    private func changeText(_ count: Int) -> String {
        count == 1 ? "1 journey change" : "\(count) journey changes"
    }
}

private struct ConnectivityBannerContent {
    var title: String
    var detail: String?
    var systemImage: String
    var foreground: Color
    var background: Color
    var dismissAction: (() -> Void)?
    var retryAction: (() -> Void)?
}

private struct SignedOutView: View {
    var body: some View {
        SignInView()
    }
}

private struct SharedJourneyStandaloneView: View {
    @Environment(AppCoordinator.self) private var appCoordinator
    var shareID: String

    var body: some View {
        NavigationStack {
            SharedJourneyView(shareID: shareID)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            appCoordinator.dismissSharedJourney()
                        }
                    }
                }
        }
        .environment(\.colorScheme, .light)
    }
}

struct SharedJourneyPresentation {
    var journey: PublicJourneyShare
    var now: Date = Date()

    var isExpired: Bool {
        Self.isExpired(journey, now: now)
    }

    var statusText: String {
        Self.statusText(status: journey.status, statusText: journey.statusText)
    }

    var statusTone: StatusPill.Tone {
        Self.statusTone(status: journey.status, statusText: journey.statusText)
    }

    var routeContext: String {
        "\(journey.originName) (\(journey.originCrs)) to \(journey.destinationName) (\(journey.destinationCrs))"
    }

    var freshnessText: String {
        "Updated \(SharedJourneyFormatting.relativeText(journey.refreshedAt))"
    }

    static func isExpired(_ journey: PublicJourneyShare, now: Date = Date()) -> Bool {
        journey.expiresAt <= now
    }

    static func statusText(status: String, statusText: String) -> String {
        let explicit = statusText.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = explicit.isEmpty ? status : explicit
        switch candidate.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "on_time", "on time", "ontime", "scheduled":
            return "On time"
        case "delayed", "late":
            return "Delayed"
        case "cancelled", "canceled":
            return "Cancelled"
        case "departed":
            return "Departed"
        case "arrived", "complete", "completed":
            return "Arrived"
        case "unreported", "unknown":
            return "Status unavailable"
        default:
            break
        }
        if !explicit.isEmpty {
            return explicit
        }

        return "Status unavailable"
    }

    static func statusTone(status: String, statusText: String) -> StatusPill.Tone {
        let value = "\(status) \(statusText)".lowercased()
        if value.contains("cancel") {
            return .red
        }
        if value.contains("delay") || value.contains("late") || value.contains("risk") {
            return .amber
        }
        if value.contains("time") || value.contains("live") || value.contains("arrived") || value.contains("departed") {
            return .green
        }
        return .accent
    }
}

struct SharedJourneyView: View {
    @Environment(AppCoordinator.self) private var appCoordinator
    var shareID: String

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            if let journey = appCoordinator.sharedJourney(for: shareID) {
                let presentation = SharedJourneyPresentation(journey: journey, now: context.date)
                if presentation.isExpired {
                    sharedUnavailableState(
                        title: "Shared journey expired",
                        message: "This public journey view is no longer available. Ask the sender for a fresh RightTrain link.",
                        symbolName: "clock.badge.exclamationmark"
                    )
                } else {
                    sharedJourneyContent(journey, presentation: presentation)
                }
            } else {
                sharedUnavailableState(
                    title: "Journey unavailable",
                    message: "RightTrain could not load this shared journey. The link may be expired, removed, or unsafe to show publicly.",
                    symbolName: "link"
                )
            }
        }
    }

    private func sharedJourneyContent(
        _ journey: PublicJourneyShare,
        presentation: SharedJourneyPresentation
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RTSpacing.sectionGap) {
                VStack(alignment: .leading, spacing: RTSpacing.compact) {
                    HStack(alignment: .firstTextBaseline) {
                        StatusPill(text: presentation.statusText, tone: presentation.statusTone)
                        Spacer(minLength: RTSpacing.small)
                        LiveFreshnessText(text: presentation.freshnessText)
                    }

                    Text(journey.routeTitle)
                        .font(.title.weight(.bold))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(presentation.routeContext)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.rightTrainInk.opacity(0.62))
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(alignment: .top, spacing: RTSpacing.compact) {
                    MetricView(label: "Dep", value: SharedJourneyFormatting.timeText(journey.expectedDeparture ?? journey.scheduledDeparture))
                    MetricView(label: "Arr", value: SharedJourneyFormatting.timeText(journey.expectedArrival ?? journey.scheduledArrival))
                }

                NextActionCallout(text: "Use this as a read-only live check.", tone: presentation.statusTone)

                if let position = journey.currentPosition {
                    VStack(alignment: .leading, spacing: RTSpacing.small) {
                        SectionHeader(
                            title: "Current position",
                            subtitle: position.description,
                            tone: presentation.statusTone
                        )
                        ProgressView(value: SharedJourneyFormatting.progressValue(position.progress))
                            .tint(presentation.statusTone.color)
                        if let upcomingStopName = position.upcomingStopName {
                            Text("Next: \(upcomingStopName)")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(RTSpacing.cardPadding)
                    .background(Color.rightTrainPaperCream, in: RoundedRectangle(cornerRadius: RTRadius.card))
                    .overlay {
                        RoundedRectangle(cornerRadius: RTRadius.card)
                            .stroke(presentation.statusTone.color.opacity(0.22), lineWidth: 1)
                    }
                }

                if let disruptions = journey.disruptions, !disruptions.isEmpty {
                    VStack(alignment: .leading, spacing: RTSpacing.small) {
                        Text("Updates")
                            .font(.headline)
                        ForEach(disruptions, id: \.self) { disruption in
                            Label(disruption, systemImage: "exclamationmark.triangle.fill")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Color.rightTrainWarnInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                if let legs = journey.legs, !legs.isEmpty {
                    sharedLegsSection(legs)
                }

                sharedLinkActions(journey)

                Text("Link expires \(SharedJourneyFormatting.timeText(journey.expiresAt)).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, RTSpacing.pageHorizontal)
            .padding(.vertical, RTSpacing.pageVertical)
            .lightSurfaceForeground()
        }
        .background(Color.rightTrainSurfaceCream.ignoresSafeArea())
        .navigationTitle("Shared Journey")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func sharedLegsSection(_ legs: [JourneyShareLeg]) -> some View {
        VStack(alignment: .leading, spacing: RTSpacing.listItem) {
            Text("Journey legs")
                .font(.headline)
            ForEach(legs) { leg in
                let tone = statusTone(for: leg)
                VStack(alignment: .leading, spacing: RTSpacing.small) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(leg.originName) to \(leg.destinationName)")
                            .font(.subheadline.weight(.semibold))
                        Spacer(minLength: RTSpacing.small)
                        StatusPill(text: SharedJourneyPresentation.statusText(status: leg.status, statusText: leg.statusText), tone: tone)
                    }
                    HStack(alignment: .top, spacing: RTSpacing.compact) {
                        MetricView(label: "Dep", value: SharedJourneyFormatting.timeText(leg.expectedDeparture ?? leg.scheduledDeparture))
                        MetricView(label: "Arr", value: SharedJourneyFormatting.timeText(leg.expectedArrival ?? leg.scheduledArrival))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(RTSpacing.compact)
                .background(Color.rightTrainPaperCream, in: RoundedRectangle(cornerRadius: RTRadius.card))
                .overlay {
                    RoundedRectangle(cornerRadius: RTRadius.card)
                        .stroke(tone.color.opacity(0.20), lineWidth: 1)
                }
            }
        }
    }

    private func sharedLinkActions(_ journey: PublicJourneyShare) -> some View {
        VStack(spacing: RTSpacing.listItem) {
            if let appURL = URL(string: journey.appUrl) {
                Link(destination: appURL) {
                    Label("Open in RightTrain", systemImage: "arrow.up.forward.app")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.rightTrainSurfaceCream)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color.rightTrainActionInk, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
            if let appStoreURL = journey.appStoreUrl.flatMap(URL.init(string:)) {
                Link(destination: appStoreURL) {
                    Label("Install RightTrain", systemImage: "arrow.down.app")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(Color.rightTrainActionInk)
            }
        }
    }

    private func sharedUnavailableState(title: String, message: String, symbolName: String) -> some View {
        EmptyStateView(
            title: title,
            message: message,
            symbolName: symbolName,
            tint: .rightTrainActionInk
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, RTSpacing.pageHorizontal)
        .background(Color.rightTrainSurfaceCream.ignoresSafeArea())
        .navigationTitle("Shared Journey")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func statusTone(for journey: PublicJourneyShare) -> StatusPill.Tone {
        SharedJourneyPresentation.statusTone(status: journey.status, statusText: journey.statusText)
    }

    private func statusTone(for leg: JourneyShareLeg) -> StatusPill.Tone {
        SharedJourneyPresentation.statusTone(status: leg.status, statusText: leg.statusText)
    }
}

private enum SharedJourneyFormatting {
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    static func timeText(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }

    static func relativeText(_ date: Date) -> String {
        relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    static func progressValue(_ progress: Double) -> Double {
        min(max(progress, 0), 1)
    }
}

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
        .toolbarColorScheme(.light, for: .tabBar)
    }
}

private struct ActiveTabView: View {
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
                BetaOnboardingView()
                    .padding(.horizontal, RTSpacing.pageHorizontal)
                    .padding(.bottom, RTSpacing.small)
                    .background(activeSurface.bg.opacity(0.96))
            }
            .scrollDismissesKeyboard(.interactively)
            .refreshable {
                await activeWindowViewModel.refreshActiveWindowFromPullGesture()
            }
            .background(activeSurface.bg.ignoresSafeArea())
            .animation(.easeInOut(duration: 0.4), value: activeSurface)
            .toolbarBackground(Color.rightTrainPaperCream, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
            .toolbarColorScheme(.light, for: .tabBar)
            .toolbarColorScheme(.light, for: .navigationBar)
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
        .environment(\.colorScheme, .light)
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

struct NotificationDetailView: View {
    @Environment(AppCoordinator.self) private var appCoordinator
    var identity: WindowNotificationDetailIdentity

    var body: some View {
        if let detail = appCoordinator.notificationDetail(for: identity) {
            NotificationDetailContentView(detail: detail)
        } else {
            EmptyStateView(
                title: "Notification unavailable",
                message: "RightTrain could not load this journey update.",
                symbolName: "bell.slash",
                tint: .rightTrainActionInk
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, RTSpacing.pageHorizontal)
            .background(Color.rightTrainBackground.ignoresSafeArea())
            .navigationTitle("Notification")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct NotificationDetailContentView: View {
    @Environment(AppCoordinator.self) private var appCoordinator
    @Environment(\.dismiss) private var dismiss
    var detail: WindowSubscriptionNotificationDetail

    private var data: WindowNotificationData {
        detail.payload.data
    }

    private var affectedRecommendation: DirectWindowRecommendation? {
        data.departedRecommendation ?? data.affectedRecommendation ?? data.topRecommendation
    }

    private var nextRecommendation: DirectWindowRecommendation? {
        data.nextRecommendation ?? data.topRecommendation
    }

    private var isRecommendedDeparted: Bool {
        detail.eventType == "recommended_train_departed" || detail.payload.type == "recommended_train_departed"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RTSpacing.sectionGap) {
                VStack(alignment: .leading, spacing: RTSpacing.small) {
                    HStack(alignment: .firstTextBaseline) {
                        StatusPill(text: notificationPillText, tone: notificationTone)
                        Spacer(minLength: RTSpacing.small)
                        LiveFreshnessText(text: notificationFreshnessText)
                    }

                    Text(title)
                        .font(.title2.weight(.bold))
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                notificationActionPanel

                if let affectedRecommendation {
                    notificationTrainSection(
                        title: isRecommendedDeparted ? "Departed train" : "Affected train",
                        recommendation: affectedRecommendation
                    )
                }

                if isRecommendedDeparted, let nextRecommendation {
                    notificationTrainSection(title: "Next best train", recommendation: nextRecommendation)
                } else if !isRecommendedDeparted,
                          let nextRecommendation,
                          nextRecommendation.journey.serviceId != affectedRecommendation?.journey.serviceId {
                    notificationTrainSection(title: "Current recommendation", recommendation: nextRecommendation)
                }

                if isRecommendedDeparted {
                    VStack(spacing: RTSpacing.listItem) {
                        if let serviceID = data.departedTrainServiceId ?? data.departedRecommendation?.journey.serviceId {
                            Button {
                                completeNotificationAction {
                                    await appCoordinator.pinDepartedTrain(serviceID: serviceID, windowID: detail.windowSubscriptionId)
                                }
                            } label: {
                                Label("Pin this journey", systemImage: "pin")
                                    .frame(maxWidth: .infinity)
                            }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }

                        Button {
                            completeNotificationAction {
                                await appCoordinator.monitorNextBestAfterDepartedTrain(
                                    serviceID: data.departedTrainServiceId ?? data.departedRecommendation?.journey.serviceId,
                                    windowID: detail.windowSubscriptionId
                                )
                            }
                        } label: {
                            Label("Keep search pinned", systemImage: "arrow.forward.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, RTSpacing.pageHorizontal)
            .padding(.vertical, RTSpacing.pageVertical)
            .lightSurfaceForeground()
        }
        .background(Color.rightTrainSurfaceCream.ignoresSafeArea())
        .toolbarColorScheme(.light, for: .navigationBar)
        .navigationTitle("Notification")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var notificationActionPanel: some View {
        VStack(alignment: .leading, spacing: RTSpacing.compact) {
            MetricView(label: "What changed", value: whatChangedText)
            MetricView(label: "Why it matters", value: whyItMattersText)
            NextActionCallout(text: nextActionText, tone: notificationTone)
        }
        .padding(RTSpacing.cardPadding)
        .background(Color.rightTrainPaperCream, in: RoundedRectangle(cornerRadius: RTRadius.card))
        .overlay {
            RoundedRectangle(cornerRadius: RTRadius.card)
                .stroke(notificationTone.color.opacity(0.28), lineWidth: 1)
        }
        .lightSurfaceForeground()
        .accessibilityElement(children: .combine)
    }

    private var notificationTone: StatusPill.Tone {
        switch detail.eventType {
        case "cancellation":
            return .red
        case "recommended_train_departed", "delay", "platform_change", "window_train_after_window":
            return .amber
        case "window_guidance_cleared":
            return .green
        default:
            return .accent
        }
    }

    private var notificationPillText: String {
        switch notificationTone {
        case .red, .amber:
            return "Action needed"
        case .green:
            return "Cleared"
        case .accent, .neutral:
            return "Live update"
        }
    }

    private var notificationFreshnessText: String {
        ActiveWindowPresentation.freshnessText(
            updatedAt: DateFormatting.date(from: detail.payload.occurredAt) ?? DateFormatting.date(from: detail.createdAt)
        )
    }

    private var title: String {
        switch detail.eventType {
        case "recommended_train_departed":
            return "Recommended train left"
        case "delay":
            return "Delay update"
        case "platform_change":
            return "Platform changed"
        case "cancellation":
            return "Train cancelled"
        case "window_guidance_cleared":
            return "Disruption cleared"
        case "window_train_entered_window", "window_train_after_window":
            return "Search Pin update"
        default:
            return "Train update"
        }
    }

    private var summary: String {
        whatChangedText
    }

    private var whatChangedText: String {
        if isRecommendedDeparted,
           let departed = data.departedRecommendation,
           let next = nextRecommendation {
            return "\(trainReference(departed)) has left. Next best is \(notificationDepartureText(next))."
        }
        if detail.eventType == "window_train_entered_window" || detail.payload.type == "window_train_entered_window" {
            return "The delayed \(windowBoundaryDepartureText) is now expected to depart during your pinned search."
        }
        if detail.eventType == "window_train_after_window" || detail.payload.type == "window_train_after_window" {
            return "The delayed \(windowBoundaryDepartureText) may now depart after your pinned search."
        }
        if let platform = data.platform, let affected = affectedRecommendation {
            if let previous = data.previousPlatform, !previous.isEmpty, previous != platform {
                return "\(trainReference(affected)) moved from platform \(previous) to platform \(platform)."
            }
            return "\(trainReference(affected)) is now platform \(platform)."
        }
        if detail.eventType == "cancellation", let affected = affectedRecommendation {
            return "\(trainReference(affected)) has been cancelled."
        }
        if detail.eventType == "delay", let affected = affectedRecommendation {
            return "\(trainReference(affected)) is delayed."
        }
        if let affected = affectedRecommendation {
            return "\(trainReference(affected)) changed."
        }
        return "RightTrain updated this Search Pin."
    }

    private var whyItMattersText: String {
        switch detail.eventType {
        case "recommended_train_departed":
            return "Your previous best option has already left, so the pinned search now needs a decision."
        case "delay":
            return "The departure or arrival timing may no longer match the window you chose."
        case "platform_change":
            return "The train may leave from a different platform than the one you were watching."
        case "cancellation":
            return "The selected train is no longer usable for this journey."
        case "window_train_entered_window":
            return "A delayed train has moved into your monitored window and may now be useful."
        case "window_train_after_window":
            return "A delayed train may leave too late for the journey window you pinned."
        case "window_guidance_cleared":
            return "The disruption RightTrain was tracking no longer needs extra action."
        default:
            return "The live recommendation changed since the Pin was last checked."
        }
    }

    private var nextActionText: String {
        switch detail.eventType {
        case "recommended_train_departed":
            return "Pin it if you boarded; otherwise keep the search pinned for the next best train."
        case "delay":
            return "Check the updated departure before leaving."
        case "platform_change":
            return data.platform.map { "Use platform \($0) and keep watching for changes." }
                ?? "Check the platform before boarding."
        case "cancellation":
            return "Avoid this train and use the next recommended option."
        case "window_train_entered_window":
            return "Review whether this delayed train now fits your journey."
        case "window_train_after_window":
            return "Review alternatives before committing to this train."
        case "window_guidance_cleared":
            return "Keep your Pin open; no extra action is needed."
        default:
            return "Open the affected journey and check the latest status."
        }
    }

    private func notificationTrainSection(title: String, recommendation: DirectWindowRecommendation) -> some View {
        let columns = [
            GridItem(.flexible(), alignment: .leading),
            GridItem(.flexible(), alignment: .leading),
            GridItem(.flexible(), alignment: .leading)
        ]
        return VStack(alignment: .leading, spacing: RTSpacing.listItem) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: RTSpacing.small) {
                HStack(alignment: .firstTextBaseline, spacing: RTSpacing.small) {
                    Text(trainReference(recommendation))
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: RTSpacing.small)
                    StatusPill(
                        text: JourneyFormatting.movementStatusText(recommendation.journey, score: recommendation.score),
                        tone: ActiveWindowPresentation.statusDisplay(for: recommendation).tone
                    )
                }

                LazyVGrid(columns: columns, alignment: .leading, spacing: RTSpacing.small) {
                    MetricView(label: "Dep", value: notificationDepartureText(recommendation))
                    MetricView(label: "Arr", value: JourneyFormatting.arrivalText(recommendation.journey))
                    MetricView(label: "Platform", value: JourneyFormatting.platformText(recommendation.journey))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(RTSpacing.cardPadding)
            .background(Color.rightTrainSurface, in: RoundedRectangle(cornerRadius: RTRadius.card))
            .lightSurfaceForeground()
            .overlay {
                RoundedRectangle(cornerRadius: RTRadius.card)
                    .stroke(Color.rightTrainBorder, lineWidth: 1)
            }
        }
    }

    private func trainReference(_ recommendation: DirectWindowRecommendation) -> String {
        let journey = recommendation.journey
        let departure = notificationDepartureText(recommendation)
        return "\(departure) from \(journey.originName) to \(journey.destinationName)"
    }

    private func notificationDepartureText(_ recommendation: DirectWindowRecommendation) -> String {
        if JourneyFormatting.hasDelaySignal(journey: recommendation.journey, score: recommendation.score) {
            return "Delayed \(JourneyFormatting.departureDisplay(recommendation.journey).scheduledText)"
        }
        return JourneyFormatting.departureText(recommendation.journey)
    }

    private var windowBoundaryDepartureText: String {
        if let scheduledDepartureTime = data.scheduledDepartureTime, !scheduledDepartureTime.isEmpty {
            return scheduledDepartureTime
        }
        if let affectedRecommendation {
            return JourneyFormatting.departureDisplay(affectedRecommendation.journey).scheduledText
        }
        return "train"
    }

    private func completeNotificationAction(_ action: @escaping () async -> Void) {
        Task {
            await action()
            await MainActor.run {
                appCoordinator.selectedTab = AppTab.active
                dismiss()
            }
        }
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
                .toolbarColorScheme(.light, for: .navigationBar)
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
        .environment(\.colorScheme, .light)
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
        .toolbarColorScheme(.light, for: .navigationBar)
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
                        .foregroundStyle(Color.rightTrainInk.opacity(0.62))
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
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.rightTrainSurfaceCream)
            .background(Color.rightTrainInk, in: RoundedRectangle(cornerRadius: RTRadius.chip))
            .accessibilityHint("Opens route and time setup.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(RTSpacing.cardPadding)
        .background(Color.rightTrainPaperCream, in: RoundedRectangle(cornerRadius: RTRadius.card))
        .overlay {
            RoundedRectangle(cornerRadius: RTRadius.card)
                .stroke(Color.rightTrainBorder, lineWidth: 1)
        }
        .lightSurfaceForeground()
    }

    private func setupRow(systemImage: String, title: String, value: String) -> some View {
        HStack(alignment: .center, spacing: RTSpacing.small) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.rightTrainActionInk)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.rightTrainInk.opacity(0.60))
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
