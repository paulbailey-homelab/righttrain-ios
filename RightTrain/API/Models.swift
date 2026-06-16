import Foundation

struct DeviceChallengeResponse: Decodable {
    var attemptId: String
    var challenge: String
    var expiresAt: Date
}

struct RegisterDeviceRequest: Encodable {
    var attemptId: String
    var keyId: String
    var attestationObject: String
}

struct AuthResponse: Decodable {
    var user: User
    var session: Session
}

struct ServiceStatus: Decodable, Equatable {
    var status: String
    var checkedAt: Date
    var components: [ServiceStatusComponent]
    var message: String
    var latestKafkaMessageAt: Date? = nil
    var kafkaMessageLagSeconds: Int? = nil
    var kafkaMessagesProcessedLast24h: Int? = nil
}

struct ServiceStatusComponent: Decodable, Equatable {
    var key: String
    var label: String
    var status: String
    var lastSeenAt: Date?
}

struct AppCapabilitiesResponse: Decodable, Equatable {
    var multiLegRoutingEnabled: Bool
}

struct Session: Codable {
    var id: String
    var accessToken: String?
    var tokenType: String
    var expiresAt: Date
    var createdAt: Date

    var isExpired: Bool {
        expiresAt <= Date()
    }
}

struct User: Codable, Identifiable {
    var id: String
    var displayName: String?
    var email: String?
    var emailVerified: Bool
    var isPrivateEmail: Bool
    var entitlements: UserEntitlements
    var stationDefaults: UserStationDefaults
    var createdAt: Date
    var updatedAt: Date
}

struct UserEntitlements: Codable {
    var tier: String
    var status: String
    var activeWindowLimit: Int
    var commuteRoutineLimit: Int
    var paidSubscription: PaidSubscriptionEntitlement? = nil
}

struct PaidSubscriptionEntitlement: Codable, Equatable {
    var state: String
    var productId: String
    var period: String
    var environment: String
    var expiresAt: Date?
    var willRenew: Bool
}

struct BillingProductsResponse: Decodable {
    var products: [BillingProduct]
    var entitlements: UserEntitlements
}

struct BillingProduct: Decodable, Identifiable, Equatable {
    var productId: String
    var tier: String
    var period: String

    var id: String { productId }
}

struct StoreKitSyncRequest: Encodable {
    var signedTransactions: [String]
}

struct UserStationDefaults: Codable, Equatable {
    var homeStationCrs: String?
    var workStationCrs: String?
}

struct UpdateStationDefaultsRequest: Encodable {
    var homeStationCrs: String?
    var workStationCrs: String?

    enum CodingKeys: String, CodingKey {
        case homeStationCrs
        case workStationCrs
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let homeStationCrs {
            try container.encode(homeStationCrs, forKey: .homeStationCrs)
        } else {
            try container.encodeNil(forKey: .homeStationCrs)
        }
        if let workStationCrs {
            try container.encode(workStationCrs, forKey: .workStationCrs)
        } else {
            try container.encodeNil(forKey: .workStationCrs)
        }
    }
}

struct StationSearchResponse: Decodable {
    var stations: [StationSuggestion]
}

struct NearbyStationSearchResponse: Decodable, Equatable {
    var stations: [StationSuggestion]
    var generatedAt: Date
    var sourceFreshness: StationMetadataFreshness
}

struct StationMetadataFreshness: Decodable, Equatable {
    var status: String
    var lastSuccessfulImportAt: Date?
    var unavailableReason: String?

    var isFresh: Bool {
        status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "fresh"
    }
}

struct StationSuggestion: Codable, Identifiable, Equatable {
    var crs: String
    var name: String
    var sixteenCharacterName: String? = nil
    var tpl: String
    var toc: String?
    var latitude: Double? = nil
    var longitude: Double? = nil
    var distanceMeters: Int? = nil
    var monitoringRadiusMeters: Int? = nil

    var id: String { crs }
    var displayName: String { name }
    var compactDisplayName: String { nonEmpty(sixteenCharacterName) ?? name }

