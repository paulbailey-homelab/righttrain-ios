import ActivityKit
import AppIntents
import Foundation
import SwiftUI
import WidgetKit

#if RIGHTTRAIN_LAYOUT_TESTS
@testable import RightTrain
#endif

#if !RIGHTTRAIN_LAYOUT_TESTS
@main
struct RightTrainLiveActivityExtensionBundle: WidgetBundle {
    var body: some Widget {
        RightTrainLiveActivityWidget()
    }
}
#endif

struct RightTrainLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RightTrainLiveActivityAttributes.self) { context in
            ActivityContentView(context: context)
                .widgetURL(activityURL(for: context))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    IslandLeadingMetric(context: context)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    if let platformChange = context.state.activePlatformChange {
                        PlatformChangeIslandMetric(change: platformChange, edge: .trailing)
                    } else if let platform = islandPlatform(for: context) {
                        IslandEdgeMetric(label: platform.label, value: platform.value, edge: .trailing)
                    } else {
                        IslandEdgeMetric(label: "Status", value: context.state.selectedTrain?.statusText ?? context.state.statusText, edge: .trailing)
                    }
                }

                DynamicIslandExpandedRegion(.center) {
                    IslandTitle(state: context.state, activityKind: context.attributes.activityKind)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    DynamicIslandBottomContent(context: context)
                }
            } compactLeading: {
                CompactLeadingMetric(context: context)
            } compactTrailing: {
                let statusKind = context.state.selectedTrain?.statusKind ?? context.state.statusKind
                if let platformChange = context.state.activePlatformChange {
                    CompactPlatformChangeText(change: platformChange)
                } else if let platform = compactPlatform(for: context) {
                    CompactPlatformText(
                        platform: platform.value,
                        fullLabel: platform.label,
                        accessibilityPrefix: platform.accessibilityPrefix
                    )
                } else if statusKind != .good {
                    StatusGlyph(kind: statusKind, delayMinutes: context.state.selectedTrain?.delayMinutes ?? context.state.delayMinutes)
                } else if let platform = departurePlatform(for: context) {
                    CompactPlatformText(platform: platform)
                } else {
                    StatusGlyph(kind: statusKind, delayMinutes: context.state.selectedTrain?.delayMinutes ?? context.state.delayMinutes)
                }
            } minimal: {
                StatusGlyph(
                    kind: context.state.selectedTrain?.statusKind ?? context.state.statusKind,
                    delayMinutes: context.state.selectedTrain?.delayMinutes ?? context.state.delayMinutes
                )
            }
            .widgetURL(activityURL(for: context))
            .keylineTint(keylineTint(for: context))
        }
        .rightTrainSupplementalActivityFamilies()
    }

    private func activityURL(for context: ActivityViewContext<RightTrainLiveActivityAttributes>) -> URL? {
        rightTrainActivityURL(attributes: context.attributes, state: context.state)
    }

    private func compactTime(for context: ActivityViewContext<RightTrainLiveActivityAttributes>) -> String {
        if context.attributes.activityKind == .train {
            if let train = context.state.selectedTrain, train.isOnboard {
                return train.arrivalTime
            }
            return context.state.selectedTrain?.departureTime ?? context.state.departureTime
        }
        if context.attributes.activityKind == .leg {
            // On a leg: countdown to ARRIVAL at the leg's destination
            // (interchange for non-final, destination for final).
            return context.state.activeItineraryTrain?.arrivalTime ?? context.state.arrivalTime
        }
        if context.attributes.activityKind == .itinerary {
            return context.state.activeItineraryTrain?.departureTime ?? context.state.departureTime
        }
        return context.state.recommendedTrain?.departureTime ?? context.state.compactWindowEmptyStateText
    }

    private func islandPlatform(for context: ActivityViewContext<RightTrainLiveActivityAttributes>) -> (label: String, value: String)? {
        if context.attributes.activityKind == .train,
           let train = context.state.selectedTrain,
           train.isOnboard {
            return displayPlatform(train.arrivalPlatform).map { (label: "Arr plat", value: $0) }
        }
        // On approaching_interchange, the user cares most about the
        // ONWARD platform at the interchange. Surface it in the island.
        if context.attributes.activityKind == .leg,
           ItineraryPhase.from(rawValue: context.state.phase) == .approachingInterchange,
           let platform = displayPlatform(context.state.interchange?.onwardPlatform) {
            return (label: "Onward", value: platform)
        }
        // On any boarded leg, current arrival platform is the next signal.
        if context.attributes.activityKind == .leg,
           let train = context.state.activeItineraryTrain,
           let platform = displayPlatform(train.arrivalPlatform) {
            return (label: "Arr plat", value: platform)
        }
        return departurePlatform(for: context).map { (label: "Dep plat", value: $0) }
    }

    private func compactPlatform(for context: ActivityViewContext<RightTrainLiveActivityAttributes>) -> (label: String, value: String, accessibilityPrefix: String)? {
        if context.attributes.activityKind == .train,
           let train = context.state.selectedTrain,
           train.isOnboard,
           let platform = displayPlatform(train.arrivalPlatform) {
            return (label: "Arr", value: platform, accessibilityPrefix: "Arrival platform")
        }
        if context.attributes.activityKind == .leg,
           ItineraryPhase.from(rawValue: context.state.phase) == .approachingInterchange,
           let platform = displayPlatform(context.state.interchange?.onwardPlatform) {
            return (label: "Onw", value: platform, accessibilityPrefix: "Onward platform")
        }
        return nil
    }

    private func departurePlatform(for context: ActivityViewContext<RightTrainLiveActivityAttributes>) -> String? {
        let train: RightTrainLiveActivityAttributes.ContentState.Train?
        if context.attributes.activityKind == .train {
            train = context.state.selectedTrain
        } else if context.attributes.activityKind == .itinerary || context.attributes.activityKind == .leg {
            train = context.state.activeItineraryTrain
        } else {
            train = context.state.recommendedTrain
        }
        if context.attributes.activityKind == .window, train == nil {
            return nil
        }
        return displayPlatform(train?.departurePlatform ?? context.state.platform)
    }

    private func displayPlatform(_ platform: String?) -> String? {
        guard let platform,
              !platform.isEmpty else {
            return nil
        }
        return platform.uppercased() == "TBC" ? "TBC" : platform
    }

    private func keylineTint(for context: ActivityViewContext<RightTrainLiveActivityAttributes>) -> Color {
        if context.attributes.activityKind == .train {
            return (context.state.selectedTrain?.statusKind ?? context.state.statusKind).tint
        }
        if context.attributes.activityKind == .leg {
            // Highlight the change in amber/red so the Lock Screen and
            // Dynamic Island look distinct when the user needs to act.
            switch ItineraryPhase.from(rawValue: context.state.phase) {
            case .approachingInterchange:
                if context.state.interchange?.riskStatus == "missed" {
                    return RightTrainLiveActivityAttributes.StatusKind.cancelled.tint
                }
                return RightTrainLiveActivityAttributes.StatusKind.delayed.tint
            default:
                return context.state.statusKind.tint
            }
        }
        if context.attributes.activityKind == .itinerary {
            return context.state.statusKind.tint
        }
        return .rightTrainActivityAccent
    }
}

func rightTrainActivityURL(
    attributes: RightTrainLiveActivityAttributes,
    state: RightTrainLiveActivityAttributes.ContentState
) -> URL? {
    if attributes.activityKind == .train {
        if state.selectedTrain?.isOnboard == true {
            if let windowSubscriptionID = attributes.windowSubscriptionID {
                return URL(string: "righttrain://windows/direct/subscriptions/\(windowSubscriptionID)")
            }
            return URL(string: "righttrain://active")
        }
        let serviceID = state.selectedTrain?.serviceID ?? state.pinnedTrainServiceID ?? state.recommendationServiceID
        return URL(string: "righttrain://journeys/\(serviceID)")
    }
    if attributes.activityKind == .itinerary,
       let itinerarySubscriptionID = attributes.itinerarySubscriptionID {
        return URL(string: "righttrain://itinerary-subscriptions/\(itinerarySubscriptionID)")
    }
    guard let windowSubscriptionID = attributes.windowSubscriptionID else {
        return nil
    }
    return URL(string: "righttrain://windows/direct/subscriptions/\(windowSubscriptionID)")
}

private struct IslandLeadingMetric: View {
    var context: ActivityViewContext<RightTrainLiveActivityAttributes>

    var body: some View {
        if let date = metricDate {
            if train?.isOnboard == true || train?.departed == true || date > Date() {
                RelativeIslandEdgeMetric(label: label, date: date, clockText: fallbackTime, countsDown: date > Date())
            } else {
                IslandEdgeMetric(label: label, value: fallbackTime)
            }
        } else {
            IslandEdgeMetric(label: label, value: fallbackTime)
        }
    }

    private var isOnboardTrainActivity: Bool {
        context.attributes.activityKind == .train && train?.isOnboard == true
    }

    /// True when the user has boarded a leg of a multi-leg journey
    /// (`.leg` kind). At that point the user cares about ARRIVAL into
    /// the current leg's destination, not the next departure.
    private var isOnboardLegActivity: Bool {
        context.attributes.activityKind == .leg
    }

    private var showsArrival: Bool {
        isOnboardTrainActivity || isOnboardLegActivity
    }

    private var metricDate: Date? {
        if showsArrival {
            return train?.arrivalDate ?? train?.scheduledArrivalDate ?? context.state.arrivalDate ?? context.state.scheduledArrivalDate
        }
        return train?.departureDate ?? train?.scheduledDepartureDate ?? context.state.departureDate ?? context.state.scheduledDepartureDate
    }

    private var train: RightTrainLiveActivityAttributes.ContentState.Train? {
        switch context.attributes.activityKind {
        case .train:
            return context.state.selectedTrain
        case .itinerary, .leg:
            return context.state.activeItineraryTrain
        case .window:
            return context.state.recommendedTrain
        }
    }

    private var label: String {
        if showsArrival {
            return "Arr"
        }
        switch context.attributes.activityKind {
        case .window:
            return "Best"
        default:
            return "Dep"
        }
    }

    private var fallbackTime: String {
        if showsArrival {
            return train?.arrivalTime ?? context.state.arrivalTime
        }
        return train?.departureTime ?? context.state.departureTime
    }
}

private struct CompactLeadingMetric: View {
    var context: ActivityViewContext<RightTrainLiveActivityAttributes>

    var body: some View {
        Text(time)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Color.rightTrainActivityText)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.62)
            .allowsTightening(true)
            .contentTransition(.numericText())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(accessibilityValue)
    }

    private var train: RightTrainLiveActivityAttributes.ContentState.Train? {
        switch context.attributes.activityKind {
        case .train:
            return context.state.selectedTrain
        case .itinerary, .leg:
            return context.state.activeItineraryTrain
        case .window:
            return context.state.recommendedTrain
        }
    }

    private var isOnboardTrainActivity: Bool {
        context.attributes.activityKind == .train && train?.isOnboard == true
    }

    private var isOnboardLegActivity: Bool {
        context.attributes.activityKind == .leg
    }

    private var time: String {
        if isOnboardTrainActivity || isOnboardLegActivity {
            return train?.arrivalTime ?? context.state.arrivalTime
        }
        if context.attributes.activityKind == .window {
            return train?.departureTime ?? context.state.compactWindowEmptyStateText
        }
        return train?.departureTime ?? context.state.departureTime
    }

    private var accessibilityLabel: String {
        isOnboardTrainActivity ? "Arrives" : "Departs"
    }

    private var accessibilityValue: String {
        let date = isOnboardTrainActivity
            ? train?.arrivalDate ?? train?.scheduledArrivalDate ?? context.state.arrivalDate ?? context.state.scheduledArrivalDate
            : train?.departureDate ?? train?.scheduledDepartureDate ?? context.state.departureDate ?? context.state.scheduledDepartureDate
        guard let date else {
            return time
        }
        let relative = RelativeDateTimeFormatter()
        relative.unitsStyle = .full
        return "\(relative.localizedString(for: date, relativeTo: Date())), \(time)"
    }
}

private struct DynamicIslandBottomContent: View {
    var context: ActivityViewContext<RightTrainLiveActivityAttributes>

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            detailContent

