import SwiftUI

// A UK station departure board: single-dot amber lettering on black, the
// columns of a concourse board (Time, Destination, Plat, Expected), Darwin's
// sixteen-character station names, a scrolling message line and the
// seconds clock along the bottom.
//
// Everything inside a board is in the board face and everything outside it
// stays in the system face, so the two never share a line. Boards keep their
// amber-on-black in light and dark mode: they're a physical object, not a
// themed surface. Status is in words ("Exp 08:36", "Cancelled"), as on a
// real board, not in colour.

enum DepartureBoardStyle {
    /// The amber of LED platform indicators.
    static let amber = Color(red: 1.0, green: 0.69, blue: 0.0)
    /// Column headings, expected platforms and stale values.
    static let dimAmber = amber.opacity(0.55)
    static let background = Color(red: 0.035, green: 0.035, blue: 0.03)
}

struct DepartureBoard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            content
        }
        .font(BoardFont.font(.body))
        .foregroundStyle(DepartureBoardStyle.amber)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            DepartureBoardStyle.background,
            in: RoundedRectangle(cornerRadius: RTRadius.chip, style: .continuous)
        )
        // Past AX2 a board line can't hold even a time and a destination.
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }
}

// MARK: - Board copy

/// The wording and abbreviations a board uses.
enum BoardText {
    /// Where the train ends up, in Darwin's sixteen-character form
    /// ("Manchester Picc"), as boards show it even when the traveller gets
    /// off sooner.
    static func destination(_ journey: JourneyResult) -> String {
        JourneyFormatting.compactFinalDestinationText(journey)
    }

    /// The Expected column: "On time", "Exp 08:36", "Delayed", "Cancelled"
    /// or "Departed".
    static func expected(_ journey: JourneyResult) -> String {
        if JourneyFormatting.isCancelled(journey) {
            return "Cancelled"
        }
        if JourneyFormatting.isDeparted(journey) {
            return "Departed"
        }
        let departure = JourneyFormatting.departureDisplay(journey)
        if let current = departure.currentText, current != departure.scheduledText {
            return "Exp \(current)"
        }
        if JourneyFormatting.displayStatus(journey) == "delayed" {
            return "Delayed"
        }
        return "On time"
    }

    /// The Plat column: the bare number, or "-" until one is known.
    static func platform(_ platform: PlatformValue) -> String {
        platform.number ?? "-"
    }

    /// The scrolling line under a board's first train: who runs it, where
    /// the traveller gets off, a platform change and Darwin's own delay or
    /// cancellation reason, which already reads as a sentence.
    static func message(_ journey: JourneyResult, platform: PlatformValue) -> String {
        var sentences: [String] = []
        let finalDestination = JourneyFormatting.finalDestinationText(journey)
        if let operatorName = nonEmpty(journey.operatorName) {
            let article = "AEIOU".contains(operatorName.prefix(1).uppercased()) ? "an" : "a"
            sentences.append("This is \(article) \(operatorName) service to \(finalDestination).")
        } else {
            sentences.append("This train is for \(finalDestination).")
        }

        let arrival = JourneyFormatting.arrivalDisplay(journey)
        let arrivalTime = arrival.currentText ?? arrival.scheduledText
        sentences.append("Arrives \(JourneyFormatting.destinationStationText(journey)) \(arrivalTime).")

        if let number = platform.number, let previous = platform.previousNumber {
            sentences.append("Now departing from platform \(number), not platform \(previous).")
        }

        let reason = JourneyFormatting.isCancelled(journey)
            ? nonEmpty(journey.cancellationReasonText)
            : nonEmpty(journey.lateReasonText)
        if let reason {
            sentences.append(reason.hasSuffix(".") ? reason : "\(reason).")
        }
        return sentences.joined(separator: "  ")
    }

    /// Boards have no middle dot or arrows; swap them for what the face has.
    static func boardSafe(_ text: String) -> String {
        text
            .replacingOccurrences(of: " · ", with: " - ")
            .replacingOccurrences(of: "·", with: "-")
            .replacingOccurrences(of: "→", with: "to")
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }
}

// MARK: - Rows

/// Column widths every row on a board shares, so headings, rows and the
/// first train line up. Each view scales them with its own @ScaledMetric.
private enum BoardColumnWidth {
    static let time: CGFloat = 44
    static let platform: CGFloat = 30
    static let expected: CGFloat = 76
}

