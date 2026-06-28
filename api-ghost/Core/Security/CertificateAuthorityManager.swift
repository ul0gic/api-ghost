import Foundation
import Security
import SwiftMITM

/// Single seam for network-mode CA lifecycle: Keychain-backed load/generate plus system trust-anchor management.
/// `nonisolated` so trust mutation can run off the main actor — `.admin`-domain calls block on a system auth prompt.
nonisolated struct CertificateAuthorityManager: Sendable {
    enum TrustStatus: Sendable, Equatable {
        case notGenerated
        case generatedNotTrusted
        case installedTrusted
    }

    enum CAError: Error, LocalizedError {
        case rootCertificateMissing
        case certificateDecodingFailed
        case trustSettingsFailed(OSStatus)

        var errorDescription: String? {
            switch self {
            case .rootCertificateMissing:
                return "No CA root certificate is present in the Keychain."
            case .certificateDecodingFailed:
                return "The stored CA root certificate could not be decoded."
            case .trustSettingsFailed(let status):
                let message = SecCopyErrorMessageString(status, nil) as String?
                return message ?? "Trust settings operation failed with status \(status)."
            }
        }
    }

    static let `default` = CertificateAuthorityManager()

    private let keychain: KeychainManager
    private let trustDomain: SecTrustSettingsDomain

    init(keychain: KeychainManager = .default, trustDomain: SecTrustSettingsDomain = .admin) {
        self.keychain = keychain
        self.trustDomain = trustDomain
    }

    // MARK: - Authority lifecycle

    /// Returns a ready engine authority — loads persisted CA material, generating and persisting it on first use.
    func currentAuthority() throws -> CertificateAuthority {
        if let pem = try keychain.loadCAPrivateKeyPEM() {
            let certificatePEM = try loadRootCertificatePEM()
            return try CertificateAuthority(privateKeyPEM: pem, certificatePEM: certificatePEM)
        }
        return try generate()
    }

    /// Creates a fresh CA and persists it, replacing any existing material. Does not touch system trust.
    @discardableResult
    func generate() throws -> CertificateAuthority {
        let generated = try CertificateAuthority.generate()
        try keychain.storeCAPrivateKeyPEM(generated.privateKeyPEM)
        try persistRootCertificate(pem: generated.certificatePEM)
        return generated.authority
    }

    /// New key + cert, with trust handed off from the old anchor to the new one.
    @discardableResult
    func rotate() throws -> CertificateAuthority {
        let previousCertificate = try? rootSecCertificate()
        let authority = try generate()
        if let previousCertificate {
            try removeTrust(for: previousCertificate)
        }
        try installTrust()
        return authority
    }

    /// Removes the current trust anchor and deletes all CA material from the Keychain.
    func remove() throws {
        if let certificate = try? rootSecCertificate() {
            try removeTrust(for: certificate)
        }
        try keychain.deleteCAMaterial()
    }

    // MARK: - Trust anchor management

    func installTrust() throws {
        let certificate = try rootSecCertificate()
        let status = SecTrustSettingsSetTrustSettings(certificate, trustDomain, nil)
        guard status == errSecSuccess else { throw CAError.trustSettingsFailed(status) }
    }

    func removeTrust() throws {
        try removeTrust(for: try rootSecCertificate())
    }

    func status() -> TrustStatus {
        guard case .some(.some) = try? keychain.loadCAPrivateKeyPEM() else { return .notGenerated }
        guard let certificate = try? rootSecCertificate() else { return .generatedNotTrusted }
        return isTrusted(certificate) ? .installedTrusted : .generatedNotTrusted
    }

    // MARK: - Private

    private func removeTrust(for certificate: SecCertificate) throws {
        let status = SecTrustSettingsRemoveTrustSettings(certificate, trustDomain)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CAError.trustSettingsFailed(status)
        }
    }

    private func isTrusted(_ certificate: SecCertificate) -> Bool {
        var settings: CFArray?
        let status = SecTrustSettingsCopyTrustSettings(certificate, trustDomain, &settings)
        return status == errSecSuccess
    }

    private func persistRootCertificate(pem: String) throws {
        guard let data = pem.data(using: .utf8) else { throw KeychainError.dataEncodingFailed }
        try keychain.storeCARootCertificate(data)
    }

    private func loadRootCertificatePEM() throws -> String? {
        guard let data = try keychain.loadCARootCertificate() else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func rootSecCertificate() throws -> SecCertificate {
        guard let pem = try loadRootCertificatePEM() else { throw CAError.rootCertificateMissing }
        guard let der = Self.derBytes(fromPEM: pem) else { throw CAError.certificateDecodingFailed }
        guard let certificate = SecCertificateCreateWithData(nil, der as CFData) else {
            throw CAError.certificateDecodingFailed
        }
        return certificate
    }

    private static func derBytes(fromPEM pem: String) -> Data? {
        let base64 = pem
            .split(whereSeparator: \.isNewline)
            .filter { !$0.hasPrefix("-----") }
            .joined()
        return Data(base64Encoded: base64)
    }
}