            if hasActions {
                Spacer(minLength: 6)
                actionButtons
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var detailContent: some View {
        if context.attributes.activityKind == .train, let train = context.state.selectedTrain {
            IslandTrainSummary(train: train, mode: .arrival)
        } else if context.attributes.activityKind == .itinerary || context.attributes.activityKind == .leg {
            if context.attributes.activityKind == .leg,
               context.state.resolvedPhase == .approachingInterchange {
                EmptyView()
            } else {
                IslandItinerarySummary(state: context.state)
            }
        } else if let train = context.state.recommendedTrain {
            IslandTrainSummary(train: train, mode: .departure)
        } else {
            IslandSummaryText(text: context.state.windowEmptyStateText)
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            if let pinIntent {
                Button(intent: pinIntent) {
                    Label("Pin", systemImage: "pin.fill")
                        .labelStyle(.titleAndIcon)
                }
            }

            if let snoozeIntent {
                Button(intent: snoozeIntent) {
                    Label("Snooze", systemImage: "bell.slash.fill")
                        .labelStyle(.titleAndIcon)
                }
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private var hasActions: Bool {
        pinIntent != nil || snoozeIntent != nil
    }

    private var pinIntent: PinTrainIntent? {
        guard context.attributes.activityKind == .window,
              let windowSubscriptionID = context.attributes.windowSubscriptionID else {
            return nil
        }
        let serviceID = context.state.recommendedTrain?.serviceID ?? context.state.recommendationServiceID
        guard serviceID > 0 else {
            return nil
        }
        return PinTrainIntent(windowSubscriptionID: windowSubscriptionID, serviceID: serviceID)
    }

    private var snoozeIntent: SnoozeAlertsIntent? {
        guard context.attributes.activityKind == .itinerary || context.attributes.activityKind == .leg else {
            return nil
        }
        return SnoozeAlertsIntent(
            minutes: 10,
            windowSubscriptionID: context.attributes.windowSubscriptionID,
            itinerarySubscriptionID: context.attributes.itinerarySubscriptionID
        )
    }
}

private struct IslandTrainSummary: View {
    enum Mode {
        case departure
        case arrival
    }

    var train: RightTrainLiveActivityAttributes.ContentState.Train
    var mode: Mode

    var body: some View {
        HStack(alignment: .center, spacing: 7) {
            IslandStatusText(kind: train.statusKind, delayMinutes: train.delayMinutes)
            ActivityTimeText(
                scheduled: scheduledTime,
                current: currentTime,
                delayed: delayed,
                font: .subheadline.weight(.bold)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var scheduledTime: String {
        switch mode {
        case .departure:
            return train.scheduledDepartureTime
        case .arrival:
            return train.scheduledArrivalTime
        }
    }

    private var currentTime: String {
        switch mode {
        case .departure:
            return train.departureTime
        case .arrival:
            return train.arrivalTime
        }
    }

    private var delayed: Bool {
        switch mode {
        case .departure:
            return train.departureDelayed
        case .arrival:
            return train.arrivalDelayed
        }
    }
}

private struct IslandItinerarySummary: View {
    var state: RightTrainLiveActivityAttributes.ContentState

    var body: some View {
        HStack(alignment: .center, spacing: 7) {
            IslandStatusText(kind: state.statusKind, delayMinutes: state.delayMinutes)
            IslandSummaryText(text: primaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var primaryText: String {
        if state.resolvedPhase == .approachingInterchange,
           let interchange = state.interchange {
            let platform = interchange.onwardPlatform?.trimmingCharacters(in: .whitespacesAndNewlines)
            let platformText: String
            if let platform, !platform.isEmpty {
                platformText = "P\(readablePlatformValue(platform))"
            } else {
                platformText = "P TBC"
            }
            return "Get off · \(platformText)"
        }
        if state.resolvedPhase.isOnboard,
           let train = state.activeItineraryTrain {
            return "Arr \(train.arrivalTime)"
        }
        if let train = state.activeItineraryTrain {
            return "Dep \(train.departureTime)"
        }
        return state.compactItinerarySummaryText
    }
}

private struct IslandStatusText: View {
    var kind: RightTrainLiveActivityAttributes.StatusKind
    var delayMinutes: Int?

    private var tint: Color {
        kind.tint(delayMinutes: delayMinutes ?? 0)
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: kind.symbolName)
                .imageScale(.medium)
            Text(kind.compactText)
                .lineLimit(1)
                .minimumScaleFactor(0.74)
                .allowsTightening(true)
        }
        .font(.subheadline.weight(.bold))
        .foregroundStyle(tint)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        guard let delayMinutes, delayMinutes > 0,
              kind == .delayed || kind == .atRisk || kind == .unreported || kind == .notReported else {
            return kind.accessibilityLabel
        }
        return "\(kind.accessibilityLabel), \(delayMinutes) minutes late"
    }
}

private struct IslandSummaryText: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.rightTrainActivityText)
            .lineLimit(1)
            .minimumScaleFactor(0.74)
            .allowsTightening(true)
    }
}

private func readablePlatformValue(_ platform: String) -> String {
    let trimmed = platform.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.uppercased().hasPrefix("P"), trimmed.count > 1 {
        return String(trimmed.dropFirst())
    }
    return trimmed
}

private func compactPlatformDisplayValue(_ platform: String) -> String {
    let trimmed = platform.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.uppercased() == "TBC" || trimmed == "-" {
        return trimmed
    }
    if trimmed.uppercased().hasPrefix("P") {
        return trimmed.uppercased()
    }
    return "P\(trimmed)"
}

private struct CompactPlatformText: View {
    var platform: String
    var fullLabel: String = "Plat"
    var accessibilityPrefix: String = "Departure platform"

    private var platformDisplayValue: String {
        readablePlatformValue(platform)
    }

    private var compactPlatformValue: String {
        compactPlatformDisplayValue(platform)
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            Text("\(fullLabel) \(platformDisplayValue)")
            Text(compactPlatformValue)
        }
        .font(.caption2.weight(.bold))
        .foregroundStyle(Color.rightTrainActivityText)
        .lineLimit(1)
        .minimumScaleFactor(0.55)
        .allowsTightening(true)
        .accessibilityLabel(platformDisplayValue.uppercased() == "TBC" ? "\(accessibilityPrefix) to be confirmed" : "\(accessibilityPrefix) \(platformDisplayValue)")
    }
}

private struct CompactPlatformChangeText: View {
    var change: RightTrainLiveActivityAttributes.ContentState.PlatformChange

    private var currentPlatform: String {
        compactPlatformDisplayValue(change.currentPlatform)
    }

    private var fullText: String {
        "\(compactPlatformDisplayValue(change.previousPlatform))->\(currentPlatform)"
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            Text(fullText)
            Text(currentPlatform)
        }
        .font(.caption2.weight(.bold))
        .foregroundStyle(Color.rightTrainActivityLate)
        .lineLimit(1)
        .minimumScaleFactor(0.55)
        .allowsTightening(true)
        .accessibilityLabel("Departure platform changed from \(readablePlatformValue(change.previousPlatform)) to \(readablePlatformValue(change.currentPlatform))")
    }
}

private extension ActivityConfiguration {
    func rightTrainSupplementalActivityFamilies() -> some WidgetConfiguration {
        supplementalActivityFamilies([.small, .medium])
    }
}

private struct ActivityContentView: View {
    var context: ActivityViewContext<RightTrainLiveActivityAttributes>

    var body: some View {
        ActivityFamilyContentView(context: context)
    }
}

private struct ActivityStatusBackground: View {
    var statusKind: RightTrainLiveActivityAttributes.StatusKind

    var body: some View {
        ZStack {
            Color.rightTrainActivityBackground
            // Status-first: the card surface takes on the status colour at a
            // meaningful opacity so the state is readable in <1 second.
            statusKind.tint.opacity(statusKind.activitySurfaceOpacity)
        }
    }
}

private struct ActivityCardChrome: ViewModifier {
    var statusKind: RightTrainLiveActivityAttributes.StatusKind

    func body(content: Content) -> some View {
        content
            .background {
                ActivityStatusBackground(statusKind: statusKind)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
            .overlay {
                if statusKind.usesSevereInnerStroke {
                    // Cancelled / missed: bold 2pt ring
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(statusKind.tint.opacity(0.78), lineWidth: 2)
                        .padding(1)
                } else if statusKind.usesModerateInnerStroke {
                    // Delayed / at-risk: subtle 1pt ring reinforces the amber surface
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(statusKind.tint.opacity(0.42), lineWidth: 1)
                        .padding(1)
                }
            }
            .activityBackgroundTint(statusKind.activityBackgroundTintColor)
            .activitySystemActionForegroundColor(.rightTrainActivityAccent)
    }
}

private extension View {
    func activityCardChrome(statusKind: RightTrainLiveActivityAttributes.StatusKind) -> some View {
        modifier(ActivityCardChrome(statusKind: statusKind))
    }
}

private extension DynamicTypeSize {
    var rightTrainPrefersExpandedLayout: Bool {
        switch self {
        case .accessibility1, .accessibility2, .accessibility3, .accessibility4, .accessibility5:
            return true
        default:
            return false
        }
    }
}

@available(iOS 18.0, *)
private struct ActivityFamilyContentView: View {
    @Environment(\.activityFamily) private var activityFamily
    var context: ActivityViewContext<RightTrainLiveActivityAttributes>

    var body: some View {
        switch activityFamily {
        case .small:
            WatchActivityView(
                state: context.state,
                activityKind: context.attributes.activityKind
            )
        case .medium:
            StandardActivityContentView(
                state: context.state,
                activityKind: context.attributes.activityKind
            )
        @unknown default:
            StandardActivityContentView(
                state: context.state,
                activityKind: context.attributes.activityKind
            )
        }
    }
}

private struct StandardActivityContentView: View {
    var state: RightTrainLiveActivityAttributes.ContentState
    var activityKind: RightTrainLiveActivityAttributes.ActivityKind

    var body: some View {
        if activityKind == .train {
            PinnedTrainActivityView(state: state)
        } else if activityKind == .itinerary || activityKind == .leg {
            // .leg = on-leg/approaching-interchange/on-final-leg. The
            // ItineraryBoardActivityView re-uses the leg timeline + footer
            // text (which the coordinator now sets phase-specifically),
            // with an interchange banner injected when relevant.
            ItineraryBoardActivityView(state: state)
        } else {
            WindowBoardActivityView(state: state)
        }
    }
}

private struct WatchActivityView: View {
    var state: RightTrainLiveActivityAttributes.ContentState
    var activityKind: RightTrainLiveActivityAttributes.ActivityKind

    var body: some View {
        Group {
            if activityKind == .train, let train = state.selectedTrain {
                WatchTrainActivityView(state: state, train: train)
            } else if activityKind == .itinerary || activityKind == .leg {
                WatchItineraryActivityView(state: state)
            } else {
                WatchWindowActivityView(state: state)
            }
        }
        .padding(8)
        .activityBackgroundTint(watchStatusKind.activityBackgroundTintColor)
        .activitySystemActionForegroundColor(.rightTrainActivityAccent)
        .accessibilityElement(children: .combine)
    }

    private var watchStatusKind: RightTrainLiveActivityAttributes.StatusKind {
        switch activityKind {
        case .train:
            return state.selectedTrain?.statusKind ?? state.statusKind
        case .itinerary, .leg:
            return state.statusKind
        case .window:
            return state.recommendedTrain?.statusKind ?? state.statusKind
        }
    }
}

private struct WatchWindowActivityView: View {
    var state: RightTrainLiveActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            WatchRouteHeader(
                title: state.routeTitle,
                compactTitle: state.compactRouteTitle,
                trailingText: state.windowSearchRangeText
            )

            if let train = state.recommendedTrain {
                WatchDepartureSummary(
                    train: train,
                    platformText: state.watchPlatformText(for: train),
                    statusText: train.statusText,
                    statusKind: train.statusKind,
                    delayMinutes: train.delayMinutes
                )
                WatchSupplementalFooter(
                    primaryText: train.watchOperatorText,
                    secondaryText: state.otherDeparturesText
                )
            } else {
                EmptyWindowText(text: state.windowEmptyStateText, compact: true)
            }
        }
    }
}

private struct WatchTrainActivityView: View {
    var state: RightTrainLiveActivityAttributes.ContentState
    var train: RightTrainLiveActivityAttributes.ContentState.Train

    var body: some View {
        if train.isOnboard {
            VStack(alignment: .leading, spacing: 6) {
                WatchRouteHeader(
                    title: "To \(train.destinationName)",
                    compactTitle: "To \(train.compactDestinationName)",
                    trailingText: state.compactUpdatedAtText
                )
                WatchOnboardArrivalRow(state: state, train: train)

                TimelineProgressHairline(progress: train.journeyProgress ?? 0)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                WatchRouteHeader(
                    title: "To \(train.serviceDestinationDisplayName)",
                    compactTitle: "To \(train.compactServiceDestinationName)",
                    trailingText: state.compactUpdatedAtText
                )
                if let operatorText = train.operatorDisplayText {
                    WatchOperatorText(text: operatorText)
                }
                WatchDepartureSummary(
                    train: train,
                    platformText: state.watchPlatformText(for: train),
                    statusText: train.statusText,
                    statusKind: train.statusKind,
                    delayMinutes: train.delayMinutes
                )
            }
        }
    }
}

private struct WatchOnboardArrivalRow: View {
    var state: RightTrainLiveActivityAttributes.ContentState
    var train: RightTrainLiveActivityAttributes.ContentState.Train

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("Arrives")
                .font(.caption2.weight(.medium))
                .foregroundStyle(Color.rightTrainActivitySecondaryText)
            ActivityTimeText(
                scheduled: train.scheduledArrivalTime,
                current: train.arrivalTime,
                delayed: train.arrivalDelayed,
                font: .headline.weight(.bold)
            )

            Spacer(minLength: 2)

            PlatformBadge(text: state.watchArrivalPlatformText(for: train))

            if train.statusKind != .departed && train.statusKind != .good {
                StatusGlyph(kind: train.statusKind, delayMinutes: train.delayMinutes)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.58)
        .allowsTightening(true)
    }
}

private struct WatchItineraryActivityView: View {
    var state: RightTrainLiveActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            WatchRouteHeader(
                title: state.routeTitle,
                compactTitle: state.compactRouteTitle,
                trailingText: state.compactItinerarySummaryText
            )

            if let train = state.activeItineraryTrain {
                WatchDepartureSummary(
                    train: train,
                    platformText: state.watchPlatformText(for: train),
                    statusText: state.statusText,
                    statusKind: state.statusKind,
                    delayMinutes: state.delayMinutes
                )
                WatchSupplementalFooter(secondaryText: state.itineraryConnectionFooterText)
            } else {
                EmptyWindowText(text: state.windowEmptyStateText, compact: true)
            }
        }
    }
}

private struct WatchRouteHeader: View {
    var title: String
    var compactTitle: String
    var trailingText: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                titleText(title)
                    .layoutPriority(1)

                Spacer(minLength: 2)

                trailing
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                titleText(compactTitle)
                    .layoutPriority(1)

                Spacer(minLength: 2)

                trailing
            }

            titleText(compactTitle)
        }
    }

    private func titleText(_ value: String) -> some View {
        Text(value)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.rightTrainActivityText)
            .lineLimit(1)
            .minimumScaleFactor(0.58)
            .allowsTightening(true)
            .truncationMode(.middle)
    }

    private var trailing: some View {
        Text(trailingText)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Color.rightTrainActivitySecondaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.58)
            .allowsTightening(true)
    }
}

private struct WatchOperatorText: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(Color.rightTrainActivitySecondaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.58)
            .allowsTightening(true)
    }
}

private struct WatchDepartureSummary: View {
    var train: RightTrainLiveActivityAttributes.ContentState.Train
    var platformText: String
    var statusText: String
    var statusKind: RightTrainLiveActivityAttributes.StatusKind
    var delayMinutes: Int

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 6) {
                WatchTimeLine(train: train)
                    .layoutPriority(2)

                Spacer(minLength: 2)

                badgeRow
                    .layoutPriority(1)
            }

            VStack(alignment: .leading, spacing: 5) {
                WatchTimeLine(train: train)
                badgeRow
            }
        }
    }

    private var badgeRow: some View {
        HStack(spacing: 5) {
            PlatformBadge(text: platformText)
            if statusKind.isHeroAnomalous {
                StatusBadge(text: statusText, kind: statusKind, delayMinutes: delayMinutes)
            }
        }
    }
}

private struct WatchSupplementalFooter: View {
    var primaryText: String? = nil
    var secondaryText: String? = nil

    private var primary: String? {
        nonEmpty(primaryText)
    }

    private var secondary: String? {
        nonEmpty(secondaryText)
    }

    var body: some View {
        if primary != nil || secondary != nil {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if let primary {
                        footerText(primary)
                    }

                    if primary != nil && secondary != nil {
                        Spacer(minLength: 4)
                    }

                    if let secondary {
                        footerText(secondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }

                if let secondary {
                    footerText(secondary)
                }

                if let primary {
                    footerText(primary)
                }
            }
        }
    }

    private func footerText(_ value: String) -> some View {
        Text(value)
            .font(.caption2.weight(.medium))
            .foregroundStyle(Color.rightTrainActivitySecondaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.58)
            .allowsTightening(true)
            .monospacedDigit()
            .accessibilityLabel(value)
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

private struct WatchTimeLine: View {
    var train: RightTrainLiveActivityAttributes.ContentState.Train

    var body: some View {
        ViewThatFits(in: .horizontal) {
            timeLine(font: .title3.weight(.bold), spacing: 5)
            timeLine(font: .headline.weight(.bold), spacing: 4)
            timeLine(font: .subheadline.weight(.bold), spacing: 3)
        }
        .layoutPriority(1)
    }

    private func timeLine(font: Font, spacing: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: spacing) {
            ActivityTimeText(
                scheduled: train.scheduledDepartureTime,
                current: train.departureTime,
                delayed: train.departureDelayed,
                font: font
            )
        }
    }
}

private struct WindowBoardActivityView: View {
    var state: RightTrainLiveActivityAttributes.ContentState

    var body: some View {
        if let train = state.recommendedTrain {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(state.routeTitle)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(Color.rightTrainActivityText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.58)
                            .allowsTightening(true)
                            .truncationMode(.middle)
                        Text(state.windowSearchRangeLabelText)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.rightTrainActivitySecondaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.58)
                            .allowsTightening(true)
                    }
                    .layoutPriority(2)

                    Spacer(minLength: 6)

                    if train.statusKind.isHeroAnomalous {
                        StatusBadge(text: train.statusText, kind: train.statusKind, delayMinutes: train.delayMinutes)
                            .layoutPriority(0)
                    }
                }

                HStack(alignment: .lastTextBaseline, spacing: 10) {
                    JourneyHeroBlock(train: train)
                        .layoutPriority(1)

                    Spacer(minLength: 6)

                    InlinePlatformLabel(
                        platform: train.departurePlatform,
                        confirmed: state.platformConfirmed,
                        platformChange: state.platformChange(for: train)
                    )
                }

                if let summary = state.disruptionSummaryText(for: train) {
                    DisruptionSummaryLine(text: summary, kind: train.statusKind)
                } else {
                    WindowBoardFooterRow(train: train, otherDeparturesText: state.otherDeparturesText)
                }
            }
            .padding(14)
            .activityCardChrome(statusKind: train.statusKind)
            .accessibilityElement(children: .combine)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(state.routeTitle)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Color.rightTrainActivityText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.58)
                    .allowsTightening(true)
                EmptyWindowText(text: state.windowEmptyStateText)
            }
            .padding(14)
            .activityCardChrome(statusKind: state.statusKind)
            .accessibilityElement(children: .combine)
        }
    }
}

private struct ItineraryBoardActivityView: View {
    var state: RightTrainLiveActivityAttributes.ContentState

    var body: some View {
        if let train = state.activeItineraryTrain ?? state.trains.first {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(state.routeTitle)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(Color.rightTrainActivityText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.58)
                            .allowsTightening(true)
                            .truncationMode(.middle)
                        Text(state.itineraryHeaderSubtitle)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.58)
                            .allowsTightening(true)
                    }
                    .layoutPriority(2)

                    Spacer(minLength: 6)

                    if state.statusKind.isHeroAnomalous,
                       state.resolvedPhase != .approachingInterchange {
                        StatusBadge(text: state.statusText, kind: state.statusKind, delayMinutes: state.delayMinutes)
                    }
                }

                if state.resolvedPhase == .approachingInterchange, let interchange = state.interchange {
                    InterchangeHeroBlock(state: state, interchange: interchange)
                } else {
                    HStack(alignment: .lastTextBaseline, spacing: 10) {
                        // Hero countdown: ARRIVAL when on a leg (gets the
                        // user off at the right station), DEPARTURE when
                        // still planning/at-origin.
                        CountdownHeroBlock(train: train, mode: state.resolvedPhase.isOnboard ? .arrival : .departure)
                            .layoutPriority(1)

                        Spacer(minLength: 6)

                        InlinePlatformLabel(
                            platform: state.resolvedPhase.isOnboard ? train.arrivalPlatform : train.departurePlatform,
                            confirmed: state.platformConfirmed,
                            accessibilityPrefix: state.resolvedPhase.isOnboard ? "Arrival platform" : "Departure platform"
                        )
                    }
                }

                if state.resolvedPhase != .approachingInterchange,
                   let summary = state.disruptionSummaryText(for: train) {
                    DisruptionSummaryLine(text: summary, kind: state.statusKind)
                }

                if let interchange = state.interchange,
                   state.resolvedPhase.isOnboard,
                   state.resolvedPhase != .approachingInterchange {
                    InterchangeBanner(
                        interchange: interchange,
                        approaching: state.resolvedPhase == .approachingInterchange
                    )
                }

                ItineraryTrainTimeline(state: state)
            }
            .padding(14)
            .activityCardChrome(statusKind: state.statusKind)
            .accessibilityElement(children: .combine)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(state.routeTitle)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Color.rightTrainActivityText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.58)
                    .allowsTightening(true)
                EmptyWindowText(text: state.windowEmptyStateText)
            }
            .padding(14)
            .activityCardChrome(statusKind: state.statusKind)
            .accessibilityElement(children: .combine)
        }
    }
}

