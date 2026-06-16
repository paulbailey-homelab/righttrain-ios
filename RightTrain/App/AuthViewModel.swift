import Foundation

@MainActor
@Observable
final class AuthViewModel {
    private(set) var user: User?
    private(set) var portableAccount: PortableAccountSessionMetadata?
    private(set) var accountPreferenceSet: AccountPreferenceSet?
    private(set) var linkedDevices: [LinkedDevice] = []
    private(set) var accountExport: AccountExportResponse?
    private(set) var oneTimeRecoveryCode: String?
    private(set) var accountStatusMessage: String?

    @ObservationIgnored var afterSessionAuthenticated: (() async -> Void)?
    @ObservationIgnored var clearExpiredSessionState: (() async -> Void)?
    @ObservationIgnored var prepareSignOut: (() async -> Void)?
    @ObservationIgnored var clearSignedOutState: (() async -> Void)?
    @ObservationIgnored var clearDeletedAccountState: (() async -> Void)?

    @ObservationIgnored private let apiClient: any APIClienting
    @ObservationIgnored private let sessionStore: SessionStoring
    @ObservationIgnored private let operationState: AppOperationState
    @ObservationIgnored private let deviceIdentityService: any DeviceIdentityHandling
    @ObservationIgnored private let accountCredentialService: any AccountCredentialHandling
    @ObservationIgnored private let accountClientDeviceIDProvider: () -> String
    @ObservationIgnored private var storedSession: StoredSession?

