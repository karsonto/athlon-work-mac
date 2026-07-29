import Foundation
import Security

nonisolated enum KeychainCredentialStoreError: Error, LocalizedError {
    case unexpectedStatus(OSStatus)
    case invalidUTF8

    var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            return "Keychain error: \(status)"
        case .invalidUTF8:
            return "Credential bytes are not valid UTF-8"
        }
    }
}

/// Keychain-backed secret store (macOS replacement for Windows DPAPI credential store).
nonisolated final class KeychainCredentialStore: @unchecked Sendable {
    static let modelAPIKeyName = ModelSettings.apiKeySecretName

    private let service: String
    private let lock = NSLock()

    init(service: String = "com.athlon.agent.credentials") {
        self.service = service
    }

    func saveSecret(name: String, secret: String) throws {
        lock.lock()
        defer { lock.unlock() }
        guard let data = secret.data(using: .utf8) else {
            throw KeychainCredentialStoreError.invalidUTF8
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: name,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        if status == errSecSuccess {
            let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw KeychainCredentialStoreError.unexpectedStatus(updateStatus)
            }
            return
        }
        if status == errSecItemNotFound {
            var add = query
            attributes.forEach { add[$0.key] = $0.value }
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainCredentialStoreError.unexpectedStatus(addStatus)
            }
            return
        }
        throw KeychainCredentialStoreError.unexpectedStatus(status)
    }

    func loadSecret(name: String) throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: name,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainCredentialStoreError.unexpectedStatus(status)
        }
        guard let data = item as? Data else {
            return nil
        }
        guard let secret = String(data: data, encoding: .utf8) else {
            throw KeychainCredentialStoreError.invalidUTF8
        }
        return secret
    }

    func hasSecret(name: String) throws -> Bool {
        try loadSecret(name: name) != nil
    }

    func deleteSecret(name: String) throws {
        lock.lock()
        defer { lock.unlock() }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: name,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainCredentialStoreError.unexpectedStatus(status)
        }
    }

    // MARK: - Model API key convenience

    func saveModelAPIKey(_ apiKey: String) throws {
        try saveSecret(name: Self.modelAPIKeyName, secret: apiKey)
    }

    func loadModelAPIKey() throws -> String? {
        try loadSecret(name: Self.modelAPIKeyName)
    }

    func deleteModelAPIKey() throws {
        try deleteSecret(name: Self.modelAPIKeyName)
    }
}
