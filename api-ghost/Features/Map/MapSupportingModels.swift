import Foundation
import SwiftUI

// MARK: - Status Rollup

protocol StatusRollupProviding {
    var statusCounts: [Int: Int] { get }
}

extension StatusRollupProviding {
    var sortedStatusCounts: [(code: Int, count: Int)] {
        statusCounts.sorted { $0.key < $1.key }.map { (code: $0.key, count: $0.value) }
    }

    var successRate: Double? {
        let total = statusCounts.values.reduce(0, +)
        guard total > 0 else { return nil }
        let success = statusCounts.filter { (200..<300).contains($0.key) }.values.reduce(0, +)
        return Double(success) / Double(total)
    }
}

// MARK: - GraphQL Operation

extension GraphQLOperationType {
    nonisolated init(rawDatabaseValue: String?) {
        self = GraphQLOperationType(rawValue: rawDatabaseValue?.lowercased() ?? "") ?? .unknown
    }

    nonisolated var label: String {
        switch self {
        case .query: return "query"
        case .mutation: return "mutation"
        case .subscription: return "subscr."
        case .unknown: return "op"
        }
    }

    var color: Color {
        switch self {
        case .query: return .ghostAccent
        case .mutation: return .ghostSuccess
        case .subscription: return .ghostWarning
        case .unknown: return .ghostTextMuted
        }
    }
}

struct GraphQLOperation: Identifiable, Hashable, StatusRollupProviding {
    let id: UUID
    let name: String
    let type: GraphQLOperationType
    let hitCount: Int
    let statusCounts: [Int: Int]

    init(
        id: UUID = UUID(),
        name: String,
        type: GraphQLOperationType,
        hitCount: Int,
        statusCounts: [Int: Int] = [:]
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.hitCount = hitCount
        self.statusCounts = statusCounts
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    static func == (lhs: GraphQLOperation, rhs: GraphQLOperation) -> Bool { lhs.id == rhs.id }
}

// MARK: - Domain Classification

enum DomainClassification: Equatable {
    case target
    case thirdParty
}

// MARK: - Endpoint Detail

struct EndpointDetail: Identifiable, Hashable, StatusRollupProviding {
    let id: UUID
    let method: String
    let graphqlType: GraphQLOperationType?
    let title: String
    let host: String
    let summary: String
    let hitCount: Int
    let statusCounts: [Int: Int]
    let examplePaths: [String]
    let contentTypes: [String]

    static func from(endpoint: APIEndpoint, host: String) -> EndpointDetail {
        EndpointDetail(
            id: endpoint.id,
            method: endpoint.method,
            graphqlType: nil,
            title: endpoint.normalizedPath,
            host: host,
            summary: "Parameterized from \(endpoint.hitCount) captures",
            hitCount: endpoint.hitCount,
            statusCounts: endpoint.statusCounts,
            examplePaths: endpoint.examplePaths,
            contentTypes: Array(endpoint.contentTypes).sorted()
        )
    }

    static func from(operation: GraphQLOperation, host: String) -> EndpointDetail {
        EndpointDetail(
            id: operation.id,
            method: operation.type.label,
            graphqlType: operation.type,
            title: operation.name,
            host: host,
            summary: "\(operation.type.label) · \(operation.hitCount) captures",
            hitCount: operation.hitCount,
            statusCounts: operation.statusCounts,
            examplePaths: [],
            contentTypes: []
        )
    }
}
