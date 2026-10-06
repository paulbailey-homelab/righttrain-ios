import CoreLocation
import CoreMotion
import Foundation
import UIKit

protocol NotificationFeedbackGenerating {
    func notificationOccurred(_ type: UINotificationFeedbackGenerator.FeedbackType)
}

struct SystemNotificationFeedbackGenerator: NotificationFeedbackGenerating {
    func notificationOccurred(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }
}

protocol ApplicationStateProviding {
    var applicationState: UIApplication.State { get }
}

struct SystemApplicationStateProvider: ApplicationStateProviding {
    var applicationState: UIApplication.State {
        UIApplication.shared.applicationState
    }
}

protocol StationProximityMonitoring: AnyObject {
    var onOriginRegionEntered: ((String) -> Void)? { get set }
    var onCaughtTrainDetected: ((String, Int) -> Void)? { get set }
    var onItineraryOriginRegionEntered: ((String) -> Void)? { get set }
    var onItineraryInterchangeRegionEntered: ((String, Int, String) -> Void)? { get set }
    var onItineraryOnwardBoardDetected: ((String, Int) -> Void)? { get set }

    func monitorOriginStation(for window: WindowSubscription, requestPermissionIfNeeded: Bool)
    func monitorItineraryPhase(_ phase: ItineraryPhase, for itinerary: ItinerarySubscription, requestPermissionIfNeeded: Bool)
    func stopMonitoring()
}

final class NoopStationProximityMonitor: StationProximityMonitoring {
    var onOriginRegionEntered: ((String) -> Void)?
    var onCaughtTrainDetected: ((String, Int) -> Void)?
    var onItineraryOriginRegionEntered: ((String) -> Void)?
    var onItineraryInterchangeRegionEntered: ((String, Int, String) -> Void)?
    var onItineraryOnwardBoardDetected: ((String, Int) -> Void)?

    func monitorOriginStation(for window: WindowSubscription, requestPermissionIfNeeded: Bool) {}
    func monitorItineraryPhase(_ phase: ItineraryPhase, for itinerary: ItinerarySubscription, requestPermissionIfNeeded: Bool) {}
    func stopMonitoring() {}
}

final class SystemStationProximityMonitor: NSObject, StationProximityMonitoring, CLLocationManagerDelegate {
    var onOriginRegionEntered: ((String) -> Void)?
    var onCaughtTrainDetected: ((String, Int) -> Void)?
    var onItineraryOriginRegionEntered: ((String) -> Void)?
    var onItineraryInterchangeRegionEntered: ((String, Int, String) -> Void)?
    var onItineraryOnwardBoardDetected: ((String, Int) -> Void)?

    private static let originRegionIdentifierPrefix = "righttrain.origin."
    private static let itineraryOriginPrefix = "righttrain.itinerary.origin."
    private static let itineraryInterchangePrefix = "righttrain.itinerary.interchange."
    private let manager = CLLocationManager()
    // Motion & Fitness activity: a second, GPS-independent signal that the
    // user is in a moving vehicle, and a record of when that began.
    private let motionManager = CMMotionActivityManager()
    private var latestMotionActivity: CMMotionActivity?
    private var motionUpdatesActive = false
    private var monitoredKind: MonitoredKind?
    private var monitoredRadius: CLLocationDistance = 0
    private var monitoredCoordinate: CLLocationCoordinate2D?
    private var caughtDetection: CaughtTrainDetectionState?
    private var pendingWindow: WindowSubscription?
    private var pendingItinerary: PendingItinerary?
    private var pendingPermissionRequest = false
    private var reportedOriginWindowID: String?
    private var reportedItineraryOriginID: String?
    private var reportedItineraryInterchange: ReportedInterchange?
    private var locationUpdatesActive = false
    private var didRequestAlwaysAuthorizationThisSession = false

    // Above a sprint along the platform, below what a departing train
    // reaches within its first few seconds.
    private let trainSpeedThreshold: CLLocationSpeed = 6
    private let maximumLocationAge: TimeInterval = 30
    private let maximumHorizontalAccuracy: CLLocationAccuracy = 160
    private let detectionLeadTime: TimeInterval = 2 * 60
    private let detectionTailTime: TimeInterval = 20 * 60
    private let originPresenceTolerance: TimeInterval = 2 * 60
    private let originPresenceStaleness: TimeInterval = 4 * 60
    private let fastSampleTolerance: TimeInterval = 90
    private let minimumFastSampleSpacing: TimeInterval = 5
    // How far a candidate's departure may sit from the moment motion
    // history says the vehicle started moving and still be matched to it.
    private let motionDepartureMatchTolerance: TimeInterval = 3 * 60
    private let requiredFastSamples = 2

    private enum MonitoredKind: Equatable {
        case window(id: String)
        case itineraryOrigin(itineraryID: String)
        case itineraryInterchange(itineraryID: String, legIndex: Int, crs: String)
    }

    private struct PendingItinerary {
        var phase: ItineraryPhase
        var subscription: ItinerarySubscription
    }

    private struct ReportedInterchange: Equatable {
        var itineraryID: String
        var legIndex: Int
    }

    private struct DetectionCandidate: Equatable {
        var serviceID: Int
        var departureDate: Date
    }

    private struct CaughtTrainDetectionState {
        var kind: MonitoredKind
        var legIndex: Int
        // Every train the user could plausibly board. A window offers all of
        // its trains, not just the recommended one: the recommendation moves
        // on to the next train as soon as Darwin reports this one departed,
        // which is exactly when detection needs to keep watching it.
        var candidates: [DetectionCandidate]
        var startDate: Date
        var endDate: Date
        var lastSeenAtOrigin: Date?
        var firstFastSampleAt: Date?
        var lastFastSampleAt: Date?
        var consecutiveFastSamples: Int
        var didEmit: Bool
    }

    override init() {
        super.init()
        manager.delegate = self
        manager.activityType = .otherNavigation
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 20
        manager.showsBackgroundLocationIndicator = true
    }

    func monitorOriginStation(for window: WindowSubscription, requestPermissionIfNeeded: Bool) {
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self),
              let latitude = window.selectedRecommendation.journey.originLatitude,
              let longitude = window.selectedRecommendation.journey.originLongitude else {
            stopMonitoring()
            return
        }

        // Switching subscription contexts always tears down the previous one.
        if monitoredKind != .window(id: window.id) {
            stopMonitoring()
        }
        pendingItinerary = nil
        pendingWindow = window
        pendingPermissionRequest = requestPermissionIfNeeded
        updateCaughtDetectionContextForWindow(window)

