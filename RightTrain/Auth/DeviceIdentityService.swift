import CryptoKit
import DeviceCheck
import Foundation

@MainActor
protocol DeviceIdentityHandling {
    /// Indicates whether App Attest is available on this device. False on the
    /// simulator and on devices that do not support DeviceCheck/App Attest.
    var isSupported: Bool { get }

    /// Generates an App Attest key, binds it to the supplied server-issued
    /// challenge, and returns the registration payload the backend expects.
    func attest(challenge: Data) async throws -> DeviceAttestationResult
}

struct DeviceAttestationResult {
    /// Base64-encoded App Attest keyID. Stable per install while the key
    /// remains valid (Secure Enclave-bound).
    var keyId: String
    /// Base64-encoded CBOR attestation object the backend will hand to the
    /// App Attest verifier.
    var attestationObject: String
}

enum DeviceIdentityError: LocalizedError {
    case unsupportedDevice
    case challengeUnavailable

    var errorDescription: String? {
        switch self {
        case .unsupportedDevice:
            return "This device does not support App Attest. RightTrain needs a real iPhone or iPad running iOS 14 or later."
        case .challengeUnavailable:
            return "RightTrain could not obtain an attestation challenge from the server."
        }
    }
}

@MainActor
final class DeviceIdentityService: DeviceIdentityHandling {
    private let attestService: DCAppAttestService
    #if DEBUG && targetEnvironment(simulator)
    private let allowsSimulatorAttestation: Bool
    #endif

    #if DEBUG && targetEnvironment(simulator)
    init(attestService: DCAppAttestService = .shared) {
        self.attestService = attestService
        self.allowsSimulatorAttestation = Self.defaultAllowsSimulatorAttestation()
    }

    init(attestService: DCAppAttestService = .shared, allowsSimulatorAttestation: Bool) {
        self.attestService = attestService
        self.allowsSimulatorAttestation = allowsSimulatorAttestation
    }
    #else
    init(attestService: DCAppAttestService = .shared) {
        self.attestService = attestService
    }
    #endif

    var isSupported: Bool {
        #if DEBUG && targetEnvironment(simulator)
        if allowsSimulatorAttestation {
            return true
        }
        #endif
        return attestService.isSupported
    }

    func attest(challenge: Data) async throws -> DeviceAttestationResult {
        #if DEBUG && targetEnvironment(simulator)
        if allowsSimulatorAttestation {
            return Self.simulatorAttestation(challenge: challenge)
        }
        #endif

        guard attestService.isSupported else {
            throw DeviceIdentityError.unsupportedDevice
        }

        let keyId = try await attestService.generateKey()
        let clientDataHash = Data(SHA256.hash(data: challenge))
        let attestation = try await attestService.attestKey(keyId, clientDataHash: clientDataHash)

        return DeviceAttestationResult(
            keyId: keyId,
            attestationObject: attestation.base64EncodedString()
        )
    }

    #if DEBUG && targetEnvironment(simulator)
    private static let simulatorInstallIDKey = "righttrain.simulatorAppAttestInstallID"
    private static let simulatorKeyIDPrefix = "righttrain-simulator-key-v1:"
    private static let simulatorAttestationPrefix = "righttrain-simulator-attestation-v1:"
    private static let simulatorAttestationHosts: Set<String> = [
        "clearsignal-api.lan.dreamshake.net",
        "localhost",
        "127.0.0.1",
        "::1"
    ]

    private static func defaultAllowsSimulatorAttestation() -> Bool {
        guard let host = AppConfig.apiBaseURL.host(percentEncoded: false)?.lowercased() else {
            return false
        }
        return simulatorAttestationHosts.contains(host)
    }

    private static func simulatorAttestation(challenge: Data) -> DeviceAttestationResult {
        let installID = simulatorInstallID()
        let keyPayload = simulatorKeyIDPrefix + installID
        let attestationPayload = simulatorAttestationPrefix + challenge.base64URLEncodedString()

        return DeviceAttestationResult(
            keyId: Data(keyPayload.utf8).base64EncodedString(),
            attestationObject: Data(attestationPayload.utf8).base64EncodedString()
        )
    }

    private static func simulatorInstallID() -> String {
        if let existing = UserDefaults.standard.string(forKey: simulatorInstallIDKey), !existing.isEmpty {
            return existing
        }
        let generated = UUID().uuidString.lowercased()
        UserDefaults.standard.set(generated, forKey: simulatorInstallIDKey)
        return generated
    }
    #endif
}

#if DEBUG && targetEnvironment(simulator)
private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
#endif
