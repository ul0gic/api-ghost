//
//  RequestParser.swift
//  api-ghost
//
//  Created for APIGhost project
//

import Foundation

/// Provides HTTP request and response parsing utilities.
/// Parses raw HTTP data into structured components for capture storage.
struct RequestParser {
    // MARK: - Parsed Types

    /// Represents a parsed HTTP request.
    struct ParsedRequest {
        let method: String
        let path: String
        let query: String?
        let httpVersion: String
        let headers: [String: String]
        let body: Data?
    }

    /// Represents a parsed HTTP response.
    struct ParsedResponse {
        let httpVersion: String
        let statusCode: Int
        let statusMessage: String
        let headers: [String: String]
        let body: Data?
    }

    // MARK: - Request Parsing

    /// Parses raw HTTP request data into a structured ParsedRequest.
    /// - Parameter data: Raw HTTP request data
    /// - Returns: ParsedRequest if parsing succeeds, nil otherwise
    static func parseRequest(from data: Data) -> ParsedRequest? {
        guard let headerEndRange = findHeaderEnd(in: data) else { return nil }

        let headerData = data.prefix(upTo: headerEndRange.lowerBound)
        guard let headerString = String(data: headerData, encoding: .utf8) else { return nil }

        let lines = headerString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }

        // Parse request line: "GET /path?query HTTP/1.1"
        let parts = requestLine.split(separator: " ", maxSplits: 2)
        guard parts.count >= 3 else { return nil }

        let method = String(parts[0])
        let fullPath = String(parts[1])
        let httpVersion = String(parts[2])

        // Parse path and query
        let (path, query) = parsePathAndQuery(fullPath)

        // Parse headers
        let headers = parseHeaders(from: Array(lines.dropFirst()))

        // Extract body
        let bodyStartIndex = headerEndRange.upperBound
        let body: Data? = bodyStartIndex < data.count ? data.suffix(from: bodyStartIndex) : nil

        return ParsedRequest(
            method: method,
            path: path,
            query: query,
            httpVersion: httpVersion,
            headers: headers,
            body: body
        )
    }

    // MARK: - Response Parsing

    /// Parses raw HTTP response data into a structured ParsedResponse.
    /// - Parameter data: Raw HTTP response data
    /// - Returns: ParsedResponse if parsing succeeds, nil otherwise
    static func parseResponse(from data: Data) -> ParsedResponse? {
        guard let headerEndRange = findHeaderEnd(in: data) else { return nil }

        let headerData = data.prefix(upTo: headerEndRange.lowerBound)
        guard let headerString = String(data: headerData, encoding: .utf8) else { return nil }

        let lines = headerString.components(separatedBy: "\r\n")
        guard let statusLine = lines.first else { return nil }

        // Parse status line: "HTTP/1.1 200 OK"
        let parts = statusLine.split(separator: " ", maxSplits: 2)
        guard parts.count >= 2 else { return nil }

        let httpVersion = String(parts[0])
        guard let statusCode = Int(parts[1]) else { return nil }
        let statusMessage = parts.count > 2 ? String(parts[2]) : ""

        // Parse headers
        let headers = parseHeaders(from: Array(lines.dropFirst()))

        // Extract body
        let bodyStartIndex = headerEndRange.upperBound
        let body: Data? = bodyStartIndex < data.count ? data.suffix(from: bodyStartIndex) : nil

        return ParsedResponse(
            httpVersion: httpVersion,
            statusCode: statusCode,
            statusMessage: statusMessage,
            headers: headers,
            body: body
        )
    }

    // MARK: - Helper Methods

    /// Finds the end of HTTP headers (indicated by \r\n\r\n).
    /// - Parameter data: The data to search in
    /// - Returns: Range of the header separator if found
    private static func findHeaderEnd(in data: Data) -> Range<Data.Index>? {
        let separator = Data("\r\n\r\n".utf8)
        return data.range(of: separator)
    }

    /// Parses a full path into path and query components.
    /// - Parameter fullPath: The full URL path including query string
    /// - Returns: Tuple of (path, query) where query may be nil
    private static func parsePathAndQuery(_ fullPath: String) -> (path: String, query: String?) {
        if let queryStart = fullPath.firstIndex(of: "?") {
            let path = String(fullPath[..<queryStart])
            let query = String(fullPath[fullPath.index(after: queryStart)...])
            return (path.isEmpty ? "/" : path, query.isEmpty ? nil : query)
        }
        return (fullPath.isEmpty ? "/" : fullPath, nil)
    }

    /// Parses HTTP header lines into a dictionary.
    /// - Parameter lines: Array of header lines (excluding the request/status line)
    /// - Returns: Dictionary of header names to values
    private static func parseHeaders(from lines: [String]) -> [String: String] {
        var headers: [String: String] = [:]

        for line in lines {
            guard !line.isEmpty else { continue }

            if let colonIndex = line.firstIndex(of: ":") {
                let key = String(line[..<colonIndex]).trimmingCharacters(in: .whitespaces)
                let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                headers[key] = value
            }
        }

        return headers
    }

    // MARK: - Content Type Helpers

    /// Extracts the Content-Type from a headers dictionary (case-insensitive).
    /// - Parameter headers: The headers dictionary to search
    /// - Returns: The content type without parameters (e.g., "application/json")
    static func getContentType(from headers: [String: String]) -> String? {
        // Headers are case-insensitive
        for (key, value) in headers where key.lowercased() == "content-type" {
            // Strip charset and other parameters
            return value.split(separator: ";").first.map(String.init)
        }
        return nil
    }

    /// Extracts the Content-Length from a headers dictionary (case-insensitive).
    /// - Parameter headers: The headers dictionary to search
    /// - Returns: The content length as an integer if found and valid
    static func getContentLength(from headers: [String: String]) -> Int? {
        for (key, value) in headers where key.lowercased() == "content-length" {
            return Int(value)
        }
        return nil
    }
}
