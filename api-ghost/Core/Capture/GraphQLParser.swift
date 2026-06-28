import Foundation

nonisolated enum GraphQLOperationType: String, Equatable, Sendable {
    case query
    case mutation
    case subscription
    case unknown
}

nonisolated struct GraphQLOperationInfo: Equatable, Sendable {
    let operationName: String?
    let operationType: GraphQLOperationType
    let isPersisted: Bool
    let isBatch: Bool

    nonisolated init(
        operationName: String?,
        operationType: GraphQLOperationType,
        isPersisted: Bool = false,
        isBatch: Bool = false
    ) {
        self.operationName = operationName
        self.operationType = operationType
        self.isPersisted = isPersisted
        self.isBatch = isBatch
    }

    /// `nil` for `.unknown` so the column stays clean for API Map grouping; a known type stores its raw value.
    nonisolated var storedOperationType: String? {
        operationType == .unknown ? nil : operationType.rawValue
    }
}

nonisolated enum GraphQLParser {
    nonisolated static func parse(
        method: String,
        url: URL,
        contentType: String?,
        body: Data?
    ) -> GraphQLOperationInfo? {
        let isGraphQLPath = pathLooksGraphQL(url)

        if method.uppercased() == "GET" {
            return parseGet(url: url, isGraphQLPath: isGraphQLPath)
        }

        if let contentType, contentType.lowercased().contains("application/graphql"),
           let body, let text = String(data: body, encoding: .utf8) {
            return GraphQLOperationInfo(
                operationName: operationName(fromQuery: text),
                operationType: operationType(fromQuery: text)
            )
        }

        if let body, !body.isEmpty,
           let json = try? JSONSerialization.jsonObject(with: body) {
            if let array = json as? [Any] {
                return parseBatch(array, isGraphQLPath: isGraphQLPath)
            }
            if let object = json as? [String: Any] {
                return parseSingle(object, isGraphQLPath: isGraphQLPath)
            }
        }

        guard isGraphQLPath else { return nil }
        return GraphQLOperationInfo(operationName: nil, operationType: .unknown)
    }

    // MARK: - Body shapes

    nonisolated private static func parseSingle(_ object: [String: Any], isGraphQLPath: Bool) -> GraphQLOperationInfo? {
        let queryText = object["query"] as? String
        let explicitName = nonEmpty(object["operationName"] as? String)
        let persisted = hasPersistedQuery(object)

        let strongSignal = explicitName != nil || persisted || isGraphQLPath
        let queryIsDocument = queryText.map(looksLikeGraphQLDocument) ?? false
        guard strongSignal || queryIsDocument else { return nil }

        let type = queryText.map(operationType(fromQuery:)) ?? .unknown
        let name = explicitName ?? queryText.flatMap(operationName(fromQuery:))
        return GraphQLOperationInfo(operationName: name, operationType: type, isPersisted: persisted)
    }

    nonisolated private static func parseBatch(_ array: [Any], isGraphQLPath: Bool) -> GraphQLOperationInfo? {
        let objects = array.compactMap { $0 as? [String: Any] }
        guard objects.contains(where: isGraphQLObject) || isGraphQLPath else { return nil }

        let first = objects.first(where: isGraphQLObject) ?? objects.first
        let info = first.flatMap { parseSingle($0, isGraphQLPath: isGraphQLPath) }
        return GraphQLOperationInfo(
            operationName: info?.operationName,
            operationType: info?.operationType ?? .unknown,
            isPersisted: info?.isPersisted ?? false,
            isBatch: true
        )
    }

    nonisolated private static func parseGet(url: URL, isGraphQLPath: Bool) -> GraphQLOperationInfo? {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let queryText = items.first { $0.name == "query" }?.value
        let explicitName = nonEmpty(items.first { $0.name == "operationName" }?.value)
        let persisted = items.first { $0.name == "extensions" }?.value?.contains("persistedQuery") ?? false

        let strongSignal = explicitName != nil || persisted || isGraphQLPath
        let queryIsDocument = queryText.map(looksLikeGraphQLDocument) ?? false
        guard strongSignal || queryIsDocument else { return nil }

        let type = queryText.map(operationType(fromQuery:)) ?? .unknown
        let name = explicitName ?? queryText.flatMap(operationName(fromQuery:))
        return GraphQLOperationInfo(operationName: name, operationType: type, isPersisted: persisted)
    }

    // MARK: - Detection helpers

    nonisolated private static func pathLooksGraphQL(_ url: URL) -> Bool {
        let path = url.path.lowercased()
        return path.contains("graphql") || path.contains("/gql")
    }

    nonisolated private static func isGraphQLObject(_ object: [String: Any]) -> Bool {
        (object["query"] as? String).map(looksLikeGraphQLDocument) == true
            || nonEmpty(object["operationName"] as? String) != nil
            || hasPersistedQuery(object)
    }

    nonisolated private static func looksLikeGraphQLDocument(_ query: String) -> Bool {
        let stripped = stripLeading(query)
        guard let first = stripped.first else { return false }
        if first == "{" { return true }
        let keyword = String(stripped.prefix { $0.isLetter })
        guard ["query", "mutation", "subscription", "fragment"].contains(keyword) else { return false }
        return stripped.contains("{")
    }

    nonisolated private static func hasPersistedQuery(_ object: [String: Any]) -> Bool {
        (object["extensions"] as? [String: Any])?["persistedQuery"] != nil
    }

    nonisolated private static func nonEmpty(_ string: String?) -> String? {
        guard let string, !string.isEmpty else { return nil }
        return string
    }

    // MARK: - Query text parsing

    nonisolated static func operationType(fromQuery query: String) -> GraphQLOperationType {
        let stripped = stripLeading(query)
        if stripped.hasPrefix("{") { return .query }
        switch String(stripped.prefix { $0.isLetter }) {
        case "mutation": return .mutation
        case "subscription": return .subscription
        case "query": return .query
        default: return .unknown
        }
    }

    nonisolated static func operationName(fromQuery query: String) -> String? {
        var rest = Substring(stripLeading(query))
        guard !rest.hasPrefix("{") else { return nil }

        let keyword = rest.prefix { $0.isLetter }
        guard ["query", "mutation", "subscription"].contains(String(keyword)) else { return nil }

        rest = rest.dropFirst(keyword.count).drop { $0.isWhitespace }
        let name = rest.prefix { $0.isLetter || $0.isNumber || $0 == "_" }
        return name.isEmpty ? nil : String(name)
    }

    nonisolated private static func stripLeading(_ string: String) -> String {
        var index = string.startIndex
        while index < string.endIndex {
            let character = string[index]
            if character.isWhitespace || character == "," {
                index = string.index(after: index)
            } else if character == "#" {
                while index < string.endIndex, string[index] != "\n" {
                    index = string.index(after: index)
                }
            } else {
                break
            }
        }
        return String(string[index...])
    }
}
