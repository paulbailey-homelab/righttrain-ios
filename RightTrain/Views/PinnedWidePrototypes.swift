#if DEBUG
import SwiftUI

// Divergent directions for the Pinned tab on iPhone Duo's inner display
// (669 × 951 pt, 951 × 669 in landscape). Prototype scaffolding only: pick
// one, fold it into ActiveTabView, then delete this file. Each variant is a
// named #Preview, and `--righttrain-prototype=<variant>` shows it on device
// inside a landscape inner-display frame for side-by-side screenshots.

enum PinnedWidePrototype: String, CaseIterable, Identifiable {
    /// Today's layout in the readable column. The baseline to beat.
    case column
    /// Hero on the left, the rest of the search on the right.
    case board
    /// Pinned journey on the left, its calling points on the right.
    case stops
    /// One wide departure-board strip over a two-column train grid.
    case departures

    var id: String { rawValue }

    var title: String {
        switch self {
        case .column: "Column"
        case .board: "Board"
        case .stops: "Stops Beside"
        case .departures: "Departure Board"
        }
    }

    init?(arguments: [String]) {
        guard let raw = arguments
            .first(where: { $0.hasPrefix("--righttrain-prototype=") })?
            .split(separator: "=", maxSplits: 1).last else {
            return nil
        }
        self.init(rawValue: String(raw))
    }

    /// The fixture each direction is judged on: a Search Pin shows the most
    /// content; Stops Beside needs a pinned train to have stops.
    var window: WindowSubscription {
        self == .stops ? PreviewFixtures.journeyPinnedWindow : Self.busySearch
    }

    /// A lived-in evening peak search: enough alternatives to fill a wide
    /// screen, with the delays and a cancellation a real board has.
    static var busySearch: WindowSubscription {
        typealias F = PreviewFixtures
        let trains = [
            F.recommendation(serviceID: 9101, departureOffset: 12, arrivalOffset: 95, rank: 1),
            F.recommendation(serviceID: 9102, departureOffset: 20, arrivalOffset: 108, rank: 2, delayMinutes: 3),
            F.recommendation(serviceID: 9103, departureOffset: 32, arrivalOffset: 115, rank: 3),
            F.recommendation(serviceID: 9104, departureOffset: 42, arrivalOffset: 130, rank: 4, delayMinutes: 22),
            F.recommendation(serviceID: 9105, departureOffset: 52, arrivalOffset: 135, rank: 5, cancelled: true),
            F.recommendation(serviceID: 9106, departureOffset: 72, arrivalOffset: 155, rank: 6),
            F.recommendation(serviceID: 9107, departureOffset: 92, arrivalOffset: 175, rank: 7, delayMinutes: 8),
            F.recommendation(serviceID: 9108, departureOffset: 112, arrivalOffset: 195, rank: 8),
            F.recommendation(serviceID: 9109, departureOffset: 132, arrivalOffset: 215, rank: 9),
        ]
        var window = F.activeWindow
        window.windowMinutes = 180
        window.selectedRecommendation = trains[0]
        window.recommendations = trains
        return window
    }
}

struct PinnedWidePrototypeView: View {
    var prototype: PinnedWidePrototype
    var window: WindowSubscription

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let presentation = ActiveWindowPresentation(window: window, now: context.date)
            switch prototype {
            case .column:
                ScrollView {
                    ActiveWindowView(window: window, loadDetail: { _ in })
                        .padding(.horizontal, RTSpacing.pageHorizontal)
                        .padding(.vertical, RTSpacing.pageVertical)
                }
                .readableContentMargins()
            case .board:
                BoardPrototype(presentation: presentation, now: context.date)
            case .stops:
                StopsBesidePrototype(window: window, presentation: presentation, now: context.date)
            case .departures:
                DepartureBoardPrototype(presentation: presentation, now: context.date)
            }
        }
        .background(Color.rightTrainSurfaceCream.ignoresSafeArea())
    }
}

// MARK: - Shared pieces

private struct PrototypeHero: View {
    var presentation: ActiveWindowPresentation
    var now: Date

    var body: some View {
        let surface = presentation.heroSurface
        let glance = ActiveWindowPresentation.liveGlanceContent(
            for: presentation.heroRecommendation,
            routeTitle: presentation.routeTitle,
            needProfile: .oneOffDirectTrip,
            now: now,
            isOffline: false
        )
        VStack(alignment: .leading, spacing: RTSpacing.small) {
            HStack {
                RTStatusPill(
                    statusText: presentation.heroIsPinnedTrain ? "On time · live" : "Watching this search",
                    surface: surface
                )
                Spacer(minLength: RTSpacing.small)
                LiveFreshnessText(text: glance.freshnessText)
            }
            StatusFirstHeroBlock(
                presentation: presentation,
                countdown: ActiveWindowPresentation.countdown(for: presentation.heroRecommendation, now: now),
                surface: surface,
                now: now,
                freshnessText: glance.freshnessText,
                loadDetail: {},
                requestUnpin: {}
            )
        }
    }
}

private struct PrototypeTrainList: View {
    var presentation: ActiveWindowPresentation
    var now: Date
    var columns = 1