    private func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

struct DirectWindowRecommendationResponse: Decodable {
    var topRecommendation: DirectWindowRecommendation?
    var recommendations: [DirectWindowRecommendation]
}

struct JourneyPlanResponse: Decodable {
    var topItinerary: ItineraryRecommendation?
    var itineraries: [ItineraryRecommendation]
    var timetableId: String?
    var generatedAt: String
}

struct ItineraryRecommendation: Codable, Identifiable {
    var rank: Int
    var recommended: Bool
    var stableKey: String
    var originCrs: String
    var destinationCrs: String
    var scheduledDeparture: String
    var scheduledArrival: String
    var expectedDeparture: String
    var expectedArrival: String
    var statusText: String?
    var compactStatusText: String?
    var statusKind: String?
    var delayMinutes: Int?
    var legs: [ItineraryLeg]
    var connections: [ItineraryConnection]
    var score: ItineraryScore
    var candidateServiceKeys: [ItineraryServiceKey]

    var id: String {
        if !stableKey.isEmpty {
            return stableKey
        }
        let services = legs.map { "\($0.serviceId)-\($0.legIndex)" }.joined(separator: "|")
        return "\(rank)-\(services)"
    }

    init(
        rank: Int,
        recommended: Bool,
        stableKey: String,
        originCrs: String,
        destinationCrs: String,
        scheduledDeparture: String,
        scheduledArrival: String,
        expectedDeparture: String,
        expectedArrival: String,
        legs: [ItineraryLeg],
        connections: [ItineraryConnection],
        score: ItineraryScore,
        candidateServiceKeys: [ItineraryServiceKey],
        statusText: String? = nil,
        compactStatusText: String? = nil,
        statusKind: String? = nil,
        delayMinutes: Int? = nil
    ) {
        self.rank = rank
        self.recommended = recommended
        self.stableKey = stableKey
        self.originCrs = originCrs
        self.destinationCrs = destinationCrs
        self.scheduledDeparture = scheduledDeparture
        self.scheduledArrival = scheduledArrival
        self.expectedDeparture = expectedDeparture
        self.expectedArrival = expectedArrival
        self.statusText = statusText
        self.compactStatusText = compactStatusText
        self.statusKind = statusKind
        self.delayMinutes = delayMinutes
        self.legs = legs
        self.connections = connections
        self.score = score
        self.candidateServiceKeys = candidateServiceKeys
    }

    enum CodingKeys: String, CodingKey {
        case rank
        case recommended
        case stableKey
        case originCrs
        case destinationCrs
        case scheduledDeparture
        case scheduledArrival
        case expectedDeparture
        case expectedArrival
        case statusText
        case compactStatusText
        case statusKind
        case delayMinutes
        case legs
        case connections
        case score
        case candidateServiceKeys
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rank = try container.decode(Int.self, forKey: .rank)
        recommended = try container.decode(Bool.self, forKey: .recommended)
        stableKey = try container.decode(String.self, forKey: .stableKey)
        originCrs = try container.decode(String.self, forKey: .originCrs)
        destinationCrs = try container.decode(String.self, forKey: .destinationCrs)
        scheduledDeparture = try container.decode(String.self, forKey: .scheduledDeparture)
        scheduledArrival = try container.decode(String.self, forKey: .scheduledArrival)
        expectedDeparture = try container.decode(String.self, forKey: .expectedDeparture)
        expectedArrival = try container.decode(String.self, forKey: .expectedArrival)
        statusText = try container.decodeIfPresent(String.self, forKey: .statusText)
        compactStatusText = try container.decodeIfPresent(String.self, forKey: .compactStatusText)
        statusKind = try container.decodeIfPresent(String.self, forKey: .statusKind)
        delayMinutes = try container.decodeIfPresent(Int.self, forKey: .delayMinutes)
        legs = try container.decodeIfPresent([ItineraryLeg].self, forKey: .legs) ?? []
        connections = try container.decodeIfPresent([ItineraryConnection].self, forKey: .connections) ?? []
        score = try container.decode(ItineraryScore.self, forKey: .score)
        candidateServiceKeys = try container.decodeIfPresent([ItineraryServiceKey].self, forKey: .candidateServiceKeys) ?? []
    }
}

struct DirectWindowRecommendation: Codable, Identifiable {
    var rank: Int
    var recommended: Bool
    var journey: JourneyResult
    var score: DirectWindowRecommendationScore

