import SwiftUI

// MARK: - Design token colours (Status-First Glance system)

// Redesign contract: live journey surfaces must prioritize status, route, next
// action, timing/platform, and freshness. These tokens provide shared emphasis
// without making colour the only status signal.
//
// Appearance stance: the app follows the system appearance and uses iOS
// semantic colours (grouped backgrounds, label, separator) so it reads as a
// native app in light and dark mode. Brand identity comes from the green
// accent only. The historical token names below (cream, paper, ink) are kept
// so call sites compile, but they now resolve to system colours — don't
// reintroduce fixed cream surfaces or light-only overrides. Green, amber and
// red come from RightTrainPalette.swift, which the Live Activity shares; the
// widget keeps only its own neutral text and surface colours.

extension Color {
    // Status and brand colours come from the shared palette in
    // RightTrainPalette.swift; these names are the app's roles for them.
    /// Buttons, links, selected controls and the brand mark.
    static let rightTrainActionInk = Color.rightTrainGood
    /// On-time status.
    static let rightTrainSuccess = Color.rightTrainGood
    /// Delayed status, changed platforms, patchy or offline connection.
    static let rightTrainAmber = Color.rightTrainLate
    /// Cancelled status and failed changes.
    static let rightTrainDanger = Color.rightTrainCancelled

    // Neutral surfaces — system semantic colours.
    /// Page background (grouped).
    static let rightTrainSurfaceCream = Color(uiColor: .systemGroupedBackground)
    /// Content on top of the page background (grouped rows and cards).
    static let rightTrainPaperCream   = Color(uiColor: .secondarySystemGroupedBackground)
    /// Fill nested inside a card (a time strip inside a grouped block).
    static let rightTrainInsetFill    = Color(uiColor: .tertiarySystemFill)
    static let rightTrainInk          = Color(uiColor: .label)
    static let rightTrainInkFaint     = Color(uiColor: .separator)
    /// Text/icons on a filled accent background: white on the dark light-mode
    /// green, near-black on the brighter dark-mode green.
    static let rightTrainOnAccent     = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(white: 0.04, alpha: 1) : .white
    })

    // Legacy aliases — kept so existing call sites compile unchanged.
    static let rightTrainBackground = Color(uiColor: .systemGroupedBackground)
    static let rightTrainSurface    = Color(uiColor: .secondarySystemGroupedBackground)
    static let rightTrainBorder     = Color(uiColor: .separator)
}

// MARK: - RTSurface

/// Status context for live journey UI. The page shell stays neutral; status
/// colour is applied as accents, borders, and soft callouts. Text and
/// accessibility labels remain the source of truth for action-needed states.
enum RTSurface: Equatable {
    case good    // emerald  — on time / pre-departure default
    case warn    // amber    — delayed
    case bad     // deep red — cancelled
    case neutral // system   — no live state / planning / settings

    var isStatus: Bool { self != .neutral }

    /// The status pill tone for text on this surface.
    var pillTone: StatusPill.Tone {
        switch self {
        case .good: .green
        case .warn: .amber
        case .bad: .red
        case .neutral: .accent
        }
    }

    var bg: Color {
        .rightTrainSurfaceCream
    }

    var ink: Color {
        .rightTrainInk
    }

    var dim: Color {
        .rightTrainInk.opacity(RTOpacity.dim)
    }

    var faint: Color {
        .rightTrainInk.opacity(RTOpacity.faint)
    }

    var accent: Color {
        switch self {
        case .good:    return .rightTrainSuccess
        case .warn:    return .rightTrainAmber
        case .bad:     return .rightTrainDanger
        case .neutral: return .rightTrainActionInk
        }
    }

    /// Inner-surface tint for secondary containers.
    var softFill: Color {
        accent.opacity(self == .neutral ? 0.07 : 0.10)
    }

    var softBorder: Color {
        accent.opacity(self == .neutral ? 0.14 : 0.24)
    }
}

// MARK: - StatusSurface view modifier

extension View {
    /// Wraps a view in the full-bleed status surface colour with animated transitions.
    func statusSurface(_ surface: RTSurface) -> some View {
        self
            .background(surface.bg.ignoresSafeArea())
            .animation(.easeInOut(duration: 0.4), value: surface)
    }

    /// Applies the standard primary/secondary/tertiary label hierarchy.
    /// (Historically pinned ink colours on light-only cream cards; now adaptive.)
    func lightSurfaceForeground() -> some View {
        self.foregroundStyle(.primary, .secondary, .tertiary)
    }
}

// MARK: - Opacity tokens

/// The only ink-opacity steps the app uses. Pick the nearest step instead of
/// inventing a new literal — 36 distinct alphas crept in before these existed.
enum RTOpacity {
    /// Emphasised secondary content (eyebrow headers over status colour).
    static let emphasized: Double = 0.72
    /// Standard secondary text on page and card surfaces.
    static let dim: Double = 0.62
    /// Supporting text a step quieter than dim (metric labels, captions).
    static let secondary: Double = 0.55
    /// Tertiary hints and de-emphasised glyphs.
    static let tertiary: Double = 0.44
    /// Hairlines, borders, disabled states.
    static let faint: Double = 0.22
}

