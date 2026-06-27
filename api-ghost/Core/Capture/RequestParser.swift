import Foundation

struct RequestParser {
    // MARK: - Parsed Types

    struct ParsedRequest {
        let method: String
        let path: String
        let query: String?
        let httpVersion: String
        let headers: [String: String]
        let body: Data?
    }

    struct ParsedResponse {
        let httpVersion: String
        let statusCode: Int
        let statusMessage: String
        let headers: [String: String]
        let body: Data?
    }

    // MARK: - Request Parsing

    static func parseRequest(from data: Data) -> ParsedRequest? {
        guard let headerEndRange = findHeaderEnd(in: data) else { return nil }

        let headerData = data.prefix(upTo: headerEndRange.lowerBound)
        guard let headerString = String(data: headerData, encoding: .utf8) else { return nil }

        let lines = headerString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }

        let parts = requestLine.split(separator: " ", maxSplits: 2)
        guard parts.count >= 3 else { return nil }

        let method = String(parts[0])
        let fullPath = String(parts[1])
        let httpVersion = String(parts[2])

        let (path, query) = parsePathAndQuery(fullPath)

        let headers = parseHeaders(from: Array(lines.dropFirst()))

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

    static func parseResponse(from data: Data) -> ParsedResponse? {
        guard let headerEndRange = findHeaderEnd(in: data) else { return nil }

        let headerData = data.prefix(upTo: headerEndRange.lowerBound)
        guard let headerString = String(data: headerData, encoding: .utf8) else { return nil }

        let lines = headerString.components(separatedBy: "\r\n")
        guard let statusLine = lines.first else { return nil }

        let parts = statusLine.split(separator: " ", maxSplits: 2)
        guard parts.count >= 2 else { return nil }

        let httpVersion = String(parts[0])
        guard let statusCode = Int(parts[1]) else { return nil }
        let statusMessage = parts.count > 2 ? String(parts[2]) : ""

        let headers = parseHeaders(from: Array(lines.dropFirst()))

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

    private static func findHeaderEnd(in data: Data) -> Range<Data.Index>? {
        let separator = Data("\r\n\r\n".utf8)
        return data.range(of: separator)
    }

    private static func parsePathAndQuery(_ fullPath: String) -> (path: String, query: String?) {
        if let queryStart = fullPath.firstIndex(of: "?") {
            let path = String(fullPath[..<queryStart])
            let query = String(fullPath[fullPath.index(after: queryStart)...])
            return (path.isEmpty ? "/" : path, query.isEmpty ? nil : query)
        }
        return (fullPath.isEmpty ? "/" : fullPath, nil)
    }

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

    static func getContentType(from headers: [String: String]) -> String? {
        for (key, value) in headers where key.lowercased() == "content-type" {
            return value.split(separator: ";").first.map(String.init)
        }
        return nil
    }

    static func getContentLength(from headers: [String: String]) -> Int? {
        for (key, value) in headers where key.lowercased() == "content-length" {
            return Int(value)
        }
        return nil
    }
}