    var id: String { "\(journey.serviceId)-\(rank)" }
}

struct DirectWindowRecommendationScore: Codable {
    var scoreMinutes: Int
    var expectedArrival: String
    var reliableArrival: String
    var delayMinutes: Int
    var penaltyMinutes: Int
    var cancellationPenaltyMinutes: Int?
    var severeDelayPenaltyMinutes: Int?
    var staleDataPenaltyMinutes: Int?
    var lowConfidencePenaltyMinutes: Int?
    var usable: Bool
    var reasons: [String]?
}

struct ItineraryLeg: Codable, Identifiable {
    var legIndex: Int
    var serviceId: Int
    var rid: String
    var ssd: String
    var uid: String?
    var toc: String?
    var operatorName: String?
    var operatorShortName: String? = nil
    var status: String
    var displayStatus: String
    var statusText: String? = nil
    var compactStatusText: String? = nil
    var statusKind: String? = nil
    var movementPhase: String? = nil
    var reportState: String? = nil
    var delayMinutes: Int? = nil
    var realtimeSource: String?
    var realtimeUpdatedAt: String?
    var lateReasonCode: String?
    var lateReasonText: String?
    var lateReasonLocationTpl: String?
    var lateReasonLocationName: String?
    var cancellationReasonCode: String?
    var cancellationReasonText: String?
    var cancellationReasonLocationTpl: String?
    var cancellationReasonLocationName: String?
    var originTpl: String
    var originCrs: String
    var originName: String
    var originSixteenCharacterName: String? = nil
    var destinationTpl: String
    var destinationCrs: String
    var destinationName: String
    var destinationSixteenCharacterName: String? = nil
    var finalDestinationTpl: String? = nil
    var finalDestinationCrs: String? = nil
    var finalDestinationName: String? = nil
    var finalDestinationSixteenCharacterName: String? = nil
    var originLatitude: Double? = nil
    var originLongitude: Double? = nil
    var destinationLatitude: Double? = nil
    var destinationLongitude: Double? = nil
    var monitoringRadiusMeters: Int? = nil
    var scheduledDeparture: String
    var scheduledArrival: String
    var scheduledDepartureRaw: String?
    var scheduledArrivalRaw: String?
    var windowMembership: String? = nil
    var departureSignageText: String? = nil
    var originPlatform: String?
    var destinationPlatform: String?
    var expectedDeparture: String?
    var expectedArrival: String?
    var expectedDepartureAt: String?
    var expectedArrivalAt: String?
    var realtimePlatform: String?
    var realtimePlatformConfirmed: Bool
    var cancelled: Bool
    var deactivated: Bool
    var originRealtime: StopRealtime?
    var destinationRealtime: StopRealtime?

    var id: String { "\(legIndex)-\(rid)-\(ssd)" }