/// One departure: Time, Destination, Plat, Expected.
struct DepartureBoardRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var time: String
    var destination: String
    var platform: PlatformValue
    var expected: String
    /// A leading pin for the train this search has pinned.
    var isPinned = false
    @ScaledMetric(relativeTo: .body) private var timeWidth = BoardColumnWidth.time
    @ScaledMetric(relativeTo: .body) private var platformWidth = BoardColumnWidth.platform
    @ScaledMetric(relativeTo: .body) private var expectedWidth = BoardColumnWidth.expected

    var body: some View {
        columns
            // In the board's side padding, so the columns still line up
            // with the headings.
            .overlay(alignment: .leading) {
                pin.offset(x: -12)
            }
    }

    @ViewBuilder
    private var columns: some View {
        // At accessibility sizes the four columns don't fit, so the platform
        // and Expected move to a second line.
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(time)
                    destinationText
                }
                HStack(spacing: 8) {
                    Text("Plat \(BoardText.platform(platform))")
                        .foregroundStyle(platformStyle)
                    Spacer(minLength: 8)
                    Text(expected)
                }
            }
        } else {
            HStack(spacing: 8) {
                Text(time)
                    .frame(width: timeWidth, alignment: .leading)
                destinationText
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(BoardText.platform(platform))
                    .foregroundStyle(platformStyle)
                    .frame(width: platformWidth, alignment: .trailing)
                Text(expected)
                    .frame(width: expectedWidth, alignment: .trailing)
            }
            .lineLimit(1)
        }
    }

    @ViewBuilder
    private var pin: some View {
        if isPinned {
            Image(systemName: "pin.fill")
                .font(.system(size: 9, weight: .bold))
                .accessibilityHidden(true)
        }
    }

    private var destinationText: some View {
        Text(destination)
            .lineLimit(1)
            .allowsTightening(true)
    }

    /// An expected platform is dim until it's confirmed; a changed one is
    /// full brightness, since it's confirmed news.
    private var platformStyle: Color {
        platform.state == .confirmed || platform.isChanged
            ? DepartureBoardStyle.amber
            : DepartureBoardStyle.dimAmber
    }
}

/// The dim headings over a board's columns.
struct DepartureBoardHeader: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var timeWidth = BoardColumnWidth.time
    @ScaledMetric(relativeTo: .body) private var platformWidth = BoardColumnWidth.platform
    @ScaledMetric(relativeTo: .body) private var expectedWidth = BoardColumnWidth.expected

    var body: some View {
        if !dynamicTypeSize.isAccessibilitySize {
            HStack(spacing: 8) {
                Text("Time")
                    .frame(width: timeWidth, alignment: .leading)
                Text("Destination")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Plat")
                    .frame(width: platformWidth, alignment: .trailing)
                Text("Expected")
                    .frame(width: expectedWidth, alignment: .trailing)
            }
            .lineLimit(1)
            .foregroundStyle(DepartureBoardStyle.dimAmber)
            .accessibilityHidden(true)
        }
    }
}

// MARK: - Scroller

/// A message line that scrolls in from the right and off to the left, as on
/// a platform indicator, when it's too long to fit. With Reduce Motion on it
/// wraps instead.
struct BoardScroller: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var text: String
    /// Points per second.
    var speed: CGFloat = 40

    @State private var containerWidth: CGFloat = 0
    @State private var textWidth: CGFloat = 0
    @State private var start = Date()

    var body: some View {
        if reduceMotion {
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            // A one-line placeholder sets the height; the moving copy is an
            // overlay so its full width never pushes the board wider.
            Text(verbatim: " ")
                .frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.width
                } action: { width in
                    containerWidth = width
                }
                .overlay(alignment: .leading) {
                    if textWidth > containerWidth, containerWidth > 0 {
                        TimelineView(.animation) { context in
                            movingText.offset(x: offset(at: context.date))
                        }
                    } else {
                        movingText
                    }
                }
                .clipped()
                .onChange(of: text) {
                    start = Date()
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(text)
        }
    }

    private var movingText: some View {
        Text(text)
            .lineLimit(1)
            .fixedSize()
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { width in
                textWidth = width
            }
    }

    /// Starts just off the right edge and runs until the end has left the
    /// left edge, then repeats.
    private func offset(at date: Date) -> CGFloat {
        let travel = containerWidth + textWidth
        guard travel > 0 else { return 0 }
        let distance = CGFloat(date.timeIntervalSince(start)) * speed
        return containerWidth - distance.truncatingRemainder(dividingBy: travel)
    }
}

// MARK: - Clock

/// The seconds clock along the bottom of a board, in UK time.
struct BoardClock: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(Self.formatter.string(from: context.date))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Europe/London")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