    init(
        apiClient: any APIClienting,
        sessionStore: SessionStoring,
        operationState: AppOperationState,
        deviceIdentityService: (any DeviceIdentityHandling)? = nil,
        accountCredentialService: (any AccountCredentialHandling)? = nil,
        accountClientDeviceIDProvider: @escaping () -> String = { DeviceRegistrationContextFactory.accountClientDeviceID }
    ) {
        self.apiClient = apiClient
        self.sessionStore = sessionStore
        self.operationState = operationState
        self.deviceIdentityService = deviceIdentityService ?? DeviceIdentityService()
        self.accountCredentialService = accountCredentialService ?? AccountCredentialService()
        self.accountClientDeviceIDProvider = accountClientDeviceIDProvider
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

    var isAccountCredentialSupported: Bool {
        accountCredentialService.isSupported
    }

    var hasPortableAccount: Bool {
        portableAccount != nil
    }

    func replaceCurrentUser(_ updatedUser: User) {
        user = updatedUser
        guard let storedSession else { return }
        let updatedSession = StoredSession(
            session: storedSession.session,
            user: updatedUser,
            portableAccount: storedSession.portableAccount
        )
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
            portableAccount = session.portableAccount

            do {
                let refreshedUser = try await apiClient.currentUser(accessToken: accessToken)
                let refreshedSession = StoredSession(
                    session: session.session,
                    user: refreshedUser,
                    portableAccount: session.portableAccount
                )
                try sessionStore.save(refreshedSession)
                storedSession = refreshedSession
                user = refreshedUser
                portableAccount = refreshedSession.portableAccount
                if refreshedSession.portableAccount != nil {
                    await refreshAccountStateSilently(accessToken: accessToken)
                }
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
    func createPortableAccount(migrateCurrentDevicePreferences: Bool = true) async -> Bool {
        guard let accessToken else {
            operationState.alertState = .auth("Continue with this device before creating an account.")
            return false
        }
        guard accountCredentialService.isSupported else {
            operationState.alertState = .auth("This device cannot create an account credential.")
            return false
        }

        var didCreate = false
        await operationState.withLoading {
            let options = try await apiClient.createAccountRegistrationOptions(accessToken: accessToken)
            let credential = try await accountCredentialService.createCredential(options: options.credentialOptions)
            let response = try await apiClient.registerAccount(
                input: RegisterAccountRequest(
                    attemptId: options.attemptId,
                    credentialAttestation: credential,
                    migrateCurrentDevicePreferences: migrateCurrentDevicePreferences,
                    clientDeviceId: accountClientDeviceIDProvider()
                ),
                accessToken: accessToken
            )
            let metadata = PortableAccountSessionMetadata(
                account: response.account,
                lastSyncedPreferenceVersion: response.preferenceSet.version,
                lastSyncedAt: response.preferenceSet.updatedAt,
                recovery: PortableAccountRecoveryMetadata(
                    issuedAt: Date(),
                    acknowledgedAt: nil,
                    replacementCredentialRequired: false
                )
            )
            try savePortableAccountMetadata(metadata)
            accountPreferenceSet = response.preferenceSet
            oneTimeRecoveryCode = response.recoveryCode
            accountStatusMessage = "Account preferences are ready to use on another device."
            await refreshLinkedDevicesSilently(accessToken: accessToken)
            didCreate = true
            BetaDiagnostics.record("portable_account_created")
        }
        return didCreate
    }

    @discardableResult
    func restorePortableAccount() async -> Bool {
        guard accountCredentialService.isSupported else {
            operationState.alertState = .auth("This device cannot use account credentials.")
            return false
        }

        var didRestore = false
        await operationState.withLoading {
            let options = try await apiClient.createAccountAssertionOptions(credentialHint: nil)
            let assertion = try await accountCredentialService.assertCredential(options: options.assertionOptions)
            let auth = try await apiClient.signInWithAccount(
                input: AccountSignInRequest(
                    attemptId: options.attemptId,
                    credentialAssertion: assertion,
                    clientDeviceId: accountClientDeviceIDProvider()
                )
            )
            try await installPortableSession(auth)
            accountStatusMessage = "Account preferences were restored on this device."
            didRestore = true
            BetaDiagnostics.record("portable_account_restored")
        }
        return didRestore
    }

    @discardableResult
    func recoverPortableAccount(recoveryCode: String) async -> Bool {
        let trimmedCode = recoveryCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCode.isEmpty else {
            operationState.alertState = .validation("Enter the recovery code shown when the account was created.")
            return false
        }

        var didRecover = false
        await operationState.withLoading {
            let credential = try await accountCredentialService.createRecoveryCredential(relyingPartyID: "righttrain.app")
            let auth = try await apiClient.recoverAccount(
                input: AccountRecoveryRequest(
                    recoveryCode: trimmedCode,
                    newCredentialAttestation: credential,
                    clientDeviceId: accountClientDeviceIDProvider()
                )
            )
            try await installPortableSession(auth)
            accountStatusMessage = "A replacement account credential was added to this device."
            didRecover = true
            BetaDiagnostics.record("portable_account_recovered")
        }
        return didRecover
    }

    func refreshAccountPreferences() async {
        guard let accessToken else {
            operationState.alertState = .auth("Sign in to refresh account preferences.")
            return
        }
        await operationState.withLoading {
            let preferenceSet = try await apiClient.getAccountPreferenceSet(accessToken: accessToken)
            accountPreferenceSet = preferenceSet
            updatePortablePreferenceMetadata(version: preferenceSet.version, syncedAt: preferenceSet.updatedAt)
            accountStatusMessage = "Account preferences refreshed."
        }
    }

    func refreshLinkedDevices() async {
        guard let accessToken else {
            operationState.alertState = .auth("Sign in to manage linked devices.")
            return
        }
        await operationState.withLoading {
            let response = try await apiClient.listLinkedDevices(accessToken: accessToken)
            linkedDevices = response.devices
        }
    }

    func revokeLinkedDevice(_ device: LinkedDevice) async {
        guard let accessToken else {
            operationState.alertState = .auth("Sign in to revoke linked devices.")
            return
        }
        guard !device.currentDevice else {
            operationState.alertState = .validation("Sign out from this device instead of revoking it here.")
            return
        }
        await operationState.withLoading {
            try await apiClient.revokeLinkedDevice(id: device.id, accessToken: accessToken)
            linkedDevices = linkedDevices.map { current in
                guard current.id == device.id else { return current }
                return LinkedDevice(
                    id: current.id,
                    platform: current.platform,
                    deviceClass: current.deviceClass,
                    appVersion: current.appVersion,
                    buildNumber: current.buildNumber,
                    lastSeenAt: current.lastSeenAt,
                    currentDevice: current.currentDevice,
                    state: "revoked"
                )
            }
            accountStatusMessage = "Linked device revoked."
        }
    }

    func exportPortableAccountData() async {
        guard let accessToken else {
            operationState.alertState = .auth("Sign in to export account data.")
            return
        }
        await operationState.withLoading {
            accountExport = try await apiClient.exportAccountPreferences(accessToken: accessToken)
            accountStatusMessage = "Account export generated."
        }
    }

    func acknowledgeRecoveryCode() {
        oneTimeRecoveryCode = nil
        guard var metadata = portableAccount else { return }
        metadata.recovery = PortableAccountRecoveryMetadata(
            issuedAt: metadata.recovery?.issuedAt ?? Date(),
            acknowledgedAt: Date(),
            replacementCredentialRequired: metadata.recovery?.replacementCredentialRequired ?? false
        )
        do {
            try savePortableAccountMetadata(metadata)
        } catch {
            operationState.alertState = .storage("RightTrain could not update recovery-code status on this device.")
        }
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
        portableAccount = nil
        accountPreferenceSet = nil
        linkedDevices = []
        accountExport = nil
        oneTimeRecoveryCode = nil
        accountStatusMessage = nil
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

    private func installPortableSession(_ auth: AuthResponse) async throws {
        guard let accessToken = auth.session.accessToken else {
            throw AppModelError.missingAccessToken
        }
        var stored = StoredSession(session: auth.session, user: auth.user)
        storedSession = stored
        user = auth.user

        let preferenceSet = try await apiClient.getAccountPreferenceSet(accessToken: accessToken)
        let metadata = PortableAccountSessionMetadata(
            account: PrivacyAccount(
                id: auth.user.id,
                mode: "portable",
                createdAt: auth.user.createdAt,
                updatedAt: auth.user.updatedAt
            ),
            lastSyncedPreferenceVersion: preferenceSet.version,
            lastSyncedAt: preferenceSet.updatedAt,
            recovery: nil
        )
        stored.portableAccount = metadata
        try sessionStore.save(stored)
        storedSession = stored
        portableAccount = metadata
        accountPreferenceSet = preferenceSet
        accountExport = nil
        oneTimeRecoveryCode = nil
        await refreshLinkedDevicesSilently(accessToken: accessToken)
        await afterSessionAuthenticated?()
    }

    private func refreshAccountStateSilently(accessToken: String) async {
        do {
            let preferenceSet = try await apiClient.getAccountPreferenceSet(accessToken: accessToken)
            accountPreferenceSet = preferenceSet
            updatePortablePreferenceMetadata(version: preferenceSet.version, syncedAt: preferenceSet.updatedAt)
            await refreshLinkedDevicesSilently(accessToken: accessToken)
        } catch {
            operationState.recordSilentOperationError(error)
        }
    }

    private func refreshLinkedDevicesSilently(accessToken: String) async {
        do {
            let response = try await apiClient.listLinkedDevices(accessToken: accessToken)
            linkedDevices = response.devices
        } catch {
            operationState.recordSilentOperationError(error)
        }
    }

    private func updatePortablePreferenceMetadata(version: Int, syncedAt: Date) {
        guard var metadata = portableAccount else { return }
        metadata.lastSyncedPreferenceVersion = version
        metadata.lastSyncedAt = syncedAt
        do {
            try savePortableAccountMetadata(metadata)
        } catch {
            operationState.recordSilentOperationError(error)
        }
    }

    private func savePortableAccountMetadata(_ metadata: PortableAccountSessionMetadata) throws {
        guard var storedSession else {
            throw SessionStoreError.noStoredSession
        }
        storedSession.portableAccount = metadata
        try sessionStore.save(storedSession)
        self.storedSession = storedSession
        portableAccount = metadata
    }
}

enum AppModelError: LocalizedError {
    case missingAccessToken

    var errorDescription: String? {
        "RightTrain did not return a bearer session."
    }
}
