import CoreLocation
import Foundation

struct StationSelectionLocation: Equatable {
    var latitude: Double
    var longitude: Double
    var horizontalAccuracyMeters: Double
    var capturedAt: Date
}

enum StationLocationProviderError: LocalizedError, Equatable {
    case denied
    case restricted
    case unavailable
    case inaccurate
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .denied:
            return "Location is off for RightTrain. Search and favourites are still available."
        case .restricted:
            return "Location is restricted on this device. Search and favourites are still available."
        case .unavailable:
            return "Location is not available right now. Search and favourites are still available."
        case .inaccurate:
            return "Location was too imprecise for nearest stations. Search and favourites are still available."
        case .failed(let message):
            return message
        }
    }
}

@MainActor
protocol StationLocationProviding: AnyObject {
    func currentLocation() async throws -> StationSelectionLocation
}

@MainActor
final class SystemStationLocationProvider: NSObject, StationLocationProviding, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuations: [CheckedContinuation<StationSelectionLocation, Error>] = []

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func currentLocation() async throws -> StationSelectionLocation {
        guard CLLocationManager.locationServicesEnabled() else {
            throw StationLocationProviderError.unavailable
        }
        // A second caller joins the request in flight rather than failing it.
        return try await withCheckedThrowingContinuation { continuation in
            let isFirstRequest = continuations.isEmpty
            continuations.append(continuation)
            if isFirstRequest {
                requestLocationAfterAuthorization()
            }
        }
    }

    private func requestLocationAfterAuthorization() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        case .denied:
            finish(throwing: StationLocationProviderError.denied)
        case .restricted:
            finish(throwing: StationLocationProviderError.restricted)
        @unknown default:
            finish(throwing: StationLocationProviderError.unavailable)
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            // The manager reports its status as soon as it's created. Only
            // act when someone asked for a location, or opening the picker
            // prompts for permission before Nearest is chosen.
            guard !continuations.isEmpty, manager.authorizationStatus != .notDetermined else { return }
            requestLocationAfterAuthorization()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            Task { @MainActor in finish(throwing: StationLocationProviderError.unavailable) }
            return
        }
        Task { @MainActor in
            guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 1_500 else {
                finish(throwing: StationLocationProviderError.inaccurate)
                return
            }
            finish(returning: StationSelectionLocation(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                horizontalAccuracyMeters: location.horizontalAccuracy,
                capturedAt: location.timestamp
            ))
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            finish(throwing: StationLocationProviderError.failed("Location could not be read. Search and favourites are still available."))
        }
    }

    private func finish(returning location: StationSelectionLocation) {
        let waiting = continuations
        continuations = []
        waiting.forEach { $0.resume(returning: location) }
    }

    private func finish(throwing error: Error) {
        let waiting = continuations
        continuations = []
        waiting.forEach { $0.resume(throwing: error) }
    }
}

/// Foreground-only location feed for the on-board screen: just accurate
/// enough to say how far the train is from the stations either side, and
/// running only while that screen is visible.
@MainActor
final class OnTrainLocationFeed: NSObject, CLLocationManagerDelegate {
    var onUpdate: ((CLLocation) -> Void)?

    private let manager = CLLocationManager()
    private var isRunning = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 100
        manager.activityType = .otherNavigation
    }

    func start() {
        guard !isRunning else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            isRunning = true
            manager.startUpdatingLocation()
        default:
            break
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        manager.stopUpdatingLocation()
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        Task { @MainActor in
            guard isRunning,
                  latest.horizontalAccuracy >= 0,
                  latest.horizontalAccuracy <= 1_000 else {
                return
            }
            onUpdate?(latest)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}

struct StationDistanceSummary: Equatable {
    struct Station: Equatable {
        var name: String
        var miles: Double
    }

    /// Set when the train is at a station rather than between two.
    var atStation: String?
    var last: Station?
    var next: Station?

    /// "2.3 mi past Woking · 4.1 mi to Guildford", or "At Woking · 4.1 mi to Guildford".
    var text: String {
        var parts: [String] = []
        if let atStation {
            parts.append("At \(atStation)")
        } else if let last {
            parts.append("\(Self.milesText(last.miles)) past \(last.name)")
        }
        if let next {
            parts.append("\(Self.milesText(next.miles)) to \(next.name)")
        }
        return parts.joined(separator: " · ")
    }

    static func milesText(_ miles: Double) -> String {
        miles < 10 ? String(format: "%.1f mi", miles) : String(format: "%.0f mi", miles)
    }
}

/// Straight-line distances from the rider to the calling points either side
/// of them. Which pair they are between comes from geometry alone (the
/// closest leg of the polyline joining the stations), so it needs no
/// realtime reports and works between stations Darwin hasn't updated yet.
enum StationDistanceCalculator {
    struct StopPoint: Equatable {
        var name: String
        var latitude: Double
        var longitude: Double
    }

    static let metresPerMile = 1_609.344
    static let atStationRadiusMeters: Double = 250

    static func summary(latitude: Double, longitude: Double, stops: [StopPoint]) -> StationDistanceSummary? {
        guard !stops.isEmpty else {
            return nil
        }
        let here = CLLocation(latitude: latitude, longitude: longitude)
        func miles(to stop: StopPoint) -> Double {
            here.distance(from: CLLocation(latitude: stop.latitude, longitude: stop.longitude)) / metresPerMile
        }
        func station(_ index: Int) -> StationDistanceSummary.Station? {
            guard stops.indices.contains(index) else { return nil }
            return StationDistanceSummary.Station(name: stops[index].name, miles: miles(to: stops[index]))
        }

        if let nearest = stops.indices.min(by: { miles(to: stops[$0]) < miles(to: stops[$1]) }),
           miles(to: stops[nearest]) * metresPerMile <= atStationRadiusMeters {
            return StationDistanceSummary(atStation: stops[nearest].name, last: nil, next: station(nearest + 1))
        }
        guard stops.count > 1 else {
            return StationDistanceSummary(atStation: nil, last: nil, next: station(0))
        }

        // Project onto a flat plane centred on the rider; at these
        // distances the error is negligible.
        let metresPerDegreeLatitude = 110_540.0
        let metresPerDegreeLongitude = 111_320.0 * cos(latitude * .pi / 180)
        func point(_ stop: StopPoint) -> (x: Double, y: Double) {
            ((stop.longitude - longitude) * metresPerDegreeLongitude, (stop.latitude - latitude) * metresPerDegreeLatitude)
        }

        var best: (index: Int, fraction: Double, distance: Double)?
        for index in 0..<(stops.count - 1) {
            let a = point(stops[index])
            let b = point(stops[index + 1])
            let dx = b.x - a.x
            let dy = b.y - a.y
            let lengthSquared = dx * dx + dy * dy
            let raw = lengthSquared > 0 ? -(a.x * dx + a.y * dy) / lengthSquared : 0
            let fraction = min(max(raw, 0), 1)
            let px = a.x + fraction * dx
            let py = a.y + fraction * dy
            let distance = (px * px + py * py).squareRoot()
            if best == nil || distance < best!.distance {
                best = (index, raw, distance)
            }
        }
        guard let best else {
            return nil
        }
        if best.index == 0, best.fraction <= 0 {
            return StationDistanceSummary(atStation: nil, last: nil, next: station(0))
        }
        if best.index == stops.count - 2, best.fraction >= 1 {
            return StationDistanceSummary(atStation: nil, last: station(stops.count - 1), next: nil)
        }
        return StationDistanceSummary(atStation: nil, last: station(best.index), next: station(best.index + 1))
    }
}