    var journeyResult: JourneyResult {
        JourneyResult(
            serviceId: serviceId,
            rid: rid,
            ssd: ssd,
            uid: uid,
            toc: toc,
            operatorName: operatorName,
            operatorShortName: operatorShortName,
            status: status,
            displayStatus: displayStatus,
            statusText: statusText,
            compactStatusText: compactStatusText,
            statusKind: statusKind,
            movementPhase: movementPhase,
            reportState: reportState,
            delayMinutes: delayMinutes,
            realtimeSource: realtimeSource,
            realtimeUpdatedAt: realtimeUpdatedAt,
            lateReasonCode: lateReasonCode,
            lateReasonText: lateReasonText,
            lateReasonLocationTpl: lateReasonLocationTpl,
            lateReasonLocationName: lateReasonLocationName,
            cancellationReasonCode: cancellationReasonCode,
            cancellationReasonText: cancellationReasonText,
            cancellationReasonLocationTpl: cancellationReasonLocationTpl,
            cancellationReasonLocationName: cancellationReasonLocationName,
            originTpl: originTpl,
            originCrs: originCrs,
            originName: originName,
            originSixteenCharacterName: originSixteenCharacterName,
            destinationTpl: destinationTpl,
            destinationCrs: destinationCrs,
            destinationName: destinationName,
            destinationSixteenCharacterName: destinationSixteenCharacterName,
            finalDestinationTpl: finalDestinationTpl,
            finalDestinationCrs: finalDestinationCrs,
            finalDestinationName: finalDestinationName,
            finalDestinationSixteenCharacterName: finalDestinationSixteenCharacterName,
            originLatitude: originLatitude,
            originLongitude: originLongitude,
            destinationLatitude: destinationLatitude,
            destinationLongitude: destinationLongitude,
            monitoringRadiusMeters: monitoringRadiusMeters,
            scheduledDeparture: scheduledDeparture,
            scheduledArrival: scheduledArrival,
            scheduledDepartureRaw: scheduledDepartureRaw,
            scheduledArrivalRaw: scheduledArrivalRaw,
            windowMembership: windowMembership,
            departureSignageText: departureSignageText,
            originPlatform: originPlatform,
            destinationPlatform: destinationPlatform,
            expectedDeparture: expectedDeparture,
            expectedArrival: expectedArrival,
            realtimePlatform: realtimePlatform,
            realtimePlatformConfirmed: realtimePlatformConfirmed,
            cancelled: cancelled,
            deactivated: deactivated,
            originRealtime: originRealtime,
            destinationRealtime: destinationRealtime
        )
    }
}

struct ItineraryConnection: Codable, Identifiable {
    var fromLegIndex: Int
    var toLegIndex: Int
    var atTpl: String
    var atCrs: String
    var atName: String
    var atSixteenCharacterName: String? = nil
    var atLatitude: Double? = nil
    var atLongitude: Double? = nil
    var atMonitoringRadiusMeters: Int? = nil
    var scheduledArrival: String
    var scheduledDeparture: String
    var expectedArrival: String
    var expectedDeparture: String
    var requiredTransferMinutes: Int
    var scheduledMarginMinutes: Int
    var expectedMarginMinutes: Int
    var risk: ConnectionRisk
    var transferSource: String? = nil
    var transferMode: String? = nil
    var transferAdvice: String? = nil
    var transferLinesOfRoute: [String]? = nil

    var id: String { "\(fromLegIndex)-\(toLegIndex)-\(atTpl)" }
}

struct ConnectionRisk: Codable {
    var status: String
    var reasons: [String]?
}

struct ItineraryScore: Codable {
    var scoreMinutes: Int
    var expectedArrival: String
    var reliableArrival: String
    var delayMinutes: Int
    var penaltyMinutes: Int
    var changeCount: Int
    var minimumConnectionMarginMinutes: Int
    var transferRiskPenaltyMinutes: Int?
    var disruptionPenaltyMinutes: Int?
    var usable: Bool
    var reasons: [String]?
}

struct ItineraryServiceKey: Codable, Hashable {
    var serviceId: Int?
    var rid: String
    var ssd: String
}

struct JourneyResult: Codable, Identifiable {
    var serviceId: Int
    var rid: String
    var ssd: String
    var uid: String?
    var toc: String?
    var operatorName: String?
    var operatorShortName: String? = nil
    var status: String
    var displayStatus: String
    var statusText: String? = nil
    var compactStatusText: String? = nil
    var statusKind: String? = nil
    var movementPhase: String? = nil
    var reportState: String? = nil
    var delayMinutes: Int? = nil
    var realtimeSource: String?
    var realtimeUpdatedAt: String?
    var lateReasonCode: String?
    var lateReasonText: String?
    var lateReasonLocationTpl: String?
    var lateReasonLocationName: String?
    var cancellationReasonCode: String?
    var cancellationReasonText: String?
    var cancellationReasonLocationTpl: String?
    var cancellationReasonLocationName: String?
    var originTpl: String
    var originCrs: String
    var originName: String
    var originSixteenCharacterName: String? = nil
    var destinationTpl: String
    var destinationCrs: String
    var destinationName: String
    var destinationSixteenCharacterName: String? = nil
    var finalDestinationTpl: String? = nil
    var finalDestinationCrs: String? = nil
    var finalDestinationName: String? = nil
    var finalDestinationSixteenCharacterName: String? = nil
    var originLatitude: Double? = nil
    var originLongitude: Double? = nil
    var destinationLatitude: Double? = nil
    var destinationLongitude: Double? = nil
    var monitoringRadiusMeters: Int? = nil
    var scheduledDeparture: String
    var scheduledArrival: String
    var scheduledDepartureRaw: String?
    var scheduledArrivalRaw: String?
    var windowMembership: String? = nil
    var departureSignageText: String? = nil
    var originPlatform: String?
    var destinationPlatform: String?
    var expectedDeparture: String?
    var expectedArrival: String?
    var realtimePlatform: String?
    var realtimePlatformConfirmed: Bool
    var cancelled: Bool
    var deactivated: Bool
    var originRealtime: StopRealtime?
    var destinationRealtime: StopRealtime?

