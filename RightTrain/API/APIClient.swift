import Foundation

protocol APIClienting {
    func createDeviceChallenge() async throws -> DeviceChallengeResponse
    func registerDevice(attemptId: String, keyId: String, attestationObject: String) async throws -> AuthResponse
    func serviceStatus() async throws -> ServiceStatus
    func appCapabilities() async throws -> AppCapabilitiesResponse
    func currentUser(accessToken: String) async throws -> User
    func updateStationDefaults(input: UpdateStationDefaultsRequest, accessToken: String) async throws -> User
    func deleteCurrentUser(accessToken: String) async throws
    func billingProducts(accessToken: String) async throws -> BillingProductsResponse
    func syncStoreKitTransactions(signedTransactions: [String], accessToken: String) async throws -> User
    func searchStations(query: String, limit: Int) async throws -> [StationSuggestion]
    func searchDirectDestinationStations(
        originCRS: String,
        query: String,
        departureStart: Date,
        windowMinutes: Int,
        limit: Int
    ) async throws -> [StationSuggestion]
    func recommendDirectWindow(
        originCRS: String,
        destinationCRS: String,
        departureStart: Date,
        windowMinutes: Int
    ) async throws -> DirectWindowRecommendationResponse
    func planJourney(
        originCRS: String,
        destinationCRS: String,
        departureStart: Date,
        windowMinutes: Int,
        maxChanges: Int,
        limit: Int
    ) async throws -> JourneyPlanResponse
    func getJourneyDetail(serviceID: Int, originTPL: String?, destinationTPL: String?) async throws -> JourneyDetail
    func createWindowSubscription(
        input: CreateWindowSubscriptionRequest,
        accessToken: String
    ) async throws -> WindowSubscription
    func createItinerarySubscription(
        input: CreateItinerarySubscriptionRequest,
        accessToken: String
    ) async throws -> ItinerarySubscription
    func createJourneyShare(
        input: CreateJourneyShareRequest,
        accessToken: String
    ) async throws -> JourneyShareResponse
    func getJourneyShare(id: String) async throws -> PublicJourneyShare
    func getWindowSubscription(id: String, accessToken: String) async throws -> WindowSubscription
    func getActiveWindowSubscription(accessToken: String) async throws -> WindowSubscription
    func getActiveItinerarySubscription(accessToken: String) async throws -> ItinerarySubscription
    func getItinerarySubscription(id: String, accessToken: String) async throws -> ItinerarySubscription
    func pinItineraryFirstLeg(id: String, input: PinItineraryFirstLegRequest, accessToken: String, idempotencyKey: String?) async throws -> ItinerarySubscription
    func clearItineraryPinnedFirstLeg(id: String, accessToken: String, idempotencyKey: String?) async throws -> ItinerarySubscription
    func reportItineraryOriginArrival(id: String, accessToken: String, idempotencyKey: String?) async throws -> ItinerarySubscription
    func reportItineraryInterchangeArrival(id: String, atCrs: String, legIndex: Int, accessToken: String, idempotencyKey: String?) async throws -> ItinerarySubscription
    func boardItineraryLeg(id: String, legIndex: Int, pinFirstLeg: Bool, accessToken: String, idempotencyKey: String?) async throws -> ItinerarySubscription
    func replanItineraryFromCurrentStation(id: String, fromCrs: String, accessToken: String, idempotencyKey: String?) async throws -> ItinerarySubscription
    func pinWindowSubscriptionTrain(id: String, serviceID: Int, accessToken: String, idempotencyKey: String?) async throws -> WindowSubscription
    func clearWindowSubscriptionPinnedTrain(id: String, accessToken: String, idempotencyKey: String?) async throws -> WindowSubscription
    func getWindowSubscriptionNotification(
        windowSubscriptionID: String,
        notificationID: String,
        accessToken: String
    ) async throws -> WindowSubscriptionNotificationDetail
    func streamWindowSubscriptionEvents(
        windowSubscriptionID: String,
        accessToken: String,
        lastEventID: String?
    ) -> AsyncThrowingStream<SubscriptionStreamEvent, Error>
    func streamItinerarySubscriptionEvents(
        itinerarySubscriptionID: String,
        accessToken: String,
        lastEventID: String?
    ) -> AsyncThrowingStream<SubscriptionStreamEvent, Error>
    func deleteWindowSubscription(id: String, accessToken: String, idempotencyKey: String?) async throws
    func deleteItinerarySubscription(id: String, accessToken: String, idempotencyKey: String?) async throws
    func listCommuteRoutines(accessToken: String) async throws -> [CommuteRoutine]
    func createCommuteRoutine(input: CommuteRoutineMutationRequest, accessToken: String) async throws -> CommuteRoutine
    func updateCommuteRoutine(id: String, input: CommuteRoutineMutationRequest, accessToken: String) async throws -> CommuteRoutine
    func deleteCommuteRoutine(id: String, accessToken: String) async throws
    func registerLiveActivityToken(
        windowSubscriptionID: String,
        activityKind: String,
        input: RegisterLiveActivityTokenRequest,
        accessToken: String
    ) async throws
    func registerItineraryLiveActivityToken(
        itinerarySubscriptionID: String,
        activityKind: String,
        input: RegisterLiveActivityTokenRequest,
        accessToken: String
    ) async throws
    func registerLiveActivityPushToStartToken(
        clientDeviceID: String,
        input: RegisterLiveActivityTokenRequest,
        accessToken: String
    ) async throws
    func deleteLiveActivityPushToStartToken(
        clientDeviceID: String,
        activityID: String,
        environment: String?,
        accessToken: String
    ) async throws
    func deleteLiveActivityToken(
        windowSubscriptionID: String,
        activityKind: String,
        activityID: String,
        environment: String?,
        accessToken: String
    ) async throws
    func deleteItineraryLiveActivityToken(
        itinerarySubscriptionID: String,
        activityKind: String,
        activityID: String,
        environment: String?,
        accessToken: String
    ) async throws
    func registerAPNsAlertToken(
        clientDeviceID: String,
        input: RegisterAPNsAlertTokenRequest,
        accessToken: String
    ) async throws
    func deleteAPNsAlertToken(
        clientDeviceID: String,
        environment: String?,
        accessToken: String
    ) async throws
    /// Tears down pooled keep-alive connections so the next request opens a
    /// fresh socket. Call when returning to the foreground: a cloud load
    /// balancer may have silently closed connections that went idle while the
    /// app was backgrounded, and URLSession would otherwise only discover the
    /// dead socket by failing the first request on resume.
    func resetPooledConnections() async
}

