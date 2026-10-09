import SwiftUI

// A UK station sign, drawn as an object: a dark housing, a recessed black
// display with its unlit dot grid, and amber single-dot lettering that glows
// faintly. Signs are the only place in the app the dot-matrix face appears.
//
// Pinned carries two signs, as a station does: the platform indicator for
// the pinned train, and a concourse departures board for the other trains
// in the search. The Lock Screen Live Activity is a sign in itself. Search
// results, journey detail and the rest of the app stay in the system face,
// so a sign sits on the page like a photo of a real one rather than as a
// second typeface. Signs keep amber on black in light and dark mode: they're
// a physical object, not a themed surface. Status is in words ("Exp 08:36",
// "Cancelled"), as on a real board, not in colour.

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
        .compositingGroup()
        .shadow(color: DepartureBoardStyle.glow, radius: 2.5)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { display }
        .padding(SignMetrics.bezel)
        .background { housing }
        .shadow(color: .black.opacity(0.22), radius: 8, y: 4)
        // Past AX2 a sign line can't hold even a time and a destination.
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    /// The black face, recessed into the housing, with its unlit pixels.
    private var display: some View {
        let shape = RoundedRectangle(cornerRadius: SignMetrics.displayRadius, style: .continuous)
        return shape
            .fill(DepartureBoardStyle.background)
            .overlay { SignDotGrid().clipShape(shape) }
            .overlay { shape.strokeBorder(.black.opacity(0.8), lineWidth: 1) }
    }

    /// The dark metal case, lit from above.
    private var housing: some View {
        let shape = RoundedRectangle(cornerRadius: SignMetrics.housingRadius, style: .continuous)
        return shape
            .fill(LinearGradient(
                colors: [Color(white: 0.22), Color(white: 0.12)],
                startPoint: .top,
                endPoint: .bottom
            ))
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.2), .white.opacity(0.03)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
            }
    }
}

private enum SignMetrics {
    /// The case showing around the display.
    static let bezel: CGFloat = 7
    static let housingRadius: CGFloat = 16
    static let displayRadius: CGFloat = housingRadius - bezel
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

// MARK: - Train line

/// Column widths for a sign's train line. The view scales them with its own
/// @ScaledMetric.
private enum BoardColumnWidth {
    static let time: CGFloat = 44
}

/// The train line at the top of a platform indicator: Time, Destination,
/// Expected. The platform has its own double-height line below it.
struct DepartureBoardRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var time: String
    var destination: String
    var expected: String
    @ScaledMetric(relativeTo: .body) private var timeWidth = BoardColumnWidth.time

    @ViewBuilder
    var body: some View {
        // At accessibility sizes the three columns don't fit, so Expected
        // moves to a second line.
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(time)
                    destinationText
                }
                Text(expected)
            }
        } else {
            HStack(spacing: 8) {
                Text(time)
                    .frame(width: timeWidth, alignment: .leading)
                destinationText
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(expected)
                    .fixedSize()
            }
            .lineLimit(1)
        }
    }

    private var destinationText: some View {
        Text(destination)
            .lineLimit(1)
            .allowsTightening(true)
    }
}

// MARK: - Concourse board

/// Column widths a concourse board's headings and rows share, so they line
/// up. Each view scales them with its own @ScaledMetric.
private enum ConcourseColumnWidth {
    static let time: CGFloat = 44
    static let platform: CGFloat = 30
    static let expected: CGFloat = 76
}

/// One line of a concourse departures board: Time, Destination, Plat,
/// Expected.
struct ConcourseBoardRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var time: String
    var destination: String
    var platform: PlatformValue
    var expected: String
    /// A leading pin for the train this search has pinned.
    var isPinned = false
    @ScaledMetric(relativeTo: .body) private var timeWidth = ConcourseColumnWidth.time
    @ScaledMetric(relativeTo: .body) private var platformWidth = ConcourseColumnWidth.platform
    @ScaledMetric(relativeTo: .body) private var expectedWidth = ConcourseColumnWidth.expected

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

/// The dim headings over a concourse board's columns.
struct ConcourseBoardHeader: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var timeWidth = ConcourseColumnWidth.time
    @ScaledMetric(relativeTo: .body) private var platformWidth = ConcourseColumnWidth.platform
    @ScaledMetric(relativeTo: .body) private var expectedWidth = ConcourseColumnWidth.expected

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
