import SwiftUI

// MARK: - Card container

/// The standard card wrapper: a grouped-content background with the same
/// continuous corner radius as inset-grouped list sections, and no border —
/// the background contrast does the separation, as in native iOS lists.
/// A status surface adds a soft tinted outline so live state stays visible.
struct RTCardModifier: ViewModifier {
    var surface: RTSurface = .neutral
    var padding: CGFloat = RTSpacing.cardPadding
    var radius: CGFloat = RTRadius.card

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Color.rightTrainPaperCream, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                if surface != .neutral {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(surface.softBorder, lineWidth: 1)
                }
            }
    }
}

extension View {
    func rtCard(
        _ surface: RTSurface = .neutral,
        padding: CGFloat = RTSpacing.cardPadding,
        radius: CGFloat = RTRadius.card
    ) -> some View {
        modifier(RTCardModifier(surface: surface, padding: padding, radius: radius))
    }
}

// MARK: - Button hierarchy

// The app's button levels. Primary is the single most important action on a
// screen; secondary sits beside or under it; anything quieter uses a plain
// tinted text button. Don't hand-roll filled pills.
//
// Liquid Glass split: these two styles are for buttons that live IN content
// (inside cards and lists) — solid capsule fills, matching the system capsule
// shape language. Controls that float ABOVE content (bottom action bars,
// overlays) use `FloatingPrimaryAction` / `.glassProminent` instead. Never put
// glass inside content or glass on glass.

/// Primary in-content action: filled accent capsule, full width.
struct RTPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity)
            .frame(minHeight: RTSize.buttonHeight)
            .foregroundStyle(Color.rightTrainOnAccent)
            .background(Color.rightTrainSuccess, in: Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
    }
}

