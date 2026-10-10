import Foundation

struct JourneyDetailIdentity: Hashable {
    var serviceID: Int
    var originTPL: String?
    var destinationTPL: String?

    init(serviceID: Int, originTPL: String? = nil, destinationTPL: String? = nil) {
        self.serviceID = serviceID
        self.originTPL = Self.normalized(originTPL)
        self.destinationTPL = Self.normalized(destinationTPL)
    }

    init(detail: JourneyDetail) {
        self.init(
            serviceID: detail.serviceId,
            originTPL: detail.originTpl,
            destinationTPL: detail.destinationTpl
        )
    }

    private static func normalized(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

enum JourneyLiveRefreshSignature {
    static func journey(_ journey: JourneyResult) -> String {
        [
            journey.status,
            journey.displayStatus,
            journey.statusText,
            journey.compactStatusText,
            journey.statusKind,
            journey.movementPhase,
            journey.reportState,
            journey.delayMinutes.map(String.init),
            journey.realtimeUpdatedAt,
            journey.lateReasonText,
            journey.cancellationReasonText,
            journey.expectedDeparture,
            journey.expectedArrival,
            journey.realtimePlatform,
            realtime(journey.originRealtime),
            realtime(journey.destinationRealtime)
        ]
        .map { $0 ?? "" }
        .joined(separator: "|")
    }

    static func leg(_ leg: ItineraryLeg) -> String {
        [
            leg.status,
            leg.displayStatus,
            leg.statusText,
            leg.compactStatusText,
            leg.statusKind,
            leg.movementPhase,
            leg.reportState,
            leg.delayMinutes.map(String.init),
            leg.realtimeUpdatedAt,
            leg.lateReasonText,
            leg.cancellationReasonText,
            leg.expectedDeparture,
            leg.expectedArrival,
            leg.realtimePlatform,
            realtime(leg.originRealtime),
            realtime(leg.destinationRealtime)
        ]
        .map { $0 ?? "" }
        .joined(separator: "|")
    }

    private static func realtime(_ realtime: StopRealtime?) -> String {
        [
            realtime?.expectedArrival,
            realtime?.expectedDeparture,
            realtime?.actualArrival,
            realtime?.actualDeparture,
            realtime?.platform,
            realtime?.reasonText,
            realtime?.reasonLocationName,
            realtime?.cancelled.map { $0 ? "true" : "false" }
        ]
        .map { $0 ?? "" }
        .joined(separator: "~")
    }
}

@MainActor
@Observable
final class JourneyDetailViewModel {
    private(set) var selectedJourneyDetail: JourneyDetail?
    private(set) var selectedJourneyDetails: [JourneyDetailIdentity: JourneyDetail] = [:]

    @ObservationIgnored private let apiClient: any APIClienting
    @ObservationIgnored private let operationState: AppOperationState
    @ObservationIgnored private var loadGenerationByIdentity: [JourneyDetailIdentity: Int] = [:]
    @ObservationIgnored private var signDetails: [JourneyDetailIdentity: JourneyDetail] = [:]

    init(
        apiClient: any APIClienting,
        operationState: AppOperationState
    ) {
        self.apiClient = apiClient
        self.operationState = operationState
    }

    @discardableResult
    func loadJourneyDetail(
        serviceID: Int,
        originTPL: String? = nil,
        destinationTPL: String? = nil,
        showLoading: Bool = true
    ) async -> JourneyDetail? {
        let requestIdentity = JourneyDetailIdentity(
            serviceID: serviceID,
            originTPL: originTPL,
            destinationTPL: destinationTPL
        )
        let generation = (loadGenerationByIdentity[requestIdentity] ?? 0) + 1
        loadGenerationByIdentity[requestIdentity] = generation
        var loaded: JourneyDetail?
        let operation = { [self] in
            let detail = try await apiClient.getJourneyDetail(
                serviceID: serviceID,
                originTPL: originTPL,
                destinationTPL: destinationTPL
            )
            guard loadGenerationByIdentity[requestIdentity] == generation else {
                return
            }
            selectedJourneyDetails[requestIdentity] = detail
            selectedJourneyDetails[JourneyDetailIdentity(detail: detail)] = detail
            selectedJourneyDetail = detail
            loaded = detail
            operationState.alertState = nil
        }

        if showLoading {
            await operationState.withLoading(operation)
        } else {
            try? await operation()
        }
        return loaded
    }

    /// A journey's detail for a sign's scrolling message (calling points,
    /// coach count), fetched quietly: no loading state, no alert, and the
    /// detail screen's selection is left alone. Kept per journey for the
    /// session, since neither changes often enough to refetch on each tick.
    func signDetail(serviceID: Int, originTPL: String, destinationTPL: String) async -> JourneyDetail? {
        let identity = JourneyDetailIdentity(
            serviceID: serviceID,
            originTPL: originTPL,
            destinationTPL: destinationTPL
        )
        if let cached = signDetails[identity] {
            return cached
        }
        guard let detail = try? await apiClient.getJourneyDetail(
            serviceID: serviceID,
            originTPL: originTPL,
            destinationTPL: destinationTPL
        ) else {
            return nil
        }
        signDetails[identity] = detail
        return detail
    }

    func detail(for identity: JourneyDetailIdentity) -> JourneyDetail? {
        selectedJourneyDetails[identity]
    }

    func dismiss() {
        selectedJourneyDetail = nil
        selectedJourneyDetails = [:]
        loadGenerationByIdentity = [:]
    }
}
