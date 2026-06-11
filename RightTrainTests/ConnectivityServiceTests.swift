@testable import RightTrain
import Foundation
import XCTest

final class ConnectivityServiceTests: XCTestCase {
    @MainActor
    func testSingleTransportFailureReportsPatchyNotOffline() {
        let service = ConnectivityService()

        service.recordBackendFailure(APIError.transport("connection lost"))

        XCTAssertFalse(service.backendUnavailable, "A single transport blip should not show Offline")
        XCTAssertTrue(service.looksPatchy, "A single transport blip should show Patchy")
        XCTAssertEqual(service.consecutiveFailures, 1)
    }

    @MainActor
    func testConsecutiveTransportFailuresReportOffline() {
        let service = ConnectivityService()

        service.recordBackendFailure(APIError.transport("connection lost"))
        service.recordBackendFailure(APIError.transport("connection lost again"))

        XCTAssertTrue(service.backendUnavailable, "Persistent transport failures should show Offline")
        XCTAssertFalse(service.looksPatchy, "Offline supersedes Patchy")
        XCTAssertEqual(service.consecutiveFailures, 2)
    }

    @MainActor
    func testSuccessAfterFailuresClearsState() {
        let service = ConnectivityService()
        service.recordBackendFailure(APIError.transport("connection lost"))
        service.recordBackendFailure(APIError.transport("connection lost again"))

        service.recordSuccessfulBackendContact()

        XCTAssertFalse(service.backendUnavailable)
        XCTAssertFalse(service.looksPatchy)
        XCTAssertEqual(service.consecutiveFailures, 0)
    }

    @MainActor
    func testServerErrorIsReachableButPatchy() {
        let service = ConnectivityService()

        service.recordBackendFailure(APIError.server(statusCode: 503, code: nil, message: "unavailable", details: [:]))

        XCTAssertFalse(service.backendUnavailable, "A 5xx means the backend is reachable, not offline")
        XCTAssertTrue(service.looksPatchy, "A 5xx should surface as degraded/patchy")
        XCTAssertEqual(service.consecutiveFailures, 0, "HTTP errors are not transport blips")
    }

    @MainActor
    func testClientErrorIsTreatedAsReachable() {
        let service = ConnectivityService()

        service.recordBackendFailure(APIError.server(statusCode: 404, code: nil, message: "not found", details: [:]))

        XCTAssertFalse(service.backendUnavailable)
        XCTAssertFalse(service.looksPatchy)
        XCTAssertEqual(service.consecutiveFailures, 0)
    }
}
