import Foundation
import Security
import SwiftMITM
import Testing

@testable import APIGhost

// MARK: - CA lifecycle (4.2.9)

/// Headless-testable surface only: load-or-generate, regenerate, and the read-only trust status.
/// Trust mutation (`installTrust`/`removeTrust`/`rotate`/`remove` trust side, `.installedTrusted`) needs a
/// signed app + `.admin`-domain auth prompt and cannot run headless — those branches are documented, not exercised.
struct CertificateAuthorityManagerTests {
    /// Each test owns a unique Keychain service so the real CA material is never touched and tests stay parallel-safe.
    private static func makeManager() -> (CertificateAuthorityManager, KeychainManager) {
        let service = "corelift.api-ghost.tests.\(UUID().uuidString)"
        let keychain = KeychainManager(service: service)
        return (CertificateAuthorityManager(keychain: keychain, trustDomain: .user), keychain)
    }

    @Test
    func statusIsNotGeneratedWhenKeychainIsEmpty() throws {
        let (manager, keychain) = Self.makeManager()
        defer { try? keychain.deleteCAMaterial() }
        #expect(manager.status() == .notGenerated)
    }

    @Test
    func generatePersistsKeyAndCertificate() throws {
        let (manager, keychain) = Self.makeManager()
        defer { try? keychain.deleteCAMaterial() }

        _ = try manager.generate()

        #expect(try keychain.loadCAPrivateKeyPEM() != nil)
        let certData = try #require(try keychain.loadCARootCertificate())
        let certPEM = try #require(String(bytes: certData, encoding: .utf8))
        #expect(certPEM.contains("BEGIN CERTIFICATE"))
    }

    @Test
    func statusIsGeneratedNotTrustedAfterGenerate() throws {
        let (manager, keychain) = Self.makeManager()
        defer { try? keychain.deleteCAMaterial() }

        _ = try manager.generate()

        // Read-only status: material exists in the Keychain but no trust anchor is installed.
        #expect(manager.status() == .generatedNotTrusted)
    }

    @Test
    func currentAuthorityGeneratesOnFirstUseThenReloadsSameKey() throws {
        let (manager, keychain) = Self.makeManager()
        defer { try? keychain.deleteCAMaterial() }

        #expect(try keychain.loadCAPrivateKeyPEM() == nil)
        _ = try manager.currentAuthority()
        let firstKey = try #require(try keychain.loadCAPrivateKeyPEM())

        _ = try manager.currentAuthority()
        let reloadedKey = try #require(try keychain.loadCAPrivateKeyPEM())
        #expect(reloadedKey == firstKey, "a second load reuses the persisted key rather than regenerating")
    }

    @Test
    func generateReplacesExistingMaterial() throws {
        let (manager, keychain) = Self.makeManager()
        defer { try? keychain.deleteCAMaterial() }

        _ = try manager.generate()
        let firstKey = try #require(try keychain.loadCAPrivateKeyPEM())
        _ = try manager.generate()
        let secondKey = try #require(try keychain.loadCAPrivateKeyPEM())
        #expect(secondKey != firstKey, "a fresh generate rotates the private key")
    }

    @Test
    func errorDescriptionsAreUserFacing() {
        // Surfaced in the certificates UI — every CAError arm must produce a non-empty message.
        #expect(CertificateAuthorityManager.CAError.rootCertificateMissing.errorDescription?.isEmpty == false)
        #expect(CertificateAuthorityManager.CAError.certificateDecodingFailed.errorDescription?.isEmpty == false)
        #expect(CertificateAuthorityManager.CAError.trustSettingsFailed(errSecParam).errorDescription?.isEmpty == false)
    }

    @Test
    func currentAuthorityProducesUsableAuthority() throws {
        let (manager, keychain) = Self.makeManager()
        defer { try? keychain.deleteCAMaterial() }

        let authority = try manager.currentAuthority()
        // The reloaded authority mints leaves — proves the persisted PEM round-tripped into a working CA.
        let identity = try authority.leaf(forHost: "example.qa.invalid")
        #expect(!identity.certificateChain.isEmpty)
    }
}
