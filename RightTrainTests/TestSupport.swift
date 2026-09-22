@testable import RightTrain
import Foundation
import UIKit
import UserNotifications

enum TestFailure: Error {
    case unimplemented
}

final class FakeAPIClient: APIClienting {
    struct DeviceRegistrationRequest {
        var attemptId: String
        var keyId: String
        var attestationObject: String
    }

    struct RecommendationRequest {
        var originCRS: String
        var destinationCRS: String
        var departureStart: Date
        var windowMinutes: Int
    }

    struct JourneyPlanRequest {
        var originCRS: String
        var destinationCRS: String
        var departureStart: Date
        var windowMinutes: Int
        var maxChanges: Int
        var limit: Int
    }

    struct DirectDestinationStationRequest {
        var originCRS: String
        var query: String
        var departureStart: Date
        var windowMinutes: Int
        var limit: Int
    }

    struct NearbyStationRequest {
        var latitude: Double
        var longitude: Double
        var selectionRole: StationPickerSelectionRole
        var routeMode: StationPickerRouteMode
        var originCRS: String?
        var departureStart: Date?
        var windowMinutes: Int
        var limit: Int
    }

    var deviceChallengeResult: Result<DeviceChallengeResponse, Error> = .success(
        DeviceChallengeResponse(attemptId: "attempt-1", challenge: "Y2hhbGxlbmdl", expiresAt: Date().addingTimeInterval(300))
    )
    var serviceStatusResult: Result<ServiceStatus, Error> = .success(
        ServiceStatus(status: "operational", checkedAt: Date(), components: [], message: "Operational")
    )
    var appCapabilitiesResult: Result<AppCapabilitiesResponse, Error> = .success(
        AppCapabilitiesResponse(multiLegRoutingEnabled: false)
    )
    var registerDeviceResult: Result<AuthResponse, Error> = .failure(TestFailure.unimplemented)
    var accountRegistrationOptionsResult: Result<AccountRegistrationOptionsResponse, Error> = .success(TestFactory.accountCredentialOptions())
    var registerAccountResult: Result<RegisterAccountResponse, Error> = .success(TestFactory.registerAccountResponse())
    var accountAssertionOptionsResult: Result<AccountAssertionOptionsResponse, Error> = .success(TestFactory.accountAssertionOptions())
    var accountSignInResult: Result<AuthResponse, Error> = .failure(TestFailure.unimplemented)
    var accountRecoveryResult: Result<AuthResponse, Error> = .failure(TestFailure.unimplemented)
    var currentUserResult: Result<User, Error> = .failure(TestFailure.unimplemented)
    var updateStationDefaultsResult: Result<User, Error> = .failure(TestFailure.unimplemented)
    var accountPreferenceSetResult: Result<AccountPreferenceSet, Error> = .success(TestFactory.accountPreferenceSet())
    var updateAccountPreferenceSetResult: Result<UpdateAccountPreferenceSetResponse, Error> = .success(UpdateAccountPreferenceSetResponse(version: 2, updatedAt: Date(timeIntervalSince1970: 0), conflict: nil))
    var linkedDevicesResult: Result<LinkedDevicesResponse, Error> = .success(LinkedDevicesResponse(devices: []))
    var accountExportResult: Result<AccountExportResponse, Error> = .success(TestFactory.accountExportResponse())
    var billingProductsResult: Result<BillingProductsResponse, Error> = .success(BillingProductsResponse(products: [], entitlements: UserEntitlements(tier: "free_beta", status: "active", activeWindowLimit: 1, commuteRoutineLimit: 2)))
    var storeKitSyncResult: Result<User, Error> = .failure(TestFailure.unimplemented)
    var stationSearchResult: Result<[StationSuggestion], Error> = .success([])
    var stationSearchResultsByQuery: [String: [StationSuggestion]] = [:]
    var directDestinationStationResult: Result<[StationSuggestion], Error> = .success([])
    var nearbyStationResult: Result<NearbyStationSearchResponse, Error> = .success(NearbyStationSearchResponse(
        stations: [],
        generatedAt: Date(timeIntervalSince1970: 0),
        sourceFreshness: StationMetadataFreshness(status: "fresh", lastSuccessfulImportAt: nil, unavailableReason: nil)
    ))
    var recommendationsResult: Result<DirectWindowRecommendationResponse, Error> = .failure(TestFailure.unimplemented)
    var journeyPlanResult: Result<JourneyPlanResponse, Error> = .failure(TestFailure.unimplemented)
    var commuteRoutinesResult: Result<[CommuteRoutine], Error> = .success([])
    var commuteRoutineResult: Result<CommuteRoutine, Error> = .failure(TestFailure.unimplemented)
    var createWindowResult: Result<WindowSubscription, Error> = .failure(TestFailure.unimplemented)
    var createItineraryResult: Result<ItinerarySubscription, Error> = .failure(TestFailure.unimplemented)
    var createJourneyShareResult: Result<JourneyShareResponse, Error> = .failure(TestFailure.unimplemented)
    var publicJourneyShareResult: Result<PublicJourneyShare, Error> = .failure(TestFailure.unimplemented)
    var windowResult: Result<WindowSubscription, Error> = .failure(TestFactory.notFoundError())
    var activeWindowResult: Result<WindowSubscription, Error> = .failure(TestFactory.notFoundError())
    var activeItineraryResult: Result<ItinerarySubscription, Error> = .failure(TestFactory.notFoundError())
    var itineraryResult: Result<ItinerarySubscription, Error> = .failure(TestFactory.notFoundError())
    var pinWindowResult: Result<WindowSubscription, Error> = .failure(TestFailure.unimplemented)
    var clearPinnedWindowResult: Result<WindowSubscription, Error> = .failure(TestFailure.unimplemented)
    var pinItineraryResult: Result<ItinerarySubscription, Error> = .failure(TestFailure.unimplemented)
    var clearPinnedItineraryResult: Result<ItinerarySubscription, Error> = .failure(TestFailure.unimplemented)
    var reportItineraryOriginArrivalResult: Result<ItinerarySubscription, Error> = .failure(TestFailure.unimplemented)
    var reportItineraryInterchangeArrivalResult: Result<ItinerarySubscription, Error> = .failure(TestFailure.unimplemented)
    var boardItineraryLegResult: Result<ItinerarySubscription, Error> = .failure(TestFailure.unimplemented)
    var replanItineraryFromCurrentStationResult: Result<ItinerarySubscription, Error> = .failure(TestFailure.unimplemented)
    var windowNotificationResult: Result<WindowSubscriptionNotificationDetail, Error> = .failure(TestFailure.unimplemented)
    var journeyDetailResult: Result<JourneyDetail, Error> = .failure(TestFailure.unimplemented)
    var journeyDetailResults: [Result<JourneyDetail, Error>] = []
    var journeyDetailHandler: ((Int, String?, String?) async throws -> JourneyDetail)?
    var deleteWindowError: Error?
    var deleteItineraryError: Error?
    var deleteCommuteRoutineError: Error?
    var deleteUserError: Error?
    var registerLiveActivityTokenError: Error?
    var registerLiveActivityPushToStartTokenError: Error?
    var deleteLiveActivityPushToStartTokenError: Error?
    var deleteLiveActivityTokenError: Error?
    var registerAPNsTokenError: Error?
    var deleteAPNsTokenError: Error?
    var streamEvents: [SubscriptionStreamEvent] = []
    var streamItineraryEvents: [SubscriptionStreamEvent] = []
    var streamError: Error?
    var streamItineraryError: Error?

