import Foundation
import GRDB

// MARK: - Endpoint Aggregation

extension CaptureStore {
    func aggregateEndpoints() throws -> [Endpoint] {
        guard let db = DatabaseManager.shared.database else { return [] }

        return try db.read { db in
            let captures = try Capture.fetchAll(db)

            let endpointMap = buildEndpointMap(from: captures)

            return endpointMap.values.map { aggregation in
                Self.convertToEndpoint(aggregation)
            }
            .sorted { $0.callCount > $1.callCount }
        }
    }

    private func buildEndpointMap(from captures: [Capture]) -> [String: EndpointAggregation] {
        var endpointMap: [String: EndpointAggregation] = [:]

        for capture in captures {
            let pathPattern = Endpoint.parameterizePath(capture.path)
            let key = "\(capture.method):\(capture.host)\(pathPattern)"

            if var aggregation = endpointMap[key] {
                aggregation.callCount += 1
                aggregation.statusCodes.append(capture.statusCode ?? 0)
                aggregation.responseSizes.append(capture.responseBodySize)
                if capture.timestamp > aggregation.lastSeen {
                    aggregation.lastSeen = capture.timestamp
                }
                aggregation.originalPaths.append(capture.path)
                if let responseBody = capture.responseBody {
                    aggregation.responseBodies.append(responseBody)
                }
                endpointMap[key] = aggregation
            } else {
                endpointMap[key] = EndpointAggregation(
                    host: capture.host,
                    pathPattern: pathPattern,
                    method: capture.method,
                    callCount: 1,
                    statusCodes: [capture.statusCode ?? 0],
                    responseSizes: [capture.responseBodySize],
                    lastSeen: capture.timestamp,
                    originalPaths: [capture.path],
                    responseBodies: capture.responseBody.map { [$0] } ?? []
                )
            }
        }

        return endpointMap
    }

    private static func convertToEndpoint(_ aggregation: EndpointAggregation) -> Endpoint {
        let typicalStatus = calculateTypicalStatus(from: aggregation.statusCodes)
        let findings = detectFindings(for: aggregation)

        return Endpoint(
            host: aggregation.host,
            pathPattern: aggregation.pathPattern,
            method: aggregation.method,
            callCount: aggregation.callCount,
            typicalStatus: typicalStatus,
            lastSeen: aggregation.lastSeen,
            hasInterestingFindings: !findings.isEmpty,
            findings: findings
        )
    }

    func fetchEndpointsByDomain() throws -> [String: [Endpoint]] {
        let endpoints = try aggregateEndpoints()
        return Dictionary(grouping: endpoints) { $0.host }
    }

    func uniqueEndpointCount() throws -> Int {
        try aggregateEndpoints().count
    }

    func uniqueDomainCount() throws -> Int {
        guard let db = DatabaseManager.shared.database else { return 0 }
        return try db.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT COUNT(DISTINCT host) as count
                FROM captures
            """)
            return rows.first?["count"] ?? 0
        }
    }

    func uniquePathCount() throws -> Int {
        guard let db = DatabaseManager.shared.database else { return 0 }
        return try db.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT COUNT(DISTINCT host || method || path) as count
                FROM captures
            """)
            return rows.first?["count"] ?? 0
        }
    }
}

// MARK: - Findings Detection

extension CaptureStore {
    static func calculateTypicalStatus(from statusCodes: [Int]) -> Int? {
        let filtered = statusCodes.filter { $0 > 0 }
        guard !filtered.isEmpty else { return nil }

        var frequency: [Int: Int] = [:]
        for code in filtered {
            frequency[code, default: 0] += 1
        }

        return frequency.max { $0.value < $1.value }?.key
    }

    static func detectFindings(for aggregation: EndpointAggregation) -> [EndpointFinding] {
        var findings: [EndpointFinding] = []

        detectSensitivePaths(in: aggregation, findings: &findings)
        detectSequentialIds(in: aggregation, findings: &findings)
        detectLargeResponses(in: aggregation, findings: &findings)
        detectStackTraces(in: aggregation, findings: &findings)

        return findings
    }

