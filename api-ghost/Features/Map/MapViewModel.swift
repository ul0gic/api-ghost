import SwiftUI

// MARK: - Map View Model

@Observable
final class MapViewModel {
    var domains: [APIDomain] = []
    var statistics: APIMapStatistics = .empty
    var isLoading: Bool = false
    var error: Error?

    var targetDomains: [APIDomain] {
        domains.filter { $0.classification == .target }
    }

    var thirdPartyDomains: [APIDomain] {
        domains.filter { $0.classification == .thirdParty }
            .sorted { $0.totalRequests > $1.totalRequests }
    }

    private let builder = APIMapBuilder.shared

    func loadMap() {
        isLoading = true
        error = nil

        Task {
            do {
                async let domainsResult = builder.buildMap()
                async let statsResult = builder.buildStatistics()

                let (newDomains, newStats) = try await (domainsResult, statsResult)

                await MainActor.run {
                    self.domains = newDomains
                    self.statistics = newStats
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.error = error
                    self.isLoading = false
                }
            }
        }
    }

    func expandAll() {
        for domain in domains {
            domain.isExpanded = true
            expandAllNodes(in: domain.rootNodes)
        }
    }

    func collapseAll() {
        for domain in domains {
            domain.isExpanded = false
            collapseAllNodes(in: domain.rootNodes)
        }
    }

    private func expandAllNodes(in nodes: [PathNode]) {
        for node in nodes {
            node.isExpanded = true
            expandAllNodes(in: node.children)
        }
    }

    private func collapseAllNodes(in nodes: [PathNode]) {
        for node in nodes {
            node.isExpanded = false
            collapseAllNodes(in: node.children)
        }
    }
}
