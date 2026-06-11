import Foundation

struct CachedActiveJourneyState: Codable {
    var window: WindowSubscription?
    var itinerary: ItinerarySubscription?
    var savedAt: Date
}

@MainActor
final class ActiveJourneyCache {
    private static let storageKey = "righttrain.ios.activeJourneyCache"
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> CachedActiveJourneyState? {
        guard let data = defaults.data(forKey: Self.storageKey) else {
            return nil
        }
        return try? decoder.decode(CachedActiveJourneyState.self, from: data)
    }

    func save(window: WindowSubscription) {
        save(CachedActiveJourneyState(window: window, itinerary: nil, savedAt: Date()))
    }

    func save(itinerary: ItinerarySubscription) {
        save(CachedActiveJourneyState(window: nil, itinerary: itinerary, savedAt: Date()))
    }

    func clear() {
        defaults.removeObject(forKey: Self.storageKey)
    }

    private func save(_ state: CachedActiveJourneyState) {
        guard let data = try? encoder.encode(state) else {
            return
        }
        defaults.set(data, forKey: Self.storageKey)
    }
}