private struct ItineraryTrainTimeline: View {
    var state: RightTrainLiveActivityAttributes.ContentState

    var body: some View {
        ViewThatFits(in: .vertical) {
            ItineraryTimelineContent(state: state, maxVisible: 4)
            ItineraryTimelineContent(state: state, maxVisible: 3)
            ItineraryTimelineContent(state: state, maxVisible: 2)
            ItineraryTimelineContent(state: state, maxVisible: 1)
        }
    }
}

private struct ItineraryTimelineContent: View {
    var state: RightTrainLiveActivityAttributes.ContentState
    var maxVisible: Int

    private var trains: [RightTrainLiveActivityAttributes.ContentState.Train] {
        state.trains
    }

    private var visibleTrains: [RightTrainLiveActivityAttributes.ContentState.Train] {
        Array(trains.prefix(maxVisible))
    }

    private var activeConnectionIndex: Int? {
        visibleTrains.indices.first { index in
            guard index + 1 < visibleTrains.count else {
                return false
            }
            return !visibleTrains[index + 1].departed
        }
    }

    var body: some View {
        let phase = ItineraryPhase.from(rawValue: state.phase)
        let onboardLegIndex = phase.isOnboard ? state.currentLegIndex : nil
        VStack(spacing: 0) {
            ForEach(visibleTrains.indices, id: \.self) { index in
                LegTimelineRow(
                    train: visibleTrains[index],
                    isPinnedFirstLeg: onboardLegIndex == index || (phase == .atOrigin && state.pinnedFirstLeg != nil && index == 0)
                )

                if index + 1 < visibleTrains.count {
                    ConnectionTimelineRow(
                        current: visibleTrains[index],
                        next: visibleTrains[index + 1],
                        emphasized: connectionShouldEmphasize(index: index)
                    )
                }
            }

            if trains.count > visibleTrains.count {
                Text(overflowText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.rightTrainActivitySecondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.58)
                    .allowsTightening(true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 3)
            }
        }
    }

    private var overflowText: String {
        let hiddenCount = max(trains.count - visibleTrains.count, 0)
        guard hiddenCount > 0 else {
            return ""
        }
        if let firstHidden = trains.dropFirst(visibleTrains.count).first {
            return "via \(firstHidden.compactDestinationName) +\(hiddenCount) more"
        }
        return "+\(hiddenCount) more \(hiddenCount == 1 ? "leg" : "legs")"
    }

    private func connectionShouldEmphasize(index: Int) -> Bool {
        guard index + 1 < visibleTrains.count else {
            return false
        }
        if connectionMinutes(from: visibleTrains[index], to: visibleTrains[index + 1]).map({ $0 < 4 }) == true {
            return true
        }
        switch state.statusKind {
        case .atRisk, .missed:
            return activeConnectionIndex == index
        default:
            return false
        }
    }

    private func connectionMinutes(
        from current: RightTrainLiveActivityAttributes.ContentState.Train,
        to next: RightTrainLiveActivityAttributes.ContentState.Train
    ) -> Int? {
        guard let arrival = current.arrivalDate ?? current.scheduledArrivalDate,
              let departure = next.departureDate ?? next.scheduledDepartureDate else {
            return nil
        }
        return max(0, Int((departure.timeIntervalSince(arrival) / 60).rounded()))
    }
}

private struct LegTimelineRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var train: RightTrainLiveActivityAttributes.ContentState.Train
    var isPinnedFirstLeg: Bool

    private var isCompleted: Bool {
        isPinnedFirstLeg || train.departed || train.statusKind == .arrived
    }

    private var isTerminalProblem: Bool {
        train.statusKind == .cancelled || train.statusKind == .missed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .center, spacing: 8) {
                TimelineNode(completed: isCompleted, kind: train.statusKind)

                ActivityTimeText(
                    scheduled: train.scheduledDepartureTime,
                    current: train.departureTime,
                    delayed: train.departureDelayed,
                    font: .caption.weight(.bold)
                )

                ViewThatFits(in: .horizontal) {
                    destinationText(train.destinationName)
                    destinationText(train.compactDestinationName)
                }

                Spacer(minLength: 4)

                if isPinnedFirstLeg {
                    Text("ON BOARD")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.rightTrainActivityBackground)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.rightTrainActivityAccent, in: Capsule())
                } else if train.statusKind.isHeroAnomalous && dynamicTypeSize.rightTrainPrefersExpandedLayout {
                    StatusGlyph(kind: train.statusKind, delayMinutes: train.delayMinutes)
                } else if train.statusKind.isHeroAnomalous {
                    StatusBadge(text: train.statusText, kind: train.statusKind, delayMinutes: train.delayMinutes)
                }
            }

            if isPinnedFirstLeg {
                TimelineProgressHairline(progress: train.journeyProgress ?? 0)
                    .padding(.leading, 20)
            }
        }
        .opacity(train.departed ? 0.58 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        var parts = [
            "Leg to \(train.destinationName)",
            departureAccessibilityText,
            train.departurePlatform.uppercased() == "TBC" ? "Platform to be confirmed" : "Platform \(train.departurePlatform)",
            train.statusKind.accessibilityLabel
        ]
        if isPinnedFirstLeg {
            parts.append("On board")
        }
        if let progress = train.journeyProgress, isPinnedFirstLeg {
            parts.append("\(Int((min(max(progress, 0), 1) * 100).rounded())) percent through this leg")
        }
        return parts.joined(separator: ", ")
    }

    private func destinationText(_ value: String) -> some View {
        Text(value)
            .font(.caption.weight(.semibold))
            .foregroundStyle(isTerminalProblem ? train.statusKind.tint : Color.rightTrainActivityText)
            .strikethrough(isTerminalProblem, color: train.statusKind.tint)
            .lineLimit(1)
            .minimumScaleFactor(0.58)
            .allowsTightening(true)
    }

    private var departureAccessibilityText: String {
        if train.departureDelayed, train.scheduledDepartureTime != train.departureTime {
            return "scheduled \(train.scheduledDepartureTime), now \(train.departureTime)"
        }
        return "departs \(train.departureTime)"
    }
}

private struct ConnectionTimelineRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var current: RightTrainLiveActivityAttributes.ContentState.Train
    var next: RightTrainLiveActivityAttributes.ContentState.Train
    var emphasized: Bool

    private var minutes: Int? {
        guard let arrival = current.arrivalDate ?? current.scheduledArrivalDate,
              let departure = next.departureDate ?? next.scheduledDepartureDate else {
            return nil
        }
        return max(0, Int((departure.timeIntervalSince(arrival) / 60).rounded()))
    }

    private var platformChangeText: String? {
        let arrivalPlatform = cleanPlatform(current.arrivalPlatform)
        let departurePlatform = cleanPlatform(next.departurePlatform)
        guard let arrivalPlatform,
              let departurePlatform,
              arrivalPlatform != departurePlatform else {
            return nil
        }
        return "Plat \(arrivalPlatform) -> \(departurePlatform)"
    }

    private var symbolName: String {
        emphasized ? "figure.walk.motion" : "arrow.triangle.2.circlepath"
    }

    private var tint: Color {
        emphasized ? .rightTrainActivityLate : .rightTrainActivitySecondaryText
    }

    private var text: String {
        var value = "Change at \(current.compactDestinationName)"
        if let minutes {
            value += " - \(minutes) min"
        }
        if let platformChangeText {
            value += " · \(platformChangeText)"
        }
        return value
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            ZStack {
                Rectangle()
                    .fill(tint.opacity(emphasized ? 0.85 : 0.42))
                    .frame(width: 2)
                Image(systemName: symbolName)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(tint)
                    .background(Color.rightTrainActivityBackground)
                    .symbolEffect(.pulse, options: .repeating, isActive: emphasized && !reduceMotion)
            }
            .frame(width: 12, height: 18)

            Text(text)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.58)
                .allowsTightening(true)
                .contentTransition(.numericText())

            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, emphasized ? 6 : 0)
        .background(emphasized ? Color.rightTrainActivityLate.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
        .overlay {
            if emphasized {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color.rightTrainActivityLate.opacity(0.42), lineWidth: 1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(emphasized ? "Connection at risk. \(accessibilityText)" : accessibilityText)
    }

    private func cleanPlatform(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.uppercased() != "TBC" else {
            return nil
        }
        return trimmed
    }

    private var accessibilityText: String {
        var value = "Change at \(current.destinationName)"
        if let minutes {
            value += ", \(minutes) \(minutes == 1 ? "minute" : "minutes")"
        }
        if let platformChangeText {
            value += ", \(platformChangeText)"
        }
        return value
    }
}

private struct TimelineNode: View {
    var completed: Bool
    var kind: RightTrainLiveActivityAttributes.StatusKind

    var body: some View {
        ZStack {
            if kind == .cancelled || kind == .missed {
                Image(systemName: kind.symbolName)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(kind.tint)
            } else if completed {
                Circle()
                    .fill(Color.rightTrainActivityAccent)
            } else {
                Circle()
                    .strokeBorder(Color.rightTrainActivitySecondaryText.opacity(0.75), lineWidth: 2)
            }
        }
        .frame(width: 12, height: 12)
        .accessibilityHidden(true)
    }
}

private struct TimelineProgressHairline: View {
    var progress: Double

    private var clampedProgress: Double {
        min(max(progress, 0), 1)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.rightTrainActivityDivider)
                Capsule()
                    .fill(Color.rightTrainActivityAccent)
                    .frame(width: max(proxy.size.width * CGFloat(clampedProgress), 2))
            }
        }
        .frame(height: 2)
        .accessibilityHidden(true)
    }
}

private struct PinnedTrainActivityView: View {
    var state: RightTrainLiveActivityAttributes.ContentState

    var body: some View {
        if let train = state.selectedTrain {
            if train.isOnboard {
                OnboardTrainActivityContent(state: state, train: train)
            } else {
                PinnedTrainPreDepartureContent(state: state, train: train)
            }
        } else {
            WindowBoardActivityView(state: state)
        }
    }
}

private struct OnboardTrainActivityContent: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var state: RightTrainLiveActivityAttributes.ContentState
    var train: RightTrainLiveActivityAttributes.ContentState.Train

    private var showsStatusGlyph: Bool {
        train.statusKind != .departed && train.statusKind != .good
    }

    var body: some View {
        Group {
            if dynamicTypeSize.rightTrainPrefersExpandedLayout {
                expandedLayout
            } else {
                compactLayout
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .activityCardChrome(statusKind: train.statusKind)
        .accessibilityElement(children: .combine)
    }

    private var compactLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                headerBlock
                    .layoutPriority(2)

                Spacer(minLength: 8)

                arrivalSummary
                    .layoutPriority(1)
            }

            JourneyProgressFooter(
                train: train,
                originText: state.originCrs,
                destinationText: state.destinationCrs
            )
        }
    }

    private var expandedLayout: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 10) {
                headerBlock

                if showsStatusGlyph {
                    Spacer(minLength: 6)

                    StatusGlyph(kind: train.statusKind, delayMinutes: train.delayMinutes)
                }
            }

            HStack(alignment: .lastTextBaseline, spacing: 10) {
                ExpectedArrivalBlock(train: train)
                    .layoutPriority(2)

                Spacer(minLength: 6)

                InlinePlatformLabel(
                    label: "Arr plat",
                    platform: train.arrivalPlatform,
                    confirmed: true,
                    accessibilityPrefix: "Arrival platform"
                )
            }

            JourneyProgressFooter(
                train: train,
                originText: state.originCrs,
                destinationText: state.destinationCrs
            )
        }
    }

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(train.statusKind == .arrived ? "Arrived" : "On board")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.rightTrainActivitySecondaryText)

            Text("\(train.statusKind == .arrived ? "At" : "To") \(train.destinationName)")
                .font(.headline.weight(.semibold))
                .foregroundStyle(Color.rightTrainActivityText)
                .lineLimit(1)
                .minimumScaleFactor(0.58)
                .allowsTightening(true)
                .truncationMode(.middle)

            if let operatorText = train.operatorDisplayText {
                Text(operatorText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.rightTrainActivitySecondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.58)
                    .allowsTightening(true)
            }
        }
    }

    private var arrivalSummary: some View {
        VStack(alignment: .trailing, spacing: 3) {
            HStack(spacing: 5) {
                if showsStatusGlyph {
                    StatusGlyph(kind: train.statusKind, delayMinutes: train.delayMinutes)
                }

                Text(train.arrivalLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.rightTrainActivitySecondaryText)
                    .lineLimit(1)
            }

            ActivityTimeText(
                scheduled: train.scheduledArrivalTime,
                current: train.arrivalTime,
                delayed: train.arrivalDelayed,
                font: .title2.weight(.bold)
            )

            InlinePlatformLabel(
                label: "Arr plat",
                platform: train.arrivalPlatform,
                confirmed: true,
                accessibilityPrefix: "Arrival platform"
            )
            .font(.caption.weight(.bold))
        }
        .frame(minWidth: 98, alignment: .trailing)
    }
}

private struct PinnedTrainPreDepartureContent: View {
    var state: RightTrainLiveActivityAttributes.ContentState
    var train: RightTrainLiveActivityAttributes.ContentState.Train

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("To \(train.serviceDestinationDisplayName)")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(Color.rightTrainActivityText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.58)
                        .allowsTightening(true)
                        .truncationMode(.middle)
                    HStack(spacing: 6) {
                        if let operatorText = train.operatorDisplayText {
                            Text(operatorText)
                        }
                        Text(state.compactUpdatedAtText)
                            .monospacedDigit()
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.rightTrainActivitySecondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.58)
                    .allowsTightening(true)
                }
                .layoutPriority(2)

                if train.statusKind.isHeroAnomalous {
                    Spacer(minLength: 6)

                    StatusBadge(text: train.statusText, kind: train.statusKind, delayMinutes: train.delayMinutes)
                        .layoutPriority(0)
                }
            }

            HStack(alignment: .lastTextBaseline, spacing: 10) {
                CountdownHeroBlock(train: train)
                    .layoutPriority(1)

                Spacer(minLength: 6)

                InlinePlatformLabel(
                    platform: train.departurePlatform,
                    confirmed: state.platformConfirmed,
                    platformChange: state.platformChange(for: train)
                )
            }

            JourneyProgressFooter(
                train: train,
                originText: state.originCrs,
                destinationText: state.destinationCrs
            )
        }
        .padding(14)
        .activityCardChrome(statusKind: train.statusKind)
        .accessibilityElement(children: .combine)
    }
}

