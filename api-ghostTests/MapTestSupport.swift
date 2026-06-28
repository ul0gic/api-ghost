import Foundation

@testable import APIGhost

@MainActor
enum MapTestSupport {
    static func allEndpoints(_ domain: APIDomain) -> [APIEndpoint] {
        domain.rootNodes.flatMap { collect($0) }
    }

    static func endpoint(
        in domain: APIDomain,
        method: String,
        normalizedPath: String
    ) -> APIEndpoint? {
        allEndpoints(domain).first { $0.method == method && $0.normalizedPath == normalizedPath }
    }

    static func domain(_ domains: [APIDomain], host: String) -> APIDomain? {
        domains.first { $0.host == host }
    }

    private static func collect(_ node: PathNode) -> [APIEndpoint] {
        node.endpoints + node.children.flatMap { collect($0) }
    }
}