    var id: Int { serviceId }
}

struct JourneyDetail: Codable, Hashable, Identifiable {
    var serviceId: Int
    var rid: String
    var ssd: String
    var uid: String?
    var toc: String?
    var operatorName: String?
    var operatorShortName: String? = nil
    var status: String
    var displayStatus: String
    var statusText: String? = nil
    var compactStatusText: String? = nil
    var statusKind: String? = nil
    var movementPhase: String? = nil
    var reportState: String? = nil
    var delayMinutes: Int? = nil
    var realtimeSource: String?
    var lateReasonCode: String?
    var lateReasonText: String?
    var lateReasonLocationTpl: String?
    var lateReasonLocationName: String?
    var cancellationReasonCode: String?
    var cancellationReasonText: String?
    var cancellationReasonLocationTpl: String?
    var cancellationReasonLocationName: String?
    var originTpl: String
    var originCrs: String
    var originName: String
    var originSixteenCharacterName: String? = nil
    var destinationTpl: String
    var destinationCrs: String
    var destinationName: String
    var destinationSixteenCharacterName: String? = nil
    var cancelled: Bool
    var deactivated: Bool
    var coachCount: Int?
    var coachCountApproximate: Bool?
    var trainPosition: JourneyTrainPosition?
    var stops: [JourneyStop]

    var id: Int { serviceId }
}

struct JourneyStop: Codable, Hashable, Identifiable {
    var stopIndex: Int
    var stopType: String
    var tpl: String
    var crs: String?
    var name: String
    var sixteenCharacterName: String? = nil
    var publicArrival: String?
    var publicDeparture: String?
    var scheduledPlatform: String?
    var activities: String?
    var timing: JourneyStopTiming?
    var realtime: StopRealtime?