// MARK: - Spacing tokens

enum RTSpacing {
    /// Keep active guidance compact enough for the first screenful contract.
    static let xs: CGFloat              = 4
    static let small: CGFloat           = 8
    static let compact: CGFloat         = 12
    static let listItem: CGFloat        = 10
    static let cardPadding: CGFloat     = 16
    /// Same leading margin as inset-grouped lists, so custom pages and
    /// native lists line up.
    static let pageHorizontal: CGFloat  = 16
    static let pageVertical: CGFloat    = 12
    static let sectionGap: CGFloat      = 20
    /// Extra bottom padding for scroll views. The tab bar already insets
    /// content, so this only needs a small breathing gap.
    static let bottomSafeArea: CGFloat  = 16
    static let statusBarSafeArea: CGFloat = 50
}

// MARK: - Layout tokens

enum RTLayout {
    /// Widest a column of guidance or rows grows before it centres — UIKit's
    /// readable content width at the default text size. Phones never reach
    /// it; iPhone Duo's inner display in landscape and wide split widths do,
    /// and without it countdown and platform drift to opposite edges.
    static let readableWidth: CGFloat = 672
    /// Container width at which Pinned switches to the board layout. iPhone
    /// Duo's inner display in landscape (951pt) qualifies; in portrait
    /// (669pt) two columns would each be too narrow for a train row.
    static let boardMinimumWidth: CGFloat = 820
    /// The board's fixed hero column: wide enough for the countdown and
    /// platform side by side.
    static let boardLeadingWidth: CGFloat = 400
}

private struct ReadableContentMargins: ViewModifier {
    @ScaledMetric(relativeTo: .body) private var readableWidth = RTLayout.readableWidth
    @State private var containerWidth: CGFloat = 0

    func body(content: Content) -> some View {
        content
            // Safe-area padding rather than `contentMargins`: contentMargins
            // replaces a List's native row inset (rows went edge to edge on
            // phones), whereas padding adds to it and is a no-op at zero.
            .safeAreaPadding(.horizontal, max(0, (containerWidth - readableWidth) / 2))
            // Measured outside the padding so the inset can't feed back
            // into the width it's computed from.
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { width in
                containerWidth = width
            }
    }
}

private struct ReadableWidthFrame: ViewModifier {
    @ScaledMetric(relativeTo: .body) private var readableWidth = RTLayout.readableWidth

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: readableWidth)
            .frame(maxWidth: .infinity)
    }
}

extension View {
    /// Centres a ScrollView, List or Form's content in a readable column once
    /// the container is wider than `RTLayout.readableWidth`. Apply it to the
    /// scroll container itself so each screen measures its own width (sheets
    /// and split columns are narrower than the window).
    func readableContentMargins() -> some View {
        modifier(ReadableContentMargins())
    }

    /// Caps floating, non-scrolling chrome (bars, banners) to the same
    /// readable column as `readableContentMargins()`.
    func readableWidthFrame() -> some View {
        modifier(ReadableWidthFrame())
    }
}

// MARK: - Size tokens

enum RTSize {
    static let profileIcon: CGFloat = 40
    static let iconButton: CGFloat  = 34
    /// Minimum comfortable hit area per HIG.
    static let tapTarget: CGFloat = 44
    /// Compact square action button (e.g. pin toggle).
    static let buttonCompact: CGFloat = 52
    /// Full-width primary button height.
    static let buttonHeight: CGFloat = 50
    /// Minimum height for dense list rows.
    static let rowMinHeight: CGFloat = 42
    static let iconSmall: CGFloat = 22
    static let iconMedium: CGFloat = 24
    static let glyphColumn: CGFloat = 13
    static let avatarSmall: CGFloat = 32
}

// MARK: - Font tokens

enum RTFont {
    static let statusLabel: Font  = .caption.weight(.semibold)
    static let metricValue: Font  = .subheadline.weight(.semibold)
    static let metricLabel: Font  = .caption
    /// Eyebrow / label style: small caps, tracked, bold
    static let eyebrow: Font      = .system(size: 11, weight: .bold)
}

private struct HeroNumberFont: ViewModifier {
    @ScaledMetric private var size: CGFloat

    init(size: CGFloat) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: .largeTitle)
    }

    func body(content: Content) -> some View {
        content
            .font(BoardFont.font(fixedSize: size))
    }
}

extension View {
    /// Display-size departure-board numerals for the countdown and platform heroes.
    /// Scales with Dynamic Type relative to Large Title, unlike a fixed
    /// `.system(size:)`.
    func heroNumberFont(size: CGFloat) -> some View {
        modifier(HeroNumberFont(size: size))
            // Applied outside the modifier so its @ScaledMetric reads the
            // capped size: past AX1 a platform can't sit beside the
            // countdown, and callers' minimum scale factors take over.
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }
}

// MARK: - Dynamic type helpers

extension DynamicTypeSize {
    /// True when text is large enough that fixed-width columnar layouts begin to
    /// cramp or truncate. Use this to switch dense grids to a stacked layout.
    var prefersExpandedLayout: Bool {
        self >= .xxLarge
    }
}
