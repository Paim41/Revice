import Foundation
import Security

@MainActor protocol CredentialStoring {
    func load() throws -> AgentIdentity?
    func save(_ identity: AgentIdentity) throws
    func clear() throws
}
@MainActor struct KeychainCredentials: CredentialStoring {
    private let service = "app.revice.ios-agent.enrollment"
    private var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service, kSecAttrAccount as String: "agent"] }
    func load() throws -> AgentIdentity? {
        var q = query; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw AgentError.message("Unlock this iPhone to access its pairing credential.") }
        return try JSONDecoder().decode(AgentIdentity.self, from: data)
    }
    func save(_ identity: AgentIdentity) throws {
        let data = try JSONEncoder().encode(identity)
        let attributes: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(attributes) { _, value in value } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw AgentError.message("Could not securely save pairing. Please unlock and retry.") }
    }
    func clear() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw AgentError.message("Could not remove the credential.") }
    }
}
