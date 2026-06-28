import Foundation
import SwiftMITM
import os

private let logger = Logger(subsystem: "corelift.api-ghost", category: "ProxyController")

/// Owns the network-mode MITM proxy lifecycle. Start/stop is driven by `InterceptMode`; the bound
/// ephemeral port is what the browser's `WKWebsiteDataStore.proxyConfigurations` points at.
@MainActor
@Observable
final class ProxyController {
    private(set) var boundPort: Int?
    private(set) var isRunning = false

    private var server: ProxyServer?
    private let sink = ProxyCaptureSink()

    @discardableResult
    func start() async throws -> Int {
        if isRunning, let boundPort { return boundPort }

        let authority = try CertificateAuthorityManager.default.currentAuthority()
        let server = ProxyServer(
            certificateAuthority: authority,
            sink: sink,
            captureBodyLimit: Preferences.shared.maxResponseSize
        )
        let port = try await server.start(port: 0)
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
        }
        guard let server else { return }
        do {
            try await server.stop()
            logger.info("Proxy stopped")
        } catch {
            logger.error("Proxy stop failed: \(error.localizedDescription)")
        }
    }
}