        switch manager.authorizationStatus {
        case .authorizedAlways:
            requestMotionAuthorizationIfNeeded()
            if monitoredKind == .window(id: window.id) {
                manager.requestLocation()
                updateLocationUpdates(now: Date())
            } else {
                startMonitoringWindow(window, latitude: latitude, longitude: longitude)
            }
        case .authorizedWhenInUse:
            requestAlwaysAuthorizationIfNeeded()
            if monitoredKind == .window(id: window.id) {
                manager.requestLocation()
                updateLocationUpdates(now: Date())
            } else {
                startMonitoringWindow(window, latitude: latitude, longitude: longitude)
            }
        case .notDetermined where requestPermissionIfNeeded:
            manager.requestWhenInUseAuthorization()
        default:
            break
        }
    }

    func monitorItineraryPhase(_ phase: ItineraryPhase, for itinerary: ItinerarySubscription, requestPermissionIfNeeded: Bool) {
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else {
            stopMonitoring()
            return
        }
        // The final-leg phase has no useful geofence: stop monitoring once
        // the user has boarded the last leg.
        if phase == .onFinalLeg {
            stopMonitoring()
            return
        }

        let target = monitoringTarget(for: phase, itinerary: itinerary)
        guard let target else {
            // No coordinate available — nothing to monitor.
            stopMonitoring()
            return
        }

        if monitoredKind != target.kind {
            stopMonitoring()
        }
        pendingWindow = nil
        pendingItinerary = PendingItinerary(phase: phase, subscription: itinerary)
        pendingPermissionRequest = requestPermissionIfNeeded
        updateCaughtDetectionContextForItinerary(phase: phase, itinerary: itinerary)

        switch manager.authorizationStatus {
        case .authorizedAlways:
            requestMotionAuthorizationIfNeeded()
            if monitoredKind == target.kind {
                manager.requestLocation()
                updateLocationUpdates(now: Date())
            } else {
                startMonitoringItinerary(target: target)
            }
        case .authorizedWhenInUse:
            requestAlwaysAuthorizationIfNeeded()
            if monitoredKind == target.kind {
                manager.requestLocation()
                updateLocationUpdates(now: Date())
            } else {
                startMonitoringItinerary(target: target)
            }
        case .notDetermined where requestPermissionIfNeeded:
            manager.requestWhenInUseAuthorization()
        default:
            break
        }
    }

    func stopMonitoring() {
        for region in manager.monitoredRegions where isManagedRegionIdentifier(region.identifier) {
            manager.stopMonitoring(for: region)
        }
        monitoredKind = nil
        monitoredRadius = 0
        monitoredCoordinate = nil
        caughtDetection = nil
        pendingWindow = nil
        pendingItinerary = nil
        pendingPermissionRequest = false
        reportedOriginWindowID = nil
        reportedItineraryOriginID = nil
        reportedItineraryInterchange = nil
        stopLocationUpdates()
        manager.allowsBackgroundLocationUpdates = false
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            if let pendingWindow {
                monitorOriginStation(for: pendingWindow, requestPermissionIfNeeded: pendingPermissionRequest)
            } else if let pendingItinerary {
                monitorItineraryPhase(pendingItinerary.phase, for: pendingItinerary.subscription, requestPermissionIfNeeded: pendingPermissionRequest)
            }
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        if let windowID = windowID(fromOriginRegionIdentifier: region.identifier) {
            reportWindowOriginEntry(windowID: windowID)
            markOriginPresence(at: Date())
            updateLocationUpdates(now: Date())
            return
        }
        if let itineraryID = itineraryID(fromItineraryOriginIdentifier: region.identifier) {
            reportItineraryOriginEntry(itineraryID: itineraryID)
            markOriginPresence(at: Date())
            updateLocationUpdates(now: Date())
            return
        }
        if let interchange = interchange(fromItineraryInterchangeIdentifier: region.identifier) {
            reportItineraryInterchangeEntry(itineraryID: interchange.itineraryID, legIndex: interchange.legIndex, crs: interchange.crs)
            markOriginPresence(at: Date())
            updateLocationUpdates(now: Date())
            return
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last,
              let coordinate = monitoredCoordinate,
              let kind = monitoredKind,
              monitoredRadius > 0 else {
            return
        }
        let origin = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let now = Date()
        let locationAge = abs(now.timeIntervalSince(latest.timestamp))
        guard locationAge <= maximumLocationAge,
              latest.horizontalAccuracy >= 0,
              latest.horizontalAccuracy <= max(maximumHorizontalAccuracy, monitoredRadius) else {
            return
        }

        if latest.distance(from: origin) <= monitoredRadius {
            switch kind {
            case .window(let windowID):
                reportWindowOriginEntry(windowID: windowID)
            case .itineraryOrigin(let itineraryID):
                reportItineraryOriginEntry(itineraryID: itineraryID)
            case .itineraryInterchange(let itineraryID, let legIndex, let crs):
                reportItineraryInterchangeEntry(itineraryID: itineraryID, legIndex: legIndex, crs: crs)
            }
            markOriginPresence(at: latest.timestamp)
        }
        evaluateCaughtTrainDetection(with: latest, now: now)
        updateLocationUpdates(now: now)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        BetaDiagnostics.record("station_proximity_location_failed", details: error.localizedDescription)
    }

    private struct MonitoringTarget {
        var kind: MonitoredKind
        var coordinate: CLLocationCoordinate2D
        var radius: CLLocationDistance
        var identifier: String
        var diagnosticContext: String
    }

    private func monitoringTarget(for phase: ItineraryPhase, itinerary: ItinerarySubscription) -> MonitoringTarget? {
        switch phase {
        case .planning, .atOrigin:
            guard let firstLeg = itinerary.selectedItinerary.legs.first,
                  let latitude = firstLeg.originLatitude,
                  let longitude = firstLeg.originLongitude else {
                return nil
            }
            let radius = clampedRadius(firstLeg.monitoringRadiusMeters)
            return MonitoringTarget(
                kind: .itineraryOrigin(itineraryID: itinerary.id),
                coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                radius: radius,
                identifier: "\(Self.itineraryOriginPrefix)\(itinerary.id)",
                diagnosticContext: "itinerary_origin:\(firstLeg.originCrs);radius=\(Int(radius))"
            )
        case .onLeg, .approachingInterchange:
            guard let connection = itinerary.nextConnection else {
                return nil
            }
            let coordinate: CLLocationCoordinate2D
            let radiusInput: Int?
            if let latitude = connection.atLatitude, let longitude = connection.atLongitude {
                coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
                radiusInput = connection.atMonitoringRadiusMeters
            } else if let onward = itinerary.onwardLeg,
                      let latitude = onward.originLatitude,
                      let longitude = onward.originLongitude {
                coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
                radiusInput = onward.monitoringRadiusMeters
            } else {
                return nil
            }
            let radius = clampedRadius(radiusInput)
            let crs = connection.atCrs.uppercased()
            let legIndex = connection.fromLegIndex
            return MonitoringTarget(
                kind: .itineraryInterchange(itineraryID: itinerary.id, legIndex: legIndex, crs: crs),
                coordinate: coordinate,
                radius: radius,
                identifier: Self.itineraryInterchangeRegionIdentifier(itineraryID: itinerary.id, legIndex: legIndex, crs: crs),
                diagnosticContext: "itinerary_interchange:\(crs);leg=\(legIndex);radius=\(Int(radius))"
            )
        case .onFinalLeg:
            return nil
        }
    }

    private func clampedRadius(_ requested: Int?) -> CLLocationDistance {
        CLLocationDistance(min(max(requested ?? 300, 100), 800))
    }

    private func startMonitoringWindow(_ window: WindowSubscription, latitude: Double, longitude: Double) {
        let radius = clampedRadius(window.selectedRecommendation.journey.monitoringRadiusMeters)
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let region = CLCircularRegion(
            center: coordinate,
            radius: radius,
            identifier: "\(Self.originRegionIdentifierPrefix)\(window.id)"
        )
        region.notifyOnEntry = true
        region.notifyOnExit = false

        monitoredKind = .window(id: window.id)
        monitoredRadius = radius
        monitoredCoordinate = coordinate
        manager.allowsBackgroundLocationUpdates = true
        manager.startMonitoring(for: region)
        manager.requestLocation()
        updateLocationUpdates(now: Date())
        BetaDiagnostics.record("station_proximity_monitor_started", details: "\(window.originCrs); radius=\(Int(radius))")
    }

    private func startMonitoringItinerary(target: MonitoringTarget) {
        let region = CLCircularRegion(
            center: target.coordinate,
            radius: target.radius,
            identifier: target.identifier
        )
        region.notifyOnEntry = true
        region.notifyOnExit = false

        monitoredKind = target.kind
        monitoredRadius = target.radius
        monitoredCoordinate = target.coordinate
        manager.allowsBackgroundLocationUpdates = true
        manager.startMonitoring(for: region)
        manager.requestLocation()
        updateLocationUpdates(now: Date())
        BetaDiagnostics.record("station_proximity_monitor_started", details: target.diagnosticContext)
    }

    private func requestAlwaysAuthorizationIfNeeded() {
        guard pendingPermissionRequest,
              manager.authorizationStatus == .authorizedWhenInUse,
              !didRequestAlwaysAuthorizationThisSession else {
            return
        }
        didRequestAlwaysAuthorizationThisSession = true
        manager.requestAlwaysAuthorization()
        BetaDiagnostics.record("station_proximity_always_authorization_requested")
    }

    private func isManagedRegionIdentifier(_ identifier: String) -> Bool {
        identifier.hasPrefix(Self.originRegionIdentifierPrefix) ||
            identifier.hasPrefix(Self.itineraryOriginPrefix) ||
            identifier.hasPrefix(Self.itineraryInterchangePrefix)
    }

    private func windowID(fromOriginRegionIdentifier identifier: String) -> String? {
        guard identifier.hasPrefix(Self.originRegionIdentifierPrefix),
              !identifier.hasPrefix(Self.itineraryOriginPrefix),
              !identifier.hasPrefix(Self.itineraryInterchangePrefix) else {
            return nil
        }
        let windowID = String(identifier.dropFirst(Self.originRegionIdentifierPrefix.count))
        return windowID.isEmpty ? nil : windowID
    }

    private func itineraryID(fromItineraryOriginIdentifier identifier: String) -> String? {
        guard identifier.hasPrefix(Self.itineraryOriginPrefix) else {
            return nil
        }
        let itineraryID = String(identifier.dropFirst(Self.itineraryOriginPrefix.count))
        return itineraryID.isEmpty ? nil : itineraryID
    }

    private func interchange(fromItineraryInterchangeIdentifier identifier: String) -> (itineraryID: String, legIndex: Int, crs: String)? {
        guard let parsed = Self.parseItineraryInterchangeRegionIdentifier(identifier) else {
            return nil
        }
        if !parsed.crs.isEmpty {
            return parsed
        }
        // Legacy region identifiers did not include CRS; keep an in-memory
        // fallback for regions created by older app versions.
        if case .itineraryInterchange(let kindID, let kindLeg, let crs) = monitoredKind,
           kindID == parsed.itineraryID, kindLeg == parsed.legIndex {
            return (parsed.itineraryID, parsed.legIndex, crs)
        }
        if let pending = pendingItinerary,
           let connection = pending.subscription.nextConnection,
           pending.subscription.id == parsed.itineraryID,
           connection.fromLegIndex == parsed.legIndex {
            return (parsed.itineraryID, parsed.legIndex, connection.atCrs.uppercased())
        }
        return parsed
    }

    static func itineraryInterchangeRegionIdentifier(itineraryID: String, legIndex: Int, crs: String) -> String {
        let normalizedCRS = crs.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return "\(itineraryInterchangePrefix)\(itineraryID).\(legIndex).\(normalizedCRS)"
    }

    static func parseItineraryInterchangeRegionIdentifier(_ identifier: String) -> (itineraryID: String, legIndex: Int, crs: String)? {
        guard identifier.hasPrefix(itineraryInterchangePrefix) else {
            return nil
        }
        let suffix = String(identifier.dropFirst(itineraryInterchangePrefix.count))
        let parts = suffix.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2 || parts.count == 3,
              !parts[0].isEmpty,
              let legIndex = Int(parts[1]) else {
            return nil
        }
        let crs = parts.count == 3
            ? String(parts[2]).trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            : ""
        return (String(parts[0]), legIndex, crs)
    }

    private func updateCaughtDetectionContextForWindow(_ window: WindowSubscription) {
        let recommendations = [window.selectedRecommendation] + window.recommendations
        var candidates: [DetectionCandidate] = []
        for recommendation in recommendations {
            let journey = recommendation.journey
            guard journey.serviceId > 0,
                  !JourneyFormatting.isCancelled(journey),
                  recommendation.score.reasons?.contains("cancelled") != true,
                  !candidates.contains(where: { $0.serviceID == journey.serviceId }) else {
                continue
            }
            let departureDisplay = JourneyFormatting.departureDisplay(journey)
            guard let departureDate = departureDisplay.currentDate ?? departureDisplay.scheduledDate else {
                continue
            }
            candidates.append(DetectionCandidate(serviceID: journey.serviceId, departureDate: departureDate))
        }
        applyCaughtDetectionContext(kind: .window(id: window.id), legIndex: 0, candidates: candidates)
    }

    /// Refreshes the candidate trains while keeping what has been observed
    /// for the same subscription (origin presence, fast samples, emission),
    /// so a refresh mid-departure never throws away the evidence.
    private func applyCaughtDetectionContext(kind: MonitoredKind, legIndex: Int, candidates: [DetectionCandidate]) {
        guard let earliest = candidates.map(\.departureDate).min(),
              let latest = candidates.map(\.departureDate).max() else {
            caughtDetection = nil
            return
        }
        let previous = caughtDetection?.kind == kind && caughtDetection?.legIndex == legIndex ? caughtDetection : nil
        caughtDetection = CaughtTrainDetectionState(
            kind: kind,
            legIndex: legIndex,
            candidates: candidates,
            startDate: earliest.addingTimeInterval(-detectionLeadTime),
            endDate: latest.addingTimeInterval(detectionTailTime),
            lastSeenAtOrigin: previous?.lastSeenAtOrigin,
            firstFastSampleAt: previous?.firstFastSampleAt,
            lastFastSampleAt: previous?.lastFastSampleAt,
            consecutiveFastSamples: previous?.consecutiveFastSamples ?? 0,
            didEmit: previous?.didEmit ?? false
        )
    }

    private func updateCaughtDetectionContextForItinerary(phase: ItineraryPhase, itinerary: ItinerarySubscription) {
        // Walking-speed caught-train detection only applies to:
        //   - planning/at_origin: the first leg
        //   - approaching_interchange: the onward leg (silent fallback to
        //     advance phase if the user never explicitly taps "I'm on
        //     this train").
        let leg: ItineraryLeg?
        let legIndex: Int
        switch phase {
        case .planning, .atOrigin:
            leg = itinerary.selectedItinerary.legs.first
            legIndex = 0
        case .approachingInterchange:
            leg = itinerary.onwardLeg
            legIndex = itinerary.currentLegIndex + 1
        case .onLeg, .onFinalLeg:
            caughtDetection = nil
            return
        }
        guard let leg, leg.serviceId > 0 else {
            caughtDetection = nil
            return
        }

        let journey = leg.journeyResult
        let departureDisplay = JourneyFormatting.departureDisplay(journey)
        guard let departureDate = departureDisplay.currentDate ?? departureDisplay.scheduledDate else {
            caughtDetection = nil
            return
        }

        let target: MonitoredKind
        switch phase {
        case .planning, .atOrigin:
            target = .itineraryOrigin(itineraryID: itinerary.id)
        case .approachingInterchange:
            let crs: String
            if let connection = itinerary.nextConnection {
                crs = connection.atCrs.uppercased()
            } else {
                crs = ""
            }
            target = .itineraryInterchange(itineraryID: itinerary.id, legIndex: itinerary.currentLegIndex, crs: crs)
        case .onLeg, .onFinalLeg:
            return
        }

        // A switched route is a different train: start its evidence afresh.
        if let previous = caughtDetection,
           previous.kind == target,
           previous.candidates.map(\.serviceID) != [leg.serviceId] {
            caughtDetection = nil
        }
        applyCaughtDetectionContext(
            kind: target,
            legIndex: legIndex,
            candidates: [DetectionCandidate(serviceID: leg.serviceId, departureDate: departureDate)]
        )
    }

    private func reportWindowOriginEntry(windowID: String) {
        guard reportedOriginWindowID != windowID else {
            return
        }
        reportedOriginWindowID = windowID
        onOriginRegionEntered?(windowID)
    }

    private func reportItineraryOriginEntry(itineraryID: String) {
        guard reportedItineraryOriginID != itineraryID else {
            return
        }
        reportedItineraryOriginID = itineraryID
        onItineraryOriginRegionEntered?(itineraryID)
    }

    private func reportItineraryInterchangeEntry(itineraryID: String, legIndex: Int, crs: String) {
        let key = ReportedInterchange(itineraryID: itineraryID, legIndex: legIndex)
        guard reportedItineraryInterchange != key else {
            return
        }
        reportedItineraryInterchange = key
        onItineraryInterchangeRegionEntered?(itineraryID, legIndex, crs)
    }

    private func markOriginPresence(at date: Date) {
        caughtDetection?.lastSeenAtOrigin = date
    }

    /// Runs on every accepted location fix, and on every motion activity
    /// update with `location` nil, since a carriage can go minutes without
    /// a usable fix while the motion chip keeps reporting.
    private func evaluateCaughtTrainDetection(with location: CLLocation?, now: Date) {
        guard var detection = caughtDetection,
              !detection.didEmit else {
            return
        }
        guard now <= detection.endDate else {
            caughtDetection = nil
            stopLocationUpdates()
            return
        }
        let eligible = detection.candidates.filter { candidateIsEligible($0, detection: detection, now: now) }
        guard now >= detection.startDate,
              !eligible.isEmpty else {
            caughtDetection = detection
            return
        }

        let measuredSpeed = location.flatMap { self.reportedSpeed(of: $0) }
        let travelSpeed = location.flatMap { self.impliedSpeedSinceOrigin(of: $0, detection: detection) }
        let inMovingVehicle = motionShowsMovingVehicle(since: detection.lastSeenAtOrigin)
        let isFast = (measuredSpeed ?? 0) >= trainSpeedThreshold ||
            (travelSpeed ?? 0) >= trainSpeedThreshold ||
            inMovingVehicle
        guard isFast else {
            // Only a trustworthy slow reading cancels a run; a fix with no
            // speed (Wi-Fi or cell positioning in a carriage) proves nothing.
            if measuredSpeed != nil {
                detection.consecutiveFastSamples = 0
                detection.firstFastSampleAt = nil
                detection.lastFastSampleAt = nil
            }
            caughtDetection = detection
            return
        }
        // GPS fixes and motion updates can arrive in bursts; a burst is
        // one observation, not several.
        if let lastFastSampleAt = detection.lastFastSampleAt,
           now.timeIntervalSince(lastFastSampleAt) < minimumFastSampleSpacing {
            caughtDetection = detection
            return
        }
        detection.lastFastSampleAt = now

        if let firstFastSampleAt = detection.firstFastSampleAt,
           now.timeIntervalSince(firstFastSampleAt) <= fastSampleTolerance {
            detection.consecutiveFastSamples += 1
        } else {
            detection.firstFastSampleAt = now
            detection.consecutiveFastSamples = 1
        }

        guard detection.consecutiveFastSamples >= requiredFastSamples else {
            caughtDetection = detection
            return
        }

        // Marked before the (asynchronous) motion history lookup so later
        // fixes can't emit twice.
        detection.didEmit = true
        caughtDetection = detection
        stopLocationUpdates()
        resolveCaughtCandidate(from: eligible, detection: detection, now: now) { [weak self] caught, movementStartedAt in
            guard let self,
                  let current = self.caughtDetection,
                  current.kind == detection.kind,
                  current.didEmit else {
                return
            }
            let movement = movementStartedAt.map { String(Int($0.timeIntervalSince1970)) } ?? "none"
            BetaDiagnostics.record(
                "station_proximity_caught_train_matched",
                details: "service=\(caught.serviceID); moving_since=\(movement); \(self.detectionDiagnostics(detection))"
            )
            self.emitCaughtTrain(caught, detection: detection)
        }
    }

    private func emitCaughtTrain(_ caught: DetectionCandidate, detection: CaughtTrainDetectionState) {
        switch detection.kind {
        case .window(let windowID):
            onCaughtTrainDetected?(windowID, caught.serviceID)
        case .itineraryOrigin(let itineraryID):
            // Silent fallback: phase advance only, never auto-pin.
            onItineraryOnwardBoardDetected?(itineraryID, detection.legIndex)
        case .itineraryInterchange(let itineraryID, _, _):
            onItineraryOnwardBoardDetected?(itineraryID, detection.legIndex)
        }
    }

    /// Picks the train that carried the user away. With motion history, the
    /// one departing closest to when the vehicle started moving; without it,
    /// the latest one already due while they were still at the station (an
    /// earlier one they were still on the platform after left without them).
    private func resolveCaughtCandidate(
        from eligible: [DetectionCandidate],
        detection: CaughtTrainDetectionState,
        now: Date,
        completion: @escaping (DetectionCandidate, Date?) -> Void
    ) {
        guard let fallback = eligible.max(by: { $0.departureDate < $1.departureDate }) else {
            return
        }
        guard eligible.count > 1,
              motionActivityAuthorized,
              let lastSeenAtOrigin = detection.lastSeenAtOrigin else {
            completion(fallback, nil)
            return
        }
        let historyStart = lastSeenAtOrigin.addingTimeInterval(-10 * 60)
        motionManager.queryActivityStarting(from: historyStart, to: now, to: .main) { [weak self] activities, _ in
            guard let self,
                  let movementStartedAt = Self.movingVehicleStart(in: activities ?? []) else {
                completion(fallback, nil)
                return
            }
            let nearest = eligible.min {
                abs($0.departureDate.timeIntervalSince(movementStartedAt)) < abs($1.departureDate.timeIntervalSince(movementStartedAt))
            }
            if let nearest,
               abs(nearest.departureDate.timeIntervalSince(movementStartedAt)) <= self.motionDepartureMatchTolerance {
                completion(nearest, movementStartedAt)
            } else {
                completion(fallback, movementStartedAt)
            }
        }
    }

    /// When the current vehicle journey began: the start of the latest run
    /// of automotive activity not broken by walking, running, cycling or
    /// standing still outside a vehicle. A train halted at a signal reads
    /// as automotive and stationary, and does not break the run.
    private static func movingVehicleStart(in activities: [CMMotionActivity]) -> Date? {
        var start: Date?
        for activity in activities.sorted(by: { $0.startDate < $1.startDate }) {
            if activity.automotive, activity.confidence != .low {
                if start == nil, !activity.stationary {
                    start = activity.startDate
                }
            } else if activity.walking || activity.running || activity.cycling || activity.stationary {
                start = nil
            }
        }
        return start
    }

    private var motionActivityAuthorized: Bool {
        CMMotionActivityManager.isActivityAvailable() &&
            CMMotionActivityManager.authorizationStatus() == .authorized
    }

    /// True when the motion chip currently has the user in a moving vehicle,
    /// a classification that began around or after they were last at the
    /// station (so a drive to the station doesn't count).
    private func motionShowsMovingVehicle(since lastSeenAtOrigin: Date?) -> Bool {
        guard let activity = latestMotionActivity,
              let lastSeenAtOrigin,
              activity.automotive,
              !activity.stationary,
              activity.confidence != .low else {
            return false
        }
        return activity.startDate >= lastSeenAtOrigin.addingTimeInterval(-2 * 60)
    }

    private func requestMotionAuthorizationIfNeeded() {
        guard pendingPermissionRequest,
              CMMotionActivityManager.isActivityAvailable(),
              CMMotionActivityManager.authorizationStatus() == .notDetermined else {
            return
        }
        // A history query is what raises the Motion & Fitness prompt.
        let now = Date()
        motionManager.queryActivityStarting(from: now.addingTimeInterval(-60), to: now, to: .main) { _, _ in }
        BetaDiagnostics.record("station_proximity_motion_authorization_requested")
    }

    private func startMotionUpdates() {
        guard !motionUpdatesActive, motionActivityAuthorized else {
            return
        }
        motionUpdatesActive = true
        motionManager.startActivityUpdates(to: .main) { [weak self] activity in
            guard let self else {
                return
            }
            self.latestMotionActivity = activity
            self.evaluateCaughtTrainDetection(with: nil, now: Date())
        }
    }

    private func stopMotionUpdates() {
        guard motionUpdatesActive else {
            return
        }
        motionManager.stopActivityUpdates()
        motionUpdatesActive = false
        latestMotionActivity = nil
    }

    /// The fix's own speed, when Core Location measured one well enough.
    private func reportedSpeed(of location: CLLocation) -> CLLocationSpeed? {
        guard location.speed >= 0,
              location.speedAccuracy < 0 || location.speedAccuracy <= max(location.speed, 4) else {
            return nil
        }
        return location.speed
    }

    /// A lower bound on average speed since the user was last inside the
    /// station radius. Works from any fix good enough to pass the accuracy
    /// filter, including the speedless ones a phone gets inside a carriage.
    private func impliedSpeedSinceOrigin(of location: CLLocation, detection: CaughtTrainDetectionState) -> CLLocationSpeed? {
        guard let coordinate = monitoredCoordinate,
              let lastSeenAtOrigin = detection.lastSeenAtOrigin else {
            return nil
        }
        let elapsed = location.timestamp.timeIntervalSince(lastSeenAtOrigin)
        let origin = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let travelled = location.distance(from: origin) - monitoredRadius - location.horizontalAccuracy
        guard elapsed >= 15, travelled > 0 else {
            return nil
        }
        return travelled / elapsed
    }

    private func candidateIsEligible(_ candidate: DetectionCandidate, detection: CaughtTrainDetectionState, now: Date) -> Bool {
        guard now >= candidate.departureDate.addingTimeInterval(-30),
              now <= candidate.departureDate.addingTimeInterval(detectionTailTime),
              let lastSeenAtOrigin = detection.lastSeenAtOrigin else {
            return false
        }
        return lastSeenAtOrigin >= candidate.departureDate.addingTimeInterval(-originPresenceTolerance) &&
            lastSeenAtOrigin <= now &&
            now.timeIntervalSince(lastSeenAtOrigin) <= originPresenceStaleness
    }

    private func detectionDiagnostics(_ detection: CaughtTrainDetectionState) -> String {
        let candidates = detection.candidates
            .map { "\($0.serviceID)@\(Int($0.departureDate.timeIntervalSince1970))" }
            .joined(separator: ",")
        let lastSeen = detection.lastSeenAtOrigin.map { String(Int($0.timeIntervalSince1970)) } ?? "none"
        return "last_seen=\(lastSeen); candidates=\(candidates)"
    }

    private func updateLocationUpdates(now: Date) {
        guard let detection = caughtDetection,
              !detection.didEmit,
              detection.lastSeenAtOrigin != nil,
              now <= detection.endDate else {
            stopLocationUpdates()
            return
        }
        startLocationUpdates()
    }

    private func startLocationUpdates() {
        guard !locationUpdatesActive else {
            return
        }
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
        locationUpdatesActive = true
        manager.startUpdatingLocation()
        startMotionUpdates()
    }

    private func stopLocationUpdates() {
        guard locationUpdatesActive else {
            return
        }
        manager.stopUpdatingLocation()
        manager.pausesLocationUpdatesAutomatically = true
        locationUpdatesActive = false
        stopMotionUpdates()
    }
}