    var id: String { "\(stopIndex)-\(tpl)" }
}

struct JourneyTrainPosition: Codable, Hashable {
    var stationIndex: Int?
    var betweenAfterIndex: Int?
    var progress: Double
}

struct JourneyStopTiming: Codable, Hashable {
    var label: String
    var scheduled: String?
    var current: String
    var delayed: Bool
    var status: String
}

struct StopRealtime: Codable, Hashable {
    @available(*, deprecated, message: "Use expectedArrival or expectedDeparture. Kept as departure for non-final stops and arrival at the final stop.")
    var expectedTime: String?
    @available(*, deprecated, message: "Use actualArrival or actualDeparture. Kept as departure for non-final stops and arrival at the final stop.")
    var actualTime: String?
    var expectedArrival: String?
    var expectedDeparture: String?
    var actualArrival: String?
    var actualDeparture: String?
    var delayed: Bool?
    var source: String?
    var sourceInstance: String?
    var estimateMinutes: String?
    var reasonCode: String?
    var reasonText: String?
    var reasonLocationTpl: String?
    var reasonLocationName: String?
    var platform: String?
    var platformConfirmed: Bool?
    var platformSource: String?
    var platformCisSupplement: Bool?
    var platformSupplement: Bool?
    var cancelled: Bool?
}

struct CreateWindowSubscriptionRequest: Encodable {
    var originCrs: String
    var destinationCrs: String
    var originTpl: String? = nil
    var destinationTpl: String? = nil
    var departureStart: Date
    var windowMinutes: Int
    var selectedTrainServiceId: Int? = nil
}

struct CreateItinerarySubscriptionRequest: Encodable {
    var originCrs: String
    var destinationCrs: String
    var departureStart: Date
    var windowMinutes: Int
    var maxChanges: Int?
    var limit: Int?
    var selectedItineraryStableKey: String? = nil
}

struct CreateJourneyShareRequest: Encodable, Equatable {
    var windowSubscriptionId: String? = nil
    var itinerarySubscriptionId: String? = nil
}

struct JourneyShareResponse: Decodable, Equatable {
    var shareId: String
    var shareUrl: String
    var appUrl: String
    var expiresAt: Date
}

struct PublicJourneyShare: Codable, Identifiable, Equatable {
    var shareId: String
    var kind: String
    var routeTitle: String
    var status: String
    var statusText: String
    var originName: String
    var originCrs: String
    var destinationName: String
    var destinationCrs: String
    var scheduledDeparture: Date
    var scheduledArrival: Date
    var expectedDeparture: Date? = nil
    var expectedArrival: Date? = nil
    var currentPosition: JourneySharePosition? = nil
    var legs: [JourneyShareLeg]? = nil
    var disruptions: [String]? = nil
    var refreshedAt: Date
    var expiresAt: Date
    var appUrl: String
    var appStoreUrl: String? = nil

    var id: String { shareId }
}

struct JourneySharePosition: Codable, Equatable {
    var description: String
    var progress: Double
    var currentStopName: String? = nil
    var upcomingStopName: String? = nil
}

struct JourneyShareLeg: Codable, Identifiable, Equatable {
    var legIndex: Int
    var originName: String
    var originCrs: String
    var destinationName: String
    var destinationCrs: String
    var status: String
    var statusText: String
    var scheduledDeparture: Date
    var scheduledArrival: Date
    var expectedDeparture: Date? = nil
    var expectedArrival: Date? = nil

    var id: Int { legIndex }
}

struct CommuteRoutine: Codable, Identifiable, Equatable {
    var id: String
    var userId: String
    var name: String
    var status: String
    var originCrs: String
    var destinationCrs: String
    var departureTime: String
    var windowMinutes: Int
    var activeWeekdays: [Int]
    var autoArmEnabled: Bool
    var autoArmLeadMinutes: Int
    var notificationsEnabled: Bool
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    var isPaused: Bool {
        status == "paused"
    }
}

struct CommuteRoutineMutationRequest: Encodable {
    var name: String
    var status: String?
    var originCrs: String
    var destinationCrs: String
    var departureTime: String
    var windowMinutes: Int
    var activeWeekdays: [Int]
    var autoArmEnabled: Bool
    var autoArmLeadMinutes: Int
    var notificationsEnabled: Bool
}

struct RegisterLiveActivityTokenRequest: Encodable {
    var token: String
    var environment: String
    var activityId: String
    var activityKind: String? = nil
    var tokenRole: String?
    var pinnedTrainServiceId: Int?
    var frequentLiveActivityUpdatesEnabled: Bool? = nil
    var clientDeviceId: String
    var appBundleId: String?
    var appVersion: String?
    var buildNumber: String?
    var deviceModel: String?
    var osVersion: String?
}

struct RegisterAPNsAlertTokenRequest: Encodable {
    var token: String
    var environment: String
    var clientDeviceId: String
    var appBundleId: String?
    var appVersion: String?
    var buildNumber: String?
    var deviceModel: String?
    var osVersion: String?
}

struct PinWindowSubscriptionTrainRequest: Codable {
    var serviceId: Int
}

struct PinItineraryFirstLegRequest: Codable, Equatable {
    var serviceId: Int
    var rid: String
    var ssd: String
}

struct ReportItineraryInterchangeArrivalRequest: Codable {
    var atCrs: String
    var legIndex: Int
}

struct BoardItineraryLegRequest: Codable {
    var legIndex: Int
    var pinFirstLeg: Bool? = nil
}

struct ReplanItineraryFromRequest: Codable {
    var fromCrs: String
}

struct APNsTokenRegistration: Decodable {
    var id: String
}

struct SubscriptionStreamEvent: Equatable {
    var id: String?
    var event: String?
    var envelope: SubscriptionStreamEnvelope?
}

struct SubscriptionStreamEnvelope: Decodable, Equatable {
    var stream: String
    var notification: SubscriptionStreamNotification
}

struct SubscriptionStreamNotification: Decodable, Equatable {
    var id: String
    var subscriptionId: String?
    var windowSubscriptionId: String?
    var itinerarySubscriptionId: String?
    var eventType: String
    var deliveryClass: String
    var createdAt: String
}

struct ItinerarySubscription: Codable, Identifiable {
    var id: String
    var userId: String
    var status: String
    var phase: String = "planning"
    var currentLegIndex: Int = 0
    var phaseUpdatedAt: String? = nil
    var originCrs: String
    var destinationCrs: String
    var departureStart: String
    var windowMinutes: Int
    var maxChanges: Int
    var limit: Int
    var notificationsEnabled: Bool
    var pinnedFirstLeg: ItineraryPinnedFirstLeg? = nil
    var selectedItinerary: ItineraryRecommendation
    var itineraries: [ItineraryRecommendation]
    var createdAt: String
    var deletedAt: String?
}

extension ItinerarySubscription {
    var resolvedPhase: ItineraryPhase {
        ItineraryPhase.from(rawValue: phase)
    }

