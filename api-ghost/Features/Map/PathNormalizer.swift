import Foundation

struct PatternRule {
    let type: ParameterType
    let regex: NSRegularExpression
    let minLength: Int
}

final class PathNormalizer: @unchecked Sendable {
    // MARK: - Singleton

    static let shared = PathNormalizer()

    // MARK: - Pattern Definitions

    private let patterns: [PatternRule]

    private let staticSegments: Set<String> = [
        "api", "v1", "v2", "v3", "v4", "v5", "rest", "graphql", "grpc",

        "admin", "auth", "oauth", "oauth2", "sso", "login", "logout",
        "register", "signup", "signin", "signout", "callback", "redirect",
        "public", "private", "internal", "external",

        "users", "user", "accounts", "account", "profiles", "profile",
        "projects", "project", "organizations", "orgs", "org",
        "teams", "team", "workspaces", "workspace", "spaces", "space",
        "groups", "group", "members", "member", "roles", "role",
        "permissions", "permission",

        "posts", "post", "comments", "comment", "messages", "message",
        "items", "item", "products", "product", "orders", "order",
        "files", "file", "documents", "document", "images", "image",
        "assets", "asset", "media", "uploads", "downloads",

        "search", "query", "filter", "sort", "list", "all", "new", "create",
        "edit", "update", "delete", "remove", "get", "set", "add", "batch",
        "start", "stop", "pause", "resume", "cancel", "retry", "reset",
        "export", "import", "download", "upload", "sync", "refresh",
        "validate", "verify", "confirm", "approve", "reject", "submit",
        "enable", "disable", "activate", "deactivate", "archive", "unarchive",

        "notifications", "notification", "alerts", "alert",
        "events", "event", "webhooks", "webhook", "hooks", "triggers",

        "settings", "config", "configuration", "preferences", "options",
        "dashboard", "home", "index", "overview", "summary", "stats",

        "health", "healthz", "status", "ping", "info", "version", "metrics",
        "debug", "logs", "traces", "audit",

        "sandbox", "dev", "development", "staging", "prod", "production",
        "test", "testing", "qa", "uat", "demo",

        "docs", "documentation", "help", "support", "faq", "about",
        "terms", "privacy", "legal", "security", "compliance",

        "realtime", "socket", "websocket", "ws", "stream", "streaming",
        "subscribe", "unsubscribe", "publish", "channel", "channels",

        "me", "self", "current", "latest", "recent", "popular", "featured",
        "count", "total", "aggregate", "bulk", "batch",

        "token", "tokens", "auth-token", "refresh-token", "access-token"
    ]

    // MARK: - Initialization

    private init() {
        var compiledPatterns: [PatternRule] = []

        if let regex = try? NSRegularExpression(
            pattern: "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$",
            options: []
        ) {
            compiledPatterns.append(PatternRule(type: .uuid, regex: regex, minLength: 36))
        }

        if let regex = try? NSRegularExpression(pattern: "^[0-9a-fA-F]{64}$", options: []) {
            compiledPatterns.append(PatternRule(type: .hash, regex: regex, minLength: 64))
        }

        if let regex = try? NSRegularExpression(pattern: "^[0-9a-fA-F]{40}$", options: []) {
            compiledPatterns.append(PatternRule(type: .hash, regex: regex, minLength: 40))
        }

        if let regex = try? NSRegularExpression(pattern: "^[0-9a-fA-F]{32}$", options: []) {
            compiledPatterns.append(PatternRule(type: .hash, regex: regex, minLength: 32))
        }

        if let regex = try? NSRegularExpression(pattern: "^[0-9a-fA-F]{24}$", options: []) {
            compiledPatterns.append(PatternRule(type: .hash, regex: regex, minLength: 24))
        }

        if let regex = try? NSRegularExpression(
            pattern: "^[A-Za-z0-9_-]{10,}\\.[A-Za-z0-9_-]{10,}\\.[A-Za-z0-9_-]{10,}$",
            options: []
        ) {
            compiledPatterns.append(PatternRule(type: .token, regex: regex, minLength: 32))
        }

        if let regex = try? NSRegularExpression(
            pattern: "^[A-Za-z0-9_+/=-]{20,}$",
            options: []
        ) {
            compiledPatterns.append(PatternRule(type: .token, regex: regex, minLength: 20))
        }

        if let regex = try? NSRegularExpression(pattern: "^[0-9]{3,}$", options: []) {
            compiledPatterns.append(PatternRule(type: .numericId, regex: regex, minLength: 3))
        }

        self.patterns = compiledPatterns
    }

    // MARK: - Public Methods

    func normalizePath(_ path: String) -> (
        normalized: String,
        parameters: [(segment: String, type: ParameterType)]
    ) {
        guard !path.isEmpty else {
            return ("/", [])
        }

        let segments = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)

        var normalizedSegments: [String] = []
        var detectedParameters: [(String, ParameterType)] = []

        for segment in segments {
            guard !segment.isEmpty else { continue }

            if staticSegments.contains(segment.lowercased()) {
                normalizedSegments.append(segment)
                continue
            }

            if let paramType = detectParameterType(segment) {
                normalizedSegments.append(paramType.placeholder)
                detectedParameters.append((segment, paramType))
            } else {
                normalizedSegments.append(segment)
            }
        }

