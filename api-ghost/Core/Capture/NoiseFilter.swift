//
//  NoiseFilter.swift
//  api-ghost
//
//  Created for APIGhost project
//

import Foundation

/// Filters network traffic to reduce noise from analytics, tracking, and non-API content.
final class NoiseFilter: @unchecked Sendable {
    // MARK: - Singleton

    static let shared = NoiseFilter()

    // MARK: - Properties

    private var domainRules: [FilterRule] = []
    private var pathRules: [FilterRule] = []
    private var contentTypeRules: [FilterRule] = []
    private var customRules: [FilterRule] = []

    /// All prebuilt categories, including ones disabled by default (e.g. Social).
    /// The active rule sets above are derived from the enabled subset only.
    private(set) var categories: [FilterCategory] = []

    /// Queue for thread-safe access to rules
    private let rulesQueue = DispatchQueue(label: "com.corelift.apighost.noisefilter", attributes: .concurrent)

    /// Whether the noise filter is enabled
    var isEnabled: Bool = true
    /// Maximum response size in bytes (10MB default)
    var maxResponseSize: Int = 10 * 1024 * 1024

    private init() {
        loadDefaultBlocklist()
        loadCustomRulesFromPreferences()
        loadFilteringStateFromPreferences()
    }

    /// Loads custom domain and path rules from Preferences (UserDefaults).
    private func loadCustomRulesFromPreferences() {
        let customDomains = Preferences.shared.customBlockedDomains
        let customPaths = Preferences.shared.customBlockedPaths

        for domain in customDomains {
            let isWildcard = domain.hasPrefix("*.")
            addDomainRule(domain, isWildcard: isWildcard)
        }

        for path in customPaths {
            addPathRule(path)
        }
    }

    /// Loads the filtering enabled state from Preferences.
    /// Called on init to restore user's capture-all preference between app restarts.
    private func loadFilteringStateFromPreferences() {
        isEnabled = Preferences.shared.filteringEnabled
    }

    // MARK: - Loading

    private func loadDefaultBlocklist() {
        guard let url = Bundle.main.url(forResource: "DefaultBlocklist", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let blocklist = try? JSONDecoder().decode(BlocklistFile.self, from: data) else {
            // Fall back to hardcoded defaults
            loadHardcodedDefaults()
            return
        }

        categories = blocklist.categories.map { $0.toFilterCategory() }
        activateEnabledCategories()
    }

    /// Populates the active rule sets from categories enabled by default only.
    /// Rules from default-off categories (e.g. Social) stay parsed in `categories` but inactive.
    private func activateEnabledCategories() {
        let activeRules = categories.filter(\.isEnabledByDefault).flatMap(\.rules)
        domainRules = activeRules.filter { $0.type == .domainExact || $0.type == .domainWildcard }
        pathRules = activeRules.filter { $0.type == .pathContains || $0.type == .pathPrefix || $0.type == .pathRegex }
        contentTypeRules = activeRules.filter { $0.type == .contentType }
    }

    private func loadHardcodedDefaults() {
        domainRules = FilterRule.defaultDomainBlocklist
        pathRules = FilterRule.defaultPathPatterns
        contentTypeRules = FilterRule.defaultContentTypeFilters
        categories = [
            FilterCategory(
                id: FilterCategory.fallbackCategoryID,
                name: "Default Filters",
                description: "Built-in fallback used when the bundled blocklist is unavailable.",
                isEnabledByDefault: true,
                rules: domainRules + pathRules + contentTypeRules
            )
        ]
    }
}

extension NoiseFilter {
    /// Checks if a domain/host is blocked by the filter rules.
    func isDomainBlocked(_ host: String) -> (blocked: Bool, reason: String?) {
        guard isEnabled else { return (false, nil) }

        for rule in domainRules where rule.isEnabled {
            if rule.matches(host: host) {
                return (true, "Domain blocked: \(rule.pattern)")
            }
        }

        // Check custom rules
        for rule in customRules where rule.isEnabled && (rule.type == .domainExact || rule.type == .domainWildcard) {
            if rule.matches(host: host) {
                return (true, "Custom rule: \(rule.pattern)")
            }
        }

        return (false, nil)
    }

