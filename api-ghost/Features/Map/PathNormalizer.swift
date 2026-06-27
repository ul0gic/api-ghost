//
//  PathNormalizer.swift
//  APIGhost
//
//  Smart path normalization with pattern detection for API endpoint analysis.
//  Detects UUIDs, numeric IDs, hashes, tokens, and other dynamic path segments.
//

import Foundation

/// A compiled pattern for detecting dynamic path segments.
struct PatternRule {
    let type: ParameterType
    let regex: NSRegularExpression
    let minLength: Int
}

/// Normalizes URL paths by detecting and replacing dynamic parameters with placeholders.
/// Thread-safe singleton for use throughout the application.
final class PathNormalizer: @unchecked Sendable {
    // MARK: - Singleton

    static let shared = PathNormalizer()

    // MARK: - Pattern Definitions

    /// Compiled regex patterns with their corresponding parameter types.
    /// Ordered by specificity (most specific patterns first).
    private let patterns: [PatternRule]

    /// Known static path segments that should never be treated as parameters.
    /// Case-insensitive matching is applied.
    private let staticSegments: Set<String> = [
        // API versioning
        "api", "v1", "v2", "v3", "v4", "v5", "rest", "graphql", "grpc",

        // Access control
        "admin", "auth", "oauth", "oauth2", "sso", "login", "logout",
        "register", "signup", "signin", "signout", "callback", "redirect",
        "public", "private", "internal", "external",

        // Resource types
        "users", "user", "accounts", "account", "profiles", "profile",
        "projects", "project", "organizations", "orgs", "org",
        "teams", "team", "workspaces", "workspace", "spaces", "space",
        "groups", "group", "members", "member", "roles", "role",
        "permissions", "permission",

        // Content types
        "posts", "post", "comments", "comment", "messages", "message",
        "items", "item", "products", "product", "orders", "order",
        "files", "file", "documents", "document", "images", "image",
        "assets", "asset", "media", "uploads", "downloads",

        // Actions
        "search", "query", "filter", "sort", "list", "all", "new", "create",
        "edit", "update", "delete", "remove", "get", "set", "add", "batch",
        "start", "stop", "pause", "resume", "cancel", "retry", "reset",
        "export", "import", "download", "upload", "sync", "refresh",
        "validate", "verify", "confirm", "approve", "reject", "submit",
        "enable", "disable", "activate", "deactivate", "archive", "unarchive",

        // Notifications and events
        "notifications", "notification", "alerts", "alert",
        "events", "event", "webhooks", "webhook", "hooks", "triggers",

        // Settings and configuration
        "settings", "config", "configuration", "preferences", "options",
        "dashboard", "home", "index", "overview", "summary", "stats",

        // System endpoints
        "health", "healthz", "status", "ping", "info", "version", "metrics",
        "debug", "logs", "traces", "audit",

        // Environment
        "sandbox", "dev", "development", "staging", "prod", "production",
        "test", "testing", "qa", "uat", "demo",

        // Documentation
        "docs", "documentation", "help", "support", "faq", "about",
        "terms", "privacy", "legal", "security", "compliance",

        // Realtime
        "realtime", "socket", "websocket", "ws", "stream", "streaming",
        "subscribe", "unsubscribe", "publish", "channel", "channels",

        // Common API patterns
        "me", "self", "current", "latest", "recent", "popular", "featured",
        "count", "total", "aggregate", "bulk", "batch",

        // Authentication tokens (the word, not the value)
        "token", "tokens", "auth-token", "refresh-token", "access-token"
    ]

    // MARK: - Initialization

