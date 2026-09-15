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
