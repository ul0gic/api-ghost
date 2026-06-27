import NIOSSL

public enum ALPNProtocol: String, Sendable {
    case http2 = "h2"
    case http11 = "http/1.1"
}

/// Builds the server-side TLS config that terminates the client leg of the MITM, minting a leaf per
/// ClientHello SNI via `sslContextCallback` (the supported NIO primitive — there is no SNIHandler).
/// ALPN advertises h2 + http/1.1 so the inbound leg can branch on the negotiated protocol.
public struct TLSTermination: Sendable {
    public let authority: CertificateAuthority
    public let defaultHost: String

    public init(authority: CertificateAuthority, defaultHost: String = "localhost") {
        self.authority = authority
        self.defaultHost = defaultHost
    }

    public func makeServerConfiguration() throws -> TLSConfiguration {
        let base = try authority.leaf(forHost: defaultHost)
        var configuration = TLSConfiguration.makeServerConfiguration(
            certificateChain: base.certificateChain,
            privateKey: base.privateKey
        )
        configuration.applicationProtocols = [ALPNProtocol.http2.rawValue, ALPNProtocol.http11.rawValue]

        let authority = authority
        let defaultHost = defaultHost
        configuration.sslContextCallback = { values, promise in
            let host = values.serverHostname ?? defaultHost
            do {
                let leaf = try authority.leaf(forHost: host)
                var override = NIOSSLContextConfigurationOverride()
                override.certificateChain = leaf.certificateChain
                override.privateKey = leaf.privateKey
                promise.succeed(override)
            } catch {
                promise.fail(error)
            }
        }
        return configuration
    }

    public func makeServerContext() throws -> NIOSSLContext {
        try NIOSSLContext(configuration: makeServerConfiguration())
    }
}
