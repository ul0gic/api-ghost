import Foundation
import os

private let logger = Logger(subsystem: "corelift.api-ghost", category: "CertificateLifecycle")

@MainActor
@Observable
final class CertificateLifecycleModel {
    enum Action: Equatable {
        case generate
        case installTrust
        case rotate
        case remove
    }

    private(set) var status: CertificateAuthorityManager.TrustStatus
    private(set) var runningAction: Action?
    var errorMessage: String?

    private let manager: CertificateAuthorityManager

    init(manager: CertificateAuthorityManager? = nil) {
        let manager = manager ?? .default
        self.manager = manager
        self.status = manager.status()
    }

    var isBusy: Bool { runningAction != nil }

    func refresh() {
        status = manager.status()
    }

    func generate() async {
        await run(.generate) { try $0.generate() }
    }

    func installTrust() async {
        await run(.installTrust) { try $0.installTrust() }
    }

    func rotate() async {
        await run(.rotate) { try $0.rotate() }
    }

    func remove() async {
        await run(.remove) { try $0.remove() }
    }

    private func run(
        _ action: Action,
        _ work: @escaping @Sendable (CertificateAuthorityManager) throws -> Void
    ) async {
        guard runningAction == nil else { return }
        runningAction = action
        errorMessage = nil
        let manager = manager
        do {
            try await Task.detached(priority: .userInitiated) {
                try work(manager)
            }.value
        } catch {
            logger.error("CA action \(String(describing: action)) failed: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
        status = manager.status()
        Preferences.shared.isCAInstalled = status == .installedTrusted
        runningAction = nil
    }
}
