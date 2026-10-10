import SwiftUI

// A UK station sign, drawn as an object: a dark housing, a recessed black
// display with its unlit dot grid, and amber single-dot lettering that glows
// faintly. Signs are the only place in the app the dot-matrix face appears.
//
// Pinned carries two signs, as a station does: the platform indicator for
// the pinned train, and a concourse departures board for the other trains
// in the search. Journey detail has two as well: a platform indicator for
// the train and a calling points board. The Lock Screen Live Activity is a
// sign in itself. Search results and the rest of the app stay in the system face,
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

    /// "Calling at Stockport 10:25": the traveller's stop, in Darwin's
    /// short form, and when the train is expected there.
    static func callingAt(_ journey: JourneyResult) -> String {
        let arrival = JourneyFormatting.arrivalDisplay(journey)
        let station = JourneyFormatting.compactDestinationStationText(journey)
        return "Calling at \(station) \(arrival.currentText ?? arrival.scheduledText)"
    }

    /// The Plat column: the bare number, or "-" until one is known.
    static func platform(_ platform: PlatformValue) -> String {
        platform.number ?? "-"
    }

    /// The scrolling line under a sign's train, in the order a platform
    /// indicator runs it: a platform change and Darwin's own delay or
    /// cancellation reason first, since they're news, then the calling
    /// points with their times, who runs the train and how many coaches it
    /// has. The calling points and coaches come from the journey's detail,
    /// so they join once it has loaded. The traveller's own arrival has its
    /// "Calling at" line.
    static func message(_ journey: JourneyResult, platform: PlatformValue, detail: JourneyDetail? = nil) -> String {
        var sentences: [String] = []

        if let number = platform.number, let previous = platform.previousNumber {
            sentences.append("Now departing from platform \(number), not platform \(previous).")
        }

        let reason = JourneyFormatting.isCancelled(journey)
            ? nonEmpty(journey.cancellationReasonText)
            : nonEmpty(journey.lateReasonText)
        if let reason {
            sentences.append(reason.hasSuffix(".") ? reason : "\(reason).")
        }

        if let detail, let callingPoints = callingPoints(detail, after: journey.originTpl) {
            sentences.append(callingPoints)
        }

        let finalDestination = JourneyFormatting.finalDestinationText(journey)
        if let operatorName = nonEmpty(journey.operatorName) {
            let article = "AEIOU".contains(operatorName.prefix(1).uppercased()) ? "an" : "a"
            sentences.append("This is \(article) \(operatorName) service to \(finalDestination).")
        } else {
            sentences.append("This train is for \(finalDestination).")
        }

        if let detail, let count = detail.coachCount, count > 0 {
            let about = detail.coachCountApproximate == true ? "about " : ""
            sentences.append("This train is formed of \(about)\(count) \(count == 1 ? "coach" : "coaches").")
        }

        return sentences.joined(separator: "  ")
    }

    /// "Calling at: Stockport (10:02) and Manchester Piccadilly (10:12)."
    /// Every stop with a public time after the traveller boards, to the end
    /// of the run; nil when there are none, as for a train's last stop.
    static func callingPoints(_ detail: JourneyDetail, after originTPL: String) -> String? {
        let origin = JourneyFormatting.segmentStopRange(
            detail.stops,
            originTPL: originTPL,
            destinationTPL: nil
        ).origin
        let stops = detail.stops.dropFirst(origin + 1).compactMap { stop -> String? in
            guard let time = nonEmpty(stop.publicArrival) ?? nonEmpty(stop.publicDeparture) else {
                return nil
            }
            return "\(stop.name) (\(time.prefix(5)))"
        }
        guard let last = stops.last else {
            return nil
        }
        let list = stops.count == 1 ? last : stops.dropLast().joined(separator: ", ") + " and " + last
        return "Calling at: \(list)."
    }

    /// A calling point's Expected column: "On time", "Exp 10:31",
    /// "Dep 10:24" once it has gone, "No report" or "Cancelled".
    static func expected(_ stop: JourneyStop) -> String {
        if stop.realtime?.cancelled == true {
            return "Cancelled"
        }
        guard let timing = stop.timing else {
            return ""
        }
        switch timing.status {
        case "actual":
            let verb = timing.label == "Arrived" ? "Arr" : "Dep"
            return "\(verb) \(timing.current.prefix(5))"
        case "not_reported":
            return "No report"
        case "unknown":
            return ""
        default:
            return timing.delayed ? "Exp \(timing.current.prefix(5))" : "On time"
        }
    }

    /// A calling point's booked time: its departure, or its arrival at the
    /// end of the run.
    static func time(_ stop: JourneyStop) -> String {
        let time = nonEmpty(stop.timing?.scheduled) ?? nonEmpty(stop.publicDeparture) ?? nonEmpty(stop.publicArrival)
        return time.map { String($0.prefix(5)) } ?? "-"
    }

    /// Darwin's sixteen-character name, as boards print it.
    static func station(_ stop: JourneyStop) -> String {
        JourneyFormatting.compactStationDisplayName(
            shortName: stop.sixteenCharacterName,
            name: stop.name,
            fallback: stop.crs ?? stop.tpl
        )
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
    /// "Calling at Stockport 10:02", dim under the destination.
    var callingAt: String? = nil
    @ScaledMetric(relativeTo: .body) private var timeWidth = BoardColumnWidth.time

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            columns
            if let callingAt {
                Text(callingAt)
                    .foregroundStyle(DepartureBoardStyle.dimAmber)
                    .lineLimit(1)
                    .allowsTightening(true)
                    .padding(.leading, dynamicTypeSize.isAccessibilitySize ? 0 : timeWidth + 8)
            }
        }
    }

    @ViewBuilder
    private var columns: some View {
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

/// One train on a concourse departures board: Time, Destination, Plat,
/// Expected, then a dim "Calling at" line with the traveller's arrival.
struct ConcourseBoardRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var time: String
    var destination: String
    var platform: PlatformValue
    var expected: String
    /// The second line, as a board's "Calling at" line reads: the
    /// traveller's stop and expected arrival, "Calling at Stockport 10:25".
    var callingAt: String? = nil
    /// A leading pin for the train this search has pinned.
    var isPinned = false
    @ScaledMetric(relativeTo: .body) private var timeWidth = ConcourseColumnWidth.time
    @ScaledMetric(relativeTo: .body) private var platformWidth = ConcourseColumnWidth.platform
    @ScaledMetric(relativeTo: .body) private var expectedWidth = ConcourseColumnWidth.expected

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            columns
                // In the board's side padding, so the columns still line up
                // with the headings.
                .overlay(alignment: .leading) {
                    pin.offset(x: -12)
                }
            if let callingAt {
                Text(callingAt)
                    .foregroundStyle(DepartureBoardStyle.dimAmber)
                    .lineLimit(1)
                    .allowsTightening(true)
                    // Under the destination, as on a real board.
                    .padding(.leading, dynamicTypeSize.isAccessibilitySize ? 0 : timeWidth + 8)
            }
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

/// The dim headings over a concourse board's columns. A calling points
/// board heads its second column "Calling at".
struct ConcourseBoardHeader: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var timeWidth = ConcourseColumnWidth.time
    @ScaledMetric(relativeTo: .body) private var platformWidth = ConcourseColumnWidth.platform
    @ScaledMetric(relativeTo: .body) private var expectedWidth = ConcourseColumnWidth.expected
    private let placeTitle: String

    init(placeTitle: String = "Destination") {
        self.placeTitle = placeTitle
    }

    var body: some View {
        if !dynamicTypeSize.isAccessibilitySize {
            HStack(spacing: 8) {
                Text("Time")
                    .frame(width: timeWidth, alignment: .leading)
                Text(placeTitle)
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

// MARK: - Calling points board

/// One stop on a calling points board: Time, Station, Plat, Expected, in the
/// concourse board's columns. Stops the train has passed, and those outside
/// the traveller's journey, are unlit; a lit dot in the margin shows where
/// the train is, hollow while it's on its way to that stop. A note, such as
/// a change or a delay reason, runs dim underneath.
struct CallingPointBoardRow: View {
    enum Marker {
        case none
        /// The train is at this stop.
        case here
        /// The train is between the previous stop and this one.
        case approaching
    }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var timeWidth = ConcourseColumnWidth.time
    @ScaledMetric(relativeTo: .body) private var platformWidth = ConcourseColumnWidth.platform
    @ScaledMetric(relativeTo: .body) private var expectedWidth = ConcourseColumnWidth.expected
    private let time: String
    private let station: String
    private let platform: PlatformValue?
    private let expected: String
    private let note: String?
    private let isLit: Bool
    private let marker: Marker

    init(
        time: String,
        station: String,
        platform: PlatformValue?,
        expected: String,
        note: String? = nil,
        isLit: Bool,
        marker: Marker = .none
    ) {
        self.time = time
        self.station = station
        self.platform = platform
        self.expected = expected
        self.note = note
        self.isLit = isLit
        self.marker = marker
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            columns
                .overlay(alignment: .leading) {
                    markerDot.offset(x: -10)
                }
            if let note {
                Text(note)
                    .foregroundStyle(DepartureBoardStyle.dimAmber)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, dynamicTypeSize.isAccessibilitySize ? 0 : timeWidth + 8)
            }
        }
        .foregroundStyle(isLit ? DepartureBoardStyle.amber : DepartureBoardStyle.dimAmber)
    }

    @ViewBuilder
    private var columns: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(time)
                    stationText
                }
                HStack(spacing: 8) {
                    if let platform, platform.number != nil {
                        Text("Plat \(BoardText.platform(platform))")
                            .foregroundStyle(platformStyle(platform))
                    }
                    Spacer(minLength: 8)
                    Text(expected)
                }
            }
        } else {
            HStack(spacing: 8) {
                Text(time)
                    .frame(width: timeWidth, alignment: .leading)
                stationText
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(platform.flatMap(\.number) ?? "")
                    .foregroundStyle(platform.map(platformStyle) ?? DepartureBoardStyle.dimAmber)
                    .frame(width: platformWidth, alignment: .trailing)
                Text(expected)
                    .frame(width: expectedWidth, alignment: .trailing)
            }
            .lineLimit(1)
        }
    }

    private var stationText: some View {
        Text(station)
            .lineLimit(1)
            .allowsTightening(true)
    }

    @ViewBuilder
    private var markerDot: some View {
        switch marker {
        case .none:
            EmptyView()
        case .here:
            Circle()
                .fill(DepartureBoardStyle.amber)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
        case .approaching:
            Circle()
                .strokeBorder(DepartureBoardStyle.amber, lineWidth: 1.5)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
        }
    }

    private func platformStyle(_ platform: PlatformValue) -> Color {
        platform.state == .confirmed || platform.isChanged
            ? DepartureBoardStyle.amber
            : DepartureBoardStyle.dimAmber
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
