import SwiftUI

// Departure-board lettering: the dot-matrix face from UK platform
// indicators (Daniel Hart's "Dot Matrix", SIL Open Font License 1.1, bundled
// in RightTrain/Fonts with its licence). Shared by the app and the Live
// Activity extension; both copy the font and list it under UIAppFonts.
//
// The rule: values a departure board would show (clock times, countdowns,
// platform numbers) use it; prose, labels and controls stay in the system
// face. The dots blur below about 15pt, so nothing smaller than subheadline
// uses it. The face has no £, · or arrows; those characters fall back to the
// system font. A missing font also falls back to the system face rather
// than failing.

enum BoardFont {
    /// PostScript name of DotMatrix-Bold.ttf.
    static let name = "Dot_Matrix_Bold"

    /// Scales with Dynamic Type like `style`, from that style's default size.
    static func font(_ style: Font.TextStyle) -> Font {
        .custom(name, size: defaultSize(style), relativeTo: style)
    }

    /// For heroes that already scale `size` with their own @ScaledMetric.
    static func font(fixedSize size: CGFloat) -> Font {
        .custom(name, fixedSize: size)
    }

    /// Default (Large) Dynamic Type sizes, so a board value sits at the same
    /// size as the system text it replaces.
    private static func defaultSize(_ style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: 34
        case .title: 28
        case .title2: 22
        case .title3: 20
        case .headline, .body: 17
        case .callout: 16
        case .subheadline: 15
        case .footnote: 13
        case .caption: 12
        case .caption2: 11
        default: 17
        }
    }
}