    private init() {
        var compiledPatterns: [PatternRule] = []

        // UUID: 8-4-4-4-12 hex format (most distinctive, check first)
        // Matches: 550e8400-e29b-41d4-a716-446655440000
        if let regex = try? NSRegularExpression(
            pattern: "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$",
            options: []
        ) {
            compiledPatterns.append(PatternRule(type: .uuid, regex: regex, minLength: 36))
        }

        // SHA256 hash: exactly 64 hex characters
        if let regex = try? NSRegularExpression(pattern: "^[0-9a-fA-F]{64}$", options: []) {
            compiledPatterns.append(PatternRule(type: .hash, regex: regex, minLength: 64))
        }

        // SHA1 hash: exactly 40 hex characters
        if let regex = try? NSRegularExpression(pattern: "^[0-9a-fA-F]{40}$", options: []) {
            compiledPatterns.append(PatternRule(type: .hash, regex: regex, minLength: 40))
        }

        // MD5 hash: exactly 32 hex characters
        if let regex = try? NSRegularExpression(pattern: "^[0-9a-fA-F]{32}$", options: []) {
            compiledPatterns.append(PatternRule(type: .hash, regex: regex, minLength: 32))
        }

        // MongoDB ObjectId: exactly 24 hex characters
        if let regex = try? NSRegularExpression(pattern: "^[0-9a-fA-F]{24}$", options: []) {
            compiledPatterns.append(PatternRule(type: .hash, regex: regex, minLength: 24))
        }

        // JWT token: three base64url segments separated by dots
        // Matches: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U
        if let regex = try? NSRegularExpression(
            pattern: "^[A-Za-z0-9_-]{10,}\\.[A-Za-z0-9_-]{10,}\\.[A-Za-z0-9_-]{10,}$",
            options: []
        ) {
            compiledPatterns.append(PatternRule(type: .token, regex: regex, minLength: 32))
        }

        // Base64/Base64URL token: 20+ characters with base64 charset (without dots)
        // Must contain mix of upper/lower/numbers to avoid matching words
        if let regex = try? NSRegularExpression(
            pattern: "^[A-Za-z0-9_+/=-]{20,}$",
            options: []
        ) {
            compiledPatterns.append(PatternRule(type: .token, regex: regex, minLength: 20))
        }

        // Numeric ID: 3+ digits (avoids version numbers like v1, v2)
        if let regex = try? NSRegularExpression(pattern: "^[0-9]{3,}$", options: []) {
            compiledPatterns.append(PatternRule(type: .numericId, regex: regex, minLength: 3))
        }

        self.patterns = compiledPatterns
    }

    // MARK: - Public Methods

    /// Normalizes a URL path by replacing detected parameters with placeholders.
    ///
    /// - Parameter path: The original path (e.g., "/projects/550e8400-e29b-41d4-a716-446655440000/auth-token")
    /// - Returns: A tuple containing:
    ///   - `normalized`: The normalized path (e.g., "/projects/{uuid}/auth-token")
    ///   - `parameters`: Array of detected parameters with their original values and types
    func normalizePath(_ path: String) -> (
        normalized: String,
        parameters: [(segment: String, type: ParameterType)]
    ) {
        // Handle empty or root path
        guard !path.isEmpty else {
            return ("/", [])
        }

        // Split path into segments, preserving structure
        let segments = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)

        var normalizedSegments: [String] = []
        var detectedParameters: [(String, ParameterType)] = []

        for segment in segments {
            // Skip empty segments
            guard !segment.isEmpty else { continue }

            // Check if it's a known static segment (case-insensitive)
            if staticSegments.contains(segment.lowercased()) {
                normalizedSegments.append(segment)
                continue
            }

            // Try to detect parameter type
            if let paramType = detectParameterType(segment) {
                normalizedSegments.append(paramType.placeholder)
                detectedParameters.append((segment, paramType))
            } else {
                // Keep as literal if no pattern matches
                normalizedSegments.append(segment)
            }
        }