    var deviceChallengeCallCount = 0
    var serviceStatusCallCount = 0
    var resetPooledConnectionsCallCount = 0
    var appCapabilitiesCallCount = 0
    var registerDeviceRequests: [DeviceRegistrationRequest] = []
    var accountRegistrationOptionTokens: [String] = []
    var registerAccountRequests: [(input: RegisterAccountRequest, accessToken: String)] = []
    var accountAssertionOptionHints: [String?] = []
    var accountSignInRequests: [AccountSignInRequest] = []
    var accountRecoveryRequests: [AccountRecoveryRequest] = []
    var currentUserAccessTokens: [String] = []
    var updateStationDefaultsRequests: [(input: UpdateStationDefaultsRequest, accessToken: String)] = []
    var deleteCurrentUserAccessTokens: [String] = []
    var accountPreferenceSetTokens: [String] = []
    var updateAccountPreferenceSetRequests: [(input: UpdateAccountPreferenceSetRequest, accessToken: String)] = []
    var linkedDevicesAccessTokens: [String] = []
    var revokedLinkedDevices: [(id: String, accessToken: String)] = []
    var accountExportAccessTokens: [String] = []
    var billingProductAccessTokens: [String] = []
    var storeKitSyncRequests: [(signedTransactions: [String], accessToken: String)] = []
    var stationSearchRequests: [(query: String, limit: Int)] = []
    var directDestinationStationRequests: [DirectDestinationStationRequest] = []
    var nearbyStationRequests: [NearbyStationRequest] = []
    var recommendationRequests: [RecommendationRequest] = []
    var journeyPlanRequests: [JourneyPlanRequest] = []
    var createWindowRequests: [(input: CreateWindowSubscriptionRequest, accessToken: String)] = []
    var createItineraryRequests: [(input: CreateItinerarySubscriptionRequest, accessToken: String)] = []
    var createJourneyShareRequests: [(input: CreateJourneyShareRequest, accessToken: String)] = []
    var publicJourneyShareRequests: [String] = []
    var journeyDetailRequests: [(serviceID: Int, originTPL: String?, destinationTPL: String?)] = []
    var getWindowRequests: [(id: String, accessToken: String)] = []
    var getItineraryRequests: [(id: String, accessToken: String)] = []
    var getActiveWindowAccessTokens: [String] = []
    var getActiveItineraryAccessTokens: [String] = []
    var pinWindowRequests: [(id: String, serviceID: Int, accessToken: String, idempotencyKey: String?)] = []
    var clearPinnedWindowRequests: [(id: String, accessToken: String, idempotencyKey: String?)] = []
    var pinItineraryRequests: [(id: String, input: PinItineraryFirstLegRequest, accessToken: String, idempotencyKey: String?)] = []
    var clearPinnedItineraryRequests: [(id: String, accessToken: String, idempotencyKey: String?)] = []
    var reportItineraryOriginArrivalRequests: [(id: String, accessToken: String, idempotencyKey: String?)] = []
    var reportItineraryInterchangeArrivalRequests: [(id: String, atCrs: String, legIndex: Int, accessToken: String, idempotencyKey: String?)] = []
    var boardItineraryLegRequests: [(id: String, legIndex: Int, pinFirstLeg: Bool, accessToken: String, idempotencyKey: String?)] = []
    var replanItineraryFromCurrentStationRequests: [(id: String, fromCrs: String, accessToken: String, idempotencyKey: String?)] = []
    var windowNotificationRequests: [(windowSubscriptionID: String, notificationID: String, accessToken: String)] = []
    var deleteWindowRequests: [(id: String, accessToken: String, idempotencyKey: String?)] = []
    var deleteItineraryRequests: [(id: String, accessToken: String, idempotencyKey: String?)] = []
    var listCommuteRoutineAccessTokens: [String] = []
    var createCommuteRoutineRequests: [(input: CommuteRoutineMutationRequest, accessToken: String)] = []
    var updateCommuteRoutineRequests: [(id: String, input: CommuteRoutineMutationRequest, accessToken: String)] = []
    var deleteCommuteRoutineRequests: [(id: String, accessToken: String)] = []
    var registerLiveActivityTokenRequests: [(windowID: String, activityKind: String, input: RegisterLiveActivityTokenRequest, accessToken: String)] = []
    var registerItineraryLiveActivityTokenRequests: [(itineraryID: String, activityKind: String, input: RegisterLiveActivityTokenRequest, accessToken: String)] = []
    var registerLiveActivityPushToStartTokenRequests: [(clientDeviceID: String, activityID: String, input: RegisterLiveActivityTokenRequest, accessToken: String)] = []
    var deleteLiveActivityPushToStartTokenRequests: [(clientDeviceID: String, activityID: String, environment: String?, accessToken: String)] = []
    var deleteLiveActivityTokenRequests: [(windowID: String, activityKind: String, activityID: String, environment: String?, accessToken: String)] = []
    var deleteItineraryLiveActivityTokenRequests: [(itineraryID: String, activityKind: String, activityID: String, environment: String?, accessToken: String)] = []
    var registerAPNsTokenRequests: [(clientDeviceID: String, accessToken: String)] = []
    var deleteAPNsTokenRequests: [(clientDeviceID: String, environment: String?, accessToken: String)] = []
    var streamWindowRequests: [(windowSubscriptionID: String, accessToken: String, lastEventID: String?)] = []
    var streamItineraryRequests: [(itinerarySubscriptionID: String, accessToken: String, lastEventID: String?)] = []

    func createDeviceChallenge() async throws -> DeviceChallengeResponse {
        deviceChallengeCallCount += 1
        return try deviceChallengeResult.get()
    }

    func serviceStatus() async throws -> ServiceStatus {
        serviceStatusCallCount += 1
        return try serviceStatusResult.get()
    }

    func resetPooledConnections() async {
        resetPooledConnectionsCallCount += 1
    }

    func appCapabilities() async throws -> AppCapabilitiesResponse {
        appCapabilitiesCallCount += 1
        return try appCapabilitiesResult.get()
    }

    func registerDevice(attemptId: String, keyId: String, attestationObject: String) async throws -> AuthResponse {
        registerDeviceRequests.append(DeviceRegistrationRequest(attemptId: attemptId, keyId: keyId, attestationObject: attestationObject))
        return try registerDeviceResult.get()
    }

    func createAccountRegistrationOptions(accessToken: String) async throws -> AccountRegistrationOptionsResponse {
        accountRegistrationOptionTokens.append(accessToken)
        return try accountRegistrationOptionsResult.get()
    }

    func registerAccount(input: RegisterAccountRequest, accessToken: String) async throws -> RegisterAccountResponse {
        registerAccountRequests.append((input, accessToken))
        return try registerAccountResult.get()
    }

    func createAccountAssertionOptions(credentialHint: String?) async throws -> AccountAssertionOptionsResponse {
        accountAssertionOptionHints.append(credentialHint)
        return try accountAssertionOptionsResult.get()
    }

    func signInWithAccount(input: AccountSignInRequest) async throws -> AuthResponse {
        accountSignInRequests.append(input)
        return try accountSignInResult.get()
    }

    func recoverAccount(input: AccountRecoveryRequest) async throws -> AuthResponse {
        accountRecoveryRequests.append(input)
        return try accountRecoveryResult.get()
    }

    func currentUser(accessToken: String) async throws -> User {
        currentUserAccessTokens.append(accessToken)
        return try currentUserResult.get()
    }

    func updateStationDefaults(input: UpdateStationDefaultsRequest, accessToken: String) async throws -> User {
        updateStationDefaultsRequests.append((input, accessToken))
        return try updateStationDefaultsResult.get()
    }

    func deleteCurrentUser(accessToken: String) async throws {
        deleteCurrentUserAccessTokens.append(accessToken)
        if let deleteUserError {
            throw deleteUserError
        }
    }

    func getAccountPreferenceSet(accessToken: String) async throws -> AccountPreferenceSet {
        accountPreferenceSetTokens.append(accessToken)
        return try accountPreferenceSetResult.get()
    }

    func updateAccountPreferenceSet(input: UpdateAccountPreferenceSetRequest, accessToken: String) async throws -> UpdateAccountPreferenceSetResponse {
        updateAccountPreferenceSetRequests.append((input, accessToken))
        return try updateAccountPreferenceSetResult.get()
    }

    func listLinkedDevices(accessToken: String) async throws -> LinkedDevicesResponse {
        linkedDevicesAccessTokens.append(accessToken)
        return try linkedDevicesResult.get()
    }

    func revokeLinkedDevice(id: String, accessToken: String) async throws {
        revokedLinkedDevices.append((id, accessToken))
    }

    func exportAccountPreferences(accessToken: String) async throws -> AccountExportResponse {
        accountExportAccessTokens.append(accessToken)
        return try accountExportResult.get()
    }