extension APIClienting {
    func pinItineraryFirstLeg(id: String, input: PinItineraryFirstLegRequest, accessToken: String) async throws -> ItinerarySubscription {
        try await pinItineraryFirstLeg(id: id, input: input, accessToken: accessToken, idempotencyKey: nil)
    }

    func clearItineraryPinnedFirstLeg(id: String, accessToken: String) async throws -> ItinerarySubscription {
        try await clearItineraryPinnedFirstLeg(id: id, accessToken: accessToken, idempotencyKey: nil)
    }

    func reportItineraryOriginArrival(id: String, accessToken: String) async throws -> ItinerarySubscription {
        try await reportItineraryOriginArrival(id: id, accessToken: accessToken, idempotencyKey: nil)
    }

    func reportItineraryInterchangeArrival(id: String, atCrs: String, legIndex: Int, accessToken: String) async throws -> ItinerarySubscription {
        try await reportItineraryInterchangeArrival(id: id, atCrs: atCrs, legIndex: legIndex, accessToken: accessToken, idempotencyKey: nil)
    }

    func boardItineraryLeg(id: String, legIndex: Int, pinFirstLeg: Bool, accessToken: String) async throws -> ItinerarySubscription {
        try await boardItineraryLeg(id: id, legIndex: legIndex, pinFirstLeg: pinFirstLeg, accessToken: accessToken, idempotencyKey: nil)
    }

    func replanItineraryFromCurrentStation(id: String, fromCrs: String, accessToken: String) async throws -> ItinerarySubscription {
        try await replanItineraryFromCurrentStation(id: id, fromCrs: fromCrs, accessToken: accessToken, idempotencyKey: nil)
    }

    func pinWindowSubscriptionTrain(id: String, serviceID: Int, accessToken: String) async throws -> WindowSubscription {
        try await pinWindowSubscriptionTrain(id: id, serviceID: serviceID, accessToken: accessToken, idempotencyKey: nil)
    }

    func clearWindowSubscriptionPinnedTrain(id: String, accessToken: String) async throws -> WindowSubscription {
        try await clearWindowSubscriptionPinnedTrain(id: id, accessToken: accessToken, idempotencyKey: nil)
    }

    func deleteWindowSubscription(id: String, accessToken: String) async throws {
        try await deleteWindowSubscription(id: id, accessToken: accessToken, idempotencyKey: nil)
    }

    func deleteItinerarySubscription(id: String, accessToken: String) async throws {
        try await deleteItinerarySubscription(id: id, accessToken: accessToken, idempotencyKey: nil)
    }
}