/// Secondary in-content action: tinted capsule fill, full width.
struct RTSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity)
            .frame(minHeight: RTSize.buttonHeight)
            .foregroundStyle(Color.rightTrainActionInk)
            .background(Color.rightTrainActionInk.opacity(0.14), in: Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

extension ButtonStyle where Self == RTPrimaryButtonStyle {
    static var rtPrimary: RTPrimaryButtonStyle { RTPrimaryButtonStyle() }
}

extension ButtonStyle where Self == RTSecondaryButtonStyle {
    static var rtSecondary: RTSecondaryButtonStyle { RTSecondaryButtonStyle() }
}

/// The screen's primary action floating above scrolling content on tinted
/// Liquid Glass. Place it in `.safeAreaBar(edge: .bottom)` so content scrolls
/// beneath it with the system scroll-edge effect.
struct FloatingPrimaryAction<Label: View>: View {
    var action: () -> Void
    @ViewBuilder var label: () -> Label

    var body: some View {
        Button(action: action) {
            label()
                .font(.body.weight(.semibold))
                // White on the bright dark-mode green is too low-contrast;
                // match the in-content primary button's on-accent colour.
                .foregroundStyle(Color.rightTrainOnAccent)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.extraLarge)
        .padding(.horizontal, RTSpacing.pageHorizontal + 4)
        .readableWidthFrame()
        .padding(.bottom, RTSpacing.small)
    }
}

// MARK: - Adaptive operator name

/// Renders an operator name with graceful fallback: full name → 16-char short
/// name → TOC code. Uses `ViewThatFits` so the longest variant that fits the
/// available horizontal space is chosen without truncation or font scaling.
///
/// Pass the raw field values; nil tiers are skipped automatically.
struct AdaptiveOperatorText: View {
    /// Full operator name, e.g. "Avanti West Coast"
    var full: String?
    /// Up-to-16-character abbreviated name, e.g. "Avanti West Coas" (populated
    /// once the API sends `operatorShortName`; nil until then).
    var short: String?
    /// 2-character TOC code, e.g. "VT"
    var code: String?
    var font: Font = .caption.weight(.medium)

    var body: some View {
        if let full, let short, let code {
            ViewThatFits(in: .horizontal) {
                label(full); label(short); label(code)
            }
        } else if let full, let short {
            ViewThatFits(in: .horizontal) {
                label(full); label(short)
            }
        } else if let full, let code {
            ViewThatFits(in: .horizontal) {
                label(full); label(code)
            }
        } else if let value = full ?? short ?? code {
            label(value).minimumScaleFactor(0.78)
        }
        // all nil → renders nothing (equivalent to EmptyView)
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(font)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}

struct SectionHeader: View {
    var title: String
    var subtitle: String
    var tone: StatusPill.Tone? = nil

    var body: some View {
        HStack(alignment: .top, spacing: tone == nil ? 0 : 10) {
            if let tone {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(tone.color)
                    .frame(width: 3)
                    .padding(.vertical, 2)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(tone?.color ?? .primary)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, tone == nil ? 0 : 2)
    }
}

struct MetricView: View {
    var label: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }
}

/// A MetricView-shaped cell whose value is a platform tile.
struct PlatformMetricView: View {
    var platform: PlatformValue

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(platform.caption())
                .font(.caption.weight(.semibold))
                .foregroundStyle(platform.isChanged ? Color.rightTrainAmber : .secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            PlatformTile(platform: platform)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(platform.accessibilityLabel())
    }
}

struct LiveGlancePanel: View {
    var content: ActiveWindowPresentation.LiveGlanceContent

    var body: some View {
        VStack(alignment: .leading, spacing: RTSpacing.compact) {
            HStack(alignment: .firstTextBaseline, spacing: RTSpacing.small) {
                StatusPill(text: content.statusText, tone: content.statusTone)
                Spacer(minLength: RTSpacing.small)
                LiveFreshnessText(text: content.freshnessText)
            }

            Text(content.routeTitle)
                .font(.title3.weight(.bold))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if let routeContextText = content.routeContextText {
                Text(routeContextText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.rightTrainInk.opacity(RTOpacity.dim))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }

            HStack(alignment: .top, spacing: RTSpacing.compact) {
                MetricView(label: "Timing", value: content.timingText)
                PlatformMetricView(platform: content.platform)
            }

            NextActionCallout(text: content.nextActionText, tone: content.statusTone)
        }
        .padding(RTSpacing.cardPadding)
        .background(Color.rightTrainPaperCream, in: RoundedRectangle(cornerRadius: RTRadius.card, style: .continuous))
        .lightSurfaceForeground()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(content.nextActionText)
    }

    private var accessibilityLabel: String {
        [
            content.statusText,
            content.routeTitle,
            content.routeContextText,
            content.platformText,
            content.freshnessText
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }
}

struct LiveFreshnessText: View {
    var text: String

    var body: some View {
        Label(text, systemImage: "dot.radiowaves.left.and.right")
            .font(.caption.weight(.medium))
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .foregroundStyle(Color.rightTrainInk.opacity(RTOpacity.dim))
            .accessibilityLabel(text)
    }
}

struct NextActionCallout: View {
    var text: String
    var tone: StatusPill.Tone = .accent

    var body: some View {
        Label(text, systemImage: "arrow.right.circle.fill")
            .font(.subheadline.weight(.semibold))
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(tone.color)
            .padding(.horizontal, RTSpacing.compact)
            .padding(.vertical, RTSpacing.small)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tone.color.opacity(0.10), in: RoundedRectangle(cornerRadius: RTRadius.chip))
            .accessibilityLabel("Next action: \(text)")
    }
}

/// Tone-based status chip for NEUTRAL (cream/paper) contexts: cards, lists,
/// and headers. For content sitting on a coloured status surface
/// (good/warn/bad backgrounds) use `RTStatusPill`, which derives its colours
/// from the surface. These are the only two status pill styles.
struct StatusPill: View {
    enum Tone: Equatable {
        case accent
        case amber
        case green
        case red
        case neutral

        var color: Color {
            switch self {
            case .accent:
                return .rightTrainActionInk
            case .amber:
                return .rightTrainAmber
            case .green:
                return .rightTrainSuccess
            case .red:
                return .rightTrainDanger
            case .neutral:
                return .rightTrainInk.opacity(RTOpacity.dim)
            }
        }
    }

    var text: String
    var tone: Tone

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .foregroundStyle(tone.color)
            .background(tone.color.opacity(0.12), in: Capsule())
            .contentTransition(.numericText())
            .accessibilityLabel(text)
    }
}

/// Surface-aware live status pill — used ONLY on coloured status backgrounds
/// (good/warn/bad surfaces, e.g. the hero block). Shows a filled accent dot +
/// uppercase eyebrow text on a soft-fill capsule. For neutral cream/paper
/// contexts use `StatusPill` instead.
struct RTStatusPill: View {
    var statusText: String
    var surface: RTSurface

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(surface.accent)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)

            Text(statusText)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(surface.accent)
                .lineLimit(1)
        }
        .contentTransition(.numericText())
        .accessibilityLabel(statusText)
    }
}

