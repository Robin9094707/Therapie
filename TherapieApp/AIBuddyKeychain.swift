import Foundation
import Security

enum AIBuddyKeychain {
    private static var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "eu.rjuhas.therapie.openai", kSecAttrAccount as String: "personal-api-key"] }
    static func read() -> String? {
        var request = query; request[kSecReturnData as String] = true; request[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &value) == errSecSuccess, let data = value as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func save(_ key: String) throws {
        let clean = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !clean.contains(where: \.isWhitespace) else { throw AIBuddyAPIError(message: "Bitte einen vollständigen API-Schlüssel ohne Leerzeichen eingeben.") }
        let attributes: [String: Any] = [kSecValueData as String: Data(clean.utf8), kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound { status = SecItemAdd(query.merging(attributes, uniquingKeysWith: { _, new in new }) as CFDictionary, nil) }
        guard status == errSecSuccess else { throw AIBuddyAPIError(message: "Der Schlüssel konnte nicht sicher im Schlüsselbund gespeichert werden.") }
    }
    static func remove() { SecItemDelete(query as CFDictionary) }
}