    var body: some View {
        let trains = presentation.futureDepartures(now: now) + presentation.cancelledDepartures(now: now)
        VStack(alignment: .leading, spacing: RTSpacing.small) {
            Text("Other trains in this search")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, RTSpacing.cardPadding)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: RTSpacing.compact), count: columns),
                spacing: columns > 1 ? RTSpacing.compact : 0
            ) {
                ForEach(trains) { recommendation in
                    StatusFirstTrainRow(
                        recommendation: recommendation,
                        surface: presentation.heroSurface,
                        isPinned: false,
                        now: now,
                        loadDetail: {},
                        togglePinned: {}
                    )
                    .padding(.horizontal, RTSpacing.cardPadding)
                    .background(columns > 1 ? Color.rightTrainPaperCream : .clear, in: .rect(cornerRadius: RTRadius.card))
                }
            }
            .background(columns > 1 ? .clear : Color.rightTrainPaperCream, in: .rect(cornerRadius: RTRadius.card))
        }
    }
}

// MARK: - Board

/// The hero never scrolls away: the countdown and platform stay put while
/// the list of alternatives scrolls beside them.
private struct BoardPrototype: View {
    var presentation: ActiveWindowPresentation
    var now: Date

    var body: some View {
        HStack(alignment: .top, spacing: RTSpacing.sectionGap) {
            PrototypeHero(presentation: presentation, now: now)
                .frame(maxWidth: 400)

            ScrollView {
                PrototypeTrainList(presentation: presentation, now: now)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, RTSpacing.sectionGap)
        .padding(.vertical, RTSpacing.pageVertical)
    }
}

// MARK: - Stops beside

/// Journey detail without navigating: what to do now on the left, where the
/// train is on the right.
private struct StopsBesidePrototype: View {
    var window: WindowSubscription
    var presentation: ActiveWindowPresentation
    var now: Date

    var body: some View {
        let journey = presentation.heroRecommendation.journey
        HStack(alignment: .top, spacing: 0) {
            ScrollView {
                ActiveWindowView(window: window, loadDetail: { _ in })
                    .padding(RTSpacing.sectionGap)
            }
            .frame(maxWidth: 420)

            Divider()

            JourneyDetailView(identity: JourneyDetailIdentity(
                serviceID: journey.serviceId,
                originTPL: journey.originTpl,
                destinationTPL: journey.destinationTpl
            ))
        }
    }
}

// MARK: - Departure board

/// Reads like a station board: every number that matters on one line, then
/// the alternatives in two columns so more fit above the fold.
private struct DepartureBoardPrototype: View {
    var presentation: ActiveWindowPresentation
    var now: Date

    var body: some View {
        let recommendation = presentation.heroRecommendation
        let countdown = ActiveWindowPresentation.countdown(for: recommendation, now: now)
        let platform = ActiveWindowPresentation.platformDisplay(for: recommendation.journey)
        ScrollView {
            VStack(alignment: .leading, spacing: RTSpacing.sectionGap) {
                VStack(alignment: .leading, spacing: RTSpacing.small) {
                    Text(presentation.routeTitle)
                        .font(.headline)
                    HStack(alignment: .lastTextBaseline, spacing: RTSpacing.sectionGap) {
                        boardCell("Leaves in", countdown.text.replacingOccurrences(of: "Leaves in ", with: ""), prominent: true)
                        boardCell("Platform", platform.primary.replacingOccurrences(of: "P", with: ""), prominent: true)
                        boardCell("Departs", JourneyFormatting.departureText(recommendation.journey))
                        boardCell("Arrives", JourneyFormatting.arrivalText(recommendation.journey))
                        Spacer(minLength: 0)
                    }
                }
                .padding(RTSpacing.cardPadding)
                .background(Color.rightTrainPaperCream, in: .rect(cornerRadius: RTRadius.card))

                PrototypeTrainList(presentation: presentation, now: now, columns: 2)
            }
            .padding(.horizontal, RTSpacing.sectionGap)
            .padding(.vertical, RTSpacing.pageVertical)
        }
    }

    private func boardCell(_ label: String, _ value: String, prominent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Group {
                if prominent {
                    Text(value).heroNumberFont(size: 48)
                } else {
                    Text(value).font(.title.weight(.semibold))
                }
            }
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        }
    }
}

// MARK: - On-device gallery

/// Frames a variant at iPhone Duo's landscape inner-display size so it can
/// be screenshotted on a larger simulator.
struct PinnedWidePrototypeFrame: View {
    var prototype: PinnedWidePrototype

    var body: some View {
        VStack(spacing: RTSpacing.compact) {
            Text("\(prototype.title) · iPhone Duo inner display, landscape")
                .font(.headline)
            PinnedWidePrototypeView(prototype: prototype, window: prototype.window)
                .frame(width: 951, height: 669)
                .background(Color.rightTrainSurfaceCream)
                .clipShape(.rect(cornerRadius: 28))
                .overlay {
                    RoundedRectangle(cornerRadius: 28)
                        .stroke(Color.rightTrainInkFaint, lineWidth: 2)
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
    }
}

#Preview("Column", traits: .fixedLayout(width: 951, height: 669)) {
    PreviewAppContainer {
        PinnedWidePrototypeView(prototype: .column, window: PinnedWidePrototype.column.window)
    }
}

#Preview("Board", traits: .fixedLayout(width: 951, height: 669)) {
    PreviewAppContainer {
        PinnedWidePrototypeView(prototype: .board, window: PinnedWidePrototype.board.window)
    }
}

#Preview("Stops Beside", traits: .fixedLayout(width: 951, height: 669)) {
    PreviewAppContainer {
        PinnedWidePrototypeView(prototype: .stops, window: PinnedWidePrototype.stops.window)
    }
}

#Preview("Departure Board", traits: .fixedLayout(width: 951, height: 669)) {
    PreviewAppContainer {
        PinnedWidePrototypeView(prototype: .departures, window: PinnedWidePrototype.departures.window)
    }
}
#endif
