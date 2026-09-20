import ActivityKit
import Foundation

protocol LiveActivityCoordinating {
    func prepareForRemoteStart(tokenRegistration: LiveActivityTokenRegistrationContext?) async
    func unregisterRemoteStart(tokenRegistration: LiveActivityTokenRegistrationContext?) async
    func sync(window: WindowSubscription?, pinnedTrainServiceID: Int?, tokenRegistration: LiveActivityTokenRegistrationContext?) async
    func sync(itinerary: ItinerarySubscription?, tokenRegistration: LiveActivityTokenRegistrationContext?) async
    func previewLiveActivity() async -> Bool
    func endAll(tokenRegistration: LiveActivityTokenRegistrationContext?) async
}

extension LiveActivityCoordinating {
    func endAll() async {
        await endAll(tokenRegistration: nil)
    }
}

struct NoopLiveActivityCoordinator: LiveActivityCoordinating {
    func prepareForRemoteStart(tokenRegistration: LiveActivityTokenRegistrationContext?) async {}
    func unregisterRemoteStart(tokenRegistration: LiveActivityTokenRegistrationContext?) async {}
    func sync(window: WindowSubscription?, pinnedTrainServiceID: Int?, tokenRegistration: LiveActivityTokenRegistrationContext?) async {}
    func sync(itinerary: ItinerarySubscription?, tokenRegistration: LiveActivityTokenRegistrationContext?) async {}
    func previewLiveActivity() async -> Bool { false }
    func endAll(tokenRegistration: LiveActivityTokenRegistrationContext?) async {}
}

struct LiveActivityTokenRegistrationContext {
    var apiClient: any APIClienting
    var accessToken: String
    var environment: String
    var clientDeviceID: String
    var appBundleID: String?
    var appVersion: String?
    var buildNumber: String?
    var deviceModel: String?
    var osVersion: String?
    var frequentLiveActivityUpdatesEnabled: Bool? = nil
}

@MainActor
final class SystemLiveActivityCoordinator: LiveActivityCoordinating {
    private static let previewWindowSubscriptionID = "righttrain-live-activity-preview"
    private static let previewItinerarySubscriptionID = "righttrain-live-activity-preview-itinerary"
    private static var didRecordActivitiesDisabled = false

    /// Records once per launch that iOS has Live Activities disabled for the
    /// app. Without this, sync() silently ends every activity and the pinned
    /// journey just disappears from the lock screen with no trace.
    private static func recordActivitiesDisabledOnce() {
        guard !didRecordActivitiesDisabled else {
            return
        }
        didRecordActivitiesDisabled = true
        BetaDiagnostics.record("live_activities_disabled_by_ios", severity: .warning)
    }

    /// Token registrations were fire-and-forget with print()-only failures: a
    /// single transient error meant the Live Activity never received a push
    /// update. Retry briefly with jitter, then leave a diagnostics trail.
    private static func withRegistrationRetry(_ event: String, operation: () async throws -> Void) async {
        var delaySeconds = 0.5
        for attempt in 1...3 {
            do {
                try await operation()
                return
            } catch {
                if attempt == 3 {
                    BetaDiagnostics.record(event, details: error.localizedDescription, severity: .error)
                    return
                }
                try? await Task.sleep(for: .seconds(delaySeconds * Double.random(in: 0.8...1.2)))
                delaySeconds *= 2
            }
        }
    }
    private var pushTokenObservers: [Activity<RightTrainLiveActivityAttributes>.ID: Task<Void, Never>] = [:]
    private var pushToStartTokenObserver: Task<Void, Never>?
    private var pushToStartObserverKey: String?
    private var activityUpdatesObserver: Task<Void, Never>?
    private var activityUpdatesObserverKey: String?
    private var frequentPushEnablementObserver: Task<Void, Never>?
    private var frequentPushEnablementObserverKey: String?

    func sync(window: WindowSubscription?, pinnedTrainServiceID: Int?, tokenRegistration: LiveActivityTokenRegistrationContext?) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            Self.recordActivitiesDisabledOnce()
            await unregisterRemoteStart(tokenRegistration: tokenRegistration)
            await endAll(tokenRegistration: tokenRegistration)
            return
        }

        await prepareForRemoteStart(tokenRegistration: tokenRegistration)

        guard let window, window.isLiveActivityActive else {
            await endAll(tokenRegistration: tokenRegistration)
            return
        }

        let recommendations = window.recommendations.isEmpty ? [window.selectedRecommendation] : window.recommendations
        let pinnedTrainIsValid = pinnedTrainServiceID.flatMap { serviceID in
            recommendations.contains { $0.journey.serviceId == serviceID } ? serviceID : nil
        }

        if let pinnedTrainIsValid {
            let trainState = RightTrainLiveActivityStateBuilder.state(
                for: window,
                pinnedTrainServiceID: pinnedTrainIsValid,
                activityKind: .train
            )
            await upsertActivity(
                kind: .train,
                pinnedTrainServiceID: pinnedTrainIsValid,
                window: window,
                state: trainState,
                relevanceScore: 100,
                tokenRegistration: tokenRegistration
            )
            await endActivities(keeping: LiveActivitySelection(
                windowSubscriptionID: window.id,
                activityKind: .train,
                pinnedTrainServiceID: pinnedTrainIsValid
            ), tokenRegistration: tokenRegistration)
        } else {
            let windowState = RightTrainLiveActivityStateBuilder.state(for: window, pinnedTrainServiceID: nil)
            await upsertActivity(
                kind: .window,
                pinnedTrainServiceID: nil,
                window: window,
                state: windowState,
                relevanceScore: 50,
                tokenRegistration: tokenRegistration
            )
            await endActivities(keeping: LiveActivitySelection(
                windowSubscriptionID: window.id,
                activityKind: .window,
                pinnedTrainServiceID: nil
            ), tokenRegistration: tokenRegistration)
        }
    }

    func sync(itinerary: ItinerarySubscription?, tokenRegistration: LiveActivityTokenRegistrationContext?) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            Self.recordActivitiesDisabledOnce()
            await unregisterRemoteStart(tokenRegistration: tokenRegistration)
            await endAll(tokenRegistration: tokenRegistration)
            return
        }

        await prepareForRemoteStart(tokenRegistration: tokenRegistration)

        guard let itinerary, itinerary.isLiveActivityActive else {
            await endAll(tokenRegistration: tokenRegistration)
            return
        }

        let kind = Self.activityKind(for: itinerary.resolvedPhase)
        let state = RightTrainLiveActivityStateBuilder.state(for: itinerary)
        await upsertItineraryActivity(
            itinerary: itinerary,
            kind: kind,
            state: state,
            relevanceScore: 60,
            tokenRegistration: tokenRegistration
        )
        await endActivities(keeping: LiveActivitySelection(
            itinerarySubscriptionID: itinerary.id,
            activityKind: kind,
            pinnedTrainServiceID: nil
        ), tokenRegistration: tokenRegistration)
    }

    /// Maps a server-driven phase to the right ActivityKind so the
    /// widget can render a different layout once the user is on board.
    /// `.itinerary` continues to mean "you're picking trains";
    /// `.leg` means "you're on one, here's what's next".
    static func activityKind(for phase: ItineraryPhase) -> RightTrainLiveActivityAttributes.ActivityKind {
        switch phase {
        case .planning, .atOrigin:
            return .itinerary
        case .onLeg, .approachingInterchange, .onFinalLeg:
            return .leg
        }
    }

    func prepareForRemoteStart(tokenRegistration: LiveActivityTokenRegistrationContext?) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            cancelPushToStartTokenObserver()
            cancelActivityUpdatesObserver()
            cancelFrequentPushEnablementObserver()
            return
        }
        guard let tokenRegistration else {
            cancelPushToStartTokenObserver()
            cancelActivityUpdatesObserver()
            cancelFrequentPushEnablementObserver()
            return
        }

        await observePushToStartTokenUpdates(tokenRegistration: tokenRegistration)
        observeRemoteStartedActivities(tokenRegistration: tokenRegistration)
        observeFrequentPushEnablementUpdates(tokenRegistration: tokenRegistration)
    }

    func unregisterRemoteStart(tokenRegistration: LiveActivityTokenRegistrationContext?) async {
        await Self.deletePushToStartTokenRegistration(tokenRegistration: tokenRegistration)
        Self.removeStoredPushToStartToken()
        cancelPushToStartTokenObserver()
        cancelActivityUpdatesObserver()
        cancelFrequentPushEnablementObserver()
    }

    func previewLiveActivity() async -> Bool {
#if DEBUG
        await previewLiveActivity(scenario: .windowOnTime)
#else
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            return false
        }

        let now = Date()
        let state = Self.previewContentState(now: now)
        let content = ActivityContent(
            state: state,
            staleDate: now.addingTimeInterval(30),
            relevanceScore: 90
        )

        for activity in Activity<RightTrainLiveActivityAttributes>.activities
            where activity.attributes.windowSubscriptionID == Self.previewWindowSubscriptionID {
            await activity.end(nil, dismissalPolicy: .immediate)
        }

        do {
            let activity = try Activity.request(
                attributes: RightTrainLiveActivityAttributes(
                    windowSubscriptionID: Self.previewWindowSubscriptionID,
                    itinerarySubscriptionID: nil,
                    activityKind: .window,
                    pinnedTrainServiceID: nil,
                    originCrs: "EUS",
                    destinationCrs: "MAN",
                    startedAtText: Self.nowText()
                ),
                content: content,
                pushType: nil
            )

            Task {
                try? await Task.sleep(for: .seconds(30))
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            return true
        } catch {
            BetaDiagnostics.record("live_activity_preview_failed", details: error.localizedDescription, severity: .warning)
            return false
        }
#endif
    }