private struct ExpectedArrivalBlock: View {
    var train: RightTrainLiveActivityAttributes.ContentState.Train
    var font: Font = .title.weight(.bold)

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(train.arrivalLabel == "Arrived" ? "Arrived" : "Expected arrival")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.rightTrainActivitySecondaryText)
            ActivityTimeText(
                scheduled: train.scheduledArrivalTime,
                current: train.arrivalTime,
                delayed: train.arrivalDelayed,
                font: font
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct InterchangeHeroBlock: View {
    var state: RightTrainLiveActivityAttributes.ContentState
    var interchange: RightTrainLiveActivityAttributes.ContentState.Interchange

    private var onwardTrain: RightTrainLiveActivityAttributes.ContentState.Train? {
        state.onwardLeg ?? state.trains.dropFirst((state.currentLegIndex ?? 0) + 1).first
    }

    private var onwardPlatform: String {
        let platform = interchange.onwardPlatform ?? onwardTrain?.departurePlatform ?? "TBC"
        let trimmed = platform.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "TBC" : trimmed
    }

    private var onwardDeparture: String {
        if let departure = onwardTrain?.departureTime, !departure.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return departure
        }
        let date = interchange.expectedDepartureDate ?? interchange.scheduledDepartureDate
        guard let date else {
            return "TBC"
        }
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "Europe/London")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private var marginText: String {
        switch interchange.riskStatus {
        case "missed":
            return "missed"
        case "tight":
            return "\(interchange.expectedMarginMinutes)m tight"
        case "at_risk":
            return "\(max(interchange.expectedMarginMinutes, 0))m spare"
        default:
            return "\(interchange.expectedMarginMinutes)m spare"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Get off at \(interchange.name)")
                .font(.title3.weight(.bold))
                .foregroundStyle(Color.rightTrainActivityText)
                .lineLimit(1)
                .minimumScaleFactor(0.54)
                .allowsTightening(true)
                .truncationMode(.middle)

            Text("Next: plat \(onwardPlatform) · \(onwardDeparture) · \(marginText)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(interchange.riskStatus == "tight" || interchange.riskStatus == "at_risk" ? Color.rightTrainActivityLate : Color.rightTrainActivitySecondaryText)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.58)
                .allowsTightening(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Get off at \(interchange.name), next train platform \(onwardPlatform), departs \(onwardDeparture), \(marginText)")
    }
}

private struct IslandTitle: View {
    var state: RightTrainLiveActivityAttributes.ContentState
    var activityKind: RightTrainLiveActivityAttributes.ActivityKind

    var body: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Color.rightTrainActivityText)
                .lineLimit(1)
                .minimumScaleFactor(0.58)
                .allowsTightening(true)
                .truncationMode(.middle)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(Color.rightTrainActivitySecondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.58)
                    .allowsTightening(true)
            }
        }
    }

    private var title: String {
        if activityKind == .train,
           let train = state.selectedTrain,
           train.isOnboard {
            return "To \(train.destinationName)"
        }
        if activityKind == .train,
           let train = state.selectedTrain {
            return "To \(train.serviceDestinationDisplayName)"
        }
        if activityKind == .leg, let train = state.activeItineraryTrain {
            // On a leg, the headline is the destination of the leg the
            // user is currently on (interchange for non-final legs).
            let phase = ItineraryPhase.from(rawValue: state.phase)
            if phase == .approachingInterchange, let interchange = state.interchange {
                return "Get off at \(interchange.name)"
            }
            return "To \(train.destinationName)"
        }
        return state.routeTitle
    }

    private var subtitle: String? {
        if activityKind == .leg {
            if ItineraryPhase.from(rawValue: state.phase) == .approachingInterchange,
               let interchange = state.interchange {
                return approachingSubtitle(interchange)
            }
            // Reuse the phase-aware otherDeparturesText that the
            // coordinator already computes ("Change at <name>",
            // "On the final train", etc.).
            if let value = state.otherDeparturesText, !value.isEmpty {
                return value
            }
            return state.itineraryIslandSubtitle
        }
        if activityKind == .itinerary {
            return state.itineraryIslandSubtitle
        }
        if activityKind == .window {
            return state.windowIslandSubtitle
        }
        return state.selectedTrain?.operatorDisplayText ?? state.compactUpdatedAtText
    }

    private func approachingSubtitle(_ interchange: RightTrainLiveActivityAttributes.ContentState.Interchange) -> String {
        "Next \(onwardDeparture(interchange)) · \(marginText(interchange))"
    }

    private func onwardDeparture(_ interchange: RightTrainLiveActivityAttributes.ContentState.Interchange) -> String {
        if let departure = state.onwardLeg?.departureTime,
           !departure.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return departure
        }
        let date = interchange.expectedDepartureDate ?? interchange.scheduledDepartureDate
        guard let date else {
            return "TBC"
        }
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "Europe/London")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func marginText(_ interchange: RightTrainLiveActivityAttributes.ContentState.Interchange) -> String {
        switch interchange.riskStatus {
        case "missed":
            return "missed"
        case "tight":
            return "\(interchange.expectedMarginMinutes)m tight"
        case "at_risk":
            return "\(max(interchange.expectedMarginMinutes, 0))m spare"
        default:
            return "\(interchange.expectedMarginMinutes)m spare"
        }
    }
}

private struct WindowBoardTrainList: View {
    var state: RightTrainLiveActivityAttributes.ContentState
    var maxVisibleTrains: Int

    private var visibleTrains: [RightTrainLiveActivityAttributes.ContentState.Train] {
        state.windowBoardVisibleTrains(maxVisibleTrains: maxVisibleTrains)
    }

    private var cancelledCount: Int {
        state.cancelledTrainCount ?? state.trains.filter { $0.statusKind == .cancelled }.count
    }

    private var departedCount: Int {
        state.departedTrainCount ?? state.trains.filter(\.departed).count
    }

    private var hiddenUpcomingCount: Int {
        let upcomingCount = state.upcomingTrainCount ?? state.trains.filter { !$0.departed && $0.statusKind != .cancelled && $0.statusKind != .arrived }.count
        return max(upcomingCount - visibleTrains.count, 0)
    }

    private var overflowText: String? {
        var segments: [String] = []
        if hiddenUpcomingCount > 0 {
            segments.append("\(hiddenUpcomingCount) later")
        }
        if departedCount > 0 {
            segments.append("\(departedCount) already departed")
        }
        if cancelledCount > 0 {
            segments.append("\(cancelledCount) cancelled")
        }
        guard !segments.isEmpty else {
            return nil
        }

        let prefix = visibleTrains.isEmpty ? "" : "Plus "
        return "\(prefix)\(segments.joined(separator: ", "))"
    }

    var body: some View {
        VStack(spacing: 0) {
            if visibleTrains.isEmpty, overflowText == nil {
                EmptyWindowText(text: state.windowEmptyStateText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            }

            ForEach(visibleTrains) { train in
                TimetableTrainRow(train: train)
                    .padding(.vertical, 3)

                if train.id != visibleTrains.last?.id {
                    Divider()
                        .overlay(Color.rightTrainActivityDivider)
                }
            }

            if let overflowText {
                if !visibleTrains.isEmpty {
                    Divider()
                        .overlay(Color.rightTrainActivityDivider)
                }

                Text(overflowText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.rightTrainActivitySecondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.58)
                    .allowsTightening(true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            }
        }
    }
}

private struct TimetableTrainRow: View {
    var train: RightTrainLiveActivityAttributes.ContentState.Train

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            HStack(spacing: 5) {
                ActivityTimeText(
                    scheduled: train.scheduledDepartureTime,
                    current: train.departureTime,
                    delayed: train.departureDelayed,
                    font: .headline.weight(.bold)
                )
                Image(systemName: "arrow.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.rightTrainActivitySecondaryText)
                ActivityTimeText(
                    scheduled: train.scheduledArrivalTime,
                    current: train.arrivalTime,
                    delayed: train.arrivalDelayed,
                    font: .headline.weight(.bold)
                )
            }
            .layoutPriority(1)

            Spacer(minLength: 4)

            HStack(spacing: 5) {
                PlatformBadge(text: "Plat \(train.departurePlatform)")
                if train.statusKind.isHeroAnomalous {
                    StatusBadge(text: train.statusText, kind: train.statusKind)
                }
            }
        }
        .opacity(train.departed ? 0.58 : 1)
    }
}

private struct CompactTrainRow: View {
    var train: RightTrainLiveActivityAttributes.ContentState.Train

    var body: some View {
        HStack(spacing: 6) {
            ActivityTimeText(scheduled: train.scheduledDepartureTime, current: train.departureTime, delayed: train.departureDelayed)
            Text("P\(train.departurePlatform)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.rightTrainActivitySecondaryText)
            Spacer(minLength: 4)
            if train.statusKind.isHeroAnomalous {
                Text(train.statusText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(train.statusKind.tint)
                    .lineLimit(1)
            }
        }
        .opacity(train.departed ? 0.58 : 1)
    }
}

private struct WindowBoardFooterRow: View {
    var train: RightTrainLiveActivityAttributes.ContentState.Train
    var otherDeparturesText: String?

    private var hasOperator: Bool {
        train.operatorDisplayText != nil
    }

    private var hasOtherDepartures: Bool {
        otherDeparturesText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    var body: some View {
        if hasOperator || hasOtherDepartures {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if hasOperator {
                    TrainOperatorFooterText(train: train)
                        .layoutPriority(0)
                }

                Spacer(minLength: 8)

                OtherDeparturesFooter(text: otherDeparturesText, alignment: .trailing)
                    .layoutPriority(1)
            }
        }
    }
}

private struct TrainOperatorFooterText: View {
    var train: RightTrainLiveActivityAttributes.ContentState.Train

    var body: some View {
        ViewThatFits(in: .horizontal) {
            if let operatorName = train.operatorNameDisplayText {
                text(operatorName)
            }

            if let operatorCode = train.operatorCodeDisplayText {
                text(operatorCode)
            }
        }
        .accessibilityLabel(train.operatorDisplayText ?? "")
    }

    private func text(_ value: String) -> some View {
        Text(value)
            .font(.caption.weight(.medium))
            .foregroundStyle(Color.rightTrainActivitySecondaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.58)
            .allowsTightening(true)
    }
}

private struct OtherDeparturesFooter: View {
    var text: String?
    var compact = false
    var alignment: Alignment = .leading

    var body: some View {
        if let text,
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text(text)
                .font(compact ? .caption2.weight(.medium) : .caption.weight(.medium))
                .foregroundStyle(Color.rightTrainActivitySecondaryText)
                .lineLimit(1)
                .minimumScaleFactor(compact ? 0.58 : 0.65)
                .allowsTightening(true)
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: alignment)
                .accessibilityLabel(text)
        }
    }
}

private struct JourneyProgressFooter: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var train: RightTrainLiveActivityAttributes.ContentState.Train
    var originText: String
    var destinationText: String

    private var progress: Double {
        if let journeyProgress = train.journeyProgress {
            return min(max(journeyProgress, 0), 1)
        }
        if train.statusKind == .arrived {
            return 1
        }
        return 0
    }

    private var liveDotShouldAnimate: Bool {
        progress > 0 && progress < 1 && train.statusKind != .cancelled && train.statusKind != .missed
    }

    private var dotTint: Color {
        switch train.statusKind {
        case .cancelled:
            return .rightTrainActivityDanger
        case .delayed, .unreported, .notReported:
            return .rightTrainActivityLate
        case .unknown:
            return .rightTrainActivityUnknown
        default:
            return .rightTrainActivityAccent
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            endpointText(originText)

            GeometryReader { proxy in
                let dotSize: CGFloat = 11
                let usableWidth = max(proxy.size.width - dotSize, 0)
                let dotOffset = usableWidth * CGFloat(progress)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.rightTrainActivityDivider)
                        .frame(height: 3)

                    Capsule()
                        .fill(dotTint.opacity(0.45))
                        .frame(width: max(dotSize / 2, dotOffset + dotSize / 2), height: 3)

                    Image(systemName: "circle.fill")
                        .font(.system(size: dotSize, weight: .bold))
                        .foregroundStyle(dotTint)
                        .frame(width: dotSize, height: dotSize)
                        .shadow(color: dotTint.opacity(0.95), radius: 6)
                        .shadow(color: dotTint.opacity(0.55), radius: 12)
                        .overlay {
                            Circle()
                                .stroke(Color.white.opacity(0.42), lineWidth: 1)
                        }
                        .symbolEffect(.variableColor.iterative, options: .repeating, isActive: liveDotShouldAnimate && !reduceMotion)
                        .offset(x: dotOffset)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 18)

            endpointText(destinationText)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Journey progress \(Int((progress * 100).rounded())) percent")
    }

    private func endpointText(_ value: String) -> some View {
        Text(value)
            .font(.caption2.weight(.bold))
            .foregroundStyle(Color.rightTrainActivitySecondaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.58)
            .allowsTightening(true)
            .frame(minWidth: 28)
    }
}

private struct EmptyWindowText: View {
    var text: String
    var compact = false

    var body: some View {
        if compact {
            Text(text)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.rightTrainActivitySecondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.58)
                .allowsTightening(true)
                .accessibilityLabel(text)
        } else {
            HStack(alignment: .center, spacing: 9) {
                Image(systemName: symbolName)
                    .font(.title3.weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(tint)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(text)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.rightTrainActivityText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)
                        .allowsTightening(true)
                    Text(hint)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Color.rightTrainActivitySecondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.58)
                        .allowsTightening(true)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(text). \(hint)")
        }
    }

    private var symbolName: String {
        switch text {
        case "All trains departed":
            return "moon.zzz.fill"
        case "All trains cancelled":
            return "bell.slash.fill"
        default:
            return "magnifyingglass"
        }
    }

    private var tint: Color {
        switch text {
        case "All trains cancelled":
            return .rightTrainActivityDanger
        default:
            return .rightTrainActivityAccent
        }
    }

    private var hint: String {
        switch text {
        case "All trains departed":
            return "Open RightTrain to add another window"
        case "All trains cancelled":
            return "Open RightTrain to choose another train"
        default:
            return "Open RightTrain to adjust the search"
        }
    }
}

private struct CompactTrainDetail: View {
    var train: RightTrainLiveActivityAttributes.ContentState.Train
    var platformChange: RightTrainLiveActivityAttributes.ContentState.PlatformChange? = nil

    var body: some View {
        ViewThatFits(in: .horizontal) {
            detailRow(showPlatform: true, showStatusText: true)
            detailRow(showPlatform: false, showStatusText: true)
            detailRow(showPlatform: false, showStatusText: false)
        }
    }

    private func detailRow(showPlatform: Bool, showStatusText: Bool) -> some View {
        HStack(spacing: 6) {
            StatusGlyph(kind: train.statusKind, delayMinutes: train.delayMinutes)
            ActivityTimeText(scheduled: train.scheduledArrivalTime, current: train.arrivalTime, delayed: train.arrivalDelayed)
            if showPlatform {
                if let platformChange {
                    CompactPlatformChangeText(change: platformChange)
                } else {
                    Text(compactArrivalPlatformText)
                        .font(.caption2)
                        .foregroundStyle(Color.rightTrainActivitySecondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)
                        .allowsTightening(true)
                }
            }
            Spacer(minLength: 2)
            if showStatusText, train.statusKind != .good {
                Text(train.statusKind.compactText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(train.statusKind.tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                    .allowsTightening(true)
            }
        }
    }

    private var compactArrivalPlatformText: String {
        let platform = readablePlatformValue(train.arrivalPlatform)
        return platform.uppercased() == "TBC" ? "Arr plat TBC" : "Arr P\(platform)"
    }
}

private struct CompactOnboardTrainDetail: View {
    var train: RightTrainLiveActivityAttributes.ContentState.Train
    var originText: String
    var destinationText: String

    private var progress: Double {
        train.journeyProgress ?? 0
    }

    var body: some View {
        HStack(alignment: .center, spacing: 7) {
            endpointText(originText)
            TimelineProgressHairline(progress: progress)
            endpointText(destinationText)
        }
    }

    private func endpointText(_ value: String) -> some View {
        Text(value)
            .font(.caption2.weight(.bold))
            .foregroundStyle(Color.rightTrainActivitySecondaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.58)
            .allowsTightening(true)
            .frame(minWidth: 28)
    }
}

private struct CompactItineraryDetail: View {
    var state: RightTrainLiveActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    StatusGlyph(kind: state.statusKind, delayMinutes: state.delayMinutes)
                    summaryText(primaryText)
                    Spacer(minLength: 2)
                    if state.statusKind.isHeroAnomalous {
                        summaryText(state.statusKind.compactText)
                            .foregroundStyle(state.statusKind.tint)
                    }
                }

                HStack(spacing: 6) {
                    StatusGlyph(kind: state.statusKind, delayMinutes: state.delayMinutes)
                    summaryText(primaryText)
                }
            }
            EmptyWindowText(text: state.itineraryConnectionFooterText, compact: true)
        }
    }

    private var primaryText: String {
        if state.resolvedPhase == .approachingInterchange,
           let interchange = state.interchange {
            let platform = interchange.onwardPlatform?.trimmingCharacters(in: .whitespacesAndNewlines)
            let platformText: String
            if let platform, !platform.isEmpty {
                platformText = "P\(platform)"
            } else {
                platformText = "P TBC"
            }
            return "Get off · \(platformText)"
        }
        if state.resolvedPhase.isOnboard,
           let train = state.activeItineraryTrain {
            return "Arr \(train.arrivalTime)"
        }
        if let train = state.activeItineraryTrain {
            return "Dep \(train.departureTime)"
        }
        return state.compactItinerarySummaryText
    }

    private func summaryText(_ value: String) -> some View {
        Text(value)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Color.rightTrainActivityText)
            .lineLimit(1)
            .minimumScaleFactor(0.62)
            .allowsTightening(true)
    }
}

private struct CountdownHeroBlock: View {
    enum Mode {
        case departure
        case arrival
    }

    var train: RightTrainLiveActivityAttributes.ContentState.Train
    var mode: Mode = .departure

    private var targetDate: Date? {
        switch mode {
        case .departure:
            return train.departureDate ?? train.scheduledDepartureDate
        case .arrival:
            return train.arrivalDate ?? train.scheduledArrivalDate
        }
    }

    private var clockText: String {
        switch mode {
        case .departure: return train.departureTime
        case .arrival: return train.arrivalTime
        }
    }

    private var countsDown: Bool {
        guard let targetDate else {
            return false
        }
        return !train.departed && targetDate > Date()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(eyebrow)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.rightTrainActivitySecondaryText)
                .lineLimit(1)