@MainActor
@Observable
final class ActiveWindowViewModel {
    private(set) var activeWindow: WindowSubscription?
    private(set) var activeItinerary: ItinerarySubscription?
    private(set) var liveRefreshGeneration = 0
    private(set) var pinnedLiveActivityServiceID: Int? {
        didSet {
            UserDefaults.standard.set(pinnedLiveActivityServiceID, forKey: Self.pinnedLiveActivityServiceIDKey)
        }
    }
    private(set) var handledDepartedPromptKeys: Set<String> = [] {
        didSet {
            UserDefaults.standard.set(Array(handledDepartedPromptKeys).sorted(), forKey: Self.handledDepartedPromptKeysKey)
        }
    }

    private var activeWindowID: String? {
        didSet {
            UserDefaults.standard.set(activeWindowID, forKey: Self.activeWindowIDKey)
        }
    }

    private var activeItineraryID: String? {
        didSet {
            UserDefaults.standard.set(activeItineraryID, forKey: Self.activeItineraryIDKey)
        }
    }

    @ObservationIgnored private let apiClient: any APIClienting
    @ObservationIgnored private let operationState: AppOperationState
    @ObservationIgnored private let liveActivityCoordinator: LiveActivityCoordinating
    @ObservationIgnored private let stationProximityMonitor: any StationProximityMonitoring
    @ObservationIgnored private let registrationContextFactory: DeviceRegistrationContextFactory
    @ObservationIgnored private let accessTokenProvider: () -> String?
    @ObservationIgnored private let notificationFeedbackGenerator: any NotificationFeedbackGenerating
    @ObservationIgnored private let applicationStateProvider: any ApplicationStateProviding
    @ObservationIgnored private let activeJourneyCache: ActiveJourneyCache
    @ObservationIgnored private let mutationQueue: JourneyMutationQueue
    @ObservationIgnored private let connectivityService: ConnectivityService
    @ObservationIgnored private var activeWindowStreamLastEventID: String?
    @ObservationIgnored private var activeItineraryStreamLastEventID: String?
    @ObservationIgnored private var streamRefreshInFlight = false
    @ObservationIgnored private var streamRefreshFollowUpNeeded = false
    @ObservationIgnored private var onboardArrivalClearTask: Task<Void, Never>?
    @ObservationIgnored private var pendingOriginEntryWindowID: String?
    @ObservationIgnored var didClearActiveWindowState: (() -> Void)?

