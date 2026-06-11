import SwiftUI

// MARK: - Header

struct CompactHeader: View {
    var routeTitle: String
    var summary: String
    var statusText: String
    var updatedAt: Date?
    var now: Date

    private var hasAnomalousStatus: Bool {
        statusText.lowercased() != "active"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(routeTitle)
                        .font(.headline)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if hasAnomalousStatus {
                    StatusPill(text: statusText, tone: .amber)
                        .fixedSize()
                }
            }

            if let updatedAt {
                Text("Updated \(MinuteRelative.text(for: updatedAt, now: now)) ago")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .accessibilityLabel("Updated")
                    .accessibilityValue(relativeAccessibilityText(for: updatedAt))
            }
        }
    }

    private func relativeAccessibilityText(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

enum MinuteRelative {
    /// Returns the absolute duration between two dates, rounded down to minute
    /// resolution. e.g. "5 min", "1 hr 23 min", "less than a min".
    static func text(for date: Date, now: Date) -> String {
        let totalMinutes = max(0, Int(abs(date.timeIntervalSince(now)) / 60))
        if totalMinutes == 0 {
            return "less than a min"
        }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        var parts: [String] = []
        if hours > 0 { parts.append("\(hours) hr") }
        if minutes > 0 { parts.append("\(minutes) min") }
        return parts.joined(separator: " ")
    }
}

// MARK: - Hero card

struct HeroTrainCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var title: String?
    var recommendation: DirectWindowRecommendation
    var countdown: ActiveWindowPresentation.CountdownDisplay
    var now: Date
    var loadDetail: () async -> Void
    var accessibilityLabel: String

    private var journey: JourneyResult {
        recommendation.journey
    }

    private var heroStatus: ActiveWindowPresentation.StatusDisplay? {
        ActiveWindowPresentation.heroStatusDisplay(for: recommendation, now: now)
    }

    private var platform: ActiveWindowPresentation.PlatformDisplay {
        ActiveWindowPresentation.platformDisplay(for: journey)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let title {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .center, spacing: 8) {
                Button {
                    Task { await loadDetail() }
                } label: {
                    cardBody
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityLabel)
                .accessibilityHint("Shows the full journey calling points.")

                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(RTSpacing.compact)
            .background(countdown.tone.color.opacity(0.10), in: RoundedRectangle(cornerRadius: RTRadius.card))
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(countdown.tone.color)
                    .frame(width: 3)
                    .clipShape(RoundedRectangle(cornerRadius: 1.5))
                    .padding(.vertical, RTSpacing.compact)
                    .accessibilityHidden(true)
            }
        }
    }

    private var cardBody: some View {
        Group {
            if dynamicTypeSize.prefersExpandedLayout {
                expandedLayout
            } else {
                denseLayout
            }
        }
        .contentShape(Rectangle())
    }

    private var denseLayout: some View {
        VStack(alignment: .leading, spacing: 6) {
            preDepartureHeroRow
            operatorLine
            preDepartureDetailLine
            disruptionLine
        }
    }

    private var expandedLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            preDepartureHeroRow
            operatorLine
            preDepartureDetailLine
            disruptionLine
        }
    }

    private var preDepartureHeroRow: some View {
        HStack(alignment: .top, spacing: 10) {
            HeroCountdownText(countdown: countdown)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 6) {
                if let heroStatus {
                    StatusPill(text: heroStatus.text, tone: heroStatus.tone)
                }
                PlatformSquareChip(platform: platform, style: dynamicTypeSize > .large ? .compact : .featured)
            }
            .fixedSize(horizontal: true, vertical: false)
            .layoutPriority(1)
        }
    }

    private var preDepartureDetailLine: some View {
        Text("Dep \(JourneyFormatting.departureText(journey)) · Arr \(JourneyFormatting.arrivalText(journey))")
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.78)
    }

    @ViewBuilder
    private var operatorLine: some View {
        if journey.operatorName != nil || journey.operatorShortName != nil || journey.toc != nil {
            AdaptiveOperatorText(
                full: journey.operatorName,
                short: journey.operatorShortName,
                code: journey.toc
            )
        }
    }

    @ViewBuilder
    private var onboardProgress: some View {
        if let progress = JourneyFormatting.journeyProgress(journey, now: now) {
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: progress)
                    .tint(Color.rightTrainAccent)
            }
            .padding(.top, 2)
        }
    }

    @ViewBuilder
    private var disruptionLine: some View {
        if heroStatus != nil {
            DisruptionLine(journey: journey, score: recommendation.score)
                .font(.caption)
        }
    }
}

