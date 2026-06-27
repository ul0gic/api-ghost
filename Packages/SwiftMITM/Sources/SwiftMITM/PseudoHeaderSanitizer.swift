import NIOHPACK

public enum HeaderSanitizationError: Error, Equatable, Sendable {
    case missingPseudoHeader(String)
    case duplicatePseudoHeader(String)
    case illegalCharacterInPseudoHeader(String)
    case illegalCharacterInHeader(String)
    case uppercaseHeaderName(String)
    case invalidPath
    case invalidAuthority
    case connectionSpecificHeader(String)
    case conflictingContentLength
    case illegalTransferEncoding
}

public struct SanitizedRequestLine: Sendable, Equatable {
    public let method: String
    public let scheme: String
    public let authority: String
    public let path: String
    public let headers: [HTTPHeaderField]
}

/// Defends the h2→h1 translation seam against the request-smuggling CVE class (the reason
/// swift-nio-http2 carries its own HPACK validation, re-checked here because this is a security tool
/// parsing hostile traffic). Rejects CR/LF and control-character injection in pseudo-headers,
/// duplicate/missing pseudo-headers, connection-specific headers that must not survive into h1
/// (RFC 9113 §8.2.2), and CL/TE framing ambiguity. Pure and synchronous — trivially fuzzable.
public enum PseudoHeaderSanitizer {
    private static let connectionSpecific: Set<String> = [
        "connection", "keep-alive", "proxy-connection", "upgrade"
    ]

    public static func sanitizeRequest(
        _ headers: HPACKHeaders
    ) -> Result<SanitizedRequestLine, HeaderSanitizationError> {
        do {
            let method = try requirePseudoHeader(":method", in: headers)
            let scheme = try requirePseudoHeader(":scheme", in: headers)
            let authority = try requirePseudoHeader(":authority", in: headers)
            let path = try requirePseudoHeader(":path", in: headers)

            guard path.first == "/" || (method == "OPTIONS" && path == "*") else {
                throw HeaderSanitizationError.invalidPath
            }
            guard !authority.contains("/"), !authority.contains(" ") else {
                throw HeaderSanitizationError.invalidAuthority
            }

            let regular = try sanitizeRegularHeaders(headers)
            return .success(
                SanitizedRequestLine(
                    method: method,
                    scheme: scheme,
                    authority: authority,
                    path: path,
                    headers: regular
                )
            )
        } catch let error as HeaderSanitizationError {
            return .failure(error)
        } catch {
            return .failure(.illegalCharacterInHeader("unknown"))
        }
    }

    private static func requirePseudoHeader(
        _ name: String,
        in headers: HPACKHeaders
    ) throws -> String {
        let values = headers[name]
        guard let value = values.first else {
            throw HeaderSanitizationError.missingPseudoHeader(name)
        }
        guard values.count == 1 else {
            throw HeaderSanitizationError.duplicatePseudoHeader(name)
        }
        guard !containsControlCharacter(value) else {
            throw HeaderSanitizationError.illegalCharacterInPseudoHeader(name)
        }
        return value
    }

    private static func sanitizeRegularHeaders(
        _ headers: HPACKHeaders
    ) throws -> [HTTPHeaderField] {
        var result: [HTTPHeaderField] = []
        var contentLengths: Set<String> = []
        var sawTransferEncoding = false

        for (name, value, _) in headers where !name.hasPrefix(":") {
            let lower = name.lowercased()
            try validateRegularHeader(name: name, lower: lower, value: value)
            if lower == "transfer-encoding" {
                sawTransferEncoding = true
                continue
            }
            if lower == "content-length" {
                try recordContentLength(value, into: &contentLengths)
            }
            result.append(HTTPHeaderField(name: lower, value: value))
        }

        if sawTransferEncoding {
            throw HeaderSanitizationError.illegalTransferEncoding
        }
        if contentLengths.count > 1 {
            throw HeaderSanitizationError.conflictingContentLength
        }
        return result
    }

    private static func validateRegularHeader(name: String, lower: String, value: String) throws {
        if name != lower {
            throw HeaderSanitizationError.uppercaseHeaderName(name)
        }
        if containsControlCharacter(value) || containsControlCharacter(name) {
            throw HeaderSanitizationError.illegalCharacterInHeader(name)
        }
        if connectionSpecific.contains(lower) {
            throw HeaderSanitizationError.connectionSpecificHeader(lower)
        }
        if lower == "te", value.lowercased() != "trailers" {
            throw HeaderSanitizationError.connectionSpecificHeader("te")
        }
    }

    private static func recordContentLength(_ value: String, into set: inout Set<String>) throws {
        set.insert(value)
        guard value.allSatisfy(\.isNumber) else {
            throw HeaderSanitizationError.conflictingContentLength
        }
    }

    private static func containsControlCharacter(_ value: String) -> Bool {
        value.utf8.contains { $0 < 0x20 || $0 == 0x7F }
    }
}