            ViewThatFits(in: .horizontal) {
                heroLabel(font: .largeTitle.weight(.bold), compact: false)
                heroLabel(font: .title.weight(.bold), compact: false)
                heroLabel(font: .title2.weight(.bold), compact: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private func heroLabel(font: Font, compact: Bool) -> some View {
        Group {
            if compact {
                Text(compactHeroText)
            } else {
                heroText
            }
        }
        .font(font)
        .fontDesign(.rounded)
        .foregroundStyle(heroTint)
        .monospacedDigit()
        .contentTransition(.numericText(countsDown: countsDown))
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .allowsTightening(true)
    }

    @ViewBuilder private var heroText: some View {
        switch heroTextKind {
        case .cancelled:
            Text("Cancelled")
        case .departed(let date):
            MinuteRelativeText(date: date, prefix: mode == .arrival ? "Arrived " : "Departed ", suffix: " ago")
        case .boarding:
            Text(mode == .arrival ? "Arriving" : "Boarding")
        case .relative(let date):
            MinuteRelativeText(date: date)
        case .awaiting:
            Text("Awaiting")
        case .clock:
            Text(clockText)
        }
    }

    private enum HeroTextKind {
        case cancelled
        case departed(Date)
        case boarding
        case relative(Date)
        case awaiting
        case clock
    }

    private var heroTextKind: HeroTextKind {
        if train.statusKind == .cancelled {
            return .cancelled
        }
        if mode == .departure, train.departed, let targetDate {
            return .departed(targetDate)
        }
        if mode == .arrival, train.statusKind == .arrived, let targetDate {
            return .departed(targetDate)
        }
        if let targetDate, isBoarding(targetDate) {
            return .boarding
        }
        if let targetDate, targetDate > Date() {
            return .relative(targetDate)
        }
        if targetDate != nil {
            return .awaiting
        }
        return .clock
    }

    private var compactHeroText: String {
        switch heroTextKind {
        case .cancelled:
            return "Cncl"
        case .departed:
            return mode == .arrival ? "Arr" : "Left"
        case .boarding:
            return mode == .arrival ? "Arr" : "Board"
        case .relative:
            return clockText
        case .awaiting:
            return "Wait"
        case .clock:
            return clockText
        }
    }

    private var eyebrow: String {
        switch train.statusKind {
        case .cancelled:
            return "Service"
        case .arrived:
            return "Arrived"
        default:
            switch mode {
            case .departure:
                return train.departed ? "Left" : "Departs"
            case .arrival:
                return "Arrives"
            }
        }
    }

    private var heroTint: Color {
        switch train.statusKind {
        case .cancelled, .missed:
            return .rightTrainActivityDanger
        case .delayed, .atRisk, .unreported, .notReported:
            return train.delayMinutes >= 25 ? .rightTrainActivityDanger : .rightTrainActivityLate
        default:
            return .rightTrainActivityText
        }
    }

    private var accessibilityLabel: String {
        var parts = [eyebrow]
        if let targetDate {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            parts.append(formatter.localizedString(for: targetDate, relativeTo: Date()))
        } else {
            parts.append(clockText)
        }
        let scheduled = mode == .arrival ? train.scheduledArrivalTime : train.scheduledDepartureTime
        parts.append("scheduled \(scheduled)")
        let delayed = mode == .arrival ? train.arrivalDelayed : train.departureDelayed
        if delayed {
            parts.append("now \(clockText)")
        }
        return parts.joined(separator: ", ")
    }

    private func isBoarding(_ date: Date) -> Bool {
        let interval = date.timeIntervalSinceNow
        return interval <= 60 && interval >= -60 && !train.departed
    }
}

private struct JourneyHeroBlock: View {
    var train: RightTrainLiveActivityAttributes.ContentState.Train

    private var targetDate: Date? {
        train.departureDate ?? train.scheduledDepartureDate
    }

    private var countsDown: Bool {
        guard let targetDate else { return false }
        return !train.departed && targetDate > Date()
    }

    private var isCancelled: Bool {
        train.statusKind == .cancelled
    }

    private var isBoarding: Bool {
        guard let targetDate, !train.departed else { return false }
        let interval = targetDate.timeIntervalSinceNow
        return interval <= 60 && interval >= -60
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            eyebrow
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.rightTrainActivitySecondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .allowsTightening(true)
                .contentTransition(.numericText(countsDown: countsDown))

            if isCancelled {
                Text("Cancelled")
                    .font(.title.weight(.bold))
                    .fontDesign(.rounded)
                    .foregroundStyle(Color.rightTrainActivityDanger)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .allowsTightening(true)
            } else {
                ViewThatFits(in: .horizontal) {
                    departureTime(font: .title.weight(.bold))
                    departureTime(font: .title2.weight(.bold))
                    departureTime(font: .title3.weight(.bold))
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder private var eyebrow: some View {
        if isCancelled {
            Text("Service")
        } else if train.departed, let targetDate {
            MinuteRelativeText(date: targetDate, prefix: "Departed ", suffix: " ago")
        } else if isBoarding {
            Text("Boarding")
        } else if let targetDate, targetDate > Date() {
            MinuteRelativeText(date: targetDate, prefix: "Departs in ")
        } else if targetDate != nil {
            Text("Awaiting")
        } else {
            Text("Departs")
        }
    }

    private func departureTime(font: Font) -> some View {
        ActivityTimeText(
            scheduled: train.scheduledDepartureTime,
            current: train.departureTime,
            delayed: train.departureDelayed,
            font: font
        )
        .fontDesign(.rounded)
    }

    private var accessibilityLabel: String {
        var parts: [String] = []
        if isCancelled {
            parts.append("Service cancelled")
            return parts.joined(separator: ", ")
        }
        if train.departed, let targetDate {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            parts.append("Departed " + formatter.localizedString(for: targetDate, relativeTo: Date()))
        } else if isBoarding {
            parts.append("Boarding")
        } else if let targetDate, targetDate > Date() {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            parts.append("Departs " + formatter.localizedString(for: targetDate, relativeTo: Date()))
        } else {
            parts.append("Departs \(train.departureTime)")
        }
        parts.append("scheduled departure \(train.scheduledDepartureTime)")
        if train.departureDelayed {
            parts.append("now \(train.departureTime)")
        }
        return parts.joined(separator: ", ")
    }
}

private struct SecondaryTimeRow: View {
    var departureLabel: String
    var scheduledDeparture: String
    var currentDeparture: String
    var departureDelayed: Bool
    var arrivalLabel: String
    var scheduledArrival: String
    var currentArrival: String
    var arrivalDelayed: Bool

    var body: some View {
        ViewThatFits(in: .horizontal) {
            timeRow(showLabels: true, font: .subheadline.weight(.semibold), spacing: 6)
            timeRow(showLabels: false, font: .subheadline.weight(.semibold), spacing: 5)
            timeRow(showLabels: false, font: .caption.weight(.bold), spacing: 4)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.58)
        .allowsTightening(true)
    }

    private func timeRow(showLabels: Bool, font: Font, spacing: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: spacing) {
            if showLabels {
                secondaryLabel(departureLabel)
            }
            ActivityTimeText(
                scheduled: scheduledDeparture,
                current: currentDeparture,
                delayed: departureDelayed,
                font: font
            )
            Image(systemName: "arrow.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.rightTrainActivitySecondaryText)
            if showLabels {
                secondaryLabel(arrivalLabel)
            }
            ActivityTimeText(
                scheduled: scheduledArrival,
                current: currentArrival,
                delayed: arrivalDelayed,
                font: font
            )
            Spacer(minLength: 0)
        }
    }

    private func secondaryLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(Color.rightTrainActivitySecondaryText)
    }
}

private struct InlinePlatformLabel: View {
    var label: String = "Plat"
    var platform: String
    var confirmed: Bool
    var accessibilityPrefix: String = "Departure platform"
    var platformChange: RightTrainLiveActivityAttributes.ContentState.PlatformChange? = nil

    private var platformText: String {
        platform.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasKnownPlatform: Bool {
        !platformText.isEmpty && platformText.uppercased() != "TBC" && platformText != "-"
    }

    private var platformDisplayValue: String {
        readablePlatformValue(platformText)
    }

    private var compactPlatformValue: String {
        compactPlatformDisplayValue(platformText)
    }

    var body: some View {
        Group {
            if let platformChange, hasKnownPlatform {
                PlatformChangeBadge(change: platformChange)
            } else if hasKnownPlatform {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 5) {
                        platformLabel(text: "\(label) \(platformDisplayValue)", includesIcon: true)
                    }
                    HStack(spacing: 4) {
                        platformLabel(text: compactPlatformValue, includesIcon: false)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityLabel)
            } else {
                tbcBadge
                    .font(.subheadline.weight(.bold))
                    .accessibilityLabel("\(accessibilityPrefix) to be confirmed")
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.58)
        .allowsTightening(true)
        .layoutPriority(1)
    }

    @ViewBuilder
    private func platformLabel(text: String, includesIcon: Bool) -> some View {
        // Unconfirmed platforms render in italics, matching the departure-board
        // convention for an estimated platform.
        if includesIcon {
            HStack(spacing: 4) {
                Image(systemName: "tram.fill")
                    .imageScale(.small)
                Text(text)
                    .italic(!confirmed)
            }
            .font(.subheadline.weight(.bold))
            .foregroundStyle(Color.rightTrainActivityText)
        } else {
            Text(text)
                .italic(!confirmed)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.rightTrainActivityText)
        }
    }

    @ViewBuilder
    private var tbcBadge: some View {
        Text("TBC")
            .font(.caption.weight(.bold))
            .foregroundStyle(Color.rightTrainActivityLate)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Color.rightTrainActivityLate.opacity(0.14), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(Color.rightTrainActivityLate.opacity(0.36), lineWidth: 1)
            }
    }

    private var accessibilityLabel: String {
        confirmed ? "\(accessibilityPrefix) \(platformDisplayValue)" : "\(accessibilityPrefix) \(platformDisplayValue), not confirmed"
    }
}

private struct PlatformChangeBadge: View {
    var change: RightTrainLiveActivityAttributes.ContentState.PlatformChange

    private var previous: String {
        readablePlatformValue(change.previousPlatform)
    }

    private var current: String {
        readablePlatformValue(change.currentPlatform)
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            label(text: "Plat \(previous) -> \(current)", includesIcon: true)
            label(text: "\(compactPlatformDisplayValue(change.previousPlatform))->\(compactPlatformDisplayValue(change.currentPlatform))", includesIcon: false)
            label(text: compactPlatformDisplayValue(change.currentPlatform), includesIcon: false)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Departure platform changed from \(previous) to \(current)")
    }

    private func label(text: String, includesIcon: Bool) -> some View {
        HStack(spacing: 5) {
            if includesIcon {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .imageScale(.small)
            }
            Text(text)
        }
        .font(.subheadline.weight(.bold))
        .foregroundStyle(Color.rightTrainActivityLate)
        .lineLimit(1)
        .minimumScaleFactor(0.58)
        .allowsTightening(true)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Color.rightTrainActivityLate.opacity(0.14), in: Capsule())
        .overlay {
            Capsule()
                .stroke(Color.rightTrainActivityLate.opacity(0.36), lineWidth: 1)
        }
    }
}

private struct DisruptionSummaryLine: View {
    var text: String
    var kind: RightTrainLiveActivityAttributes.StatusKind

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(kind == .good ? Color.rightTrainActivitySecondaryText : kind.tint)
            .lineLimit(1)
            .minimumScaleFactor(0.58)
            .allowsTightening(true)
            .contentTransition(.numericText())
            .accessibilityLabel(text)
    }
}

private struct InterchangeBanner: View {
    var interchange: RightTrainLiveActivityAttributes.ContentState.Interchange
    var approaching: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: approaching ? "figure.walk.diamond.fill" : "arrow.triangle.swap")
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.rightTrainActivityText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                    .allowsTightening(true)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Color.rightTrainActivitySecondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .allowsTightening(true)
                }
            }
            Spacer(minLength: 4)
            if let platform = onwardPlatformDisplay {
                Text("Plat \(platform)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.rightTrainActivityText)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(tint.opacity(0.18), in: Capsule())
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(tint.opacity(approaching ? 0.55 : 0.25), lineWidth: approaching ? 1.5 : 1)
        )
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        approaching ? "Get off at \(interchange.name)" : interchange.transferTitle ?? "Change at \(interchange.name)"
    }

    private var subtitle: String? {
        let parts = [marginText, departureText].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var marginText: String? {
        switch interchange.riskStatus {
        case "missed":
            return "Missed connection"
        case "at_risk":
            return interchange.expectedMarginMinutes > 0
                ? "At risk · \(interchange.expectedMarginMinutes)m spare"
                : "At risk"
        case "tight":
            return "Tight · \(max(interchange.expectedMarginMinutes, 0))m spare"
        default:
            return interchange.expectedMarginMinutes > 0 ? "\(interchange.expectedMarginMinutes)m spare" : nil
        }
    }

    private var departureText: String? {
        let date = interchange.expectedDepartureDate ?? interchange.scheduledDepartureDate
        guard let date else { return nil }
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "Europe/London")
        formatter.dateFormat = "HH:mm"
        return "Onward \(formatter.string(from: date))"
    }

    private var onwardPlatformDisplay: String? {
        guard let platform = interchange.onwardPlatform?.trimmingCharacters(in: .whitespacesAndNewlines),
              !platform.isEmpty else {
            return nil
        }
        return platform
    }

    private var tint: Color {
        switch interchange.riskStatus {
        case "missed":
            return RightTrainLiveActivityAttributes.StatusKind.cancelled.tint
        case "at_risk", "tight":
            return RightTrainLiveActivityAttributes.StatusKind.delayed.tint
        default:
            return approaching
                ? RightTrainLiveActivityAttributes.StatusKind.delayed.tint
                : .rightTrainActivityAccent
        }
    }
}

private struct PinnedTimeBlock: View {
    var label: String
    var scheduled: String
    var current: String
    var delayed: Bool
    var font: Font = .title3.weight(.bold)

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(Color.rightTrainActivitySecondaryText)
            ActivityTimeText(scheduled: scheduled, current: current, delayed: delayed, font: font)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TimeBlock: View {
    enum Kind {
        case departure
        case arrival
    }

    var label: String
    var train: RightTrainLiveActivityAttributes.ContentState.Train
    var kind: Kind

    private var scheduled: String {
        switch kind {
        case .departure:
            return train.scheduledDepartureTime
        case .arrival:
            return train.scheduledArrivalTime
        }
    }

    private var current: String {
        switch kind {
        case .departure:
            return train.departureTime
        case .arrival:
            return train.arrivalTime
        }
    }

    private var delayed: Bool {
        switch kind {
        case .departure:
            return train.departureDelayed
        case .arrival:
            return train.arrivalDelayed
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(Color.rightTrainActivitySecondaryText)
            ActivityTimeText(scheduled: scheduled, current: current, delayed: delayed, font: .title3.weight(.bold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PlatformBlock: View {
    var label: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(Color.rightTrainActivitySecondaryText)
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.rightTrainActivityText)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ActivityTimeText: View {
    var scheduled: String
    var current: String
    var delayed: Bool
    var font: Font = .caption.weight(.bold)

    private var hasOverride: Bool {
        current.trimmingCharacters(in: .whitespacesAndNewlines) != scheduled.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Group {
            if hasOverride {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 4) {
                        Text(scheduled)
                            .strikethrough(true, color: Color.rightTrainActivitySecondaryText)
                            .foregroundStyle(Color.rightTrainActivitySecondaryText)
                        Text(current)
                            .foregroundStyle(delayed ? Color.rightTrainActivityLate : Color.rightTrainActivityText)
                    }

                    HStack(spacing: 2) {
                        Image(systemName: "clock")
                            .imageScale(.small)
                            .foregroundStyle(delayed ? Color.rightTrainActivityLate : Color.rightTrainActivitySecondaryText)
                        Text(current)
                            .foregroundStyle(delayed ? Color.rightTrainActivityLate : Color.rightTrainActivityText)
                    }

                    Text(current)
                        .foregroundStyle(delayed ? Color.rightTrainActivityLate : Color.rightTrainActivityText)
                }
            } else {
                Text(scheduled)
                    .foregroundStyle(Color.rightTrainActivityText)
            }
        }
        .font(font)
        .monospacedDigit()
        .contentTransition(.numericText())
        .lineLimit(1)
        .minimumScaleFactor(0.58)
        .allowsTightening(true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        if hasOverride {
            return "\(scheduled), now \(current)"
        }
        return scheduled
    }
}

private struct IslandMetric: View {
    var label: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(Color.rightTrainActivitySecondaryText)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.rightTrainActivityText)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.58)
                .allowsTightening(true)
        }
    }
}

private struct IslandEdgeMetric: View {
    var label: String
    var value: String
    var tint: Color = .rightTrainActivityText
    var edge: IslandExpandedEdge = .leading

    var body: some View {
        Text(value)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.58)
            .allowsTightening(true)
            .frame(maxWidth: IslandExpandedEdge.contentMaxWidth, alignment: edge.alignment)
            .padding(edge.paddingEdges, IslandExpandedEdge.safeInset)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(value)
    }