#if DEBUG
    func previewLiveActivity(scenario: LiveActivityPreviewScenario, duration: TimeInterval = 120) async -> Bool {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            return false
        }

        let now = Date()
        let state = scenario.state(now: now)
        let content = ActivityContent(
            state: state,
            staleDate: now.addingTimeInterval(duration),
            relevanceScore: 90
        )

        await Self.endPreviewLiveActivities()

        do {
            let activity = try Activity.request(
                attributes: scenario.attributes(startedAtText: Self.nowText()),
                content: content,
                pushType: nil
            )

            Task {
                try? await Task.sleep(for: .seconds(duration))
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            return true
        } catch {
            BetaDiagnostics.record("live_activity_preview_failed", details: error.localizedDescription, severity: .warning)
            return false
        }
    }

    static func endPreviewLiveActivities() async {
        for activity in Activity<RightTrainLiveActivityAttributes>.activities where isPreviewActivity(activity) {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    private static func isPreviewActivity(_ activity: Activity<RightTrainLiveActivityAttributes>) -> Bool {
        activity.attributes.windowSubscriptionID == previewWindowSubscriptionID ||
            activity.attributes.itinerarySubscriptionID == previewItinerarySubscriptionID
    }
#endif

    private struct LiveActivitySelection {
        var windowSubscriptionID: String? = nil
        var itinerarySubscriptionID: String? = nil
        var activityKind: RightTrainLiveActivityAttributes.ActivityKind
        var pinnedTrainServiceID: Int?
    }

    private func upsertActivity(
        kind: RightTrainLiveActivityAttributes.ActivityKind,
        pinnedTrainServiceID: Int?,
        window: WindowSubscription,
        state: RightTrainLiveActivityAttributes.ContentState,
        relevanceScore: Double,
        tokenRegistration: LiveActivityTokenRegistrationContext?
    ) async {
        let matchingActivities = Activity<RightTrainLiveActivityAttributes>.activities.filter {
            $0.attributes.windowSubscriptionID == window.id &&
                $0.attributes.activityKind == kind &&
                $0.attributes.pinnedTrainServiceID == pinnedTrainServiceID
        }

        if let activity = matchingActivities.first {
            let markedState = Self.stateByApplyingPlatformChangeMarker(
                to: state,
                previousState: activity.content.state,
                activityKind: kind
            )
            let content = ActivityContent(
                state: markedState,
                staleDate: staleDate(for: window),
                relevanceScore: relevanceScore
            )
            await activity.update(content)
            observePushTokenUpdates(for: activity, tokenRegistration: tokenRegistration)

            for duplicate in matchingActivities.dropFirst() {
                await Self.deletePushTokenRegistration(for: duplicate, tokenRegistration: tokenRegistration)
                await duplicate.end(content, dismissalPolicy: .immediate)
                Self.removeStoredPushToken(activity: duplicate, subscriptionKey: Self.activitySubscriptionKey(for: duplicate))
                cancelPushTokenObserver(for: duplicate.id)
            }
        } else {
            let content = ActivityContent(
                state: state,
                staleDate: staleDate(for: window),
                relevanceScore: relevanceScore
            )
            do {
                let activity = try Activity.request(
                    attributes: RightTrainLiveActivityAttributes(
                        windowSubscriptionID: window.id,
                        itinerarySubscriptionID: nil,
                        activityKind: kind,
                        pinnedTrainServiceID: pinnedTrainServiceID,
                        originCrs: window.originCrs,
                        destinationCrs: window.destinationCrs,
                        startedAtText: Self.nowText()
                    ),
                    content: content,
                    pushType: .token
                )
                observePushTokenUpdates(for: activity, tokenRegistration: tokenRegistration)
            } catch {
                BetaDiagnostics.record("live_activity_request_failed", details: error.localizedDescription, severity: .error)
            }
        }
    }

    private static func stateByApplyingPlatformChangeMarker(
        to state: RightTrainLiveActivityAttributes.ContentState,
        previousState: RightTrainLiveActivityAttributes.ContentState?,
        activityKind: RightTrainLiveActivityAttributes.ActivityKind
    ) -> RightTrainLiveActivityAttributes.ContentState {
        guard activityKind == .window || activityKind == .train else {
            return state
        }
        var next = state
        guard let currentTrain = visibleDirectTrain(in: state),
              !currentTrain.departed,
              let currentPlatform = knownPlatform(currentTrain.departurePlatform) else {
            next.platformChange = nil
            return next
        }

        let previousChange = previousState?.platformChange
        if previousChange?.serviceID == currentTrain.serviceID,
           previousChange?.currentPlatform == currentPlatform {
            next.platformChange = previousChange
            return next
        }

        let previousTrain = previousState.flatMap { Self.visibleDirectTrain(in: $0) }
        let previousPlatform = knownPlatform(previousTrain?.departurePlatform) ?? previousChange?.currentPlatform
        guard previousTrain?.serviceID == currentTrain.serviceID || previousChange?.serviceID == currentTrain.serviceID,
              let previousPlatform,
              previousPlatform != currentPlatform else {
            next.platformChange = nil
            return next
        }

        next.platformChange = RightTrainLiveActivityAttributes.ContentState.PlatformChange(
            serviceID: currentTrain.serviceID,
            previousPlatform: previousPlatform,
            currentPlatform: currentPlatform,
            changedAtText: nowText()
        )
        return next
    }

    private static func visibleDirectTrain(
        in state: RightTrainLiveActivityAttributes.ContentState
    ) -> RightTrainLiveActivityAttributes.ContentState.Train? {
        if let pinnedTrainServiceID = state.pinnedTrainServiceID,
           let train = state.trains.first(where: { $0.serviceID == pinnedTrainServiceID }) {
            return train
        }
        if let train = state.trains.first(where: { $0.serviceID == state.recommendationServiceID }) {
            return train
        }
        return state.trains.first(where: \.recommended) ?? state.trains.first
    }

    private static func knownPlatform(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty,
              trimmed != "-",
              trimmed.uppercased() != "TBC" else {
            return nil
        }
        return trimmed
    }

    /// ActivityKit rejects a content state over roughly 4 KB, and an itinerary
    /// carries one `Train` per leg where a direct window carries one in total.
    /// A four-leg journey can reach the limit on its own, and `Activity.request`
    /// then throws, leaving no Live Activity and no sign of why. The widget
    /// reads only the leg at `currentLegIndex` and the one after it, so a state
    /// that will not fit is reduced to those two.
    private static let maximumContentStateBytes = 3_500

    private static func encodedSize(
        _ state: RightTrainLiveActivityAttributes.ContentState
    ) -> Int? {
        try? JSONEncoder().encode(state).count
    }

    private static func sizeBounded(
        _ state: RightTrainLiveActivityAttributes.ContentState
    ) -> RightTrainLiveActivityAttributes.ContentState {
        guard let size = encodedSize(state), size > maximumContentStateBytes else {
            return state
        }
        // Keep the leg being travelled and the one being changed on to; the
        // widget renders no others. Rebasing `currentLegIndex` to zero keeps
        // every index it derives pointing at the same train, so a journey of
        // any length reduces to two.
        let start = min(max(state.currentLegIndex ?? 0, 0), max(state.trains.count - 1, 0))
        let window = Array(state.trains.dropFirst(start).prefix(2))
        guard window.count < state.trains.count else {
            BetaDiagnostics.record(
                "live_activity_itinerary_state_oversized",
                details: "\(size) bytes across \(state.trains.count) legs, nothing left to trim",
                severity: .error
            )
            return state
        }
        var trimmed = state
        trimmed.trains = window
        trimmed.currentLegIndex = state.currentLegIndex == nil ? nil : 0
        BetaDiagnostics.record(
            "live_activity_itinerary_state_trimmed",
            details: "\(size) bytes across \(state.trains.count) legs cut to \(window.count)",
            severity: .warning
        )
        return trimmed
    }

    private func upsertItineraryActivity(
        itinerary: ItinerarySubscription,
        kind: RightTrainLiveActivityAttributes.ActivityKind,
        state: RightTrainLiveActivityAttributes.ContentState,
        relevanceScore: Double,
        tokenRegistration: LiveActivityTokenRegistrationContext?
    ) async {
        let content = ActivityContent(
            state: Self.sizeBounded(state),
            staleDate: staleDate(for: itinerary, activityKind: kind),
            relevanceScore: relevanceScore
        )
        let matchingActivities = Activity<RightTrainLiveActivityAttributes>.activities.filter {
            $0.attributes.itinerarySubscriptionID == itinerary.id &&
                $0.attributes.activityKind == kind
        }

        if let activity = matchingActivities.first {
            await activity.update(content)
            observePushTokenUpdates(for: activity, tokenRegistration: tokenRegistration)

            for duplicate in matchingActivities.dropFirst() {
                await Self.deletePushTokenRegistration(for: duplicate, tokenRegistration: tokenRegistration)
                await duplicate.end(content, dismissalPolicy: .immediate)
                Self.removeStoredPushToken(activity: duplicate, subscriptionKey: Self.activitySubscriptionKey(for: duplicate))
                cancelPushTokenObserver(for: duplicate.id)
            }
        } else {
            do {
                let activity = try Activity.request(
                    attributes: RightTrainLiveActivityAttributes(
                        windowSubscriptionID: nil,
                        itinerarySubscriptionID: itinerary.id,
                        activityKind: kind,
                        pinnedTrainServiceID: nil,
                        originCrs: itinerary.originCrs,
                        destinationCrs: itinerary.destinationCrs,
                        startedAtText: Self.nowText()
                    ),
                    content: content,
                    pushType: .token
                )
                observePushTokenUpdates(for: activity, tokenRegistration: tokenRegistration)
            } catch {
                // Worth the encoded size: every realistic cause of a throw here
                // is the payload, and the message alone does not say so.
                let size = Self.encodedSize(content.state).map { "\($0) bytes, " } ?? ""
                BetaDiagnostics.record(
                    "live_activity_itinerary_request_failed",
                    details: "\(size)\(content.state.trains.count) legs: \(error.localizedDescription)",
                    severity: .error
                )
            }
        }
    }

    func endAll(tokenRegistration: LiveActivityTokenRegistrationContext?) async {
        await endActivities(keeping: nil, tokenRegistration: tokenRegistration)
    }

    private func endActivities(keeping selection: LiveActivitySelection?, tokenRegistration: LiveActivityTokenRegistrationContext?) async {
        for activity in Activity<RightTrainLiveActivityAttributes>.activities {
            if let selection,
               activity.attributes.windowSubscriptionID == selection.windowSubscriptionID,
               activity.attributes.itinerarySubscriptionID == selection.itinerarySubscriptionID,
               activity.attributes.activityKind == selection.activityKind,
               activity.attributes.pinnedTrainServiceID == selection.pinnedTrainServiceID {
                continue
            }
            await Self.deletePushTokenRegistration(for: activity, tokenRegistration: tokenRegistration)
            await activity.end(nil, dismissalPolicy: .immediate)
            Self.removeStoredPushToken(activity: activity, subscriptionKey: Self.activitySubscriptionKey(for: activity))
            cancelPushTokenObserver(for: activity.id)
        }
    }

    private func observePushTokenUpdates(
        for activity: Activity<RightTrainLiveActivityAttributes>,
        tokenRegistration: LiveActivityTokenRegistrationContext?
    ) {
        let subscriptionKey = Self.activitySubscriptionKey(for: activity)
        if let token = activity.pushToken {
            Self.storePushToken(token, activity: activity, subscriptionKey: subscriptionKey)
            Task {
                await Self.registerPushToken(token, activity: activity, tokenRegistration: tokenRegistration)
            }
        }

        guard pushTokenObservers[activity.id] == nil else {
            return
        }

        pushTokenObservers[activity.id] = Task {
            for await token in activity.pushTokenUpdates {
                Self.storePushToken(token, activity: activity, subscriptionKey: subscriptionKey)
                await Self.registerPushToken(token, activity: activity, tokenRegistration: tokenRegistration)
            }
        }
    }

    private func cancelPushTokenObserver(for activityID: Activity<RightTrainLiveActivityAttributes>.ID) {
        pushTokenObservers[activityID]?.cancel()
        pushTokenObservers[activityID] = nil
    }

    private func observePushToStartTokenUpdates(tokenRegistration: LiveActivityTokenRegistrationContext) async {
        if let token = Activity<RightTrainLiveActivityAttributes>.pushToStartToken {
            Self.storePushToStartToken(token)
            await Self.registerPushToStartToken(token, tokenRegistration: tokenRegistration)
        }

        let observerKey = "\(tokenRegistration.clientDeviceID)|\(tokenRegistration.environment)|\(tokenRegistration.accessToken)"
        guard pushToStartObserverKey != observerKey else {
            return
        }

        cancelPushToStartTokenObserver()
        pushToStartObserverKey = observerKey
        pushToStartTokenObserver = Task {
            for await token in Activity<RightTrainLiveActivityAttributes>.pushToStartTokenUpdates {
                Self.storePushToStartToken(token)
                await Self.registerPushToStartToken(token, tokenRegistration: tokenRegistration)
            }
        }
    }

    private func cancelPushToStartTokenObserver() {
        pushToStartTokenObserver?.cancel()
        pushToStartTokenObserver = nil
        pushToStartObserverKey = nil
    }

    private func observeRemoteStartedActivities(tokenRegistration: LiveActivityTokenRegistrationContext) {
        let observerKey = "\(tokenRegistration.clientDeviceID)|\(tokenRegistration.environment)|\(tokenRegistration.accessToken)"
        guard activityUpdatesObserverKey != observerKey else {
            return
        }

        cancelActivityUpdatesObserver()
        activityUpdatesObserverKey = observerKey
        for activity in Activity<RightTrainLiveActivityAttributes>.activities {
            observePushTokenUpdates(for: activity, tokenRegistration: tokenRegistration)
        }
        activityUpdatesObserver = Task { [weak self] in
            for await activity in Activity<RightTrainLiveActivityAttributes>.activityUpdates {
                self?.observeRemoteStartedActivity(activity, tokenRegistration: tokenRegistration)
            }
        }
    }

    private func observeRemoteStartedActivity(
        _ activity: Activity<RightTrainLiveActivityAttributes>,
        tokenRegistration: LiveActivityTokenRegistrationContext
    ) {
        observePushTokenUpdates(for: activity, tokenRegistration: tokenRegistration)
    }

    private func cancelActivityUpdatesObserver() {
        activityUpdatesObserver?.cancel()
        activityUpdatesObserver = nil
        activityUpdatesObserverKey = nil
    }

    private func observeFrequentPushEnablementUpdates(tokenRegistration: LiveActivityTokenRegistrationContext) {
        let observerKey = "\(tokenRegistration.clientDeviceID)|\(tokenRegistration.environment)|\(tokenRegistration.accessToken)"
        guard frequentPushEnablementObserverKey != observerKey else {
            return
        }

        cancelFrequentPushEnablementObserver()
        frequentPushEnablementObserverKey = observerKey
        frequentPushEnablementObserver = Task { [weak self] in
            for await enabled in ActivityAuthorizationInfo().frequentPushEnablementUpdates {
                var updatedRegistration = tokenRegistration
                updatedRegistration.frequentLiveActivityUpdatesEnabled = enabled
                await Self.registerStoredPushToStartToken(tokenRegistration: updatedRegistration)
                await self?.registerStoredPushTokens(tokenRegistration: updatedRegistration)
            }
        }
    }

    private func cancelFrequentPushEnablementObserver() {
        frequentPushEnablementObserver?.cancel()
        frequentPushEnablementObserver = nil
        frequentPushEnablementObserverKey = nil
    }

    private func registerStoredPushTokens(tokenRegistration: LiveActivityTokenRegistrationContext) async {
        for activity in Activity<RightTrainLiveActivityAttributes>.activities {
            let subscriptionKey = Self.activitySubscriptionKey(for: activity)
            if let token = Self.storedPushToken(activity: activity, subscriptionKey: subscriptionKey) {
                await Self.registerPushTokenHex(token, activity: activity, tokenRegistration: tokenRegistration)
            } else if let token = activity.pushToken {
                Self.storePushToken(token, activity: activity, subscriptionKey: subscriptionKey)
                await Self.registerPushToken(token, activity: activity, tokenRegistration: tokenRegistration)
            }
        }
    }

    private static func registerStoredPushToStartToken(tokenRegistration: LiveActivityTokenRegistrationContext) async {
        if let token = storedPushToStartToken() {
            await registerPushToStartTokenHex(token, tokenRegistration: tokenRegistration)
        } else if let token = Activity<RightTrainLiveActivityAttributes>.pushToStartToken {
            storePushToStartToken(token)
            await registerPushToStartToken(token, tokenRegistration: tokenRegistration)
        }
    }

    private func staleDate(for window: WindowSubscription) -> Date? {
        guard let departureStart = DateFormatting.date(from: window.departureStart) else {
            return nil
        }
        return departureStart.addingTimeInterval(TimeInterval(window.windowMinutes + 30) * 60)
    }

    private func staleDate(
        for itinerary: ItinerarySubscription,
        activityKind: RightTrainLiveActivityAttributes.ActivityKind
    ) -> Date? {
        guard let departureStart = DateFormatting.date(from: itinerary.departureStart) else {
            return nil
        }
        let fallback = departureStart.addingTimeInterval(TimeInterval(itinerary.windowMinutes + 30) * 60)
        switch itinerary.resolvedPhase {
        case .onLeg:
            if activityKind == .leg,
               let currentLeg = itinerary.currentLeg {
                return Self.expectedArrivalDate(for: currentLeg) ?? fallback
            }
            return Self.finalExpectedArrivalDate(for: itinerary) ?? fallback
        case .approachingInterchange:
            if let connection = itinerary.nextConnection {
                return Self.expectedDepartureDate(for: connection) ?? fallback
            }
            return Self.finalExpectedArrivalDate(for: itinerary) ?? fallback
        case .onFinalLeg:
            return Self.finalExpectedArrivalDate(for: itinerary) ?? fallback
        case .planning, .atOrigin:
            return fallback
        }
    }

    private static func expectedArrivalDate(for leg: ItineraryLeg) -> Date? {
        leg.expectedArrivalAt.flatMap(DateFormatting.date(from:))
            ?? leg.expectedArrival.flatMap(DateFormatting.date(from:))
            ?? DateFormatting.date(from: leg.scheduledArrival)
    }

    private static func expectedDepartureDate(for connection: ItineraryConnection) -> Date? {
        DateFormatting.date(from: connection.expectedDeparture)
            ?? DateFormatting.date(from: connection.scheduledDeparture)
    }

    private static func finalExpectedArrivalDate(for itinerary: ItinerarySubscription) -> Date? {
        guard let finalLeg = itinerary.selectedItinerary.legs.last else {
            return nil
        }
        return expectedArrivalDate(for: finalLeg)
    }

    private static func storePushToken(
        _ token: Data,
        activity: Activity<RightTrainLiveActivityAttributes>,
        subscriptionKey: String
    ) {
        UserDefaults.standard.set(
            hexString(token),
            forKey: pushTokenKey(activity: activity, subscriptionKey: subscriptionKey)
        )
    }

    private static func storePushToStartToken(
        _ token: Data
    ) {
        UserDefaults.standard.set(
            hexString(token),
            forKey: pushToStartTokenKey
        )
    }

    private static func storedPushToken(
        activity: Activity<RightTrainLiveActivityAttributes>,
        subscriptionKey: String
    ) -> String? {
        UserDefaults.standard.string(forKey: pushTokenKey(activity: activity, subscriptionKey: subscriptionKey))
    }

    private static func storedPushToStartToken() -> String? {
        UserDefaults.standard.string(forKey: pushToStartTokenKey)
    }

    private static func removeStoredPushToken(
        activity: Activity<RightTrainLiveActivityAttributes>,
        subscriptionKey: String
    ) {
        UserDefaults.standard.removeObject(forKey: pushTokenKey(activity: activity, subscriptionKey: subscriptionKey))
    }

    private static func removeStoredPushToStartToken() {
        UserDefaults.standard.removeObject(forKey: pushToStartTokenKey)
    }

    private static func pushTokenKey(
        activity: Activity<RightTrainLiveActivityAttributes>,
        subscriptionKey: String
    ) -> String {
        "righttrain.liveActivity.\(subscriptionKey).\(activity.attributes.activityKind.rawValue).\(activity.attributes.pinnedTrainServiceID ?? 0).pushToken"
    }

    private static func activitySubscriptionKey(for activity: Activity<RightTrainLiveActivityAttributes>) -> String {
        if let itinerarySubscriptionID = activity.attributes.itinerarySubscriptionID,
           !itinerarySubscriptionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "itinerary:\(itinerarySubscriptionID)"
        }
        if let windowSubscriptionID = activity.attributes.windowSubscriptionID,
           !windowSubscriptionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "window:\(windowSubscriptionID)"
        }
        return "unknown:\(activity.id)"
    }

    private static var pushToStartTokenKey: String {
        "righttrain.liveActivity.pushToStartToken"
    }

    private static func pushToStartActivityID(clientDeviceID: String) -> String {
        "push-to-start:\(clientDeviceID)"
    }

    private static func itineraryPushToStartActivityID(clientDeviceID: String) -> String {
        "push-to-start:itinerary:\(clientDeviceID)"
    }

    private static func hexString(_ token: Data) -> String {
        token.map { String(format: "%02x", $0) }.joined()
    }

    private static func registerPushToken(
        _ token: Data,
        activity: Activity<RightTrainLiveActivityAttributes>,
        tokenRegistration: LiveActivityTokenRegistrationContext?
    ) async {
        guard let tokenRegistration else {
            return
        }
        await registerPushTokenHex(hexString(token), activity: activity, tokenRegistration: tokenRegistration)
    }

    private static func registerPushTokenHex(
        _ token: String,
        activity: Activity<RightTrainLiveActivityAttributes>,
        tokenRegistration: LiveActivityTokenRegistrationContext
    ) async {
        await withRegistrationRetry("live_activity_token_registration_failed") {
            let request = RegisterLiveActivityTokenRequest(
                token: token,
                environment: tokenRegistration.environment,
                activityId: activity.id,
                activityKind: activity.attributes.activityKind.rawValue,
                tokenRole: nil,
                pinnedTrainServiceId: activity.attributes.pinnedTrainServiceID,
                frequentLiveActivityUpdatesEnabled: tokenRegistration.frequentLiveActivityUpdatesEnabled,
                clientDeviceId: tokenRegistration.clientDeviceID,
                appBundleId: tokenRegistration.appBundleID,
                appVersion: tokenRegistration.appVersion,
                buildNumber: tokenRegistration.buildNumber,
                deviceModel: tokenRegistration.deviceModel,
                osVersion: tokenRegistration.osVersion
            )
            if let itinerarySubscriptionID = activity.attributes.itinerarySubscriptionID,
               !itinerarySubscriptionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try await tokenRegistration.apiClient.registerItineraryLiveActivityToken(
                    itinerarySubscriptionID: itinerarySubscriptionID,
                    activityKind: activity.attributes.activityKind.rawValue,
                    input: request,
                    accessToken: tokenRegistration.accessToken
                )
            } else if let windowSubscriptionID = activity.attributes.windowSubscriptionID,
                      !windowSubscriptionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try await tokenRegistration.apiClient.registerLiveActivityToken(
                    windowSubscriptionID: windowSubscriptionID,
                    activityKind: activity.attributes.activityKind.rawValue,
                    input: request,
                    accessToken: tokenRegistration.accessToken
                )
            }
        }
    }

    private static func registerPushToStartToken(
        _ token: Data,
        tokenRegistration: LiveActivityTokenRegistrationContext
    ) async {
        await registerPushToStartTokenHex(hexString(token), tokenRegistration: tokenRegistration)
    }

    private static func registerPushToStartTokenHex(
        _ token: String,
        tokenRegistration: LiveActivityTokenRegistrationContext
    ) async {
        await withRegistrationRetry("live_activity_push_to_start_registration_failed") {
            try await tokenRegistration.apiClient.registerLiveActivityPushToStartToken(
                clientDeviceID: tokenRegistration.clientDeviceID,
                input: RegisterLiveActivityTokenRequest(
                    token: token,
                    environment: tokenRegistration.environment,
                    activityId: pushToStartActivityID(clientDeviceID: tokenRegistration.clientDeviceID),
                    activityKind: "window",
                    tokenRole: "push_to_start",
                    pinnedTrainServiceId: nil,
                    frequentLiveActivityUpdatesEnabled: tokenRegistration.frequentLiveActivityUpdatesEnabled,
                    clientDeviceId: tokenRegistration.clientDeviceID,
                    appBundleId: tokenRegistration.appBundleID,
                    appVersion: tokenRegistration.appVersion,
                    buildNumber: tokenRegistration.buildNumber,
                    deviceModel: tokenRegistration.deviceModel,
                    osVersion: tokenRegistration.osVersion
                ),
                accessToken: tokenRegistration.accessToken
            )
            try await tokenRegistration.apiClient.registerLiveActivityPushToStartToken(
                clientDeviceID: tokenRegistration.clientDeviceID,
                input: RegisterLiveActivityTokenRequest(
                    token: token,
                    environment: tokenRegistration.environment,
                    activityId: itineraryPushToStartActivityID(clientDeviceID: tokenRegistration.clientDeviceID),
                    activityKind: "itinerary",
                    tokenRole: "push_to_start",
                    pinnedTrainServiceId: nil,
                    frequentLiveActivityUpdatesEnabled: tokenRegistration.frequentLiveActivityUpdatesEnabled,
                    clientDeviceId: tokenRegistration.clientDeviceID,
                    appBundleId: tokenRegistration.appBundleID,
                    appVersion: tokenRegistration.appVersion,
                    buildNumber: tokenRegistration.buildNumber,
                    deviceModel: tokenRegistration.deviceModel,
                    osVersion: tokenRegistration.osVersion
                ),
                accessToken: tokenRegistration.accessToken
            )
        }
    }

    private static func deletePushTokenRegistration(
        for activity: Activity<RightTrainLiveActivityAttributes>,
        tokenRegistration: LiveActivityTokenRegistrationContext?
    ) async {
        guard let tokenRegistration else {
            return
        }

        do {
            if let itinerarySubscriptionID = activity.attributes.itinerarySubscriptionID,
               !itinerarySubscriptionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try await tokenRegistration.apiClient.deleteItineraryLiveActivityToken(
                    itinerarySubscriptionID: itinerarySubscriptionID,
                    activityKind: activity.attributes.activityKind.rawValue,
                    activityID: activity.id,
                    environment: tokenRegistration.environment,
                    accessToken: tokenRegistration.accessToken
                )
            } else if let windowSubscriptionID = activity.attributes.windowSubscriptionID,
                      !windowSubscriptionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try await tokenRegistration.apiClient.deleteLiveActivityToken(
                    windowSubscriptionID: windowSubscriptionID,
                    activityKind: activity.attributes.activityKind.rawValue,
                    activityID: activity.id,
                    environment: tokenRegistration.environment,
                    accessToken: tokenRegistration.accessToken
                )
            }
        } catch {
            BetaDiagnostics.record("live_activity_token_deletion_failed", details: error.localizedDescription, severity: .warning)
        }
    }

    private static func deletePushToStartTokenRegistration(
        tokenRegistration: LiveActivityTokenRegistrationContext?
    ) async {
        guard let tokenRegistration else {
            return
        }

        do {
            try await tokenRegistration.apiClient.deleteLiveActivityPushToStartToken(
                clientDeviceID: tokenRegistration.clientDeviceID,
                activityID: pushToStartActivityID(clientDeviceID: tokenRegistration.clientDeviceID),
                environment: tokenRegistration.environment,
                accessToken: tokenRegistration.accessToken
            )
            try await tokenRegistration.apiClient.deleteLiveActivityPushToStartToken(
                clientDeviceID: tokenRegistration.clientDeviceID,
                activityID: itineraryPushToStartActivityID(clientDeviceID: tokenRegistration.clientDeviceID),
                environment: tokenRegistration.environment,
                accessToken: tokenRegistration.accessToken
            )
        } catch {
            BetaDiagnostics.record("live_activity_push_to_start_deletion_failed", details: error.localizedDescription, severity: .warning)
        }
    }

    private static func nowText() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }

    private static func previewContentState(now: Date) -> RightTrainLiveActivityAttributes.ContentState {
        let departure = now.addingTimeInterval(12 * 60)
        let arrival = now.addingTimeInterval(95 * 60)
        let departureText = previewClockText(departure)
        let arrivalText = previewClockText(arrival)
        let train = RightTrainLiveActivityAttributes.ContentState.Train(
            serviceID: 9001,
            operatorName: "RightTrain Preview",
            operatorCode: nil,
            destinationName: "Manchester Piccadilly",
            scheduledDepartureTime: departureText,
            departureTime: departureText,
            scheduledDepartureDate: departure,
            departureDate: departure,
            departureDelayed: false,
            scheduledArrivalTime: arrivalText,
            arrivalTime: arrivalText,
            scheduledArrivalDate: arrival,
            arrivalDate: arrival,
            arrivalDelayed: false,
            departurePlatform: "4",
            arrivalPlatform: "7",
            departed: false,
            recommended: true,
            statusText: "Preview",
            statusKind: .good,
            delayMinutes: 0,
            journeyProgress: nil
        )

        return RightTrainLiveActivityAttributes.ContentState(
            windowSubscriptionID: Self.previewWindowSubscriptionID,
            itinerarySubscriptionID: nil,
            phase: "preview",
            recommendationServiceID: train.serviceID,
            routeTitle: "Euston to Manchester",
            originName: "London Euston",
            destinationName: "Manchester Piccadilly",
            originCrs: "EUS",
            destinationCrs: "MAN",
            departureTime: departureText,
            scheduledDepartureDate: departure,
            departureDate: departure,
            arrivalTime: arrivalText,
            scheduledArrivalDate: arrival,
            arrivalDate: arrival,
            platform: "4",
            platformConfirmed: true,
            statusText: "Preview",
            statusKind: .good,
            delayMinutes: 0,
            nextUpdateText: "Preview ends soon",
            updatedAtText: "Updated now",
            emptyStateText: nil,
            windowTimeRangeText: "Preview",
            windowTrainCount: 1,
            upcomingTrainCount: 1,
            departedTrainCount: 0,
            cancelledTrainCount: 0,
            otherDeparturesText: nil,
            trains: [train],
            pinnedTrainServiceID: nil,
            pinnedFirstLeg: nil
        )
    }

    private static func previewClockText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "Europe/London")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

