import AuthenticationServices
import Foundation
import UIKit

@MainActor
protocol AccountCredentialHandling {
    var isSupported: Bool { get }

    func createCredential(options: AccountCredentialOptions) async throws -> AccountCredentialAttestation
    func assertCredential(options: AccountAssertionOptions) async throws -> AccountCredentialAssertion
    func createRecoveryCredential(relyingPartyID: String) async throws -> AccountCredentialAttestation
}

enum AccountCredentialError: LocalizedError {
    case invalidChallenge
    case credentialUnavailable
    case recoveryChallengeUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidChallenge:
            return "RightTrain could not read the account credential challenge."
        case .credentialUnavailable:
            return "RightTrain could not create or read the account credential."
        case .recoveryChallengeUnavailable:
            return "Account recovery needs an updated backend challenge before this device can create a replacement credential."
        }
    }
}

@MainActor
final class AccountCredentialService: AccountCredentialHandling {
    var isSupported: Bool { true }

    func createCredential(options: AccountCredentialOptions) async throws -> AccountCredentialAttestation {
        guard let challenge = Data(base64URLEncoded: options.challenge),
              let userID = Data(base64URLEncoded: options.userHandle) else {
            throw AccountCredentialError.invalidChallenge
        }

        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: options.relyingPartyId)
        let request = provider.createCredentialRegistrationRequest(
            challenge: challenge,
            name: options.displayName,
            userID: userID
        )
        let authorization = try await AccountCredentialAuthorizationPerformer.perform(request)
        guard let registration = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialRegistration else {
            throw AccountCredentialError.credentialUnavailable
        }
        return AccountCredentialAttestation(
            credentialId: registration.credentialID.base64URLEncodedString(),
            clientDataJSON: registration.rawClientDataJSON.base64URLEncodedString(),
            attestationObject: (registration.rawAttestationObject ?? Data()).base64URLEncodedString()
        )
    }

    func assertCredential(options: AccountAssertionOptions) async throws -> AccountCredentialAssertion {
        guard let challenge = Data(base64URLEncoded: options.challenge) else {
            throw AccountCredentialError.invalidChallenge
        }

        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: options.relyingPartyId)
        let request = provider.createCredentialAssertionRequest(challenge: challenge)
        request.allowedCredentials = options.allowCredentials.compactMap { credentialID in
            guard let credentialData = Data(base64URLEncoded: credentialID) else { return nil }
            return ASAuthorizationPlatformPublicKeyCredentialDescriptor(credentialID: credentialData)
        }

        let authorization = try await AccountCredentialAuthorizationPerformer.perform(request)
        guard let assertion = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialAssertion else {
            throw AccountCredentialError.credentialUnavailable
        }
        return AccountCredentialAssertion(
            credentialId: assertion.credentialID.base64URLEncodedString(),
            clientDataJSON: assertion.rawClientDataJSON.base64URLEncodedString(),
            authenticatorData: assertion.rawAuthenticatorData.base64URLEncodedString(),
            signature: assertion.signature.base64URLEncodedString(),
            userHandle: assertion.userID.base64URLEncodedString()
        )
    }

    func createRecoveryCredential(relyingPartyID: String) async throws -> AccountCredentialAttestation {
        throw AccountCredentialError.recoveryChallengeUnavailable
    }
}

@MainActor
private enum AccountCredentialAuthorizationPerformer {
    static func perform(_ request: ASAuthorizationRequest) async throws -> ASAuthorization {
        try await withCheckedThrowingContinuation { continuation in
            let controller = ASAuthorizationController(authorizationRequests: [request])
            let coordinator = AccountCredentialAuthorizationCoordinator(
                continuation: continuation,
                controller: controller
            )
            AccountCredentialAuthorizationRetainer.shared.retain(coordinator)
            controller.delegate = coordinator
            controller.presentationContextProvider = coordinator
            controller.performRequests()
        }
    }
}

@MainActor
private final class AccountCredentialAuthorizationRetainer {
    static let shared = AccountCredentialAuthorizationRetainer()
    private var coordinators: [ObjectIdentifier: AccountCredentialAuthorizationCoordinator] = [:]

    func retain(_ coordinator: AccountCredentialAuthorizationCoordinator) {
        coordinators[ObjectIdentifier(coordinator)] = coordinator
    }

    func release(_ coordinator: AccountCredentialAuthorizationCoordinator) {
        coordinators.removeValue(forKey: ObjectIdentifier(coordinator))
    }
}

@MainActor
private final class AccountCredentialAuthorizationCoordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<ASAuthorization, Error>?
    private let controller: ASAuthorizationController

    init(continuation: CheckedContinuation<ASAuthorization, Error>, controller: ASAuthorizationController) {
        self.continuation = continuation
        self.controller = controller
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let keyWindow = scenes.flatMap(\.windows).first(where: \.isKeyWindow) {
            return keyWindow
        }
        guard let scene = scenes.first else {
            preconditionFailure("Presenting account credentials requires a connected window scene")
        }
        return scene.windows.first ?? ASPresentationAnchor(windowScene: scene)
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        finish { $0.resume(returning: authorization) }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        finish { $0.resume(throwing: error) }
    }

    private func finish(_ resume: (CheckedContinuation<ASAuthorization, Error>) -> Void) {
        guard let continuation else { return }
        self.continuation = nil
        resume(continuation)
        AccountCredentialAuthorizationRetainer.shared.release(self)
        _ = controller
    }
}

private extension Data {
    init?(base64URLEncoded value: String) {
        var padded = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let remainder = padded.count % 4
        if remainder > 0 {
            padded.append(String(repeating: "=", count: 4 - remainder))
        }
        self.init(base64Encoded: padded)
    }

    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
