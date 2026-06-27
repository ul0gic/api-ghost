//
//  FilterRule.swift
//  api-ghost
//
//  Created for APIGhost project
//

import Foundation

/// Represents a filter rule for determining whether to capture traffic.
struct FilterRule: Identifiable, Codable, Hashable, Sendable {
    // MARK: - Properties

    /// Unique identifier
    let id: String

    /// Whether this rule is currently active
    var isEnabled: Bool

    /// Type of filter matching
    let type: FilterRuleType

    /// Pattern to match against
    let pattern: String

    /// Human-readable description of the rule
    var description: String?

    /// Prebuilt category this rule belongs to; nil for user-added custom rules.
    let categoryID: String?

    /// True for user-added rules, false for prebuilt defaults.
    let isCustom: Bool

    // MARK: - Initialization

    init(
        id: String = UUID().uuidString,
        isEnabled: Bool = true,
        type: FilterRuleType,
        pattern: String,
        description: String? = nil,
        categoryID: String? = nil,
        isCustom: Bool = false
    ) {
        self.id = id
        self.isEnabled = isEnabled
        self.type = type
        self.pattern = pattern
        self.description = description
        self.categoryID = categoryID
        self.isCustom = isCustom
    }

    private enum CodingKeys: String, CodingKey {
        case id, isEnabled, type, pattern, description, categoryID, isCustom
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        type = try container.decode(FilterRuleType.self, forKey: .type)
        pattern = try container.decode(String.self, forKey: .pattern)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        categoryID = try container.decodeIfPresent(String.self, forKey: .categoryID)
        isCustom = try container.decodeIfPresent(Bool.self, forKey: .isCustom) ?? false
    }
}

/// Types of filter rules supported.
enum FilterRuleType: String, Codable, Hashable, Sendable {
    case domainExact = "domain_exact"
    case domainWildcard = "domain_wildcard"
    case pathContains = "path_contains"
    case pathPrefix = "path_prefix"
    case pathRegex = "path_regex"
    case contentType = "content_type"
    case statusCode = "status_code"
}

// MARK: - Filter Matching

extension FilterRule {
    /// Checks if this rule matches the given parameters.
    /// - Parameters:
    ///   - host: The request host/domain
    ///   - path: The request path
    ///   - contentType: The response content type
    ///   - statusCode: The response status code
    /// - Returns: True if the rule matches, false otherwise
    func matches(
        host: String? = nil,
        path: String? = nil,
        contentType: String? = nil,
        statusCode: Int? = nil
    ) -> Bool {
        guard isEnabled else { return false }

        switch type {
        case .domainExact:
            return host == pattern
        case .domainWildcard:
            return matchesDomainWildcard(host: host)
        case .pathContains:
            return path?.contains(pattern) ?? false
        case .pathPrefix:
            return path?.hasPrefix(pattern) ?? false
        case .pathRegex:
            return matchesPathRegex(path: path)
        case .contentType:
            return matchesContentType(contentType)
        case .statusCode:
            return matchesStatusCode(statusCode)
        }
    }

    private func matchesDomainWildcard(host: String?) -> Bool {
        guard let host = host else { return false }
        if pattern.hasPrefix("*.") {
            let suffix = String(pattern.dropFirst(2))
            return host.hasSuffix(suffix) || host == suffix
        }
        return host == pattern
    }

    private func matchesPathRegex(path: String?) -> Bool {
        guard let path = path else { return false }
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(path.startIndex..., in: path)
        return regex.firstMatch(in: path, range: range) != nil
    }

    private func matchesContentType(_ contentType: String?) -> Bool {
        guard let contentType = contentType else { return false }
        if pattern.hasSuffix("/*") {
            let prefix = String(pattern.dropLast(2))
            return contentType.hasPrefix(prefix)
        }
        return contentType == pattern || contentType.hasPrefix(pattern + ";")
    }

    private func matchesStatusCode(_ statusCode: Int?) -> Bool {
        guard let statusCode = statusCode, let patternCode = Int(pattern) else { return false }
        return statusCode == patternCode
    }
}

// MARK: - Default Rules

extension FilterRule {
    /// Last-resort fallback used only when the bundled blocklist resource is missing.
    /// Social domains are intentionally excluded — they are never blocked by default.
    static var defaultDomainBlocklist: [FilterRule] {
        let domains = [
            "*.google-analytics.com",
            "*.googletagmanager.com",
            "*.doubleclick.net",
            "*.hotjar.com",
            "*.mixpanel.com",
            "*.segment.io",
            "*.segment.com",
            "*.amplitude.com",
            "*.intercom.io",
            "*.crisp.chat",
            "*.zendesk.com",
            "*.sentry.io",
            "*.newrelic.com",
            "*.nr-data.net",
            "*.datadoghq.com",
            "*.bugsnag.com",
            "*.rollbar.com"
        ]

        return domains.map { domain in
            FilterRule(
                type: .domainWildcard,
                pattern: domain,
                description: "Analytics/tracking domain",
                categoryID: FilterCategory.fallbackCategoryID
            )
        }
    }

    /// Default path patterns for tracking endpoints.
    static var defaultPathPatterns: [FilterRule] {
        let patterns = [
            "/collect",
            "/pixel",
            "/beacon",
            "/analytics",
            "/tracking",
            "/__utm",
            "/log_event"
        ]

        return patterns.map { pattern in
            FilterRule(
                type: .pathContains,
                pattern: pattern,
                description: "Tracking endpoint",
                categoryID: FilterCategory.fallbackCategoryID
            )
        }
    }

    /// Default content type filters for non-API content.
    static var defaultContentTypeFilters: [FilterRule] {
        let types = [
            "image/*",
            "font/*",
            "video/*",
            "audio/*"
        ]

        return types.map { type in
            FilterRule(
                type: .contentType,
                pattern: type,
                description: "Non-API content type",
                categoryID: FilterCategory.fallbackCategoryID
            )
        }
    }

    /// All default filter rules combined.
    static var allDefaults: [FilterRule] {
        defaultDomainBlocklist + defaultPathPatterns + defaultContentTypeFilters
    }
}
