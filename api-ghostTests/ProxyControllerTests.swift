import Foundation
import Testing

@testable import APIGhost

// MARK: - Proxy lifecycle (5.2.2)

/// Only the headless-safe branches: initial state and idempotent stop. `start()` binds a real loopback port and
/// reaches `CertificateAuthorityManager.default` (the production Keychain CA), so the bound lifecycle needs an
/// integration test with a DI seam — tracked in DBT-009, not exercised here.
@MainActor
struct ProxyControllerTests {
    @Test
    func isIdleBeforeStart() {
        let controller = ProxyController()
        #expect(controller.isRunning == false)
        #expect(controller.boundPort == nil)
    }

    @Test
    func stopOnAnIdleControllerIsANoOp() async {
        let controller = ProxyController()
        await controller.stop()
        #expect(controller.isRunning == false)
        #expect(controller.boundPort == nil)
    }
}