#if DEBUG
enum LiveActivityPreviewScenario: String, CaseIterable {
    case windowOnTime = "window-on-time"
    case windowDelayed = "window-delayed"
    case windowPlatformChanged = "window-platform-changed"
    case windowStaleData = "window-stale-data"
    case windowOffline = "window-offline"
    case windowAlternativeNeeded = "window-alternative-needed"
    case trainPreDeparture = "train-pre-departure"
    case trainOnBoard = "train-on-board"
    case trainCancelled = "train-cancelled"
    case itineraryPlanning = "itinerary-planning"
    case itineraryAtRisk = "itinerary-at-risk"
    case itineraryCancelled = "itinerary-cancelled"
    case legMidJourney = "leg-mid-journey"
    case legApproachingInterchange = "leg-approaching-interchange"
    case legFinal = "leg-final"

    private static let previewWindowSubscriptionID = "righttrain-live-activity-preview"
    private static let previewItinerarySubscriptionID = "righttrain-live-activity-preview-itinerary"

    var activityKind: RightTrainLiveActivityAttributes.ActivityKind {
        switch self {
        case .windowOnTime, .windowDelayed, .windowPlatformChanged, .windowStaleData, .windowOffline, .windowAlternativeNeeded:
            return .window
        case .trainPreDeparture, .trainOnBoard, .trainCancelled:
            return .train
        case .itineraryPlanning, .itineraryAtRisk, .itineraryCancelled:
            return .itinerary
        case .legMidJourney, .legApproachingInterchange, .legFinal:
            return .leg
        }
    }

