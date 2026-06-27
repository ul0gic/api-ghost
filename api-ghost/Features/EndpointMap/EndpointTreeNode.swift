import Foundation
import Combine

final class EndpointTreeNode: Identifiable, ObservableObject {
    // MARK: - Properties

    let id: String

    let name: String

    let nodeType: EndpointNodeType

    let method: String?

    let pathPattern: String?

    let callCount: Int

    let typicalStatus: Int?

    let hasFindings: Bool

    let findings: [EndpointFinding]

    @Published var children: [EndpointTreeNode]

    @Published var isExpanded: Bool

    // MARK: - Computed Properties

    var hasChildren: Bool {
        !children.isEmpty
    }

    var totalCallCount: Int {
        if nodeType == .endpoint {
            return callCount
        }
        return children.reduce(0) { $0 + $1.totalCallCount }
    }

    var findingsCount: Int {
        if nodeType == .endpoint {
            return hasFindings ? 1 : 0
        }
        return children.reduce(0) { $0 + $1.findingsCount }
    }

    // MARK: - Initialization

    init(
        id: String = UUID().uuidString,
        name: String,
        nodeType: EndpointNodeType,
        method: String? = nil,
        pathPattern: String? = nil,
        callCount: Int = 0,
        typicalStatus: Int? = nil,
        hasFindings: Bool = false,
        findings: [EndpointFinding] = [],
        children: [EndpointTreeNode] = [],
        isExpanded: Bool = false
    ) {
        self.id = id
        self.name = name
        self.nodeType = nodeType
        self.method = method
        self.pathPattern = pathPattern
        self.callCount = callCount
        self.typicalStatus = typicalStatus
        self.hasFindings = hasFindings
        self.findings = findings
        self.children = children
        self.isExpanded = isExpanded
    }

    // MARK: - Tree Building

    static func buildTree(from endpoints: [Endpoint]) -> [EndpointTreeNode] {
        let endpointsByDomain = Dictionary(grouping: endpoints) { $0.host }

        var domainNodes: [EndpointTreeNode] = []

        for (domain, domainEndpoints) in endpointsByDomain.sorted(by: { $0.key < $1.key }) {
            let domainNode = EndpointTreeNode(
                id: "domain:\(domain)",
                name: domain,
                nodeType: .domain,
                isExpanded: true
            )

            var pathGroups: [String: [Endpoint]] = [:]
            for endpoint in domainEndpoints {
                let segments = endpoint.pathPattern.split(separator: "/").map(String.init)
                let firstSegment = segments.first ?? ""
                pathGroups[firstSegment, default: []].append(endpoint)
            }

            for (segment, segmentEndpoints) in pathGroups.sorted(by: { $0.key < $1.key }) {
                if segmentEndpoints.count == 1 && !hasSubPaths(segmentEndpoints) {
                    let endpoint = segmentEndpoints[0]
                    let endpointNode = createEndpointNode(from: endpoint)
                    domainNode.children.append(endpointNode)
                } else {
                    let segmentNode = buildPathSegmentNode(
                        segment: segment.isEmpty ? "/" : "/\(segment)",
                        endpoints: segmentEndpoints,
                        domain: domain,
                        depth: 1
                    )
                    domainNode.children.append(segmentNode)
                }
            }

            domainNodes.append(domainNode)
        }

        return domainNodes
    }

    private static func buildPathSegmentNode(
        segment: String,
        endpoints: [Endpoint],
        domain: String,
        depth: Int
    ) -> EndpointTreeNode {
        let segmentNode = EndpointTreeNode(
            id: "path:\(domain)\(segment):\(depth)",
            name: segment,
            nodeType: .pathSegment,
            isExpanded: depth < 2
        )

        var subGroups: [String: [Endpoint]] = [:]

        for endpoint in endpoints {
            let segments = endpoint.pathPattern.split(separator: "/").map(String.init)

            if segments.count > depth {
                let nextSegment = segments[depth]
                subGroups[nextSegment, default: []].append(endpoint)
            } else {
                subGroups["", default: []].append(endpoint)
            }
        }

        for (nextSegment, subEndpoints) in subGroups.sorted(by: { $0.key < $1.key }) {
            if nextSegment.isEmpty {
                for endpoint in subEndpoints {
                    let endpointNode = createEndpointNode(from: endpoint)
                    segmentNode.children.append(endpointNode)
                }
            } else if subEndpoints.count == 1 && !hasMoreSegments(subEndpoints, depth: depth + 1) {
                let endpoint = subEndpoints[0]
                let endpointNode = createEndpointNode(from: endpoint)
                segmentNode.children.append(endpointNode)
            } else {
                let childSegmentNode = buildPathSegmentNode(
                    segment: "/\(nextSegment)",
                    endpoints: subEndpoints,
                    domain: domain,
                    depth: depth + 1
                )
                segmentNode.children.append(childSegmentNode)
            }
        }

        return segmentNode
    }

    private static func createEndpointNode(from endpoint: Endpoint) -> EndpointTreeNode {
        EndpointTreeNode(
            id: endpoint.id,
            name: endpoint.pathPattern,
            nodeType: .endpoint,
            method: endpoint.method,
            pathPattern: endpoint.pathPattern,
            callCount: endpoint.callCount,
            typicalStatus: endpoint.typicalStatus,
            hasFindings: endpoint.hasInterestingFindings,
            findings: endpoint.findings
        )
    }

    private static func hasSubPaths(_ endpoints: [Endpoint]) -> Bool {
        for endpoint in endpoints {
            let segments = endpoint.pathPattern.split(separator: "/")
            if segments.count > 1 {
                return true
            }
        }
        return false
    }

    private static func hasMoreSegments(_ endpoints: [Endpoint], depth: Int) -> Bool {
        for endpoint in endpoints {
            let segments = endpoint.pathPattern.split(separator: "/")
            if segments.count > depth {
                return true
            }
        }
        return false
    }
}

// MARK: - Node Type

enum EndpointNodeType: Equatable {
    case domain
    case pathSegment
    case endpoint
}

// MARK: - Hashable

extension EndpointTreeNode: Hashable {
    static func == (lhs: EndpointTreeNode, rhs: EndpointTreeNode) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
