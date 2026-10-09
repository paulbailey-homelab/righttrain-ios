import SwiftUI

// Departure-board lettering: the dot-matrix face from UK platform
// indicators (Daniel Hart's "Dot Matrix", SIL Open Font License 1.1, bundled
// in RightTrain/Fonts with its licence). Regular has the single-dot strokes
// of real boards; Bold doubles them for the large lines.
//
// The rule: the face appears only on a sign, a drawn display object with a
// lit dot-matrix face, and everything on a sign uses it. The signs are the
// platform indicator and concourse board on Pinned, and the Lock Screen Live
// Activity. Search results and app chrome stay in the system face. The face has no £, · or arrows; sign copy avoids them. A
// missing font falls back to the system face rather than failing.

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

/// Board colours, shared with the Live Activity. Boards keep amber on black
/// in light and dark mode: they're a physical object, not a themed surface.
enum DepartureBoardStyle {
    /// The amber of LED platform indicators.
    static let amber = Color(red: 1.0, green: 0.69, blue: 0.0)
    /// Column headings, expected platforms and stale values.
    static let dimAmber = amber.opacity(0.55)
    static let background = Color(red: 0.035, green: 0.035, blue: 0.03)
    /// The unlit pixels behind the lettering.
    static let unlit = amber.opacity(0.08)
    /// The faint halo lit LEDs throw on the glass in front of them.
    static let glow = amber.opacity(0.45)
}

/// The unlit pixels of a dot-matrix display: a faint grid behind the
/// lettering, so a sign reads as a display rather than a black box.
struct SignDotGrid: View {
    /// Centre-to-centre distance between dots.
    var pitch: CGFloat = 3.5

    var body: some View {
        Canvas { context, size in
            let diameter = pitch * 0.5
            var path = Path()
            var y = pitch / 2
            while y < size.height {
                var x = pitch / 2
                while x < size.width {
                    path.addEllipse(in: CGRect(
                        x: x - diameter / 2,
                        y: y - diameter / 2,
                        width: diameter,
                        height: diameter
                    ))
                    x += pitch
                }
                y += pitch
            }
            context.fill(path, with: .color(DepartureBoardStyle.unlit))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
