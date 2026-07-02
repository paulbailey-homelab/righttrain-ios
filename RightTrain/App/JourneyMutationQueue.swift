import Foundation

enum JourneyMutationKind: String, Codable {
    case windowPinTrain
    case windowClearPinnedTrain
    case windowDelete
    case itineraryPinFirstLeg
    case itineraryClearPinnedFirstLeg
    case itineraryReportOriginArrival
    case itineraryReportInterchangeArrival
    case itineraryBoardLeg
    case itineraryReplanFromCurrentStation
    case itineraryDelete
}

enum JourneyMutationStatus: String, Codable {
    case pending
    case failed
}

struct JourneyMutation: Codable, Identifiable, Equatable {
    var id: String
    var kind: JourneyMutationKind
    var status: JourneyMutationStatus
    var createdAt: Date
    var attempts: Int
    var lastAttemptAt: Date?
    var lastError: String?
    var windowID: String?
    var itineraryID: String?
    var serviceID: Int?
    var legIndex: Int?
    var atCrs: String?
    var fromCrs: String?
    var pinFirstLeg: Bool?
    var firstLegPin: PinItineraryFirstLegRequest?

    init(
        id: String = UUID().uuidString,
        kind: JourneyMutationKind,
        windowID: String? = nil,
        itineraryID: String? = nil,
        serviceID: Int? = nil,
        legIndex: Int? = nil,
        atCrs: String? = nil,
        fromCrs: String? = nil,
        pinFirstLeg: Bool? = nil,
        firstLegPin: PinItineraryFirstLegRequest? = nil
    ) {
        self.id = id
        self.kind = kind
        self.status = .pending
        self.createdAt = Date()
        self.attempts = 0
        self.windowID = windowID
        self.itineraryID = itineraryID
        self.serviceID = serviceID
        self.legIndex = legIndex
        self.atCrs = atCrs
        self.fromCrs = fromCrs
        self.pinFirstLeg = pinFirstLeg
        self.firstLegPin = firstLegPin
    }
}