        let normalizedPath = "/" + normalizedSegments.joined(separator: "/")
        return (normalizedPath, detectedParameters)
    }

    /// Detects the parameter type of a single path segment.
    ///
    /// - Parameter segment: A single path segment to analyze
    /// - Returns: The detected parameter type, or nil if it appears to be a literal value
    func detectParameterType(_ segment: String) -> ParameterType? {
        let range = NSRange(segment.startIndex..., in: segment)

        // Check against known patterns in order of specificity
        for rule in patterns {
            // Skip if segment is too short for this pattern
            guard segment.count >= rule.minLength else { continue }

            if rule.regex.firstMatch(in: segment, options: [], range: range) != nil {
                // Additional validation for token type to avoid false positives
                if rule.type == .token && !isLikelyToken(segment) {
                    continue
                }
                return rule.type
            }
        }

        // Fallback: check if it looks dynamic based on heuristics
        if isProbablyDynamic(segment) {
            return .unknown
        }

        return nil
    }

    /// Checks if a segment appears to be a dynamic parameter based on heuristics.
    /// Used as a fallback when no specific pattern matches.
    ///
    /// - Parameter segment: The segment to analyze
    /// - Returns: True if the segment is likely a dynamic value
    func isProbablyDynamic(_ segment: String) -> Bool {
        // Very short segments are usually literals
        guard segment.count > 8 else { return false }

        // Check character composition
        let hasUppercase = segment.contains { $0.isUppercase }
        let hasLowercase = segment.contains { $0.isLowercase }
        let hasNumbers = segment.contains { $0.isNumber }
        let hasSpecialChars = segment.contains { !$0.isLetter && !$0.isNumber && $0 != "-" && $0 != "_" }

        // Mixed case with numbers and special characters often indicates generated values
        if hasNumbers && (hasUppercase && hasLowercase) && segment.count > 12 {
            return true
        }

        // Long segments with only numbers and letters (like base64 without padding)
        if segment.count > 20 && !hasSpecialChars && hasNumbers && (hasUppercase || hasLowercase) {
            return true
        }

        // Very long segments are probably dynamic
        if segment.count > 30 {
            return true
        }

        return false
    }

    // MARK: - Private Helpers

    /// Additional validation for token detection to reduce false positives.
    private func isLikelyToken(_ segment: String) -> Bool {
        // Tokens should have high entropy (mix of character types)
        let uppercaseCount = segment.filter { $0.isUppercase }.count
        let lowercaseCount = segment.filter { $0.isLowercase }.count
        let numberCount = segment.filter { $0.isNumber }.count

        // Should have a mix of character types
        let hasGoodMix = uppercaseCount > 0 && lowercaseCount > 0 && numberCount > 0

        // Shouldn't be a common word pattern
        let looksLikeWord = segment.allSatisfy { $0.isLetter } && segment.count < 20

        return hasGoodMix && !looksLikeWord
    }
}

// MARK: - Path Analysis Utilities

extension PathNormalizer {
    /// Extracts all unique parameter types found in a normalized path.
    ///
    /// - Parameter normalizedPath: A path with parameter placeholders
    /// - Returns: Set of parameter types found in the path
    func extractParameterTypes(from normalizedPath: String) -> Set<ParameterType> {
        var types = Set<ParameterType>()

        for type in ParameterType.allCases where normalizedPath.contains(type.placeholder) {
            types.insert(type)
        }

        return types
    }

    /// Counts the number of dynamic segments in a normalized path.
    ///
    /// - Parameter normalizedPath: A path with parameter placeholders
    /// - Returns: Number of dynamic segments
    func countDynamicSegments(in normalizedPath: String) -> Int {
        let segments = normalizedPath.split(separator: "/", omittingEmptySubsequences: true)
        return segments.filter { segment in
            let seg = String(segment)
            return seg.hasPrefix("{") && seg.hasSuffix("}")
        }.count
    }

    /// Generates a regex pattern that matches concrete paths for a normalized pattern.
    ///
    /// - Parameter normalizedPath: A path with parameter placeholders
    /// - Returns: A regex pattern string, or nil if generation fails
    func generateMatchingPattern(for normalizedPath: String) -> String? {
        var pattern = "^"

        let segments = normalizedPath.split(separator: "/", omittingEmptySubsequences: true)

        for segment in segments {
            pattern += "/"
            let seg = String(segment)

            if seg.hasPrefix("{") && seg.hasSuffix("}") {
                // Dynamic segment - match any non-slash characters
                pattern += "[^/]+"
            } else {
                // Literal segment - escape regex special characters
                pattern += NSRegularExpression.escapedPattern(for: seg)
            }
        }

        pattern += "$"
        return pattern
    }
}