    private var accessibilityLabel: String {
        switch label {
        case "Best":
            return "Best departure"
        case "Dep":
            return "Departure"
        case "Arr":
            return "Arrival"
        case "Dep plat":
            return "Departure platform"
        case "Arr plat":
            return "Arrival platform"
        case "Onward":
            return "Onward platform"
        default:
            return label
        }
    }
}

private struct PlatformChangeIslandMetric: View {
    var change: RightTrainLiveActivityAttributes.ContentState.PlatformChange
    var edge: IslandExpandedEdge = .leading

    var body: some View {
        IslandEdgeMetric(
            label: "Changed",
            value: "\(compactPlatformDisplayValue(change.previousPlatform))->\(compactPlatformDisplayValue(change.currentPlatform))",
            tint: .rightTrainActivityLate,
            edge: edge
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Departure platform changed from \(readablePlatformValue(change.previousPlatform)) to \(readablePlatformValue(change.currentPlatform))")
    }
}

private struct RelativeIslandEdgeMetric: View {
    var label: String
    var date: Date
    var clockText: String? = nil
    var countsDown: Bool
    var edge: IslandExpandedEdge = .leading

    var body: some View {
        valueText
            .frame(maxWidth: IslandExpandedEdge.contentMaxWidth, alignment: edge.alignment)
            .padding(edge.paddingEdges, IslandExpandedEdge.safeInset)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(accessibilityValue)
    }

    @ViewBuilder
    private var valueText: some View {
        if countsDown {
            MinuteRelativeText(date: date)
                .contentTransition(.numericText(countsDown: true))
                .metricTextStyle()
        } else if let clockText, !clockText.isEmpty {
            Text(clockText)
                .metricTextStyle()
        } else {
            MinuteRelativeText(date: date)
                .contentTransition(.numericText(countsDown: false))
                .metricTextStyle()
        }
    }

    private var accessibilityLabel: String {
        switch label {
        case "Best":
            return "Best departure"
        case "Arr":
            return "Arrival"
        default:
            return "Departure"
        }
    }

    private var accessibilityValue: String {
        let relative = RelativeDateTimeFormatter()
        relative.unitsStyle = .full
        let relativeText = relative.localizedString(for: date, relativeTo: Date())
        if let clockText, !clockText.isEmpty {
            return "\(relativeText), \(clockText)"
        }
        return relativeText
    }
}

private enum IslandExpandedEdge {
    static let contentMaxWidth: CGFloat = 62
    static let safeInset: CGFloat = 14

    case leading
    case trailing

    var alignment: Alignment {
        switch self {
        case .leading:
            return .leading
        case .trailing:
            return .trailing
        }
    }

    var paddingEdges: Edge.Set {
        switch self {
        case .leading:
            return .leading
        case .trailing:
            return .trailing
        }
    }
}

private struct RelativeIslandMetric: View {
    var label: String
    var date: Date
    var clockText: String? = nil
    var countsDown: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(Color.rightTrainActivitySecondaryText)
            valueText
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
    }

    @ViewBuilder
    private var valueText: some View {
        if countsDown {
            MinuteRelativeText(date: date)
                .contentTransition(.numericText(countsDown: true))
                .metricTextStyle()
        } else if let clockText, !clockText.isEmpty {
            Text(clockText)
                .metricTextStyle()
        } else {
            MinuteRelativeText(date: date)
                .contentTransition(.numericText(countsDown: false))
                .metricTextStyle()
        }
    }

    private var accessibilityLabel: String {
        switch label {
        case "Best":
            return "Best departure"
        case "Arr":
            return "Arrival"
        default:
            return "Departure"
        }
    }

    private var accessibilityValue: String {
        let relative = RelativeDateTimeFormatter()
        relative.unitsStyle = .full
        let relativeText = relative.localizedString(for: date, relativeTo: Date())
        if let clockText, !clockText.isEmpty {
            return "\(relativeText), \(clockText)"
        }
        return relativeText
    }
}

private extension View {
    func metricTextStyle() -> some View {
        self
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.rightTrainActivityText)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.58)
            .allowsTightening(true)
    }
}

struct MinuteRelativeText: View {
    var date: Date
    var prefix: String = ""
    var suffix: String = ""

    var body: some View {
        TimelineView(.everyMinute) { context in
            Text(prefix + Self.durationText(from: date, now: context.date) + suffix)
        }
    }

    static func durationText(from date: Date, now: Date) -> String {
        let totalMinutes = max(0, Int(abs(date.timeIntervalSince(now)) / 60))
        if totalMinutes == 0 {
            return "less than a min"
        }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        var parts: [String] = []
        if hours > 0 { parts.append("\(hours) hr") }
        if minutes > 0 { parts.append("\(minutes) min") }
        return parts.joined(separator: " ")
    }
}

private struct StatusBadge: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var text: String
    var kind: RightTrainLiveActivityAttributes.StatusKind
    var delayMinutes: Int? = nil

    private var effectiveDelayMinutes: Int {
        if let delayMinutes {
            return delayMinutes
        }
        let digits = text.split(whereSeparator: { !$0.isNumber }).compactMap { Int(String($0)) }
        return digits.max() ?? 0
    }

    private var tint: Color {
        kind.tint(delayMinutes: effectiveDelayMinutes)
    }

    private var severeDelay: Bool {
        effectiveDelayMinutes >= 15 && (kind == .delayed || kind == .atRisk || kind == .unreported || kind == .notReported)
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            badgeText(text)
            badgeText(kind.compactText)
            statusLight
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private func badgeText(_ value: String) -> some View {
        HStack(spacing: 4) {
            if severeDelay || kind == .cancelled || kind == .missed || kind == .atRisk {
                Image(systemName: kind.symbolName)
                    .imageScale(.small)
                    .symbolEffect(.pulse, options: .repeating, isActive: severeDelay && !reduceMotion)
            }
            Text(displayText(for: value))
        }
        .font(.caption.weight(.semibold))
        .lineLimit(1)
        .minimumScaleFactor(0.58)
        .allowsTightening(true)
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(tint.opacity(backgroundOpacity), in: Capsule())
        .overlay {
            Capsule()
                .stroke(tint.opacity(0.35), lineWidth: 1)
        }
        .contentTransition(.numericText())
    }

    private var statusLight: some View {
        Image(systemName: kind.symbolName)
            .font(.caption2.weight(.bold))
            .foregroundStyle(tint)
            .symbolEffect(.pulse, options: .repeating, isActive: severeDelay && !reduceMotion)
            .frame(width: 10, height: 10)
            .padding(5)
            .background(tint.opacity(backgroundOpacity), in: Circle())
            .overlay {
                Circle()
                    .stroke(tint.opacity(0.38), lineWidth: 1)
            }
    }

    private var backgroundOpacity: Double {
        if effectiveDelayMinutes >= 25 {
            return 0.22
        }
        if effectiveDelayMinutes >= 12 {
            return 0.19
        }
        return 0.14
    }

    private func displayText(for value: String) -> String {
        guard kind == .delayed, effectiveDelayMinutes > 0 else {
            return value
        }
        if value == kind.compactText {
            return "+\(effectiveDelayMinutes)"
        }
        if value.localizedCaseInsensitiveContains("delayed") || value.localizedCaseInsensitiveContains("late") {
            return "+\(effectiveDelayMinutes) Late"
        }
        return value
    }

    private var accessibilityLabel: String {
        if effectiveDelayMinutes > 0,
           kind == .delayed || kind == .atRisk || kind == .unreported || kind == .notReported {
            return "\(kind.accessibilityLabel), \(effectiveDelayMinutes) minutes late"
        }
        return text.isEmpty ? kind.accessibilityLabel : text
    }
}

private struct PlatformBadge: View {
    var text: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            badgeText(text)
            badgeText(compactText)
        }
        .accessibilityLabel(text)
    }

    private var compactText: String {
        text
            .replacingOccurrences(of: "Platform ", with: "P")
            .replacingOccurrences(of: "Plat ", with: "P")
    }

    private func badgeText(_ value: String) -> some View {
        Text(value)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.58)
            .allowsTightening(true)
            .foregroundStyle(Color.rightTrainActivityText)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Color.rightTrainActivityAccent.opacity(0.14), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(Color.rightTrainActivityAccent.opacity(0.35), lineWidth: 1)
            }
    }
}

private struct DeparturePlatformChip: View {
    var platform: String

    var body: some View {
        VStack(spacing: 1) {
            Text("Plat")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.rightTrainActivitySecondaryText)
                .lineLimit(1)
            Text(platform)
                .font(.title3.weight(.bold))
                .foregroundStyle(Color.rightTrainActivityText)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
        }
        .frame(width: 54, height: 54)
        .background(Color.rightTrainActivityAccent.opacity(0.14), in: RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color.rightTrainActivityAccent.opacity(0.38), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        platform.uppercased() == "TBC" ? "Departure platform to be confirmed" : "Departure platform \(platform)"
    }
}

private struct StatusGlyph: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var kind: RightTrainLiveActivityAttributes.StatusKind
    var delayMinutes: Int? = nil

    private var severeDelay: Bool {
        (delayMinutes ?? 0) >= 15 && (kind == .delayed || kind == .atRisk || kind == .unreported || kind == .notReported)
    }

    private var tint: Color {
        kind.tint(delayMinutes: delayMinutes ?? 0)
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 2) {
                Image(systemName: kind.symbolName)
                    .imageScale(.medium)
                    .symbolEffect(.pulse, options: .repeating, isActive: severeDelay && !reduceMotion)
                Text(kind.compactText)
                    .font(.caption2.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.58)
                    .allowsTightening(true)
            }

            Image(systemName: kind.symbolName)
                .imageScale(.medium)
                .symbolEffect(.pulse, options: .repeating, isActive: severeDelay && !reduceMotion)
        }
        .foregroundStyle(tint)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        guard let delayMinutes, delayMinutes > 0,
              kind == .delayed || kind == .atRisk || kind == .unreported || kind == .notReported else {
            return kind.accessibilityLabel
        }
        return "\(kind.accessibilityLabel), \(delayMinutes) minutes late"
    }
}

private extension RightTrainLiveActivityAttributes.ContentState {
    var compactRouteTitle: String {
        let origin = nonEmpty(originShortName) ?? nonEmpty(originCrs) ?? nonEmpty(originName) ?? "Origin"
        let destination = nonEmpty(destinationShortName) ?? nonEmpty(destinationCrs) ?? nonEmpty(destinationName) ?? "Dest"
        return "\(origin) to \(destination)"
    }

    var activeItineraryTrain: RightTrainLiveActivityAttributes.ContentState.Train? {
        // Once a leg is being travelled (on_leg / approaching_interchange /
        // on_final_leg), the active train is the one indexed by
        // currentLegIndex — not the next "still-to-depart" leg. Falling
        // back to the upcoming-leg heuristic for planning / at_origin.
        if resolvedPhase.isOnboard, let index = currentLegIndex, index >= 0, index < trains.count {
            return trains[index]
        }
        return trains.first { !$0.departed && $0.statusKind != .cancelled && $0.statusKind != .arrived }
            ?? trains.last
    }

    var resolvedPhase: ItineraryPhase {
        ItineraryPhase.from(rawValue: phase)
    }

    var compactItinerarySummaryText: String {
        if let value = nonEmpty(windowTimeRangeText) {
            return value
        }
        if windowTrainCount == 1 || trains.count == 1 {
            return "Direct"
        }
        let legCount = windowTrainCount ?? trains.count
        return "\(max(legCount - 1, 0)) \(max(legCount - 1, 0) == 1 ? "change" : "changes")"
    }

    var itineraryHeaderSubtitle: AttributedString {
        var subtitle = AttributedString()
        func append(_ text: String, color: Color = .rightTrainActivitySecondaryText) {
            var segment = AttributedString(text)
            segment.foregroundColor = color
            subtitle += segment
        }
        func appendSeparatorIfNeeded() {
            guard !subtitle.characters.isEmpty else { return }
            append(" · ")
        }

        if let duration = itineraryDurationText {
            append(duration)
        }
        appendSeparatorIfNeeded()
        append(compactItinerarySummaryText)
        if delayMinutes > 0 {
            appendSeparatorIfNeeded()
            append("+\(delayMinutes) min", color: .rightTrainActivityLate)
        }
        return subtitle
    }

    var itineraryIslandSubtitle: String {
        if statusKind == .good {
            return compactItinerarySummaryText
        }
        return statusText
    }

    var windowIslandSubtitle: String? {
        if let platformChange = activePlatformChange {
            return "Platform \(platformChange.currentPlatform) · was \(platformChange.previousPlatform)"
        }
        if statusKind == .good,
           recommendedTrain?.statusKind == .good {
            return nil
        }
        if let value = nonEmpty(nextUpdateText) {
            return value
        }
        if let train = recommendedTrain,
           let value = nonEmpty(train.statusText) {
            return value
        }
        return nonEmpty(statusText)
    }

    var itineraryConnectionFooterText: String {
        // The coordinator now sets a phase-specific otherDeparturesText
        // ("At the station", "Tube journey at <name>", "On the final train"
        // etc.) so we lean on that first.
        if let value = nonEmpty(otherDeparturesText) {
            return value
        }
        if let value = nonEmpty(nextUpdateText) {
            return value
        }
        return compactItinerarySummaryText
    }

    func disruptionSummaryText(for train: RightTrainLiveActivityAttributes.ContentState.Train) -> String? {
        let resolved = ItineraryPhase.from(rawValue: phase)
        if resolved == .atOrigin,
           let value = nonEmpty(nextUpdateText) {
            return value
        }
        if statusKind == .cancelled || train.statusKind == .cancelled {
            return nonEmpty(nextUpdateText) ?? "Service cancelled"
        }
        let delay = max(delayMinutes, train.delayMinutes)
        if delay > 0 {
            let arrival = train.arrivalTime.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? arrivalTime : train.arrivalTime
            let scheduledArrival = train.scheduledArrivalTime.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? arrival
                : train.scheduledArrivalTime
            if arrival != scheduledArrival {
                return "Arr \(arrival) · was \(scheduledArrival)"
            }
            return nil
        }
        if let value = nonEmpty(otherDeparturesText) {
            return value
        }
        return nil
    }

    var compactUpdatedAtText: String {
        if updatedAtText == "Updated now" {
            return "Now"
        }
        if updatedAtText.hasPrefix("Updated ") {
            return String(updatedAtText.dropFirst("Updated ".count))
        }
        return updatedAtText
    }

