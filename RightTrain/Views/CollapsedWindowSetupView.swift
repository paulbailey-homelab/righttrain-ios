import SwiftUI

struct CollapsedWindowSetupView: View {
    var state: ActiveWindowPresentation.CollapsedSetupState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: RTSpacing.listItem) {
                    collapsedTitle
                    Spacer(minLength: 8)
                    collapsedStatus
                }

                VStack(alignment: .leading, spacing: 6) {
                    collapsedTitle
                    collapsedStatus
                }
            }

            Text(state.message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
        .rtCard()
        .lightSurfaceForeground()
        .accessibilityElement(children: .combine)
    }

    private var collapsedTitle: some View {
        Text(state.title)
            .font(.headline)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var collapsedStatus: some View {
        Text(state.statusText)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color.rightTrainBackground, in: Capsule())
    }
}
