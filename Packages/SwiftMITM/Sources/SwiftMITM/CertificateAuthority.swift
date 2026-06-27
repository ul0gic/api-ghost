import Crypto
import Foundation
import NIOConcurrencyHelpers
import NIOSSL
import SwiftASN1
import X509

public struct MintedIdentity: Sendable {
    public let certificateChain: [NIOSSLCertificateSource]
    public let privateKey: NIOSSLPrivateKeySource
}

/// In-memory MITM root + per-host P256 leaf minting. CA key lives only in memory for the spike;
/// Phase 4 sources it from Keychain (`SecKey`) instead — the minting path is identical.
public final class CertificateAuthority: Sendable {
    public let caCertificate: Certificate
    public let caCertificatePEM: String

    private let caPrivateKey: Certificate.PrivateKey
    private let leafCache: NIOLockedValueBox<[String: MintedIdentity]>

    public init(commonName: String = "APIGhost MITM Root") throws {
        let caKey = P256.Signing.PrivateKey()
        let privateKey = Certificate.PrivateKey(caKey)
        let name = try DistinguishedName {
            CommonName(commonName)
            OrganizationName("APIGhost")
        }
        let now = Date()
        let certificate = try Certificate(
            version: .v3,
            serialNumber: Certificate.SerialNumber(),
            publicKey: Certificate.PublicKey(caKey.publicKey),
            notValidBefore: now.addingTimeInterval(-3600),
            notValidAfter: now.addingTimeInterval(60 * 60 * 24 * 3650),
            issuer: name,
            subject: name,
            extensions: try Certificate.Extensions {
                Critical(BasicConstraints.isCertificateAuthority(maxPathLength: 0))
                Critical(KeyUsage(keyCertSign: true, cRLSign: true))
            },
            issuerPrivateKey: privateKey
        )
        self.caCertificate = certificate
        self.caPrivateKey = privateKey
        self.caCertificatePEM = try certificate.serializeAsPEM().pemString
        self.leafCache = NIOLockedValueBox([:])
    }

    /// Mints (and caches) a leaf for the SNI host, signed by the root. Cached per host.
    public func leaf(forHost host: String) throws -> MintedIdentity {
        let key = host.lowercased()
        if let cached = leafCache.withLockedValue({ $0[key] }) {
            return cached
        }
        let identity = try mintLeaf(forHost: key)
        leafCache.withLockedValue { $0[key] = identity }
        return identity
    }

    private func mintLeaf(forHost host: String) throws -> MintedIdentity {
        let (leaf, leafPrivate) = try makeLeafCertificate(forHost: host)
        let leafNIO = try Self.nioCertificate(leaf)
        let caNIO = try Self.nioCertificate(caCertificate)
        let keyNIO = try Self.nioPrivateKey(leafPrivate)
        return MintedIdentity(
            certificateChain: [.certificate(leafNIO), .certificate(caNIO)],
            privateKey: .privateKey(keyNIO)
        )
    }

    func makeLeafCertificate(forHost host: String) throws -> (Certificate, Certificate.PrivateKey) {
        let leafKey = P256.Signing.PrivateKey()
        let leafPrivate = Certificate.PrivateKey(leafKey)
        let now = Date()
        let leaf = try Certificate(
            version: .v3,
            serialNumber: Certificate.SerialNumber(),
            publicKey: Certificate.PublicKey(leafKey.publicKey),
            notValidBefore: now.addingTimeInterval(-3600),
            notValidAfter: now.addingTimeInterval(60 * 60 * 24 * 397),
            issuer: caCertificate.subject,
            subject: try DistinguishedName { CommonName(host) },
            extensions: try Certificate.Extensions {
                Critical(BasicConstraints.notCertificateAuthority)
                KeyUsage(digitalSignature: true, keyEncipherment: true)
                try ExtendedKeyUsage([.serverAuth])
                SubjectAlternativeNames([.dnsName(host)])
            },
            issuerPrivateKey: caPrivateKey
        )
        return (leaf, leafPrivate)
    }

    private static func nioCertificate(_ certificate: Certificate) throws -> NIOSSLCertificate {
        let pem = try certificate.serializeAsPEM().pemString
        return try NIOSSLCertificate(bytes: Array(pem.utf8), format: .pem)
    }

    private static func nioPrivateKey(_ key: Certificate.PrivateKey) throws -> NIOSSLPrivateKey {
        let pem = try key.serializeAsPEM().pemString
        return try NIOSSLPrivateKey(bytes: Array(pem.utf8), format: .pem)
    }
}