    func billingProducts(accessToken: String) async throws -> BillingProductsResponse {
        billingProductAccessTokens.append(accessToken)
        return try billingProductsResult.get()
    }

    func syncStoreKitTransactions(signedTransactions: [String], accessToken: String) async throws -> User {
        storeKitSyncRequests.append((signedTransactions, accessToken))
        return try storeKitSyncResult.get()
    }

    func searchStations(query: String, limit: Int) async throws -> [StationSuggestion] {
        stationSearchRequests.append((query, limit))
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if let stations = stationSearchResultsByQuery[normalized] {
            return stations
        }
        return try stationSearchResult.get()
    }

    func searchDirectDestinationStations(
        originCRS: String,
        query: String,
        departureStart: Date,
        windowMinutes: Int,
        limit: Int
    ) async throws -> [StationSuggestion] {
        directDestinationStationRequests.append(DirectDestinationStationRequest(
            originCRS: originCRS,
            query: query,
            departureStart: departureStart,
            windowMinutes: windowMinutes,
            limit: limit
        ))
        return try directDestinationStationResult.get()
    }

    func searchNearbyStations(
        latitude: Double,
        longitude: Double,
        selectionRole: StationPickerSelectionRole,
        routeMode: StationPickerRouteMode,
        originCRS: String?,
        departureStart: Date?,
        windowMinutes: Int,
        limit: Int
    ) async throws -> NearbyStationSearchResponse {
        nearbyStationRequests.append(NearbyStationRequest(
            latitude: latitude,
            longitude: longitude,
            selectionRole: selectionRole,
            routeMode: routeMode,
            originCRS: originCRS,
            departureStart: departureStart,
            windowMinutes: windowMinutes,
            limit: limit
        ))
        return try nearbyStationResult.get()
    }

    func recommendDirectWindow(
        originCRS: String,
        destinationCRS: String,
        departureStart: Date,
        windowMinutes: Int
    ) async throws -> DirectWindowRecommendationResponse {
        recommendationRequests.append(RecommendationRequest(
            originCRS: originCRS,
            destinationCRS: destinationCRS,
            departureStart: departureStart,
            windowMinutes: windowMinutes
        ))
        return try recommendationsResult.get()
    }

    func planJourney(
        originCRS: String,
        destinationCRS: String,
        departureStart: Date,
        windowMinutes: Int,
        maxChanges: Int,
        limit: Int
    ) async throws -> JourneyPlanResponse {
        journeyPlanRequests.append(JourneyPlanRequest(
            originCRS: originCRS,
            destinationCRS: destinationCRS,
            departureStart: departureStart,
            windowMinutes: windowMinutes,
            maxChanges: maxChanges,
            limit: limit
        ))
        return try journeyPlanResult.get()
    }

    func getJourneyDetail(serviceID: Int, originTPL: String?, destinationTPL: String?) async throws -> JourneyDetail {
        journeyDetailRequests.append((serviceID, originTPL, destinationTPL))
        if let journeyDetailHandler {
            return try await journeyDetailHandler(serviceID, originTPL, destinationTPL)
        }
        if !journeyDetailResults.isEmpty {
            return try journeyDetailResults.removeFirst().get()
        }
        return try journeyDetailResult.get()
    }

    func createWindowSubscription(
        input: CreateWindowSubscriptionRequest,
        accessToken: String
    ) async throws -> WindowSubscription {
        createWindowRequests.append((input, accessToken))
        return try createWindowResult.get()
    }

    func createItinerarySubscription(
        input: CreateItinerarySubscriptionRequest,
        accessToken: String
    ) async throws -> ItinerarySubscription {
        createItineraryRequests.append((input, accessToken))
        return try createItineraryResult.get()
    }

    func createJourneyShare(
        input: CreateJourneyShareRequest,
        accessToken: String
    ) async throws -> JourneyShareResponse {
        createJourneyShareRequests.append((input, accessToken))
        return try createJourneyShareResult.get()
    }

    func getJourneyShare(id: String) async throws -> PublicJourneyShare {
        publicJourneyShareRequests.append(id)
        return try publicJourneyShareResult.get()
    }

    func getWindowSubscription(id: String, accessToken: String) async throws -> WindowSubscription {
        getWindowRequests.append((id, accessToken))
        return try windowResult.get()
    }

    func getActiveWindowSubscription(accessToken: String) async throws -> WindowSubscription {
        getActiveWindowAccessTokens.append(accessToken)
        return try activeWindowResult.get()
    }

    func getActiveItinerarySubscription(accessToken: String) async throws -> ItinerarySubscription {
        getActiveItineraryAccessTokens.append(accessToken)
        return try activeItineraryResult.get()
    }

    func getItinerarySubscription(id: String, accessToken: String) async throws -> ItinerarySubscription {
        getItineraryRequests.append((id, accessToken))
        return try itineraryResult.get()
    }

    func pinItineraryFirstLeg(id: String, input: PinItineraryFirstLegRequest, accessToken: String, idempotencyKey: String? = nil) async throws -> ItinerarySubscription {
        pinItineraryRequests.append((id, input, accessToken, idempotencyKey))
        return try pinItineraryResult.get()
    }

    func clearItineraryPinnedFirstLeg(id: String, accessToken: String, idempotencyKey: String? = nil) async throws -> ItinerarySubscription {
        clearPinnedItineraryRequests.append((id, accessToken, idempotencyKey))
        return try clearPinnedItineraryResult.get()
    }

    func reportItineraryOriginArrival(id: String, accessToken: String, idempotencyKey: String? = nil) async throws -> ItinerarySubscription {
        reportItineraryOriginArrivalRequests.append((id, accessToken, idempotencyKey))
        return try reportItineraryOriginArrivalResult.get()
    }

    func reportItineraryInterchangeArrival(id: String, atCrs: String, legIndex: Int, accessToken: String, idempotencyKey: String? = nil) async throws -> ItinerarySubscription {
        reportItineraryInterchangeArrivalRequests.append((id, atCrs, legIndex, accessToken, idempotencyKey))
        return try reportItineraryInterchangeArrivalResult.get()
    }

    func boardItineraryLeg(id: String, legIndex: Int, pinFirstLeg: Bool, accessToken: String, idempotencyKey: String? = nil) async throws -> ItinerarySubscription {
        boardItineraryLegRequests.append((id, legIndex, pinFirstLeg, accessToken, idempotencyKey))
        return try boardItineraryLegResult.get()
    }

    func replanItineraryFromCurrentStation(id: String, fromCrs: String, accessToken: String, idempotencyKey: String? = nil) async throws -> ItinerarySubscription {
        replanItineraryFromCurrentStationRequests.append((id, fromCrs, accessToken, idempotencyKey))
        return try replanItineraryFromCurrentStationResult.get()
    }

    func pinWindowSubscriptionTrain(id: String, serviceID: Int, accessToken: String, idempotencyKey: String? = nil) async throws -> WindowSubscription {
        pinWindowRequests.append((id, serviceID, accessToken, idempotencyKey))
        return try pinWindowResult.get()
    }

    func clearWindowSubscriptionPinnedTrain(id: String, accessToken: String, idempotencyKey: String? = nil) async throws -> WindowSubscription {
        clearPinnedWindowRequests.append((id, accessToken, idempotencyKey))
        return try clearPinnedWindowResult.get()
    }

    func getWindowSubscriptionNotification(
        windowSubscriptionID: String,
        notificationID: String,
        accessToken: String
    ) async throws -> WindowSubscriptionNotificationDetail {
        windowNotificationRequests.append((windowSubscriptionID, notificationID, accessToken))
        return try windowNotificationResult.get()
    }

    func streamWindowSubscriptionEvents(
        windowSubscriptionID: String,
        accessToken: String,
        lastEventID: String?
    ) -> AsyncThrowingStream<SubscriptionStreamEvent, Error> {
        streamWindowRequests.append((windowSubscriptionID, accessToken, lastEventID))
        let events = streamEvents
        let error = streamError
        return AsyncThrowingStream { continuation in
            for event in events {
                continuation.yield(event)
            }
            if let error {
                continuation.finish(throwing: error)
            } else {
                continuation.finish()
            }
        }
    }

