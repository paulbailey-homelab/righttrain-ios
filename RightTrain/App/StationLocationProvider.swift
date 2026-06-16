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
    private var continuation: CheckedContinuation<StationSelectionLocation, Error>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func currentLocation() async throws -> StationSelectionLocation {
        guard CLLocationManager.locationServicesEnabled() else {
            throw StationLocationProviderError.unavailable
        }
        if let continuation {
            continuation.resume(throwing: StationLocationProviderError.failed("A location request is already running."))
            self.continuation = nil
        }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            requestLocationAfterAuthorization()
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
        continuation?.resume(returning: location)
        continuation = nil
    }

    private func finish(throwing error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