    private static func detectSensitivePaths(
        in aggregation: EndpointAggregation,
        findings: inout [EndpointFinding]
    ) {
        let sensitivePatterns = [
            "/internal", "/debug", "/admin",
            "/_internal", "/_debug", "/_admin",
            "/api/internal", "/api/debug", "/api/admin"
        ]
        let lowercasePath = aggregation.pathPattern.lowercased()

        for pattern in sensitivePatterns where lowercasePath.contains(pattern) {
            let findingType: FindingType
            if pattern.contains("internal") {
                findingType = .internalEndpoint
            } else if pattern.contains("debug") {
                findingType = .debugEndpoint
            } else {
                findingType = .adminEndpoint
            }

            findings.append(EndpointFinding(
                type: findingType,
                description: "Potentially sensitive endpoint detected: \(pattern)",
                severity: .medium
            ))
            break
        }
    }

    private static func detectSequentialIds(
        in aggregation: EndpointAggregation,
        findings: inout [EndpointFinding]
    ) {
        guard aggregation.pathPattern.contains("{id}"),
              aggregation.originalPaths.count >= 2 else { return }

        let numericIds = aggregation.originalPaths.compactMap { path -> Int? in
            let components = path.split(separator: "/")
            for component in components {
                if let num = Int(component) { return num }
            }
            return nil
        }
        .sorted()

        guard numericIds.count >= 2 else { return }

        let hasSequential = zip(numericIds, numericIds.dropFirst())
            .contains { $0.1 - $0.0 == 1 }

        if hasSequential {
            findings.append(EndpointFinding(
                type: .sequentialIds,
                description: "Sequential numeric IDs detected - potential IDOR vulnerability",
                severity: .high
            ))
        }
    }

    private static func detectLargeResponses(
        in aggregation: EndpointAggregation,
        findings: inout [EndpointFinding]
    ) {
        let largeResponseThreshold = 100_000
        let maxResponseSize = aggregation.responseSizes.max() ?? 0

        if maxResponseSize > largeResponseThreshold {
            let sizeKB = maxResponseSize / 1024
            findings.append(EndpointFinding(
                type: .largeResponse,
                description: "Large response detected (\(sizeKB)KB) - potential over-fetching",
                severity: .low
            ))
        }
    }

    private static func detectStackTraces(
        in aggregation: EndpointAggregation,
        findings: inout [EndpointFinding]
    ) {
        let stackTracePatterns = [
            "at .+\\(.+:\\d+:\\d+\\)",
            "File \".+\", line \\d+",
            "\\sat\\s.+\\(.+\\.java:\\d+\\)",
            "Stack trace:",
            "Traceback \\(most recent call last\\):",
            "Exception in thread",
            "panic:",
            "goroutine \\d+ \\[running\\]:"
        ]

        for responseBody in aggregation.responseBodies {
            guard let bodyString = String(data: responseBody, encoding: .utf8) else { continue }

            let hasStackTrace = stackTracePatterns.contains { pattern in
                guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
                    return false
                }
                let range = NSRange(bodyString.startIndex..., in: bodyString)
                return regex.firstMatch(in: bodyString, range: range) != nil
            }

            if hasStackTrace {
                findings.append(EndpointFinding(
                    type: .errorWithStackTrace,
                    description: "Error response contains stack trace - information disclosure risk",
                    severity: .medium
                ))
                return
            }
        }
    }
}

// MARK: - Endpoint Aggregation Helper

struct EndpointAggregation {
    let host: String
    let pathPattern: String
    let method: String
    var callCount: Int
    var statusCodes: [Int]
    var responseSizes: [Int]
    var lastSeen: Date
    var originalPaths: [String]
    var responseBodies: [Data]
}
