import Foundation

final class NoiseFilter: @unchecked Sendable {
    // MARK: - Singleton

    static let shared = NoiseFilter()

    typealias FilterResult = FilterDecision

    // MARK: - Guarded State

    private struct State {
        var categories: [FilterCategory] = []
        var categoryOverrides: [String: Bool] = [:]
        var disabledRuleIDs: Set<String> = []
        var customRules: [FilterRule] = []
        var isEnabled = true
        var maxResponseSize = 10 * 1024 * 1024
        var engine = FilterEngine.empty

        mutating func rebuildEngine() {
            engine = FilterEngine(
                categories: categories,
                categoryOverrides: categoryOverrides,
                disabledRuleIDs: disabledRuleIDs,
                customRules: customRules,
                isEnabled: isEnabled,
                maxResponseSize: maxResponseSize
            )
        }
    }

    private let lock = NSLock()
    private var state = State()
    private var changeObserver: (any NSObjectProtocol)?

    // MARK: - Initialization

    private init() {
        state.categories = Self.loadBlocklist()
        state.customRules = Self.loadCustomRules()
        state.isEnabled = Preferences.shared.filteringEnabled
        state.categoryOverrides = Self.loadCategoryOverrides()
        state.disabledRuleIDs = Self.loadDisabledRuleIDs()
        state.rebuildEngine()

        changeObserver = NotificationCenter.default.addObserver(
            forName: FilterPersistence.rulesDidChange,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor in self?.reloadFilterState() }
        }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

// MARK: - Public Accessors

extension NoiseFilter {
    var isEnabled: Bool {
        get { withLock { state.isEnabled } }
        set { withLock { state.isEnabled = newValue; state.rebuildEngine() } }
    }

    var maxResponseSize: Int {
        get { withLock { state.maxResponseSize } }
        set { withLock { state.maxResponseSize = newValue; state.rebuildEngine() } }
    }

    var categories: [FilterCategory] { withLock { state.categories } }

    var allRules: [FilterRule] { withLock { state.engine.allRules } }

    var customRulesList: [FilterRule] { withLock { state.customRules } }

    /// The current active rule set as a pure value — snapshot it to assert capture decisions without the singleton.
    var currentEngine: FilterEngine { withLock { state.engine } }
}

// MARK: - Category / Rule Toggling (consumes the UI-owned persistence contract)

extension NoiseFilter {
    func reloadFilterState() {
        let overrides = Self.loadCategoryOverrides()
        let disabled = Self.loadDisabledRuleIDs()
        withLock {
            state.categoryOverrides = overrides
            state.disabledRuleIDs = disabled
            state.rebuildEngine()
        }
    }

    func isCategoryEnabled(_ id: String) -> Bool {
        withLock {
            guard let category = state.categories.first(where: { $0.id == id }) else {
                return state.categoryOverrides[id] ?? false
            }
            return state.categoryOverrides[category.id] ?? category.isEnabledByDefault
        }
    }
}

// MARK: - Decision (delegates to the pure engine)

extension NoiseFilter {
    func shouldCapture(
        url: URL,
        contentType: String? = nil,
        responseSize: Int? = nil
    ) -> FilterResult {
        currentEngine.decision(host: url.host, path: url.path, contentType: contentType, responseSize: responseSize)
    }

    func shouldCapture(
        host: String,
        path: String,
        contentType: String? = nil,
        responseSize: Int? = nil
    ) -> FilterResult {
        currentEngine.decision(host: host, path: path, contentType: contentType, responseSize: responseSize)
    }

    func isDomainBlocked(_ host: String) -> (blocked: Bool, reason: String?) {
        currentEngine.domainBlocked(host)
    }

    func isPathBlocked(_ path: String) -> (blocked: Bool, reason: String?) {
        currentEngine.pathBlocked(path)
    }

    func isContentTypeBlocked(_ contentType: String?) -> (blocked: Bool, reason: String?) {
        guard let contentType else { return (false, nil) }
        return currentEngine.contentTypeBlocked(contentType)
    }

