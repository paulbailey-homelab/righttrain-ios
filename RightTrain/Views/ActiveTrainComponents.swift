import SwiftUI

struct CompactTrainTime: View {
    var display: JourneyTimeDisplay
    var primaryFont: Font = .subheadline.weight(.semibold)
    var secondaryFont: Font = .caption2

    private var primaryText: String {
        display.currentText ?? display.scheduledText
    }

    private var secondaryText: String? {
        display.currentText == nil ? nil : display.scheduledText
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(primaryText)
                .font(primaryFont)
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .foregroundStyle(display.isDelayed ? Color.rightTrainAmber : .primary)

            if let secondaryText {
                Text(secondaryText)
                    .font(secondaryFont)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .strikethrough(display.isDelayed, color: Color.secondary.opacity(0.7))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        if let secondaryText {
            return "\(primaryText), scheduled \(secondaryText)"
        }
        return primaryText
    }
}

struct PlatformSquareChip: View {
    enum Style {
        case featured
        case compact
    }

    var platform: ActiveWindowPresentation.PlatformDisplay
    var style: Style = .featured
    var label: String? = "Plat"

    private var featuredDisplayValue: String {
        let trimmed = platform.primary.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.uppercased() == "TBC" || trimmed == "-" {
            return trimmed
        }
        if trimmed.uppercased().hasPrefix("P"), trimmed.count > 1 {
            return String(trimmed.dropFirst())
        }
        return trimmed
    }

    private var compactDisplayValue: String {
        let trimmed = platform.primary.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.uppercased() == "TBC" || trimmed == "-" {
            return trimmed
        }
        if trimmed.uppercased().hasPrefix("P") {
            return trimmed.uppercased()
        }
        return "P\(trimmed)"
    }

    private var accessibilityPlatformValue: String {
        let value = compactDisplayValue
        if value.uppercased().hasPrefix("P"), value.count > 1 {
            return String(value.dropFirst())
        }
        return value
    }

    private var hasKnownPlatform: Bool {
        let value = featuredDisplayValue.uppercased()
        return value != "TBC" && value != "-"
    }

    private var isExpected: Bool {
        hasKnownPlatform && !platform.confirmed
    }

    private var featuredLabel: String? {
        guard let label else { return nil }
        return isExpected ? "Exp." : label
    }

    var body: some View {
        Group {
            switch style {
            case .featured:
                VStack(spacing: label == nil ? 0 : 1) {
                    if let featuredLabel {
                        Text(featuredLabel)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Text(featuredDisplayValue)
                        .italic(isExpected)
                        .font((label == nil ? Font.title : Font.title3).weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                }
                .frame(width: RTSize.buttonCompact, height: RTSize.buttonCompact)
                .background(Color.rightTrainInsetFill, in: RoundedRectangle(cornerRadius: RTRadius.chip + 2, style: .continuous))
            case .compact:
                Text(compactDisplayValue)
                    .italic(isExpected)
                    .font(.caption.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 7)
                    .frame(height: 24)
                    .background(Color.rightTrainInsetFill, in: Capsule())
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        switch compactDisplayValue.uppercased() {
        case "TBC":
            return "Platform to be confirmed"
        case "-":
            return "Platform unavailable"
        default:
            return isExpected ? "Expected platform \(accessibilityPlatformValue)" : "Platform \(accessibilityPlatformValue)"
        }
    }
}