@MainActor
@Observable
final class JourneyMutationQueue {
    private(set) var mutations: [JourneyMutation] = []
    private(set) var isSyncing = false
    private static let storageKey = "righttrain.ios.journeyMutationQueue"
    static let maxMutationAge: TimeInterval = 24 * 60 * 60
    /// After this age expired-and-surfaced mutations are removed outright so
    /// the queue can't grow without bound.
    static let hardPurgeAge: TimeInterval = 2 * maxMutationAge
    /// Sentinel `lastError` marking a mutation that aged out before it could
    /// sync. Kept distinct from server-rejection messages so the UI can offer
    /// retry only where a retry makes sense.
    static let expiredErrorMessage = "expired before syncing"

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let encoder = JSONEncoder()
    @ObservationIgnored private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
        purgeExpired()
    }

    var pendingCount: Int {
        mutations.filter { $0.status == .pending }.count
    }

    var failedCount: Int {
        mutations.filter { $0.status == .failed }.count
    }

    var hasPendingWork: Bool {
        pendingCount > 0
    }

    var needsAttention: Bool {
        failedCount > 0
    }

    func hasPendingDelete(windowID: String) -> Bool {
        mutations.contains { mutation in
            mutation.status == .pending &&
                mutation.kind == .windowDelete &&
                mutation.windowID == windowID
        }
    }

    func hasPendingDelete(itineraryID: String) -> Bool {
        mutations.contains { mutation in
            mutation.status == .pending &&
                mutation.kind == .itineraryDelete &&
                mutation.itineraryID == itineraryID
        }
    }

    var pendingMutations: [JourneyMutation] {
        mutations.filter { $0.status == .pending }.sorted { $0.createdAt < $1.createdAt }
    }

    func duePendingMutations(now: Date = Date()) -> [JourneyMutation] {
        pendingMutations.filter { mutation in
            guard let lastAttemptAt = mutation.lastAttemptAt else {
                return true
            }
            return now.timeIntervalSince(lastAttemptAt) >= retryDelay(for: mutation)
        }
    }

    func enqueue(_ mutation: JourneyMutation) {
        mutations.append(mutation)
        save()
    }

    func remove(id: String) {
        mutations.removeAll { $0.id == id }
        save()
    }

    func markAttempt(id: String) {
        guard let index = mutations.firstIndex(where: { $0.id == id }) else {
            return
        }
        mutations[index].attempts += 1
        mutations[index].lastAttemptAt = Date()
        mutations[index].lastError = nil
        save()
    }

    func markFailed(id: String, message: String) {
        guard let index = mutations.firstIndex(where: { $0.id == id }) else {
            return
        }
        mutations[index].status = .failed
        mutations[index].lastError = message
        mutations[index].lastAttemptAt = Date()
        save()
    }

    func markDeferred(id: String, message: String) {
        guard let index = mutations.firstIndex(where: { $0.id == id }) else {
            return
        }
        mutations[index].status = .pending
        mutations[index].lastError = message
        mutations[index].lastAttemptAt = Date()
        save()
    }

    func clearFailed() {
        guard mutations.contains(where: { $0.status == .failed }) else {
            return
        }
        mutations.removeAll { $0.status == .failed }
        save()
    }

    /// Ages the queue: mutations older than `maxMutationAge` become visible
    /// failures (instead of vanishing silently), and ones past `hardPurgeAge`
    /// are removed so the queue stays bounded.
    func purgeExpired(now: Date = Date()) {
        var changed = false
        var newlyExpired = 0

        mutations.removeAll { mutation in
            guard now.timeIntervalSince(mutation.createdAt) > Self.hardPurgeAge else {
                return false
            }
            changed = true
            return true
        }

        for index in mutations.indices where now.timeIntervalSince(mutations[index].createdAt) > Self.maxMutationAge {
            guard mutations[index].status != .failed || mutations[index].lastError != Self.expiredErrorMessage else {
                continue
            }
            mutations[index].status = .failed
            mutations[index].lastError = Self.expiredErrorMessage
            changed = true
            newlyExpired += 1
        }

        guard changed else {
            return
        }
        save()
        if newlyExpired > 0 {
            BetaDiagnostics.record(
                "journey_mutations_expired",
                details: "count=\(newlyExpired)",
                severity: .warning
            )
        }
    }

    /// Failed mutations that a retry could still plausibly apply — everything
    /// failed except the ones that aged out.
    var retryableFailedCount: Int {
        mutations.filter { $0.status == .failed && $0.lastError != Self.expiredErrorMessage }.count
    }

    /// Returns retryable failed mutations to pending so the next flush
    /// re-attempts them. Expired failures stay failed; they are dismiss-only.
    func retryFailed() {
        var changed = false
        for index in mutations.indices where mutations[index].status == .failed && mutations[index].lastError != Self.expiredErrorMessage {
            mutations[index].status = .pending
            mutations[index].lastError = nil
            changed = true
        }
        guard changed else {
            return
        }
        save()
    }

    func clear() {
        mutations = []
        defaults.removeObject(forKey: Self.storageKey)
    }

    func setSyncing(_ syncing: Bool) {
        isSyncing = syncing
    }

    private func load() {
        guard let data = defaults.data(forKey: Self.storageKey),
              let decoded = try? decoder.decode([JourneyMutation].self, from: data) else {
            mutations = []
            return
        }
        mutations = decoded
    }

    private func save() {
        guard let data = try? encoder.encode(mutations) else {
            return
        }
        defaults.set(data, forKey: Self.storageKey)
    }

    func retryDelay(for mutation: JourneyMutation) -> TimeInterval {
        guard mutation.attempts > 0 else {
            return 0
        }
        let exponent = min(mutation.attempts - 1, 7)
        let base = min(pow(2, Double(exponent)) * 5, 300)
        // ±20% jitter spreads retries across devices so a backend recovery
        // doesn't get a synchronized thundering herd. Derived from the mutation
        // identity (not Bool.random) so duePendingMutations() sees a stable due
        // time on every call within an attempt.
        let jitter = 0.8 + 0.4 * Self.jitterFraction(id: mutation.id, attempts: mutation.attempts)
        return base * jitter
    }

    /// Deterministic value in [0, 1] from an FNV-1a hash of the mutation
    /// identity and attempt count. Stable across processes, unlike hashValue.
    private static func jitterFraction(id: String, attempts: Int) -> Double {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in "\(id):\(attempts)".utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return Double(hash % 1000) / 999
    }
}
