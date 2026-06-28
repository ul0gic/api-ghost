import Foundation
import Testing

@testable import APIGhost

// MARK: - Proxy lifecycle (5.2.2)

/// Initial state and idempotent stop on the production-default controller. The bound `start → stop`
/// lifecycle is exercised against injected collaborators in `ProxyControllerLifecycleTests` (DBT-009).
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
