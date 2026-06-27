//
//  APIMapModels.swift
//  APIGhost
//
//  Data models for the API Map feature.
//  Represents normalized endpoints, path trees, and domains.
//

import Foundation
import SwiftUI
import Combine

// MARK: - API Endpoint

/// Represents a normalized API endpoint discovered from captured traffic.
/// Endpoints are grouped by normalized path pattern and HTTP method.
struct APIEndpoint: Identifiable, Hashable {
    /// Unique identifier for SwiftUI
    let id: UUID

    /// Normalized path with parameter placeholders (e.g., "/projects/{uuid}/auth-token")
    let normalizedPath: String

    /// HTTP method (GET, POST, PUT, DELETE, PATCH, etc.)
    let method: String

    /// All observed HTTP status codes for this endpoint
    let statusCodes: Set<Int>

    /// Total number of times this endpoint was hit
    let hitCount: Int

    /// Example actual paths (up to 3 for display)
    let examplePaths: [String]

    /// Whether any request to this endpoint had a body
    let hasRequestBody: Bool

    /// Whether any response from this endpoint had a body
    let hasResponseBody: Bool

    /// All observed content types
    let contentTypes: Set<String>

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        normalizedPath: String,
        method: String,
        statusCodes: Set<Int> = [],
        hitCount: Int = 1,
        examplePaths: [String] = [],
        hasRequestBody: Bool = false,
        hasResponseBody: Bool = false,
        contentTypes: Set<String> = []
    ) {
        self.id = id
        self.normalizedPath = normalizedPath
        self.method = method
        self.statusCodes = statusCodes
        self.hitCount = hitCount
        self.examplePaths = examplePaths
        self.hasRequestBody = hasRequestBody
        self.hasResponseBody = hasResponseBody
        self.contentTypes = contentTypes
    }

    // MARK: - Computed Properties

    /// Returns the primary status code (most common 2xx, or first observed)
    var primaryStatusCode: Int? {
        // Prefer 2xx codes
        let successCodes = statusCodes.filter { $0 >= 200 && $0 < 300 }
        if let first = successCodes.min() {
            return first
        }
        return statusCodes.min()
    }

    /// Color for the HTTP method badge
    var methodColor: Color {
        switch method.uppercased() {
        case "GET": return .ghostMethodGet
        case "POST": return .ghostMethodPost
        case "PUT": return .ghostMethodPut
        case "PATCH": return .ghostMethodPatch
        case "DELETE": return .ghostMethodDelete
        case "HEAD": return .ghostTextMuted
        case "OPTIONS": return .ghostTextMuted
        default: return .ghostTextSecondary
        }
    }

    // MARK: - Hashable

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: APIEndpoint, rhs: APIEndpoint) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Parameter Type

/// Types of detected dynamic parameters in URL paths.
/// Used for smart normalization and visual differentiation.
enum ParameterType: String, CaseIterable {
    case uuid = "uuid"
    case numericId = "id"
    case hash = "hash"
    case token = "token"
    case unknown = "param"

    /// Placeholder string for display (e.g., "{uuid}")
    var placeholder: String {
        "{\(rawValue)}"
    }

    /// Color for visual display of this parameter type
    var color: Color {
        switch self {
        case .uuid: return Color(hex: "#A855F7")      // Purple
        case .numericId: return Color(hex: "#3B82F6") // Blue
        case .hash: return Color(hex: "#F97316")      // Orange
        case .token: return Color(hex: "#22C55E")     // Green
        case .unknown: return Color(hex: "#6B7280")   // Gray
        }
    }

    /// Description for tooltip/help
    var description: String {
        switch self {
        case .uuid: return "UUID (e.g., 550e8400-e29b-41d4-a716-446655440000)"
        case .numericId: return "Numeric identifier (e.g., 12345)"
        case .hash: return "Hash value (MD5, SHA1, SHA256)"
        case .token: return "Token or encoded string (JWT, Base64)"
        case .unknown: return "Dynamic parameter (pattern unknown)"
        }
    }
}

// MARK: - Path Node

/// Represents a segment in the hierarchical path tree.
/// Nodes can contain child segments and/or terminal endpoints.
final class PathNode: Identifiable, ObservableObject {
    /// Unique identifier for SwiftUI
    let id: UUID