struct APIClient {
    var baseURL: URL
    var urlSession: URLSession

    init(baseURL: URL, urlSession: URLSession = APIClient.makeURLSession()) {
        self.baseURL = baseURL
        self.urlSession = urlSession
    }

    static func makeURLSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 60
        return URLSession(configuration: configuration)
    }

    /// Number of times a retryable request is re-issued after a transient
    /// transport error before the failure is surfaced.
    static let maxTransportRetries = 1

    /// GET/HEAD are inherently idempotent and always safe to retry. Other verbs
    /// are only retried when the caller supplied an Idempotency-Key, so a retry
    /// can't double-apply a write.
    static func isRetryableRequest(method: String, idempotencyKey: String?) -> Bool {
        let normalized = method.uppercased()
        if normalized == "GET" || normalized == "HEAD" {
            return true
        }
        if let key = idempotencyKey?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
            return true
        }
        return false
    }

    /// Transport errors worth a quick retry: a stale pooled keep-alive
    /// connection that a load balancer closed, a timeout, or a transient failure
    /// to reach the host. Genuine "no network" conditions are left to
    /// URLSession's `waitsForConnectivity`.
    static func isRetryableTransportError(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .networkConnectionLost, .timedOut, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
            return true
        default:
            return false
        }
    }

    func resetPooledConnections() async {
        await withCheckedContinuation { continuation in
            // flush(completionHandler:) clears transient caches and guarantees
            // that subsequent requests run on new TCP connections.
            urlSession.flush {
                continuation.resume()
            }
        }
    }

    func createDeviceChallenge() async throws -> DeviceChallengeResponse {
        try await send(
            path: "/v1/auth/device/challenge",
            method: "POST",
            body: Optional<String>.none
        )
    }

    func registerDevice(attemptId: String, keyId: String, attestationObject: String) async throws -> AuthResponse {
        try await send(
            path: "/v1/auth/device/register",
            method: "POST",
            body: RegisterDeviceRequest(attemptId: attemptId, keyId: keyId, attestationObject: attestationObject)
        )
    }

    func serviceStatus() async throws -> ServiceStatus {
        try await send(path: "/v1/status")
    }

    func appCapabilities() async throws -> AppCapabilitiesResponse {
        try await send(path: "/v1/app/capabilities")
    }

    func currentUser(accessToken: String) async throws -> User {
        try await send(path: "/v1/me", accessToken: accessToken)
    }

    func updateStationDefaults(input: UpdateStationDefaultsRequest, accessToken: String) async throws -> User {
        try await send(
            path: "/v1/me/station-defaults",
            method: "PATCH",
            accessToken: accessToken,
            body: input
        )
    }

    func deleteCurrentUser(accessToken: String) async throws {
        try await send(
            path: "/v1/me",
            method: "DELETE",
            accessToken: accessToken
        )
    }

    func billingProducts(accessToken: String) async throws -> BillingProductsResponse {
        try await send(path: "/v1/billing/products", accessToken: accessToken)
    }

    func syncStoreKitTransactions(signedTransactions: [String], accessToken: String) async throws -> User {
        try await send(
            path: "/v1/billing/storekit/sync",
            method: "POST",
            accessToken: accessToken,
            body: StoreKitSyncRequest(signedTransactions: signedTransactions)
        )
    }

    func searchStations(query: String, limit: Int = 8) async throws -> [StationSuggestion] {
        let response: StationSearchResponse = try await send(
            path: "/v1/stations",
            queryItems: [
                URLQueryItem(name: "query", value: query),
                URLQueryItem(name: "limit", value: String(limit))
            ]
        )
        return response.stations
    }

    func searchDirectDestinationStations(
        originCRS: String,
        query: String,
        departureStart: Date,
        windowMinutes: Int,
        limit: Int = 8
    ) async throws -> [StationSuggestion] {
        let response: StationSearchResponse = try await send(
            path: "/v1/stations/direct-destinations",
            queryItems: [
                URLQueryItem(name: "origin_crs", value: originCRS),
                URLQueryItem(name: "query", value: query),
                URLQueryItem(name: "departure_start", value: DateFormatting.apiDateTime.string(from: departureStart)),
                URLQueryItem(name: "window_minutes", value: String(windowMinutes)),
                URLQueryItem(name: "limit", value: String(limit))
            ]
        )
        return response.stations
    }

    func recommendDirectWindow(
        originCRS: String,
        destinationCRS: String,
        departureStart: Date,
        windowMinutes: Int
    ) async throws -> DirectWindowRecommendationResponse {
        try await send(
            path: "/v1/windows/direct/recommendations",
            queryItems: [
                URLQueryItem(name: "origin_crs", value: originCRS),
                URLQueryItem(name: "destination_crs", value: destinationCRS),
                URLQueryItem(name: "departure_start", value: DateFormatting.apiDateTime.string(from: departureStart)),
                URLQueryItem(name: "window_minutes", value: String(windowMinutes))
            ]
        )
    }

    func planJourney(
        originCRS: String,
        destinationCRS: String,
        departureStart: Date,
        windowMinutes: Int,
        maxChanges: Int = 3,
        limit: Int = 5
    ) async throws -> JourneyPlanResponse {
        try await send(
            path: "/v1/journeys/plan",
            queryItems: [
                URLQueryItem(name: "origin_crs", value: originCRS),
                URLQueryItem(name: "destination_crs", value: destinationCRS),
                URLQueryItem(name: "departure_after", value: DateFormatting.apiDateTime.string(from: departureStart)),
                URLQueryItem(name: "window_minutes", value: String(windowMinutes)),
                URLQueryItem(name: "max_changes", value: String(maxChanges)),
                URLQueryItem(name: "limit", value: String(limit))
            ]
        )
    }

    func getJourneyDetail(serviceID: Int, originTPL: String? = nil, destinationTPL: String? = nil) async throws -> JourneyDetail {
        var queryItems: [URLQueryItem] = []
        if let originTPL, !originTPL.isEmpty {
            queryItems.append(URLQueryItem(name: "origin_tpl", value: originTPL))
        }
        if let destinationTPL, !destinationTPL.isEmpty {
            queryItems.append(URLQueryItem(name: "destination_tpl", value: destinationTPL))
        }
        return try await send(path: "/v1/journeys/direct/\(serviceID)", queryItems: queryItems)
    }

    func createWindowSubscription(
        input: CreateWindowSubscriptionRequest,
        accessToken: String
    ) async throws -> WindowSubscription {
        try await send(
            path: "/v1/windows/direct/subscriptions",
            method: "POST",
            accessToken: accessToken,
            body: input
        )
    }

    func createItinerarySubscription(
        input: CreateItinerarySubscriptionRequest,
        accessToken: String
    ) async throws -> ItinerarySubscription {
        try await send(
            path: "/v1/itinerary-subscriptions",
            method: "POST",
            accessToken: accessToken,
            body: input
        )
    }

    func createJourneyShare(
        input: CreateJourneyShareRequest,
        accessToken: String
    ) async throws -> JourneyShareResponse {
        try await send(
            path: "/v1/journey-shares",
            method: "POST",
            accessToken: accessToken,
            body: input
        )
    }

    func getJourneyShare(id: String) async throws -> PublicJourneyShare {
        try await send(path: "/v1/journey-shares/\(id)")
    }

    func getWindowSubscription(id: String, accessToken: String) async throws -> WindowSubscription {
        try await send(path: "/v1/windows/direct/subscriptions/\(id)", accessToken: accessToken)
    }

    func getActiveWindowSubscription(accessToken: String) async throws -> WindowSubscription {
        try await send(path: "/v1/windows/direct/subscriptions/active", accessToken: accessToken)
    }

    func getActiveItinerarySubscription(accessToken: String) async throws -> ItinerarySubscription {
        try await send(path: "/v1/itinerary-subscriptions/active", accessToken: accessToken)
    }

    func getItinerarySubscription(id: String, accessToken: String) async throws -> ItinerarySubscription {
        try await send(path: "/v1/itinerary-subscriptions/\(id)", accessToken: accessToken)
    }

    func pinItineraryFirstLeg(id: String, input: PinItineraryFirstLegRequest, accessToken: String, idempotencyKey: String? = nil) async throws -> ItinerarySubscription {
        try await send(
            path: "/v1/itinerary-subscriptions/\(id)/pinned-first-leg",
            method: "PUT",
            accessToken: accessToken,
            idempotencyKey: idempotencyKey,
            body: input
        )
    }

    func clearItineraryPinnedFirstLeg(id: String, accessToken: String, idempotencyKey: String? = nil) async throws -> ItinerarySubscription {
        try await send(
            path: "/v1/itinerary-subscriptions/\(id)/pinned-first-leg",
            method: "DELETE",
            accessToken: accessToken,
            idempotencyKey: idempotencyKey
        )
    }

    func reportItineraryOriginArrival(id: String, accessToken: String, idempotencyKey: String? = nil) async throws -> ItinerarySubscription {
        try await send(
            path: "/v1/itinerary-subscriptions/\(id)/report-origin-arrival",
            method: "POST",
            accessToken: accessToken,
            idempotencyKey: idempotencyKey
        )
    }

    func reportItineraryInterchangeArrival(id: String, atCrs: String, legIndex: Int, accessToken: String, idempotencyKey: String? = nil) async throws -> ItinerarySubscription {
        try await send(
            path: "/v1/itinerary-subscriptions/\(id)/report-interchange-arrival",
            method: "POST",
            accessToken: accessToken,
            idempotencyKey: idempotencyKey,
            body: ReportItineraryInterchangeArrivalRequest(atCrs: atCrs, legIndex: legIndex)
        )
    }

    func boardItineraryLeg(id: String, legIndex: Int, pinFirstLeg: Bool, accessToken: String, idempotencyKey: String? = nil) async throws -> ItinerarySubscription {
        try await send(
            path: "/v1/itinerary-subscriptions/\(id)/board-leg",
            method: "POST",
            accessToken: accessToken,
            idempotencyKey: idempotencyKey,
            body: BoardItineraryLegRequest(legIndex: legIndex, pinFirstLeg: pinFirstLeg)
        )
    }

    func replanItineraryFromCurrentStation(id: String, fromCrs: String, accessToken: String, idempotencyKey: String? = nil) async throws -> ItinerarySubscription {
        try await send(
            path: "/v1/itinerary-subscriptions/\(id)/replan-from",
            method: "POST",
            accessToken: accessToken,
            idempotencyKey: idempotencyKey,
            body: ReplanItineraryFromRequest(fromCrs: fromCrs)
        )
    }

    func pinWindowSubscriptionTrain(id: String, serviceID: Int, accessToken: String, idempotencyKey: String? = nil) async throws -> WindowSubscription {
        try await send(
            path: "/v1/windows/direct/subscriptions/\(id)/pinned-train",
            method: "PUT",
            accessToken: accessToken,
            idempotencyKey: idempotencyKey,
            body: PinWindowSubscriptionTrainRequest(serviceId: serviceID)
        )
    }

    func clearWindowSubscriptionPinnedTrain(id: String, accessToken: String, idempotencyKey: String? = nil) async throws -> WindowSubscription {
        try await send(
            path: "/v1/windows/direct/subscriptions/\(id)/pinned-train",
            method: "DELETE",
            accessToken: accessToken,
            idempotencyKey: idempotencyKey
        )
    }

    func getWindowSubscriptionNotification(
        windowSubscriptionID: String,
        notificationID: String,
        accessToken: String
    ) async throws -> WindowSubscriptionNotificationDetail {
        try await send(
            path: "/v1/windows/direct/subscriptions/\(windowSubscriptionID)/notifications/\(notificationID)",
            accessToken: accessToken
        )
    }

    func streamWindowSubscriptionEvents(
        windowSubscriptionID: String,
        accessToken: String,
        lastEventID: String? = nil
    ) -> AsyncThrowingStream<SubscriptionStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let url = try makeURL(
                        path: "/v1/subscriptions/stream",
                        queryItems: [URLQueryItem(name: "window_subscription_id", value: windowSubscriptionID)]
                    )
                    var request = URLRequest(url: url)
                    request.httpMethod = "GET"
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
                    setStoreKitClientEnvironmentHeader(on: &request)
                    if let lastEventID, !lastEventID.isEmpty {
                        request.setValue(lastEventID, forHTTPHeaderField: "Last-Event-ID")
                    }

                    let (bytes, response) = try await urlSession.bytes(for: request)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw APIError.transport("RightTrain did not return an HTTP response.")
                    }
                    guard (200..<300).contains(httpResponse.statusCode) else {
                        let body = try await collectErrorBody(from: bytes)
                        throw APIError.from(statusCode: httpResponse.statusCode, data: body)
                    }

                    var parser = ServerSentEventParser()
                    for try await line in bytes.lines {
                        guard !Task.isCancelled else {
                            break
                        }
                        if let event = try decodeStreamEvent(parser.consume(line: line)) {
                            continuation.yield(event)
                        }
                    }
                    if let event = try decodeStreamEvent(parser.finish()) {
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch let error as APIError {
                    continuation.finish(throwing: error)
                } catch let error as DecodingError {
                    continuation.finish(throwing: APIError.decoding(error))
                } catch {
                    continuation.finish(throwing: APIError.transport(error.localizedDescription))
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func streamItinerarySubscriptionEvents(
        itinerarySubscriptionID: String,
        accessToken: String,
        lastEventID: String? = nil
    ) -> AsyncThrowingStream<SubscriptionStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let url = try makeURL(
                        path: "/v1/subscriptions/stream",
                        queryItems: [URLQueryItem(name: "itinerary_subscription_id", value: itinerarySubscriptionID)]
                    )
                    var request = URLRequest(url: url)
                    request.httpMethod = "GET"
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
                    setStoreKitClientEnvironmentHeader(on: &request)
                    if let lastEventID, !lastEventID.isEmpty {
                        request.setValue(lastEventID, forHTTPHeaderField: "Last-Event-ID")
                    }

                    let (bytes, response) = try await urlSession.bytes(for: request)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw APIError.transport("RightTrain did not return an HTTP response.")
                    }
                    guard (200..<300).contains(httpResponse.statusCode) else {
                        let body = try await collectErrorBody(from: bytes)
                        throw APIError.from(statusCode: httpResponse.statusCode, data: body)
                    }

                    var parser = ServerSentEventParser()
                    for try await line in bytes.lines {
                        guard !Task.isCancelled else {
                            break
                        }
                        if let event = try decodeStreamEvent(parser.consume(line: line)) {
                            continuation.yield(event)
                        }
                    }
                    if let event = try decodeStreamEvent(parser.finish()) {
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch let error as APIError {
                    continuation.finish(throwing: error)
                } catch let error as DecodingError {
                    continuation.finish(throwing: APIError.decoding(error))
                } catch {
                    continuation.finish(throwing: APIError.transport(error.localizedDescription))
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func deleteWindowSubscription(id: String, accessToken: String, idempotencyKey: String? = nil) async throws {
        try await send(
            path: "/v1/windows/direct/subscriptions/\(id)",
            method: "DELETE",
            accessToken: accessToken,
            idempotencyKey: idempotencyKey
        )
    }

    func deleteItinerarySubscription(id: String, accessToken: String, idempotencyKey: String? = nil) async throws {
        try await send(
            path: "/v1/itinerary-subscriptions/\(id)",
            method: "DELETE",
            accessToken: accessToken,
            idempotencyKey: idempotencyKey
        )
    }

    func listCommuteRoutines(accessToken: String) async throws -> [CommuteRoutine] {
        try await send(path: "/v1/commute/routines", accessToken: accessToken)
    }

    func createCommuteRoutine(input: CommuteRoutineMutationRequest, accessToken: String) async throws -> CommuteRoutine {
        try await send(
            path: "/v1/commute/routines",
            method: "POST",
            accessToken: accessToken,
            body: input
        )
    }

    func updateCommuteRoutine(id: String, input: CommuteRoutineMutationRequest, accessToken: String) async throws -> CommuteRoutine {
        try await send(
            path: "/v1/commute/routines/\(id)",
            method: "PUT",
            accessToken: accessToken,
            body: input
        )
    }

    func deleteCommuteRoutine(id: String, accessToken: String) async throws {
        try await send(
            path: "/v1/commute/routines/\(id)",
            method: "DELETE",
            accessToken: accessToken
        )
    }

    func registerLiveActivityToken(
        windowSubscriptionID: String,
        activityKind: String,
        input: RegisterLiveActivityTokenRequest,
        accessToken: String
    ) async throws {
        let _: APNsTokenRegistration = try await send(
            path: "/v1/windows/direct/subscriptions/\(windowSubscriptionID)/live-activities/\(activityKind)/token",
            method: "PUT",
            accessToken: accessToken,
            body: input
        )
    }

    func registerItineraryLiveActivityToken(
        itinerarySubscriptionID: String,
        activityKind: String,
        input: RegisterLiveActivityTokenRequest,
        accessToken: String
    ) async throws {
        let _: APNsTokenRegistration = try await send(
            path: "/v1/itinerary-subscriptions/\(itinerarySubscriptionID)/live-activities/\(activityKind)/token",
            method: "PUT",
            accessToken: accessToken,
            body: input
        )
    }

    func registerLiveActivityPushToStartToken(
        clientDeviceID: String,
        input: RegisterLiveActivityTokenRequest,
        accessToken: String
    ) async throws {
        let _: APNsTokenRegistration = try await send(
            path: "/v1/devices/\(clientDeviceID)/apns/live-activity-push-to-start-token",
            method: "PUT",
            accessToken: accessToken,
            body: input
        )
    }

    func deleteLiveActivityPushToStartToken(
        clientDeviceID: String,
        activityID: String,
        environment: String?,
        accessToken: String
    ) async throws {
        var queryItems = [URLQueryItem(name: "activityId", value: activityID)]
        if let environment, !environment.isEmpty {
            queryItems.append(URLQueryItem(name: "environment", value: environment))
        }
        try await send(
            path: "/v1/devices/\(clientDeviceID)/apns/live-activity-push-to-start-token",
            method: "DELETE",
            queryItems: queryItems,
            accessToken: accessToken
        )
    }

    func deleteLiveActivityToken(
        windowSubscriptionID: String,
        activityKind: String,
        activityID: String,
        environment: String?,
        accessToken: String
    ) async throws {
        var queryItems = [URLQueryItem(name: "activityId", value: activityID)]
        if let environment, !environment.isEmpty {
            queryItems.append(URLQueryItem(name: "environment", value: environment))
        }
        try await send(
            path: "/v1/windows/direct/subscriptions/\(windowSubscriptionID)/live-activities/\(activityKind)/token",
            method: "DELETE",
            queryItems: queryItems,
            accessToken: accessToken
        )
    }

    func deleteItineraryLiveActivityToken(
        itinerarySubscriptionID: String,
        activityKind: String,
        activityID: String,
        environment: String?,
        accessToken: String
    ) async throws {
        var queryItems = [URLQueryItem(name: "activityId", value: activityID)]
        if let environment, !environment.isEmpty {
            queryItems.append(URLQueryItem(name: "environment", value: environment))
        }
        try await send(
            path: "/v1/itinerary-subscriptions/\(itinerarySubscriptionID)/live-activities/\(activityKind)/token",
            method: "DELETE",
            queryItems: queryItems,
            accessToken: accessToken
        )
    }

    func registerAPNsAlertToken(
        clientDeviceID: String,
        input: RegisterAPNsAlertTokenRequest,
        accessToken: String
    ) async throws {
        let _: APNsTokenRegistration = try await send(
            path: "/v1/devices/\(clientDeviceID)/apns/alert-token",
            method: "PUT",
            accessToken: accessToken,
            body: input
        )
    }

    func deleteAPNsAlertToken(
        clientDeviceID: String,
        environment: String?,
        accessToken: String
    ) async throws {
        var queryItems: [URLQueryItem] = []
        if let environment, !environment.isEmpty {
            queryItems.append(URLQueryItem(name: "environment", value: environment))
        }
        try await send(
            path: "/v1/devices/\(clientDeviceID)/apns/alert-token",
            method: "DELETE",
            queryItems: queryItems,
            accessToken: accessToken
        )
    }

    private func send<Response: Decodable>(
        path: String,
        method: String = "GET",
        queryItems: [URLQueryItem] = [],
        accessToken: String? = nil,
        idempotencyKey: String? = nil
    ) async throws -> Response {
        try await send(
            path: path,
            method: method,
            queryItems: queryItems,
            accessToken: accessToken,
            idempotencyKey: idempotencyKey,
            body: Optional<String>.none
        )
    }

    private func send<RequestBody: Encodable, Response: Decodable>(
        path: String,
        method: String = "GET",
        queryItems: [URLQueryItem] = [],
        accessToken: String? = nil,
        idempotencyKey: String? = nil,
        body: RequestBody?
    ) async throws -> Response {
        do {
            let data = try await sendData(
                path: path,
                method: method,
                queryItems: queryItems,
                accessToken: accessToken,
                idempotencyKey: idempotencyKey,
                body: body
            )
            return try JSONCoding.decoder.decode(Response.self, from: data)
        } catch let error as APIError {
            throw error
        } catch let error as DecodingError {
            throw APIError.decoding(error)
        } catch {
            throw APIError.transport(error.localizedDescription)
        }
    }

    private func send(
        path: String,
        method: String = "GET",
        queryItems: [URLQueryItem] = [],
        accessToken: String? = nil,
        idempotencyKey: String? = nil
    ) async throws {
        try await send(
            path: path,
            method: method,
            queryItems: queryItems,
            accessToken: accessToken,
            idempotencyKey: idempotencyKey,
            body: Optional<String>.none
        )
    }

    private func send<RequestBody: Encodable>(
        path: String,
        method: String = "GET",
        queryItems: [URLQueryItem] = [],
        accessToken: String? = nil,
        idempotencyKey: String? = nil,
        body: RequestBody?
    ) async throws {
        _ = try await sendData(
            path: path,
            method: method,
            queryItems: queryItems,
            accessToken: accessToken,
            idempotencyKey: idempotencyKey,
            body: body
        )
    }

    private func sendData<RequestBody: Encodable>(
        path: String,
        method: String = "GET",
        queryItems: [URLQueryItem] = [],
        accessToken: String? = nil,
        idempotencyKey: String? = nil,
        body: RequestBody?
    ) async throws -> Data {
        let url = try makeURL(path: path, queryItems: queryItems)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        setStoreKitClientEnvironmentHeader(on: &request)

        if let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        if let idempotencyKey = idempotencyKey?.trimmingCharacters(in: .whitespacesAndNewlines), !idempotencyKey.isEmpty {
            request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        }

        if let body {
            request.httpBody = try JSONCoding.encoder.encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let canRetry = APIClient.isRetryableRequest(method: method, idempotencyKey: idempotencyKey)
        var attemptsRemaining = canRetry ? APIClient.maxTransportRetries : 0

        while true {
            do {
                let (data, response) = try await urlSession.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw APIError.transport("RightTrain did not return an HTTP response.")
                }

                guard (200..<300).contains(httpResponse.statusCode) else {
                    throw APIError.from(statusCode: httpResponse.statusCode, data: data)
                }

                return data
            } catch let error as APIError {
                throw error
            } catch {
                // A cloud load balancer can silently drop a pooled keep-alive
                // connection; URLSession only notices the dead socket when it
                // reuses it, surfacing a transient error. Retrying forces a fresh
                // connection and usually succeeds immediately.
                if attemptsRemaining > 0, APIClient.isRetryableTransportError(error) {
                    attemptsRemaining -= 1
                    continue
                }
                throw APIError.transport(error.localizedDescription)
            }
        }
    }

    private func setStoreKitClientEnvironmentHeader(on request: inout URLRequest) {
        let environment = StoreKitClientEnvironment.current()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard environment == "sandbox" || environment == "production" else {
            return
        }
        request.setValue(environment, forHTTPHeaderField: "X-RightTrain-StoreKit-Environment")
    }

    private func makeURL(path: String, queryItems: [URLQueryItem] = []) throws -> URL {
        let endpoint = baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            + "/"
            + path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var components = URLComponents(string: endpoint)
        components?.queryItems = queryItems.isEmpty ? nil : queryItems

        guard let url = components?.url else {
            throw APIError.invalidURL
        }
        return url
    }

    private func collectErrorBody(from bytes: URLSession.AsyncBytes) async throws -> Data {
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            if data.count >= 4096 {
                break
            }
        }
        return data
    }

    private func decodeStreamEvent(_ event: ServerSentEvent?) throws -> SubscriptionStreamEvent? {
        guard let event else {
            return nil
        }
        var envelope: SubscriptionStreamEnvelope?
        if !event.data.isEmpty {
            envelope = try JSONCoding.decoder.decode(SubscriptionStreamEnvelope.self, from: Data(event.data.utf8))
        }
        return SubscriptionStreamEvent(id: event.id, event: event.event, envelope: envelope)
    }
}

extension APIClient: APIClienting {}

enum StoreKitClientEnvironment {
    static func current(bundle: Bundle = .main) -> String {
        if bundle.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt" {
            return "sandbox"
        }
        return "production"
    }
}

