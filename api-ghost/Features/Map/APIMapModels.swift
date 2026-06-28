import Foundation
import SwiftUI
import Combine

// MARK: - API Endpoint

struct APIEndpoint: Identifiable, Hashable, StatusRollupProviding {
    let id: UUID

    let normalizedPath: String

    let method: String

    let statusCodes: Set<Int>

    let statusCounts: [Int: Int]

    let hitCount: Int

    let examplePaths: [String]

    let hasRequestBody: Bool

    let hasResponseBody: Bool

    let contentTypes: Set<String>

    let graphqlOperations: [GraphQLOperation]

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        normalizedPath: String,
        method: String,
        statusCodes: Set<Int> = [],
        statusCounts: [Int: Int] = [:],
        hitCount: Int = 1,
        examplePaths: [String] = [],
        hasRequestBody: Bool = false,
        hasResponseBody: Bool = false,
        contentTypes: Set<String> = [],
        graphqlOperations: [GraphQLOperation] = []
    ) {
        self.id = id
        self.normalizedPath = normalizedPath
        self.method = method
        self.statusCodes = statusCodes
        self.statusCounts = statusCounts
        self.hitCount = hitCount
        self.examplePaths = examplePaths
        self.hasRequestBody = hasRequestBody
        self.hasResponseBody = hasResponseBody
        self.contentTypes = contentTypes
        self.graphqlOperations = graphqlOperations
    }

    // MARK: - Computed Properties

    var isGraphQL: Bool { !graphqlOperations.isEmpty }

    var primaryStatusCode: Int? {
        let successCodes = statusCodes.filter { $0 >= 200 && $0 < 300 }
        if let first = successCodes.min() {
            return first
        }
        return statusCodes.min()
    }

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

enum ParameterType: String, CaseIterable {
    case uuid = "uuid"
    case numericId = "id"
    case hash = "hash"
    case token = "token"
    case unknown = "param"

    var placeholder: String {
        "{\(rawValue)}"
    }

    var color: Color {
        switch self {
        case .uuid: return Color(hex: "#A855F7")
        case .numericId: return Color(hex: "#3B82F6")
        case .hash: return Color(hex: "#F97316")
        case .token: return Color(hex: "#22C55E")
        case .unknown: return Color(hex: "#6B7280")
        }
    }

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

final class PathNode: Identifiable, ObservableObject {
    let id: UUID

    let segment: String

    let isParameter: Bool

    let parameterType: ParameterType?

    @Published var children: [PathNode]

    @Published var endpoints: [APIEndpoint]

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

    var totalEndpoints: Int {
        endpoints.count + children.reduce(0) { $0 + $1.totalEndpoints }
    }

    var totalHitCount: Int {
        endpoints.reduce(0) { $0 + $1.hitCount } + children.reduce(0) { $0 + $1.totalHitCount }
    }

    var hasChildren: Bool {
        !children.isEmpty || !endpoints.isEmpty
    }

    var allMethods: Set<String> {
        var methods = Set(endpoints.map { $0.method })
        for child in children {
            methods.formUnion(child.allMethods)
        }
        return methods
    }
}

// MARK: - API Domain

final class APIDomain: Identifiable, ObservableObject {
    let id: UUID

    let host: String

    @Published var rootNodes: [PathNode]

    let totalRequests: Int

    let uniqueEndpoints: Int

    let methods: Set<String>

    let classification: DomainClassification

    let category: String?

    @Published var isExpanded: Bool

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        host: String,
        rootNodes: [PathNode] = [],
        totalRequests: Int = 0,
        uniqueEndpoints: Int = 0,
        methods: Set<String> = [],
        classification: DomainClassification = .target,
        category: String? = nil,
        isExpanded: Bool = true
    ) {
        self.id = id
        self.host = host
        self.rootNodes = rootNodes
        self.totalRequests = totalRequests
        self.uniqueEndpoints = uniqueEndpoints
        self.methods = methods
        self.classification = classification
        self.category = category
        self.isExpanded = isExpanded
    }

    // MARK: - Computed Properties

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
