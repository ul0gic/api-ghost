import Foundation

// MARK: - Builder Input Row

/// DB-free fixture surface for `APIMapBuilder.buildDomains(from:)`.
nonisolated struct RawRow: Sendable {
    let host: String
    let path: String
    let method: String
    let statusCode: Int?
    let graphqlName: String?
    let graphqlType: String?
    let hitCount: Int
    let hasRequestBody: Bool
    let hasResponseBody: Bool
    let contentTypes: [String]

    nonisolated init(
        host: String,
        path: String,
        method: String,
        statusCode: Int? = nil,
        graphqlName: String? = nil,
        graphqlType: String? = nil,
        hitCount: Int = 1,
        hasRequestBody: Bool = false,
        hasResponseBody: Bool = false,
        contentTypes: [String] = []
    ) {
        self.host = host
        self.path = path
        self.method = method
        self.statusCode = statusCode
        self.graphqlName = graphqlName
        self.graphqlType = graphqlType
        self.hitCount = hitCount
        self.hasRequestBody = hasRequestBody
        self.hasResponseBody = hasResponseBody
        self.contentTypes = contentTypes
    }
}

// MARK: - Internal Builder Helpers

struct DomainRank {
    let key: String
    let requests: Int
    let endpoints: Int
}

final class PathNodeBuilder {
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