enum PinKind {
    case window
    case journey

    var label: String {
        switch self {
        case .window:
            return "Search Pin"
        case .journey:
            return "Journey Pin"
        }
    }

    var systemImage: String {
        switch self {
        case .window:
            return "magnifyingglass"
        case .journey:
            return "pin"
        }
    }

    var tone: StatusPill.Tone {
        switch self {
        case .window:
            return .accent
        case .journey:
            return .green
        }
    }
}

struct PinBadge: View {
    var kind: PinKind

    var body: some View {
        Label(kind.label, systemImage: kind.systemImage)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.84)
            .foregroundStyle(kind.tone.color)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(kind.tone.color.opacity(0.12), in: Capsule())
            .accessibilityLabel(kind.label)
    }
}

struct PinnedHeaderPrimaryAction {
    var title: String
    var systemImage: String
    var role: ButtonRole? = nil
    var accessibilityHint: String? = nil
    var isDisabled = false
    var action: () -> Void
}

struct PinnedObjectHeader<ActionContent: View>: View {
    var kind: PinKind
    var showsKindBadge: Bool
    var showsActionMenu: Bool
    var title: String
    var summary: String
    var statusText: String?
    var statusTone: StatusPill.Tone
    var updatedAt: Date?
    var now: Date
    var primaryAction: PinnedHeaderPrimaryAction?
    private let actionContent: () -> ActionContent

    init(
        kind: PinKind,
        showsKindBadge: Bool = true,
        showsActionMenu: Bool = true,
        title: String,
        summary: String,
        statusText: String? = nil,
        statusTone: StatusPill.Tone = .accent,
        updatedAt: Date? = nil,
        now: Date = Date(),
        primaryAction: PinnedHeaderPrimaryAction? = nil,
        @ViewBuilder actions: @escaping () -> ActionContent
    ) {
        self.kind = kind
        self.showsKindBadge = showsKindBadge
        self.showsActionMenu = showsActionMenu
        self.title = title
        self.summary = summary
        self.statusText = statusText
        self.statusTone = statusTone
        self.updatedAt = updatedAt
        self.now = now
        self.primaryAction = primaryAction
        self.actionContent = actions
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: RTSpacing.small) {
                if showsKindBadge {
                    PinBadge(kind: kind)
                        .fixedSize(horizontal: true, vertical: false)
                }

                if let statusText,
                   !statusText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    StatusPill(text: statusText, tone: statusTone)
                }

                Spacer(minLength: 0)

                if let updatedAt {
                    Text("Updated \(MinuteRelative.text(for: updatedAt, now: now)) ago")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .accessibilityLabel("Updated")
                        .accessibilityValue(relativeAccessibilityText(for: updatedAt))
                }
            }

            Text(title)
                .font(.title3.weight(.bold))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
        .pinnedActionsToolbar(primaryAction: primaryAction, showsMenu: showsActionMenu, menuContent: actionContent)
    }

    private func relativeAccessibilityText(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }
}

/// Puts a Pin's actions in the navigation bar as a single "More" menu, the
/// way native apps expose per-screen actions, instead of floating capsules in
/// the content. The primary action (usually a destructive Unpin) comes last.
struct PinnedActionsToolbar<MenuContent: View>: ViewModifier {
    var primaryAction: PinnedHeaderPrimaryAction?
    var showsMenu: Bool
    var menuContent: () -> MenuContent

    func body(content: Content) -> some View {
        content.toolbar {
            if primaryAction != nil || showsMenu {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if showsMenu {
                            menuContent()
                        }
                        if let primaryAction {
                            Button(role: primaryAction.role) {
                                primaryAction.action()
                            } label: {
                                Label(primaryAction.title, systemImage: primaryAction.systemImage)
                            }
                            .disabled(primaryAction.isDisabled)
                            .accessibilityHint(primaryAction.accessibilityHint ?? "")
                        }
                    } label: {
                        Label("Pin actions", systemImage: "ellipsis.circle")
                    }
                    .accessibilityLabel("More Pin actions")
                }
            }
        }
    }
}