    /// Adds a domain rule to the custom rules list.
    /// - Parameters:
    ///   - pattern: The domain pattern to block
    ///   - isWildcard: Whether the pattern is a wildcard (e.g., *.example.com)
    func addDomainRule(_ pattern: String, isWildcard: Bool = false) {
        let rule = FilterRule(
            type: isWildcard ? .domainWildcard : .domainExact,
            pattern: pattern,
            description: "User added",
            isCustom: true
        )
        customRules.append(rule)
    }

    /// Removes a domain rule from the custom rules list.
    /// - Parameter pattern: The domain pattern to remove
    func removeDomainRule(_ pattern: String) {
        customRules.removeAll { $0.pattern == pattern && ($0.type == .domainExact || $0.type == .domainWildcard) }
    }
}

extension NoiseFilter {
    /// Checks if a path is blocked by the filter rules.
    func isPathBlocked(_ path: String) -> (blocked: Bool, reason: String?) {
        guard isEnabled else { return (false, nil) }

        for rule in pathRules where rule.isEnabled {
            if rule.matches(path: path) {
                return (true, "Path blocked: \(rule.pattern)")
            }
        }

        // Check custom rules
        for rule in customRules where rule.isEnabled {
            switch rule.type {
            case .pathContains, .pathPrefix, .pathRegex:
                if rule.matches(path: path) {
                    return (true, "Custom rule: \(rule.pattern)")
                }
            default:
                continue
            }
        }

        return (false, nil)
    }

    /// Adds a path rule to the custom rules list.
    /// - Parameters:
    ///   - pattern: The path pattern to block
    ///   - type: The type of path matching (defaults to pathContains)
    func addPathRule(_ pattern: String, type: FilterRuleType = .pathContains) {
        guard type == .pathContains || type == .pathPrefix || type == .pathRegex else { return }
        let rule = FilterRule(
            type: type,
            pattern: pattern,
            description: "User added",
            isCustom: true
        )
        customRules.append(rule)
    }

    /// Removes a path rule from the custom rules list.
    /// - Parameter pattern: The path pattern to remove
    func removePathRule(_ pattern: String) {
        customRules.removeAll {
            $0.pattern == pattern
                && ($0.type == .pathContains || $0.type == .pathPrefix || $0.type == .pathRegex)
        }
    }
}

// MARK: - Content-Type Matching

extension NoiseFilter {
    /// Checks if a content type is blocked by the filter rules.
    /// - Parameter contentType: The Content-Type header value to check
    /// - Returns: A tuple indicating if blocked and the reason
    func isContentTypeBlocked(_ contentType: String?) -> (blocked: Bool, reason: String?) {
        guard isEnabled, let contentType = contentType else { return (false, nil) }

        // Normalize content type (remove charset, etc.)
        let normalizedType = contentType.split(separator: ";").first.map(String.init) ?? contentType

        for rule in contentTypeRules where rule.isEnabled {
            if rule.matches(contentType: normalizedType) {
                return (true, "Content-Type blocked: \(rule.pattern)")
            }
        }

        // Check custom rules
        for rule in customRules where rule.isEnabled && rule.type == .contentType {
            if rule.matches(contentType: normalizedType) {
                return (true, "Custom rule: \(rule.pattern)")
            }
        }

        return (false, nil)
    }

    /// Checks if a response is too large to capture.
    /// - Parameter size: The response size in bytes
    /// - Returns: A tuple indicating if blocked and the reason
    func isResponseTooLarge(_ size: Int) -> (blocked: Bool, reason: String?) {
        guard isEnabled else { return (false, nil) }

        if size > maxResponseSize {
            let sizeStr = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
            return (true, "Response too large: \(sizeStr)")
        }

        return (false, nil)
    }

    /// Adds a content type rule to the custom rules list.
    /// - Parameter pattern: The content type pattern to block (e.g., "image/*")
    func addContentTypeRule(_ pattern: String) {
        let rule = FilterRule(
            type: .contentType,
            pattern: pattern,
            description: "User added",
            isCustom: true
        )
        customRules.append(rule)
    }

