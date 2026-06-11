import SwiftUI

// MARK: - Design token colours (Status-First Glance system)

// Redesign contract: live journey surfaces must prioritize status, route, next
// action, timing/platform, and freshness. These tokens provide shared emphasis
// without making colour the only status signal.

extension Color {
    // On-time surface
    static let rightTrainGoodBg     = Color("RightTrainGoodBg")
    static let rightTrainGoodInk    = Color("RightTrainGoodInk")
    static let rightTrainGoodAccent = Color("RightTrainGoodAccent")

    // Delayed surface
    static let rightTrainWarnBg     = Color("RightTrainWarnBg")
    static let rightTrainWarnInk    = Color("RightTrainWarnInk")
    static let rightTrainWarnAccent = Color("RightTrainWarnAccent")

    // Cancelled surface
    static let rightTrainBadBg      = Color("RightTrainBadBg")
    static let rightTrainBadInk     = Color("RightTrainBadInk")
    static let rightTrainBadAccent  = Color("RightTrainBadAccent")

    // Neutral / planning surface
    static let rightTrainSurfaceCream = Color("RightTrainSurfaceCream")
    static let rightTrainPaperCream   = Color("RightTrainPaperCream")
    static let rightTrainInk          = Color("RightTrainInk")
    static let rightTrainInkFaint     = Color("RightTrainInkFaint")
    static let rightTrainActionInk    = Color("RightTrainGoodBg")

    // Legacy backward-compat aliases — kept so existing call sites compile unchanged.
    // The underlying xcasset values have been updated to match the new design tokens.
    static let rightTrainBackground = Color("RightTrainBackground")   // → cream #F4F0E8
    static let rightTrainSurface    = Color("RightTrainSurface")      // → paper cream #FFFCF5
    static let rightTrainHighlight  = Color("RightTrainHighlight")    // → paper cream #FFFCF5
    static let rightTrainAccent     = Color("RightTrainAccent")       // → good accent #9EE07C
    static let rightTrainBorder     = Color("RightTrainBorder")       // → ink-faint
    static let rightTrainAmber      = Color("RightTrainAmber")        // → warn bg #D08214
    static let rightTrainSuccess    = Color("RightTrainSuccess")      // → good bg #0E4A30
    static let rightTrainDanger     = Color("RightTrainDanger")       // → bad bg #831F12
    static let rightTrainBlue       = Color("RightTrainBlue")         // retired — maps to good accent
}

// MARK: - RTSurface

/// Status context for live journey UI. The page shell stays neutral; status
/// colour is applied as accents, borders, and soft callouts. Text and
/// accessibility labels remain the source of truth for action-needed states.
enum RTSurface: Equatable {
    case good    // emerald  — on time / pre-departure default
    case warn    // amber    — delayed
    case bad     // deep red — cancelled
    case neutral // cream    — no live state / planning / settings

    var isStatus: Bool { self != .neutral }

    var bg: Color {
        .rightTrainSurfaceCream
    }

    var ink: Color {
        .rightTrainInk
    }

    var dim: Color {
        .rightTrainInk.opacity(0.62)
    }

    var faint: Color {
        .rightTrainInk.opacity(0.22)
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

    /// Applies fixed ink colours for cream/paper surfaces so dark mode does not
    /// turn text white on the app's intentionally light cards.
    func lightSurfaceForeground() -> some View {
        self.foregroundStyle(
            Color.rightTrainInk,
            Color.rightTrainInk.opacity(0.66),
            Color.rightTrainInk.opacity(0.44)
        )
    }
}

// MARK: - Radius tokens

enum RTRadius {
    static let chip: CGFloat     = 8
    static let card: CGFloat     = 12
    static let heroCard: CGFloat = 18
    static let live: CGFloat     = 22
}

// MARK: - Spacing tokens

enum RTSpacing {
    /// Keep active guidance compact enough for the first screenful contract.
    static let xs: CGFloat              = 4
    static let small: CGFloat           = 8
    static let compact: CGFloat         = 12
    static let listItem: CGFloat        = 10
    static let cardPadding: CGFloat     = 16
    static let pageHorizontal: CGFloat  = 22
    static let pageVertical: CGFloat    = 24
    static let sectionGap: CGFloat      = 22
    static let bottomSafeArea: CGFloat  = 88
    static let statusBarSafeArea: CGFloat = 50
}

// MARK: - Size tokens

enum RTSize {
    static let profileIcon: CGFloat = 40
    static let iconButton: CGFloat  = 34
}

// MARK: - Font tokens

enum RTFont {
    static let statusLabel: Font  = .caption.weight(.semibold)
    static let metricValue: Font  = .subheadline.weight(.semibold)
    static let metricLabel: Font  = .caption
    /// Eyebrow / label style: small caps, tracked, bold
    static let eyebrow: Font      = .system(size: 11, weight: .bold)
}

// MARK: - Dynamic type helpers

extension DynamicTypeSize {
    /// True when text is large enough that fixed-width columnar layouts begin to
    /// cramp or truncate. Use this to switch dense grids to a stacked layout.
    var prefersExpandedLayout: Bool {
        self >= .xxLarge
    }
}
