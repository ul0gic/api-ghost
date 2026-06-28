import Foundation
import SwiftMITM
import Testing

@testable import APIGhost

// MARK: - Proxy bound lifecycle (DBT-009)

/// A `ProxyServing` that records calls and returns a fixed port without binding a socket.
private final class RecordingProxyServer: ProxyServing, @unchecked Sendable {
    struct StartCall: Sendable {
        let host: String
        let port: Int
    }

    let portToReturn: Int
    private let lock = NSLock()
    private var recordedStarts: [StartCall] = []
    private var recordedStops = 0

    var startCalls: [StartCall] { lock.withLock { recordedStarts } }
    var stopCalls: Int { lock.withLock { recordedStops } }

    init(portToReturn: Int) {
        self.portToReturn = portToReturn
    }

    func start(host: String, port: Int) async throws -> Int {
        lock.withLock { recordedStarts.append(StartCall(host: host, port: port)) }
        return portToReturn
    }

    func stop() async throws {
        lock.withLock { recordedStops += 1 }
    }
}

@MainActor
struct ProxyControllerLifecycleTests {
    private static func isolatedAuthority() -> (CertificateAuthorityManager, KeychainManager) {
        let service = "corelift.api-ghost.tests.\(UUID().uuidString)"
        let keychain = KeychainManager(service: service)
        return (CertificateAuthorityManager(keychain: keychain, trustDomain: .user), keychain)
    }

    @Test
    func startBindsViaFactoryThenStopTearsDown() async throws {
        let (authority, keychain) = Self.isolatedAuthority()
        defer { try? keychain.deleteCAMaterial() }
        let server = RecordingProxyServer(portToReturn: 49281)
        let controller = ProxyController(certificateAuthority: authority) { _, _, _, _ in server }

        let port = try await controller.start()

        #expect(port == 49281)
        #expect(controller.isRunning)
        #expect(controller.boundPort == 49281)
        #expect(server.startCalls.count == 1)
        #expect(server.startCalls.first?.host == "127.0.0.1")
        #expect(server.startCalls.first?.port == 0)

        await controller.stop()

        #expect(controller.isRunning == false)
        #expect(controller.boundPort == nil)
        #expect(server.stopCalls == 1)
    }

    @Test
    func startIsIdempotentWhileRunning() async throws {
        let (authority, keychain) = Self.isolatedAuthority()
        defer { try? keychain.deleteCAMaterial() }
        let server = RecordingProxyServer(portToReturn: 50112)
        let controller = ProxyController(certificateAuthority: authority) { _, _, _, _ in server }

        let first = try await controller.start()
        let second = try await controller.start()

        #expect(first == second)
        #expect(server.startCalls.count == 1)

        await controller.stop()
    }
}