    func streamItinerarySubscriptionEvents(
        itinerarySubscriptionID: String,
        accessToken: String,
        lastEventID: String?
    ) -> AsyncThrowingStream<SubscriptionStreamEvent, Error> {
        streamItineraryRequests.append((itinerarySubscriptionID, accessToken, lastEventID))
        let events = streamItineraryEvents
        let error = streamItineraryError
        return AsyncThrowingStream { continuation in
            for event in events {
                continuation.yield(event)
            }
            if let error {
                continuation.finish(throwing: error)
            } else {
                continuation.finish()
            }
        }
    }

    func deleteWindowSubscription(id: String, accessToken: String, idempotencyKey: String? = nil) async throws {
        deleteWindowRequests.append((id, accessToken, idempotencyKey))
        if let deleteWindowError {
            throw deleteWindowError
        }
    }

    func deleteItinerarySubscription(id: String, accessToken: String, idempotencyKey: String? = nil) async throws {
        deleteItineraryRequests.append((id, accessToken, idempotencyKey))
        if let deleteItineraryError {
            throw deleteItineraryError
        }
    }

    func listCommuteRoutines(accessToken: String) async throws -> [CommuteRoutine] {
        listCommuteRoutineAccessTokens.append(accessToken)
        return try commuteRoutinesResult.get()
    }

    func createCommuteRoutine(input: CommuteRoutineMutationRequest, accessToken: String) async throws -> CommuteRoutine {
        createCommuteRoutineRequests.append((input, accessToken))
        return try commuteRoutineResult.get()
    }

    func updateCommuteRoutine(id: String, input: CommuteRoutineMutationRequest, accessToken: String) async throws -> CommuteRoutine {
        updateCommuteRoutineRequests.append((id, input, accessToken))
        return try commuteRoutineResult.get()
    }

    func deleteCommuteRoutine(id: String, accessToken: String) async throws {
        deleteCommuteRoutineRequests.append((id, accessToken))
        if let deleteCommuteRoutineError {
            throw deleteCommuteRoutineError
        }
    }

    func registerLiveActivityToken(
        windowSubscriptionID: String,
        activityKind: String,
        input: RegisterLiveActivityTokenRequest,
        accessToken: String
    ) async throws {
        registerLiveActivityTokenRequests.append((windowSubscriptionID, activityKind, input, accessToken))
        if let registerLiveActivityTokenError {
            throw registerLiveActivityTokenError
        }
    }

    func registerItineraryLiveActivityToken(
        itinerarySubscriptionID: String,
        activityKind: String,
        input: RegisterLiveActivityTokenRequest,
        accessToken: String
    ) async throws {
        registerItineraryLiveActivityTokenRequests.append((itinerarySubscriptionID, activityKind, input, accessToken))
        if let registerLiveActivityTokenError {
            throw registerLiveActivityTokenError
        }
    }

    func registerLiveActivityPushToStartToken(
        clientDeviceID: String,
        input: RegisterLiveActivityTokenRequest,
        accessToken: String
    ) async throws {
        registerLiveActivityPushToStartTokenRequests.append((clientDeviceID, input.activityId, input, accessToken))
        if let registerLiveActivityPushToStartTokenError {
            throw registerLiveActivityPushToStartTokenError
        }
    }

    func deleteLiveActivityPushToStartToken(
        clientDeviceID: String,
        activityID: String,
        environment: String?,
        accessToken: String
    ) async throws {
        deleteLiveActivityPushToStartTokenRequests.append((clientDeviceID, activityID, environment, accessToken))
        if let deleteLiveActivityPushToStartTokenError {
            throw deleteLiveActivityPushToStartTokenError
        }
    }

    func deleteLiveActivityToken(
        windowSubscriptionID: String,
        activityKind: String,
        activityID: String,
        environment: String?,
        accessToken: String
    ) async throws {
        deleteLiveActivityTokenRequests.append((windowSubscriptionID, activityKind, activityID, environment, accessToken))
        if let deleteLiveActivityTokenError {
            throw deleteLiveActivityTokenError
        }
    }

    func deleteItineraryLiveActivityToken(
        itinerarySubscriptionID: String,
        activityKind: String,
        activityID: String,
        environment: String?,
        accessToken: String
    ) async throws {
        deleteItineraryLiveActivityTokenRequests.append((itinerarySubscriptionID, activityKind, activityID, environment, accessToken))
        if let deleteLiveActivityTokenError {
            throw deleteLiveActivityTokenError
        }
    }

    func registerAPNsAlertToken(
        clientDeviceID: String,
        input: RegisterAPNsAlertTokenRequest,
        accessToken: String
    ) async throws {
        registerAPNsTokenRequests.append((clientDeviceID, accessToken))
        if let registerAPNsTokenError {
            throw registerAPNsTokenError
        }
    }

    func deleteAPNsAlertToken(
        clientDeviceID: String,
        environment: String?,
        accessToken: String
    ) async throws {
        deleteAPNsTokenRequests.append((clientDeviceID, environment, accessToken))
        if let deleteAPNsTokenError {
            throw deleteAPNsTokenError
        }
    }
}

@MainActor
final class FakeStoreKitSubscriptionService: StoreKitSubscriptionServicing {
    var products: [SubscriptionProduct] = []
    var purchaseResult: StoreKitPurchaseOutcome = .cancelled
    var restoreResult: [PendingStoreKitTransaction] = []
    var currentEntitlementsResult: [PendingStoreKitTransaction] = []
    var purchasedProductIDs: [String] = []
    var purchaseAccountTokens: [UUID] = []
    var restoredProductIDs: [[String]] = []
    var finishedTransactionIDs: [UInt64] = []
    var didOpenManageSubscriptions = false

    func loadProducts(_ billingProducts: [BillingProduct]) async throws -> [SubscriptionProduct] {
        if products.isEmpty {
            products = billingProducts.map {
                SubscriptionProduct(productID: $0.productId, displayName: $0.period.humanizedIdentifier, displayPrice: "$1.99", period: $0.period)
            }
        }
        return products
    }

    func purchase(productID: String, appAccountToken: UUID) async throws -> StoreKitPurchaseOutcome {
        purchasedProductIDs.append(productID)
        purchaseAccountTokens.append(appAccountToken)
        return purchaseResult
    }

    func restore(productIDs: [String]) async throws -> [PendingStoreKitTransaction] {
        restoredProductIDs.append(productIDs)
        return restoreResult
    }

    func currentEntitlements(productIDs: [String]) async -> [PendingStoreKitTransaction] {
        currentEntitlementsResult
    }

    func transactionUpdates(productIDs: [String]) -> AsyncStream<PendingStoreKitTransaction> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    func finishTransactions(ids: [UInt64]) async {
        finishedTransactionIDs.append(contentsOf: ids)
    }

    func openManageSubscriptions() async {
        didOpenManageSubscriptions = true
    }
}

final class FakeSessionStore: SessionStoring {
    var session: StoredSession?
    var savedSessions: [StoredSession] = []
    var clearCount = 0
    var loadError: Error?
    var saveError: Error?
    var clearError: Error?

    func load() throws -> StoredSession? {
        if let loadError {
            throw loadError
        }
        return session
    }

    func save(_ session: StoredSession) throws {
        if let saveError {
            throw saveError
        }
        savedSessions.append(session)
        self.session = session
    }

    func clear() throws {
        if let clearError {
            throw clearError
        }
        clearCount += 1
        session = nil
    }
}

struct FakeNotificationAuthorizer: NotificationAuthorizing {
    var status: UNAuthorizationStatus = .denied
    var requestedStatus: UNAuthorizationStatus = .authorized
    var requestError: Error?

    func currentStatus() async -> UNAuthorizationStatus {
        status
    }

    func requestAuthorization() async throws -> UNAuthorizationStatus {
        if let requestError {
            throw requestError
        }
        return requestedStatus
    }
}

@MainActor
final class FakeStationLocationProvider: StationLocationProviding {
    var result: Result<StationSelectionLocation, Error>
    private(set) var requestCount = 0

