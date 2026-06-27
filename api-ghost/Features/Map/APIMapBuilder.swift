import Foundation
import GRDB

final class APIMapBuilder: Sendable {
    // MARK: - Singleton

    static let shared = APIMapBuilder()

    // MARK: - Dependencies

    private let normalizer = PathNormalizer.shared

    private init() {}

    // MARK: - Build Map

    /// Filtered traffic is never persisted, so no exclusion is applied.
    func buildMap() async throws -> [APIDomain] {
        guard let db = DatabaseManager.shared.database else {
            throw APIMapError.databaseNotAvailable
        }

        let rawEndpoints = try await fetchRawEndpoints(from: db)
        let groupedByHost = Dictionary(grouping: rawEndpoints) { $0.host }

        let domains = groupedByHost.map { host, endpoints in
            buildDomainTree(host: host, endpoints: endpoints)
        }

        return domains.sorted { $0.totalRequests > $1.totalRequests }
    }

    private func fetchRawEndpoints(from db: DatabaseQueue) async throws -> [RawEndpointData] {
        try await db.read { db -> [RawEndpointData] in
            let sql = """
                SELECT host, path, method,
                    GROUP_CONCAT(DISTINCT status_code) as status_codes,
                    COUNT(*) as hit_count,
                    MAX(CASE WHEN request_body_size > 0 THEN 1 ELSE 0 END) as has_request_body,
                    MAX(CASE WHEN response_body_size > 0 THEN 1 ELSE 0 END) as has_response_body,
                    GROUP_CONCAT(DISTINCT content_type) as content_types
                FROM captures
                GROUP BY host, path, method
                ORDER BY host, path, method
            """

            return try Row.fetchAll(db, sql: sql).compactMap { row in
                Self.parseRawEndpoint(from: row)
            }
        }
    }

    nonisolated private static func parseRawEndpoint(from row: Row) -> RawEndpointData? {
        guard let host: String = row["host"],
              let path: String = row["path"],
              let method: String = row["method"] else {
            return nil
        }

        let statusCodesStr: String? = row["status_codes"]
        let statusCodes = statusCodesStr?
            .split(separator: ",")
            .compactMap { Int(String($0).trimmingCharacters(in: .whitespaces)) } ?? []

        let contentTypesStr: String? = row["content_types"]
        let contentTypes = contentTypesStr?
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty } ?? []

