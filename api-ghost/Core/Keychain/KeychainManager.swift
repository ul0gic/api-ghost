import Foundation
import Security

/// Sole component that talks to the Keychain — generic secret storage plus network-mode CA material.
struct KeychainManager: Sendable {
    static let `default` = KeychainManager()

    static let serviceIdentifier = "corelift.api-ghost"

    /// Must match the keychain-access-groups entitlement value ($(AppIdentifierPrefix)corelift.api-ghost).
    static let accessGroup = "corelift.api-ghost"

    static let caPrivateKeyPEMKey = "ca.private-key.pem"
    static let caRootCertificateKey = "ca.root-certificate"

    private let service: String
    private let accessGroup: String?

    init(service: String = KeychainManager.serviceIdentifier, accessGroup: String? = nil) {
        self.service = service
        self.accessGroup = accessGroup
    }

    // MARK: - Generic secret storage

    func store(_ data: Data, forKey key: String) throws {
        var query = baseQuery(forKey: key)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let addStatus = SecItemAdd(query as CFDictionary, nil)
        switch addStatus {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            let attributes: [String: Any] = [
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            ]
            let updateStatus = SecItemUpdate(baseQuery(forKey: key) as CFDictionary, attributes as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(updateStatus)
            }
        default:
            throw KeychainError.unexpectedStatus(addStatus)
        }
    }

    func load(forKey key: String) throws -> Data? {
        var query = baseQuery(forKey: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            return result as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func delete(forKey key: String) throws {
        let status = SecItemDelete(baseQuery(forKey: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    // MARK: - CA material

    func storeCAPrivateKeyPEM(_ pem: String) throws {
        guard let data = pem.data(using: .utf8) else { throw KeychainError.dataEncodingFailed }
        try store(data, forKey: Self.caPrivateKeyPEMKey)
    }

    func loadCAPrivateKeyPEM() throws -> String? {
        guard let data = try load(forKey: Self.caPrivateKeyPEMKey) else { return nil }
        guard let pem = String(data: data, encoding: .utf8) else { throw KeychainError.dataEncodingFailed }
        return pem
    }

    func storeCARootCertificate(_ certificate: Data) throws {
        try store(certificate, forKey: Self.caRootCertificateKey)
    }

    func loadCARootCertificate() throws -> Data? {
        try load(forKey: Self.caRootCertificateKey)
    }

    func deleteCAMaterial() throws {
        try delete(forKey: Self.caPrivateKeyPEMKey)
        try delete(forKey: Self.caRootCertificateKey)
    }

    // MARK: - Private

    private func baseQuery(forKey key: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }
}