    init(result: Result<StationSelectionLocation, Error> = .success(StationSelectionLocation(
        latitude: 51.5282,
        longitude: -0.1337,
        horizontalAccuracyMeters: 30,
        capturedAt: Date(timeIntervalSince1970: 0)
    ))) {
        self.result = result
    }

    func currentLocation() async throws -> StationSelectionLocation {
        requestCount += 1
        return try result.get()
    }
}

final class FakeLiveActivityCoordinator: LiveActivityCoordinating {
    struct SyncCall {
        var windowID: String?
        var itineraryID: String?
        var pinnedTrainServiceID: Int?
        var hasTokenRegistration: Bool
    }

    var syncCalls: [SyncCall] = []
    var prepareRemoteStartHasTokenRegistrations: [Bool] = []
    var unregisterRemoteStartHasTokenRegistrations: [Bool] = []
    var endAllHasTokenRegistrations: [Bool] = []
    var endAllCount = 0
    var previewLiveActivityCount = 0
    var previewLiveActivityResult = true
    var pauseEndAll = false
    var onEndAllStarted: (() -> Void)?
    private var endAllContinuation: CheckedContinuation<Void, Never>?

    func prepareForRemoteStart(tokenRegistration: LiveActivityTokenRegistrationContext?) async {
        prepareRemoteStartHasTokenRegistrations.append(tokenRegistration != nil)
    }

    func unregisterRemoteStart(tokenRegistration: LiveActivityTokenRegistrationContext?) async {
        unregisterRemoteStartHasTokenRegistrations.append(tokenRegistration != nil)
    }

    func sync(window: WindowSubscription?, pinnedTrainServiceID: Int?, tokenRegistration: LiveActivityTokenRegistrationContext?) async {
        syncCalls.append(SyncCall(
            windowID: window?.id,
            itineraryID: nil,
            pinnedTrainServiceID: pinnedTrainServiceID,
            hasTokenRegistration: tokenRegistration != nil
        ))
    }

    func sync(itinerary: ItinerarySubscription?, tokenRegistration: LiveActivityTokenRegistrationContext?) async {
        syncCalls.append(SyncCall(
            windowID: nil,
            itineraryID: itinerary?.id,
            pinnedTrainServiceID: nil,
            hasTokenRegistration: tokenRegistration != nil
        ))
    }

    func previewLiveActivity() async -> Bool {
        previewLiveActivityCount += 1
        return previewLiveActivityResult
    }

    func endAll(tokenRegistration: LiveActivityTokenRegistrationContext?) async {
        endAllHasTokenRegistrations.append(tokenRegistration != nil)
        endAllCount += 1
        onEndAllStarted?()
        guard pauseEndAll else { return }
        await withCheckedContinuation { continuation in
            endAllContinuation = continuation
        }
    }

    func resumeEndAll() {
        pauseEndAll = false
        endAllContinuation?.resume()
        endAllContinuation = nil
    }
}

final class FakePushNotificationCoordinator: PushNotificationCoordinating {
    var registerCalls: [(token: String, accessToken: String)] = []
    var unregisterAccessTokens: [String] = []
    var clearLocalStateCount = 0

    func register(token: String, context: PushNotificationRegistrationContext) async {
        registerCalls.append((token, context.accessToken))
    }

    func unregister(context: PushNotificationRegistrationContext) async {
        unregisterAccessTokens.append(context.accessToken)
    }

    func clearLocalState() {
        clearLocalStateCount += 1
    }
}

final class FakeNotificationFeedbackGenerator: NotificationFeedbackGenerating {
    var types: [UINotificationFeedbackGenerator.FeedbackType] = []

    func notificationOccurred(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        types.append(type)
    }
}

final class FakeApplicationStateProvider: ApplicationStateProviding {
    var applicationState: UIApplication.State

    init(applicationState: UIApplication.State = .active) {
        self.applicationState = applicationState
    }
}

@MainActor
final class FakeDeviceIdentityService: DeviceIdentityHandling {
    var isSupported: Bool = true
    var attestResult: Result<DeviceAttestationResult, Error> = .success(
        DeviceAttestationResult(keyId: "fake-key-id", attestationObject: "ZmFrZS1hdHRlc3RhdGlvbg")
    )
    private(set) var attestChallenges: [Data] = []

    func attest(challenge: Data) async throws -> DeviceAttestationResult {
        attestChallenges.append(challenge)
        return try attestResult.get()
    }
}

@MainActor
final class FakeAccountCredentialService: AccountCredentialHandling {
    var isSupported: Bool = true
    var createCredentialResult: Result<AccountCredentialAttestation, Error> = .success(TestFactory.accountCredentialAttestation())
    var assertCredentialResult: Result<AccountCredentialAssertion, Error> = .success(TestFactory.accountCredentialAssertion())
    var recoveryCredentialResult: Result<AccountCredentialAttestation, Error> = .success(TestFactory.accountCredentialAttestation(credentialId: "recovery-credential"))
    private(set) var createCredentialOptions: [AccountCredentialOptions] = []
    private(set) var assertionOptions: [AccountAssertionOptions] = []
    private(set) var recoveryRelyingPartyIDs: [String] = []

    func createCredential(options: AccountCredentialOptions) async throws -> AccountCredentialAttestation {
        createCredentialOptions.append(options)
        return try createCredentialResult.get()
    }

    func assertCredential(options: AccountAssertionOptions) async throws -> AccountCredentialAssertion {
        assertionOptions.append(options)
        return try assertCredentialResult.get()
    }

    func createRecoveryCredential(relyingPartyID: String) async throws -> AccountCredentialAttestation {
        recoveryRelyingPartyIDs.append(relyingPartyID)
        return try recoveryCredentialResult.get()
    }
}

enum TestFactory {
    static let now = DateFormatting.date(from: "2026-01-10T09:00:00.000Z")!

    static func notFoundError(message: String = "not found") -> APIError {
        .server(statusCode: 404, code: nil, message: message, details: [:])
    }

    static func entitlementLimitError() -> APIError {
        .server(
            statusCode: 403,
            code: "entitlement_active_window_limit_exceeded",
            message: "limit reached",
            details: [:]
        )
    }

    static func user(id: String = "user-1", name: String = "Test User") -> User {
        User(
            id: id,
            displayName: name,
            email: "\(id)@example.com",
            emailVerified: true,
            isPrivateEmail: false,
            entitlements: UserEntitlements(tier: "beta", status: "active", activeWindowLimit: 1, commuteRoutineLimit: 2),
            stationDefaults: UserStationDefaults(homeStationCrs: nil, workStationCrs: nil),
            createdAt: now,
            updatedAt: now
        )
    }

    static func storedSession(
        user: User = user(),
        accessToken: String? = "token",
        expiresAt: Date = Date().addingTimeInterval(3600),
        portableAccount: PortableAccountSessionMetadata? = nil
    ) -> StoredSession {
        StoredSession(
            session: Session(
                id: "session-1",
                accessToken: accessToken,
                tokenType: "Bearer",
                expiresAt: expiresAt,
                createdAt: now
            ),
            user: user,
            portableAccount: portableAccount
        )
    }

    static func authResponse(user: User = user(), accessToken: String? = "token") -> AuthResponse {
        AuthResponse(user: user, session: storedSession(user: user, accessToken: accessToken).session)
    }

    static func privacyAccount(
        id: String = "4b4f16d9-6ff7-4755-9b64-890e3c205404",
        state: String = "active"
    ) -> PrivacyAccount {
        PrivacyAccount(id: id, state: state, createdAt: now, updatedAt: now)
    }

    static func accountCredentialOptions() -> AccountRegistrationOptionsResponse {
        AccountRegistrationOptionsResponse(
            attemptId: "8f64b3bd-9c64-4ab7-8b57-f2b6ab8c3f12",
            expiresAt: now.addingTimeInterval(300),
            credentialOptions: AccountCredentialOptions(
                challenge: "base64url-challenge",
                relyingPartyId: "righttrain.app",
                userHandle: "base64url-user-handle",
                displayName: "RightTrain account"
            )
        )
    }

