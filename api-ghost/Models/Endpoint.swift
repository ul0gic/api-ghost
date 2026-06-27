//
//  Endpoint.swift
//  api-ghost
//
//  Created for APIGhost project
//

import Foundation

/// Represents an API endpoint with parameterized path pattern for endpoint mapping.
struct Endpoint: Identifiable, Codable, Hashable {
    // MARK: - Properties

    /// Unique identifier combining method, host, and path pattern
    let id: String

    /// The domain host
    let host: String

    /// Parameterized path pattern (e.g., /users/{id})
    let pathPattern: String

    /// HTTP method
    let method: String

    /// Number of times this endpoint was called
    var callCount: Int

    /// Most common status code returned
    var typicalStatus: Int?

    /// When this endpoint was last accessed
    var lastSeen: Date

    /// Whether interesting findings were detected
    var hasInterestingFindings: Bool

    /// List of findings for this endpoint
    var findings: [EndpointFinding]

    // MARK: - Initialization

    init(
        host: String,
        pathPattern: String,
        method: String,
        callCount: Int = 1,
        typicalStatus: Int? = nil,
        lastSeen: Date = Date(),
        hasInterestingFindings: Bool = false,
        findings: [EndpointFinding] = []
    ) {
        self.id = "\(method):\(host)\(pathPattern)"
        self.host = host
        self.pathPattern = pathPattern
        self.method = method
        self.callCount = callCount
        self.typicalStatus = typicalStatus
        self.lastSeen = lastSeen
        self.hasInterestingFindings = hasInterestingFindings
        self.findings = findings
    }
}

/// Represents an interesting finding detected for an endpoint.
struct EndpointFinding: Identifiable, Codable, Hashable {
    // MARK: - Properties

    /// Unique identifier
    let id: String

    /// Type of finding
    let type: FindingType

    /// Human-readable description
    let description: String

    /// Severity level
    let severity: FindingSeverity

    // MARK: - Initialization

    init(type: FindingType, description: String, severity: FindingSeverity = .info) {
        self.id = UUID().uuidString
        self.type = type
        self.description = description
        self.severity = severity
    }
}

/// Types of interesting findings that can be detected.
enum FindingType: String, Codable, Hashable {
    case internalEndpoint = "internal_endpoint"
    case debugEndpoint = "debug_endpoint"
    case adminEndpoint = "admin_endpoint"
    case sequentialIds = "sequential_ids"
    case largeResponse = "large_response"
    case errorWithStackTrace = "error_with_stack_trace"
    case sensitiveData = "sensitive_data"
}

/// Severity levels for findings.
enum FindingSeverity: String, Codable, Hashable {
    case info
    case low
    case medium
    case high
}

// MARK: - Path Parameterization

extension Endpoint {
    /// Converts a concrete path to a parameterized pattern.
    /// Example: /users/123/posts/456 becomes /users/{id}/posts/{id}
    /// - Parameter path: The concrete path to parameterize
    /// - Returns: The parameterized path pattern
    static func parameterizePath(_ path: String) -> String {
        let components = path.split(separator: "/")
        let parameterized = components.map { component -> String in
            let str = String(component)
            // Check if it looks like an ID (numeric, UUID, or hex string)
            if str.isLikelyId {
                return "{id}"
            }
            return str
        }
        return "/" + parameterized.joined(separator: "/")
    }
}

// MARK: - String ID Detection

extension String {
    /// Determines if this string looks like an identifier (numeric, UUID, or hex).
    var isLikelyId: Bool {
        // Numeric ID
        if Int(self) != nil { return true }

        // UUID pattern
        if self.count == 36 && self.contains("-") {
            let uuidRegex = try? NSRegularExpression(
                pattern: "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"
            )
            let range = NSRange(self.startIndex..., in: self)
            if uuidRegex?.firstMatch(in: self, range: range) != nil { return true }
        }

        // Hex string (common for MongoDB ObjectIds, etc.)
        if self.count >= 16 && self.count <= 32 {
            let hexRegex = try? NSRegularExpression(pattern: "^[0-9a-fA-F]+$")
            let range = NSRange(self.startIndex..., in: self)
            if hexRegex?.firstMatch(in: self, range: range) != nil { return true }
        }

        return false
    }
}
