import Foundation
import Security

protocol CredentialStoring: Sendable {
    func save(_ secret: String, for account: String) throws
    func get(for account: String) -> String?
    func has(for account: String) -> Bool
}

struct CredentialStore: CredentialStoring {
    static let service = "com.athlon.agent"
    static let apiKeyAccount = ModelSettings.apiKeySecretName

    private let serviceName: String

    init(service: String = CredentialStore.service) {
        self.serviceName = service
    }

    func save(_ secret: String, for account: String) throws {
        let data = Data(secret.utf8)
        let query = baseQuery(account: account)

        SecItemDelete(query as CFDictionary)

        var addQuery = query
        addQuery[kSecValueData as String] = data
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw CredentialStoreError.saveFailed(status)
        }
    }

    func get(for account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    func has(for account: String) -> Bool {
        get(for: account) != nil
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]
    }
}

enum CredentialStoreError: LocalizedError {
    case saveFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            "Keychain save failed (status \(status))"
        }
    }
}