    func attributes(startedAtText: String) -> RightTrainLiveActivityAttributes {
        RightTrainLiveActivityAttributes(
            windowSubscriptionID: usesWindowSubscription ? Self.previewWindowSubscriptionID : nil,
            itinerarySubscriptionID: usesWindowSubscription ? nil : Self.previewItinerarySubscriptionID,
            activityKind: activityKind,
            pinnedTrainServiceID: pinnedTrainServiceID,
            originCrs: "EUS",
            destinationCrs: "MAN",
            startedAtText: startedAtText
        )
    }

    func state(now: Date) -> RightTrainLiveActivityAttributes.ContentState {
        switch self {
        case .windowOnTime:
            let train = previewTrain(
                serviceID: 10_001,
                destinationName: "Manchester Piccadilly",
                departureOffset: 12,
                arrivalOffset: 95,
                platform: "4",
                recommended: true,
                statusText: "On time",
                statusKind: .good,
                now: now
            )
            return contentState(
                now: now,
                statusText: "On time",
                statusKind: .good,
                trains: [train],
                recommendationServiceID: train.serviceID,
                upcomingTrainCount: 1
            )
        case .windowDelayed:
            let train = previewTrain(
                serviceID: 10_002,
                destinationName: "Manchester Piccadilly",
                departureOffset: 18,
                arrivalOffset: 110,
                platform: "1",
                departureDelay: 18,
                arrivalDelay: 18,
                recommended: true,
                statusText: "+18 Late",
                statusKind: .delayed,
                delayMinutes: 18,
                now: now
            )
            return contentState(
                now: now,
                statusText: "+18 Late",
                statusKind: .delayed,
                delayMinutes: 18,
                nextUpdateText: "Delayed 18 min",
                trains: [train],
                recommendationServiceID: train.serviceID,
                platformConfirmed: false,
                upcomingTrainCount: 1
            )
        case .windowPlatformChanged:
            let train = previewTrain(
                serviceID: 10_003,
                destinationName: "Manchester Piccadilly",
                departureOffset: 14,
                arrivalOffset: 98,
                platform: "12",
                recommended: true,
                statusText: "Platform changed",
                statusKind: .atRisk,
                delayMinutes: 0,
                now: now
            )
            var state = contentState(
                now: now,
                statusText: "Platform changed",
                statusKind: .atRisk,
                nextUpdateText: "Use platform 12",
                trains: [train],
                recommendationServiceID: train.serviceID,
                upcomingTrainCount: 1
            )
            state.platformChange = RightTrainLiveActivityAttributes.ContentState.PlatformChange(
                serviceID: train.serviceID,
                previousPlatform: "2",
                currentPlatform: "12",
                changedAtText: "Updated now"
            )
            return state
        case .windowStaleData:
            let train = previewTrain(
                serviceID: 10_004,
                destinationName: "Manchester Piccadilly",
                departureOffset: 16,
                arrivalOffset: 100,
                platform: "TBC",
                recommended: true,
                statusText: "Update delayed",
                statusKind: .unreported,
                now: now
            )
            var state = contentState(
                now: now,
                statusText: "Update delayed",
                statusKind: .unreported,
                nextUpdateText: "Check before boarding",
                trains: [train],
                recommendationServiceID: train.serviceID,
                platformConfirmed: false,
                upcomingTrainCount: 1
            )
            state.updatedAtText = "Updated 18 min ago"
            return state
        case .windowOffline:
            let train = previewTrain(
                serviceID: 10_005,
                destinationName: "Manchester Piccadilly",
                departureOffset: 18,
                arrivalOffset: 102,
                platform: "4",
                recommended: true,
                statusText: "Offline",
                statusKind: .unreported,
                now: now
            )
            var state = contentState(
                now: now,
                statusText: "Offline",
                statusKind: .unreported,
                nextUpdateText: "Last known on time",
                trains: [train],
                recommendationServiceID: train.serviceID,
                platformConfirmed: false,
                upcomingTrainCount: 1
            )
            state.updatedAtText = "Last updated 20 min ago"
            return state
        case .windowAlternativeNeeded:
            let cancelled = previewTrain(
                serviceID: 10_006,
                destinationName: "Manchester Piccadilly",
                departureOffset: 12,
                arrivalOffset: 92,
                platform: "4",
                recommended: true,
                statusText: "Cancelled",
                statusKind: .cancelled,
                now: now
            )
            let nextBest = previewTrain(
                serviceID: 10_007,
                destinationName: "Manchester Piccadilly",
                departureOffset: 38,
                arrivalOffset: 120,
                platform: "5",
                recommended: false,
                statusText: "Next best",
                statusKind: .good,
                now: now
            )
            return contentState(
                now: now,
                statusText: "Use next best",
                statusKind: .cancelled,
                nextUpdateText: "Next best departs \(nextBest.departureTime)",
                trains: [cancelled, nextBest],
                recommendationServiceID: cancelled.serviceID,
                windowTrainCount: 2,
                upcomingTrainCount: 1,
                cancelledTrainCount: 1,
                otherDeparturesText: "Next best \(nextBest.departureTime) from platform \(nextBest.departurePlatform)"
            )
        case .trainPreDeparture:
            let train = previewTrain(
                serviceID: 11_001,
                destinationName: "Manchester Piccadilly",
                departureOffset: 16,
                arrivalOffset: 92,
                platform: "4",
                recommended: true,
                statusText: "On time",
                statusKind: .good,
                now: now
            )
            return contentState(
                now: now,
                statusText: "On time",
                statusKind: .good,
                trains: [train],
                recommendationServiceID: train.serviceID,
                upcomingTrainCount: 1,
                pinnedTrainServiceID: train.serviceID
            )
        case .trainOnBoard:
            var train = previewTrain(
                serviceID: 11_002,
                destinationName: "Moorgate",
                departureOffset: -22,
                arrivalOffset: 18,
                platform: "1",
                departed: true,
                recommended: true,
                statusText: "On board",
                statusKind: .departed,
                now: now
            )
            train.journeyProgress = 0.76
            return contentState(
                now: now,
                statusText: "On board",
                statusKind: .departed,
                nextUpdateText: "On board",
                trains: [train],
                recommendationServiceID: train.serviceID,
                upcomingTrainCount: 0,
                departedTrainCount: 1,
                pinnedTrainServiceID: train.serviceID
            )
        case .trainCancelled:
            let train = previewTrain(
                serviceID: 11_003,
                destinationName: "Manchester Piccadilly",
                departureOffset: 16,
                arrivalOffset: 92,
                platform: "4",
                recommended: true,
                statusText: "Cancelled",
                statusKind: .cancelled,
                now: now
            )
            return contentState(
                now: now,
                statusText: "Cancelled",
                statusKind: .cancelled,
                nextUpdateText: "Service cancelled",
                trains: [train],
                recommendationServiceID: train.serviceID,
                upcomingTrainCount: 0,
                cancelledTrainCount: 1,
                pinnedTrainServiceID: train.serviceID
            )
        case .itineraryPlanning:
            let trains = [
                previewTrain(serviceID: 12_001, destinationName: "Crewe", departureOffset: 8, arrivalOffset: 44, platform: "4", recommended: true, statusText: "On time", statusKind: .good, now: now),
                previewTrain(serviceID: 12_002, destinationName: "Manchester Piccadilly", departureOffset: 58, arrivalOffset: 100, platform: "7", statusText: "On time", statusKind: .good, now: now)
            ]
            return contentState(
                now: now,
                phase: "planning",
                statusText: "Planned",
                statusKind: .good,
                trains: trains,
                recommendationServiceID: trains[0].serviceID,
                windowTrainCount: trains.count,
                upcomingTrainCount: trains.count,
                otherDeparturesText: "Change at Crewe - 14 min"
            )
        case .itineraryAtRisk:
            let trains = [
                previewTrain(serviceID: 12_101, destinationName: "Crewe", departureOffset: 8, arrivalOffset: 44, platform: "4", recommended: true, statusText: "On time", statusKind: .good, now: now),
                previewTrain(serviceID: 12_102, destinationName: "Wilmslow", departureOffset: 47, arrivalOffset: 70, platform: "6", statusText: "Tight", statusKind: .atRisk, delayMinutes: 3, now: now),
                previewTrain(serviceID: 12_103, destinationName: "Manchester Piccadilly", departureOffset: 76, arrivalOffset: 95, platform: "2", statusText: "On time", statusKind: .good, now: now)
            ]
            return contentState(
                now: now,
                phase: "planning",
                statusText: "Connection at risk",
                statusKind: .atRisk,
                delayMinutes: 3,
                trains: trains,
                recommendationServiceID: trains[0].serviceID,
                windowTrainCount: trains.count,
                upcomingTrainCount: trains.count,
                otherDeparturesText: "Change at Crewe - 3 min"
            )
        case .itineraryCancelled:
            let trains = [
                previewTrain(serviceID: 12_201, destinationName: "Crewe", departureOffset: 10, arrivalOffset: 42, platform: "4", recommended: true, statusText: "On time", statusKind: .good, now: now),
                previewTrain(serviceID: 12_202, destinationName: "Manchester Piccadilly", departureOffset: 55, arrivalOffset: 95, platform: "7", statusText: "Cancelled", statusKind: .cancelled, now: now)
            ]
            return contentState(
                now: now,
                phase: "planning",
                statusText: "Cancelled",
                statusKind: .cancelled,
                nextUpdateText: "Middle leg cancelled",
                trains: trains,
                recommendationServiceID: trains[0].serviceID,
                windowTrainCount: trains.count,
                upcomingTrainCount: 1,
                cancelledTrainCount: 1
            )
        case .legMidJourney:
            var current = previewTrain(serviceID: 13_001, destinationName: "Crewe", departureOffset: -20, arrivalOffset: 25, platform: "4", departed: true, recommended: true, statusText: "On board", statusKind: .departed, now: now)
            current.journeyProgress = 0.6
            let onward = previewTrain(serviceID: 13_002, destinationName: "Manchester Piccadilly", departureOffset: 38, arrivalOffset: 88, platform: "7", statusText: "On time", statusKind: .good, now: now)
            let interchange = previewInterchange(current: current, onward: onward, riskStatus: "ok", expectedMarginMinutes: 8)
            return contentState(
                now: now,
                phase: "on_leg",
                statusText: "On board",
                statusKind: .departed,
                nextUpdateText: "Change at Crewe",
                trains: [current, onward],
                recommendationServiceID: current.serviceID,
                windowTrainCount: 2,
                upcomingTrainCount: 1,
                departedTrainCount: 1,
                otherDeparturesText: "Change at Crewe",
                currentLegIndex: 0,
                onwardLeg: onward,
                interchange: interchange
            )
        case .legApproachingInterchange:
            var current = previewTrain(serviceID: 13_101, destinationName: "Crewe", departureOffset: -42, arrivalOffset: 3, platform: "4", departed: true, recommended: true, statusText: "Arriving", statusKind: .departed, now: now)
            current.journeyProgress = 0.94
            let onward = previewTrain(serviceID: 13_102, destinationName: "Manchester Piccadilly", departureOffset: 10, arrivalOffset: 60, platform: "7", statusText: "On time", statusKind: .good, now: now)
            let interchange = previewInterchange(current: current, onward: onward, riskStatus: "at_risk", expectedMarginMinutes: 2)
            return contentState(
                now: now,
                phase: "approaching_interchange",
                statusText: "Change at Crewe",
                statusKind: .atRisk,
                nextUpdateText: "Get off at next stop",
                trains: [current, onward],
                recommendationServiceID: current.serviceID,
                windowTrainCount: 2,
                upcomingTrainCount: 1,
                departedTrainCount: 1,
                otherDeparturesText: "Get off at Crewe",
                currentLegIndex: 0,
                onwardLeg: onward,
                interchange: interchange
            )
        case .legFinal:
            var first = previewTrain(serviceID: 13_201, destinationName: "Crewe", departureOffset: -70, arrivalOffset: -25, platform: "4", departed: true, statusText: "Arrived", statusKind: .arrived, now: now)
            first.journeyProgress = 1
            var current = previewTrain(serviceID: 13_202, destinationName: "Manchester Piccadilly", departureOffset: -15, arrivalOffset: 38, platform: "7", departed: true, recommended: true, statusText: "On board", statusKind: .departed, now: now)
            current.journeyProgress = 0.4
            return contentState(
                now: now,
                phase: "on_final_leg",
                statusText: "On board",
                statusKind: .departed,
                nextUpdateText: "On the final train",
                trains: [first, current],
                recommendationServiceID: current.serviceID,
                windowTrainCount: 2,
                upcomingTrainCount: 0,
                departedTrainCount: 2,
                otherDeparturesText: "On the final train",
                currentLegIndex: 1
            )
        }
    }

