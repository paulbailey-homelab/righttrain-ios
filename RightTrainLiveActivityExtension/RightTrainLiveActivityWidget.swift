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
                    Group {
                        if let platformChange = context.state.activePlatformChange {
                            PlatformChangeIslandMetric(change: platformChange, edge: .trailing)
                        } else if let platform = islandPlatform(for: context) {
                            IslandPlatformMetric(
                                platform: PlatformValue(platform.value, confirmed: platform.confirmed),
                                role: platform.role,
                                edge: .trailing
                            )
                        } else {
                            IslandEdgeMetric(label: "Status", value: context.state.selectedTrain?.statusText ?? context.state.statusText, edge: .trailing)
                        }
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
                DynamicIslandWidthReader { isLimitedInWidth in
                    let statusKind = context.state.selectedTrain?.statusKind ?? context.state.statusKind
                    if let platformChange = context.state.activePlatformChange {
                        CompactPlatformChangeText(change: platformChange, showsIcon: !isLimitedInWidth)
                    } else if let platform = compactPlatform(for: context) {
                        CompactPlatformText(
                            platform: platform.value,
                            confirmed: platform.confirmed,
                            accessibilityPrefix: platform.accessibilityPrefix
                        )
                    } else if statusKind != .good {
                        // Already falls back to its bare symbol via
                        // ViewThatFits, keeping "+18" whenever it fits.
                        StatusGlyph(kind: statusKind, delayMinutes: context.state.selectedTrain?.delayMinutes ?? context.state.delayMinutes)
                    } else if let platform = departurePlatform(for: context) {
                        CompactPlatformText(platform: platform, confirmed: context.state.platformConfirmed)
                    } else {
                        StatusGlyph(kind: statusKind, delayMinutes: context.state.selectedTrain?.delayMinutes ?? context.state.delayMinutes)
                    }
                }
            } minimal: {
                let statusKind = context.state.selectedTrain?.statusKind ?? context.state.statusKind
                if statusKind.isHeroAnomalous || islandPlatform(for: context) == nil {
                    StatusGlyph(
                        kind: statusKind,
                        delayMinutes: context.state.selectedTrain?.delayMinutes ?? context.state.delayMinutes,
                        showsText: false
                    )
                } else if let platform = islandPlatform(for: context) {
                    // An on-time tick says nothing; the platform is the
                    // one thing worth a glance when the island is shared.
                    PlatformTile.activity(
                        PlatformValue(platform.value, confirmed: platform.confirmed),
                        role: platform.role
                    )
                }
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

    private func islandPlatform(for context: ActivityViewContext<RightTrainLiveActivityAttributes>) -> (role: String, value: String, confirmed: Bool)? {
        if context.attributes.activityKind == .train,
           let train = context.state.selectedTrain,
           train.isOnboard {
            return displayPlatform(train.arrivalPlatform).map { (role: "Arrival platform", value: $0, confirmed: true) }
        }
        // On approaching_interchange, the user cares most about the
        // ONWARD platform at the interchange. Surface it in the island.
        if context.attributes.activityKind == .leg,
           ItineraryPhase.from(rawValue: context.state.phase) == .approachingInterchange,
           let platform = displayPlatform(context.state.interchange?.onwardPlatform) {
            return (role: "Next platform", value: platform, confirmed: context.state.interchange?.onwardPlatformConfirmed == true)
        }
        // On any boarded leg, current arrival platform is the next signal.
        if context.attributes.activityKind == .leg,
           let train = context.state.activeItineraryTrain,
           let platform = displayPlatform(train.arrivalPlatform) {
            return (role: "Arrival platform", value: platform, confirmed: true)
        }
        return departurePlatform(for: context).map { (role: "Platform", value: $0, confirmed: context.state.platformConfirmed) }
    }

    private func compactPlatform(for context: ActivityViewContext<RightTrainLiveActivityAttributes>) -> (value: String, accessibilityPrefix: String, confirmed: Bool)? {
        if context.attributes.activityKind == .train,
           let train = context.state.selectedTrain,
           train.isOnboard,
           let platform = displayPlatform(train.arrivalPlatform) {
            return (value: platform, accessibilityPrefix: "Arrival platform", confirmed: true)
        }
        // At an interchange the onward platform is the one to walk to.
        if context.attributes.activityKind == .leg,
           ItineraryPhase.from(rawValue: context.state.phase) == .approachingInterchange,
           let platform = displayPlatform(context.state.interchange?.onwardPlatform) {
            return (value: platform, accessibilityPrefix: "Next platform", confirmed: context.state.interchange?.onwardPlatformConfirmed == true)
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
        return .rightTrainGood
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
        // The clock time is what departure boards show and never goes
        // stale; the live countdown sits in the bottom region.
        IslandEdgeMetric(label: label, value: fallbackTime, tint: tint)
    }

    private var tint: Color {
        let delayed = showsArrival ? train?.arrivalDelayed : train?.departureDelayed
        return delayed == true ? .rightTrainLate : .rightTrainActivityText
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
        showsArrival ? "Arrives" : "Departs"
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
            .font(.caption.weight(.semibold))
            .foregroundStyle(isDelayed ? Color.rightTrainLate : Color.rightTrainActivityText)
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

    private var isDelayed: Bool {
        let delayed = isOnboardTrainActivity || isOnboardLegActivity ? train?.arrivalDelayed : train?.departureDelayed
        return delayed == true
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
            IslandTrainSummary(train: train, mode: train.isOnboard ? .arrival : .departure)
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
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            IslandStatusText(kind: train.statusKind, delayMinutes: train.delayMinutes)
            if train.statusKind != .cancelled {
                IslandCountdownText(date: targetDate, prefix: mode == .arrival ? "· arrives in " : "· in ")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var targetDate: Date? {
        switch mode {
        case .departure:
            return train.departed ? nil : train.departureDate ?? train.scheduledDepartureDate
        case .arrival:
            return train.statusKind == .arrived ? nil : train.arrivalDate ?? train.scheduledArrivalDate
        }
    }
}

private struct IslandItinerarySummary: View {
    var state: RightTrainLiveActivityAttributes.ContentState

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            IslandStatusText(kind: state.statusKind, delayMinutes: state.delayMinutes)
            if let train = state.activeItineraryTrain {
                IslandCountdownText(
                    date: state.resolvedPhase.isOnboard
                        ? train.arrivalDate ?? train.scheduledArrivalDate
                        : train.departureDate ?? train.scheduledDepartureDate,
                    prefix: state.resolvedPhase.isOnboard ? "· arrives in " : "· in "
                )
            } else {
                IslandSummaryText(text: state.compactItinerarySummaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Live countdown for the expanded island's bottom row. Renders nothing
/// once the moment has passed so a stale "in 0 minutes" never lingers.
private struct IslandCountdownText: View {
    var date: Date?
    var prefix: String

    var body: some View {
        if let date, date > Date() {
            MinuteRelativeText(date: date, prefix: prefix)
                .font(.subheadline)
                .foregroundStyle(Color.rightTrainActivitySecondaryText)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.74)
        }
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
                .imageScale(.small)
            Text(text)
                .lineLimit(1)
                .minimumScaleFactor(0.74)
                .allowsTightening(true)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(tint)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var text: String {
        if kind == .delayed, let delayMinutes, delayMinutes > 0 {
            return "\(delayMinutes) min late"
        }
        return kind.compactText
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

private struct CompactPlatformText: View {
    var platform: String
    var confirmed: Bool
    var accessibilityPrefix: String = "Platform"

    var body: some View {
        PlatformTile.activity(PlatformValue(platform, confirmed: confirmed), role: accessibilityPrefix)
    }
}

/// Hands compact Dynamic Island content whether the island is width-limited.
/// From iOS 27 compact and minimal presentations also show in landscape,
/// where they can't grow, so they drop to their narrowest form. Earlier
/// systems only show them in portrait, which is never limited.
///
/// This always reports "not limited" for now. The value comes from SwiftUI's
/// `isDynamicIslandLimitedInWidth` environment key, shown in the WWDC26
/// sessions but not yet declared in any shipped iPhoneOS SDK, so reading it
/// fails to compile rather than falling back at runtime — an availability
/// check doesn't help, because the symbol has to exist to build at all. That
/// left the widget extension unbuildable by every released Xcode. Restoring
/// the real value is a change to this one type once an SDK declares the key.
///
/// Reporting "not limited" is what every device running this app gets today:
/// the landscape presentation it feeds only exists on iOS 27.
private struct DynamicIslandWidthReader<Content: View>: View {
    @ViewBuilder var content: (_ isLimitedInWidth: Bool) -> Content

    var body: some View {
        content(false)
    }
}

private struct CompactPlatformChangeText: View {
    var change: RightTrainLiveActivityAttributes.ContentState.PlatformChange
    /// The swap arrows give the change a cue beyond colour; they're dropped
    /// when the island is width-limited, where the amber tile and the
    /// accessibility label still carry it.
    var showsIcon = true

    var body: some View {
        HStack(spacing: 3) {
            if showsIcon {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.rightTrainLate)
                    .accessibilityHidden(true)
            }
            PlatformTile.activity(
                PlatformValue(change.currentPlatform, confirmed: true, previous: change.previousPlatform)
            )
        }
    }
}

private extension PlatformTile {
    /// A tile in the Live Activity's own palette, which follows the Lock
    /// Screen and Dynamic Island appearance rather than the app's.
    static func activity(_ platform: PlatformValue, size: Size = .small, role: String = "Platform") -> PlatformTile {
        PlatformTile(
            platform: platform,
            size: size,
            role: role,
            ink: .rightTrainActivityText,
            onInk: .rightTrainActivityBackground,
            changeTint: .rightTrainLate,
            onChangeTint: .rightTrainActivityBackground
        )
    }
}

private struct ActivityCaptionedPlatformTile: View {
    var platform: PlatformValue
    var size: PlatformTile.Size = .medium
    var role = "Platform"
    var alignment: HorizontalAlignment = .trailing
    var captionFont: Font = .caption.weight(.medium)
    var highlighted = false

    var body: some View {
        CaptionedPlatformTile(
            platform: platform,
            size: size,
            role: role,
            alignment: alignment,
            captionFont: captionFont,
            captionColor: highlighted ? .rightTrainLate : .rightTrainActivitySecondaryText,
            ink: .rightTrainActivityText,
            onInk: .rightTrainActivityBackground,
            changeTint: .rightTrainLate,
            onChangeTint: .rightTrainActivityBackground
        )
    }
}

private struct IslandPlatformMetric: View {
    var platform: PlatformValue
    var role = "Platform"
    var edge: IslandExpandedEdge = .trailing

    var body: some View {
        ActivityCaptionedPlatformTile(
            platform: platform,
            size: .medium,
            role: role,
            alignment: edge.horizontalAlignment,
            captionFont: .caption2.weight(.medium)
        )
        .frame(maxWidth: .infinity, alignment: edge.alignment)
        // Keep clear of the island's rounded shoulders.
        .padding(edge.paddingEdges, 6)
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

private struct ActivityCardChrome: ViewModifier {
    var statusKind: RightTrainLiveActivityAttributes.StatusKind

    func body(content: Content) -> some View {
        // The system draws the Lock Screen container and adapts it to the
        // wallpaper and appearance. Status is carried by tinted text and
        // symbols, not by repainting the whole surface.
        content
            .activityBackgroundTint(nil)
            .activitySystemActionForegroundColor(.rightTrainActivityText)
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
        .activityBackgroundTint(nil)
        .activitySystemActionForegroundColor(.rightTrainGood)
        .accessibilityElement(children: .combine)
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
                    platform: PlatformValue(train.departurePlatform, confirmed: state.platformConfirmed),
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
                    platform: PlatformValue(train.departurePlatform, confirmed: state.platformConfirmed),
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

            PlatformBadge(platform: PlatformValue(train.arrivalPlatform, confirmed: true), role: "Arrival platform")

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
                    platform: PlatformValue(train.departurePlatform, confirmed: state.platformConfirmed),
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
    var platform: PlatformValue
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
            PlatformBadge(platform: platform)
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
                HStack(alignment: .center, spacing: 10) {
                    // The operator adds a row without changing what the
                    // traveller does, so the route stands alone.
                    Text(state.routeTitle)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(Color.rightTrainActivityText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.58)
                        .allowsTightening(true)
                        .truncationMode(.middle)
                        .layoutPriority(2)

                    Spacer(minLength: 6)

                    // The hero already says "Cancelled", and a platform
                    // change is spelled out beside the platform.
                    if train.statusKind.isHeroAnomalous, train.statusKind != .cancelled,
                       state.platformChange(for: train) == nil {
                        StatusBadge(text: train.statusText, kind: train.statusKind, delayMinutes: train.delayMinutes)
                            .layoutPriority(0)
                    }
                }

                HStack(alignment: .lastTextBaseline, spacing: 10) {
                    JourneyHeroBlock(train: train)
                        .layoutPriority(1)

                    Spacer(minLength: 6)

                    if train.statusKind != .cancelled {
                        InlinePlatformLabel(
                            platform: train.departurePlatform,
                            confirmed: state.platformConfirmed,
                            platformChange: state.platformChange(for: train)
                        )
                    }
                }

                if let summary = state.disruptionSummaryText(for: train) {
                    DisruptionSummaryLine(text: summary, kind: train.statusKind)
                } else {
                    OtherDeparturesFooter(text: state.otherDeparturesText)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
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
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
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
                HStack(alignment: .center, spacing: 10) {
                    // The change count, duration and operator used to fill a
                    // second caption row; the rows below already show the
                    // change and any delay.
                    Text(state.routeTitle)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(Color.rightTrainActivityText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.58)
                        .allowsTightening(true)
                        .truncationMode(.middle)
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
                        JourneyHeroBlock(train: train, mode: state.resolvedPhase.isOnboard ? .arrival : .departure)
                            .layoutPriority(1)

                        Spacer(minLength: 6)

                        InlinePlatformLabel(
                            platform: state.resolvedPhase.isOnboard ? train.arrivalPlatform : train.departurePlatform,
                            confirmed: state.platformConfirmed,
                            accessibilityPrefix: state.resolvedPhase.isOnboard ? "Arrival platform" : "Departure platform"
                        )
                    }
                }

                // Once aboard, the leg list is history; show only what the
                // traveller acts on next so the card stays within the
                // Lock Screen's height budget.
                switch state.resolvedPhase {
                case .approachingInterchange, .onFinalLeg:
                    JourneyProgressFooter(
                        train: train,
                        originText: train.departureTime,
                        destinationText: train.arrivalTime
                    )
                case .onLeg:
                    if let interchange = state.interchange {
                        InterchangeBanner(interchange: interchange, approaching: false)
                    } else {
                        JourneyProgressFooter(
                            train: train,
                            originText: train.departureTime,
                            destinationText: train.arrivalTime
                        )
                    }
                case .planning, .atOrigin:
                    // One line only: a full leg list cannot fit the Lock
                    // Screen's 160pt budget and would get scaled down.
                    if let summary = state.disruptionSummaryText(for: train),
                       summary != state.otherDeparturesText?.trimmingCharacters(in: .whitespacesAndNewlines) {
                        DisruptionSummaryLine(text: summary, kind: state.statusKind)
                    } else if let connection = state.nextConnection(after: train) {
                        ConnectionTimelineRow(
                            current: connection.current,
                            next: connection.next,
                            emphasized: state.statusKind == .atRisk || state.statusKind == .missed
                        )
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
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
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .activityCardChrome(statusKind: state.statusKind)
            .accessibilityElement(children: .combine)
        }
    }
}

private struct ConnectionTimelineRow: View {

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
        return "platform \(arrivalPlatform) to \(departurePlatform)"
    }

    private var symbolName: String {
        emphasized ? "figure.walk.motion" : "arrow.triangle.2.circlepath"
    }

    private var tint: Color {
        emphasized ? .rightTrainLate : .rightTrainActivitySecondaryText
    }

    // Platforms at the change wait for the "Get off" state, where the
    // onward platform gets the large slot.
    private var text: String {
        var value = "Change at \(current.compactDestinationName)"
        if let minutes {
            value += " · \(minutes) min"
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
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(tint)
            }
            .frame(width: 18, height: 22)

            Text(text)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.58)
                .allowsTightening(true)
                .contentTransition(.numericText())

            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, emphasized ? 8 : 0)
        .background(emphasized ? Color.rightTrainLate.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: RTRadius.chip))
        .overlay {
            if emphasized {
                RoundedRectangle(cornerRadius: RTRadius.chip)
                    .stroke(Color.rightTrainLate.opacity(0.42), lineWidth: 1)
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
                    .fill(Color.rightTrainGood)
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
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .activityCardChrome(statusKind: train.statusKind)
        .accessibilityElement(children: .combine)
    }

    private var compactLayout: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 10) {
                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Color.rightTrainActivityText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.58)
                    .allowsTightening(true)
                    .truncationMode(.middle)
                    .layoutPriority(2)

                if showsStatusGlyph {
                    Spacer(minLength: 6)

                    StatusGlyph(kind: train.statusKind, delayMinutes: train.delayMinutes)
                }
            }

            HStack(alignment: .lastTextBaseline, spacing: 10) {
                JourneyHeroBlock(train: train, mode: .arrival)
                    .layoutPriority(1)

                Spacer(minLength: 6)

                InlinePlatformLabel(
                    platform: train.arrivalPlatform,
                    confirmed: true,
                    accessibilityPrefix: "Arrival platform"
                )
            }

            JourneyProgressFooter(
                train: train,
                originText: train.departureTime,
                destinationText: train.arrivalTime
            )
        }
    }

    private var title: String {
        "\(train.statusKind == .arrived ? "At" : "To") \(train.destinationName)"
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
                    platform: train.arrivalPlatform,
                    confirmed: true,
                    accessibilityPrefix: "Arrival platform"
                )
            }

            JourneyProgressFooter(
                train: train,
                originText: train.departureTime,
                destinationText: train.arrivalTime
            )
        }
    }

    private var headerBlock: some View {
        Text(title)
            .font(.headline.weight(.semibold))
            .foregroundStyle(Color.rightTrainActivityText)
            .lineLimit(2)
            .minimumScaleFactor(0.58)
            .allowsTightening(true)
    }
}

private struct PinnedTrainPreDepartureContent: View {
    var state: RightTrainLiveActivityAttributes.ContentState
    var train: RightTrainLiveActivityAttributes.ContentState.Train

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .center, spacing: 10) {
                Text("To \(train.serviceDestinationDisplayName)")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Color.rightTrainActivityText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.58)
                    .allowsTightening(true)
                    .truncationMode(.middle)
                    .layoutPriority(2)

                if train.statusKind.isHeroAnomalous, train.statusKind != .cancelled,
                   state.platformChange(for: train) == nil {
                    Spacer(minLength: 6)

                    StatusBadge(text: train.statusText, kind: train.statusKind, delayMinutes: train.delayMinutes)
                        .layoutPriority(0)
                }
            }

            HStack(alignment: .lastTextBaseline, spacing: 10) {
                JourneyHeroBlock(train: train)
                    .layoutPriority(1)

                Spacer(minLength: 6)

                if train.statusKind != .cancelled {
                    InlinePlatformLabel(
                        platform: train.departurePlatform,
                        confirmed: state.platformConfirmed,
                        platformChange: state.platformChange(for: train)
                    )
                }
            }

            // A progress bar at 0% says nothing before departure.
            if let summary = state.disruptionSummaryText(for: train) {
                DisruptionSummaryLine(text: summary, kind: train.statusKind)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
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
        default:
            return "\(max(interchange.expectedMarginMinutes, 0)) min to change"
        }
    }

    private var marginTint: Color {
        switch interchange.riskStatus {
        case "missed":
            return .rightTrainCancelled
        case "tight", "at_risk":
            return .rightTrainLate
        default:
            return .rightTrainActivitySecondaryText
        }
    }

    var body: some View {
        // The onward platform is the one thing to act on, so it gets the
        // same large right-hand slot as the departure platform elsewhere.
        HStack(alignment: .lastTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Get off at \(interchange.name)")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Color.rightTrainActivityText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.54)
                    .allowsTightening(true)
                    .truncationMode(.middle)

                Text("Next \(onwardDeparture) · \(marginText)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(marginTint)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .allowsTightening(true)
            }
            .layoutPriority(1)

            Spacer(minLength: 6)

            InlinePlatformLabel(
                platform: onwardPlatform,
                confirmed: interchange.onwardPlatformConfirmed,
                accessibilityPrefix: "Next platform",
                title: "Next platform",
                highlighted: true
            )
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
        // A platform change is captioned on the platform tile beside the
        // title, so it isn't repeated here.
        return nil
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
            return "\(interchange.expectedMarginMinutes) min, tight"
        case "at_risk":
            return "\(max(interchange.expectedMarginMinutes, 0)) min spare"
        default:
            return "\(interchange.expectedMarginMinutes) min spare"
        }
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

    private var tint: Color {
        switch train.statusKind {
        case .cancelled, .missed:
            return .rightTrainCancelled
        case .delayed, .atRisk, .unreported, .notReported:
            return .rightTrainLate
        case .unknown:
            return .rightTrainActivitySecondaryText
        default:
            return .rightTrainGood
        }
    }

    /// While the train is moving, let the system advance the bar between
    /// pushes. Outside that window fall back to the last reported value.
    private var liveInterval: ClosedRange<Date>? {
        guard train.statusKind != .arrived,
              train.statusKind != .cancelled,
              let departure = train.departureDate ?? train.scheduledDepartureDate,
              let arrival = train.arrivalDate ?? train.scheduledArrivalDate,
              departure < arrival,
              departure <= Date(),
              arrival > Date() else {
            return nil
        }
        return departure...arrival
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            endpointText(originText)

            Group {
                if let liveInterval {
                    ProgressView(timerInterval: liveInterval, countsDown: false) {
                        EmptyView()
                    } currentValueLabel: {
                        EmptyView()
                    }
                } else {
                    ProgressView(value: progress)
                }
            }
            .progressViewStyle(.linear)
            .labelsHidden()
            .tint(tint)

            endpointText(destinationText)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Journey progress \(Int((progress * 100).rounded())) percent")
    }

    private func endpointText(_ value: String) -> some View {
        Text(value)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.rightTrainActivitySecondaryText)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .fixedSize(horizontal: true, vertical: false)
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
            return .rightTrainCancelled
        default:
            return .rightTrainGood
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
            let platformText = PlatformValue.bare(platform).map { "platform \($0)" } ?? "platform TBC"
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

/// Lock Screen hero: a live countdown as the headline and the board time
/// (with the scheduled time when it has moved) underneath.
private struct JourneyHeroBlock: View {
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

    private var scheduledTime: String {
        mode == .arrival ? train.scheduledArrivalTime : train.scheduledDepartureTime
    }

    private var currentTime: String {
        mode == .arrival ? train.arrivalTime : train.departureTime
    }

    private var isDelayed: Bool {
        mode == .arrival ? train.arrivalDelayed : train.departureDelayed
    }

    private var isCancelled: Bool {
        train.statusKind == .cancelled
    }

    private var hasHappened: Bool {
        switch mode {
        case .departure:
            return train.departed
        case .arrival:
            return train.statusKind == .arrived
        }
    }

    private var isImminent: Bool {
        guard let targetDate, !hasHappened else { return false }
        let interval = targetDate.timeIntervalSinceNow
        return interval <= 60 && interval >= -60
    }

    /// A countdown reads faster than a clock time, and the Lock Screen
    /// already shows the clock. Beyond an hour the board time is clearer.
    private var countdownDate: Date? {
        guard let targetDate, !hasHappened, !isImminent else { return nil }
        let interval = targetDate.timeIntervalSinceNow
        return interval > 0 && interval < 60 * 60 ? targetDate : nil
    }

    private var hasOverride: Bool {
        currentTime.trimmingCharacters(in: .whitespacesAndNewlines) != scheduledTime.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headline
                .font(.title.weight(.semibold))
                .fontDesign(.rounded)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .allowsTightening(true)

            detail
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.rightTrainActivitySecondaryText)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .allowsTightening(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var verb: String {
        mode == .arrival ? "Arrives" : "Departs"
    }

    private var pastVerb: String {
        mode == .arrival ? "Arrived" : "Departed"
    }

    @ViewBuilder private var headline: some View {
        if isCancelled {
            Text("Cancelled")
                .foregroundStyle(Color.rightTrainCancelled)
        } else if hasHappened {
            Text(pastVerb)
                .foregroundStyle(Color.rightTrainActivityText)
        } else if isImminent {
            Text(mode == .arrival ? "Arriving now" : "Departing now")
                .foregroundStyle(Color.rightTrainActivityText)
        } else if let countdownDate {
            MinuteRelativeText(date: countdownDate)
                .foregroundStyle(Color.rightTrainActivityText)
        } else {
            Text(currentTime)
                .foregroundStyle(isDelayed ? Color.rightTrainLate : Color.rightTrainActivityText)
        }
    }

    /// One line under the headline: the board time, then what it was.
    @ViewBuilder private var detail: some View {
        if isCancelled {
            Text("Was due \(scheduledTime)")
        } else if hasHappened {
            Text("At \(currentTimeText)\(wasText)")
        } else if countdownDate != nil || isImminent {
            Text("\(verb) \(currentTimeText)\(wasText)")
        } else {
            Text("\(targetDate == nil ? verb : "Expected")\(wasText)")
        }
    }

    private var currentTimeText: Text {
        Text(currentTime)
            .foregroundStyle(isDelayed ? Color.rightTrainLate : Color.rightTrainActivityText)
    }

    private var wasText: String {
        hasOverride ? " · was \(scheduledTime)" : ""
    }

    private var accessibilityLabel: String {
        if isCancelled {
            return "Service cancelled, was due \(scheduledTime)"
        }
        var parts: [String] = []
        if let targetDate {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            let relative = formatter.localizedString(for: targetDate, relativeTo: Date())
            parts.append(hasHappened ? "\(pastVerb) \(relative)" : "\(verb) \(relative)")
        } else {
            parts.append("\(verb) \(currentTime)")
        }
        parts.append("scheduled \(scheduledTime)")
        if isDelayed, scheduledTime != currentTime {
            parts.append("now \(currentTime)")
        }
        return parts.joined(separator: ", ")
    }
}

private struct InlinePlatformLabel: View {
    var platform: String
    var confirmed: Bool
    var accessibilityPrefix: String = "Platform"
    var platformChange: RightTrainLiveActivityAttributes.ContentState.PlatformChange? = nil
    /// Replaces "Platform", e.g. "Next platform" at an interchange.
    var title = "Platform"
    /// Amber caption: this is the platform to walk to now.
    var highlighted = false

    var body: some View {
        ActivityCaptionedPlatformTile(
            platform: PlatformValue(platform, confirmed: confirmed, previous: platformChange?.previousPlatform),
            role: title,
            highlighted: highlighted
        )
        .layoutPriority(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            PlatformValue(platform, confirmed: confirmed, previous: platformChange?.previousPlatform)
                .accessibilityLabel(role: title == "Platform" ? accessibilityPrefix : title)
        )
    }
}

private struct DisruptionSummaryLine: View {
    var text: String
    var kind: RightTrainLiveActivityAttributes.StatusKind

    var body: some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
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
                PlatformTile.activity(
                    PlatformValue(platform, confirmed: interchange.onwardPlatformConfirmed),
                    role: "Next platform"
                )
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: RTRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: RTRadius.card, style: .continuous)
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
                ? "At risk · \(interchange.expectedMarginMinutes) min spare"
                : "At risk"
        case "tight":
            return "Tight · \(max(interchange.expectedMarginMinutes, 0)) min spare"
        default:
            return interchange.expectedMarginMinutes > 0 ? "\(interchange.expectedMarginMinutes) min spare" : nil
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
                : .rightTrainGood
        }
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
                            .foregroundStyle(delayed ? Color.rightTrainLate : Color.rightTrainActivityText)
                    }

                    HStack(spacing: 2) {
                        Image(systemName: "clock")
                            .imageScale(.small)
                            .foregroundStyle(delayed ? Color.rightTrainLate : Color.rightTrainActivitySecondaryText)
                        Text(current)
                            .foregroundStyle(delayed ? Color.rightTrainLate : Color.rightTrainActivityText)
                    }

                    Text(current)
                        .foregroundStyle(delayed ? Color.rightTrainLate : Color.rightTrainActivityText)
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