        return RawEndpointData(
            host: host,
            path: path,
            method: method.uppercased(),
            statusCodes: statusCodes,
            hitCount: row["hit_count"] ?? 1,
            hasRequestBody: (row["has_request_body"] as Int? ?? 0) > 0,
            hasResponseBody: (row["has_response_body"] as Int? ?? 0) > 0,
            contentTypes: contentTypes
        )
    }

    func buildStatistics() async throws -> APIMapStatistics {
        guard let db = DatabaseManager.shared.database else {
            throw APIMapError.databaseNotAvailable
        }
        return try await db.read { db in
            try Self.fetchStatistics(from: db)
        }
    }

    nonisolated private static func fetchStatistics(from db: Database) throws -> APIMapStatistics {
        let domainCount: Int = try Row.fetchOne(
            db, sql: "SELECT COUNT(DISTINCT host) as count FROM captures"
        )?["count"] ?? 0

        let totalRequests: Int = try Row.fetchOne(
            db, sql: "SELECT COUNT(*) as count FROM captures"
        )?["count"] ?? 0

        let methodBreakdown = try fetchMethodBreakdown(from: db)
        let statusCodeBreakdown = try fetchStatusBreakdown(from: db)

        let endpointCount: Int = try Row.fetchOne(db, sql: """
            SELECT COUNT(*) as count FROM (
                SELECT DISTINCT host, path, method FROM captures
            )
        """)?["count"] ?? 0

        return APIMapStatistics(
            domainCount: domainCount,
            endpointCount: endpointCount,
            totalRequests: totalRequests,
            methodBreakdown: methodBreakdown,
            statusCodeBreakdown: statusCodeBreakdown
        )
    }

    nonisolated private static func fetchMethodBreakdown(from db: Database) throws -> [String: Int] {
        var breakdown: [String: Int] = [:]
        let sql = "SELECT method, COUNT(*) as count FROM captures GROUP BY method"
        for row in try Row.fetchAll(db, sql: sql) {
            if let method: String = row["method"], let count: Int = row["count"] {
                breakdown[method.uppercased()] = count
            }
        }
        return breakdown
    }

    nonisolated private static func fetchStatusBreakdown(from db: Database) throws -> [Int: Int] {
        var breakdown: [Int: Int] = [:]
        let sql = """
            SELECT status_code, COUNT(*) as count FROM captures \
            WHERE status_code IS NOT NULL GROUP BY status_code
            """
        for row in try Row.fetchAll(db, sql: sql) {
            if let statusCode: Int = row["status_code"], let count: Int = row["count"] {
                breakdown[statusCode] = count
            }
        }
        return breakdown
    }

    // MARK: - Build Domain Tree

    private func buildDomainTree(host: String, endpoints: [RawEndpointData]) -> APIDomain {
        var normalizedGroups: [String: [NormalizedEndpointData]] = [:]
        var allMethods: Set<String> = []
        var totalRequests = 0

        for raw in endpoints {
            let (normalizedPath, _) = normalizer.normalizePath(raw.path)
            let key = "\(raw.method):\(normalizedPath)"

            let normalized = NormalizedEndpointData(
                normalizedPath: normalizedPath,
                originalPath: raw.path,
                method: raw.method,
                statusCodes: raw.statusCodes,
                hitCount: raw.hitCount,
                hasRequestBody: raw.hasRequestBody,
                hasResponseBody: raw.hasResponseBody,
                contentTypes: raw.contentTypes
            )

            normalizedGroups[key, default: []].append(normalized)
            allMethods.insert(raw.method)
            totalRequests += raw.hitCount
        }

        var mergedEndpoints: [APIEndpoint] = []
        for (_, group) in normalizedGroups {
            let merged = mergeEndpoints(group)
            mergedEndpoints.append(merged)
        }

        let rootNodes = buildPathTree(from: mergedEndpoints)

        return APIDomain(
            host: host,
            rootNodes: rootNodes,
            totalRequests: totalRequests,
            uniqueEndpoints: mergedEndpoints.count,
            methods: allMethods,
            isExpanded: true
        )
    }

    // MARK: - Build Path Tree

    private func buildPathTree(from endpoints: [APIEndpoint]) -> [PathNode] {
        var rootDict: [String: PathNodeBuilder] = [:]

        for endpoint in endpoints {
            let segments = endpoint.normalizedPath
                .split(separator: "/", omittingEmptySubsequences: true)
                .map(String.init)

            guard !segments.isEmpty else { continue }

            insertIntoTree(&rootDict, segments: segments, endpoint: endpoint, index: 0)
        }

        return rootDict.values
            .map { $0.build() }
            .sorted { $0.segment.lowercased() < $1.segment.lowercased() }
    }

    private func insertIntoTree(
        _ nodes: inout [String: PathNodeBuilder],
        segments: [String],
        endpoint: APIEndpoint,
        index: Int
    ) {
        guard index < segments.count else { return }

        let segment = segments[index]
        let isParameter = segment.hasPrefix("{") && segment.hasSuffix("}")
        let paramType = isParameter ? parseParameterType(segment) : nil

        if nodes[segment] == nil {
            nodes[segment] = PathNodeBuilder(
                segment: segment,
                isParameter: isParameter,
                parameterType: paramType
            )
        }

        if index == segments.count - 1 {
            nodes[segment]?.endpoints.append(endpoint)
        } else {
            if let node = nodes[segment] {
                insertIntoTree(&node.children, segments: segments, endpoint: endpoint, index: index + 1)
                nodes[segment] = node
            }
        }
    }

    private func parseParameterType(_ placeholder: String) -> ParameterType {
        let inner = String(placeholder.dropFirst().dropLast())
        return ParameterType(rawValue: inner) ?? .unknown
    }

    // MARK: - Merge Endpoints

    private func mergeEndpoints(_ endpoints: [NormalizedEndpointData]) -> APIEndpoint {
        guard let first = endpoints.first else {
            fatalError("Cannot merge empty endpoint list")
        }

        guard endpoints.count > 1 else {
            return APIEndpoint(
                normalizedPath: first.normalizedPath,
                method: first.method,
                statusCodes: Set(first.statusCodes),
                hitCount: first.hitCount,
                examplePaths: [first.originalPath],
                hasRequestBody: first.hasRequestBody,
                hasResponseBody: first.hasResponseBody,
                contentTypes: Set(first.contentTypes)
            )
        }

        var allStatusCodes = Set<Int>()
        var totalHits = 0
        var allExamples: [String] = []
        var hasReqBody = false
        var hasRespBody = false
        var allContentTypes = Set<String>()

        for ep in endpoints {
            allStatusCodes.formUnion(ep.statusCodes)
            totalHits += ep.hitCount
            allExamples.append(ep.originalPath)
            hasReqBody = hasReqBody || ep.hasRequestBody
            hasRespBody = hasRespBody || ep.hasResponseBody
            allContentTypes.formUnion(ep.contentTypes)
        }

        let uniqueExamples = Array(Set(allExamples)).prefix(3)

        return APIEndpoint(
            normalizedPath: first.normalizedPath,
            method: first.method,
            statusCodes: allStatusCodes,
            hitCount: totalHits,
            examplePaths: Array(uniqueExamples),
            hasRequestBody: hasReqBody,
            hasResponseBody: hasRespBody,
            contentTypes: allContentTypes
        )
    }
}

// MARK: - Supporting Types

private struct RawEndpointData {
    let host: String
    let path: String
    let method: String
    let statusCodes: [Int]
    let hitCount: Int
    let hasRequestBody: Bool
    let hasResponseBody: Bool
    let contentTypes: [String]
}

private struct NormalizedEndpointData {
    let normalizedPath: String
    let originalPath: String
    let method: String
    let statusCodes: [Int]
    let hitCount: Int
    let hasRequestBody: Bool
    let hasResponseBody: Bool
    let contentTypes: [String]
}

private class PathNodeBuilder {
    let segment: String
    let isParameter: Bool
    let parameterType: ParameterType?
    var children: [String: PathNodeBuilder] = [:]
    var endpoints: [APIEndpoint] = []

    init(segment: String, isParameter: Bool, parameterType: ParameterType?) {
        self.segment = segment
        self.isParameter = isParameter
        self.parameterType = parameterType
    }

    func build() -> PathNode {
        let childNodes = children.values
            .map { $0.build() }
            .sorted { $0.segment.lowercased() < $1.segment.lowercased() }

        let sortedEndpoints = endpoints.sorted { $0.method < $1.method }

        return PathNode(
            segment: segment,
            isParameter: isParameter,
            parameterType: parameterType,
            children: childNodes,
            endpoints: sortedEndpoints,
            isExpanded: false
        )
    }
}