    private var usesWindowSubscription: Bool {
        activityKind == .window || activityKind == .train
    }

    private var pinnedTrainServiceID: Int? {
        switch self {
        case .trainPreDeparture:
            return 11_001
        case .trainOnBoard:
            return 11_002
        case .trainCancelled:
            return 11_003
        default:
            return nil
        }
    }

    private func contentState(
        now: Date,
        phase: String? = nil,
        statusText: String,
        statusKind: RightTrainLiveActivityAttributes.StatusKind,
        delayMinutes: Int = 0,
        nextUpdateText: String = "Updated now",
        trains: [RightTrainLiveActivityAttributes.ContentState.Train],
        recommendationServiceID: Int,
        platformConfirmed: Bool = true,
        windowTrainCount: Int? = 1,
        upcomingTrainCount: Int? = 0,
        departedTrainCount: Int? = 0,
        cancelledTrainCount: Int? = 0,
        otherDeparturesText: String? = nil,
        pinnedTrainServiceID: Int? = nil,
        currentLegIndex: Int? = nil,
        onwardLeg: RightTrainLiveActivityAttributes.ContentState.Train? = nil,
        interchange: RightTrainLiveActivityAttributes.ContentState.Interchange? = nil
    ) -> RightTrainLiveActivityAttributes.ContentState {
        let first = trains.first
        let focused = currentLegIndex.flatMap { index in
            trains.indices.contains(index) ? trains[index] : nil
        } ?? first
        let last = onwardLeg ?? focused ?? trains.last ?? first

        return RightTrainLiveActivityAttributes.ContentState(
            windowSubscriptionID: usesWindowSubscription ? Self.previewWindowSubscriptionID : nil,
            itinerarySubscriptionID: usesWindowSubscription ? nil : Self.previewItinerarySubscriptionID,
            phase: phase ?? activityKind.rawValue,
            recommendationServiceID: recommendationServiceID,
            routeTitle: activityKind == .train && self == .trainOnBoard ? "New Barnet to Moorgate" : "Euston to Manchester",
            originName: activityKind == .train && self == .trainOnBoard ? "New Barnet" : "London Euston",
            originShortName: activityKind == .train && self == .trainOnBoard ? "New Barnet" : "Euston",
            destinationName: activityKind == .train && self == .trainOnBoard ? "Moorgate" : "Manchester Piccadilly",
            destinationShortName: activityKind == .train && self == .trainOnBoard ? "Moorgate" : "Man Piccadilly",
            originCrs: activityKind == .train && self == .trainOnBoard ? "NBA" : "EUS",
            destinationCrs: activityKind == .train && self == .trainOnBoard ? "MOG" : "MAN",
            departureTime: focused?.departureTime ?? "--:--",
            scheduledDepartureDate: focused?.scheduledDepartureDate,
            departureDate: focused?.departureDate,
            arrivalTime: last?.arrivalTime ?? "--:--",
            scheduledArrivalDate: last?.scheduledArrivalDate,
            arrivalDate: last?.arrivalDate,
            platform: focused?.departurePlatform ?? "TBC",
            platformConfirmed: platformConfirmed,
            statusText: statusText,
            statusKind: statusKind,
            delayMinutes: delayMinutes,
            nextUpdateText: nextUpdateText,
            updatedAtText: "Updated now",
            emptyStateText: nil,
            windowTimeRangeText: "09:30 - 11:30",
            windowTrainCount: windowTrainCount,
            upcomingTrainCount: upcomingTrainCount,
            departedTrainCount: departedTrainCount,
            cancelledTrainCount: cancelledTrainCount,
            otherDeparturesText: otherDeparturesText,
            trains: trains,
            pinnedTrainServiceID: pinnedTrainServiceID,
            pinnedFirstLeg: pinnedFirstLeg(from: trains.first),
            currentLegIndex: currentLegIndex,
            onwardLeg: onwardLeg,
            interchange: interchange
        )
    }

    private func pinnedFirstLeg(
        from train: RightTrainLiveActivityAttributes.ContentState.Train?
    ) -> RightTrainLiveActivityAttributes.ContentState.PinnedFirstLeg? {
        guard self == .legMidJourney || self == .legApproachingInterchange || self == .legFinal,
              let train else {
            return nil
        }
        return RightTrainLiveActivityAttributes.ContentState.PinnedFirstLeg(
            serviceID: train.serviceID,
            rid: "preview-\(train.serviceID)",
            ssd: "2030-01-10",
            originName: "London Euston",
            originShortName: "Euston",
            destinationName: "Crewe",
            destinationShortName: "Crewe",
            scheduledDepartureTime: train.scheduledDepartureTime,
            departureTime: train.departureTime,
            scheduledDepartureDate: train.scheduledDepartureDate,
            departureDate: train.departureDate,
            scheduledArrivalTime: train.scheduledArrivalTime,
            arrivalTime: train.arrivalTime,
            scheduledArrivalDate: train.scheduledArrivalDate,
            arrivalDate: train.arrivalDate
        )
    }

    private func previewInterchange(
        current: RightTrainLiveActivityAttributes.ContentState.Train,
        onward: RightTrainLiveActivityAttributes.ContentState.Train,
        riskStatus: String,
        expectedMarginMinutes: Int
    ) -> RightTrainLiveActivityAttributes.ContentState.Interchange {
        RightTrainLiveActivityAttributes.ContentState.Interchange(
            crs: "CRE",
            name: "Crewe",
            legIndex: 0,
            scheduledArrivalDate: current.scheduledArrivalDate,
            expectedArrivalDate: current.arrivalDate,
            scheduledDepartureDate: onward.scheduledDepartureDate,
            expectedDepartureDate: onward.departureDate,
            requiredTransferMinutes: 5,
            expectedMarginMinutes: expectedMarginMinutes,
            riskStatus: riskStatus,
            onwardPlatform: onward.departurePlatform,
            onwardPlatformConfirmed: true
        )
    }