    static func accountAssertionOptions() -> AccountAssertionOptionsResponse {
        AccountAssertionOptionsResponse(
            attemptId: "26864ba9-4052-41e3-9fb9-135baf8766c0",
            expiresAt: now.addingTimeInterval(300),
            assertionOptions: AccountAssertionOptions(
                challenge: "base64url-assertion-challenge",
                relyingPartyId: "righttrain.app",
                allowCredentials: ["base64url-credential-id"]
            )
        )
    }

    static func accountCredentialAttestation(
        credentialId: String = "base64url-credential-id"
    ) -> AccountCredentialAttestation {
        AccountCredentialAttestation(
            credentialId: credentialId,
            clientDataJSON: "base64url-client-data",
            attestationObject: "base64url-attestation-object"
        )
    }

    static func accountCredentialAssertion(
        credentialId: String = "base64url-credential-id"
    ) -> AccountCredentialAssertion {
        AccountCredentialAssertion(
            credentialId: credentialId,
            clientDataJSON: "base64url-client-data",
            authenticatorData: "base64url-authenticator-data",
            signature: "base64url-signature",
            userHandle: "base64url-user-handle"
        )
    }

    static func accountPreferenceRoutine(
        id: String = "afcb09c3-7017-4746-a963-7814d95470f4",
        originCrs: String = "EUS",
        destinationCrs: String = "MAN"
    ) -> AccountPreferenceRoutine {
        AccountPreferenceRoutine(
            id: id,
            name: "Morning commute",
            status: "active",
            originCrs: originCrs,
            destinationCrs: destinationCrs,
            departureTime: "08:10",
            windowMinutes: 120,
            activeWeekdays: [1, 2, 3, 4, 5],
            autoArmEnabled: true,
            autoArmLeadMinutes: 30,
            notificationsEnabled: true,
            updatedAt: now
        )
    }

    static func accountPreferenceSet(
        version: Int = 1,
        homeStationCrs: String? = "EUS",
        workStationCrs: String? = "MAN",
        routines: [AccountPreferenceRoutine]? = nil
    ) -> AccountPreferenceSet {
        AccountPreferenceSet(
            version: version,
            updatedAt: now,
            stationDefaults: UserStationDefaults(homeStationCrs: homeStationCrs, workStationCrs: workStationCrs),
            commuteRoutines: routines ?? [accountPreferenceRoutine()],
            routeSetupDefaults: [:],
            notificationPreferences: AccountNotificationPreferences(routineNotificationsEnabled: true),
            productPreferences: [:]
        )
    }

    static func registerAccountResponse() -> RegisterAccountResponse {
        RegisterAccountResponse(
            account: privacyAccount(),
            preferenceSet: accountPreferenceSet(),
            recoveryCode: "shown-once-to-user"
        )
    }

    static func preferenceConflict() -> PreferenceConflict {
        PreferenceConflict(
            fields: ["stationDefaults.homeStationCrs", "commuteRoutines"],
            allowedResolutions: ["keep_local", "replace_with_account", "merge_non_conflicting"]
        )
    }

    static func linkedDevice(
        id: String = "f73aa4cc-0f64-44bc-a0e2-822ef509d685",
        currentDevice: Bool = true,
        state: String = "active"
    ) -> LinkedDevice {
        LinkedDevice(
            id: id,
            platform: "iOS",
            deviceClass: "iPhone",
            appVersion: "0.1.0",
            buildNumber: "42",
            lastSeenAt: now,
            currentDevice: currentDevice,
            state: state
        )
    }

    static func accountExportResponse() -> AccountExportResponse {
        AccountExportResponse(
            generatedAt: now,
            account: privacyAccount(),
            preferenceSet: accountPreferenceSet(),
            linkedDevices: [
                ExportLinkedDevice(platform: "iOS", deviceClass: "iPhone", lastSeenAt: now, state: "active")
            ],
            retainedRecords: nil
        )
    }

    static func publicJourneyShare(shareID: String = "share-1") -> PublicJourneyShare {
        PublicJourneyShare(
            shareId: shareID,
            kind: "window",
            routeTitle: "Alpha to Beta",
            status: "on_time",
            statusText: "On time",
            originName: "Alpha",
            originCrs: "AAA",
            destinationName: "Beta",
            destinationCrs: "BBB",
            scheduledDeparture: now.addingTimeInterval(15 * 60),
            scheduledArrival: now.addingTimeInterval(55 * 60),
            expectedDeparture: now.addingTimeInterval(15 * 60),
            expectedArrival: now.addingTimeInterval(55 * 60),
            currentPosition: JourneySharePosition(
                description: "Approaching Beta",
                progress: 0.72,
                currentStopName: "Alpha",
                upcomingStopName: "Beta"
            ),
            legs: [],
            disruptions: [],
            refreshedAt: now,
            expiresAt: now.addingTimeInterval(3 * 60 * 60),
            appUrl: "righttrain://journey-shares/\(shareID)",
            appStoreUrl: nil
        )
    }

    static func station(crs: String, name: String, sixteenCharacterName: String? = nil) -> StationSuggestion {
        StationSuggestion(crs: crs, name: name, sixteenCharacterName: sixteenCharacterName, tpl: crs.lowercased(), toc: nil)
    }

    static func score(delayMinutes: Int = 0, usable: Bool = true) -> DirectWindowRecommendationScore {
        DirectWindowRecommendationScore(
            scoreMinutes: 0,
            expectedArrival: "2026-01-10T11:00:00.000Z",
            reliableArrival: "2026-01-10T11:00:00.000Z",
            delayMinutes: delayMinutes,
            penaltyMinutes: 0,
            cancellationPenaltyMinutes: nil,
            severeDelayPenaltyMinutes: nil,
            staleDataPenaltyMinutes: nil,
            lowConfidencePenaltyMinutes: nil,
            usable: usable,
            reasons: nil
        )
    }

    static func realtime(
        expectedTime: String? = nil,
        actualTime: String? = nil,
        expectedArrival: String? = nil,
        expectedDeparture: String? = nil,
        actualArrival: String? = nil,
        actualDeparture: String? = nil,
        delayed: Bool? = nil,
        platform: String? = nil,
        platformConfirmed: Bool? = nil,
        cancelled: Bool? = nil
    ) -> StopRealtime {
        StopRealtime(
            expectedTime: expectedTime,
            actualTime: actualTime,
            expectedArrival: expectedArrival,
            expectedDeparture: expectedDeparture,
            actualArrival: actualArrival,
            actualDeparture: actualDeparture,
            delayed: delayed,
            source: nil,
            sourceInstance: nil,
            estimateMinutes: nil,
            reasonCode: nil,
            reasonText: nil,
            reasonLocationTpl: nil,
            reasonLocationName: nil,
            platform: platform,
            platformConfirmed: platformConfirmed,
            platformSource: nil,
            platformCisSupplement: nil,
            platformSupplement: nil,
            cancelled: cancelled
        )
    }

