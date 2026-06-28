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
        let rows = try await fetchRawRows(from: db)
        return Self.buildDomains(from: rows)
    }

    /// Pure transform — DB-free seam for unit tests: normalize → merge → tree → graphql-group → classify.
    static func buildDomains(from rows: [RawRow]) -> [APIDomain] {
        let targetRegistrable = pickTargetRegistrableDomain(from: rows)
        let groupedByHost = Dictionary(grouping: rows) { $0.host }

        let domains = groupedByHost.map { host, hostRows -> APIDomain in
            let isTarget = PathNormalizer.registrableDomain(host) == targetRegistrable
            return buildDomain(
                host: host,
                rows: hostRows,
                classification: isTarget ? .target : .thirdParty
            )
        }

        return domains.sorted { lhs, rhs in
            if lhs.classification != rhs.classification {
                return lhs.classification == .target
            }
            return lhs.totalRequests > rhs.totalRequests
        }
    }

    /// TARGET = registrable-domain group with most requests; ties → more unique endpoints, then lexicographic.
    /// Upgradeable to a real browser-navigation signal once tabs (3.2) land.
    private static func pickTargetRegistrableDomain(from rows: [RawRow]) -> String? {
        let groups = Dictionary(grouping: rows) { PathNormalizer.registrableDomain($0.host) }
        let ranked = groups.map { key, groupRows in
            DomainRank(
                key: key,
                requests: groupRows.reduce(0) { $0 + $1.hitCount },
                endpoints: Set(groupRows.map { "\($0.method):\($0.path)" }).count
            )
        }
        return ranked.min { lhs, rhs in
            if lhs.requests != rhs.requests { return lhs.requests > rhs.requests }
            if lhs.endpoints != rhs.endpoints { return lhs.endpoints > rhs.endpoints }
            return lhs.key < rhs.key
        }?.key
    }

    private func fetchRawRows(from db: DatabaseQueue) async throws -> [RawRow] {
        try await db.read { db -> [RawRow] in
            let sql = """
                SELECT host, path, method, status_code,
                    graphql_operation_name, graphql_operation_type,
                    COUNT(*) as hit_count,
                    MAX(CASE WHEN request_body_size > 0 THEN 1 ELSE 0 END) as has_request_body,
                    MAX(CASE WHEN response_body_size > 0 THEN 1 ELSE 0 END) as has_response_body,
                    GROUP_CONCAT(DISTINCT content_type) as content_types
                FROM captures
                GROUP BY host, path, method, status_code,
                    graphql_operation_name, graphql_operation_type
                ORDER BY host, path, method
            """

            return try Row.fetchAll(db, sql: sql).compactMap { row in
                Self.parseRawRow(from: row)
            }
        }
    }

    nonisolated private static func parseRawRow(from row: Row) -> RawRow? {
        guard let host: String = row["host"],
              let path: String = row["path"],
              let method: String = row["method"] else {
            return nil
        }

        let contentTypesStr: String? = row["content_types"]
        let contentTypes = contentTypesStr?
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty } ?? []

        return RawRow(
            host: host,
            path: path,
            method: method.uppercased(),
            statusCode: row["status_code"],
            graphqlName: row["graphql_operation_name"],
            graphqlType: row["graphql_operation_type"],
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

    private static func buildDomain(
        host: String,
        rows: [RawRow],
        classification: DomainClassification
    ) -> APIDomain {
        let normalizer = PathNormalizer.shared
        var normalizedGroups: [String: [RawRow]] = [:]
        var allMethods: Set<String> = []
        var totalRequests = 0

        for raw in rows {
            let (normalizedPath, _) = normalizer.normalizePath(raw.path)
            let key = "\(raw.method):\(normalizedPath)"
            normalizedGroups[key, default: []].append(raw)
            allMethods.insert(raw.method)
            totalRequests += raw.hitCount
        }

        let mergedEndpoints = normalizedGroups.values.compactMap { group in
            mergeEndpoint(rows: group, normalizer: normalizer)
        }

        let rootNodes = buildPathTree(from: mergedEndpoints)

        return APIDomain(
            host: host,
            rootNodes: rootNodes,
            totalRequests: totalRequests,
            uniqueEndpoints: mergedEndpoints.count,
            methods: allMethods,
            classification: classification,
            category: classification == .thirdParty
                ? PathNormalizer.thirdPartyCategory(for: host)
                : nil,
            isExpanded: classification == .target
        )
    }

    // MARK: - Build Path Tree

    private static func buildPathTree(from endpoints: [APIEndpoint]) -> [PathNode] {
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

    private static func insertIntoTree(
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

    private static func parseParameterType(_ placeholder: String) -> ParameterType {
        let inner = String(placeholder.dropFirst().dropLast())
        return ParameterType(rawValue: inner) ?? .unknown
    }

    // MARK: - Merge Endpoints

    private static func mergeEndpoint(rows: [RawRow], normalizer: PathNormalizer) -> APIEndpoint? {
        guard let first = rows.first else { return nil }
        let (normalizedPath, _) = normalizer.normalizePath(first.path)

        var statusCounts: [Int: Int] = [:]
        var totalHits = 0
        var examples: [String] = []
        var hasReqBody = false
        var hasRespBody = false
        var contentTypes = Set<String>()

        for row in rows {
            totalHits += row.hitCount
            if let code = row.statusCode {
                statusCounts[code, default: 0] += row.hitCount
            }
            examples.append(row.path)
            hasReqBody = hasReqBody || row.hasRequestBody
            hasRespBody = hasRespBody || row.hasResponseBody
            contentTypes.formUnion(row.contentTypes)
        }

        let uniqueExamples = Array(NSOrderedSet(array: examples).array.compactMap { $0 as? String }.prefix(3))

        return APIEndpoint(
            normalizedPath: normalizedPath,
            method: first.method,
            statusCodes: Set(statusCounts.keys),
            statusCounts: statusCounts,
            hitCount: totalHits,
            examplePaths: uniqueExamples,
            hasRequestBody: hasReqBody,
            hasResponseBody: hasRespBody,
            contentTypes: contentTypes,
            graphqlOperations: buildGraphQLOperations(from: rows)
        )
    }

    private static func buildGraphQLOperations(from rows: [RawRow]) -> [GraphQLOperation] {
        let gqlRows = rows.filter { ($0.graphqlName?.isEmpty == false) }
        guard !gqlRows.isEmpty else { return [] }

        let grouped = Dictionary(grouping: gqlRows) { row in
            "\(row.graphqlName ?? ""):\(row.graphqlType ?? "")"
        }

        let operations = grouped.values.compactMap { group -> GraphQLOperation? in
            guard let first = group.first, let name = first.graphqlName else { return nil }
            var statusCounts: [Int: Int] = [:]
            var hits = 0
            for row in group {
                hits += row.hitCount
                if let code = row.statusCode {
                    statusCounts[code, default: 0] += row.hitCount
                }
            }
            return GraphQLOperation(
                name: name,
                type: GraphQLOperationType(rawDatabaseValue: first.graphqlType),
                hitCount: hits,
                statusCounts: statusCounts
            )
        }

        return operations.sorted { lhs, rhs in
            if lhs.hitCount != rhs.hitCount { return lhs.hitCount > rhs.hitCount }
            return lhs.name < rhs.name
        }
    }
}
