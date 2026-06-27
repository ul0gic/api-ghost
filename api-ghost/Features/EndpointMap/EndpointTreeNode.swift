//
//  EndpointTreeNode.swift
//  api-ghost
//
//  Tree node structure for the Endpoint Map hierarchical display.
//  Represents domains, path segments, and methods in a tree format.
//

import Foundation
import Combine

/// Represents a node in the endpoint tree hierarchy.
/// The tree structure is: Domain > Path Segments > Method
final class EndpointTreeNode: Identifiable, ObservableObject {
    // MARK: - Properties

    /// Unique identifier for the node
    let id: String

    /// Display name for this node
    let name: String

    /// Type of node (domain, path segment, or endpoint)
    let nodeType: EndpointNodeType

    /// HTTP method (only set for endpoint nodes)
    let method: String?

    /// Full path pattern (only set for endpoint nodes)
    let pathPattern: String?

    /// Number of requests for this endpoint (only set for endpoint nodes)
    let callCount: Int

    /// Typical HTTP status code (only set for endpoint nodes)
    let typicalStatus: Int?

    /// Whether this endpoint has interesting findings
    let hasFindings: Bool

    /// Findings for this endpoint (only set for endpoint nodes)
    let findings: [EndpointFinding]

    /// Child nodes
    @Published var children: [EndpointTreeNode]

    /// Whether this node is expanded in the tree view
    @Published var isExpanded: Bool

    // MARK: - Computed Properties

    /// Whether this node has children
    var hasChildren: Bool {
        !children.isEmpty
    }

    /// Total call count for this node and all children
    var totalCallCount: Int {
        if nodeType == .endpoint {
            return callCount
        }
        return children.reduce(0) { $0 + $1.totalCallCount }
    }

    /// Count of endpoints with findings in this subtree
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

    /// Builds a tree structure from a list of endpoints.
    /// - Parameter endpoints: Array of endpoints to build tree from
    /// - Returns: Array of root nodes (one per domain)
    static func buildTree(from endpoints: [Endpoint]) -> [EndpointTreeNode] {
        // Group endpoints by domain
        let endpointsByDomain = Dictionary(grouping: endpoints) { $0.host }

        // Create domain nodes
        var domainNodes: [EndpointTreeNode] = []

        for (domain, domainEndpoints) in endpointsByDomain.sorted(by: { $0.key < $1.key }) {
            let domainNode = EndpointTreeNode(
                id: "domain:\(domain)",
                name: domain,
                nodeType: .domain,
                isExpanded: true
            )

            // Group endpoints by path prefix (first segment)
            var pathGroups: [String: [Endpoint]] = [:]
            for endpoint in domainEndpoints {
                let segments = endpoint.pathPattern.split(separator: "/").map(String.init)
                let firstSegment = segments.first ?? ""
                pathGroups[firstSegment, default: []].append(endpoint)
            }

            // Build path segment children
            for (segment, segmentEndpoints) in pathGroups.sorted(by: { $0.key < $1.key }) {
                if segmentEndpoints.count == 1 && !hasSubPaths(segmentEndpoints) {
                    // Single endpoint at this level - create endpoint node directly
                    let endpoint = segmentEndpoints[0]
                    let endpointNode = createEndpointNode(from: endpoint)
                    domainNode.children.append(endpointNode)
                } else {
                    // Multiple endpoints or sub-paths - create path segment node
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

    /// Builds a path segment node with its children.
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

        // Group remaining endpoints by next segment
        var subGroups: [String: [Endpoint]] = [:]

        for endpoint in endpoints {
            let segments = endpoint.pathPattern.split(separator: "/").map(String.init)

            if segments.count > depth {
                let nextSegment = segments[depth]
                subGroups[nextSegment, default: []].append(endpoint)
            } else {
                // This endpoint terminates at this level
                subGroups["", default: []].append(endpoint)
            }
        }

        for (nextSegment, subEndpoints) in subGroups.sorted(by: { $0.key < $1.key }) {
            if nextSegment.isEmpty {
                // Endpoints that terminate at this level
                for endpoint in subEndpoints {
                    let endpointNode = createEndpointNode(from: endpoint)
                    segmentNode.children.append(endpointNode)
                }
            } else if subEndpoints.count == 1 && !hasMoreSegments(subEndpoints, depth: depth + 1) {
                // Single endpoint with no more sub-paths
                let endpoint = subEndpoints[0]
                let endpointNode = createEndpointNode(from: endpoint)
                segmentNode.children.append(endpointNode)
            } else {
                // Recurse for sub-paths
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

    /// Creates an endpoint leaf node from an Endpoint model.
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

    /// Checks if any endpoint in the list has sub-paths beyond depth.
    private static func hasSubPaths(_ endpoints: [Endpoint]) -> Bool {
        for endpoint in endpoints {
            let segments = endpoint.pathPattern.split(separator: "/")
            if segments.count > 1 {
                return true
            }
        }
        return false
    }

    /// Checks if any endpoint has more path segments beyond the given depth.
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

/// Types of nodes in the endpoint tree.
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