    static func journey(
        serviceID: Int = 101,
        scheduledDeparture: String = "2026-01-10T10:00:00.000Z",
        scheduledArrival: String = "2026-01-10T11:00:00.000Z",
        scheduledDepartureRaw: String? = "10:00",
        scheduledArrivalRaw: String? = "11:00",
        expectedDeparture: String? = nil,
        expectedArrival: String? = nil,
        operatorName: String? = "Caledonian Sleeper",
        originName: String = "Origin",
        originSixteenCharacterName: String? = nil,
        destinationName: String = "Destination",
        destinationSixteenCharacterName: String? = nil,
        finalDestinationName: String? = nil,
        finalDestinationSixteenCharacterName: String? = nil,
        displayStatus: String = "on_time",
        statusText: String? = nil,
        compactStatusText: String? = nil,
        statusKind: String? = nil,
        movementPhase: String? = nil,
        reportState: String? = nil,
        delayMinutes: Int? = nil,
        cancelled: Bool = false,
        deactivated: Bool = false,
        originRealtime: StopRealtime? = nil,
        destinationRealtime: StopRealtime? = nil,
        originTpl: String = "orig",
        originCrs: String = "AAA",
        destinationTpl: String = "dest",
        destinationCrs: String = "BBB",
        originPlatform: String? = nil,
        destinationPlatform: String? = nil,
        realtimePlatform: String? = nil,
        realtimePlatformConfirmed: Bool = false
    ) -> JourneyResult {
        JourneyResult(
            serviceId: serviceID,
            rid: "rid-\(serviceID)",
            ssd: "2026-01-10",
            uid: nil,
            toc: "CS",
            operatorName: operatorName,
            status: cancelled ? "cancelled" : "scheduled",
            displayStatus: cancelled ? "cancelled" : displayStatus,
            statusText: statusText,
            compactStatusText: compactStatusText,
            statusKind: statusKind,
            movementPhase: movementPhase,
            reportState: reportState,
            delayMinutes: delayMinutes,
            realtimeSource: nil,
            realtimeUpdatedAt: nil,
            lateReasonCode: nil,
            lateReasonText: nil,
            lateReasonLocationTpl: nil,
            lateReasonLocationName: nil,
            cancellationReasonCode: nil,
            cancellationReasonText: nil,
            cancellationReasonLocationTpl: nil,
            cancellationReasonLocationName: nil,
            originTpl: originTpl,
            originCrs: originCrs,
            originName: originName,
            originSixteenCharacterName: originSixteenCharacterName,
            destinationTpl: destinationTpl,
            destinationCrs: destinationCrs,
            destinationName: destinationName,
            destinationSixteenCharacterName: destinationSixteenCharacterName,
            finalDestinationName: finalDestinationName,
            finalDestinationSixteenCharacterName: finalDestinationSixteenCharacterName,
            scheduledDeparture: scheduledDeparture,
            scheduledArrival: scheduledArrival,
            scheduledDepartureRaw: scheduledDepartureRaw,
            scheduledArrivalRaw: scheduledArrivalRaw,
            originPlatform: originPlatform,
            destinationPlatform: destinationPlatform,
            expectedDeparture: expectedDeparture,
            expectedArrival: expectedArrival,
            realtimePlatform: realtimePlatform,
            realtimePlatformConfirmed: realtimePlatformConfirmed,
            cancelled: cancelled,
            deactivated: deactivated,
            originRealtime: originRealtime,
            destinationRealtime: destinationRealtime
        )
    }

    static func journeyDetail(serviceID: Int = 101) -> JourneyDetail {
        JourneyDetail(
            serviceId: serviceID,
            rid: "rid-\(serviceID)",
            ssd: "2026-01-10",
            uid: nil,
            toc: "CS",
            operatorName: "Caledonian Sleeper",
            status: "scheduled",
            displayStatus: "on_time",
            realtimeSource: nil,
            lateReasonCode: nil,
            lateReasonText: nil,
            lateReasonLocationTpl: nil,
            lateReasonLocationName: nil,
            cancellationReasonCode: nil,
            cancellationReasonText: nil,
            cancellationReasonLocationTpl: nil,
            cancellationReasonLocationName: nil,
            originTpl: "orig",
            originCrs: "AAA",
            originName: "Origin",
            destinationTpl: "dest",
            destinationCrs: "BBB",
            destinationName: "Destination",
            cancelled: false,
            deactivated: false,
            coachCount: 8,
            coachCountApproximate: nil,
            stops: [
                JourneyStop(
                    stopIndex: 0,
                    stopType: "origin",
                    tpl: "orig",
                    crs: "AAA",
                    name: "Origin",
                    publicArrival: nil,
                    publicDeparture: "10:00",
                    scheduledPlatform: nil,
                    activities: nil,
                    realtime: nil
                ),
                JourneyStop(
                    stopIndex: 1,
                    stopType: "destination",
                    tpl: "dest",
                    crs: "BBB",
                    name: "Destination",
                    publicArrival: "11:00",
                    publicDeparture: nil,
                    scheduledPlatform: nil,
                    activities: nil,
                    realtime: nil
                )
            ]
        )
    }

    static func recommendation(
        rank: Int = 1,
        serviceID: Int = 101,
        journey: JourneyResult? = nil,
        score: DirectWindowRecommendationScore = score()
    ) -> DirectWindowRecommendation {
        DirectWindowRecommendation(
            rank: rank,
            recommended: rank == 1,
            journey: journey ?? self.journey(serviceID: serviceID),
            score: score
        )
    }

    static func recommendationResponse(_ recommendations: [DirectWindowRecommendation]) -> DirectWindowRecommendationResponse {
        DirectWindowRecommendationResponse(
            topRecommendation: recommendations.first,
            recommendations: recommendations
        )
    }

    static func emptyRecommendationResponse() -> DirectWindowRecommendationResponse {
        DirectWindowRecommendationResponse(topRecommendation: nil, recommendations: [])
    }

    static func itineraryLeg(
        legIndex: Int = 0,
        journey: JourneyResult = journey()
    ) -> ItineraryLeg {
        ItineraryLeg(
            legIndex: legIndex,
            serviceId: journey.serviceId,
            rid: journey.rid,
            ssd: journey.ssd,
            uid: journey.uid,
            toc: journey.toc,
            operatorName: journey.operatorName,
            status: journey.status,
            displayStatus: journey.displayStatus,
            statusText: journey.statusText,
            compactStatusText: journey.compactStatusText,
            statusKind: journey.statusKind,
            movementPhase: journey.movementPhase,
            reportState: journey.reportState,
            delayMinutes: journey.delayMinutes,
            realtimeSource: journey.realtimeSource,
            realtimeUpdatedAt: journey.realtimeUpdatedAt,
            lateReasonCode: journey.lateReasonCode,
            lateReasonText: journey.lateReasonText,
            lateReasonLocationTpl: journey.lateReasonLocationTpl,
            lateReasonLocationName: journey.lateReasonLocationName,
            cancellationReasonCode: journey.cancellationReasonCode,
            cancellationReasonText: journey.cancellationReasonText,
            cancellationReasonLocationTpl: journey.cancellationReasonLocationTpl,
            cancellationReasonLocationName: journey.cancellationReasonLocationName,
            originTpl: journey.originTpl,
            originCrs: journey.originCrs,
            originName: journey.originName,
            originSixteenCharacterName: journey.originSixteenCharacterName,
            destinationTpl: journey.destinationTpl,
            destinationCrs: journey.destinationCrs,
            destinationName: journey.destinationName,
            destinationSixteenCharacterName: journey.destinationSixteenCharacterName,
            finalDestinationTpl: journey.finalDestinationTpl,
            finalDestinationCrs: journey.finalDestinationCrs,
            finalDestinationName: journey.finalDestinationName,
            finalDestinationSixteenCharacterName: journey.finalDestinationSixteenCharacterName,
            scheduledDeparture: journey.scheduledDeparture,
            scheduledArrival: journey.scheduledArrival,
            scheduledDepartureRaw: journey.scheduledDepartureRaw,
            scheduledArrivalRaw: journey.scheduledArrivalRaw,
            originPlatform: journey.originPlatform,
            destinationPlatform: journey.destinationPlatform,
            expectedDeparture: journey.expectedDeparture,
            expectedArrival: journey.expectedArrival,
            expectedDepartureAt: nil,
            expectedArrivalAt: nil,
            realtimePlatform: journey.realtimePlatform,
            realtimePlatformConfirmed: journey.realtimePlatformConfirmed,
            cancelled: journey.cancelled,
            deactivated: journey.deactivated,
            originRealtime: journey.originRealtime,
            destinationRealtime: journey.destinationRealtime
        )
    }

    static func itinerary(
        rank: Int = 1,
        stableKey: String = "itinerary-1",
        legs: [ItineraryLeg]? = nil,
        connections: [ItineraryConnection] = []
    ) -> ItineraryRecommendation {
        let resolvedLegs = legs ?? [itineraryLeg()]
        let first = resolvedLegs.first ?? itineraryLeg()
        let last = resolvedLegs.last ?? first
        return ItineraryRecommendation(
            rank: rank,
            recommended: rank == 1,
            stableKey: stableKey,
            originCrs: first.originCrs,
            destinationCrs: last.destinationCrs,
            scheduledDeparture: first.scheduledDeparture,
            scheduledArrival: last.scheduledArrival,
            expectedDeparture: first.expectedDepartureAt ?? first.scheduledDeparture,
            expectedArrival: last.expectedArrivalAt ?? last.scheduledArrival,
            legs: resolvedLegs,
            connections: connections,
            score: ItineraryScore(
                scoreMinutes: 0,
                expectedArrival: last.expectedArrivalAt ?? last.scheduledArrival,
                reliableArrival: last.expectedArrivalAt ?? last.scheduledArrival,
                delayMinutes: 0,
                penaltyMinutes: 0,
                changeCount: max(0, resolvedLegs.count - 1),
                minimumConnectionMarginMinutes: connections.map(\.expectedMarginMinutes).min() ?? 0,
                transferRiskPenaltyMinutes: nil,
                disruptionPenaltyMinutes: nil,
                usable: true,
                reasons: nil
            ),
            candidateServiceKeys: resolvedLegs.map { ItineraryServiceKey(serviceId: $0.serviceId, rid: $0.rid, ssd: $0.ssd) }
        )
    }

