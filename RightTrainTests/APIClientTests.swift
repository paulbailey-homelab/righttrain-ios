@testable import RightTrain
import Foundation
import XCTest

/// A URLProtocol that lets each test script the sequence of outcomes returned
/// for successive requests, so we can exercise the transport-retry path.
private final class StubURLProtocol: URLProtocol {
    enum Outcome {
        case failure(Error)
        case success(statusCode: Int, body: Data)
    }

    static let lock = NSLock()
    static var outcomes: [Outcome] = []
    static var requestCount = 0

    static func reset(_ outcomes: [Outcome]) {
        lock.lock()
        defer { lock.unlock() }
        self.outcomes = outcomes
        requestCount = 0
    }

    static func nextOutcome() -> Outcome {
        lock.lock()
        defer { lock.unlock() }
        requestCount += 1
        guard !outcomes.isEmpty else {
            return .failure(URLError(.unknown))
        }
        return outcomes.removeFirst()
    }

    static var totalRequests: Int {
        lock.lock()
        defer { lock.unlock() }
        return requestCount
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        switch StubURLProtocol.nextOutcome() {
        case .failure(let error):
            client?.urlProtocol(self, didFailWithError: error)
        case .success(let statusCode, let body):
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}

final class APIClientTests: XCTestCase {
    private func makeClient() -> APIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        return APIClient(baseURL: URL(string: "https://api.example.test")!, urlSession: session)
    }

    private func statusJSON() -> Data {
        Data(#"{"status":"operational","checkedAt":"2026-06-07T10:00:00.000Z","components":[],"message":"OK"}"#.utf8)
    }

    func testRetryableRequestClassification() {
        XCTAssertTrue(APIClient.isRetryableRequest(method: "GET", idempotencyKey: nil))
        XCTAssertTrue(APIClient.isRetryableRequest(method: "head", idempotencyKey: nil))
        XCTAssertFalse(APIClient.isRetryableRequest(method: "POST", idempotencyKey: nil))
        XCTAssertFalse(APIClient.isRetryableRequest(method: "POST", idempotencyKey: "  "))
        XCTAssertTrue(APIClient.isRetryableRequest(method: "POST", idempotencyKey: "key-123"))
    }

    func testRetryableTransportErrorClassification() {
        XCTAssertTrue(APIClient.isRetryableTransportError(URLError(.networkConnectionLost)))
        XCTAssertTrue(APIClient.isRetryableTransportError(URLError(.timedOut)))
        XCTAssertFalse(APIClient.isRetryableTransportError(URLError(.cancelled)))
        XCTAssertFalse(APIClient.isRetryableTransportError(APIError.transport("nope")))
    }

    func testGetRetriesOnceAfterStaleConnection() async throws {
        StubURLProtocol.reset([
            .failure(URLError(.networkConnectionLost)),
            .success(statusCode: 200, body: statusJSON())
        ])
        let client = makeClient()

        let status = try await client.serviceStatus()

        XCTAssertEqual(status.status, "operational")
        XCTAssertEqual(StubURLProtocol.totalRequests, 2, "Expected one retry after a stale-connection failure")
    }

    func testGetDoesNotRetryMoreThanOnce() async {
        StubURLProtocol.reset([
            .failure(URLError(.networkConnectionLost)),
            .failure(URLError(.networkConnectionLost)),
            .success(statusCode: 200, body: statusJSON())
        ])
        let client = makeClient()

        do {
            _ = try await client.serviceStatus()
            XCTFail("Expected the second consecutive failure to surface")
        } catch {
            XCTAssertEqual(StubURLProtocol.totalRequests, 2, "Should attempt at most original + one retry")
        }
    }

    func testServerErrorIsNotRetried() async {
        StubURLProtocol.reset([
            .success(statusCode: 503, body: Data()),
            .success(statusCode: 200, body: statusJSON())
        ])
        let client = makeClient()

        do {
            _ = try await client.serviceStatus()
            XCTFail("Expected a 503 to throw")
        } catch let error as APIError {
            XCTAssertEqual(error.statusCode, 503)
            XCTAssertEqual(StubURLProtocol.totalRequests, 1, "HTTP errors must not trigger a transport retry")
        } catch {
            XCTFail("Expected APIError, got \(error)")
        }
    }
}