    /// Removes a content type rule from the custom rules list.
    /// - Parameter pattern: The content type pattern to remove
    func removeContentTypeRule(_ pattern: String) {
        customRules.removeAll { $0.pattern == pattern && $0.type == .contentType }
    }
}

// MARK: - Main Filter Method

extension NoiseFilter {
    /// Result of a filter check
    struct FilterResult {
        /// Whether the traffic should be captured
        let shouldCapture: Bool

        /// The reason for filtering, if applicable
        let reason: String?

        /// A result indicating the traffic should be captured
        static let capture = FilterResult(shouldCapture: true, reason: nil)

        /// Creates a result indicating the traffic should be filtered out
        /// - Parameter reason: The reason for filtering
        /// - Returns: A FilterResult indicating filtering
        static func filter(_ reason: String) -> FilterResult {
            FilterResult(shouldCapture: false, reason: reason)
        }
    }

    /// Determines whether traffic should be captured based on URL and optional parameters.
    /// - Parameters:
    ///   - url: The URL of the request
    ///   - contentType: Optional Content-Type header value
    ///   - responseSize: Optional response size in bytes
    /// - Returns: A FilterResult indicating whether to capture or filter
    func shouldCapture(
        url: URL,
        contentType: String? = nil,
        responseSize: Int? = nil
    ) -> FilterResult {
        guard isEnabled else { return .capture }

        // Check domain
        if let host = url.host {
            let domainCheck = isDomainBlocked(host)
            if domainCheck.blocked {
                return .filter(domainCheck.reason ?? "Domain blocked")
            }
        }

        // Check path
        let pathCheck = isPathBlocked(url.path)
        if pathCheck.blocked {
            return .filter(pathCheck.reason ?? "Path blocked")
        }

        // Check content type
        if let contentType = contentType {
            let contentTypeCheck = isContentTypeBlocked(contentType)
            if contentTypeCheck.blocked {
                return .filter(contentTypeCheck.reason ?? "Content-Type blocked")
            }
        }

        // Check response size
        if let size = responseSize {
            let sizeCheck = isResponseTooLarge(size)
            if sizeCheck.blocked {
                return .filter(sizeCheck.reason ?? "Response too large")
            }
        }

        return .capture
    }

    /// Determines whether traffic should be captured based on host, path, and optional parameters.
    /// - Parameters:
    ///   - host: The host/domain of the request
    ///   - path: The path of the request
    ///   - contentType: Optional Content-Type header value
    ///   - responseSize: Optional response size in bytes
    /// - Returns: A FilterResult indicating whether to capture or filter
    func shouldCapture(
        host: String,
        path: String,
        contentType: String? = nil,
        responseSize: Int? = nil
    ) -> FilterResult {
        guard isEnabled else { return .capture }

        // Check domain
        let domainCheck = isDomainBlocked(host)
        if domainCheck.blocked {
            return .filter(domainCheck.reason ?? "Domain blocked")
        }

        // Check path
        let pathCheck = isPathBlocked(path)
        if pathCheck.blocked {
            return .filter(pathCheck.reason ?? "Path blocked")
        }

        // Check content type
        if let contentType = contentType {
            let contentTypeCheck = isContentTypeBlocked(contentType)
            if contentTypeCheck.blocked {
                return .filter(contentTypeCheck.reason ?? "Content-Type blocked")
            }
        }

        // Check response size
        if let size = responseSize {
            let sizeCheck = isResponseTooLarge(size)
            if sizeCheck.blocked {
                return .filter(sizeCheck.reason ?? "Response too large")
            }
        }

        return .capture
    }
}

// MARK: - Configuration

extension NoiseFilter {
    /// Resets all rules to the default blocklist.
    func resetToDefaults() {
        customRules.removeAll()
        loadDefaultBlocklist()
    }

    /// All rules currently active (default + custom).
    var allRules: [FilterRule] {
        domainRules + pathRules + contentTypeRules + customRules
    }

    /// The list of user-added custom rules.
    var customRulesList: [FilterRule] {
        customRules
    }
}
