import Foundation

@MainActor
@Observable
final class AuthViewModel {
    private(set) var user: User?

    @ObservationIgnored var afterSessionAuthenticated: (() async -> Void)?
    @ObservationIgnored var clearExpiredSessionState: (() async -> Void)?
    @ObservationIgnored var prepareSignOut: (() async -> Void)?
    @ObservationIgnored var clearSignedOutState: (() async -> Void)?
    @ObservationIgnored var clearDeletedAccountState: (() async -> Void)?

    @ObservationIgnored private let apiClient: any APIClienting
    @ObservationIgnored private let sessionStore: SessionStoring
    @ObservationIgnored private let operationState: AppOperationState
    @ObservationIgnored private let deviceIdentityService: any DeviceIdentityHandling
    @ObservationIgnored private var storedSession: StoredSession?

    init(
        apiClient: any APIClienting,
        sessionStore: SessionStoring,
        operationState: AppOperationState,
        deviceIdentityService: (any DeviceIdentityHandling)? = nil
    ) {
        self.apiClient = apiClient
        self.sessionStore = sessionStore
        self.operationState = operationState
        self.deviceIdentityService = deviceIdentityService ?? DeviceIdentityService()
    }

    var isSignedIn: Bool {
        user != nil && storedSession?.accessToken != nil
    }

    var accessToken: String? {
        storedSession?.accessToken
    }

    var isDeviceAttestationSupported: Bool {
        deviceIdentityService.isSupported
    }

    func replaceCurrentUser(_ updatedUser: User) {
        user = updatedUser
        guard let storedSession else { return }
        let updatedSession = StoredSession(session: storedSession.session, user: updatedUser)
        try? sessionStore.save(updatedSession)
        self.storedSession = updatedSession
    }

    func bootstrap() async {
        do {
            guard let session = try sessionStore.load(), let accessToken = session.accessToken, !session.session.isExpired else {
                try? sessionStore.clear()
                clearSession()
                await clearExpiredSessionState?()
                BetaDiagnostics.record("bootstrap_no_valid_session")
                return
            }
            storedSession = session
            user = session.user

            do {
                let refreshedUser = try await apiClient.currentUser(accessToken: accessToken)
                let refreshedSession = StoredSession(session: session.session, user: refreshedUser)
                try sessionStore.save(refreshedSession)
                storedSession = refreshedSession
                user = refreshedUser
                await afterSessionAuthenticated?()
                BetaDiagnostics.record("bootstrap_restored_session")
            } catch let apiError as APIError where apiError.requiresSignIn {
                await invalidateCurrentSession(reason: "bootstrap_session_invalid")
            } catch {
                operationState.alertState = .network("You are signed in, but RightTrain could not refresh your account right now.")
                BetaDiagnostics.record("bootstrap_refresh_failed", details: error.localizedDescription)
            }
        } catch {
            operationState.alertState = .network("The saved session could not be loaded. Sign in again to continue.")
            clearSession()
            await clearExpiredSessionState?()
            BetaDiagnostics.record("bootstrap_session_load_failed", details: error.localizedDescription)
        }
    }

    /// Registers this install as an anonymous user via Apple App Attest and
    /// stores the resulting bearer session.
    func registerDevice() async {
        await operationState.withLoading {
            let challengeResponse = try await apiClient.createDeviceChallenge()
            guard let challengeData = Self.decodeBase64URL(challengeResponse.challenge) else {
                throw DeviceIdentityError.challengeUnavailable
            }
            let attestation = try await deviceIdentityService.attest(challenge: challengeData)
            let auth = try await apiClient.registerDevice(
                attemptId: challengeResponse.attemptId,
                keyId: attestation.keyId,
                attestationObject: attestation.attestationObject
            )
            guard auth.session.accessToken != nil else {
                throw AppModelError.missingAccessToken
            }
            let stored = StoredSession(session: auth.session, user: auth.user)
            try sessionStore.save(stored)
            storedSession = stored
            user = auth.user
            operationState.alertState = nil
            await afterSessionAuthenticated?()
            BetaDiagnostics.record("device_registration_succeeded")
        }
    }

    func signOut() async {
        await prepareSignOut?()
        do {
            try sessionStore.clear()
        } catch {
            operationState.alertState = .storage("RightTrain could not remove the saved session from this device. Try signing out again before handing off this device.")
            BetaDiagnostics.record("sign_out_session_clear_failed", details: error.localizedDescription)
        }
        clearSession()
        await clearSignedOutState?()
    }

    @discardableResult
    func deleteAccount() async -> Bool {
        guard let accessToken else {
            operationState.alertState = .auth("Sign in to delete your account.")
            return false
        }

        var didDelete = false
        await operationState.withLoading {
            try await apiClient.deleteCurrentUser(accessToken: accessToken)
            try? sessionStore.clear()
            clearSession()
            await clearDeletedAccountState?()
            didDelete = true
        }
        return didDelete
    }

    private func clearSession() {
        storedSession = nil
        user = nil
    }

    func invalidateCurrentSession(reason: String = "session_invalidated") async {
        try? sessionStore.clear()
        clearSession()
        await clearExpiredSessionState?()
        operationState.alertState = .auth(AppOperationState.expiredSessionMessage)
        BetaDiagnostics.record(reason)
    }

    private static func decodeBase64URL(_ value: String) -> Data? {
        var padded = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let remainder = padded.count % 4
        if remainder > 0 {
            padded.append(String(repeating: "=", count: 4 - remainder))
        }
        return Data(base64Encoded: padded)
    }
}

enum AppModelError: LocalizedError {
    case missingAccessToken

    var errorDescription: String? {
        "RightTrain did not return a bearer session."
    }
}
