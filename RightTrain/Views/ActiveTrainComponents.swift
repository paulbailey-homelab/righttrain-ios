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

    var body: some View {
        Group {
            switch style {
            case .featured:
                VStack(spacing: label == nil ? 0 : 1) {
                    if let label {
                        Text(label)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Text(featuredDisplayValue)
                        .font((label == nil ? Font.title : Font.title3).weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                }
                .frame(width: 52, height: 52)
                .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 7))
                .overlay {
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(Color.secondary.opacity(0.22), lineWidth: 1)
                }
            case .compact:
                Text(compactDisplayValue)
                    .font(.caption.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 7)
                    .frame(height: 24)
                    .background(Color.secondary.opacity(0.10), in: Capsule())
                    .overlay {
                        Capsule()
                            .stroke(Color.secondary.opacity(0.22), lineWidth: 1)
                    }
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
            return "Platform \(accessibilityPlatformValue)"
        }
    }
}
