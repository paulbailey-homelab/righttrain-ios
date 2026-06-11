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

    func purgeExpired(now: Date = Date()) {
        let expired = mutations.filter { now.timeIntervalSince($0.createdAt) > Self.maxMutationAge }
        guard !expired.isEmpty else {
            return
        }
        mutations.removeAll { mutation in
            expired.contains { $0.id == mutation.id }
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

    private func retryDelay(for mutation: JourneyMutation) -> TimeInterval {
        guard mutation.attempts > 0 else {
            return 0
        }
        let exponent = min(mutation.attempts - 1, 7)
        return min(pow(2, Double(exponent)) * 5, 300)
    }
}
