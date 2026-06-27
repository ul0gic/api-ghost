import Foundation

// MARK: - Encodable Extensions

extension Encodable {
    func toJSONString(prettyPrinted: Bool = false) -> String? {
        let encoder = JSONEncoder()
        if prettyPrinted {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        }
        guard let data = try? encoder.encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func toJSONData() -> Data? {
        try? JSONEncoder().encode(self)
    }
}

// MARK: - Decodable Extensions

extension Decodable {
    static func fromJSON(_ string: String) -> Self? {
        guard let data = string.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }

    static func fromJSON(_ data: Data) -> Self? {
        try? JSONDecoder().decode(Self.self, from: data)
    }
}

// MARK: - Capture Header Helpers

extension Capture {
    var requestHeadersDict: [String: String]? {
        guard let json = requestHeaders else { return nil }
        return [String: String].fromJSON(json)
    }

    var responseHeadersDict: [String: String]? {
        guard let json = responseHeaders else { return nil }
        return [String: String].fromJSON(json)
    }

    static func encodeHeaders(_ headers: [String: String]) -> String? {
        headers.toJSONString()
    }
}