private struct IslandEdgeMetric: View {
    var label: String
    var value: String
    var tint: Color = .rightTrainActivityText
    var edge: IslandExpandedEdge = .leading

    var body: some View {
        VStack(alignment: edge.horizontalAlignment, spacing: 0) {
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(Color.rightTrainActivitySecondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value)
                .font(.title3.weight(.semibold))
                .fontDesign(.rounded)
                .foregroundStyle(tint)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .allowsTightening(true)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: edge.alignment)
        // Keep clear of the island's rounded shoulders.
        .padding(edge.paddingEdges, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }
}

private struct PlatformChangeIslandMetric: View {
    var change: RightTrainLiveActivityAttributes.ContentState.PlatformChange
    var edge: IslandExpandedEdge = .leading

    var body: some View {
        IslandPlatformMetric(
            platform: PlatformValue(change.currentPlatform, confirmed: true, previous: change.previousPlatform),
            edge: edge
        )
    }
}

private enum IslandExpandedEdge {
    case leading
    case trailing

    var alignment: Alignment {
        self == .leading ? .leading : .trailing
    }

    var horizontalAlignment: HorizontalAlignment {
        self == .leading ? .leading : .trailing
    }

    var paddingEdges: Edge.Set {
        self == .leading ? .leading : .trailing
    }
}

struct MinuteRelativeText: View {
    var date: Date
    var prefix: String = ""
    var suffix: String = ""