    private func previewTrain(
        serviceID: Int,
        destinationName: String,
        departureOffset: Int,
        arrivalOffset: Int,
        platform: String,
        departureDelay: Int = 0,
        arrivalDelay: Int = 0,
        departed: Bool = false,
        recommended: Bool = false,
        statusText: String,
        statusKind: RightTrainLiveActivityAttributes.StatusKind,
        delayMinutes: Int = 0,
        now: Date
    ) -> RightTrainLiveActivityAttributes.ContentState.Train {
        let scheduledDeparture = now.addingTimeInterval(TimeInterval(departureOffset) * 60)
        let scheduledArrival = now.addingTimeInterval(TimeInterval(arrivalOffset) * 60)
        let departure = scheduledDeparture.addingTimeInterval(TimeInterval(departureDelay) * 60)
        let arrival = scheduledArrival.addingTimeInterval(TimeInterval(arrivalDelay) * 60)
        return RightTrainLiveActivityAttributes.ContentState.Train(
            serviceID: serviceID,
            operatorName: serviceID == 11_002 ? "Great Northern" : "Avanti West Coast",
            operatorCode: serviceID == 11_002 ? "GN" : "VT",
            destinationName: destinationName,
            destinationShortName: destinationName == "Manchester Piccadilly" ? "Man Piccadilly" : destinationName,
            scheduledDepartureTime: clockText(scheduledDeparture),
            departureTime: clockText(departure),
            scheduledDepartureDate: scheduledDeparture,
            departureDate: departure,
            departureDelayed: departureDelay > 0,
            scheduledArrivalTime: clockText(scheduledArrival),
            arrivalTime: clockText(arrival),
            scheduledArrivalDate: scheduledArrival,
            arrivalDate: arrival,
            arrivalDelayed: arrivalDelay > 0,
            departurePlatform: platform,
            arrivalPlatform: platform == "TBC" ? "TBC" : "\(max((Int(platform) ?? 1) + 1, 1))",
            departed: departed,
            recommended: recommended,
            statusText: statusText,
            statusKind: statusKind,
            delayMinutes: delayMinutes,
            journeyProgress: departed ? 0.35 : nil
        )
    }

    private func clockText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "Europe/London")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

struct LiveActivityPreviewLaunch {
    private enum Request {
        case start(LiveActivityPreviewScenario)
        case end
    }

    private var request: Request

    init?(arguments: [String]) {
        let rawValue = arguments
            .first { $0.hasPrefix("--righttrain-live-activity-preview=") }
            .flatMap { $0.split(separator: "=", maxSplits: 1).last }
            .map(String.init)

        guard let rawValue else {
            return nil
        }

        if rawValue == "end" {
            request = .end
        } else if let scenario = LiveActivityPreviewScenario(rawValue: rawValue) {
            request = .start(scenario)
        } else {
            return nil
        }
    }

    func start() async {
        switch request {
        case .start(let scenario):
            _ = await SystemLiveActivityCoordinator().previewLiveActivity(scenario: scenario)
        case .end:
            await SystemLiveActivityCoordinator.endPreviewLiveActivities()
        }
    }
}
#endif

enum RightTrainLiveActivityStateBuilder {
    static func state(
        for window: WindowSubscription,
        pinnedTrainServiceID: Int?,
        activityKind: RightTrainLiveActivityAttributes.ActivityKind = .window,
        now: Date = Date()
    ) -> RightTrainLiveActivityAttributes.ContentState {
        let rawRecommendations = window.recommendations.isEmpty ? [window.selectedRecommendation] : window.recommendations
        let recommendations = JourneyFormatting.chronologicalRecommendations(
            rawRecommendations.filter { $0.journey.serviceId != 0 }
        )
        let trainCandidates = recommendations.map { trainCandidate(for: $0, now: now) }
        let allTrains = trainCandidates.map(\.train)
        let recommendation = selectedRecommendation(
            from: recommendations,
            fallback: window.selectedRecommendation,
            pinnedTrainServiceID: pinnedTrainServiceID
        )
        let selectedTrainCandidate = trainCandidates.first { $0.train.serviceID == recommendation.journey.serviceId }
            ?? trainCandidate(for: recommendation, now: now)
        let journey = recommendation.journey
        let statusKind = statusKind(for: recommendation, now: now)
        let platform = JourneyFormatting.platformText(journey)
        let statusDelayMinutes = JourneyFormatting.statusDelayMinutes(journey: journey, score: recommendation.score)
        let emptyStateText = activityKind == .window ? emptyStateText(for: allTrains) : nil
        let phase = window.phase ?? "window"
        let visibleTrains: [RightTrainLiveActivityAttributes.ContentState.Train]
        if selectedTrainCandidate.train.serviceID != 0 && (activityKind == .train || emptyStateText == nil) {
            visibleTrains = [selectedTrainCandidate.train]
        } else {
            visibleTrains = []
        }
        let otherDepartures = activityKind == .window && pinnedTrainServiceID == nil
            ? otherDeparturesText(from: trainCandidates, selectedServiceID: selectedTrainCandidate.train.serviceID)
            : nil
        let activityStatusKind = emptyStateText.map(emptyStatusKind(for:)) ?? statusKind
        let activityStatusText = emptyStateText ?? statusText(for: recommendation, statusKind: statusKind, now: now)
        let activityNextUpdateText = emptyStateText.map(emptyNextUpdateText(for:))
            ?? nextUpdateText(for: recommendation, platform: platform, phase: phase, now: now)

        return RightTrainLiveActivityAttributes.ContentState(
            windowSubscriptionID: window.id,
            phase: phase,
            recommendationServiceID: emptyStateText == nil ? journey.serviceId : 0,
            routeTitle: routeTitle(for: window, journey: journey),
            originName: JourneyFormatting.originStationText(journey),
            originShortName: JourneyFormatting.compactOriginStationText(journey),
            destinationName: JourneyFormatting.destinationStationText(journey),
            destinationShortName: JourneyFormatting.compactDestinationStationText(journey),
            originCrs: nonEmpty(journey.originCrs) ?? window.originCrs,
            destinationCrs: nonEmpty(journey.destinationCrs) ?? window.destinationCrs,
            departureTime: JourneyFormatting.departureText(journey),
            scheduledDepartureDate: selectedTrainCandidate.train.scheduledDepartureDate,
            departureDate: selectedTrainCandidate.train.departureDate,
            arrivalTime: JourneyFormatting.arrivalText(journey),
            scheduledArrivalDate: selectedTrainCandidate.train.scheduledArrivalDate,
            arrivalDate: selectedTrainCandidate.train.arrivalDate,
            platform: platform,
            platformConfirmed: journey.realtimePlatformConfirmed || journey.originRealtime?.platformConfirmed == true,
            statusText: activityStatusText,
            statusKind: activityStatusKind,
            delayMinutes: statusDelayMinutes,
            nextUpdateText: activityNextUpdateText,
            updatedAtText: updateText(for: recommendations),
            emptyStateText: emptyStateText,
            windowTimeRangeText: windowTimeRangeText(for: window, trainCount: allTrains.count),
            windowTrainCount: allTrains.count,
            upcomingTrainCount: allTrains.filter { !$0.departed && $0.statusKind != .cancelled && $0.statusKind != .arrived }.count,
            departedTrainCount: allTrains.filter(\.departed).count,
            cancelledTrainCount: allTrains.filter { $0.statusKind == .cancelled }.count,
            otherDeparturesText: otherDepartures,
            trains: visibleTrains,
            pinnedTrainServiceID: pinnedTrainServiceID
        )
    }

    static func state(
        for itinerary: ItinerarySubscription,
        now: Date = Date()
    ) -> RightTrainLiveActivityAttributes.ContentState {
        let recommendations = itinerary.itineraries.isEmpty ? [itinerary.selectedItinerary] : itinerary.itineraries
        let selected = recommendations.first(where: \.recommended) ?? itinerary.selectedItinerary
        let trainCandidates = selected.legs.map { trainCandidate(for: $0, now: now) }
        let trains = trainCandidates.map(\.train)
        let phase = itinerary.resolvedPhase
        let firstLeg = selected.legs.first
        let lastLeg = selected.legs.last

        // Focused-leg selection: once boarded, headline times track the
        // CURRENT leg rather than the journey's bookends.
        let focusedLeg: ItineraryLeg?
        switch phase {
        case .planning, .atOrigin:
            focusedLeg = firstLeg
        case .onLeg, .approachingInterchange, .onFinalLeg:
            focusedLeg = itinerary.currentLeg ?? firstLeg
        }
        let focusedTrain = focusedLeg.flatMap { leg in
            trains.first(where: { $0.serviceID == leg.serviceId })
        }

        let onwardLeg = itinerary.onwardLeg
        let onwardTrain = onwardLeg.flatMap { leg in
            trains.first(where: { $0.serviceID == leg.serviceId })
        }
        let interchange: RightTrainLiveActivityAttributes.ContentState.Interchange?
        switch phase {
        case .onLeg, .approachingInterchange:
            interchange = itinerary.nextConnection.map { liveActivityInterchange($0, onward: onwardLeg) }
        case .planning, .atOrigin, .onFinalLeg:
            interchange = nil
        }

        let statusKind = itineraryStatusKind(for: selected, trains: trains)
        let statusText = itineraryStatusText(for: selected, statusKind: statusKind)
        let routeTitle = itineraryRouteTitle(for: itinerary, selected: selected)
        let emptyStateText = selected.legs.isEmpty ? "No route available" : nil

        return RightTrainLiveActivityAttributes.ContentState(
            windowSubscriptionID: nil,
            itinerarySubscriptionID: itinerary.id,
            phase: itinerary.phase,
            recommendationServiceID: focusedLeg?.serviceId ?? 0,
            routeTitle: routeTitle,
            originName: firstLeg.map(originStationText) ?? itinerary.originCrs,
            originShortName: firstLeg.map(compactOriginStationText),
            destinationName: lastLeg.map(destinationStationText) ?? itinerary.destinationCrs,
            destinationShortName: lastLeg.map(compactDestinationStationText),
            originCrs: nonEmpty(firstLeg?.originCrs) ?? itinerary.originCrs,
            destinationCrs: nonEmpty(lastLeg?.destinationCrs) ?? itinerary.destinationCrs,
            departureTime: focusedLeg.map { JourneyFormatting.departureText($0.journeyResult) } ?? "",
            scheduledDepartureDate: focusedTrain?.scheduledDepartureDate ?? trains.first?.scheduledDepartureDate,
            departureDate: focusedTrain?.departureDate ?? trains.first?.departureDate,
            arrivalTime: focusedLeg.map { JourneyFormatting.arrivalText($0.journeyResult) } ?? "",
            scheduledArrivalDate: focusedTrain?.scheduledArrivalDate ?? trains.last?.scheduledArrivalDate,
            arrivalDate: focusedTrain?.arrivalDate ?? trains.last?.arrivalDate,
            platform: focusedLeg.map { JourneyFormatting.platformText($0.journeyResult) } ?? "",
            platformConfirmed: focusedLeg?.realtimePlatformConfirmed == true || focusedLeg?.originRealtime?.platformConfirmed == true,
            statusText: emptyStateText ?? statusText,
            statusKind: emptyStateText == nil ? statusKind : .unknown,
            delayMinutes: selected.delayMinutes ?? selected.score.delayMinutes,
            nextUpdateText: itineraryNextUpdateText(for: selected, statusKind: statusKind),
            updatedAtText: itineraryUpdateText(for: selected),
            emptyStateText: emptyStateText,
            windowTimeRangeText: ItineraryFormatting.changesText(selected),
            windowTrainCount: trains.count,
            upcomingTrainCount: trains.filter { !$0.departed && $0.statusKind != .cancelled && $0.statusKind != .arrived }.count,
            departedTrainCount: trains.filter(\.departed).count,
            cancelledTrainCount: trains.filter { $0.statusKind == .cancelled }.count,
            otherDeparturesText: itineraryOtherDeparturesText(for: phase, selected: selected, interchange: interchange),
            trains: trains,
            pinnedTrainServiceID: nil,
            pinnedFirstLeg: itinerary.pinnedFirstLeg.map(liveActivityPinnedFirstLeg),
            currentLegIndex: itinerary.currentLegIndex,
            onwardLeg: onwardTrain,
            interchange: interchange
        )
    }

    private static func itineraryOtherDeparturesText(
        for phase: ItineraryPhase,
        selected: ItineraryRecommendation,
        interchange: RightTrainLiveActivityAttributes.ContentState.Interchange?
    ) -> String? {
        switch phase {
        case .planning:
            return itineraryConnectionSummaryText(for: selected)
        case .atOrigin:
            return "At the station"
        case .onLeg:
            if let interchange {
                return interchange.transferTitle ?? "Change at \(interchange.name)"
            }
            return itineraryConnectionSummaryText(for: selected)
        case .approachingInterchange:
            if let interchange {
                return "Get off at \(interchange.name)"
            }
            return "Approaching the change"
        case .onFinalLeg:
            return "On the final train"
        }
    }

