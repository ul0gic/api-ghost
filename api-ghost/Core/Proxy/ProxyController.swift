import Foundation
import SwiftMITM
import os

private let logger = Logger(subsystem: "corelift.api-ghost", category: "ProxyController")

/// Owns the network-mode MITM proxy lifecycle. Start/stop is driven by `InterceptMode`; the bound
/// ephemeral port is what the browser's `WKWebsiteDataStore.proxyConfigurations` points at.
@MainActor
@Observable
final class ProxyController {
    typealias ServerFactory = @Sendable (CertificateAuthority, CaptureEventSink, Int, EgressPolicy) -> ProxyServing

    private(set) var boundPort: Int?
    private(set) var isRunning = false

    private var server: ProxyServing?
    private let sink = ProxyCaptureSink()
    private let authorityProvider: CertificateAuthorityProviding
    private let makeServer: ServerFactory

    init(
        certificateAuthority: CertificateAuthorityProviding = CertificateAuthorityManager.default,
        makeServer: @escaping ServerFactory = ProxyController.makeProductionServer
    ) {
        self.authorityProvider = certificateAuthority
        self.makeServer = makeServer
    }

    @discardableResult
    func start() async throws -> Int {
        if isRunning, let boundPort { return boundPort }

        let authority = try authorityProvider.currentAuthority()
        let egress = EgressPolicy(allowInternal: Preferences.shared.allowInternalProxyTargets)
        let server = makeServer(authority, sink, Preferences.shared.maxResponseSize, egress)
        let port = try await server.start(host: "127.0.0.1", port: 0)
        self.server = server
        boundPort = port
        isRunning = true
        logger.info("Proxy listening on 127.0.0.1:\(port)")
        return port
    }

    func stop() async {
        defer {
            server = nil
            boundPort = nil
            isRunning = false
            sink.reset()
        }
        guard let server else { return }
        do {
            try await server.stop()
            logger.info("Proxy stopped")
        } catch {
            logger.error("Proxy stop failed: \(error.localizedDescription)")
        }
        await removeTrustAnchorIfInstalled()
    }

    /// Trust is system-wide; revoke it when network mode stops so the always-trusted window matches the proxy run.
    private func removeTrustAnchorIfInstalled() async {
        let provider = authorityProvider
        let installed = await Task.detached { provider.status() == .installedTrusted }.value
        guard installed else { return }
        do {
            try await Task.detached(priority: .userInitiated) { try provider.removeTrust() }.value
            Preferences.shared.isCAInstalled = false
            logger.info("Revoked system trust anchor on network-mode stop")
        } catch {
            logger.error("Failed to revoke trust anchor on stop: \(error.localizedDescription)")
        }
    }

    private static let makeProductionServer: ServerFactory = { authority, sink, bodyLimit, egress in
        ProxyServer(
            certificateAuthority: authority,
            sink: sink,
            egressPolicy: egress,
            captureBodyLimit: bodyLimit
        )
    }
}