    static func itineraryConnection(
        fromLegIndex: Int = 0,
        toLegIndex: Int = 1,
        atTpl: String = "change",
        atCrs: String = "CCC",
        atName: String = "Change",
        scheduledArrival: String = "2026-01-10T10:40:00.000Z",
        scheduledDeparture: String = "2026-01-10T10:55:00.000Z",
        expectedArrival: String = "2026-01-10T10:40:00.000Z",
        expectedDeparture: String = "2026-01-10T10:55:00.000Z",
        requiredTransferMinutes: Int = 8,
        scheduledMarginMinutes: Int = 7,
        expectedMarginMinutes: Int = 7,
        riskStatus: String = "ok",
        transferSource: String? = nil,
        transferMode: String? = nil,
        transferAdvice: String? = nil,
        transferLinesOfRoute: [String]? = nil
    ) -> ItineraryConnection {
        ItineraryConnection(
            fromLegIndex: fromLegIndex,
            toLegIndex: toLegIndex,
            atTpl: atTpl,
            atCrs: atCrs,
            atName: atName,
            scheduledArrival: scheduledArrival,
            scheduledDeparture: scheduledDeparture,
            expectedArrival: expectedArrival,
            expectedDeparture: expectedDeparture,
            requiredTransferMinutes: requiredTransferMinutes,
            scheduledMarginMinutes: scheduledMarginMinutes,
            expectedMarginMinutes: expectedMarginMinutes,
            risk: ConnectionRisk(status: riskStatus, reasons: nil),
            transferSource: transferSource,
            transferMode: transferMode,
            transferAdvice: transferAdvice,
            transferLinesOfRoute: transferLinesOfRoute
        )
    }

    static func journeyPlanResponse(
        _ itineraries: [ItineraryRecommendation],
        direct: [ItineraryRecommendation]? = nil
    ) -> JourneyPlanResponse {
        JourneyPlanResponse(
            topItinerary: itineraries.first,
            itineraries: itineraries,
            topDirectItinerary: direct?.first,
            directItineraries: direct,
            timetableId: "test-timetable",
            generatedAt: "2026-01-10T09:00:00.000Z"
        )
    }

    /// An itinerary whose score carries a specific reliable arrival, which is
    /// what the direct-only suggestion weighs journeys by.
    static func scoredItinerary(
        stableKey: String,
        reliableArrival: String,
        changeCount: Int,
        usable: Bool = true
    ) -> ItineraryRecommendation {
        let legs = (0...changeCount).map { itineraryLeg(legIndex: $0) }
        var itinerary = itinerary(stableKey: stableKey, legs: legs)
        itinerary.score.reliableArrival = reliableArrival
        itinerary.score.expectedArrival = reliableArrival
        itinerary.score.changeCount = changeCount
        itinerary.score.usable = usable
        return itinerary
    }

    static func emptyJourneyPlanResponse() -> JourneyPlanResponse {
        JourneyPlanResponse(topItinerary: nil, itineraries: [], timetableId: "test-timetable", generatedAt: "2026-01-10T09:00:00.000Z")
    }

    static func commuteRoutine(
        id: String = "routine-1",
        status: String = "active",
        originCrs: String = "AAA",
        destinationCrs: String = "BBB"
    ) -> CommuteRoutine {
        CommuteRoutine(
            id: id,
            userId: "user-1",
            name: "Morning",
            status: status,
            originCrs: originCrs,
            destinationCrs: destinationCrs,
            departureTime: "08:15",
            windowMinutes: 120,
            activeWeekdays: [1, 2, 3, 4, 5],
            autoArmEnabled: true,
            autoArmLeadMinutes: 30,
            notificationsEnabled: true,
            createdAt: now,
            updatedAt: now,
            deletedAt: nil
        )
    }

    static func window(
        id: String = "window-1",
        status: String = "active",
        departureStart: String = "2026-01-10T10:00:00.000Z",
        windowMinutes: Int = 120,
        selectedRecommendation: DirectWindowRecommendation? = nil,
        recommendations: [DirectWindowRecommendation]? = nil,
        selectedTrainServiceId: Int? = nil,
        pinnedTrainServiceId: Int? = nil,
        deletedAt: String? = nil
    ) -> WindowSubscription {
        let selected = selectedRecommendation ?? recommendations?.first ?? recommendation()
        return WindowSubscription(
            id: id,
            userId: "user-1",
            status: status,
            originCrs: "AAA",
            destinationCrs: "BBB",
            departureStart: departureStart,
            windowMinutes: windowMinutes,
            selectedTrainServiceId: selectedTrainServiceId,
            selectedRecommendation: selected,
            recommendations: recommendations ?? [selected],
            pinnedTrainServiceId: pinnedTrainServiceId,
            entitlement: WindowSubscriptionEntitlementState(
                tier: "beta",
                status: "active",
                activeWindowLimit: 1,
                activeWindowCount: 1
            ),
            createdAt: "2026-01-10T09:00:00.000Z",
            deletedAt: deletedAt
        )
    }

    static func itinerarySubscription(
        id: String = "itinerary-subscription-1",
        status: String = "active",
        phase: String = "planning",
        currentLegIndex: Int = 0,
        departureStart: String = "2026-01-10T10:00:00.000Z",
        windowMinutes: Int = 120,
        selectedItinerary: ItineraryRecommendation? = nil,
        itineraries: [ItineraryRecommendation]? = nil,
        deletedAt: String? = nil
    ) -> ItinerarySubscription {
        let selected = selectedItinerary ?? itineraries?.first ?? itinerary()
        return ItinerarySubscription(
            id: id,
            userId: "user-1",
            status: status,
            phase: phase,
            currentLegIndex: currentLegIndex,
            originCrs: "AAA",
            destinationCrs: "BBB",
            departureStart: departureStart,
            windowMinutes: windowMinutes,
            maxChanges: 4,
            limit: 5,
            notificationsEnabled: true,
            selectedItinerary: selected,
            itineraries: itineraries ?? [selected],
            createdAt: "2026-01-10T09:00:00.000Z",
            deletedAt: deletedAt
        )
    }

    static func windowNotificationDetail(
        id: String = "notification-1",
        windowID: String = "window-1",
        eventType: String = "recommended_train_departed",
        departed: DirectWindowRecommendation? = nil,
        next: DirectWindowRecommendation? = nil
    ) -> WindowSubscriptionNotificationDetail {
        WindowSubscriptionNotificationDetail(
            id: id,
            windowSubscriptionId: windowID,
            eventType: eventType,
            deliveryClass: "attention",
            payload: WindowNotificationPayload(
                type: eventType,
                occurredAt: "2026-01-10T10:05:00.000Z",
                data: WindowNotificationData(
                    reasons: [eventType],
                    topRecommendation: next,
                    previousRecommendation: nil,
                    affectedRecommendation: departed,
                    departedRecommendation: departed,
                    nextRecommendation: next,
                    platform: nil,
                    previousPlatform: nil,
                    delayBand: nil,
                    boundary: nil,
                    scheduledDeparture: nil,
                    scheduledDepartureTime: nil,
                    expectedDeparture: nil,
                    expectedDepartureAt: nil,
                    windowStart: nil,
                    windowEnd: nil,
                    departedTrainServiceId: departed?.journey.serviceId,
                    nextRecommendationServiceId: next?.journey.serviceId
                )
            ),
            createdAt: "2026-01-10T10:05:00.000Z"
        )
    }
}