    private static func liveActivityInterchange(
        _ connection: ItineraryConnection,
        onward: ItineraryLeg?
    ) -> RightTrainLiveActivityAttributes.ContentState.Interchange {
        let onwardPlatform: String? = {
            let candidate = onward?.realtimePlatform?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? onward?.originPlatform?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let candidate, !candidate.isEmpty else { return nil }
            return candidate
        }()
        let onwardPlatformConfirmed = onward?.realtimePlatformConfirmed == true
            || onward?.originRealtime?.platformConfirmed == true
        let name = JourneyFormatting.stationDisplayName(name: connection.atName, fallback: connection.atCrs)
        return RightTrainLiveActivityAttributes.ContentState.Interchange(
            crs: connection.atCrs,
            name: name,
            legIndex: connection.fromLegIndex,
            scheduledArrivalDate: DateFormatting.date(from: connection.scheduledArrival),
            expectedArrivalDate: DateFormatting.date(from: connection.expectedArrival),
            scheduledDepartureDate: DateFormatting.date(from: connection.scheduledDeparture),
            expectedDepartureDate: DateFormatting.date(from: connection.expectedDeparture),
            requiredTransferMinutes: connection.requiredTransferMinutes,
            expectedMarginMinutes: connection.expectedMarginMinutes,
            riskStatus: connection.risk.status,
            onwardPlatform: onwardPlatform,
            onwardPlatformConfirmed: onwardPlatformConfirmed,
            transferTitle: ItineraryFormatting.connectionTitleText(connection)
        )
    }

    private static func emptyStateText(for trains: [RightTrainLiveActivityAttributes.ContentState.Train]) -> String? {
        guard !trains.isEmpty else {
            return "No trains available"
        }
        guard !trains.contains(where: { !$0.departed && $0.statusKind != .cancelled && $0.statusKind != .arrived }) else {
            return nil
        }
        let departedOrArrivedCount = trains.filter { $0.departed || $0.statusKind == .arrived }.count
        if departedOrArrivedCount == trains.count {
            return "All trains departed"
        }
        if trains.allSatisfy({ $0.statusKind == .cancelled }) {
            return "All trains cancelled"
        }
        return "No trains available"
    }

    private static func emptyStatusKind(for emptyStateText: String) -> RightTrainLiveActivityAttributes.StatusKind {
        switch emptyStateText {
        case "All trains departed":
            return .departed
        case "All trains cancelled":
            return .cancelled
        default:
            return .unknown
        }
    }

    private static func liveActivityStatusKind(_ rawValue: String?) -> RightTrainLiveActivityAttributes.StatusKind? {
        guard let value = nonEmpty(rawValue) else {
            return nil
        }
        return RightTrainLiveActivityAttributes.StatusKind(rawValue: value)
    }

    private static func emptyNextUpdateText(for emptyStateText: String) -> String {
        switch emptyStateText {
        case "All trains departed":
            return "Window complete"
        case "All trains cancelled":
            return "No available trains in this window"
        default:
            return "No trains in this window"
        }
    }

    private static func routeTitle(for window: WindowSubscription, journey: JourneyResult) -> String {
        let origin = JourneyFormatting.stationDisplayName(
            name: journey.originName,
            fallback: window.originCrs
        )
        let destination = JourneyFormatting.stationDisplayName(
            name: journey.destinationName,
            fallback: window.destinationCrs
        )
        return "\(origin) to \(destination)"
    }

    private static func originStationText(_ leg: ItineraryLeg) -> String {
        JourneyFormatting.stationDisplayName(
            name: leg.originName,
            fallback: leg.originCrs
        )
    }

    private static func destinationStationText(_ leg: ItineraryLeg) -> String {
        JourneyFormatting.stationDisplayName(
            name: leg.destinationName,
            fallback: leg.destinationCrs
        )
    }

    private static func compactOriginStationText(_ leg: ItineraryLeg) -> String {
        JourneyFormatting.compactStationDisplayName(
            shortName: leg.originSixteenCharacterName,
            name: leg.originName,
            fallback: leg.originCrs
        )
    }

    private static func compactDestinationStationText(_ leg: ItineraryLeg) -> String {
        JourneyFormatting.compactStationDisplayName(
            shortName: leg.destinationSixteenCharacterName,
            name: leg.destinationName,
            fallback: leg.destinationCrs
        )
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private struct TrainCandidate {
        var train: RightTrainLiveActivityAttributes.ContentState.Train
        var departureSortDate: Date?
        var arrivalSortDate: Date?
    }

    private static func trainCandidate(
        for recommendation: DirectWindowRecommendation,
        now: Date
    ) -> TrainCandidate {
        let journey = recommendation.journey
        let departure = JourneyFormatting.departureDisplay(journey)
        let arrival = JourneyFormatting.arrivalDisplay(journey)
        let statusKind = statusKind(for: recommendation, now: now)
        let statusDelayMinutes = JourneyFormatting.statusDelayMinutes(journey: journey, score: recommendation.score)
        let departed = JourneyFormatting.isDeparted(journey)

        return TrainCandidate(
            train: RightTrainLiveActivityAttributes.ContentState.Train(
                serviceID: journey.serviceId,
                operatorName: journey.operatorName,
                operatorCode: journey.toc,
                destinationName: JourneyFormatting.destinationStationText(journey),
                destinationShortName: JourneyFormatting.compactDestinationStationText(journey),
                serviceDestinationName: JourneyFormatting.finalDestinationText(journey),
                serviceDestinationShortName: JourneyFormatting.compactFinalDestinationText(journey),
                scheduledDepartureTime: departure.scheduledText,
                departureTime: departure.currentText ?? departure.scheduledText,
                scheduledDepartureDate: departure.scheduledDate,
                departureDate: departure.currentDate ?? departure.scheduledDate,
                departureDelayed: departure.isDelayed,
                scheduledArrivalTime: arrival.scheduledText,
                arrivalTime: arrival.currentText ?? arrival.scheduledText,
                scheduledArrivalDate: arrival.scheduledDate,
                arrivalDate: arrival.currentDate ?? arrival.scheduledDate,
                arrivalDelayed: arrival.isDelayed,
                departurePlatform: JourneyFormatting.platformText(journey),
                arrivalPlatform: JourneyFormatting.arrivalPlatformText(journey),
                departed: departed,
                recommended: recommendation.recommended,
                statusText: nonEmpty(journey.compactStatusText) ?? trainStatusText(for: recommendation, statusKind: statusKind, now: now),
                statusKind: statusKind,
                delayMinutes: statusDelayMinutes,
                journeyProgress: journeyProgress(
                    departureDate: departure.currentDate ?? departure.scheduledDate,
                    arrivalDate: arrival.currentDate ?? arrival.scheduledDate,
                    now: now,
                    departed: departed,
                    statusKind: statusKind
                )
            ),
            departureSortDate: departure.currentDate ?? departure.scheduledDate,
            arrivalSortDate: arrival.currentDate ?? arrival.scheduledDate
        )
    }

    private static func trainCandidate(
        for leg: ItineraryLeg,
        now: Date
    ) -> TrainCandidate {
        let journey = leg.journeyResult
        let departure = JourneyFormatting.departureDisplay(journey)
        let arrival = JourneyFormatting.arrivalDisplay(journey)
        let statusKind = itineraryLegStatusKind(for: leg, now: now)
        let delayMinutes = leg.delayMinutes ?? journey.delayMinutes ?? 0
        let departed = JourneyFormatting.isDeparted(journey)

        return TrainCandidate(
            train: RightTrainLiveActivityAttributes.ContentState.Train(
                serviceID: leg.serviceId,
                operatorName: leg.operatorName,
                operatorCode: leg.toc,
                destinationName: destinationStationText(leg),
                destinationShortName: compactDestinationStationText(leg),
                scheduledDepartureTime: departure.scheduledText,
                departureTime: departure.currentText ?? departure.scheduledText,
                scheduledDepartureDate: departure.scheduledDate,
                departureDate: departure.currentDate ?? departure.scheduledDate,
                departureDelayed: departure.isDelayed,
                scheduledArrivalTime: arrival.scheduledText,
                arrivalTime: arrival.currentText ?? arrival.scheduledText,
                scheduledArrivalDate: arrival.scheduledDate,
                arrivalDate: arrival.currentDate ?? arrival.scheduledDate,
                arrivalDelayed: arrival.isDelayed,
                departurePlatform: JourneyFormatting.platformText(journey),
                arrivalPlatform: JourneyFormatting.arrivalPlatformText(journey),
                departed: departed,
                recommended: leg.legIndex == 0,
                statusText: nonEmpty(leg.compactStatusText) ?? itineraryLegStatusText(for: leg, statusKind: statusKind, now: now),
                statusKind: statusKind,
                delayMinutes: delayMinutes,
                journeyProgress: journeyProgress(
                    departureDate: departure.currentDate ?? departure.scheduledDate,
                    arrivalDate: arrival.currentDate ?? arrival.scheduledDate,
                    now: now,
                    departed: departed,
                    statusKind: statusKind
                )
            ),
            departureSortDate: departure.currentDate ?? departure.scheduledDate,
            arrivalSortDate: arrival.currentDate ?? arrival.scheduledDate
        )
    }

    private static func liveActivityPinnedFirstLeg(
        _ leg: ItineraryPinnedFirstLeg
    ) -> RightTrainLiveActivityAttributes.ContentState.PinnedFirstLeg {
        RightTrainLiveActivityAttributes.ContentState.PinnedFirstLeg(
            serviceID: leg.serviceId,
            rid: leg.rid,
            ssd: leg.ssd,
            originName: JourneyFormatting.stationDisplayName(
                name: leg.originName,
                fallback: leg.originCrs ?? ""
            ),
            originShortName: JourneyFormatting.compactStationDisplayName(
                shortName: leg.originSixteenCharacterName,
                name: leg.originName,
                fallback: leg.originCrs ?? ""
            ),
            destinationName: JourneyFormatting.stationDisplayName(
                name: leg.destinationName,
                fallback: leg.destinationCrs ?? ""
            ),
            destinationShortName: JourneyFormatting.compactStationDisplayName(
                shortName: leg.destinationSixteenCharacterName,
                name: leg.destinationName,
                fallback: leg.destinationCrs ?? ""
            ),
            scheduledDepartureTime: leg.scheduledDeparture.map(ItineraryFormatting.timeText),
            departureTime: (leg.expectedDeparture ?? leg.scheduledDeparture).map(ItineraryFormatting.timeText),
            scheduledDepartureDate: leg.scheduledDeparture.flatMap(DateFormatting.date(from:)),
            departureDate: (leg.expectedDeparture ?? leg.scheduledDeparture).flatMap(DateFormatting.date(from:)),
            scheduledArrivalTime: leg.scheduledArrival.map(ItineraryFormatting.timeText),
            arrivalTime: (leg.expectedArrival ?? leg.scheduledArrival).map(ItineraryFormatting.timeText),
            scheduledArrivalDate: leg.scheduledArrival.flatMap(DateFormatting.date(from:)),
            arrivalDate: (leg.expectedArrival ?? leg.scheduledArrival).flatMap(DateFormatting.date(from:))
        )
    }

    private static func itineraryRouteTitle(for subscription: ItinerarySubscription, selected: ItineraryRecommendation) -> String {
        guard let first = selected.legs.first, let last = selected.legs.last else {
            return "\(subscription.originCrs) to \(subscription.destinationCrs)"
        }
        return "\(originStationText(first)) to \(destinationStationText(last))"
    }

    private static func journeyProgress(
        departureDate: Date?,
        arrivalDate: Date?,
        now: Date,
        departed: Bool,
        statusKind: RightTrainLiveActivityAttributes.StatusKind
    ) -> Double? {
        if statusKind == .arrived {
            return 1
        }
        guard departed,
              let departureDate,
              let arrivalDate,
              arrivalDate > departureDate else {
            return 0
        }
        let progress = now.timeIntervalSince(departureDate) / arrivalDate.timeIntervalSince(departureDate)
        return min(max(progress, 0), 1)
    }

    private static func selectedRecommendation(
        from recommendations: [DirectWindowRecommendation],
        fallback: DirectWindowRecommendation,
        pinnedTrainServiceID: Int?
    ) -> DirectWindowRecommendation {
        if let pinnedTrainServiceID,
           let pinnedRecommendation = recommendations.first(where: { $0.journey.serviceId == pinnedTrainServiceID }) {
            return pinnedRecommendation
        }
        if let recommended = recommendations.first(where: \.recommended) {
            return recommended
        }
        return recommendations.first ?? fallback
    }

    private static func highlightedWindowTrains(from candidates: [TrainCandidate], maxVisibleTrains: Int) -> [TrainCandidate] {
        guard maxVisibleTrains > 0 else {
            return []
        }

        let upcoming = candidates.filter { !$0.train.departed && $0.train.statusKind != .cancelled && $0.train.statusKind != .arrived }
        guard let firstDepartingTrain = upcoming.sorted(by: departureSort).first else {
            return []
        }

        var highlighted = [firstDepartingTrain]
        if maxVisibleTrains > 1 {
            if let firstArrivingTrain = upcoming.sorted(by: arrivalSort).first,
               firstArrivingTrain.train.serviceID != firstDepartingTrain.train.serviceID {
                highlighted.append(firstArrivingTrain)
            }
        }

        for candidate in upcoming.sorted(by: departureSort)
            where highlighted.count < maxVisibleTrains &&
                !highlighted.contains(where: { $0.train.serviceID == candidate.train.serviceID }) {
            highlighted.append(candidate)
        }

        return Array(highlighted.sorted(by: departureSort).prefix(maxVisibleTrains))
    }

    private static func otherDeparturesText(from candidates: [TrainCandidate], selectedServiceID: Int) -> String? {
        var seenTimes = Set<String>()
        let times = candidates
            .sorted(by: departureSort)
            .compactMap { candidate -> String? in
                let train = candidate.train
                guard train.serviceID != selectedServiceID,
                      !train.departed,
                      train.statusKind != .cancelled,
                      train.statusKind != .arrived else {
                    return nil
                }
                let time = train.scheduledDepartureTime.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? train.departureTime
                    : train.scheduledDepartureTime
                let trimmedTime = time.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedTime.isEmpty, !seenTimes.contains(trimmedTime) else {
                    return nil
                }
                seenTimes.insert(trimmedTime)
                return trimmedTime
            }

        guard !times.isEmpty else {
            return nil
        }

        let maxFooterTimes = 4
        let visibleTimes = Array(times.prefix(maxFooterTimes))
        let hiddenCount = max(times.count - maxFooterTimes, 0)
        var text = "Other trains: " + visibleTimes.joined(separator: ", ")
        if hiddenCount > 0 {
            text += " +\(hiddenCount) more"
        }
        return text
    }

    private static func departureSort(_ left: TrainCandidate, _ right: TrainCandidate) -> Bool {
        sort(left.departureSortDate, before: right.departureSortDate, leftID: left.train.serviceID, rightID: right.train.serviceID)
    }

    private static func arrivalSort(_ left: TrainCandidate, _ right: TrainCandidate) -> Bool {
        sort(left.arrivalSortDate, before: right.arrivalSortDate, leftID: left.train.serviceID, rightID: right.train.serviceID)
    }

    private static func sort(_ leftDate: Date?, before rightDate: Date?, leftID: Int, rightID: Int) -> Bool {
        switch (leftDate, rightDate) {
        case let (leftDate?, rightDate?):
            return leftDate == rightDate ? leftID < rightID : leftDate < rightDate
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        case (nil, nil):
            return leftID < rightID
        }
    }

    private static func statusKind(
        for recommendation: DirectWindowRecommendation,
        now: Date = Date()
    ) -> RightTrainLiveActivityAttributes.StatusKind {
        let journey = recommendation.journey
        if let kind = liveActivityStatusKind(journey.statusKind) {
            return kind
        }
        return liveActivityStatusKind(JourneyFormatting.statusKind(journey)) ?? .unknown
    }

    private static func itineraryLegStatusKind(
        for leg: ItineraryLeg,
        now: Date
    ) -> RightTrainLiveActivityAttributes.StatusKind {
        if let kind = liveActivityStatusKind(leg.statusKind) {
            return kind
        }
        return liveActivityStatusKind(JourneyFormatting.statusKind(leg.journeyResult)) ?? .unknown
    }

    private static func itineraryStatusKind(
        for itinerary: ItineraryRecommendation,
        trains: [RightTrainLiveActivityAttributes.ContentState.Train]
    ) -> RightTrainLiveActivityAttributes.StatusKind {
        if let kind = liveActivityStatusKind(itinerary.statusKind) {
            return kind
        }
        if itinerary.connections.contains(where: { $0.risk.status == "missed" }) {
            return .missed
        }
        if itinerary.connections.contains(where: { $0.risk.status == "at_risk" }) {
            return .atRisk
        }
        if !trains.isEmpty && trains.allSatisfy({ $0.statusKind == .cancelled }) {
            return .cancelled
        }
        if itinerary.score.delayMinutes > 0 || trains.contains(where: { $0.statusKind == .delayed }) {
            return .delayed
        }
        if !trains.isEmpty && trains.allSatisfy({ $0.statusKind == .arrived }) {
            return .arrived
        }
        if !itinerary.score.usable {
            return .unknown
        }
        return .good
    }

    private static func itineraryStatusText(
        for itinerary: ItineraryRecommendation,
        statusKind: RightTrainLiveActivityAttributes.StatusKind
    ) -> String {
        if let text = nonEmpty(itinerary.statusText) {
            return text
        }
        switch statusKind {
        case .missed:
            return "Connection missed"
        case .atRisk:
            return "Connection at risk"
        case .cancelled:
            return "Cancelled"
        case .delayed:
            return itinerary.score.delayMinutes > 0 ? "Delayed +\(itinerary.score.delayMinutes)" : "Delayed"
        case .arrived:
            return "Arrived"
        case .good:
            return "On time"
        case .departed:
            return "Departed"
        case .unreported, .notReported:
            return "Unreported"
        case .unknown:
            return "Checking"
        }
    }

    private static func itineraryLegStatusText(
        for leg: ItineraryLeg,
        statusKind: RightTrainLiveActivityAttributes.StatusKind,
        now: Date
    ) -> String {
        if let text = nonEmpty(leg.statusText) {
            return text
        }
        switch statusKind {
        case .cancelled:
            return "Cancelled"
        case .delayed:
            return "Delayed"
        case .arrived:
            return "Arrived"
        case .unreported, .notReported:
            return JourneyFormatting.compactMovementStatusText(leg.journeyResult, now: now)
        case .missed:
            return "Connection missed"
        case .atRisk:
            return "Connection at risk"
        case .good:
            return "On time"
        case .departed:
            return "Departed"
        case .unknown:
            let status = leg.status.trimmingCharacters(in: .whitespacesAndNewlines)
            return status.isEmpty ? "Checking" : status.capitalized
        }
    }

    private static func itineraryNextUpdateText(
        for itinerary: ItineraryRecommendation,
        statusKind: RightTrainLiveActivityAttributes.StatusKind
    ) -> String {
        switch statusKind {
        case .missed, .atRisk:
            return "Checking reachable connections"
        case .cancelled:
            return "Checking alternatives"
        case .delayed:
            return "Tracking delay and connections"
        case .arrived:
            return "Arrived at destination"
        default:
            return ""
        }
    }

    private static func itineraryConnectionSummaryText(for itinerary: ItineraryRecommendation) -> String? {
        guard !itinerary.connections.isEmpty else {
            return nil
        }
        for connection in itinerary.connections {
            switch connection.risk.status {
            case "missed":
                return "\(connection.atName): \(abs(connection.expectedMarginMinutes)) min short"
            case "at_risk":
                return "\(connection.atName): \(max(connection.expectedMarginMinutes, 0)) min spare"
            default:
                continue
            }
        }
        let margin = itinerary.score.minimumConnectionMarginMinutes
        let label = itinerary.connections.contains { $0.transferMode?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }
            ? "Tightest transfer"
            : "Tightest connection"
        return "\(label): \(margin) min spare"
    }

    private static func itineraryUpdateText(for itinerary: ItineraryRecommendation) -> String {
        let latestUpdate = itinerary.legs
            .compactMap { $0.realtimeUpdatedAt.flatMap(DateFormatting.date(from:)) }
            .max()
        guard let latestUpdate else {
            return "Updated now"
        }
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "Europe/London")
        formatter.dateFormat = "HH:mm"
        return "Updated \(formatter.string(from: latestUpdate))"
    }