    /// The path segment text (e.g., "projects" or "{uuid}")
    let segment: String

    /// Whether this segment is a detected parameter placeholder
    let isParameter: Bool

    /// The detected parameter type (if isParameter is true)
    let parameterType: ParameterType?

    /// Child path nodes
    @Published var children: [PathNode]

    /// Endpoints that terminate at this path level
    @Published var endpoints: [APIEndpoint]

    /// Whether this node is expanded in the tree view
    @Published var isExpanded: Bool

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        segment: String,
        isParameter: Bool = false,
        parameterType: ParameterType? = nil,
        children: [PathNode] = [],
        endpoints: [APIEndpoint] = [],
        isExpanded: Bool = false
    ) {
        self.id = id
        self.segment = segment
        self.isParameter = isParameter
        self.parameterType = parameterType
        self.children = children
        self.endpoints = endpoints
        self.isExpanded = isExpanded
    }

    // MARK: - Computed Properties

    /// Total number of endpoints in this subtree
    var totalEndpoints: Int {
        endpoints.count + children.reduce(0) { $0 + $1.totalEndpoints }
    }

    /// Total hit count for all endpoints in this subtree
    var totalHitCount: Int {
        endpoints.reduce(0) { $0 + $1.hitCount } + children.reduce(0) { $0 + $1.totalHitCount }
    }

    /// Whether this node has any children (nodes or endpoints)
    var hasChildren: Bool {
        !children.isEmpty || !endpoints.isEmpty
    }

    /// All unique methods used in this subtree
    var allMethods: Set<String> {
        var methods = Set(endpoints.map { $0.method })
        for child in children {
            methods.formUnion(child.allMethods)
        }
        return methods
    }
}

// MARK: - API Domain

/// Represents a domain (host) with its complete endpoint tree.
final class APIDomain: Identifiable, ObservableObject {
    /// Unique identifier for SwiftUI
    let id: UUID

    /// The domain host (e.g., "api.lovable.dev")
    let host: String

    /// Root path nodes for this domain
    @Published var rootNodes: [PathNode]

    /// Total number of captured requests to this domain
    let totalRequests: Int

    /// Number of unique normalized endpoints
    let uniqueEndpoints: Int

    /// All HTTP methods used across this domain
    let methods: Set<String>

    /// Whether this domain is expanded in the tree view
    @Published var isExpanded: Bool

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        host: String,
        rootNodes: [PathNode] = [],
        totalRequests: Int = 0,
        uniqueEndpoints: Int = 0,
        methods: Set<String> = [],
        isExpanded: Bool = true
    ) {
        self.id = id
        self.host = host
        self.rootNodes = rootNodes
        self.totalRequests = totalRequests
        self.uniqueEndpoints = uniqueEndpoints
        self.methods = methods
        self.isExpanded = isExpanded
    }

    // MARK: - Computed Properties

    /// All unique status codes observed across this domain
    var allStatusCodes: Set<Int> {
        var codes = Set<Int>()
        func collectCodes(from node: PathNode) {
            for endpoint in node.endpoints {
                codes.formUnion(endpoint.statusCodes)
            }
            for child in node.children {
                collectCodes(from: child)
            }
        }
        for node in rootNodes {
            collectCodes(from: node)
        }
        return codes
    }
}

// MARK: - API Map Error

/// Errors that can occur during API map building.
enum APIMapError: Error, LocalizedError {
    case databaseNotAvailable
    case queryFailed(String)
    case buildFailed(String)

    var errorDescription: String? {
        switch self {
        case .databaseNotAvailable:
            return "Database is not available"
        case .queryFailed(let reason):
            return "Database query failed: \(reason)"
        case .buildFailed(let reason):
            return "Failed to build API map: \(reason)"
        }
    }
}

// MARK: - API Map Statistics

/// Summary statistics for the API map.
struct APIMapStatistics {
    let domainCount: Int
    let endpointCount: Int
    let totalRequests: Int
    let methodBreakdown: [String: Int]
    let statusCodeBreakdown: [Int: Int]

    static let empty = APIMapStatistics(
        domainCount: 0,
        endpointCount: 0,
        totalRequests: 0,
        methodBreakdown: [:],
        statusCodeBreakdown: [:]
    )
}