        let normalizedPath = "/" + normalizedSegments.joined(separator: "/")
        return (normalizedPath, detectedParameters)
    }

    func detectParameterType(_ segment: String) -> ParameterType? {
        let range = NSRange(segment.startIndex..., in: segment)

        for rule in patterns {
            guard segment.count >= rule.minLength else { continue }

            if rule.regex.firstMatch(in: segment, options: [], range: range) != nil {
                if rule.type == .token && !isLikelyToken(segment) {
                    continue
                }
                return rule.type
            }
        }

        if isProbablyDynamic(segment) {
            return .unknown
        }

        return nil
    }

    func isProbablyDynamic(_ segment: String) -> Bool {
        guard segment.count > 8 else { return false }

        let hasUppercase = segment.contains { $0.isUppercase }
        let hasLowercase = segment.contains { $0.isLowercase }
        let hasNumbers = segment.contains { $0.isNumber }
        let hasSpecialChars = segment.contains { !$0.isLetter && !$0.isNumber && $0 != "-" && $0 != "_" }

        if hasNumbers && (hasUppercase && hasLowercase) && segment.count > 12 {
            return true
        }

        if segment.count > 20 && !hasSpecialChars && hasNumbers && (hasUppercase || hasLowercase) {
            return true
        }

        if segment.count > 30 {
            return true
        }

        return false
    }

    // MARK: - Private Helpers

    private func isLikelyToken(_ segment: String) -> Bool {
        let uppercaseCount = segment.filter { $0.isUppercase }.count
        let lowercaseCount = segment.filter { $0.isLowercase }.count
        let numberCount = segment.filter { $0.isNumber }.count

        let hasGoodMix = uppercaseCount > 0 && lowercaseCount > 0 && numberCount > 0

        let looksLikeWord = segment.allSatisfy { $0.isLetter } && segment.count < 20

        return hasGoodMix && !looksLikeWord
    }
}

// MARK: - Domain Analysis

extension PathNormalizer {
    private static let multiPartSuffixes: Set<String> = [
        "co.uk", "org.uk", "gov.uk", "ac.uk",
        "com.au", "co.jp", "co.nz", "com.br"
    ]

    /// Pragmatic eTLD+1 — last two DNS labels, or three for a known multi-part public suffix.
    static func registrableDomain(_ host: String) -> String {
        let hostOnly = host.lowercased()
            .split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init) ?? host.lowercased()

        let labels = hostOnly.split(separator: ".", omittingEmptySubsequences: true).map(String.init)
        guard labels.count > 2 else { return hostOnly }

        let lastTwo = labels.suffix(2).joined(separator: ".")
        if multiPartSuffixes.contains(lastTwo) {
            return labels.suffix(3).joined(separator: ".")
        }
        return lastTwo
    }

    /// Best-effort third-party label from host keywords; nil when unrecognized.
    static func thirdPartyCategory(for host: String) -> String? {
        let lower = host.lowercased()
        let rules: [(needles: [String], label: String)] = [
            (["cdn", "cloudfront", "akamai", "fastly", "jsdelivr", "unpkg"], "CDN"),
            (["analytics", "telemetry", "segment", "mixpanel", "amplitude", "ga.", "gtm", "doubleclick"],
             "Analytics / Telemetry"),
            (["sentry", "bugsnag", "rollbar", "errors", "crash", "datadog", "newrelic"],
             "Error / Session Tracking"),
            (["consent", "cookiebot", "onetrust", "cmp", "privacy"], "Consent / CMP"),
            (["ads", "adservice", "adsystem", "adnxs", "taboola", "outbrain"], "Advertising"),
            (["fonts", "gstatic", "typekit"], "Fonts / Assets")
        ]
        for rule in rules where rule.needles.contains(where: { lower.contains($0) }) {
            return rule.label
        }
        return nil
    }
}

// MARK: - Path Analysis Utilities

extension PathNormalizer {
    func extractParameterTypes(from normalizedPath: String) -> Set<ParameterType> {
        var types = Set<ParameterType>()

        for type in ParameterType.allCases where normalizedPath.contains(type.placeholder) {
            types.insert(type)
        }

        return types
    }

    func countDynamicSegments(in normalizedPath: String) -> Int {
        let segments = normalizedPath.split(separator: "/", omittingEmptySubsequences: true)
        return segments.filter { segment in
            let seg = String(segment)
            return seg.hasPrefix("{") && seg.hasSuffix("}")
        }.count
    }

    func generateMatchingPattern(for normalizedPath: String) -> String? {
        var pattern = "^"

        let segments = normalizedPath.split(separator: "/", omittingEmptySubsequences: true)

        for segment in segments {
            pattern += "/"
            let seg = String(segment)

            if seg.hasPrefix("{") && seg.hasSuffix("}") {
                pattern += "[^/]+"
            } else {
                pattern += NSRegularExpression.escapedPattern(for: seg)
            }
        }

        pattern += "$"
        return pattern
    }
}
