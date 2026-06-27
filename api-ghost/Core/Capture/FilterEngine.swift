import Foundation

struct FilterDecision: Sendable, Equatable {
    let shouldCapture: Bool

    let reason: String?

    static let capture = FilterDecision(shouldCapture: true, reason: nil)

    static func filter(_ reason: String) -> FilterDecision {
        FilterDecision(shouldCapture: false, reason: reason)
    }
}

/// Pure capture decision over an immutable active rule set — no I/O, no singletons. Build one and ask it.
struct FilterEngine: Sendable {
    let isEnabled: Bool
    let maxResponseSize: Int

    private let domainRules: [FilterRule]
    private let pathRules: [FilterRule]
    private let contentTypeRules: [FilterRule]
    private let customRules: [FilterRule]

    init(
        domainRules: [FilterRule],
        pathRules: [FilterRule],
        contentTypeRules: [FilterRule],
        customRules: [FilterRule] = [],
        isEnabled: Bool = true,
        maxResponseSize: Int = 10 * 1024 * 1024
    ) {
        self.domainRules = domainRules
        self.pathRules = pathRules
        self.contentTypeRules = contentTypeRules
        self.customRules = customRules
        self.isEnabled = isEnabled
        self.maxResponseSize = maxResponseSize
    }

    init(
        categories: [FilterCategory],
        categoryOverrides: [String: Bool] = [:],
        disabledRuleIDs: Set<String> = [],
        customRules: [FilterRule] = [],
        isEnabled: Bool = true,
        maxResponseSize: Int = 10 * 1024 * 1024
    ) {
        let enabledCategories = categories.filter { categoryOverrides[$0.id] ?? $0.isEnabledByDefault }
        let categoryRules = enabledCategories.flatMap(\.rules)
        let active = categoryRules.filter { !disabledRuleIDs.contains($0.id) }

        let domain = active.filter { $0.type == .domainExact || $0.type == .domainWildcard }
        let path = active.filter { $0.type == .pathContains || $0.type == .pathPrefix || $0.type == .pathRegex }
        let content = active.filter { $0.type == .contentType }

        self.init(
            domainRules: domain,
            pathRules: path,
            contentTypeRules: content,
            customRules: customRules,
            isEnabled: isEnabled,
            maxResponseSize: maxResponseSize
        )
    }

    static let empty = FilterEngine(domainRules: [], pathRules: [], contentTypeRules: [])

    var allRules: [FilterRule] {
        domainRules + pathRules + contentTypeRules + customRules
    }
}

// MARK: - Decision

extension FilterEngine {
    func decision(
        host: String?,
        path: String,
        contentType: String? = nil,
        responseSize: Int? = nil
    ) -> FilterDecision {
        guard isEnabled else { return .capture }

        if let host {
            let domain = domainBlocked(host)
            if domain.blocked { return .filter(domain.reason ?? "Domain blocked") }
        }

        let pathCheck = pathBlocked(path)
        if pathCheck.blocked { return .filter(pathCheck.reason ?? "Path blocked") }

        if let contentType {
            let content = contentTypeBlocked(contentType)
            if content.blocked { return .filter(content.reason ?? "Content-Type blocked") }
        }

        if let responseSize {
            let size = responseTooLarge(responseSize)
            if size.blocked { return .filter(size.reason ?? "Response too large") }
        }

        return .capture
    }

    func domainBlocked(_ host: String) -> (blocked: Bool, reason: String?) {
        guard isEnabled else { return (false, nil) }
        for rule in domainRules where rule.isEnabled && rule.matches(host: host) {
            return (true, "Domain blocked: \(rule.pattern)")
        }
        for rule in customRules
        where rule.isEnabled
            && (rule.type == .domainExact || rule.type == .domainWildcard)
            && rule.matches(host: host) {
            return (true, "Custom rule: \(rule.pattern)")
        }
        return (false, nil)
    }

    func pathBlocked(_ path: String) -> (blocked: Bool, reason: String?) {
        guard isEnabled else { return (false, nil) }
        for rule in pathRules where rule.isEnabled && rule.matches(path: path) {
            return (true, "Path blocked: \(rule.pattern)")
        }
        for rule in customRules
        where rule.isEnabled
            && (rule.type == .pathContains || rule.type == .pathPrefix || rule.type == .pathRegex)
            && rule.matches(path: path) {
            return (true, "Custom rule: \(rule.pattern)")
        }
        return (false, nil)
    }

    func contentTypeBlocked(_ contentType: String) -> (blocked: Bool, reason: String?) {
        guard isEnabled else { return (false, nil) }
        let normalized = contentType.split(separator: ";").first.map(String.init) ?? contentType
        for rule in contentTypeRules where rule.isEnabled && rule.matches(contentType: normalized) {
            return (true, "Content-Type blocked: \(rule.pattern)")
        }
        for rule in customRules
        where rule.isEnabled && rule.type == .contentType && rule.matches(contentType: normalized) {
            return (true, "Custom rule: \(rule.pattern)")
        }
        return (false, nil)
    }

    func responseTooLarge(_ size: Int) -> (blocked: Bool, reason: String?) {
        guard isEnabled, size > maxResponseSize else { return (false, nil) }
        let sizeStr = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
        return (true, "Response too large: \(sizeStr)")
    }
}
