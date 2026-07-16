import Foundation
import Security

enum KeychainManager {
    private static let service = "com.christiankaal.overseer"

    static func store(password: String, for connectionID: UUID) throws {
        let data = Data(password.utf8)

        SecItemDelete(query(for: connectionID) as CFDictionary)

        var query = query(for: connectionID)
        query[kSecValueData as String] = data

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.storeFailed(status)
        }
    }

    static func retrievePassword(for connectionID: UUID) -> String? {
        var query = query(for: connectionID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func deletePassword(for connectionID: UUID) {
        SecItemDelete(query(for: connectionID) as CFDictionary)
    }

    private static func query(for connectionID: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: connectionID.uuidString
        ]
    }
}

enum KeychainError: LocalizedError {
    case storeFailed(OSStatus)
    case retrieveFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .storeFailed(let status):
            "Failed to store password in Keychain: \(status)"
        case .retrieveFailed(let status):
            "Failed to retrieve password from Keychain: \(status)"
        }
    }
}
