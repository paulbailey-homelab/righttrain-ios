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
        HStack(alignment: .top, spacing: RTSpacing.listItem) {
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

// MARK: - Status-first hero block

/// The full-bleed hero block on the active window: giant countdown + dep/arr/platform strip.
/// Tapping opens the journey detail sheet. Rendered directly on the status-surface background —
/// no card chrome needed.
struct StatusFirstHeroBlock: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var presentation: ActiveWindowPresentation
    var countdown: ActiveWindowPresentation.CountdownDisplay
    var surface: RTSurface
    var now: Date
    var freshnessText: String
    /// Old or offline data: the countdown is dimmed so it isn't read as live.
    var isStale = false
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
            VStack(alignment: .leading, spacing: RTSpacing.cardPadding) {
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
        VStack(alignment: .leading, spacing: 2) {
            // The countdown and the platform are the two things to act on,
            // so they share the top row at the same scale.
            // Side by side the two heroes squeeze each other at accessibility
            // sizes, so they stack there.
            let heroLayout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: RTSpacing.small))
                : AnyLayout(HStackLayout(alignment: .lastTextBaseline, spacing: RTSpacing.compact))
            heroLayout {
                VStack(alignment: .leading, spacing: 0) {
                    if let prefix = countdownPrefix {
                        Text(prefix)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                    }

                    Text(countdownValue)
                        .heroNumberFont(size: 56)
                        .foregroundStyle(isStale ? AnyShapeStyle(.secondary) : AnyShapeStyle(surface.ink))
                        .monospacedDigit()
                        .contentTransition(.numericText(countsDown: countdown.targetDate.map { $0 > now } ?? false))
                        // The countdown ticks from a TimelineView, not a live
                        // refresh, so it needs its own animation to roll.
                        .animation(reduceMotion ? nil : .snappy, value: countdownValue)
                        .lineLimit(1)
                        .minimumScaleFactor(0.44)
                }
                .layoutPriority(1)

                if !dynamicTypeSize.isAccessibilitySize {
                    Spacer(minLength: RTSpacing.small)
                }

                platformHero
            }

            Text(presentation.routeTitle)
                .font(.subheadline.weight(.semibold))
                // Wrap rather than truncate once the text is large enough
                // that shrinking can't fit a long route name.
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                .minimumScaleFactor(0.82)
        }
    }

    private var platformHero: some View {
        let value = compactPlatformValue
        let hasKnownPlatform = value != "-" && value.uppercased() != "TBC"
        let isExpected = hasKnownPlatform && !platform.confirmed
        let changedFrom = hasKnownPlatform ? platform.secondary : nil
        return VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: 0) {
            Text(platformLabel(changedFrom: changedFrom, isExpected: isExpected))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(changedFrom != nil ? Color.rightTrainAmber : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if changedFrom != nil {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.title3.weight(.bold))
                        .transition(.symbolEffect(.appear))
                        .accessibilityHidden(true)
                }
                Text(value)
                    .italic(isExpected)
                    .heroNumberFont(size: 56)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            .foregroundStyle(platformTint(hasKnownPlatform: hasKnownPlatform, changed: changedFrom != nil))
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func platformLabel(changedFrom: String?, isExpected: Bool) -> String {
        if let changedFrom {
            // "was 2" -> "Was platform 2"
            return "Was platform \(changedFrom.dropFirst("was ".count))"
        }
        return isExpected ? "Platform · exp" : "Platform"
    }

    private func platformTint(hasKnownPlatform: Bool, changed: Bool) -> AnyShapeStyle {
        if changed {
            return AnyShapeStyle(Color.rightTrainAmber)
        }
        if !hasKnownPlatform || isStale {
            return AnyShapeStyle(.secondary)
        }
        return AnyShapeStyle(surface.ink)
    }

    // MARK: - Time strip

    private var timeStrip: some View {
        let stacked = dynamicTypeSize.isAccessibilitySize
        let layout = stacked ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
        return layout {
            timeCell(label: "Dep", display: depDisplay)

            Divider()
                .padding(stacked ? .horizontal : .vertical, RTSpacing.compact)

            timeCell(label: "Arr", display: arrDisplay)
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(Color.rightTrainPaperCream, in: RoundedRectangle(cornerRadius: RTRadius.card, style: .continuous))
    }

    private func timeCell(label: String, display: JourneyTimeDisplay) -> some View {
        let primaryTime = display.currentText ?? display.scheduledText
        let scheduledTime: String? = display.currentText != nil ? display.scheduledText : nil

        return HStack(alignment: .firstTextBaseline, spacing: RTSpacing.small) {
            Text(label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            Text(primaryTime)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(display.isDelayed ? Color.rightTrainAmber : surface.ink)
                .lineLimit(1)

            if let scheduled = scheduledTime {
                Text(scheduled)
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .strikethrough(display.isDelayed, color: surface.faint)
                    .foregroundStyle(surface.dim)
                    .lineLimit(1)
            }
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

    private var heroFreshnessText: String {
        if freshnessText.hasPrefix("Updated") {
            return "Train data \(freshnessText.lowercased())"
        }
        if freshnessText == "Live data pending" {
            return "Train data pending"
        }
        return freshnessText
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
            heroFreshnessText,
            JourneyFormatting.platformStateText(primary: platform.primary, confirmed: platform.confirmed)
        ].joined(separator: ", ")
    }
}
