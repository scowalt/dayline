import DaylineCore
import Foundation
import Security

struct KeychainVault: Sendable {
    private let accessGroup: String

    init(accessGroup: String = AppGroup.identifier) {
        self.accessGroup = accessGroup
    }

    func read() -> [GoogleCredential] {
        var query = itemQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return [] }
        let decoder = JSONDecoder()
        if let credentials = try? decoder.decode([GoogleCredential].self, from: data) {
            return credentials
        }
        return (try? decoder.decode(GoogleCredential.self, from: data)).map { [$0] } ?? []
    }

    func save(_ credentials: [GoogleCredential]) throws(CalendarServiceError) {
        guard !credentials.isEmpty else { return delete() }
        guard let data = try? JSONEncoder().encode(credentials) else { throw .failed("Dayline could not save your Google sign-in.") }
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        var status = SecItemUpdate(itemQuery as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(itemQuery.merging(attributes) { $1 } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw .failed("Dayline could not save your Google sign-in (Keychain error \(status)).") }
    }

    func delete() {
        SecItemDelete(itemQuery as CFDictionary)
    }

    private var itemQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "\(accessGroup).google",
            kSecAttrAccount as String: "credential",
            kSecAttrAccessGroup as String: accessGroup,
        ]
    }
}
