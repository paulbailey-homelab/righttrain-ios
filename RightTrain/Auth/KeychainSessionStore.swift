import Foundation
import Security

protocol SessionStoring {
    func load() throws -> StoredSession?
    func save(_ session: StoredSession) throws
    func clear() throws
}

struct StoredSession: Codable {
    var session: Session
    var user: User
    var portableAccount: PortableAccountSessionMetadata? = nil

    var accessToken: String? {
        session.accessToken
    }
}

struct PortableAccountSessionMetadata: Codable, Equatable {
    var account: PrivacyAccount
    var recovery: PortableAccountRecoveryMetadata?
}

struct PortableAccountRecoveryMetadata: Codable, Equatable {
    var issuedAt: Date
    var acknowledgedAt: Date?
    var replacementCredentialRequired: Bool
}

extension SessionStoring {
    func loadPortableAccountMetadata() throws -> PortableAccountSessionMetadata? {
        try load()?.portableAccount
    }

    func savePortableAccountMetadata(_ metadata: PortableAccountSessionMetadata) throws {
        guard var storedSession = try load() else {
            throw SessionStoreError.noStoredSession
        }
        storedSession.portableAccount = metadata
        try save(storedSession)
    }

    func clearPortableAccountMetadata() throws {
        guard var storedSession = try load(), storedSession.portableAccount != nil else {
            return
        }
        storedSession.portableAccount = nil
        try save(storedSession)
    }
}

struct KeychainSessionStore: SessionStoring {
    private let service = "com.righttrain.ios.session"
    private let account = "current"

    func load() throws -> StoredSession? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainError(status: status)
        }
        guard let data = item as? Data else {
            return nil
        }
        return try JSONCoding.decoder.decode(StoredSession.self, from: data)
    }

    func save(_ session: StoredSession) throws {
        let data = try JSONCoding.encoder.encode(session)
        try clear()

        var query = baseQuery
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError(status: status)
        }
    }

    func clear() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

struct KeychainError: LocalizedError {
    var status: OSStatus

    var errorDescription: String? {
        "Keychain operation failed with status \(status)."
    }
}

enum SessionStoreError: LocalizedError {
    case noStoredSession

    var errorDescription: String? {
        "No stored RightTrain session is available."
    }
}
