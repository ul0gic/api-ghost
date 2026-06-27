import Foundation

final class NoiseFilter: @unchecked Sendable {
    // MARK: - Singleton

    static let shared = NoiseFilter()

    // MARK: - Properties

    private var domainRules: [FilterRule] = []
    private var pathRules: [FilterRule] = []
    private var contentTypeRules: [FilterRule] = []
    private var customRules: [FilterRule] = []

    private(set) var categories: [FilterCategory] = []

    private let rulesQueue = DispatchQueue(label: "com.corelift.apighost.noisefilter", attributes: .concurrent)

    var isEnabled: Bool = true
    var maxResponseSize: Int = 10 * 1024 * 1024

    private init() {
        loadDefaultBlocklist()
        loadCustomRulesFromPreferences()
        loadFilteringStateFromPreferences()
    }

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

    private func loadFilteringStateFromPreferences() {
        isEnabled = Preferences.shared.filteringEnabled
    }

    // MARK: - Loading

    private func loadDefaultBlocklist() {
        guard let url = Bundle.main.url(forResource: "DefaultBlocklist", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let blocklist = try? JSONDecoder().decode(BlocklistFile.self, from: data) else {
            loadHardcodedDefaults()
            return
        }

        categories = blocklist.categories.map { $0.toFilterCategory() }
        activateEnabledCategories()
    }

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
    func isDomainBlocked(_ host: String) -> (blocked: Bool, reason: String?) {
        guard isEnabled else { return (false, nil) }

        for rule in domainRules where rule.isEnabled {
            if rule.matches(host: host) {
                return (true, "Domain blocked: \(rule.pattern)")
            }
        }

        for rule in customRules where rule.isEnabled && (rule.type == .domainExact || rule.type == .domainWildcard) {
            if rule.matches(host: host) {
                return (true, "Custom rule: \(rule.pattern)")
            }
        }

        return (false, nil)
    }

    func addDomainRule(_ pattern: String, isWildcard: Bool = false) {
        let rule = FilterRule(
            type: isWildcard ? .domainWildcard : .domainExact,
            pattern: pattern,
            description: "User added",
            isCustom: true
        )
        customRules.append(rule)
    }

    func removeDomainRule(_ pattern: String) {
        customRules.removeAll { $0.pattern == pattern && ($0.type == .domainExact || $0.type == .domainWildcard) }
    }
}

extension NoiseFilter {
    func isPathBlocked(_ path: String) -> (blocked: Bool, reason: String?) {
        guard isEnabled else { return (false, nil) }

        for rule in pathRules where rule.isEnabled {
            if rule.matches(path: path) {
                return (true, "Path blocked: \(rule.pattern)")
            }
        }

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

    func removePathRule(_ pattern: String) {
        customRules.removeAll {
            $0.pattern == pattern
                && ($0.type == .pathContains || $0.type == .pathPrefix || $0.type == .pathRegex)
        }
    }
}

// MARK: - Content-Type Matching

extension NoiseFilter {
    func isContentTypeBlocked(_ contentType: String?) -> (blocked: Bool, reason: String?) {
        guard isEnabled, let contentType = contentType else { return (false, nil) }

        let normalizedType = contentType.split(separator: ";").first.map(String.init) ?? contentType

        for rule in contentTypeRules where rule.isEnabled {
            if rule.matches(contentType: normalizedType) {
                return (true, "Content-Type blocked: \(rule.pattern)")
            }
        }

        for rule in customRules where rule.isEnabled && rule.type == .contentType {
            if rule.matches(contentType: normalizedType) {
                return (true, "Custom rule: \(rule.pattern)")
            }
        }

        return (false, nil)
    }

    func isResponseTooLarge(_ size: Int) -> (blocked: Bool, reason: String?) {
        guard isEnabled else { return (false, nil) }

        if size > maxResponseSize {
            let sizeStr = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
            return (true, "Response too large: \(sizeStr)")
        }

        return (false, nil)
    }

    func addContentTypeRule(_ pattern: String) {
        let rule = FilterRule(
            type: .contentType,
            pattern: pattern,
            description: "User added",
            isCustom: true
        )
        customRules.append(rule)
    }

    func removeContentTypeRule(_ pattern: String) {
        customRules.removeAll { $0.pattern == pattern && $0.type == .contentType }
    }
}

// MARK: - Main Filter Method

extension NoiseFilter {
    struct FilterResult {
        let shouldCapture: Bool

        let reason: String?

        static let capture = FilterResult(shouldCapture: true, reason: nil)

        static func filter(_ reason: String) -> FilterResult {
            FilterResult(shouldCapture: false, reason: reason)
        }
    }

    func shouldCapture(
        url: URL,
        contentType: String? = nil,
        responseSize: Int? = nil
    ) -> FilterResult {
        guard isEnabled else { return .capture }

        if let host = url.host {
            let domainCheck = isDomainBlocked(host)
            if domainCheck.blocked {
                return .filter(domainCheck.reason ?? "Domain blocked")
            }
        }

        let pathCheck = isPathBlocked(url.path)
        if pathCheck.blocked {
            return .filter(pathCheck.reason ?? "Path blocked")
        }

        if let contentType = contentType {
            let contentTypeCheck = isContentTypeBlocked(contentType)
            if contentTypeCheck.blocked {
                return .filter(contentTypeCheck.reason ?? "Content-Type blocked")
            }
        }

        if let size = responseSize {
            let sizeCheck = isResponseTooLarge(size)
            if sizeCheck.blocked {
                return .filter(sizeCheck.reason ?? "Response too large")
            }
        }

        return .capture
    }

    func shouldCapture(
        host: String,
        path: String,
        contentType: String? = nil,
        responseSize: Int? = nil
    ) -> FilterResult {
        guard isEnabled else { return .capture }

        let domainCheck = isDomainBlocked(host)
        if domainCheck.blocked {
            return .filter(domainCheck.reason ?? "Domain blocked")
        }

        let pathCheck = isPathBlocked(path)
        if pathCheck.blocked {
            return .filter(pathCheck.reason ?? "Path blocked")
        }

        if let contentType = contentType {
            let contentTypeCheck = isContentTypeBlocked(contentType)
            if contentTypeCheck.blocked {
                return .filter(contentTypeCheck.reason ?? "Content-Type blocked")
            }
        }

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
    func resetToDefaults() {
        customRules.removeAll()
        loadDefaultBlocklist()
    }

    var allRules: [FilterRule] {
        domainRules + pathRules + contentTypeRules + customRules
    }

    var customRulesList: [FilterRule] {
        customRules
    }
}