private struct HeroCountdownText: View {
    var countdown: ActiveWindowPresentation.CountdownDisplay

    var body: some View {
        Text(countdown.text)
            .font(.title3.weight(.bold))
            .foregroundStyle(countdown.tone.color)
            .monospacedDigit()
            .contentTransition(.numericText(countsDown: countsDown))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    private var countsDown: Bool {
        guard let targetDate = countdown.targetDate else {
            return false
        }
        return targetDate > Date()
    }
}

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
                        .opacity(0.72)

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
        .frame(minHeight: 42)
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
                    .frame(width: 13)
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
            .fill(Color.rightTrainBorder.opacity(0.55))
            .frame(height: 0.5)
    }
}

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

// MARK: - Status-first hero block

/// The full-bleed hero block on the active window: giant countdown + dep/arr/platform strip.
/// Tapping opens the journey detail sheet. Rendered directly on the status-surface background —
/// no card chrome needed.
struct StatusFirstHeroBlock: View {
    var presentation: ActiveWindowPresentation
    var countdown: ActiveWindowPresentation.CountdownDisplay
    var surface: RTSurface
    var now: Date
    var loadDetail: () async -> Void
    var requestUnpin: () -> Void

    private var recommendation: DirectWindowRecommendation { presentation.heroRecommendation }
    private var journey: JourneyResult { recommendation.journey }
    private var depDisplay: JourneyTimeDisplay { JourneyFormatting.departureDisplay(journey) }
    private var arrDisplay: JourneyTimeDisplay { JourneyFormatting.arrivalDisplay(journey) }
    private var platform: ActiveWindowPresentation.PlatformDisplay {
        ActiveWindowPresentation.platformDisplay(for: journey)
    }

    var body: some View {
        Button {
            Task { await loadDetail() }
        } label: {
            VStack(alignment: .leading, spacing: RTSpacing.sectionGap) {
                countdownHero
                timeStrip
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityHint("Shows full journey calling points")
        .accessibilityAction(named: "Unpin") { requestUnpin() }
    }

    // MARK: - Countdown hero

    private var countdownHero: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Eyebrow: "PINNED TRAIN" / "RECOMMENDED TRAIN" / "ON BOARD"
            Text(presentation.heroTitle.uppercased())
                .font(RTFont.eyebrow)
                .tracking(2)
                .foregroundStyle(surface.dim)
                .padding(.bottom, RTSpacing.xs)

            // Optional prefix label ("Leaves in", "Departed", "Arriving at")
            if let prefix = countdownPrefix {
                Text(prefix)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(surface.dim)
                    .padding(.bottom, 2)
            }

            // Giant countdown value (the glanceable core)
            Text(countdownValue)
                .font(.system(size: 56, weight: .bold))
                .foregroundStyle(surface.ink)
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: countdown.targetDate.map { $0 > now } ?? false))
                .lineLimit(1)
                .minimumScaleFactor(0.44)
                .padding(.bottom, RTSpacing.compact)

