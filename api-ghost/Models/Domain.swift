//
//  Domain.swift
//  api-ghost
//
//  Created for APIGhost project
//

import Foundation

/// Represents a domain (host) with aggregated request information for sidebar display.
struct Domain: Identifiable, Codable, Hashable {
    // MARK: - Properties

    /// Unique identifier (same as host)
    let id: String

    /// The domain host name
    let host: String

    /// Total number of requests to this domain
    var requestCount: Int

    /// List of paths accessed on this domain
    var paths: [PathInfo]

    /// When this domain was last seen
    var lastSeen: Date

    // MARK: - Initialization

    init(host: String, requestCount: Int = 0, paths: [PathInfo] = [], lastSeen: Date = Date()) {
        self.id = host
        self.host = host
        self.requestCount = requestCount
        self.paths = paths
        self.lastSeen = lastSeen
    }
}

/// Represents a path endpoint within a domain.
struct PathInfo: Identifiable, Codable, Hashable {
    // MARK: - Properties

    /// Unique identifier combining method and path
    var id: String { "\(method):\(path)" }

    /// The request path
    let path: String

    /// HTTP method used
    let method: String

    /// Number of times this path was accessed
    var count: Int

    /// Most recent status code received
    var lastStatus: Int?

    // MARK: - Initialization

    init(path: String, method: String, count: Int = 1, lastStatus: Int? = nil) {
        self.path = path
        self.method = method
        self.count = count
        self.lastStatus = lastStatus
    }
}

// MARK: - Domain Aggregation

extension Domain {
    /// Aggregates captures into domains with their paths.
    /// - Parameter captures: Array of captures to aggregate
    /// - Returns: Array of domains sorted by request count (descending)
    static func aggregate(from captures: [Capture]) -> [Domain] {
        var domainMap: [String: Domain] = [:]

        for capture in captures {
            let host = capture.host

            if var domain = domainMap[host] {
                domain.requestCount += 1
                domain.lastSeen = max(domain.lastSeen, capture.timestamp)

                // Update or add path
                let pathKey = "\(capture.method):\(capture.path)"
                if let index = domain.paths.firstIndex(where: { $0.id == pathKey }) {
                    domain.paths[index].count += 1
                    domain.paths[index].lastStatus = capture.statusCode
                } else {
                    domain.paths.append(PathInfo(
                        path: capture.path,
                        method: capture.method,
                        count: 1,
                        lastStatus: capture.statusCode
                    ))
                }

                domainMap[host] = domain
            } else {
                domainMap[host] = Domain(
                    host: host,
                    requestCount: 1,
                    paths: [
                        PathInfo(
                            path: capture.path,
                            method: capture.method,
                            count: 1,
                            lastStatus: capture.statusCode
                        )
                    ],
                    lastSeen: capture.timestamp
                )
            }
        }

        return Array(domainMap.values).sorted { $0.requestCount > $1.requestCount }
    }
}
