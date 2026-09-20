import ActivityKit
import Foundation

struct RightTrainLiveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        struct PinnedFirstLeg: Codable, Hashable {
            var serviceID: Int
            var rid: String?
            var ssd: String?
            var originName: String?
            var originShortName: String? = nil
            var destinationName: String?
            var destinationShortName: String? = nil
            var scheduledDepartureTime: String?
            var departureTime: String?
            var scheduledDepartureDate: Date? = nil
            var departureDate: Date? = nil
            var scheduledArrivalTime: String?
            var arrivalTime: String?
            var scheduledArrivalDate: Date? = nil
            var arrivalDate: Date? = nil
        }

        struct Train: Codable, Hashable, Identifiable {
            var id: Int { serviceID }

            var serviceID: Int
            var operatorName: String?
            var operatorCode: String?
            var destinationName: String
            var destinationShortName: String? = nil
            var serviceDestinationName: String? = nil
            var serviceDestinationShortName: String? = nil
            var scheduledDepartureTime: String
            var departureTime: String
            var scheduledDepartureDate: Date? = nil
            var departureDate: Date? = nil
            var departureDelayed: Bool
            var scheduledArrivalTime: String
            var arrivalTime: String
            var scheduledArrivalDate: Date? = nil
            var arrivalDate: Date? = nil
            var arrivalDelayed: Bool
            var departurePlatform: String
            var arrivalPlatform: String
            var departed: Bool
            var recommended: Bool
            var statusText: String
            var statusKind: StatusKind
            var delayMinutes: Int
            var journeyProgress: Double?
        }

        /// Snapshot of the next interchange the user has yet to make.
        /// Populated for the `on_leg` / `approaching_interchange` phases
        /// so the Live Activity can render the change-over without a
        /// follow-up fetch.
        struct Interchange: Codable, Hashable {
            var crs: String
            var name: String
            var legIndex: Int
            var scheduledArrivalDate: Date?
            var expectedArrivalDate: Date?
            var scheduledDepartureDate: Date?
            var expectedDepartureDate: Date?
            var requiredTransferMinutes: Int
            var expectedMarginMinutes: Int
            var riskStatus: String
            var onwardPlatform: String?
            var onwardPlatformConfirmed: Bool
            var transferTitle: String? = nil
        }

        struct PlatformChange: Codable, Hashable {
            var serviceID: Int
            var previousPlatform: String
            var currentPlatform: String
            var changedAtText: String
        }

        var windowSubscriptionID: String? = nil
        var itinerarySubscriptionID: String? = nil
        var phase: String? = nil
        var recommendationServiceID: Int
        var routeTitle: String
        var originName: String
        var originShortName: String? = nil
        var destinationName: String
        var destinationShortName: String? = nil
        var originCrs: String
        var destinationCrs: String
        var departureTime: String
        var scheduledDepartureDate: Date? = nil
        var departureDate: Date? = nil
        var arrivalTime: String
        var scheduledArrivalDate: Date? = nil
        var arrivalDate: Date? = nil
        var platform: String
        var platformConfirmed: Bool
        var statusText: String
        var statusKind: StatusKind
        var delayMinutes: Int
        var nextUpdateText: String
        var updatedAtText: String
        var emptyStateText: String?
        var windowTimeRangeText: String?
        var windowTrainCount: Int?
        var upcomingTrainCount: Int?
        var departedTrainCount: Int?
        var cancelledTrainCount: Int?
        var otherDeparturesText: String?
        var platformChange: PlatformChange? = nil
        var trains: [Train]
        var pinnedTrainServiceID: Int? = nil
        var pinnedFirstLeg: PinnedFirstLeg? = nil
        var currentLegIndex: Int? = nil
        var onwardLeg: Train? = nil
        var interchange: Interchange? = nil
    }

    enum ActivityKind: String, Codable, Hashable {
        case window
        case train
        case itinerary
        case leg
    }

    enum StatusKind: String, Codable, Hashable {
        case good
        case delayed
        case cancelled
        case arrived
        case departed
        case missed
        case atRisk = "at_risk"
        case unreported
        case notReported = "not_reported"
        case unknown
    }

    var windowSubscriptionID: String? = nil
    var itinerarySubscriptionID: String? = nil
    var activityKind: ActivityKind
    var pinnedTrainServiceID: Int? = nil
    var originCrs: String
    var destinationCrs: String
    var startedAtText: String
}

/// Canonical lifecycle for an active multi-leg journey. Mirrors the
/// `itinerary_subscriptions.phase` enum on the backend; the legacy
/// strings "window" and "pinned_first_leg" are tolerated on read.
enum ItineraryPhase: String, Codable, Equatable {
    case planning
    case atOrigin = "at_origin"
    case onLeg = "on_leg"
    case approachingInterchange = "approaching_interchange"
    case onFinalLeg = "on_final_leg"

    static func from(rawValue: String?) -> ItineraryPhase {
        guard let value = rawValue?.trimmingCharacters(in: .whitespaces), !value.isEmpty else {
            return .planning
        }
        switch value {
        case "window":
            return .planning
        case "pinned_first_leg":
            return .atOrigin
        default:
            return ItineraryPhase(rawValue: value) ?? .planning
        }
    }

    var isOnboard: Bool {
        self == .onLeg || self == .approachingInterchange || self == .onFinalLeg
    }
}