    var windowSearchRangeText: String {
        guard let range = nonEmpty(windowTimeRangeText) else {
            return "Search window"
        }
        let withoutCount = range.split(separator: "(", maxSplits: 1).first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? range
        guard let separatorIndex = withoutCount.firstIndex(of: "-") else {
            return withoutCount
        }
        let start = String(withoutCount[..<separatorIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        let end = String(withoutCount[withoutCount.index(after: separatorIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !start.isEmpty, !end.isEmpty else {
            return withoutCount
        }
        return "\(start) - \(end)"
    }

    var windowSearchRangeLabelText: String {
        let range = windowSearchRangeText
        guard range.contains("-") else {
            return range
        }
        return "for departures between \(range)"
    }

    var windowHeaderSubtitle: String {
        if let windowTimeRangeText {
            return "Departing between \(windowTimeRangeText)"
        }
        let trainCount = windowTrainCount ?? trains.count
        return "\(trainCount) \(trainCount == 1 ? "train" : "trains")"
    }

    func windowBoardVisibleTrains(maxVisibleTrains: Int) -> [RightTrainLiveActivityAttributes.ContentState.Train] {
        Array(trains.prefix(maxVisibleTrains))
    }

    var recommendedTrain: RightTrainLiveActivityAttributes.ContentState.Train? {
        guard hasAvailableWindowTrain else {
            return nil
        }
        return trains.first { $0.serviceID == recommendationServiceID }
            ?? trains.first(where: \.recommended)
            ?? nextTrain
    }

    var selectedTrain: RightTrainLiveActivityAttributes.ContentState.Train? {
        if let pinnedTrainServiceID,
           let train = trains.first(where: { $0.serviceID == pinnedTrainServiceID }) {
            return train
        }
        return recommendedTrain
    }

    var activePlatformChange: RightTrainLiveActivityAttributes.ContentState.PlatformChange? {
        guard let train = selectedTrain ?? recommendedTrain else {
            return nil
        }
        return platformChange(for: train)
    }

    func platformChange(
        for train: RightTrainLiveActivityAttributes.ContentState.Train
    ) -> RightTrainLiveActivityAttributes.ContentState.PlatformChange? {
        guard let platformChange,
              platformChange.serviceID == train.serviceID,
              !train.departed,
              platformChange.currentPlatform.trimmingCharacters(in: .whitespacesAndNewlines) == train.departurePlatform.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return nil
        }
        return platformChange
    }

    var nextTrain: RightTrainLiveActivityAttributes.ContentState.Train? {
        trains.first { !$0.departed && $0.statusKind != .cancelled && $0.statusKind != .arrived }
    }

    var windowEmptyStateText: String {
        if let emptyStateText = nonEmpty(emptyStateText) {
            return emptyStateText
        }
        let trainCount = windowTrainCount ?? trains.count
        let upcomingCount = upcomingTrainCount ?? trains.filter { !$0.departed && $0.statusKind != .cancelled && $0.statusKind != .arrived }.count
        let departedCount = departedTrainCount ?? trains.filter(\.departed).count
        let cancelledCount = cancelledTrainCount ?? trains.filter { $0.statusKind == .cancelled }.count
        if trainCount > 0, upcomingCount == 0 {
            if departedCount == trainCount {
                return "All trains departed"
            }
            if cancelledCount == trainCount {
                return "All trains cancelled"
            }
        }
        return "No trains available"
    }

    var compactWindowEmptyStateText: String {
        switch windowEmptyStateText {
        case "All trains departed":
            return "Done"
        case "All trains cancelled":
            return "Cncl"
        default:
            return "None"
        }
    }

    private var hasAvailableWindowTrain: Bool {
        if nonEmpty(emptyStateText) != nil {
            return false
        }
        let upcomingCount = upcomingTrainCount ?? trains.filter { !$0.departed && $0.statusKind != .cancelled && $0.statusKind != .arrived }.count
        return upcomingCount > 0
    }

    var watchTrainSummary: String {
        let trainCount = windowTrainCount ?? trains.count
        let departedCount = departedTrainCount ?? trains.filter(\.departed).count
        if departedCount > 0 {
            return "\(trainCount) trains, \(departedCount) departed"
        }
        return "\(trainCount) \(trainCount == 1 ? "train" : "trains")"
    }

    func watchPlatformText(for train: RightTrainLiveActivityAttributes.ContentState.Train) -> String {
        let platform = train.departurePlatform.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !platform.isEmpty else {
            return "Plat TBC"
        }
        return platform.uppercased() == "TBC" ? "Plat TBC" : "Plat \(readablePlatformValue(platform))"
    }

    func watchArrivalPlatformText(for train: RightTrainLiveActivityAttributes.ContentState.Train) -> String {
        let platform = readablePlatformValue(train.arrivalPlatform)
        return platform.uppercased() == "TBC" ? "Arr plat TBC" : "Arr plat \(platform)"
    }

    private var itineraryDurationText: String? {
        guard let departure = departureDate ?? scheduledDepartureDate ?? trains.first?.departureDate ?? trains.first?.scheduledDepartureDate,
              let arrival = arrivalDate ?? scheduledArrivalDate ?? trains.last?.arrivalDate ?? trains.last?.scheduledArrivalDate else {
            return nil
        }
        let minutes = max(0, Int((arrival.timeIntervalSince(departure) / 60).rounded()))
        let hours = minutes / 60
        let remaining = minutes % 60
        if hours > 0 && remaining > 0 {
            return "\(hours)h \(remaining)m"
        }
        if hours > 0 {
            return "\(hours)h"
        }
        return "\(remaining)m"
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

}

private extension RightTrainLiveActivityAttributes.ContentState.Train {
    var isOnboard: Bool {
        departed || journeyProgress != nil
    }

    var operatorNameDisplayText: String? {
        nonEmpty(operatorName)
    }

    var operatorCodeDisplayText: String? {
        nonEmpty(operatorCode)
    }

    var operatorDisplayText: String? {
        if let operatorName = operatorNameDisplayText {
            return operatorName
        }
        return operatorCodeDisplayText
    }

    var watchOperatorText: String? {
        operatorCodeDisplayText ?? operatorNameDisplayText
    }

    var compactDestinationName: String {
        nonEmpty(destinationShortName) ?? destinationName
    }

    var serviceDestinationDisplayName: String {
        nonEmpty(serviceDestinationName) ?? destinationName
    }

    var compactServiceDestinationName: String {
        nonEmpty(serviceDestinationShortName) ?? nonEmpty(serviceDestinationName) ?? compactDestinationName
    }

    var departureLabel: String {
        departed ? "Departed" : "Departs"
    }

    var arrivalLabel: String {
        statusKind == .arrived ? "Arrived" : "Arrives"
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

private extension RightTrainLiveActivityAttributes.StatusKind {
    var isHeroAnomalous: Bool {
        switch self {
        case .good, .departed, .arrived:
            return false
        default:
            return true
        }
    }

    var usesSevereInnerStroke: Bool {
        self == .cancelled || self == .missed
    }

    /// Delayed / at-risk states get a subtle 1pt ring to reinforce the amber surface.
    var usesModerateInnerStroke: Bool {
        self == .delayed || self == .atRisk || self == .unreported || self == .notReported
    }

    /// Opacity of the status tint layer inside the dark activity card.
    /// Higher values = more saturated status colour for more urgent states.
    var activitySurfaceOpacity: Double {
        switch self {
        case .good, .arrived:        return 0.28
        case .delayed, .unreported, .notReported: return 0.34
        case .atRisk:                return 0.40
        case .cancelled, .missed:    return 0.52
        case .departed, .unknown:    return 0.10
        }
    }

    /// Color passed to `.activityBackgroundTint()` for Lock Screen and
    /// watch-family supplemental activities. Matches the card surface so
    /// the system pill echoes the status at first glance.
    var activityBackgroundTintColor: Color {
        switch self {
        case .good, .arrived:        return .rightTrainActivityGood.opacity(0.30)
        case .delayed, .unreported, .notReported: return .rightTrainActivityLate.opacity(0.38)
        case .atRisk:                return .rightTrainActivityLate.opacity(0.44)
        case .cancelled, .missed:    return .rightTrainActivityDanger.opacity(0.56)
        case .departed, .unknown:    return .rightTrainActivityBackground
        }
    }

    var symbolName: String {
        switch self {
        case .good:
            return "checkmark.circle.fill"
        case .arrived:
            return "checkmark.circle.fill"
        case .delayed, .atRisk:
            return "exclamationmark.triangle.fill"
        case .missed:
            return "xmark.octagon.fill"
        case .cancelled:
            return "xmark.octagon.fill"
        case .departed:
            return "checkmark.circle"
        case .unreported, .notReported:
            return "clock.badge.exclamationmark.fill"
        case .unknown:
            return "clock.badge.questionmark.fill"
        }
    }

    var tint: Color {
        tint(delayMinutes: 0)
    }

    func tint(delayMinutes: Int) -> Color {
        switch self {
        case .good:
            return .rightTrainActivityGood
        case .arrived:
            return .rightTrainActivityGood
        case .delayed, .atRisk:
            if delayMinutes >= 25 || self == .atRisk {
                return delayMinutes >= 25 ? .rightTrainActivityDanger : .rightTrainActivityLate
            }
            if delayMinutes > 0 && delayMinutes < 12 {
                return .rightTrainActivityLateSoft
            }
            return .rightTrainActivityLate
        case .missed:
            return .rightTrainActivityDanger
        case .cancelled:
            return .rightTrainActivityDanger
        case .departed:
            return .rightTrainActivityDeparted
        case .unreported, .notReported:
            return .rightTrainActivityLate
        case .unknown:
            return .rightTrainActivityUnknown
        }
    }

    var compactText: String {
        switch self {
        case .good:
            return "OK"
        case .arrived:
            return "Arr"
        case .delayed:
            return "Late"
        case .atRisk:
            return "Risk"
        case .missed:
            return "Miss"
        case .cancelled:
            return "Cncl"
        case .departed:
            return "Dep"
        case .unreported, .notReported:
            return "Rpt"
        case .unknown:
            return "Chk"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .good:
            return "On time"
        case .arrived:
            return "Arrived"
        case .delayed:
            return "Delayed"
        case .atRisk:
            return "Connection at risk"
        case .missed:
            return "Connection missed"
        case .cancelled:
            return "Cancelled"
        case .departed:
            return "Departed"
        case .unreported, .notReported:
            return "Unreported"
        case .unknown:
            return "Checking"
        }
    }
}

#if RIGHTTRAIN_LAYOUT_TESTS
enum LiveActivityLayoutTestSurface: CaseIterable {
    case watchSupplemental
    case dynamicIslandCompact
    case dynamicIslandExpanded
    case lockScreenStandard
    case carPlaySupplemental
}

struct LiveActivityLayoutProbe: View {
    var surface: LiveActivityLayoutTestSurface
    var state: RightTrainLiveActivityAttributes.ContentState
    var activityKind: RightTrainLiveActivityAttributes.ActivityKind

    var body: some View {
        Group {
            switch surface {
            case .watchSupplemental:
                WatchActivityView(state: state, activityKind: activityKind)
            case .dynamicIslandCompact:
                dynamicIslandCompact
            case .dynamicIslandExpanded:
                dynamicIslandExpanded
            case .lockScreenStandard:
                StandardActivityContentView(state: state, activityKind: activityKind)
            case .carPlaySupplemental:
                WatchActivityView(state: state, activityKind: activityKind)
            }
        }
        .environment(\.colorScheme, .dark)
    }

    private var selectedTrain: RightTrainLiveActivityAttributes.ContentState.Train? {
        switch activityKind {
        case .train:
            state.selectedTrain
        case .itinerary, .leg:
            state.activeItineraryTrain
        case .window:
            state.recommendedTrain
        }
    }

    private var statusKind: RightTrainLiveActivityAttributes.StatusKind {
        selectedTrain?.statusKind ?? state.statusKind
    }

    private var delayMinutes: Int {
        selectedTrain?.delayMinutes ?? state.delayMinutes
    }

    private var compactTime: String {
        if activityKind == .train, selectedTrain?.isOnboard == true {
            return selectedTrain?.arrivalTime ?? state.arrivalTime
        }
        if activityKind == .window {
            return selectedTrain?.departureTime ?? state.compactWindowEmptyStateText
        }
        return selectedTrain?.departureTime ?? state.departureTime
    }

    private var platform: String? {
        let value: String
        if activityKind == .train, selectedTrain?.isOnboard == true {
            value = selectedTrain?.arrivalPlatform ?? state.platform
        } else {
            value = selectedTrain?.departurePlatform ?? state.platform
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private var leadingMetricLabel: String {
        if activityKind == .train, selectedTrain?.isOnboard == true {
            return "Arr"
        }
        return activityKind == .window ? "Best" : "Dep"
    }

    private var platformMetricLabel: String {
        if activityKind == .train, selectedTrain?.isOnboard == true {
            return "Arr plat"
        }
        return "Dep plat"
    }

    private var dynamicIslandCompact: some View {
        HStack(spacing: 4) {
            Text(compactTime)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.rightTrainActivityText)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.62)
                .allowsTightening(true)

            Spacer(minLength: 2)

            if let platformChange = state.activePlatformChange {
                CompactPlatformChangeText(change: platformChange)
            } else if activityKind == .train, selectedTrain?.isOnboard == true, let platform {
                CompactPlatformText(platform: platform, fullLabel: "Arr", accessibilityPrefix: "Arrival platform")
            } else if statusKind != .good {
                StatusGlyph(kind: statusKind, delayMinutes: delayMinutes)
            } else if let platform {
                CompactPlatformText(platform: platform)
            } else {
                StatusGlyph(kind: statusKind, delayMinutes: delayMinutes)
            }
        }
        .padding(.horizontal, 4)
    }

    private var dynamicIslandExpanded: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top, spacing: 6) {
                IslandEdgeMetric(label: leadingMetricLabel, value: compactTime)
                    .frame(maxWidth: 84, alignment: .leading)

                IslandTitle(state: state, activityKind: activityKind)
                    .frame(maxWidth: .infinity)

                if let platformChange = state.activePlatformChange {
                    PlatformChangeIslandMetric(change: platformChange, edge: .trailing)
                        .frame(maxWidth: 84, alignment: .trailing)
                } else if let platform {
                    IslandEdgeMetric(label: platformMetricLabel, value: platform, edge: .trailing)
                        .frame(maxWidth: 84, alignment: .trailing)
                } else {
                    StatusGlyph(kind: statusKind, delayMinutes: delayMinutes)
                }
            }

            if activityKind == .itinerary {
                CompactItineraryDetail(state: state)
            } else if let selectedTrain, selectedTrain.isOnboard {
                CompactOnboardTrainDetail(
                    train: selectedTrain,
                    originText: state.originCrs,
                    destinationText: state.destinationCrs
                )
            } else if let selectedTrain {
                CompactTrainDetail(train: selectedTrain, platformChange: state.platformChange(for: selectedTrain))
            } else {
                EmptyWindowText(text: state.windowEmptyStateText, compact: true)
            }
        }
        .padding(8)
    }
}
#endif

#if !RIGHTTRAIN_LAYOUT_TESTS
#Preview("Window On Time", as: .content, using: ActivityPreviewFixtures.windowAttributes) {
    RightTrainLiveActivityWidget()
} contentStates: {
    ActivityPreviewFixtures.windowOnTime
}

#Preview("Window Severe Delay", as: .content, using: ActivityPreviewFixtures.windowAttributes) {
    RightTrainLiveActivityWidget()
} contentStates: {
    ActivityPreviewFixtures.windowSevereDelay
}

#Preview("Itinerary At Risk", as: .content, using: ActivityPreviewFixtures.itineraryAttributes) {
    RightTrainLiveActivityWidget()
} contentStates: {
    ActivityPreviewFixtures.itineraryAtRisk
}

#Preview("Itinerary Pinned First Leg", as: .content, using: ActivityPreviewFixtures.itineraryAttributes) {
    RightTrainLiveActivityWidget()
} contentStates: {
    ActivityPreviewFixtures.itineraryPinnedFirstLeg
}

#Preview("Itinerary Cancelled Leg", as: .content, using: ActivityPreviewFixtures.itineraryAttributes) {
    RightTrainLiveActivityWidget()
} contentStates: {
    ActivityPreviewFixtures.itineraryCancelledLeg
}

#Preview("Train Cancelled", as: .content, using: ActivityPreviewFixtures.trainAttributes) {
    RightTrainLiveActivityWidget()
} contentStates: {
    ActivityPreviewFixtures.trainCancelled
}

#Preview("Train On Board", as: .content, using: ActivityPreviewFixtures.trainAttributes) {
    RightTrainLiveActivityWidget()
} contentStates: {
    ActivityPreviewFixtures.trainOnboard
}

#Preview("Leg Mid Journey", as: .content, using: ActivityPreviewFixtures.legAttributes) {
    RightTrainLiveActivityWidget()
} contentStates: {
    ActivityPreviewFixtures.legOnLegMidJourney
}

#Preview("Leg Approaching Interchange", as: .content, using: ActivityPreviewFixtures.legAttributes) {
    RightTrainLiveActivityWidget()
} contentStates: {
    ActivityPreviewFixtures.legApproachingInterchange
}

#Preview("Leg On Final Train", as: .content, using: ActivityPreviewFixtures.legAttributes) {
    RightTrainLiveActivityWidget()
} contentStates: {
    ActivityPreviewFixtures.legOnFinalLeg
}

#Preview("DI Expanded Approaching", as: .dynamicIsland(.expanded), using: ActivityPreviewFixtures.legAttributes) {
    RightTrainLiveActivityWidget()
} contentStates: {
    ActivityPreviewFixtures.legApproachingInterchange
}

#Preview("DI Compact Approaching", as: .dynamicIsland(.compact), using: ActivityPreviewFixtures.legAttributes) {
    RightTrainLiveActivityWidget()
} contentStates: {
    ActivityPreviewFixtures.legApproachingInterchange
}

#Preview("Dynamic Island Expanded", as: .dynamicIsland(.expanded), using: ActivityPreviewFixtures.itineraryAttributes) {
    RightTrainLiveActivityWidget()
} contentStates: {
    ActivityPreviewFixtures.itineraryAtRisk
}

#Preview("Dynamic Island Compact", as: .dynamicIsland(.compact), using: ActivityPreviewFixtures.windowAttributes) {
    RightTrainLiveActivityWidget()
} contentStates: {
    ActivityPreviewFixtures.windowSevereDelay
}

#Preview("Dynamic Island Minimal", as: .dynamicIsland(.minimal), using: ActivityPreviewFixtures.trainAttributes) {
    RightTrainLiveActivityWidget()
} contentStates: {
    ActivityPreviewFixtures.trainCancelled
}

#Preview("Window Board AX5") {
    WindowBoardActivityView(state: ActivityPreviewFixtures.windowSevereDelay)
        .environment(\.dynamicTypeSize, .accessibility5)
        .padding()
        .background(Color.rightTrainActivityBackground)
}

#Preview("Itinerary Timeline AX5") {
    ItineraryBoardActivityView(state: ActivityPreviewFixtures.itineraryAtRisk)
        .environment(\.dynamicTypeSize, .accessibility5)
        .padding()
        .background(Color.rightTrainActivityBackground)
}

#Preview("Pinned Train AX5") {
    PinnedTrainActivityView(state: ActivityPreviewFixtures.trainCancelled)
        .environment(\.dynamicTypeSize, .accessibility5)
        .padding()
        .background(Color.rightTrainActivityBackground)
}
#endif