            // Route context line
            Text(presentation.routeTitle)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(surface.dim)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
    }

    // MARK: - Time strip

    private var timeStrip: some View {
        HStack(spacing: 0) {
            timeCell(label: "Dep", display: depDisplay)

            Rectangle()
                .fill(surface.softBorder)
                .frame(width: 1)

            timeCell(label: "Arr", display: arrDisplay)

            Rectangle()
                .fill(surface.softBorder)
                .frame(width: 1)

            platformCell
        }
        .background(surface.softFill, in: RoundedRectangle(cornerRadius: RTRadius.card))
        .overlay {
            RoundedRectangle(cornerRadius: RTRadius.card)
                .stroke(surface.softBorder, lineWidth: 1)
        }
    }

    private func timeCell(label: String, display: JourneyTimeDisplay) -> some View {
        let primaryTime = display.currentText ?? display.scheduledText
        let scheduledTime: String? = display.currentText != nil ? display.scheduledText : nil

        return VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(RTFont.eyebrow)
                .tracking(1.5)
                .foregroundStyle(surface.dim)

            VStack(alignment: .leading, spacing: 1) {
                Text(primaryTime)
                    .font(.system(size: 18, weight: .bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(surface.ink)
                    .lineLimit(1)

                if let scheduled = scheduledTime {
                    Text(scheduled)
                        .font(.caption2.weight(.medium))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .strikethrough(display.isDelayed, color: surface.faint)
                        .foregroundStyle(surface.dim)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var platformCell: some View {
        let value = compactPlatformValue
        return VStack(alignment: .leading, spacing: 3) {
            Text("Platform")
                .font(RTFont.eyebrow)
                .tracking(0.5)
                .foregroundStyle(surface.dim)
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(value == "-" || value.uppercased() == "TBC" ? surface.dim : surface.ink)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - Helpers

    /// Splits "Leaves in 14 min" into prefix "Leaves in" / value "14 min".
    /// Handles all countdown text variants produced by ActiveWindowPresentation.countdown().
    private var countdownPrefix: String? {
        let text = countdown.text
        if text.hasPrefix("Leaves in ")       { return "Leaves in" }
        if text.hasPrefix("Departed · arr ")  { return "Arriving at" }
        if text.hasPrefix("Departed ")        { return "Departed" }
        return nil
    }

    private var countdownValue: String {
        let text = countdown.text
        if text.hasPrefix("Leaves in ")       { return String(text.dropFirst("Leaves in ".count)) }
        if text.hasPrefix("Departed · arr ")  { return String(text.dropFirst("Departed · arr ".count)) }
        if text.hasPrefix("Departed ")        { return String(text.dropFirst("Departed ".count)) }
        return text
    }

    private var compactPlatformValue: String {
        let p = platform.primary.trimmingCharacters(in: .whitespacesAndNewlines)
        if p.uppercased() == "TBC" || p == "-" { return p }
        if p.uppercased().hasPrefix("P"), p.count > 1 { return String(p.dropFirst()) }
        return p
    }

    private var accessibilityDescription: String {
        let depTime  = depDisplay.currentText ?? depDisplay.scheduledText
        let arrTime  = arrDisplay.currentText ?? arrDisplay.scheduledText
        return [
            presentation.heroTitle,
            countdown.text,
            presentation.routeTitle,
            "Departs \(depTime)",
            "Arrives \(arrTime)",
            "Platform \(platform.primary)"
        ].joined(separator: ", ")
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
                    .foregroundStyle(surface.faint)
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
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(surface.dim)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Text(compactPlatform)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(surface.ink)
                    .padding(.horizontal, 7)
                    .frame(height: 22)
                    .background(surface.softFill, in: Capsule())
                    .overlay { Capsule().stroke(surface.softBorder, lineWidth: 1) }
                    .lineLimit(1)

                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(surface.faint)
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
        case .red:   return .rightTrainBadAccent
        case .amber: return .rightTrainWarnAccent
        default:     return surface.accent
        }
    }

    private var compactPlatform: String {
        let p = platform.primary.trimmingCharacters(in: .whitespacesAndNewlines)
        if p.uppercased() == "TBC" || p == "-" { return p }
        if p.uppercased().hasPrefix("P"), p.count > 1 { return String(p.dropFirst()) }
        return p
    }

    private var accessibilityText: String {
        var parts: [String] = []
        if isPinned         { parts.append("Pinned journey") }
        if isCancelledTrain { parts.append("Cancelled") }
        parts.append("Departs \(depDisplay.currentText ?? depDisplay.scheduledText)")
        parts.append("Arrives \(arrDisplay.currentText ?? arrDisplay.scheduledText)")
        if let status = rowStatus { parts.append(status.text) }
        parts.append("Platform \(platform.primary)")
        return parts.joined(separator: ", ")
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
