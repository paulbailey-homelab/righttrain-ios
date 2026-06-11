import Foundation
import Network

enum NetworkPathState: String, Equatable {
    case unknown
    case satisfied
    case unsatisfied
    case requiresConnection
}

enum BackendContactState: String, Equatable {
    case unknown
    case available
    case degraded
    case unavailable
}

@MainActor
@Observable
final class ConnectivityService {
    /// Number of consecutive transport-level failures tolerated before the
    /// backend is treated as fully unavailable (the red "Offline" banner). The
    /// first blip is surfaced as "patchy" instead, so a single dropped request
    /// — common on cellular or behind a cloud load balancer that recycles idle
    /// connections — doesn't flap the UI straight to offline.
    static let unavailableFailureThreshold = 2

    private(set) var pathState: NetworkPathState = .unknown
    private(set) var backendState: BackendContactState = .unknown
    private(set) var lastSuccessfulContactAt: Date?
    private(set) var lastFailureAt: Date?
    private(set) var consecutiveFailures = 0
    private(set) var isConstrained = false
    private(set) var isExpensive = false

    @ObservationIgnored private let monitor: NWPathMonitor
    @ObservationIgnored private let monitorQueue = DispatchQueue(label: "righttrain.connectivity")
    @ObservationIgnored private var hasStarted = false

    init(monitor: NWPathMonitor = NWPathMonitor()) {
        self.monitor = monitor
    }

    var backendUnavailable: Bool {
        pathState == .unsatisfied || backendState == .unavailable
    }

    var looksPatchy: Bool {
        guard !backendUnavailable else { return false }
        return pathState == .requiresConnection ||
            backendState == .degraded ||
            consecutiveFailures >= 2 ||
            isConstrained
    }

    func startMonitoring() {
        guard !hasStarted else { return }
        hasStarted = true
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                self?.apply(path)
            }
        }
        monitor.start(queue: monitorQueue)
    }

    func refreshBackendStatus(apiClient: any APIClienting) async {
        do {
            let status = try await apiClient.serviceStatus()
            recordSuccessfulBackendContact(degraded: status.status != "operational")
        } catch {
            recordBackendFailure(error)
        }
    }

    func recordSuccessfulBackendContact(degraded: Bool = false) {
        lastSuccessfulContactAt = Date()
        consecutiveFailures = 0
        backendState = degraded ? .degraded : .available
    }

    func recordBackendFailure(_ error: Error) {
        lastFailureAt = Date()
        if let apiError = error as? APIError,
           let statusCode = apiError.statusCode {
            // The backend answered with an HTTP error, so the connection itself
            // is healthy: 5xx means it's reachable but struggling, while 4xx is a
            // normal application-level response that shouldn't dim connectivity.
            backendState = statusCode >= 500 ? .degraded : .available
            return
        }
        // Transport-level failure (timeout, dropped connection, TLS reset, DNS).
        // Surface the first occurrence as "patchy" and only declare the backend
        // fully unavailable once failures persist past the threshold.
        consecutiveFailures += 1
        backendState = consecutiveFailures >= Self.unavailableFailureThreshold ? .unavailable : .degraded
    }

    private func apply(_ path: NWPath) {
        switch path.status {
        case .satisfied:
            pathState = .satisfied
        case .unsatisfied:
            pathState = .unsatisfied
            backendState = .unavailable
        case .requiresConnection:
            pathState = .requiresConnection
        @unknown default:
            pathState = .unknown
        }
        isConstrained = path.isConstrained
        isExpensive = path.isExpensive
    }
}