private enum ActivityPreviewFixtures {
    static var windowAttributes: RightTrainLiveActivityAttributes {
        RightTrainLiveActivityAttributes(
            windowSubscriptionID: "preview-window",
            itinerarySubscriptionID: nil,
            activityKind: .window,
            pinnedTrainServiceID: nil,
            originCrs: "EUS",
            destinationCrs: "MAN",
            startedAtText: "Preview"
        )
    }

    static var itineraryAttributes: RightTrainLiveActivityAttributes {
        RightTrainLiveActivityAttributes(
            windowSubscriptionID: nil,
            itinerarySubscriptionID: "preview-itinerary",
            activityKind: .itinerary,
            pinnedTrainServiceID: nil,
            originCrs: "EUS",
            destinationCrs: "MAN",
            startedAtText: "Preview"
        )
    }

    static var trainAttributes: RightTrainLiveActivityAttributes {
        RightTrainLiveActivityAttributes(
            windowSubscriptionID: "preview-window",
            itinerarySubscriptionID: nil,
            activityKind: .train,
            pinnedTrainServiceID: 1001,
            originCrs: "EUS",
            destinationCrs: "MAN",
            startedAtText: "Preview"
        )
    }

    static var legAttributes: RightTrainLiveActivityAttributes {
        RightTrainLiveActivityAttributes(
            windowSubscriptionID: nil,
            itinerarySubscriptionID: "preview-itinerary",
            activityKind: .leg,
            pinnedTrainServiceID: nil,
            originCrs: "EUS",
            destinationCrs: "MAN",
            startedAtText: "Preview"
        )
    }

    static var windowOnTime: RightTrainLiveActivityAttributes.ContentState {
        let train = previewTrain(
            serviceID: 1001,
            destinationName: "Manchester Piccadilly",
            departureOffset: 12,
            arrivalOffset: 95,
            platform: "4",
            recommended: true,
            statusText: "On time",
            statusKind: .good
        )
        return state(
            activityKind: .window,
            statusText: "On time",
            statusKind: .good,
            delayMinutes: 0,
            trains: [train],
            recommendationServiceID: train.serviceID,
            windowTrainCount: 1,
            upcomingTrainCount: 1
        )
    }

    static var windowSevereDelay: RightTrainLiveActivityAttributes.ContentState {
        let train = previewTrain(
            serviceID: 1002,
            destinationName: "Manchester Piccadilly",
            departureOffset: 18,
            arrivalOffset: 110,
            platform: "1",
            departureDelay: 18,
            arrivalDelay: 18,
            recommended: true,
            statusText: "+18 Late",
            statusKind: .delayed,
            delayMinutes: 18
        )
        return state(
            activityKind: .window,
            statusText: "+18 Late",
            statusKind: .delayed,
            delayMinutes: 18,
            trains: [train],
            recommendationServiceID: train.serviceID,
            platformConfirmed: false,
            windowTrainCount: 1,
            upcomingTrainCount: 1,
            nextUpdateText: "Delayed 18 min"
        )
    }

    static var itineraryAtRisk: RightTrainLiveActivityAttributes.ContentState {
        let trains = [
            previewTrain(serviceID: 2001, destinationName: "Crewe", departureOffset: 8, arrivalOffset: 44, platform: "4", recommended: true, statusText: "On time", statusKind: .good),
            previewTrain(serviceID: 2002, destinationName: "Wilmslow", departureOffset: 47, arrivalOffset: 70, platform: "6", statusText: "Tight", statusKind: .atRisk, delayMinutes: 3),
            previewTrain(serviceID: 2003, destinationName: "Manchester Piccadilly", departureOffset: 76, arrivalOffset: 95, platform: "2", statusText: "On time", statusKind: .good)
        ]
        return state(
            activityKind: .itinerary,
            statusText: "Connection at risk",
            statusKind: .atRisk,
            delayMinutes: 3,
            trains: trains,
            recommendationServiceID: trains[0].serviceID,
            windowTrainCount: trains.count,
            upcomingTrainCount: trains.count,
            otherDeparturesText: "Change at Crewe - 3 min"
        )
    }

    static var itineraryPinnedFirstLeg: RightTrainLiveActivityAttributes.ContentState {
        var first = previewTrain(serviceID: 3001, destinationName: "Crewe", departureOffset: -15, arrivalOffset: 32, platform: "4", departed: true, recommended: true, statusText: "On board", statusKind: .departed)
        first.journeyProgress = 0.42
        let trains = [
            first,
            previewTrain(serviceID: 3002, destinationName: "Manchester Piccadilly", departureOffset: 42, arrivalOffset: 88, platform: "7", statusText: "On time", statusKind: .good)
        ]
        var content = state(
            activityKind: .itinerary,
            phase: "pinned_first_leg",
            statusText: "On board",
            statusKind: .departed,
            delayMinutes: 0,
            trains: trains,
            recommendationServiceID: first.serviceID,
            windowTrainCount: trains.count,
            upcomingTrainCount: 1,
            otherDeparturesText: "Pinned first train"
        )
        content.pinnedFirstLeg = RightTrainLiveActivityAttributes.ContentState.PinnedFirstLeg(
            serviceID: first.serviceID,
            rid: "preview-\(first.serviceID)",
            ssd: "2030-01-10",
            originName: "London Euston",
            destinationName: "Crewe",
            scheduledDepartureTime: first.scheduledDepartureTime,
            departureTime: first.departureTime,
            scheduledDepartureDate: first.scheduledDepartureDate,
            departureDate: first.departureDate,
            scheduledArrivalTime: first.scheduledArrivalTime,
            arrivalTime: first.arrivalTime,
            scheduledArrivalDate: first.scheduledArrivalDate,
            arrivalDate: first.arrivalDate
        )
        return content
    }

    static var itineraryCancelledLeg: RightTrainLiveActivityAttributes.ContentState {
        let trains = [
            previewTrain(serviceID: 4001, destinationName: "Crewe", departureOffset: 10, arrivalOffset: 42, platform: "4", recommended: true, statusText: "On time", statusKind: .good),
            previewTrain(serviceID: 4002, destinationName: "Manchester Piccadilly", departureOffset: 55, arrivalOffset: 95, platform: "7", statusText: "Cancelled", statusKind: .cancelled)
        ]
        return state(
            activityKind: .itinerary,
            statusText: "Cancelled",
            statusKind: .cancelled,
            delayMinutes: 0,
            trains: trains,
            recommendationServiceID: trains[0].serviceID,
            windowTrainCount: trains.count,
            upcomingTrainCount: 1,
            cancelledTrainCount: 1,
            nextUpdateText: "Middle leg cancelled"
        )
    }

    static var trainCancelled: RightTrainLiveActivityAttributes.ContentState {
        let train = previewTrain(
            serviceID: 5001,
            destinationName: "Manchester Piccadilly",
            departureOffset: 16,
            arrivalOffset: 92,
            platform: "4",
            recommended: true,
            statusText: "Cancelled",
            statusKind: .cancelled
        )
        var content = state(
            activityKind: .train,
            statusText: "Cancelled",
            statusKind: .cancelled,
            delayMinutes: 0,
            trains: [train],
            recommendationServiceID: train.serviceID,
            windowTrainCount: 1,
            upcomingTrainCount: 0,
            cancelledTrainCount: 1,
            nextUpdateText: "Service cancelled"
        )
        content.pinnedTrainServiceID = train.serviceID
        return content
    }

    static var legOnLegMidJourney: RightTrainLiveActivityAttributes.ContentState {
        var current = previewTrain(
            serviceID: 6001,
            destinationName: "Crewe",
            departureOffset: -20,
            arrivalOffset: 25,
            platform: "4",
            departed: true,
            recommended: true,
            statusText: "On board",
            statusKind: .departed
        )
        current.journeyProgress = 0.6
        let onward = previewTrain(
            serviceID: 6002,
            destinationName: "Manchester Piccadilly",
            departureOffset: 38,
            arrivalOffset: 88,
            platform: "7",
            statusText: "On time",
            statusKind: .good
        )
        let interchange = RightTrainLiveActivityAttributes.ContentState.Interchange(
            crs: "CRE",
            name: "Crewe",
            legIndex: 0,
            scheduledArrivalDate: current.scheduledArrivalDate,
            expectedArrivalDate: current.arrivalDate,
            scheduledDepartureDate: onward.scheduledDepartureDate,
            expectedDepartureDate: onward.departureDate,
            requiredTransferMinutes: 5,
            expectedMarginMinutes: 8,
            riskStatus: "ok",
            onwardPlatform: "7",
            onwardPlatformConfirmed: true
        )
        return state(
            activityKind: .leg,
            phase: "on_leg",
            statusText: "On board",
            statusKind: .departed,
            delayMinutes: 0,
            trains: [current, onward],
            recommendationServiceID: current.serviceID,
            windowTrainCount: 2,
            upcomingTrainCount: 1,
            departedTrainCount: 1,
            nextUpdateText: "Change at Crewe",
            otherDeparturesText: "Change at Crewe",
            currentLegIndex: 0,
            onwardLeg: onward,
            interchange: interchange
        )
    }

    static var legApproachingInterchange: RightTrainLiveActivityAttributes.ContentState {
        var current = previewTrain(
            serviceID: 7001,
            destinationName: "Crewe",
            departureOffset: -42,
            arrivalOffset: 3,
            platform: "4",
            departed: true,
            recommended: true,
            statusText: "Arriving",
            statusKind: .departed
        )
        current.journeyProgress = 0.94
        let onward = previewTrain(
            serviceID: 7002,
            destinationName: "Manchester Piccadilly",
            departureOffset: 10,
            arrivalOffset: 60,
            platform: "7",
            statusText: "On time",
            statusKind: .good
        )
        let interchange = RightTrainLiveActivityAttributes.ContentState.Interchange(
            crs: "CRE",
            name: "Crewe",
            legIndex: 0,
            scheduledArrivalDate: current.scheduledArrivalDate,
            expectedArrivalDate: current.arrivalDate,
            scheduledDepartureDate: onward.scheduledDepartureDate,
            expectedDepartureDate: onward.departureDate,
            requiredTransferMinutes: 5,
            expectedMarginMinutes: 2,
            riskStatus: "at_risk",
            onwardPlatform: "7",
            onwardPlatformConfirmed: true
        )
        return state(
            activityKind: .leg,
            phase: "approaching_interchange",
            statusText: "Change at Crewe",
            statusKind: .atRisk,
            delayMinutes: 0,
            trains: [current, onward],
            recommendationServiceID: current.serviceID,
            windowTrainCount: 2,
            upcomingTrainCount: 1,
            departedTrainCount: 1,
            nextUpdateText: "Get off at next stop",
            otherDeparturesText: "Get off at Crewe",
            currentLegIndex: 0,
            onwardLeg: onward,
            interchange: interchange
        )
    }

    static var legOnFinalLeg: RightTrainLiveActivityAttributes.ContentState {
        var first = previewTrain(
            serviceID: 8001,
            destinationName: "Crewe",
            departureOffset: -70,
            arrivalOffset: -25,
            platform: "4",
            departed: true,
            statusText: "Arrived",
            statusKind: .arrived
        )
        first.journeyProgress = 1
        var current = previewTrain(
            serviceID: 8002,
            destinationName: "Manchester Piccadilly",
            departureOffset: -15,
            arrivalOffset: 38,
            platform: "7",
            departed: true,
            recommended: true,
            statusText: "On board",
            statusKind: .departed
        )
        current.journeyProgress = 0.4
        return state(
            activityKind: .leg,
            phase: "on_final_leg",
            statusText: "On board",
            statusKind: .departed,
            delayMinutes: 0,
            trains: [first, current],
            recommendationServiceID: current.serviceID,
            windowTrainCount: 2,
            upcomingTrainCount: 0,
            departedTrainCount: 2,
            nextUpdateText: "On the final train",
            otherDeparturesText: "On the final train",
            currentLegIndex: 1
        )
    }

    static var trainOnboard: RightTrainLiveActivityAttributes.ContentState {
        var train = previewTrain(
            serviceID: 5002,
            destinationName: "Moorgate",
            departureOffset: -22,
            arrivalOffset: 18,
            platform: "1",
            departed: true,
            recommended: true,
            statusText: "On board",
            statusKind: .departed
        )
        train.journeyProgress = 0.76
        var content = state(
            activityKind: .train,
            statusText: "On board",
            statusKind: .departed,
            delayMinutes: 0,
            trains: [train],
            recommendationServiceID: train.serviceID,
            windowTrainCount: 1,
            upcomingTrainCount: 0,
            departedTrainCount: 1,
            nextUpdateText: "On board"
        )
        content.pinnedTrainServiceID = train.serviceID
        return content
    }

    private static func state(
        activityKind: RightTrainLiveActivityAttributes.ActivityKind,
        phase: String? = nil,
        statusText: String,
        statusKind: RightTrainLiveActivityAttributes.StatusKind,
        delayMinutes: Int,
        trains: [RightTrainLiveActivityAttributes.ContentState.Train],
        recommendationServiceID: Int,
        platformConfirmed: Bool = true,
        windowTrainCount: Int? = nil,
        upcomingTrainCount: Int? = nil,
        departedTrainCount: Int? = 0,
        cancelledTrainCount: Int? = 0,
        nextUpdateText: String = "Updated now",
        otherDeparturesText: String? = nil,
        currentLegIndex: Int? = nil,
        onwardLeg: RightTrainLiveActivityAttributes.ContentState.Train? = nil,
        interchange: RightTrainLiveActivityAttributes.ContentState.Interchange? = nil
    ) -> RightTrainLiveActivityAttributes.ContentState {
        let first = trains.first
        let last = trains.last ?? first
        let focused: RightTrainLiveActivityAttributes.ContentState.Train? = {
            if let index = currentLegIndex, index >= 0, index < trains.count {
                return trains[index]
            }
            return first
        }()
        let focusedLast = onwardLeg ?? focused ?? last
        return RightTrainLiveActivityAttributes.ContentState(
            windowSubscriptionID: activityKind == .itinerary || activityKind == .leg ? nil : "preview-window",
            itinerarySubscriptionID: activityKind == .itinerary || activityKind == .leg ? "preview-itinerary" : nil,
            phase: phase,
            recommendationServiceID: recommendationServiceID,
            routeTitle: "Euston to Manchester",
            originName: "London Euston",
            destinationName: "Manchester Piccadilly",
            originCrs: "EUS",
            destinationCrs: "MAN",
            departureTime: focused?.departureTime ?? "--:--",
            scheduledDepartureDate: focused?.scheduledDepartureDate,
            departureDate: focused?.departureDate,
            arrivalTime: focused?.arrivalTime ?? last?.arrivalTime ?? "--:--",
            scheduledArrivalDate: focused?.scheduledArrivalDate ?? focusedLast?.scheduledArrivalDate,
            arrivalDate: focused?.arrivalDate ?? focusedLast?.arrivalDate,
            platform: focused?.departurePlatform ?? first?.departurePlatform ?? "TBC",
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
            pinnedTrainServiceID: activityKind == .train ? recommendationServiceID : nil,
            pinnedFirstLeg: nil,
            itineraryOptions: nil,
            currentLegIndex: currentLegIndex,
            onwardLeg: onwardLeg,
            interchange: interchange
        )
    }

    private static func previewTrain(
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
        delayMinutes: Int = 0
    ) -> RightTrainLiveActivityAttributes.ContentState.Train {
        let scheduledDeparture = Date().addingTimeInterval(TimeInterval(departureOffset) * 60)
        let scheduledArrival = Date().addingTimeInterval(TimeInterval(arrivalOffset) * 60)
        let departure = scheduledDeparture.addingTimeInterval(TimeInterval(departureDelay) * 60)
        let arrival = scheduledArrival.addingTimeInterval(TimeInterval(arrivalDelay) * 60)
        return RightTrainLiveActivityAttributes.ContentState.Train(
            serviceID: serviceID,
            operatorName: "Avanti West Coast",
            operatorCode: "VT",
            destinationName: destinationName,
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

    private static func clockText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "Europe/London")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

private extension Color {
    static let rightTrainActivityBackground = Color("RightTrainActivityBackground")
    static let rightTrainActivityAccent = Color("RightTrainActivityAccent")
    static let rightTrainActivityGood = Color("RightTrainActivityGood")
    static let rightTrainActivityDeparted = Color("RightTrainActivityDeparted")
    static let rightTrainActivityUnknown = Color("RightTrainActivityUnknown")
    static let rightTrainActivityText = Color("RightTrainActivityText")
    static let rightTrainActivitySecondaryText = Color("RightTrainActivitySecondaryText")
    static let rightTrainActivityLate = Color("RightTrainActivityLate")
    static let rightTrainActivityLateSoft = Color("RightTrainActivityLateSoft")
    static let rightTrainActivityDanger = Color("RightTrainActivityDanger")
    static let rightTrainActivityDivider = Color("RightTrainActivityDivider")
}
