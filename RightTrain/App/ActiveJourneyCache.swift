import Foundation

struct CachedActiveJourneyState: Codable {
    var window: WindowSubscription?
    var itinerary: ItinerarySubscription?
    var savedAt: Date
}

@MainActor
final class ActiveJourneyCache {
    private static let storageKey = "righttrain.ios.activeJourneyCache"
    private static let cursorStorageKey = "righttrain.ios.streamCursors"
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

    /// Clears the cached journey snapshot only. Stream cursors are cleared
    /// separately by the clearWindowState/clearItineraryState paths — clear()
    /// also runs during routine window↔itinerary transitions where the
    /// surviving subscription's cursor must not be lost.
    func clear() {
        defaults.removeObject(forKey: Self.storageKey)
    }

    // MARK: - Stream cursors

    // The SSE Last-Event-ID cursors survive app restarts so a reconnect can
    // resume from where the stream left off instead of replaying recent
    // events. Keys embed the subscription ID, so a cursor can never be
    // applied to a different subscription; saving prunes the other entries of
    // the same kind to keep the store bounded at one window + one itinerary.

    func streamCursor(forWindow id: String) -> String? {
        loadCursors()["window.\(id)"]
    }

    func streamCursor(forItinerary id: String) -> String? {
        loadCursors()["itinerary.\(id)"]
    }

    func saveStreamCursor(_ cursor: String, forWindow id: String) {
        saveCursor(cursor, key: "window.\(id)", kindPrefix: "window.")
    }

    func saveStreamCursor(_ cursor: String, forItinerary id: String) {
        saveCursor(cursor, key: "itinerary.\(id)", kindPrefix: "itinerary.")
    }

    func clearWindowStreamCursors() {
        clearCursors(kindPrefix: "window.")
    }

    func clearItineraryStreamCursors() {
        clearCursors(kindPrefix: "itinerary.")
    }

    private func loadCursors() -> [String: String] {
        defaults.dictionary(forKey: Self.cursorStorageKey) as? [String: String] ?? [:]
    }

    private func saveCursor(_ cursor: String, key: String, kindPrefix: String) {
        var cursors = loadCursors().filter { !$0.key.hasPrefix(kindPrefix) }
        cursors[key] = cursor
        defaults.set(cursors, forKey: Self.cursorStorageKey)
    }

    private func clearCursors(kindPrefix: String) {
        let cursors = loadCursors().filter { !$0.key.hasPrefix(kindPrefix) }
        if cursors.isEmpty {
            defaults.removeObject(forKey: Self.cursorStorageKey)
        } else {
            defaults.set(cursors, forKey: Self.cursorStorageKey)
        }
    }

    private func save(_ state: CachedActiveJourneyState) {
        guard let data = try? encoder.encode(state) else {
            return
        }
        defaults.set(data, forKey: Self.storageKey)
    }
}