    var currentLeg: ItineraryLeg? {
        let legs = selectedItinerary.legs
        guard currentLegIndex >= 0, currentLegIndex < legs.count else { return nil }
        return legs[currentLegIndex]
    }

    var nextConnection: ItineraryConnection? {
        selectedItinerary.connections.first(where: { $0.fromLegIndex == currentLegIndex })
    }

    var onwardLeg: ItineraryLeg? {
        let legs = selectedItinerary.legs
        let nextIndex = currentLegIndex + 1
        guard nextIndex >= 0, nextIndex < legs.count else { return nil }
        return legs[nextIndex]
    }
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
}

struct ItineraryPinnedFirstLeg: Codable, Equatable {
    var serviceId: Int
    var rid: String
    var ssd: String
    var originTpl: String?
    var originCrs: String?
    var originName: String?
    var originSixteenCharacterName: String? = nil
    var destinationTpl: String?
    var destinationCrs: String?
    var destinationName: String?
    var destinationSixteenCharacterName: String? = nil
    var scheduledDeparture: String?
    var scheduledArrival: String?
    var expectedDeparture: String?
    var expectedArrival: String?
}

struct WindowSubscription: Codable, Identifiable {
    var id: String
    var userId: String
    var status: String
    var phase: String? = nil
    var originCrs: String
    var destinationCrs: String
    var departureStart: String
    var windowMinutes: Int
    var selectedTrainServiceId: Int?
    var pinnedTrainServiceId: Int?
    var sourceRoutineId: String?
    var notificationsEnabled: Bool
    var selectedRecommendation: DirectWindowRecommendation
    var recommendations: [DirectWindowRecommendation]
    var entitlement: WindowSubscriptionEntitlementState
    var createdAt: String
    var deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userId
        case status
        case phase
        case originCrs
        case destinationCrs
        case departureStart
        case windowMinutes
        case selectedTrainServiceId
        case pinnedTrainServiceId
        case sourceRoutineId
        case notificationsEnabled
        case selectedRecommendation
        case recommendations
        case entitlement
        case createdAt
        case deletedAt
    }

