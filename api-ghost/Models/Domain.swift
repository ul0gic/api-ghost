import Foundation

struct Domain: Identifiable, Codable, Hashable {
    // MARK: - Properties

    let id: String

    let host: String

    var requestCount: Int

    var paths: [PathInfo]

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

struct PathInfo: Identifiable, Codable, Hashable {
    // MARK: - Properties

    var id: String { "\(method):\(path)" }

    let path: String

    let method: String

    var count: Int

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
    static func aggregate(from captures: [Capture]) -> [Domain] {
        var domainMap: [String: Domain] = [:]

        for capture in captures {
            let host = capture.host

            if var domain = domainMap[host] {
                domain.requestCount += 1
                domain.lastSeen = max(domain.lastSeen, capture.timestamp)

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