    var body: some View {
        // Live Activities are archived snapshots, so TimelineView never
        // re-renders between pushes. The system date format keeps ticking.
        Text("\(prefix)\(Text(.currentDate, format: .offset(to: date, allowedFields: [.hour, .minute], sign: .never)))\(suffix)")
    }
}

private struct StatusBadge: View {

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
    var platform: PlatformValue
    var role = "Platform"

    var body: some View {
        PlatformTile.activity(platform, role: role)
    }
}

private struct StatusGlyph: View {
    var kind: RightTrainLiveActivityAttributes.StatusKind
    var delayMinutes: Int? = nil
    var showsText = true

    private var tint: Color {
        kind.tint(delayMinutes: delayMinutes ?? 0)
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            if showsText {
                HStack(spacing: 3) {
                    Image(systemName: kind.symbolName)
                        .imageScale(.medium)
                    Text(glyphText)
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.58)
                        .allowsTightening(true)
                }
            }

            Image(systemName: kind.symbolName)
                .imageScale(.medium)
        }
        .foregroundStyle(tint)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    /// "+18" says more than "Late" in the same width.
    private var glyphText: String {
        if kind == .delayed, let delayMinutes, delayMinutes > 0 {
            return "+\(delayMinutes)"
        }
        return kind.compactText
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

    func nextConnection(
        after train: RightTrainLiveActivityAttributes.ContentState.Train
    ) -> (current: RightTrainLiveActivityAttributes.ContentState.Train, next: RightTrainLiveActivityAttributes.ContentState.Train)? {
        guard let index = trains.firstIndex(where: { $0.serviceID == train.serviceID }),
              index + 1 < trains.count else {
            return nil
        }
        return (trains[index], trains[index + 1])
    }

    var changeCountText: String {
        let changes = max((windowTrainCount ?? trains.count) - 1, 0)
        switch changes {
        case 0:
            return "Direct"
        case 1:
            return "1 change"
        default:
            return "\(changes) changes"
        }
    }

    var itineraryIslandSubtitle: String {
        changeCountText
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
            // The hero already reads "Cancelled"; only add a line that
            // tells the traveller something new, such as the next option.
            guard let value = nonEmpty(nextUpdateText) else {
                return nil
            }
            if train.statusKind == .cancelled, value.localizedCaseInsensitiveContains("cancel") {
                return nil
            }
            return value
        }
        let delay = max(delayMinutes, train.delayMinutes)
        if delay > 0 {
            let arrival = train.arrivalTime.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? arrivalTime : train.arrivalTime
            let scheduledArrival = train.scheduledArrivalTime.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? arrival
                : train.scheduledArrivalTime
            if arrival != scheduledArrival {
                return "Arrives \(arrival)"
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
            return "Cancelled"
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
            return .rightTrainGood
        case .arrived:
            return .rightTrainGood
        case .delayed, .atRisk:
            if delayMinutes >= 25 || self == .atRisk {
                return delayMinutes >= 25 ? .rightTrainCancelled : .rightTrainLate
            }
            if delayMinutes > 0 && delayMinutes < 12 {
                return .rightTrainLate
            }
            return .rightTrainLate
        case .missed:
            return .rightTrainCancelled
        case .cancelled:
            return .rightTrainCancelled
        case .departed:
            return .rightTrainActivityDeparted
        case .unreported, .notReported:
            return .rightTrainLate
        case .unknown:
            return .rightTrainActivityUnknown
        }
    }

    var compactText: String {
        switch self {
        case .good:
            return "On time"
        case .arrived:
            return "Arrived"
        case .delayed:
            return "Late"
        case .atRisk:
            return "At risk"
        case .missed:
            return "Missed"
        case .cancelled:
            return "Cancelled"
        case .departed:
            return "Departed"
        case .unreported, .notReported:
            return "No report"
        case .unknown:
            return "Checking"
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
                // The Dynamic Island is always dark; other surfaces follow
                // the environment so light layouts can be exercised.
                dynamicIslandCompact
                    .environment(\.colorScheme, .dark)
            case .dynamicIslandExpanded:
                dynamicIslandExpanded
                    .environment(\.colorScheme, .dark)
            case .lockScreenStandard:
                StandardActivityContentView(state: state, activityKind: activityKind)
            case .carPlaySupplemental:
                WatchActivityView(state: state, activityKind: activityKind)
            }
        }
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
        activityKind == .train && selectedTrain?.isOnboard == true ? "Arrives" : "Departs"
    }

    private var platformMetricLabel: String {
        "Platform"
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
                CompactPlatformText(platform: platform, confirmed: true, accessibilityPrefix: "Arrival platform")
            } else if statusKind != .good {
                StatusGlyph(kind: statusKind, delayMinutes: delayMinutes)
            } else if let platform {
                CompactPlatformText(platform: platform, confirmed: state.platformConfirmed)
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
                    IslandPlatformMetric(
                        platform: PlatformValue(platform, confirmed: selectedTrain?.isOnboard == true || state.platformConfirmed),
                        role: platformMetricLabel,
                        edge: .trailing
                    )
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
    static let rightTrainActivityDeparted = Color("RightTrainActivityDeparted")
    static let rightTrainActivityUnknown = Color("RightTrainActivityUnknown")
    static let rightTrainActivityText = Color("RightTrainActivityText")
    static let rightTrainActivitySecondaryText = Color("RightTrainActivitySecondaryText")
    static let rightTrainActivityDivider = Color("RightTrainActivityDivider")
}