    private static let activeWindowIDKey = "righttrain.ios.activeWindowID"
    private static let activeItineraryIDKey = "righttrain.ios.activeItineraryID"
    private static let pinnedLiveActivityServiceIDKey = "righttrain.ios.pinnedLiveActivityServiceID"
    private static let handledDepartedPromptKeysKey = "righttrain.ios.handledDepartedPromptKeys"
    private static let activeWindowFallbackPollingInterval = Duration.seconds(120)
    private static let activeWindowDiscoveryPollingInterval = Duration.seconds(60)
    private static let activeWindowDistantPollingInterval = Duration.seconds(300)
    private static let activeWindowApproachingPollingInterval = Duration.seconds(60)
    private static let activeWindowImminentPollingInterval = Duration.seconds(20)
    private static let activeWindowStaleGraceSeconds: TimeInterval = 30 * 60
    static let onboardArrivalClearGraceSeconds: TimeInterval = 5 * 60
    private static let activeWindowAuthFailureBackoff = Duration.seconds(300)

    init(
        apiClient: any APIClienting,
        operationState: AppOperationState,
        liveActivityCoordinator: LiveActivityCoordinating,
        stationProximityMonitor: any StationProximityMonitoring = NoopStationProximityMonitor(),
        registrationContextFactory: DeviceRegistrationContextFactory,
        accessTokenProvider: @escaping () -> String?,
        notificationFeedbackGenerator: any NotificationFeedbackGenerating,
        applicationStateProvider: any ApplicationStateProviding,
        activeJourneyCache: ActiveJourneyCache? = nil,
        mutationQueue: JourneyMutationQueue? = nil,
        connectivityService: ConnectivityService? = nil
    ) {
        self.apiClient = apiClient
        self.operationState = operationState
        self.liveActivityCoordinator = liveActivityCoordinator
        self.stationProximityMonitor = stationProximityMonitor
        self.registrationContextFactory = registrationContextFactory
        self.accessTokenProvider = accessTokenProvider
        self.notificationFeedbackGenerator = notificationFeedbackGenerator
        self.applicationStateProvider = applicationStateProvider
        self.activeJourneyCache = activeJourneyCache ?? ActiveJourneyCache()
        self.mutationQueue = mutationQueue ?? JourneyMutationQueue()
        self.connectivityService = connectivityService ?? ConnectivityService()
        self.activeWindowID = UserDefaults.standard.string(forKey: Self.activeWindowIDKey)
        self.activeItineraryID = UserDefaults.standard.string(forKey: Self.activeItineraryIDKey)
        self.pinnedLiveActivityServiceID = UserDefaults.standard.object(forKey: Self.pinnedLiveActivityServiceIDKey) as? Int
        self.handledDepartedPromptKeys = Set(UserDefaults.standard.stringArray(forKey: Self.handledDepartedPromptKeysKey) ?? [])
        self.stationProximityMonitor.onOriginRegionEntered = { [weak self] windowID in
            Task { @MainActor in
                await self?.markNearOriginStation(windowID: windowID)
            }
        }
        self.stationProximityMonitor.onCaughtTrainDetected = { [weak self] windowID, serviceID in
            Task { @MainActor in
                await self?.markCaughtTrainByDetection(windowID: windowID, serviceID: serviceID)
            }
        }
        self.stationProximityMonitor.onItineraryOriginRegionEntered = { [weak self] itineraryID in
            Task { @MainActor in
                await self?.markItineraryAtOrigin(itineraryID: itineraryID)
            }
        }
        self.stationProximityMonitor.onItineraryInterchangeRegionEntered = { [weak self] itineraryID, legIndex, crs in
            Task { @MainActor in
                await self?.markItineraryApproachingInterchange(itineraryID: itineraryID, legIndex: legIndex, atCrs: crs)
            }
        }
        self.stationProximityMonitor.onItineraryOnwardBoardDetected = { [weak self] itineraryID, legIndex in
            Task { @MainActor in
                await self?.markItineraryOnwardBoardedByDetection(itineraryID: itineraryID, legIndex: legIndex)
            }
        }
    }

    func restoreCachedActiveJourneyIfPossible() {
        guard accessTokenProvider() != nil else {
            return
        }
        restoreCachedActiveJourneyIfNeeded()
    }

    private func restoreCachedActiveJourneyIfNeeded() {
        guard activeWindow == nil, activeItinerary == nil, let cached = activeJourneyCache.load() else {
            return
        }
        if let window = cached.window, window.isActive {
            activeWindow = window
            activeWindowID = window.id
            pinnedLiveActivityServiceID = normalizedPinnedServiceID(window.pinnedTrainServiceId)
        } else if let itinerary = cached.itinerary, itinerary.isActive {
            activeItinerary = itinerary
            activeItineraryID = itinerary.id
        }
    }

    func refreshActiveWindow(showLoading: Bool = true) async {
        await reconcileLiveActivityIntentActions()
        await flushQueuedMutations()
        await performActiveWindowRefresh(showLoading: showLoading)
    }

    func refreshActiveWindowFromPullGesture() async {
        await reconcileLiveActivityIntentActions()
        await flushQueuedMutations()
        await performActiveWindowRefresh(showLoading: false, showAlertOnFailure: false)
    }

    var canShareActiveJourney: Bool {
        activeItinerary != nil || activeWindow != nil
    }

    func createJourneyShareURL() async -> URL? {
        guard let accessToken = accessTokenProvider() else {
            operationState.alertState = .auth(AppOperationState.expiredSessionMessage)
            return nil
        }
        let input: CreateJourneyShareRequest
        if let activeItinerary {
            input = CreateJourneyShareRequest(itinerarySubscriptionId: activeItinerary.id)
        } else if let activeWindow {
            input = CreateJourneyShareRequest(windowSubscriptionId: activeWindow.id)
        } else {
            operationState.alertState = .validation("Pin a journey before sharing it.")
            return nil
        }

        do {
            let response = try await apiClient.createJourneyShare(input: input, accessToken: accessToken)
            return URL(string: response.shareUrl)
        } catch {
            operationState.handleOperationError(error)
            return nil
        }
    }

    func monitorActiveWindowForegroundUpdates() async {
        guard accessTokenProvider() != nil else {
            return
        }
        await reconcileLiveActivityIntentActions()
        await flushQueuedMutations()
        guard activeWindowID != nil || activeItineraryID != nil else {
            await runActiveWindowDiscoveryLoop()
            return
        }
        await performActiveWindowRefresh(showLoading: false, showAlertOnFailure: false)

        let heartbeatTask = Task { [weak self] in
            await self?.runActiveWindowHeartbeatFallback()
        }
        defer {
            heartbeatTask.cancel()
        }

        await runActiveWindowStreamReconnectLoop()
    }

    func createWindow(input: CreateWindowSubscriptionRequest) async throws -> WindowSubscription {
        guard let accessToken = accessTokenProvider() else {
            throw ActiveWindowViewModelError.missingAccessToken
        }

        var subscription = try await apiClient.createWindowSubscription(input: input, accessToken: accessToken)
        subscription.phase = "window"
        if activeWindowID != subscription.id {
            handledDepartedPromptKeys = []
        }
        clearItineraryState()
        activeWindow = subscription
        activeWindowID = subscription.id
        activeWindowStreamLastEventID = nil
        pinnedLiveActivityServiceID = normalizedPinnedServiceID(subscription.pinnedTrainServiceId)
        activeJourneyCache.save(window: subscription)
        await liveActivityCoordinator.sync(
            window: subscription,
            pinnedTrainServiceID: pinnedLiveActivityServiceID,
            tokenRegistration: liveActivityTokenRegistrationContext()
        )
        stationProximityMonitor.monitorOriginStation(for: subscription, requestPermissionIfNeeded: true)
        await scheduleOnboardArrivalClearIfNeeded(for: subscription)
        operationState.alertState = nil
        BetaDiagnostics.record("active_window_created")
        return subscription
    }

    func createItinerary(input: CreateItinerarySubscriptionRequest) async throws -> ItinerarySubscription {
        guard let accessToken = accessTokenProvider() else {
            throw ActiveWindowViewModelError.missingAccessToken
        }

        let subscription = try await apiClient.createItinerarySubscription(input: input, accessToken: accessToken)
        clearWindowState()
        activeItinerary = subscription
        activeItineraryID = subscription.id
        activeItineraryStreamLastEventID = nil
        activeJourneyCache.save(itinerary: subscription)
        await liveActivityCoordinator.sync(
            itinerary: subscription,
            tokenRegistration: liveActivityTokenRegistrationContext()
        )
        operationState.alertState = nil
        BetaDiagnostics.record("active_itinerary_created")
        return subscription
    }

    /// Switches the monitored journey to another itinerary the same search
    /// returned. There is no server-side "select" for an existing
    /// subscription, so this recreates it with the chosen stable key — the
    /// same path the results screen uses when replacing an active journey.
    /// Only offered before boarding: once a leg is under way the recovery
    /// replan is the right tool.
    func switchSelectedItinerary(to option: ItineraryRecommendation) async {
        guard let itinerary = activeItinerary else {
            return
        }
        let stableKey = option.stableKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stableKey.isEmpty,
              stableKey != itinerary.selectedItinerary.stableKey.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return
        }
        guard let departureStart = DateFormatting.date(from: itinerary.departureStart) else {
            return
        }