    init(
        id: String,
        userId: String,
        status: String,
        phase: String? = nil,
        originCrs: String,
        destinationCrs: String,
        departureStart: String,
        windowMinutes: Int,
        selectedTrainServiceId: Int? = nil,
        selectedRecommendation: DirectWindowRecommendation,
        recommendations: [DirectWindowRecommendation],
        pinnedTrainServiceId: Int? = nil,
        sourceRoutineId: String? = nil,
        notificationsEnabled: Bool = true,
        entitlement: WindowSubscriptionEntitlementState,
        createdAt: String,
        deletedAt: String?
    ) {
        self.id = id
        self.userId = userId
        self.status = status
        self.phase = phase
        self.originCrs = originCrs
        self.destinationCrs = destinationCrs
        self.departureStart = departureStart
        self.windowMinutes = windowMinutes
        self.selectedTrainServiceId = selectedTrainServiceId
        self.pinnedTrainServiceId = pinnedTrainServiceId
        self.sourceRoutineId = sourceRoutineId
        self.notificationsEnabled = notificationsEnabled
        self.selectedRecommendation = selectedRecommendation
        self.recommendations = recommendations
        self.entitlement = entitlement
        self.createdAt = createdAt
        self.deletedAt = deletedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        userId = try container.decode(String.self, forKey: .userId)
        status = try container.decode(String.self, forKey: .status)
        phase = try container.decodeIfPresent(String.self, forKey: .phase)
        originCrs = try container.decode(String.self, forKey: .originCrs)
        destinationCrs = try container.decode(String.self, forKey: .destinationCrs)
        departureStart = try container.decode(String.self, forKey: .departureStart)
        windowMinutes = try container.decode(Int.self, forKey: .windowMinutes)
        selectedTrainServiceId = try container.decodeIfPresent(Int.self, forKey: .selectedTrainServiceId)
        pinnedTrainServiceId = try container.decodeIfPresent(Int.self, forKey: .pinnedTrainServiceId)
        sourceRoutineId = try container.decodeIfPresent(String.self, forKey: .sourceRoutineId)
        notificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? true
        selectedRecommendation = try container.decode(DirectWindowRecommendation.self, forKey: .selectedRecommendation)
        recommendations = try container.decodeIfPresent([DirectWindowRecommendation].self, forKey: .recommendations) ?? [selectedRecommendation]
        entitlement = try container.decode(WindowSubscriptionEntitlementState.self, forKey: .entitlement)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        deletedAt = try container.decodeIfPresent(String.self, forKey: .deletedAt)
    }
}

struct WindowSubscriptionNotificationDetail: Codable, Hashable, Identifiable {
    var id: String
    var windowSubscriptionId: String
    var eventType: String
    var deliveryClass: String
    var payload: WindowNotificationPayload
    var createdAt: String

    static func == (lhs: WindowSubscriptionNotificationDetail, rhs: WindowSubscriptionNotificationDetail) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct WindowNotificationPayload: Codable {
    var type: String
    var occurredAt: String
    var data: WindowNotificationData
}

struct WindowNotificationData: Codable {
    var reasons: [String]?
    var topRecommendation: DirectWindowRecommendation?
    var previousRecommendation: DirectWindowRecommendation?
    var affectedRecommendation: DirectWindowRecommendation?
    var departedRecommendation: DirectWindowRecommendation?
    var nextRecommendation: DirectWindowRecommendation?
    var platform: String?
    var previousPlatform: String?
    var delayBand: String?
    var boundary: String?
    var scheduledDeparture: String?
    var scheduledDepartureTime: String?
    var expectedDeparture: String?
    var expectedDepartureAt: String?
    var windowStart: String?
    var windowEnd: String?
    var departedTrainServiceId: Int?
    var nextRecommendationServiceId: Int?
}

struct WindowSubscriptionEntitlementState: Codable {
    var tier: String
    var status: String
    var activeWindowLimit: Int
    var activeWindowCount: Int
}

struct ErrorResponse: Decodable {
    var error: String
    var code: String?
    var details: [String: LossyStringValue]?

    var stringDetails: [String: String] {
        details?.mapValues(\.value) ?? [:]
    }
}

struct LossyStringValue: Decodable {
    var value: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = String(int)
        } else if let bool = try? container.decode(Bool.self) {
            value = String(bool)
        } else {
            value = ""
        }
    }
}
