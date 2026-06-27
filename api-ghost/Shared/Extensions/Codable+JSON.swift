//
//  Codable+JSON.swift
//  api-ghost
//
//  Created for APIGhost project
//

import Foundation

// MARK: - Encodable Extensions

extension Encodable {
    /// Converts this value to a JSON string.
    /// - Parameter prettyPrinted: Whether to format the output with indentation
    /// - Returns: JSON string or nil if encoding fails
    func toJSONString(prettyPrinted: Bool = false) -> String? {
        let encoder = JSONEncoder()
        if prettyPrinted {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        }
        guard let data = try? encoder.encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Converts this value to JSON data.
    /// - Returns: JSON data or nil if encoding fails
    func toJSONData() -> Data? {
        try? JSONEncoder().encode(self)
    }
}

// MARK: - Decodable Extensions

extension Decodable {
    /// Creates an instance from a JSON string.
    /// - Parameter string: The JSON string to decode
    /// - Returns: Decoded instance or nil if decoding fails
    static func fromJSON(_ string: String) -> Self? {
        guard let data = string.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }

    /// Creates an instance from JSON data.
    /// - Parameter data: The JSON data to decode
    /// - Returns: Decoded instance or nil if decoding fails
    static func fromJSON(_ data: Data) -> Self? {
        try? JSONDecoder().decode(Self.self, from: data)
    }
}

// MARK: - Capture Header Helpers

extension Capture {
    /// Returns the request headers as a dictionary.
    var requestHeadersDict: [String: String]? {
        guard let json = requestHeaders else { return nil }
        return [String: String].fromJSON(json)
    }

    /// Returns the response headers as a dictionary.
    var responseHeadersDict: [String: String]? {
        guard let json = responseHeaders else { return nil }
        return [String: String].fromJSON(json)
    }

    /// Encodes a headers dictionary to a JSON string.
    /// - Parameter headers: The headers dictionary to encode
    /// - Returns: JSON string or nil if encoding fails
    static func encodeHeaders(_ headers: [String: String]) -> String? {
        headers.toJSONString()
    }
}