    private static func statusText(
        for recommendation: DirectWindowRecommendation,
        statusKind: RightTrainLiveActivityAttributes.StatusKind,
        now: Date
    ) -> String {
        if let text = nonEmpty(recommendation.journey.compactStatusText) ?? nonEmpty(recommendation.journey.statusText) {
            return text
        }
        switch statusKind {
        case .arrived:
            return "Arrived"
        case .cancelled:
            return "Cancelled"
        case .delayed:
            let delay = JourneyFormatting.statusDelayMinutes(journey: recommendation.journey, score: recommendation.score)
            return delay > 0 ? "Delayed +\(delay)" : "Delayed"
        case .departed:
            return JourneyFormatting.compactMovementStatusText(recommendation.journey, score: recommendation.score, now: now)
        case .unreported, .notReported:
            return JourneyFormatting.compactMovementStatusText(recommendation.journey, score: recommendation.score, now: now)
        case .missed:
            return "Connection missed"
        case .atRisk:
            return "Connection at risk"
        case .good:
            return "On time"
        case .unknown:
            if recommendation.journey.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "deactivated" {
                return "Checking"
            }
            return recommendation.journey.status.isEmpty ? "Checking" : recommendation.journey.status.capitalized
        }
    }

    private static func trainStatusText(
        for recommendation: DirectWindowRecommendation,
        statusKind: RightTrainLiveActivityAttributes.StatusKind,
        now: Date
    ) -> String {
        if let text = nonEmpty(recommendation.journey.compactStatusText) ?? nonEmpty(recommendation.journey.statusText) {
            return text
        }
        switch statusKind {
        case .arrived, .cancelled, .delayed, .departed, .unreported, .notReported, .missed, .atRisk, .unknown:
            return statusText(for: recommendation, statusKind: statusKind, now: now)
        case .good:
            return "On time"
        }
    }

    private static func nextUpdateText(
        for recommendation: DirectWindowRecommendation,
        platform: String,
        phase: String = "window",
        now: Date
    ) -> String {
        let journey = recommendation.journey
        if phase == "at_origin",
           let signage = JourneyFormatting.departureSignageText(journey) {
            return signage
        }
        let displayStatus = JourneyFormatting.displayStatus(journey)
        switch displayStatus {
        case "arrived":
            return "Arrived at destination"
        case "unreported":
            if JourneyFormatting.isDeparted(journey) {
                return "Report incomplete"
            }
            return "Arrival unreported"
        case "cancelled":
            return journey.cancellationReasonText ?? "Service cancelled"
        case "delayed":
            return "Tracking delay and alternatives"
        default:
            break
        }
        if JourneyFormatting.isCancelled(journey) {
            return journey.cancellationReasonText ?? "Service cancelled"
        }
        if JourneyFormatting.hasDelaySignal(journey: journey, score: recommendation.score) {
            return "Tracking delay and alternatives"
        }
        if platform == "TBC" {
            return "Waiting for platform"
        }
        return ""
    }

    private static func updateText(for recommendations: [DirectWindowRecommendation]) -> String {
        let latestUpdate = recommendations
            .compactMap { $0.journey.realtimeUpdatedAt.flatMap(DateFormatting.date(from:)) }
            .max()

        guard let latestUpdate else {
            return "Updated now"
        }

        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "Europe/London")
        formatter.dateFormat = "HH:mm"
        return "Updated \(formatter.string(from: latestUpdate))"
    }

    private static func windowTimeRangeText(for window: WindowSubscription, trainCount: Int) -> String {
        guard let start = DateFormatting.date(from: window.departureStart) else {
            return "\(window.windowMinutes) min (\(trainCount) \(trainCount == 1 ? "train" : "trains"))"
        }

        let end = start.addingTimeInterval(TimeInterval(window.windowMinutes) * 60)
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "Europe/London")
        formatter.dateFormat = "HH:mm"
        return "\(formatter.string(from: start))-\(formatter.string(from: end)) (\(trainCount) \(trainCount == 1 ? "train" : "trains"))"
    }
}

private extension WindowSubscription {
    var isLiveActivityActive: Bool {
        status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "active" && deletedAt == nil
    }
}

private extension ItinerarySubscription {
    var isLiveActivityActive: Bool {
        status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "active" && deletedAt == nil
    }
}
