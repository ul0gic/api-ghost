//
//  SQLQuickQueries.swift
//  APIGhost
//
//  Quick query types and time range filters for the SQL Explorer.
//

import Foundation

// MARK: - Quick Query Types

enum QuickQueryType: String, CaseIterable, Identifiable {
    case allCaptures = "Recent"
    case jsonResponses = "JSON"
    case failedRequests = "Failed"
    case slowRequests = "Slow"
    case graphQL = "GraphQL"
    case authEndpoints = "Auth"
    case byDomain = "By Domain"
    case largeBodies = "Large"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .allCaptures: return "list.bullet"
        case .jsonResponses: return "curlybraces"
        case .failedRequests: return "exclamationmark.triangle"
        case .slowRequests: return "tortoise"
        case .graphQL: return "point.3.connected.trianglepath.dotted"
        case .authEndpoints: return "lock"
        case .byDomain: return "globe"
        case .largeBodies: return "doc.fill"
        }
    }

    var description: String {
        switch self {
        case .allCaptures: return "Recent API captures"
        case .jsonResponses: return "JSON responses only"
        case .failedRequests: return "4xx and 5xx errors"
        case .slowRequests: return "Requests > 1 second"
        case .graphQL: return "GraphQL endpoints"
        case .authEndpoints: return "Auth/login endpoints"
        case .byDomain: return "Group by domain"
        case .largeBodies: return "Large response bodies"
        }
    }

    var sql: String {
        switch self {
        case .allCaptures:
            return """
                SELECT id, method, host, path, status_code, content_type,
                       response_body_size, duration_ms, timestamp
                FROM captures
                ORDER BY timestamp DESC
                LIMIT 100
                """
        case .jsonResponses:
            return """
                SELECT id, method, host, path, status_code, content_type,
                       response_body_size, duration_ms, timestamp
                FROM captures
                WHERE content_type LIKE '%json%'
                ORDER BY timestamp DESC
                LIMIT 100
                """
        case .failedRequests:
            return """
                SELECT id, method, host, path, status_code, status_message,
                       content_type, response_body_size, duration_ms, timestamp
                FROM captures
                WHERE status_code >= 400
                ORDER BY timestamp DESC
                LIMIT 100
                """
        case .slowRequests:
            return """
                SELECT id, method, host, path, status_code, content_type,
                       response_body_size, duration_ms, timestamp
                FROM captures
                WHERE duration_ms > 1000
                ORDER BY duration_ms DESC
                LIMIT 100
                """
        case .graphQL:
            return """
                SELECT id, method, host, path, status_code, content_type,
                       response_body_size, duration_ms, timestamp
                FROM captures
                WHERE path LIKE '%graphql%' OR path LIKE '%gql%'
                ORDER BY timestamp DESC
                LIMIT 100
                """
        case .authEndpoints:
            return """
                SELECT id, method, host, path, status_code, content_type,
                       response_body_size, duration_ms, timestamp
                FROM captures
                WHERE path LIKE '%auth%' OR path LIKE '%login%'
                   OR path LIKE '%token%' OR path LIKE '%oauth%'
                   OR path LIKE '%signin%' OR path LIKE '%session%'
                ORDER BY timestamp DESC
                LIMIT 100
                """
        case .byDomain:
            return """
                SELECT host, COUNT(*) as request_count,
                       AVG(duration_ms) as avg_duration_ms,
                       SUM(response_body_size) as total_bytes
                FROM captures
                GROUP BY host
                ORDER BY request_count DESC
                """
        case .largeBodies:
            return """
                SELECT id, method, host, path, status_code, content_type,
                       response_body_size, duration_ms, timestamp
                FROM captures
                WHERE response_body_size > 10000
                ORDER BY response_body_size DESC
                LIMIT 100
                """
        }
    }
}

// MARK: - Time Range Filter

enum TimeRangeFilter: String, CaseIterable {
    case all = "All Time"
    case lastHour = "Last Hour"
    case today = "Today"
    case yesterday = "Yesterday"
    case lastWeek = "Last Week"

    var sqlCondition: String? {
        switch self {
        case .all:
            return nil
        case .lastHour:
            return "timestamp >= datetime('now', '-1 hour')"
        case .today:
            return "timestamp >= datetime('now', 'start of day')"
        case .yesterday:
            return "timestamp >= datetime('now', '-1 day', 'start of day') "
                + "AND timestamp < datetime('now', 'start of day')"
        case .lastWeek:
            return "timestamp >= datetime('now', '-7 days')"
        }
    }
}