    func isResponseTooLarge(_ size: Int) -> (blocked: Bool, reason: String?) {
        currentEngine.responseTooLarge(size)
    }
}

// MARK: - Custom Rules

extension NoiseFilter {
    func addDomainRule(_ pattern: String, isWildcard: Bool = false) {
        let rule = FilterRule(
            type: isWildcard ? .domainWildcard : .domainExact,
            pattern: pattern,
            description: "User added",
            isCustom: true
        )
        withLock { state.customRules.append(rule); state.rebuildEngine() }
    }

    func removeDomainRule(_ pattern: String) {
        withLock {
            state.customRules.removeAll {
                $0.pattern == pattern && ($0.type == .domainExact || $0.type == .domainWildcard)
            }
            state.rebuildEngine()
        }
    }

    func addPathRule(_ pattern: String, type: FilterRuleType = .pathContains) {
        guard type == .pathContains || type == .pathPrefix || type == .pathRegex else { return }
        let rule = FilterRule(type: type, pattern: pattern, description: "User added", isCustom: true)
        withLock { state.customRules.append(rule); state.rebuildEngine() }
    }

    func removePathRule(_ pattern: String) {
        withLock {
            state.customRules.removeAll {
                $0.pattern == pattern
                    && ($0.type == .pathContains || $0.type == .pathPrefix || $0.type == .pathRegex)
            }
            state.rebuildEngine()
        }
    }

    func addContentTypeRule(_ pattern: String) {
        let rule = FilterRule(type: .contentType, pattern: pattern, description: "User added", isCustom: true)
        withLock { state.customRules.append(rule); state.rebuildEngine() }
    }

    func removeContentTypeRule(_ pattern: String) {
        withLock {
            state.customRules.removeAll { $0.pattern == pattern && $0.type == .contentType }
            state.rebuildEngine()
        }
    }
}

// MARK: - Configuration

extension NoiseFilter {
    func resetToDefaults() {
        let categories = Self.loadBlocklist()
        withLock {
            state.customRules.removeAll()
            state.categories = categories
            state.rebuildEngine()
        }
    }
}

// MARK: - Loading

private extension NoiseFilter {
    static func loadBlocklist() -> [FilterCategory] {
        guard let url = Bundle.main.url(forResource: "DefaultBlocklist", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let blocklist = try? JSONDecoder().decode(BlocklistFile.self, from: data) else {
            return hardcodedCategories()
        }
        return blocklist.categories.map { $0.toFilterCategory() }
    }

    static func hardcodedCategories() -> [FilterCategory] {
        [
            FilterCategory(
                id: FilterCategory.fallbackCategoryID,
                name: "Default Filters",
                description: "Built-in fallback used when the bundled blocklist is unavailable.",
                isEnabledByDefault: true,
                rules: FilterRule.defaultDomainBlocklist
                    + FilterRule.defaultPathPatterns
                    + FilterRule.defaultContentTypeFilters
            )
        ]
    }

    static func loadCustomRules() -> [FilterRule] {
        var rules: [FilterRule] = []
        for domain in Preferences.shared.customBlockedDomains {
            rules.append(
                FilterRule(
                    type: domain.hasPrefix("*.") ? .domainWildcard : .domainExact,
                    pattern: domain,
                    description: "User added",
                    isCustom: true
                )
            )
        }
        for path in Preferences.shared.customBlockedPaths {
            rules.append(FilterRule(type: .pathContains, pattern: path, description: "User added", isCustom: true))
        }
        return rules
    }

    static func loadCategoryOverrides() -> [String: Bool] {
        (UserDefaults.standard.dictionary(forKey: FilterPersistence.categoryOverridesKey) as? [String: Bool]) ?? [:]
    }

    static func loadDisabledRuleIDs() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: FilterPersistence.disabledRuleIDsKey) ?? [])
    }
}