        await operationState.withLoading {
            try await replaceActiveJourneyIfNeeded()
            _ = try await createItinerary(
                input: CreateItinerarySubscriptionRequest(
                    originCrs: itinerary.originCrs,
                    destinationCrs: itinerary.destinationCrs,
                    departureStart: departureStart,
                    windowMinutes: itinerary.windowMinutes,
                    maxChanges: itinerary.maxChanges,
                    limit: itinerary.limit,
                    selectedItineraryStableKey: stableKey
                )
            )
            BetaDiagnostics.record("active_itinerary_switched")
        }
    }

    func replaceActiveJourneyIfNeeded() async throws {
        guard activeWindowID != nil || activeItineraryID != nil else {
            return
        }
        guard let accessToken = accessTokenProvider() else {
            throw ActiveWindowViewModelError.missingAccessToken
        }
        if let activeWindowID {
            try await apiClient.deleteWindowSubscription(
                id: activeWindowID,
                accessToken: accessToken,
                idempotencyKey: UUID().uuidString
            )
        }
        if let activeItineraryID {
            try await apiClient.deleteItinerarySubscription(
                id: activeItineraryID,
                accessToken: accessToken,
                idempotencyKey: UUID().uuidString
            )
        }
        clearState()
        await liveActivityCoordinator.endAll(tokenRegistration: liveActivityTokenRegistrationContext())
    }

    func togglePinnedLiveActivity(for recommendation: DirectWindowRecommendation) async {
        guard let activeWindow else {
            pinnedLiveActivityServiceID = nil
            await liveActivityCoordinator.endAll(tokenRegistration: liveActivityTokenRegistrationContext())
            return
        }

        if pinnedLiveActivityServiceID == recommendation.journey.serviceId {
            await clearPinnedTrain(windowID: activeWindow.id)
        } else {
            await pinTrain(serviceID: recommendation.journey.serviceId, windowID: activeWindow.id)
        }
    }

    func pinTrain(serviceID: Int, windowID: String? = nil) async {
        await pinTrain(serviceID: serviceID, windowID: windowID, showErrors: true)
    }

    private func pinTrain(serviceID: Int, windowID: String? = nil, showErrors: Bool) async {
        guard accessTokenProvider() != nil,
              let targetWindowID = windowID ?? activeWindowID else {
            return
        }
        await optimisticallyPinTrain(serviceID: serviceID, windowID: targetWindowID)
        await enqueueAndFlush(
            JourneyMutation(
                kind: .windowPinTrain,
                windowID: targetWindowID,
                serviceID: serviceID
            ),
            showErrors: showErrors
        )
    }

    func clearPinnedTrain(windowID: String? = nil) async {
        guard accessTokenProvider() != nil,
              let targetWindowID = windowID ?? activeWindowID else {
            pinnedLiveActivityServiceID = nil
            return
        }
        await optimisticallyClearPinnedTrain(windowID: targetWindowID)
        await enqueueAndFlush(
            JourneyMutation(kind: .windowClearPinnedTrain, windowID: targetWindowID),
            showErrors: true
        )
    }

    func clearPinnedTrainOrDeleteArrivedJourney(windowID: String? = nil, serviceID: Int) async {
        let targetWindowID = windowID ?? activeWindowID
        if let window = activeWindow,
           targetWindowID == nil || window.id == targetWindowID,
           let recommendation = Self.recommendation(in: window, serviceID: serviceID),
           JourneyFormatting.isArrived(recommendation.journey) {
            await deleteActiveWindow()
            return
        }
        await clearPinnedTrain(windowID: targetWindowID)
    }

    func pinItineraryFirstLeg(_ leg: ItineraryLeg, itineraryID: String? = nil) async {
        guard accessTokenProvider() != nil,
              let targetItineraryID = itineraryID ?? activeItineraryID else {
            return
        }
        let pin = PinItineraryFirstLegRequest(serviceId: leg.serviceId, rid: leg.rid, ssd: leg.ssd)
        await optimisticallyPinItineraryFirstLeg(pin, itineraryID: targetItineraryID)
        await enqueueAndFlush(
            JourneyMutation(
                kind: .itineraryPinFirstLeg,
                itineraryID: targetItineraryID,
                firstLegPin: pin
            ),
            showErrors: true
        )
    }

    func clearItineraryPinnedFirstLeg(itineraryID: String? = nil) async {
        guard accessTokenProvider() != nil,
              let targetItineraryID = itineraryID ?? activeItineraryID else {
            return
        }
        await optimisticallyClearItineraryPinnedFirstLeg(itineraryID: targetItineraryID)
        await enqueueAndFlush(
            JourneyMutation(kind: .itineraryClearPinnedFirstLeg, itineraryID: targetItineraryID),
            showErrors: true
        )
    }

    /// User explicitly says "I'm on this train" for the given leg. For the
    /// first leg this also pins the train server-side; for an onward leg
    /// it advances `phase` and `currentLegIndex` only.
    func boardItineraryLeg(_ legIndex: Int, itineraryID: String? = nil, pinFirstLeg: Bool = true) async {
        guard accessTokenProvider() != nil,
              let targetItineraryID = itineraryID ?? activeItineraryID else {
            return
        }
        await optimisticallyBoardItineraryLeg(legIndex, itineraryID: targetItineraryID, pinFirstLeg: pinFirstLeg)
        await enqueueAndFlush(
            JourneyMutation(
                kind: .itineraryBoardLeg,
                itineraryID: targetItineraryID,
                legIndex: legIndex,
                pinFirstLeg: pinFirstLeg
            ),
            showErrors: true
        )
    }

    /// User taps "Not on this train" mid-journey. Re-plans the itinerary
    /// using `fromCrs` as the new origin and resets phase to planning.
    func replanItineraryFromCurrentStation(fromCrs: String, itineraryID: String? = nil) async {
        let trimmed = fromCrs.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmed.isEmpty,
              accessTokenProvider() != nil,
              let targetItineraryID = itineraryID ?? activeItineraryID else {
            return
        }
        await enqueueAndFlush(
            JourneyMutation(
                kind: .itineraryReplanFromCurrentStation,
                itineraryID: targetItineraryID,
                fromCrs: trimmed
            ),
            showErrors: true
        )
    }

    func markDepartedPromptHandled(serviceID: Int, windowID: String? = nil) {
        guard let key = departedPromptKey(windowID: windowID, serviceID: serviceID) else {
            return
        }
        handledDepartedPromptKeys.insert(key)
    }

    func hasHandledDepartedPrompt(windowID: String? = nil, serviceID: Int) -> Bool {
        guard let key = departedPromptKey(windowID: windowID, serviceID: serviceID) else {
            return false
        }
        return handledDepartedPromptKeys.contains(key)
    }

    func deleteActiveWindow() async {
        guard let id = activeWindowID, accessTokenProvider() != nil else {
            clearWindowState()
            return
        }
        mutationQueue.enqueue(JourneyMutation(kind: .windowDelete, windowID: id))
        scheduleQueuedMutationRetryIfNeeded()
        clearWindowState()
        await liveActivityCoordinator.endAll(tokenRegistration: liveActivityTokenRegistrationContext())
        await flushQueuedMutations()
    }

    func deleteActiveItinerary() async {
        guard let id = activeItineraryID, accessTokenProvider() != nil else {
            clearItineraryState()
            return
        }
        mutationQueue.enqueue(JourneyMutation(kind: .itineraryDelete, itineraryID: id))
        scheduleQueuedMutationRetryIfNeeded()
        clearItineraryState()
        await liveActivityCoordinator.endAll(tokenRegistration: liveActivityTokenRegistrationContext())
        await flushQueuedMutations()
    }

    func flushQueuedMutations() async {
        mutationQueue.purgeExpired()
        guard !mutationQueue.isSyncing,
              let accessToken = accessTokenProvider() else {
            return
        }
        guard !connectivityService.backendUnavailable else {
            scheduleQueuedMutationRetryIfNeeded()
            return
        }

        let dueMutations = mutationQueue.duePendingMutations()
        guard !dueMutations.isEmpty else {
            scheduleQueuedMutationRetryIfNeeded()
            return
        }

        mutationQueue.setSyncing(true)
        defer {
            mutationQueue.setSyncing(false)
            scheduleQueuedMutationRetryIfNeeded()
        }

        for mutation in dueMutations {
            guard accessTokenProvider() != nil else {
                return
            }
            mutationQueue.markAttempt(id: mutation.id)
            do {
                try await performQueuedMutation(mutation, accessToken: accessToken)
                mutationQueue.remove(id: mutation.id)
                connectivityService.recordSuccessfulBackendContact()
            } catch let apiError as APIError where apiError.requiresSignIn {
                connectivityService.recordBackendFailure(apiError)
                mutationQueue.markDeferred(id: mutation.id, message: apiError.localizedDescription)
                operationState.handleOperationError(apiError)
                return
            } catch let apiError as APIError where apiError.isAuthFailure {
                connectivityService.recordBackendFailure(apiError)
                mutationQueue.markDeferred(id: mutation.id, message: apiError.localizedDescription)
                return
            } catch let apiError as APIError where apiError.isClientFailure {
                connectivityService.recordBackendFailure(apiError)
                mutationQueue.markFailed(id: mutation.id, message: apiError.localizedDescription)
                await reconcileActiveJourneyAfterFailedMutation(accessToken: accessToken)
            } catch {
                connectivityService.recordBackendFailure(error)
                mutationQueue.markDeferred(id: mutation.id, message: error.localizedDescription)
                return
            }
        }
    }

    private func enqueueAndFlush(_ mutation: JourneyMutation, showErrors: Bool) async {
        mutationQueue.enqueue(mutation)
        scheduleQueuedMutationRetryIfNeeded()
        await flushQueuedMutations()
        if !showErrors, mutationQueue.needsAttention {
            BetaDiagnostics.record("journey_mutation_needs_attention")
        }
    }

    private func scheduleQueuedMutationRetryIfNeeded() {
        guard mutationQueue.hasPendingWork else {
            return
        }
        BackgroundSyncScheduler.shared.schedule()
    }

    private func optimisticallyPinTrain(serviceID: Int, windowID: String) async {
        guard var window = activeWindow, window.id == windowID else {
            pinnedLiveActivityServiceID = serviceID
            return
        }
        window.pinnedTrainServiceId = serviceID
        await applyActiveWindow(window, previousWindow: activeWindow)
    }

    private func optimisticallyMarkCaughtTrain(serviceID: Int, windowID: String) async {
        guard var window = activeWindow, window.id == windowID else {
            pinnedLiveActivityServiceID = serviceID
            return
        }
        window.pinnedTrainServiceId = serviceID
        window.selectedRecommendation = Self.markDepartedIfMatching(window.selectedRecommendation, serviceID: serviceID)
        window.recommendations = window.recommendations.map {
            Self.markDepartedIfMatching($0, serviceID: serviceID)
        }
        await applyActiveWindow(window, previousWindow: activeWindow)
    }

    private static func markDepartedIfMatching(_ recommendation: DirectWindowRecommendation, serviceID: Int) -> DirectWindowRecommendation {
        guard recommendation.journey.serviceId == serviceID else {
            return recommendation
        }
        var updated = recommendation
        updated.journey.movementPhase = "departed"
        updated.journey.reportState = "origin_reported"
        updated.journey.statusKind = "departed"
        updated.journey.statusText = "Departed"
        updated.journey.compactStatusText = "Departed"
        if updated.journey.displayStatus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            updated.journey.displayStatus = "on_time"
        }
        return updated
    }

    private func optimisticallyClearPinnedTrain(windowID: String) async {
        guard var window = activeWindow, window.id == windowID else {
            pinnedLiveActivityServiceID = nil
            return
        }
        window.pinnedTrainServiceId = nil
        await applyActiveWindow(window, previousWindow: activeWindow)
    }

    private func optimisticallyPinItineraryFirstLeg(_ pin: PinItineraryFirstLegRequest, itineraryID: String) async {
        guard var itinerary = activeItinerary, itinerary.id == itineraryID else {
            return
        }
        itinerary.pinnedFirstLeg = pinnedFirstLeg(from: pin, itinerary: itinerary)
        await applyActiveItinerary(itinerary)
    }

    private func optimisticallyClearItineraryPinnedFirstLeg(itineraryID: String) async {
        guard var itinerary = activeItinerary, itinerary.id == itineraryID else {
            return
        }
        itinerary.pinnedFirstLeg = nil
        await applyActiveItinerary(itinerary)
    }

    private func optimisticallyReportItineraryOriginArrival(itineraryID: String) async {
        guard var itinerary = activeItinerary, itinerary.id == itineraryID else {
            return
        }
        itinerary.phase = ItineraryPhase.atOrigin.rawValue
        itinerary.currentLegIndex = 0
        await applyActiveItinerary(itinerary)
    }

    private func optimisticallyReportItineraryInterchangeArrival(itineraryID: String, legIndex: Int) async {
        guard var itinerary = activeItinerary, itinerary.id == itineraryID else {
            return
        }
        itinerary.phase = ItineraryPhase.approachingInterchange.rawValue
        itinerary.currentLegIndex = legIndex
        await applyActiveItinerary(itinerary)
    }

    private func optimisticallyBoardItineraryLeg(_ legIndex: Int, itineraryID: String, pinFirstLeg: Bool) async {
        guard var itinerary = activeItinerary,
              itinerary.id == itineraryID,
              legIndex >= 0,
              legIndex < itinerary.selectedItinerary.legs.count else {
            return
        }
        if legIndex == 0 && pinFirstLeg, itinerary.pinnedFirstLeg == nil {
            let leg = itinerary.selectedItinerary.legs[0]
            itinerary.pinnedFirstLeg = pinnedFirstLeg(
                from: PinItineraryFirstLegRequest(serviceId: leg.serviceId, rid: leg.rid, ssd: leg.ssd),
                itinerary: itinerary
            )
        }
        itinerary.currentLegIndex = legIndex
        itinerary.phase = legIndex == itinerary.selectedItinerary.legs.count - 1
            ? ItineraryPhase.onFinalLeg.rawValue
            : ItineraryPhase.onLeg.rawValue
        await applyActiveItinerary(itinerary)
    }

    private func pinnedFirstLeg(from pin: PinItineraryFirstLegRequest, itinerary: ItinerarySubscription) -> ItineraryPinnedFirstLeg {
        guard let leg = itinerary.selectedItinerary.legs.first(where: {
            $0.serviceId == pin.serviceId && $0.rid == pin.rid && $0.ssd == pin.ssd
        }) else {
            return ItineraryPinnedFirstLeg(
                serviceId: pin.serviceId,
                rid: pin.rid,
                ssd: pin.ssd,
                originTpl: nil,
                originCrs: nil,
                originName: nil,
                destinationTpl: nil,
                destinationCrs: nil,
                destinationName: nil,
                scheduledDeparture: nil,
                scheduledArrival: nil,
                expectedDeparture: nil,
                expectedArrival: nil
            )
        }
        return ItineraryPinnedFirstLeg(
            serviceId: leg.serviceId,
            rid: leg.rid,
            ssd: leg.ssd,
            originTpl: leg.originTpl,
            originCrs: leg.originCrs,
            originName: leg.originName,
            destinationTpl: leg.destinationTpl,
            destinationCrs: leg.destinationCrs,
            destinationName: leg.destinationName,
            scheduledDeparture: leg.scheduledDeparture,
            scheduledArrival: leg.scheduledArrival,
            expectedDeparture: leg.expectedDeparture,
            expectedArrival: leg.expectedArrival
        )
    }

    private func performQueuedMutation(_ mutation: JourneyMutation, accessToken: String) async throws {
        switch mutation.kind {
        case .windowPinTrain:
            guard let windowID = mutation.windowID, let serviceID = mutation.serviceID else {
                throw ActiveWindowViewModelError.invalidQueuedMutation
            }
            let subscription = try await apiClient.pinWindowSubscriptionTrain(
                id: windowID,
                serviceID: serviceID,
                accessToken: accessToken,
                idempotencyKey: mutation.id
            )
            await applyActiveWindow(subscription, previousWindow: activeWindow)
        case .windowClearPinnedTrain:
            guard let windowID = mutation.windowID else {
                throw ActiveWindowViewModelError.invalidQueuedMutation
            }
            let subscription = try await apiClient.clearWindowSubscriptionPinnedTrain(
                id: windowID,
                accessToken: accessToken,
                idempotencyKey: mutation.id
            )
            await applyActiveWindow(subscription, previousWindow: activeWindow)
        case .windowDelete:
            guard let windowID = mutation.windowID else {
                throw ActiveWindowViewModelError.invalidQueuedMutation
            }
            do {
                try await apiClient.deleteWindowSubscription(
                    id: windowID,
                    accessToken: accessToken,
                    idempotencyKey: mutation.id
                )
            } catch let apiError as APIError where apiError.isNotFound {
                clearWindowState()
                return
            }
            clearWindowState()
        case .itineraryPinFirstLeg:
            guard let itineraryID = mutation.itineraryID, let input = mutation.firstLegPin else {
                throw ActiveWindowViewModelError.invalidQueuedMutation
            }
            let subscription = try await apiClient.pinItineraryFirstLeg(
                id: itineraryID,
                input: input,
                accessToken: accessToken,
                idempotencyKey: mutation.id
            )
            await applyActiveItinerary(subscription)
        case .itineraryClearPinnedFirstLeg:
            guard let itineraryID = mutation.itineraryID else {
                throw ActiveWindowViewModelError.invalidQueuedMutation
            }
            let subscription = try await apiClient.clearItineraryPinnedFirstLeg(
                id: itineraryID,
                accessToken: accessToken,
                idempotencyKey: mutation.id
            )
            await applyActiveItinerary(subscription)
        case .itineraryReportOriginArrival:
            guard let itineraryID = mutation.itineraryID else {
                throw ActiveWindowViewModelError.invalidQueuedMutation
            }
            let subscription = try await apiClient.reportItineraryOriginArrival(
                id: itineraryID,
                accessToken: accessToken,
                idempotencyKey: mutation.id
            )
            await applyActiveItinerary(subscription)
        case .itineraryReportInterchangeArrival:
            guard let itineraryID = mutation.itineraryID,
                  let atCrs = mutation.atCrs,
                  let legIndex = mutation.legIndex else {
                throw ActiveWindowViewModelError.invalidQueuedMutation
            }
            let subscription = try await apiClient.reportItineraryInterchangeArrival(
                id: itineraryID,
                atCrs: atCrs,
                legIndex: legIndex,
                accessToken: accessToken,
                idempotencyKey: mutation.id
            )
            await applyActiveItinerary(subscription)
        case .itineraryBoardLeg:
            guard let itineraryID = mutation.itineraryID, let legIndex = mutation.legIndex else {
                throw ActiveWindowViewModelError.invalidQueuedMutation
            }
            let subscription = try await apiClient.boardItineraryLeg(
                id: itineraryID,
                legIndex: legIndex,
                pinFirstLeg: mutation.pinFirstLeg ?? true,
                accessToken: accessToken,
                idempotencyKey: mutation.id
            )
            await applyActiveItinerary(subscription)
        case .itineraryReplanFromCurrentStation:
            guard let itineraryID = mutation.itineraryID, let fromCrs = mutation.fromCrs else {
                throw ActiveWindowViewModelError.invalidQueuedMutation
            }
            let subscription = try await apiClient.replanItineraryFromCurrentStation(
                id: itineraryID,
                fromCrs: fromCrs,
                accessToken: accessToken,
                idempotencyKey: mutation.id
            )
            await applyActiveItinerary(subscription)
        case .itineraryDelete:
            guard let itineraryID = mutation.itineraryID else {
                throw ActiveWindowViewModelError.invalidQueuedMutation
            }
            do {
                try await apiClient.deleteItinerarySubscription(
                    id: itineraryID,
                    accessToken: accessToken,
                    idempotencyKey: mutation.id
                )
            } catch let apiError as APIError where apiError.isNotFound {
                clearItineraryState()
                return
            }
            clearItineraryState()
        }
    }

    private func reconcileActiveJourneyAfterFailedMutation(accessToken: String) async {
        do {
            try await loadActiveJourney(accessToken: accessToken)
            connectivityService.recordSuccessfulBackendContact()
        } catch {
            connectivityService.recordBackendFailure(error)
            operationState.recordSilentOperationError(error)
        }
    }

    func openWindowDeepLink(windowID: String) async {
        if activeWindowID != windowID {
            activeWindowStreamLastEventID = nil
        }
        activeWindowID = windowID
        await refreshActiveWindow()
    }

    func clearState() {
        onboardArrivalClearTask?.cancel()
        onboardArrivalClearTask = nil
        activeWindow = nil
        activeWindowID = nil
        activeWindowStreamLastEventID = nil
        activeItinerary = nil
        activeItineraryID = nil
        activeItineraryStreamLastEventID = nil
        pinnedLiveActivityServiceID = nil
        handledDepartedPromptKeys = []
        activeJourneyCache.clear()
        activeJourneyCache.clearWindowStreamCursors()
        activeJourneyCache.clearItineraryStreamCursors()
        didClearActiveWindowState?()
    }

    func clearStateAndEndLiveActivities() async {
        clearState()
        await liveActivityCoordinator.unregisterRemoteStart(tokenRegistration: liveActivityTokenRegistrationContext())
        await liveActivityCoordinator.endAll(tokenRegistration: liveActivityTokenRegistrationContext())
    }

    func endAllLiveActivitiesWithTokenIfPossible() async {
        await liveActivityCoordinator.unregisterRemoteStart(tokenRegistration: liveActivityTokenRegistrationContext())
        await liveActivityCoordinator.endAll(tokenRegistration: liveActivityTokenRegistrationContext())
    }

    func prepareLiveActivityRemoteStartRegistration() async {
        await liveActivityCoordinator.prepareForRemoteStart(tokenRegistration: liveActivityTokenRegistrationContext())
    }

    func previewLiveActivity() async {
        let didStart = await liveActivityCoordinator.previewLiveActivity()
        if didStart {
            operationState.alertState = nil
        } else {
            operationState.alertState = .validation("Live Activity previews are unavailable on this device or in the current simulator state.")
        }
    }

    func reconcileLiveActivityIntentActions() async {
        guard accessTokenProvider() != nil else {
            return
        }
        let actions = LiveActivityIntentActionStore.drainPendingActions()
        guard !actions.isEmpty else {
            return
        }

        for action in actions {
            switch action.kind {
            case .pinTrain:
                guard let serviceID = action.serviceID, serviceID > 0 else {
                    continue
                }
                await pinTrain(serviceID: serviceID, windowID: action.windowSubscriptionID)
            case .snoozeAlerts:
                if let snoozedUntil = action.snoozedUntil, snoozedUntil > Date() {
                    LiveActivityIntentActionStore.alertsSnoozedUntil = snoozedUntil
                }
            }
        }
    }

    func activeWindowPollingInterval(now: Date = Date()) -> Duration? {
        Self.activeWindowPollingInterval(for: activeWindow, activeWindowID: activeWindowID, now: now)
    }

    var hasActiveJourney: Bool {
        activeWindow != nil || activeItinerary != nil
    }

    static func activeWindowPollingInterval(
        for window: WindowSubscription?,
        activeWindowID: String?,
        now: Date
    ) -> Duration? {
        guard activeWindowID != nil else {
            return nil
        }
        guard let window,
              let departureStart = DateFormatting.date(from: window.departureStart) else {
            return activeWindowFallbackPollingInterval
        }

        let staleEnd = departureStart.addingTimeInterval(
            TimeInterval(window.windowMinutes) * 60 + activeWindowStaleGraceSeconds
        )
        guard now < staleEnd else {
            return nil
        }

        let secondsUntilDeparture = departureStart.timeIntervalSince(now)
        if secondsUntilDeparture > 60 * 60 {
            return activeWindowDistantPollingInterval
        }
        if secondsUntilDeparture > 15 * 60 {
            return activeWindowApproachingPollingInterval
        }
        return activeWindowImminentPollingInterval
    }

    private func performActiveWindowRefresh(showLoading: Bool, showAlertOnFailure: Bool = true) async {
        guard let accessToken = accessTokenProvider() else {
            return
        }

        let operation = {
            do {
                try await self.loadActiveJourney(accessToken: accessToken)
                self.connectivityService.recordSuccessfulBackendContact()
            } catch {
                self.connectivityService.recordBackendFailure(error)
                throw error
            }
        }

        if showLoading {
            if showAlertOnFailure {
                await operationState.withLoading(operation)
            } else {
                await operationState.withLoadingSilently(operation)
            }
        } else {
            do {
                try await operation()
            } catch {
                if showAlertOnFailure {
                    operationState.handleOperationError(error)
                } else {
                    operationState.recordSilentOperationError(error)
                }
            }
        }
    }

    private func loadActiveJourney(accessToken: String) async throws {
        if activeWindowID != nil || activeItineraryID == nil {
            try await loadActiveWindow(accessToken: accessToken)
        }
        if let activeItineraryID {
            try await loadActiveItinerary(id: activeItineraryID, accessToken: accessToken)
        } else if activeWindowID == nil {
            try await loadActiveItinerary(id: nil, accessToken: accessToken)
        }
    }

    private func loadActiveWindow(accessToken: String) async throws {
        let subscription: WindowSubscription
        do {
            if let id = activeWindowID {
                do {
                    subscription = try await apiClient.getWindowSubscription(id: id, accessToken: accessToken)
                } catch let apiError as APIError where apiError.isNotFound {
                    subscription = try await apiClient.getActiveWindowSubscription(accessToken: accessToken)
                }
            } else {
                subscription = try await apiClient.getActiveWindowSubscription(accessToken: accessToken)
            }
        } catch let apiError as APIError where apiError.isNotFound {
            clearWindowState()
            await liveActivityCoordinator.endAll(tokenRegistration: liveActivityTokenRegistrationContext())
            return
        }

        await applyActiveWindow(subscription, previousWindow: activeWindow)
    }

    private func loadActiveItinerary(id: String?, accessToken: String) async throws {
        do {
            let subscription: ItinerarySubscription
            if let id {
                subscription = try await apiClient.getItinerarySubscription(id: id, accessToken: accessToken)
            } else {
                subscription = try await apiClient.getActiveItinerarySubscription(accessToken: accessToken)
            }
            if subscription.isActive {
                await applyActiveItinerary(subscription)
            } else {
                clearItineraryState()
            }
        } catch let apiError as APIError where apiError.isNotFound {
            clearItineraryState()
        }
    }

    private func applyActiveWindow(_ subscription: WindowSubscription, previousWindow: WindowSubscription?) async {
        var updatedSubscription = subscription
        if mutationQueue.hasPendingDelete(windowID: updatedSubscription.id) {
            if activeWindowID == updatedSubscription.id || activeWindow?.id == updatedSubscription.id {
                clearWindowState()
            }
            return
        }
        // A refresh can race an unsynced pin: the fetch reflects server state
        // from before the queued mutation lands. Keep the local intent on top.
        switch mutationQueue.pendingWindowPinOverride(windowID: updatedSubscription.id) {
        case .pin(let serviceID):
            updatedSubscription.pinnedTrainServiceId = serviceID
        case .clear:
            updatedSubscription.pinnedTrainServiceId = nil
        case nil:
            break
        }
        if updatedSubscription.isActive {
            if previousWindow?.id == updatedSubscription.id,
               previousWindow?.phase == "at_origin" {
                updatedSubscription.phase = "at_origin"
            } else if pendingOriginEntryWindowID == updatedSubscription.id {
                updatedSubscription.phase = "at_origin"
                pendingOriginEntryWindowID = nil
                BetaDiagnostics.record("station_proximity_origin_entered", details: updatedSubscription.originCrs)
            } else if updatedSubscription.phase == nil {
                updatedSubscription.phase = "window"
            }
            if activeWindowID != updatedSubscription.id {
                activeWindowStreamLastEventID = nil
                handledDepartedPromptKeys = handledDepartedPromptKeys.filter { $0.hasPrefix("\(updatedSubscription.id)|") }
            }
            pinnedLiveActivityServiceID = normalizedPinnedServiceID(updatedSubscription.pinnedTrainServiceId)
            clearItineraryState()
            activeWindow = updatedSubscription
            activeWindowID = updatedSubscription.id
            activeJourneyCache.save(window: updatedSubscription)
            liveRefreshGeneration += 1
            emitFeedbackIfNeeded(previous: previousWindow, current: updatedSubscription)
            await liveActivityCoordinator.sync(
                window: updatedSubscription,
                pinnedTrainServiceID: pinnedLiveActivityServiceID,
                tokenRegistration: liveActivityTokenRegistrationContext()
            )
            stationProximityMonitor.monitorOriginStation(for: updatedSubscription, requestPermissionIfNeeded: false)
            await scheduleOnboardArrivalClearIfNeeded(for: updatedSubscription)
        } else {
            clearWindowState()
            await liveActivityCoordinator.endAll(tokenRegistration: liveActivityTokenRegistrationContext())
        }
    }

    private func markNearOriginStation(windowID: String) async {
        guard var window = activeWindow,
              window.id == windowID else {
            pendingOriginEntryWindowID = windowID
            return
        }
        guard window.phase != "at_origin" else {
            return
        }
        pendingOriginEntryWindowID = nil
        window.phase = "at_origin"
        activeWindow = window
        activeJourneyCache.save(window: window)
        liveRefreshGeneration += 1
        BetaDiagnostics.record("station_proximity_origin_entered", details: window.originCrs)
        await liveActivityCoordinator.sync(
            window: window,
            pinnedTrainServiceID: pinnedLiveActivityServiceID,
            tokenRegistration: liveActivityTokenRegistrationContext()
        )
    }

    private func markCaughtTrainByDetection(windowID: String, serviceID: Int) async {
        guard let window = activeWindow,
              window.id == windowID,
              serviceID > 0,
              pinnedLiveActivityServiceID == nil,
              automaticCaughtDetectionIsRelevant(window: window, serviceID: serviceID, now: Date()) else {
            return
        }

        BetaDiagnostics.record("station_proximity_caught_train_detected", details: "\(window.originCrs); service=\(serviceID)")
        await optimisticallyMarkCaughtTrain(serviceID: serviceID, windowID: windowID)
        await enqueueAndFlush(
            JourneyMutation(
                kind: .windowPinTrain,
                windowID: windowID,
                serviceID: serviceID
            ),
            showErrors: false
        )
    }

    private func automaticCaughtDetectionIsRelevant(window: WindowSubscription, serviceID: Int, now: Date) -> Bool {
        let recommendations = window.recommendations.isEmpty ? [window.selectedRecommendation] : window.recommendations
        guard let recommendation = recommendations.first(where: { $0.journey.serviceId == serviceID }),
              !isCancellation(recommendation) else {
            return false
        }
        let departure = JourneyFormatting.departureDisplay(recommendation.journey)
        guard let departureDate = departure.currentDate ?? departure.scheduledDate else {
            return false
        }
        return now >= departureDate.addingTimeInterval(-(2 * 60)) &&
            now <= departureDate.addingTimeInterval(25 * 60)
    }

    private func applyActiveItinerary(_ subscription: ItinerarySubscription) async {
        var subscription = subscription
        if mutationQueue.hasPendingDelete(itineraryID: subscription.id) {
            if activeItineraryID == subscription.id || activeItinerary?.id == subscription.id {
                clearItineraryState()
            }
            return
        }
        // Keep an unsynced first-leg pin (or clear) on top of fetched state so
        // a racing refresh can't undo the user's action before the queue syncs.
        if let override = mutationQueue.pendingItineraryFirstLegPinOverride(itineraryID: subscription.id) {
            if let pin = override {
                subscription.pinnedFirstLeg = pinnedFirstLeg(from: pin, itinerary: subscription)
            } else {
                subscription.pinnedFirstLeg = nil
            }
        }
        if subscription.isActive {
            let isNew = activeItineraryID != subscription.id
            if isNew {
                activeItineraryStreamLastEventID = nil
            }
            clearWindowState()
            activeItinerary = subscription
            activeItineraryID = subscription.id
            activeJourneyCache.save(itinerary: subscription)
            liveRefreshGeneration += 1
            await liveActivityCoordinator.sync(
                itinerary: subscription,
                tokenRegistration: liveActivityTokenRegistrationContext()
            )
            // Permission flow already requested for windows; itineraries
            // piggyback on the same Always grant. Only re-prompt on first
            // assignment to avoid pestering the user on every refresh.
            stationProximityMonitor.monitorItineraryPhase(
                subscription.resolvedPhase,
                for: subscription,
                requestPermissionIfNeeded: isNew
            )
        } else {
            clearItineraryState()
            await liveActivityCoordinator.endAll(tokenRegistration: liveActivityTokenRegistrationContext())
        }
    }

    private func markItineraryAtOrigin(itineraryID: String) async {
        guard activeItinerary?.id == itineraryID,
              accessTokenProvider() != nil else {
            return
        }
        if activeItinerary?.resolvedPhase == .atOrigin {
            return
        }
        BetaDiagnostics.record("itinerary_origin_entered", details: itineraryID)
        await optimisticallyReportItineraryOriginArrival(itineraryID: itineraryID)
        await enqueueAndFlush(
            JourneyMutation(kind: .itineraryReportOriginArrival, itineraryID: itineraryID),
            showErrors: false
        )
    }

    private func markItineraryApproachingInterchange(itineraryID: String, legIndex: Int, atCrs: String) async {
        guard let active = activeItinerary,
              active.id == itineraryID,
              accessTokenProvider() != nil else {
            return
        }
        if active.resolvedPhase == .approachingInterchange {
            return
        }
        let crs = atCrs.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !crs.isEmpty else {
            return
        }
        BetaDiagnostics.record("itinerary_interchange_entered", details: "\(itineraryID);leg=\(legIndex);crs=\(crs)")
        notificationFeedbackGenerator.notificationOccurred(.warning)

        // Post a local interchange notification so the user sees a
        // banner even if the app is backgrounded when the geofence fires.
        let stationName: String = {
            if let connection = active.nextConnection {
                return JourneyFormatting.stationDisplayName(name: connection.atName, fallback: connection.atCrs)
            }
            return crs
        }()
        let notificationTitle = active.nextConnection.map(ItineraryFormatting.connectionTitleText)
        let onwardPlatform = active.onwardLeg.flatMap { leg -> String? in
            let candidate = leg.realtimePlatform?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? leg.originPlatform?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let candidate, !candidate.isEmpty else { return nil }
            return candidate
        }
        let onwardDeparture = active.onwardLeg.map { leg in
            ItineraryFormatting.timeText(leg.expectedDeparture ?? leg.scheduledDeparture)
        }
        LocalInterchangeNotification.schedule(
            itineraryID: itineraryID,
            legIndex: legIndex,
            stationName: stationName,
            title: notificationTitle,
            onwardPlatform: onwardPlatform,
            onwardDeparture: onwardDeparture
        )

        await optimisticallyReportItineraryInterchangeArrival(itineraryID: itineraryID, legIndex: legIndex)
        await enqueueAndFlush(
            JourneyMutation(
                kind: .itineraryReportInterchangeArrival,
                itineraryID: itineraryID,
                legIndex: legIndex,
                atCrs: crs
            ),
            showErrors: false
        )
    }

    private func markItineraryOnwardBoardedByDetection(itineraryID: String, legIndex: Int) async {
        // Silent fallback: only advance the phase if the user never
        // explicitly tapped "I'm on this train". Don't auto-pin a
        // service ID with the server.
        guard let active = activeItinerary,
              active.id == itineraryID,
              accessTokenProvider() != nil else {
            return
        }
        let alreadyOnLeg = active.resolvedPhase == .onLeg || active.resolvedPhase == .onFinalLeg
        if alreadyOnLeg && active.currentLegIndex == legIndex {
            return
        }
        BetaDiagnostics.record("itinerary_onward_board_detected", details: "\(itineraryID);leg=\(legIndex)")
        await optimisticallyBoardItineraryLeg(legIndex, itineraryID: itineraryID, pinFirstLeg: false)
        await enqueueAndFlush(
            JourneyMutation(
                kind: .itineraryBoardLeg,
                itineraryID: itineraryID,
                legIndex: legIndex,
                pinFirstLeg: false
            ),
            showErrors: false
        )
    }

    private func runActiveWindowDiscoveryLoop() async {
        while !Task.isCancelled {
            await performActiveWindowRefresh(showLoading: false, showAlertOnFailure: false)
            guard activeWindowID == nil else {
                return
            }
            guard await sleep(for: Self.activeWindowDiscoveryPollingInterval) else {
                return
            }
        }
    }

    private func runActiveWindowHeartbeatFallback() async {
        while !Task.isCancelled {
            guard let interval = activeJourneyPollingInterval() else {
                return
            }
            guard await sleep(for: interval) else {
                return
            }
            guard !Task.isCancelled, activeWindowID != nil || activeItineraryID != nil else {
                return
            }
            await performActiveWindowRefresh(showLoading: false, showAlertOnFailure: false)
        }
    }

    private func runActiveWindowStreamReconnectLoop() async {
        guard activeWindowID != nil else {
            await runActiveItineraryStreamReconnectLoop()
            return
        }
        var backoff = ActiveWindowStreamBackoff()

        while !Task.isCancelled {
            guard let windowID = activeWindowID, let accessToken = accessTokenProvider() else {
                return
            }
            await performActiveWindowRefresh(showLoading: false, showAlertOnFailure: false)
            guard activeWindowID == windowID, accessTokenProvider() == accessToken else {
                return
            }

            do {
                let stream = apiClient.streamWindowSubscriptionEvents(
                    windowSubscriptionID: windowID,
                    accessToken: accessToken,
                    lastEventID: activeWindowStreamLastEventID ?? activeJourneyCache.streamCursor(forWindow: windowID)
                )
                for try await event in stream {
                    guard !Task.isCancelled else {
                        return
                    }
                    connectivityService.recordSuccessfulBackendContact()
                    backoff.reset()
                    await flushQueuedMutations()
                    guard activeWindowID == windowID, accessTokenProvider() == accessToken else {
                        return
                    }
                    if let eventID = event.id, !eventID.isEmpty {
                        activeWindowStreamLastEventID = eventID
                        activeJourneyCache.saveStreamCursor(eventID, forWindow: windowID)
                    }
                    guard shouldRefreshActiveWindow(for: event, windowID: windowID) else {
                        continue
                    }
                    scheduleCoalescedStreamRefresh()
                }

                let delay = backoff.nextDelay()
                BetaDiagnostics.record("active_window_stream_disconnected", details: "reconnecting_in=\(delay)")
                guard await sleep(for: delay) else {
                    return
                }
            } catch {
                guard !Task.isCancelled else {
                    return
                }
                connectivityService.recordBackendFailure(error)
                let delay = activeWindowStreamReconnectDelay(after: error, backoff: &backoff)
                BetaDiagnostics.record("active_window_stream_error", details: "\(error.localizedDescription); reconnecting_in=\(delay)")
                guard await sleep(for: delay) else {
                    return
                }
            }
        }
    }

    private func runActiveItineraryStreamReconnectLoop() async {
        var backoff = ActiveWindowStreamBackoff()

        while !Task.isCancelled {
            guard let itineraryID = activeItineraryID, let accessToken = accessTokenProvider() else {
                return
            }

            do {
                let stream = apiClient.streamItinerarySubscriptionEvents(
                    itinerarySubscriptionID: itineraryID,
                    accessToken: accessToken,
                    lastEventID: activeItineraryStreamLastEventID ?? activeJourneyCache.streamCursor(forItinerary: itineraryID)
                )
                for try await event in stream {
                    guard !Task.isCancelled else {
                        return
                    }
                    connectivityService.recordSuccessfulBackendContact()
                    backoff.reset()
                    await flushQueuedMutations()
                    guard activeItineraryID == itineraryID, accessTokenProvider() == accessToken else {
                        return
                    }
                    if let eventID = event.id, !eventID.isEmpty {
                        activeItineraryStreamLastEventID = eventID
                        activeJourneyCache.saveStreamCursor(eventID, forItinerary: itineraryID)
                    }
                    guard shouldRefreshActiveItinerary(for: event, itineraryID: itineraryID) else {
                        continue
                    }
                    scheduleCoalescedStreamRefresh()
                }

                let delay = backoff.nextDelay()
                BetaDiagnostics.record("active_itinerary_stream_disconnected", details: "reconnecting_in=\(delay)")
                guard await sleep(for: delay) else {
                    return
                }
            } catch {
                guard !Task.isCancelled else {
                    return
                }
                connectivityService.recordBackendFailure(error)
                let delay = activeWindowStreamReconnectDelay(after: error, backoff: &backoff)
                BetaDiagnostics.record("active_itinerary_stream_error", details: "\(error.localizedDescription); reconnecting_in=\(delay)")
                guard await sleep(for: delay) else {
                    return
                }
            }
        }
    }

    /// Runs at most one stream-driven refresh at a time. A burst of stream
    /// events while a refresh is in flight collapses into a single follow-up
    /// refresh instead of one fetch per event.
    private func scheduleCoalescedStreamRefresh() {
        guard !streamRefreshInFlight else {
            streamRefreshFollowUpNeeded = true
            return
        }
        streamRefreshInFlight = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.streamRefreshInFlight = false }
            repeat {
                self.streamRefreshFollowUpNeeded = false
                await self.performActiveWindowRefresh(showLoading: false, showAlertOnFailure: false)
            } while self.streamRefreshFollowUpNeeded
        }
    }

    private func shouldRefreshActiveWindow(for event: SubscriptionStreamEvent, windowID: String) -> Bool {
        guard event.event == nil || event.event == "subscription_event" else {
            return false
        }
        guard let envelope = event.envelope else {
            return false
        }
        if let eventWindowID = envelope.notification.windowSubscriptionId, eventWindowID != windowID {
            return false
        }
        return envelope.stream == "attention" || envelope.stream == "state_update"
    }

    private func shouldRefreshActiveItinerary(for event: SubscriptionStreamEvent, itineraryID: String) -> Bool {
        guard event.event == nil || event.event == "subscription_event" else {
            return false
        }
        guard let envelope = event.envelope else {
            return false
        }
        if let eventItineraryID = envelope.notification.itinerarySubscriptionId, eventItineraryID != itineraryID {
            return false
        }
        return envelope.stream == "attention" || envelope.stream == "state_update"
    }

    private func activeWindowStreamReconnectDelay(after error: Error, backoff: inout ActiveWindowStreamBackoff) -> Duration {
        if let apiError = error as? APIError, apiError.isAuthFailure {
            return Self.activeWindowAuthFailureBackoff
        }
        return backoff.nextDelay()
    }

    private func sleep(for duration: Duration) async -> Bool {
        do {
            try await Task.sleep(for: duration)
            return true
        } catch {
            return false
        }
    }

    private func liveActivityTokenRegistrationContext() -> LiveActivityTokenRegistrationContext? {
        registrationContextFactory.liveActivityContext(accessToken: accessTokenProvider())
    }

    private func emitFeedbackIfNeeded(previous: WindowSubscription?, current: WindowSubscription) {
        guard applicationStateProvider.applicationState == .active,
              let previous,
              previous.id == current.id,
              let type = notificationFeedbackType(previous: previous, current: current) else {
            return
        }

        notificationFeedbackGenerator.notificationOccurred(type)
    }

    private func notificationFeedbackType(
        previous: WindowSubscription,
        current: WindowSubscription
    ) -> UINotificationFeedbackGenerator.FeedbackType? {
        let previousRecommendation = previous.selectedRecommendation
        let currentRecommendation = current.selectedRecommendation

        if isCancellation(currentRecommendation), !isCancellation(previousRecommendation) {
            return .error
        }

        // A platform change sends people across the station, so it's the
        // most urgent thing short of a cancellation.
        if isSameRecommendation(previousRecommendation, currentRecommendation),
           platformChanged(from: previousRecommendation.journey, to: currentRecommendation.journey) {
            return .warning
        }

        let previousDelay = JourneyFormatting.statusDelayMinutes(
            journey: previousRecommendation.journey,
            score: previousRecommendation.score
        )
        let currentDelay = JourneyFormatting.statusDelayMinutes(
            journey: currentRecommendation.journey,
            score: currentRecommendation.score
        )
        if Self.delayTier(currentDelay) > Self.delayTier(previousDelay) {
            return .warning
        }

        if !isSameRecommendation(previousRecommendation, currentRecommendation) {
            return .success
        }

        return nil
    }

    /// Minutes of delay at which a growing delay buzzes again. Live delays
    /// often creep up a minute per refresh; buzzing on each one teaches
    /// people to ignore the warning.
    static let delayHapticThresholds = [1, 5, 15, 30, 60]

    static func delayTier(_ minutes: Int) -> Int {
        delayHapticThresholds.lastIndex { minutes >= $0 }.map { $0 + 1 } ?? 0
    }

    /// Only a move between two known platforms counts: TBC becoming a
    /// number is the platform arriving, not changing.
    private func platformChanged(from previous: JourneyResult, to current: JourneyResult) -> Bool {
        let unknown: Set<String> = ["-", "TBC"]
        let previousPlatform = ActiveWindowPresentation.platformDisplay(for: previous).primary
        let currentPlatform = ActiveWindowPresentation.platformDisplay(for: current).primary
        guard !unknown.contains(previousPlatform), !unknown.contains(currentPlatform) else {
            return false
        }
        return previousPlatform != currentPlatform
    }

    private func isSameRecommendation(
        _ left: DirectWindowRecommendation,
        _ right: DirectWindowRecommendation
    ) -> Bool {
        left.journey.serviceId == right.journey.serviceId &&
            left.journey.rid == right.journey.rid &&
            left.journey.ssd == right.journey.ssd
    }

    private func isCancellation(_ recommendation: DirectWindowRecommendation) -> Bool {
        return JourneyFormatting.isCancelled(recommendation.journey) ||
            recommendation.score.reasons?.contains("cancelled") == true
    }

    private func normalizedPinnedServiceID(_ value: Int?) -> Int? {
        guard let value, value > 0 else {
            return nil
        }
        return value
    }

    private func departedPromptKey(windowID: String?, serviceID: Int) -> String? {
        guard serviceID > 0,
              let windowID = windowID ?? activeWindowID,
              !windowID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return "\(windowID)|\(serviceID)"
    }

    private func activeJourneyPollingInterval(now: Date = Date()) -> Duration? {
        Self.activeWindowPollingInterval(for: activeWindow, activeWindowID: activeWindowID, now: now)
            ?? Self.activeItineraryPollingInterval(for: activeItinerary, activeItineraryID: activeItineraryID, now: now)
    }

    static func onboardArrivalClearDate(for window: WindowSubscription) -> Date? {
        guard let pinnedTrainServiceID = window.pinnedTrainServiceId,
              pinnedTrainServiceID > 0 else {
            return nil
        }
        let recommendation = recommendation(in: window, serviceID: pinnedTrainServiceID)
        guard let recommendation,
              JourneyFormatting.isArrived(recommendation.journey) else {
            return nil
        }
        let arrivalDisplay = JourneyFormatting.arrivalDisplay(recommendation.journey)
        guard let arrivalDate = arrivalDisplay.currentDate ?? arrivalDisplay.scheduledDate else {
            return nil
        }
        return arrivalDate.addingTimeInterval(onboardArrivalClearGraceSeconds)
    }

    private static func recommendation(in window: WindowSubscription, serviceID: Int) -> DirectWindowRecommendation? {
        let selected = window.selectedRecommendation
        if selected.journey.serviceId == serviceID {
            return selected
        }
        return window.recommendations.first { $0.journey.serviceId == serviceID }
    }

    private func scheduleOnboardArrivalClearIfNeeded(for window: WindowSubscription, now: Date = Date()) async {
        onboardArrivalClearTask?.cancel()
        onboardArrivalClearTask = nil

        guard let clearDate = Self.onboardArrivalClearDate(for: window) else {
            return
        }

        let delay = clearDate.timeIntervalSince(now)
        guard delay > 0 else {
            await clearArrivedOnboardWindow(windowID: window.id)
            return
        }

        let nanoseconds = Self.sleepNanoseconds(for: delay)
        onboardArrivalClearTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: nanoseconds)
            } catch {
                return
            }
            await self?.clearArrivedOnboardWindow(windowID: window.id)
        }
    }

    private func clearArrivedOnboardWindow(windowID: String) async {
        guard activeWindowID == windowID else {
            return
        }
        if let activeWindow,
           let clearDate = Self.onboardArrivalClearDate(for: activeWindow),
           clearDate > Date() {
            return
        }

        guard accessTokenProvider() != nil else {
            clearWindowState()
            await liveActivityCoordinator.endAll(tokenRegistration: liveActivityTokenRegistrationContext())
            return
        }
        clearWindowState()
        await liveActivityCoordinator.endAll(tokenRegistration: liveActivityTokenRegistrationContext())
        await enqueueAndFlush(
            JourneyMutation(kind: .windowDelete, windowID: windowID),
            showErrors: false
        )
    }

    private static func sleepNanoseconds(for delay: TimeInterval) -> UInt64 {
        let safeDelay = max(0, min(delay, TimeInterval(UInt64.max) / 1_000_000_000))
        return UInt64(safeDelay * 1_000_000_000)
    }

    private static func activeItineraryPollingInterval(
        for itinerary: ItinerarySubscription?,
        activeItineraryID: String?,
        now: Date
    ) -> Duration? {
        guard activeItineraryID != nil else {
            return nil
        }
        guard let itinerary,
              let departureStart = DateFormatting.date(from: itinerary.departureStart) else {
            return activeWindowFallbackPollingInterval
        }

        let staleEnd = departureStart.addingTimeInterval(
            TimeInterval(itinerary.windowMinutes) * 60 + activeWindowStaleGraceSeconds
        )
        guard now < staleEnd else {
            return nil
        }

        let secondsUntilDeparture = departureStart.timeIntervalSince(now)
        if secondsUntilDeparture > 60 * 60 {
            return activeWindowDistantPollingInterval
        }
        if secondsUntilDeparture > 15 * 60 {
            return activeWindowApproachingPollingInterval
        }
        return activeWindowImminentPollingInterval
    }

    private func clearWindowState() {
        let hadWindowState = activeWindow != nil || activeWindowID != nil
        onboardArrivalClearTask?.cancel()
        onboardArrivalClearTask = nil
        activeWindow = nil
        activeWindowID = nil
        activeWindowStreamLastEventID = nil
        activeJourneyCache.clearWindowStreamCursors()
        pinnedLiveActivityServiceID = nil
        handledDepartedPromptKeys = []
        pendingOriginEntryWindowID = nil
        stationProximityMonitor.stopMonitoring()
        if activeItinerary == nil {
            activeJourneyCache.clear()
        } else if let activeItinerary {
            activeJourneyCache.save(itinerary: activeItinerary)
        }
        if hadWindowState {
            didClearActiveWindowState?()
        }
    }

    private func clearItineraryState() {
        let hadItineraryState = activeItinerary != nil || activeItineraryID != nil
        activeItinerary = nil
        activeItineraryID = nil
        activeItineraryStreamLastEventID = nil
        activeJourneyCache.clearItineraryStreamCursors()
        // Only stop monitoring if no active window is also using the
        // monitor; the window path manages its own teardown.
        if activeWindow == nil {
            stationProximityMonitor.stopMonitoring()
        }
        if activeWindow == nil {
            activeJourneyCache.clear()
        } else if let activeWindow {
            activeJourneyCache.save(window: activeWindow)
        }
        if hadItineraryState {
            didClearActiveWindowState?()
        }
    }
}

private enum ActiveWindowViewModelError: LocalizedError {
    case missingAccessToken
    case invalidQueuedMutation

    var errorDescription: String? {
        switch self {
        case .missingAccessToken:
            return "Sign in to create a journey."
        case .invalidQueuedMutation:
            return "RightTrain could not sync one of the saved journey changes."
        }
    }
}

private extension WindowSubscription {
    var isActive: Bool {
        status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "active" && deletedAt == nil
    }

}

private extension ItinerarySubscription {
    var isActive: Bool {
        status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "active" && deletedAt == nil
    }
}

private struct ActiveWindowStreamBackoff {
    private var nextSeconds = 1

    mutating func nextDelay() -> Duration {
        let delay = Duration.seconds(nextSeconds)
        nextSeconds = min(nextSeconds * 2, 30)
        return delay
    }

    mutating func reset() {
        nextSeconds = 1
    }
}
