import Foundation
import Security

struct KeychainStore {
    private let service = "local.snipper.OpenRouter"
    private let account = "api-key"

    enum StoreError: LocalizedError {
        case operationFailed(OSStatus)
        case invalidData

        var errorDescription: String? {
            switch self {
            case .operationFailed(let status):
                // Report only the system error, never the secret.
                return (SecCopyErrorMessageString(status, nil) as String?) ?? "Keychain operation failed (\(status))."
            case .invalidData:
                return "The Keychain entry could not be read."
            }
        }
    }

    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    func read() throws -> String? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw StoreError.operationFailed(status) }
        guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            throw StoreError.invalidData
        }
        return value
    }

    func save(_ value: String) throws {
        let attributes = [kSecValueData as String: Data(value.utf8)]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item.merge(attributes) { _, new in new }
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw StoreError.operationFailed(addStatus) }
        } else if status != errSecSuccess {
            throw StoreError.operationFailed(status)
        }
    }

    func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw StoreError.operationFailed(status)
        }
    }
}
