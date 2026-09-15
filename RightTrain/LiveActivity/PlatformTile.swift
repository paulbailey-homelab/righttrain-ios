import SwiftUI
import UIKit

// Shared by the app and the Live Activity extension, so a platform looks the
// same on Pinned, in journey detail, on the Lock Screen and in the Dynamic
// Island.
//
// The rule: a platform shown as a value is always a PlatformTile carrying the
// bare number, never "P4", "Plat" or "Exp.". Its state is in the tile's
// style: solid when confirmed, dashed outline when expected, amber when it
// changed, faint dashed "TBC" when unknown. In running prose it stays words
// ("Go to platform 4"), and PlatformValue supplies the caption and
// VoiceOver text so those match too.

/// A platform parsed once from feed strings ("4", "P4", " 12A", "TBC", "-").
struct PlatformValue: Equatable {
    enum State: Equatable {
        case confirmed
        case expected
        case unknown
    }

    /// The bare platform, e.g. "4" or "12A"; nil when unknown.
    var number: String?
    var state: State
    /// The platform it moved from, when it changed between two known ones.
    var previousNumber: String?

    init(_ raw: String?, confirmed: Bool, previous: String? = nil) {
        number = Self.bare(raw)
        if number == nil {
            state = .unknown
        } else {
            state = confirmed ? .confirmed : .expected
        }
        if let number, let old = Self.bare(previous), old != number {
            previousNumber = old
        } else {
            previousNumber = nil
        }
    }

    static let unknown = PlatformValue(nil, confirmed: false)

    var isChanged: Bool { previousNumber != nil }

    /// Strips whitespace and a "P" prefix; nil for empty, "-" or "TBC".
    static func bare(_ raw: String?) -> String? {
        guard var value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        if value.lowercased().hasPrefix("platform ") {
            value = String(value.dropFirst("platform ".count))
        } else if value.uppercased().hasPrefix("P"), value.count > 1 {
            value = String(value.dropFirst())
        }
        value = value.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty, value != "-", value != "—", value.uppercased() != "TBC" else {
            return nil
        }
        return value.uppercased()
    }

    /// The label above a tile: "Platform", "Expected platform",
    /// "Was platform 2". `role` replaces "Platform", e.g. "Next platform".
    func caption(role: String = "Platform") -> String {
        if let previousNumber {
            return "Was \(role.lowercased()) \(previousNumber)"
        }
        if state == .expected {
            return "Expected \(role.lowercased())"
        }
        return role
    }

    /// VoiceOver text, e.g. "Expected arrival platform 4".
    func accessibilityLabel(role: String = "Platform") -> String {
        guard let number else {
            return "\(role) to be confirmed"
        }
        let name = state == .expected ? "Expected \(role.lowercased())" : role
        if let previousNumber {
            return "\(name) \(number), changed from \(previousNumber)"
        }
        return "\(name) \(number)"
    }
}

struct PlatformTile: View {
    enum Size {
        /// Rows, stop lists and compact islands.
        case small
        /// Cards and secondary heroes.
        case medium
        /// The countdown hero.
        case large
    }

    var platform: PlatformValue
    var size: Size = .small
    /// VoiceOver name, e.g. "Arrival platform".
    var role = "Platform"
    var ink = Color(uiColor: .label)
    /// Number colour on a solid tile.
    var onInk = Color(uiColor: .systemBackground)
    /// The app's amber; both targets share the colour asset.
    var changeTint = Color("RightTrainAmber")
    /// Number colour on a changed (tinted) tile.
    var onChangeTint = Color.black

    @ScaledMetric(relativeTo: .footnote) private var smallSide: CGFloat = 22
    @ScaledMetric(relativeTo: .title3) private var mediumSide: CGFloat = 36
    @ScaledMetric(relativeTo: .largeTitle) private var largeSide: CGFloat = 72
    @ScaledMetric(relativeTo: .largeTitle) private var largeNumber: CGFloat = 52

    var body: some View {
        Text(platform.number ?? "TBC")
            .font(font)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .foregroundStyle(numberStyle)
            .padding(.horizontal, horizontalPadding)
            .frame(minWidth: side, minHeight: side)
            .background { tileShape.fill(fillStyle) }
            .overlay {
                if platform.state != .confirmed, !platform.isChanged {
                    tileShape.strokeBorder(
                        platform.state == .unknown ? ink.opacity(0.4) : ink,
                        style: StrokeStyle(lineWidth: strokeWidth, dash: [strokeWidth * 2.5, strokeWidth * 1.6])
                    )
                }
            }
            .fixedSize()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(platform.accessibilityLabel(role: role))
    }

    private var tileShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: side * 0.22, style: .continuous)
    }

    private var side: CGFloat {
        switch size {
        case .small: smallSide
        case .medium: mediumSide
        case .large: largeSide
        }
    }

    private var horizontalPadding: CGFloat {
        switch size {
        case .small: 5
        case .medium: 8
        case .large: 12
        }
    }

    private var strokeWidth: CGFloat {
        switch size {
        case .small: 1.25
        case .medium: 1.5
        case .large: 2.5
        }
    }

    private var font: Font {
        let isUnknown = platform.number == nil
        switch size {
        case .small:
            return (isUnknown ? Font.caption2 : Font.footnote).weight(.bold)
        case .medium:
            return (isUnknown ? Font.footnote : Font.title3).weight(.bold)
        case .large:
            return isUnknown
                ? .title3.weight(.bold)
                : .system(size: largeNumber, weight: .bold, design: .rounded)
        }
    }

    private var fillStyle: Color {
        if platform.isChanged { return changeTint }
        return platform.state == .confirmed ? ink : .clear
    }

    private var numberStyle: Color {
        if platform.isChanged { return onChangeTint }
        switch platform.state {
        case .confirmed: return onInk
        case .expected: return ink
        case .unknown: return ink.opacity(0.55)
        }
    }
}

/// Caption over a tile, as on the hero and Lock Screen.
struct CaptionedPlatformTile: View {
    var platform: PlatformValue
    var size: PlatformTile.Size = .medium
    var role = "Platform"
    var alignment: HorizontalAlignment = .trailing
    var captionFont: Font = .subheadline.weight(.medium)
    var captionColor = Color.secondary
    var ink = Color(uiColor: .label)
    var onInk = Color(uiColor: .systemBackground)
    /// The app's amber; both targets share the colour asset.
    var changeTint = Color("RightTrainAmber")
    var onChangeTint = Color.black

    var body: some View {
        VStack(alignment: alignment, spacing: 4) {
            Text(platform.caption(role: role))
                .font(captionFont)
                .foregroundStyle(platform.isChanged ? changeTint : captionColor)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .accessibilityHidden(true)
            PlatformTile(
                platform: platform,
                size: size,
                role: role,
                ink: ink,
                onInk: onInk,
                changeTint: changeTint,
                onChangeTint: onChangeTint
            )
        }
    }
}
