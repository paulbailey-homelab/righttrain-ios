import SwiftUI

// MARK: - Just departed

struct JustDepartedSection: View {
    @State private var caughtFeedbackTrigger = 0
    @State private var notOnFeedbackTrigger = 0

    var recommendation: DirectWindowRecommendation
    var countdown: ActiveWindowPresentation.CountdownDisplay
    var isPinned: Bool
    var loadDetail: () async -> Void
    var caughtTrain: () async -> Void
    var notOnTrain: () async -> Void
    var accessibilityLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Just departed")
                    .font(.footnote.weight(.semibold))
                Text("· \(countdown.text)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            VStack(alignment: .leading, spacing: 8) {
                UpcomingTrainRow(
                    recommendation: recommendation,
                    isPinned: isPinned,
                    loadDetail: loadDetail,
                    togglePinned: {
                        if isPinned {
                            await notOnTrain()
                        } else {
                            await caughtTrain()
                        }
                    },
                    accessibilityLabel: accessibilityLabel
                )

                actionButtons
            }
        }
        .sensoryFeedback(.success, trigger: caughtFeedbackTrigger)
        .sensoryFeedback(.warning, trigger: notOnFeedbackTrigger)
    }

    private var actionButtons: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                caughtButton
                notOnButton
            }

            VStack(spacing: 8) {
                caughtButton
                notOnButton
            }
        }
    }

    private var caughtButton: some View {
        Button {
            caughtFeedbackTrigger += 1
            Task { await caughtTrain() }
        } label: {
            Label("I caught this train", systemImage: "pin")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    private var notOnButton: some View {
        Button {
            notOnFeedbackTrigger += 1
            Task { await notOnTrain() }
        } label: {
            Label("I missed it", systemImage: "arrow.forward.circle")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }
}

// MARK: - Cancelled trains

struct CancelledTrainsSection: View {
    var cancelled: [DirectWindowRecommendation]
    @Binding var isExpanded: Bool
    var loadDetail: (DirectWindowRecommendation) async -> Void
    var trainAccessibilityLabel: (DirectWindowRecommendation) -> String

    private var toggleLabel: String {
        if isExpanded {
            return "Hide cancelled trains"
        }
        let trainText = cancelled.count == 1 ? "train" : "trains"
        return "Show \(cancelled.count) cancelled \(trainText)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2.weight(.bold))
                        .padding(.top, 6)
                    SectionHeader(
                        title: "Cancelled",
                        subtitle: toggleLabel,
                        tone: .red
                    )
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Color.rightTrainDanger)
                .activeSectionHeaderBackground(tone: .red, opacity: 0.12)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Toggles the list of cancelled trains.")

            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(cancelled.enumerated()), id: \.element.id) { index, recommendation in
                        UpcomingTrainRow(
                            recommendation: recommendation,
                            isPinned: false,
                            allowsPinning: false,
                            loadDetail: { await loadDetail(recommendation) },
                            togglePinned: {},
                            accessibilityLabel: trainAccessibilityLabel(recommendation)
                        )
                        .opacity(RTOpacity.emphasized)

                        if index < cancelled.count - 1 {
                            SoftDivider()
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Past trains

struct PastTrainsSection: View {
    var past: [DirectWindowRecommendation]
    @Binding var isExpanded: Bool
    var pinnedServiceID: Int?
    var loadDetail: (DirectWindowRecommendation) async -> Void
    var togglePinned: (DirectWindowRecommendation) async -> Void
    var trainAccessibilityLabel: (DirectWindowRecommendation) -> String

    private var subtitle: String {
        if isExpanded {
            return "Hide departed trains"
        }
        let trainText = past.count == 1 ? "train" : "trains"
        return "Show \(past.count) departed \(trainText)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2.weight(.bold))
                        .padding(.top, 6)
                    SectionHeader(
                        title: "Departed",
                        subtitle: subtitle,
                        tone: .neutral
                    )
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.secondary)
                .activeSectionHeaderBackground(tone: .neutral, opacity: 0.12)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Toggles the list of departed trains.")

            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(past.enumerated()), id: \.element.id) { index, recommendation in
                        UpcomingTrainRow(
                            recommendation: recommendation,
                            isPinned: pinnedServiceID == recommendation.journey.serviceId,
                            loadDetail: { await loadDetail(recommendation) },
                            togglePinned: { await togglePinned(recommendation) },
                            accessibilityLabel: trainAccessibilityLabel(recommendation)
                        )
                        .opacity(0.64)

                        if index < past.count - 1 {
                            SoftDivider()
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Upcoming list

struct UpcomingList: View {
    var items: [DirectWindowRecommendation]
    var pinnedServiceID: Int?
    var loadDetail: (DirectWindowRecommendation) async -> Void
    var togglePinned: (DirectWindowRecommendation) async -> Void
    var trainAccessibilityLabel: (DirectWindowRecommendation) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Upcoming")
                    .font(.footnote.weight(.semibold))
                Text(upcomingSubtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .activeSectionHeaderBackground(tone: .neutral, opacity: 0.06)
            .padding(.top, 2)

            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, recommendation in
                    UpcomingTrainRow(
                        recommendation: recommendation,
                        isPinned: pinnedServiceID == recommendation.journey.serviceId,
                        loadDetail: { await loadDetail(recommendation) },
                        togglePinned: { await togglePinned(recommendation) },
                        accessibilityLabel: trainAccessibilityLabel(recommendation)
                    )

                    if index < items.count - 1 {
                        SoftDivider()
                    }
                }
            }
        }
    }

    private var upcomingSubtitle: String {
        let trainText = items.count == 1 ? "train" : "trains"
        return "\(items.count) \(trainText) still to depart"
    }
}

private enum UpcomingRowLayout {
    static let departureWidth: CGFloat = 50
    static let arrivalWidth: CGFloat = 50
    static let columnSpacing: CGFloat = 8
}

private struct UpcomingTrainRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var entryAnimationTrigger = false

    var recommendation: DirectWindowRecommendation
    var isPinned: Bool
    var allowsPinning: Bool = true
    var loadDetail: () async -> Void
    var togglePinned: () async -> Void
    var accessibilityLabel: String

    private var journey: JourneyResult {
        recommendation.journey
    }

    private var rowStatus: ActiveWindowPresentation.StatusDisplay? {
        ActiveWindowPresentation.heroStatusDisplay(for: recommendation)
    }

    private var platform: ActiveWindowPresentation.PlatformDisplay {
        ActiveWindowPresentation.platformDisplay(for: journey)
    }

    var body: some View {
        Group {
            if allowsPinning {
                baseButton
                    .contextMenu {
                        Button {
                            Task { await togglePinned() }
                        } label: {
                            Label(isPinned ? "Change train" : "Pin this journey",
                                  systemImage: isPinned ? "pin.slash" : "pin")
                        }
                    }
                    .accessibilityAction(named: isPinned ? "Change train" : "Pin this journey") {
                        Task { await togglePinned() }
                    }
            } else {
                baseButton
            }
        }
    }

    private var baseButton: some View {
        Button {
            Task { await loadDetail() }
        } label: {
            rowBody
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(isPinned && allowsPinning ? Color.rightTrainAccent.opacity(0.08) : Color.clear)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isPinned && allowsPinning ? "\(accessibilityLabel), pinned" : accessibilityLabel)
        .accessibilityHint("Shows the full journey calling points.")
    }

    @ViewBuilder
    private var rowBody: some View {
        if dynamicTypeSize.prefersExpandedLayout {
            expandedLayout
        } else {
            denseLayout
        }
    }

    private var denseLayout: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                ViewThatFits(in: .horizontal) {
                    rowTimingColumns
                    compactStackedTiming
                }
                metadataLine
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            rowTrailingControls(statusDisplay: rowStatus)
                .layoutPriority(1)
        }
        .frame(minHeight: RTSize.rowMinHeight)
        .padding(.vertical, 5)
    }

    private var expandedLayout: some View {
        VStack(alignment: .leading, spacing: 6) {
            if isPinned {
                Text("Journey pinned")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.rightTrainAccent)
            }
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 6) {
                    rowTimingColumns
                    metadataLine
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                rowTrailingControls(statusDisplay: rowStatus)
                    .layoutPriority(1)
            }
        }
        .padding(.vertical, 8)
    }

    private var rowTimingColumns: some View {
        HStack(alignment: .center, spacing: UpcomingRowLayout.columnSpacing) {
            trainSymbol
            CompactTrainTime(display: JourneyFormatting.departureDisplay(journey))
                .frame(width: UpcomingRowLayout.departureWidth, alignment: .leading)
            Image(systemName: "arrow.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
            CompactTrainTime(display: JourneyFormatting.arrivalDisplay(journey))
                .frame(width: UpcomingRowLayout.arrivalWidth, alignment: .leading)
        }
    }

    private var compactStackedTiming: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .center, spacing: UpcomingRowLayout.columnSpacing) {
                trainSymbol
                CompactTrainTime(display: JourneyFormatting.departureDisplay(journey))
            }

            HStack(alignment: .center, spacing: UpcomingRowLayout.columnSpacing) {
                Image(systemName: "arrow.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: RTSize.glyphColumn)
                    .accessibilityHidden(true)
                CompactTrainTime(display: JourneyFormatting.arrivalDisplay(journey))
            }
            .padding(.leading, 24)
        }
    }

    private var trainSymbol: some View {
        Image(systemName: "tram.fill")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Color.rightTrainAccent)
            .symbolEffect(.bounce, value: entryAnimationTrigger)
            .accessibilityHidden(true)
            .onAppear {
                guard !reduceMotion else { return }
                entryAnimationTrigger.toggle()
            }
    }

    private func rowTrailingControls(statusDisplay: ActiveWindowPresentation.StatusDisplay?) -> some View {
        HStack(alignment: .center, spacing: 8) {
            if isPinned {
                Image(systemName: "pin.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.rightTrainAccent)
                    .accessibilityHidden(true)
            }
            if let statusDisplay {
                StatusPill(text: statusDisplay.text, tone: statusDisplay.tone)
            }
            PlatformSquareChip(platform: platform, style: .compact)
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
    }

    private var metadataLine: some View {
        let parts = [
            JourneyFormatting.windowMembershipText(journey),
            JourneyFormatting.operatorSummaryText(journey)
        ].compactMap { $0 }

        return Text(parts.joined(separator: " · "))
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
    }
}

// MARK: - Shared building blocks

private extension View {
    func activeSectionHeaderBackground(tone: StatusPill.Tone, opacity: Double) -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(tone.color.opacity(opacity), in: RoundedRectangle(cornerRadius: RTRadius.chip))
    }
}