extension View {
    func pinnedActionsToolbar<MenuContent: View>(
        primaryAction: PinnedHeaderPrimaryAction?,
        showsMenu: Bool,
        @ViewBuilder menuContent: @escaping () -> MenuContent
    ) -> some View {
        modifier(PinnedActionsToolbar(primaryAction: primaryAction, showsMenu: showsMenu, menuContent: menuContent))
    }
}

struct DisruptionLine: View {
    var journey: JourneyResult
    var score: DirectWindowRecommendationScore

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(tone.color)
            Text(message)
                .font(.footnote.weight(.medium))
                .foregroundStyle(Color.rightTrainInk.opacity(RTOpacity.emphasized))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var icon: String {
        switch JourneyFormatting.displayStatus(journey) {
        case "arrived":
            return "checkmark.circle.fill"
        case "cancelled":
            return "xmark.octagon.fill"
        case "delayed":
            return "exclamationmark.triangle.fill"
        case "unreported":
            return "clock.badge.exclamationmark.fill"
        default:
            return "checkmark.circle.fill"
        }
    }

    private var tone: StatusPill.Tone {
        switch JourneyFormatting.displayStatus(journey) {
        case "arrived":
            return .green
        case "cancelled":
            return .red
        case "delayed", "unreported":
            return .amber
        default:
            return .green
        }
    }

    private var message: String {
        switch JourneyFormatting.displayStatus(journey) {
        case "arrived":
            return "Arrived at your destination."
        case "cancelled":
            return journey.cancellationReasonText ?? "This service is cancelled."
        case "unreported":
            return "Arrival status not available yet."
        case "delayed":
            if let reason = journey.lateReasonText, !reason.isEmpty {
                return reason
            }
            let delayMinutes = JourneyFormatting.statusDelayMinutes(journey: journey, score: score)
            if delayMinutes > 0 {
                return "Expected delay: \(delayMinutes) minutes."
            }
            return "Delay reported for this service."
        default:
            break
        }
        if let reason = journey.lateReasonText, !reason.isEmpty {
            return reason
        }
        let delayMinutes = JourneyFormatting.statusDelayMinutes(journey: journey, score: score)
        if delayMinutes > 0 {
            return "Expected delay: \(delayMinutes) minutes."
        }
        return "No disruption reported."
    }
}

struct EmptyStateView: View {
    struct PrimaryAction {
        var label: String
        var systemImage: String?
        var perform: () -> Void

        init(label: String, systemImage: String? = nil, perform: @escaping () -> Void) {
            self.label = label
            self.systemImage = systemImage
            self.perform = perform
        }
    }

    var title: String
    var message: String
    var symbolName: String?
    var tint: Color
    var primaryAction: PrimaryAction?

    init(
        title: String,
        message: String,
        symbolName: String? = nil,
        tint: Color = .rightTrainActionInk,
        primaryAction: PrimaryAction? = nil
    ) {
        self.title = title
        self.message = message
        self.symbolName = symbolName
        self.tint = tint
        self.primaryAction = primaryAction
    }

    var body: some View {
        VStack(spacing: 8) {
            if let symbolName {
                Image(systemName: symbolName)
                    .font(.largeTitle)
                    .imageScale(.large)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(tint)
                    .padding(.bottom, 4)
                    .accessibilityHidden(true)
            }

            Text(title)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let primaryAction {
                Button(action: primaryAction.perform) {
                    if let systemImage = primaryAction.systemImage {
                        Label(primaryAction.label, systemImage: systemImage)
                            .frame(maxWidth: .infinity)
                    } else {
                        Text(primaryAction.label)
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.rtPrimary)
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, RTSpacing.cardPadding)
        .padding(.vertical, 28)
        .background(Color.rightTrainPaperCream, in: RoundedRectangle(cornerRadius: RTRadius.card, style: .continuous))
        .lightSurfaceForeground()
        .accessibilityElement(children: .combine)
    }
}

// RightTrainBrand is defined in HeaderView.swift
