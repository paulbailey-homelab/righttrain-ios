import SwiftUI

// Departure-board lettering: the dot-matrix face from UK platform
// indicators (Daniel Hart's "Dot Matrix", SIL Open Font License 1.1, bundled
// in RightTrain/Fonts with its licence). Regular has the single-dot strokes
// of real boards; Bold doubles them for the large lines.
//
// The rule: the board face appears only inside a DepartureBoard, and
// everything inside a board uses it. Outside a board the app stays in the
// system face, so the two never share a line. The face has no £, · or
// arrows; board copy avoids them. A missing font falls back to the system
// face rather than failing.

enum BoardFont {
    enum Weight {
        case regular
        case bold

        /// PostScript names of DotMatrix-Regular.ttf and DotMatrix-Bold.ttf.
        var postScriptName: String {
            switch self {
            case .regular: "Dot_Matrix"
            case .bold: "Dot_Matrix_Bold"
            }
        }
    }

    /// Scales with Dynamic Type like `style`, from that style's default size.
    static func font(_ style: Font.TextStyle, weight: Weight = .regular) -> Font {
        .custom(weight.postScriptName, size: defaultSize(style), relativeTo: style)
    }

    /// For text that already scales `size` with its own @ScaledMetric.
    static func font(fixedSize size: CGFloat, weight: Weight = .regular) -> Font {
        .custom(weight.postScriptName, fixedSize: size)
    }

    /// Default (Large) Dynamic Type sizes, so a board line sits at the same
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