private struct SoftDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.rightTrainBorder.opacity(RTOpacity.secondary))
            .frame(height: 0.5)
    }
}

// MARK: - Status-first train row (other trains list)

/// Compact train row rendered inside the other-trains container on a status surface.
/// All colours are derived from `surface` so they read correctly on emerald / amber / deep-red.
struct StatusFirstTrainRow: View {
    var recommendation: DirectWindowRecommendation
    var surface: RTSurface
    var isPinned: Bool
    var now: Date
    var loadDetail: () async -> Void
    var togglePinned: () async -> Void

    private var journey: JourneyResult { recommendation.journey }

    private var rowStatus: ActiveWindowPresentation.StatusDisplay? {
        ActiveWindowPresentation.heroStatusDisplay(for: recommendation, now: now)
    }

    private var platform: ActiveWindowPresentation.PlatformDisplay {
        ActiveWindowPresentation.platformDisplay(for: journey)
    }

    private var isCancelledTrain: Bool { JourneyFormatting.isCancelled(journey) }
    private var depDisplay: JourneyTimeDisplay { JourneyFormatting.departureDisplay(journey) }
    private var arrDisplay: JourneyTimeDisplay { JourneyFormatting.arrivalDisplay(journey) }

    var body: some View {
        Button {
            Task { await loadDetail() }
        } label: {
            rowContent
        }
        .buttonStyle(.plain)
        .opacity(isCancelledTrain ? 0.58 : 1.0)
        .contextMenu {
            Button {
                Task { await togglePinned() }
            } label: {
                Label(
                    isPinned ? "Change train" : "Pin this journey",
                    systemImage: isPinned ? "pin.slash" : "pin"
                )
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Shows full journey calling points")
        .accessibilityAction(named: isPinned ? "Change train" : "Pin this journey") {
            Task { await togglePinned() }
        }
    }

    private var rowContent: some View {
        HStack(alignment: .center, spacing: RTSpacing.small) {
            // Status indicator dot — accent for on-time, accent-of-status-surface for anomalies
            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)

            // Dep → Arr timing columns
            HStack(alignment: .top, spacing: 5) {
                surfaceTimeView(depDisplay)
                    .frame(width: 46, alignment: .leading)

                Text("→")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
                    .accessibilityHidden(true)

                surfaceTimeView(arrDisplay)
                    .frame(width: 46, alignment: .leading)
            }

            Spacer(minLength: RTSpacing.xs)

            // Trailing: optional anomaly label + platform chip + chevron
            HStack(alignment: .center, spacing: 6) {
                if let status = rowStatus {
                    Text(status.text)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(status.tone.color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Text(compactPlatform)
                    .italic(isExpectedPlatform)
                    .font(.footnote.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .frame(minWidth: 26, minHeight: 24)
                    .padding(.horizontal, 4)
                    .background(Color.rightTrainInsetFill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .lineLimit(1)

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .layoutPriority(1)
        }
        .padding(.vertical, RTSpacing.compact)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    // MARK: - Surface-aware time display

    private func surfaceTimeView(_ display: JourneyTimeDisplay) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(display.currentText ?? display.scheduledText)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(surface.ink)
                .lineLimit(1)

            // Only show scheduled (strikethrough) when a realtime time differs
            if display.currentText != nil {
                Text(display.scheduledText)
                    .font(.caption2)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .strikethrough(display.isDelayed, color: surface.faint)
                    .foregroundStyle(surface.dim)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Helpers

    /// Dot colour: accent colours from the relevant status surface, so they
    /// remain distinguishable regardless of which surface this row lives on.
    private var dotColor: Color {
        switch rowStatus?.tone {
        case .red:   return .rightTrainDanger
        case .amber: return .rightTrainAmber
        default:     return surface.accent
        }
    }

    private var compactPlatform: String {
        let p = platform.primary.trimmingCharacters(in: .whitespacesAndNewlines)
        if p.uppercased() == "TBC" || p == "-" { return p }
        if p.uppercased().hasPrefix("P"), p.count > 1 { return String(p.dropFirst()) }
        return p
    }

    private var isExpectedPlatform: Bool {
        let p = compactPlatform.uppercased()
        return p != "TBC" && p != "-" && !platform.confirmed
    }

    private var accessibilityText: String {
        var parts: [String] = []
        if isPinned         { parts.append("Pinned journey") }
        if isCancelledTrain { parts.append("Cancelled") }
        parts.append("Departs \(depDisplay.currentText ?? depDisplay.scheduledText)")
        parts.append("Arrives \(arrDisplay.currentText ?? arrDisplay.scheduledText)")
        if let status = rowStatus { parts.append(status.text) }
        parts.append(JourneyFormatting.platformStateText(primary: platform.primary, confirmed: platform.confirmed))
        return parts.joined(separator: ", ")
    }
}
