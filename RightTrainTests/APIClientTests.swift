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
    static var requests: [URLRequest] = []
    static var requestCount = 0

    static func reset(_ outcomes: [Outcome]) {
        lock.lock()
        defer { lock.unlock() }
        self.outcomes = outcomes
        requests = []
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

    static var recordedRequests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }

    static func recordableRequest(_ request: URLRequest) -> URLRequest {
        var copy = request
        if copy.httpBody == nil, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(buffer, count: count)
            }
            copy.httpBody = data
        }
        return copy
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.requests.append(Self.recordableRequest(request))
        Self.lock.unlock()
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

    private func requestBodyDictionary(_ request: URLRequest) throws -> [String: Any] {
        let data = try XCTUnwrap(request.httpBody)
        let object = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(object as? [String: Any])
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

    func testNearbyStationsRequestAndDecode() async throws {
        StubURLProtocol.reset([
            .success(statusCode: 200, body: Data("""
            {
              "stations": [
                {
                  "crs": "EUS",
                  "name": "London Euston",
                  "tpl": "EUSTON",
                  "latitude": 51.5284,
                  "longitude": -0.1331,
                  "distanceMeters": 142,
                  "monitoringRadiusMeters": 300
                }
              ],
              "generatedAt": "2026-06-16T12:00:00Z",
              "sourceFreshness": {
                "status": "fresh",
                "lastSuccessfulImportAt": "2026-06-16T03:00:00Z"
              }
            }
            """.utf8))
        ])
        let client = makeClient()

        let response = try await client.searchNearbyStations(
            latitude: 51.5282,
            longitude: -0.1337,
            selectionRole: .destination,
            routeMode: .direct,
            originCRS: "MAN",
            departureStart: Date(timeIntervalSince1970: 1_781_621_600),
            windowMinutes: 120,
            limit: 6
        )

        XCTAssertEqual(response.stations.first?.crs, "EUS")
        XCTAssertEqual(response.stations.first?.distanceMeters, 142)
        XCTAssertTrue(response.sourceFreshness.isFresh)
        let requestURL = try XCTUnwrap(StubURLProtocol.recordedRequests.first?.url)
        let components = try XCTUnwrap(URLComponents(url: requestURL, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.path, "/v1/stations/nearby")
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
            item.value.map { (item.name, $0) }
        })
        XCTAssertEqual(query["selection_role"], "destination")
        XCTAssertEqual(query["route_mode"], "direct")
        XCTAssertEqual(query["origin_crs"], "MAN")
        XCTAssertEqual(query["window_minutes"], "120")
        XCTAssertEqual(query["limit"], "6")
    }

    func testAccountRegistrationRequestsAndDecoding() async throws {
        StubURLProtocol.reset([
            .success(statusCode: 200, body: Data("""
            {
              "attemptId": "attempt-account-1",
              "expiresAt": "2026-06-16T12:05:00Z",
              "credentialOptions": {
                "challenge": "challenge",
                "relyingPartyId": "righttrain.app",
                "userHandle": "user-handle",
                "displayName": "RightTrain account"
              }
            }
            """.utf8)),
            .success(statusCode: 200, body: Data("""
            {
              "account": {
                "id": "account-1",
                "state": "active",
                "createdAt": "2026-06-16T12:00:00Z",
                "updatedAt": "2026-06-16T12:00:00Z"
              },
              "preferenceSet": {
                "version": 1,
                "updatedAt": "2026-06-16T12:00:00Z",
                "stationDefaults": {"homeStationCrs": "EUS", "workStationCrs": "MAN"},
                "commuteRoutines": [],
                "routeSetupDefaults": {},
                "notificationPreferences": {},
                "productPreferences": {}
              },
              "recoveryCode": "RECOVERY-CODE"
            }
            """.utf8))
        ])
        let client = makeClient()

        let options = try await client.createAccountRegistrationOptions(accessToken: "token-1")
        let response = try await client.registerAccount(
            input: RegisterAccountRequest(
                attemptId: options.attemptId,
                credentialAttestation: AccountCredentialAttestation(
                    credentialId: "credential-id",
                    clientDataJSON: "client-data",
                    attestationObject: "attestation"
                ),
                clientDeviceId: "device-1"
            ),
            accessToken: "token-1"
        )

        XCTAssertEqual(options.credentialOptions.relyingPartyId, "righttrain.app")
        XCTAssertEqual(response.account.state, "active")
        XCTAssertEqual(response.recoveryCode, "RECOVERY-CODE")
        let requests = StubURLProtocol.recordedRequests
        XCTAssertEqual(requests[0].url?.path, "/v1/auth/account/registration-options")
        XCTAssertEqual(requests[0].httpMethod, "POST")
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer token-1")
        XCTAssertEqual(requests[1].url?.path, "/v1/auth/account/register")
        let registerBody = try requestBodyDictionary(requests[1])
        XCTAssertEqual(registerBody["attemptId"] as? String, "attempt-account-1")
        XCTAssertNil(registerBody["migrateCurrentDevicePreferences"])
    }

    func testAccountSignInAndRecoveryRequests() async throws {
        StubURLProtocol.reset([
            .success(statusCode: 200, body: Data("""
            {
              "attemptId": "assertion-attempt-1",
              "expiresAt": "2026-06-16T12:05:00Z",
              "assertionOptions": {
                "challenge": "challenge",
                "relyingPartyId": "righttrain.app",
                "allowCredentials": ["credential-id"]
              }
            }
            """.utf8)),
            .success(statusCode: 200, body: Data("""
            {
              "user": {"id": "user-1", "entitlements": {"tier": "free_beta", "status": "active", "activeWindowLimit": 1, "commuteRoutineLimit": 2}, "stationDefaults": {}, "createdAt": "2026-06-16T12:00:00Z", "updatedAt": "2026-06-16T12:00:00Z"},
              "session": {"id": "session-1", "accessToken": "account-token", "tokenType": "Bearer", "expiresAt": "2026-07-16T12:00:00Z", "createdAt": "2026-06-16T12:00:00Z"}
            }
            """.utf8)),
            .success(statusCode: 200, body: Data("""
            {
              "user": {"id": "user-1", "entitlements": {"tier": "free_beta", "status": "active", "activeWindowLimit": 1, "commuteRoutineLimit": 2}, "stationDefaults": {}, "createdAt": "2026-06-16T12:00:00Z", "updatedAt": "2026-06-16T12:00:00Z"},
              "session": {"id": "session-2", "accessToken": "recovered-token", "tokenType": "Bearer", "expiresAt": "2026-07-16T12:00:00Z", "createdAt": "2026-06-16T12:00:00Z"}
            }
            """.utf8))
        ])
        let client = makeClient()

        let options = try await client.createAccountAssertionOptions(credentialHint: "credential-id")
        let signedIn = try await client.signInWithAccount(input: AccountSignInRequest(
            attemptId: options.attemptId,
            credentialAssertion: AccountCredentialAssertion(
                credentialId: "credential-id",
                clientDataJSON: "client-data",
                authenticatorData: "auth-data",
                signature: "signature",
                userHandle: "user-handle"
            ),
            clientDeviceId: "device-1"
        ))
        let recovered = try await client.recoverAccount(input: AccountRecoveryRequest(
            recoveryCode: "RECOVERY-CODE",
            newCredentialAttestation: AccountCredentialAttestation(
                credentialId: "new-credential",
                clientDataJSON: "client-data",
                attestationObject: "attestation"
            ),
            clientDeviceId: "device-1"
        ))

        XCTAssertEqual(signedIn.session.accessToken, "account-token")
        XCTAssertEqual(recovered.session.accessToken, "recovered-token")
        let requests = StubURLProtocol.recordedRequests
        XCTAssertEqual(requests[0].url?.path, "/v1/auth/account/assertion-options")
        XCTAssertEqual(try requestBodyDictionary(requests[0])["credentialHint"] as? String, "credential-id")
        XCTAssertEqual(requests[1].url?.path, "/v1/auth/account/sign-in")
        XCTAssertEqual(requests[2].url?.path, "/v1/auth/account/recover")
    }

    func testAccountPreferenceSetFetchUpdateAndConflictMapping() async throws {
        let preferenceJSON = Data("""
        {
          "version": 1,
          "updatedAt": "2026-06-16T12:00:00Z",
          "stationDefaults": {"homeStationCrs": "EUS", "workStationCrs": "MAN"},
          "commuteRoutines": [],
          "routeSetupDefaults": {},
          "notificationPreferences": {"routineNotificationsEnabled": true},
          "productPreferences": {}
        }
        """.utf8)
        StubURLProtocol.reset([
            .success(statusCode: 200, body: preferenceJSON),
            .success(statusCode: 200, body: Data(#"{"version":2,"updatedAt":"2026-06-16T12:01:00Z","conflict":null}"#.utf8)),
            .success(statusCode: 409, body: Data("""
            {
              "error": "preference_conflict",
              "message": "Account preferences changed on another device.",
              "currentVersion": 3,
              "conflict": {"fields": ["stationDefaults"], "allowedResolutions": ["keep_local"]}
            }
            """.utf8))
        ])
        let client = makeClient()

        let preferenceSet = try await client.getAccountPreferenceSet(accessToken: "token-1")
        let update = try await client.updateAccountPreferenceSet(
            input: UpdateAccountPreferenceSetRequest(
                baseVersion: preferenceSet.version,
                mergeStrategy: "merge_non_conflicting",
                stationDefaults: preferenceSet.stationDefaults,
                commuteRoutines: [],
                routeSetupDefaults: [:],
                notificationPreferences: preferenceSet.notificationPreferences,
                productPreferences: [:]
            ),
            accessToken: "token-1"
        )
        XCTAssertEqual(update.version, 2)

        do {
            _ = try await client.updateAccountPreferenceSet(
                input: UpdateAccountPreferenceSetRequest(
                    baseVersion: 1,
                    mergeStrategy: "merge_non_conflicting",
                    stationDefaults: preferenceSet.stationDefaults,
                    commuteRoutines: [],
                    routeSetupDefaults: [:],
                    notificationPreferences: preferenceSet.notificationPreferences,
                    productPreferences: [:]
                ),
                accessToken: "token-1"
            )
            XCTFail("Expected conflict")
        } catch let error as APIError {
            XCTAssertTrue(error.isConflict)
            XCTAssertEqual(error.errorDescription, "preference_conflict")
        }

        let requests = StubURLProtocol.recordedRequests
        XCTAssertEqual(requests[0].url?.path, "/v1/me/preference-set")
        XCTAssertEqual(requests[1].httpMethod, "PUT")
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "Authorization"), "Bearer token-1")
    }

    func testLinkedDevicesRevokeAndExportRequests() async throws {
        StubURLProtocol.reset([
            .success(statusCode: 200, body: Data("""
            {
              "devices": [
                {
                  "id": "linked-device-1",
                  "platform": "iOS",
                  "deviceClass": "iPhone",
                  "appVersion": "0.1",
                  "buildNumber": "42",
                  "lastSeenAt": null,
                  "currentDevice": true,
                  "state": "active"
                }
              ]
            }
            """.utf8)),
            .success(statusCode: 204, body: Data()),
            .success(statusCode: 200, body: Data("""
            {
              "generatedAt": "2026-06-16T12:00:00Z",
              "account": {"id": "account-1", "state": "active", "createdAt": "2026-06-16T12:00:00Z", "updatedAt": "2026-06-16T12:00:00Z"},
              "preferenceSet": {
                "version": 1,
                "updatedAt": "2026-06-16T12:00:00Z",
                "stationDefaults": {},
                "commuteRoutines": [],
                "routeSetupDefaults": {},
                "notificationPreferences": {},
                "productPreferences": {}
              },
              "linkedDevices": [{"platform": "iOS", "deviceClass": "iPhone", "lastSeenAt": null, "state": "active"}]
            }
            """.utf8)),
            .success(statusCode: 204, body: Data())
        ])
        let client = makeClient()

        let devices = try await client.listLinkedDevices(accessToken: "token-1")
        try await client.revokeLinkedDevice(id: "linked-device-1", accessToken: "token-1")
        let export = try await client.exportAccountPreferences(accessToken: "token-1")
        try await client.deleteCurrentUser(accessToken: "token-1")

        XCTAssertEqual(devices.devices.first?.id, "linked-device-1")
        XCTAssertNil(devices.devices.first?.lastSeenAt)
        XCTAssertEqual(export.linkedDevices.first?.platform, "iOS")
        let requests = StubURLProtocol.recordedRequests
        XCTAssertEqual(requests[0].url?.path, "/v1/me/linked-devices")
        XCTAssertEqual(requests[1].httpMethod, "DELETE")
        XCTAssertEqual(requests[1].url?.path, "/v1/me/linked-devices/linked-device-1")
        XCTAssertEqual(requests[2].url?.path, "/v1/me/export")
        XCTAssertEqual(requests[3].httpMethod, "DELETE")
        XCTAssertEqual(requests[3].url?.path, "/v1/me")
        XCTAssertEqual(requests[3].value(forHTTPHeaderField: "Authorization"), "Bearer token-1")
    }
}