private struct ServerSentEvent {
    var id: String?
    var event: String?
    var data: String
}

private struct ServerSentEventParser {
    private var id: String?
    private var event: String?
    private var dataLines: [String] = []

    mutating func consume(line: String) -> ServerSentEvent? {
        if line.isEmpty {
            return dispatch()
        }
        if line.hasPrefix(":") {
            return nil
        }

        let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        let field = String(parts.first ?? "")
        var value = parts.count > 1 ? String(parts[1]) : ""
        if value.hasPrefix(" ") {
            value.removeFirst()
        }

        switch field {
        case "id":
            id = value
        case "event":
            event = value
        case "data":
            dataLines.append(value)
        default:
            break
        }
        return nil
    }

    mutating func finish() -> ServerSentEvent? {
        dispatch()
    }

    private mutating func dispatch() -> ServerSentEvent? {
        guard id != nil || event != nil || !dataLines.isEmpty else {
            return nil
        }
        defer {
            id = nil
            event = nil
            dataLines = []
        }
        return ServerSentEvent(id: id, event: event, data: dataLines.joined(separator: "\n"))
    }
}

enum JSONCoding {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(DateFormatting.apiDateTime.string(from: date))
        }
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = DateFormatting.date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid RFC3339 date: \(value)")
        }
        return decoder
    }()
}

enum DateFormatting {
    static let apiDateTime: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let fallbackAPIDateTime: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func date(from value: String) -> Date? {
        apiDateTime.date(from: value) ?? fallbackAPIDateTime.date(from: value)
    }
}
