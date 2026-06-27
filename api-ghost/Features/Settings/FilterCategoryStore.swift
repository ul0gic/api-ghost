import SwiftUI

// Persistence contract consumed by Core NoiseFilter (build-plan 2.1.3):
// `filter.categoryOverrides` ([String:Bool], categoryID→enabled; absent = isEnabledByDefault)
// and `filter.disabledRuleIDs` ([String]) define the active prebuilt rule set.
@Observable
final class FilterCategoryStore {
    private(set) var categories: [FilterCategory]

    private var categoryOverrides: [String: Bool]
    private var disabledRuleIDs: Set<String>

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let categoryOverrides = "filter.categoryOverrides"
        static let disabledRuleIDs = "filter.disabledRuleIDs"
    }

    init() {
        categories = NoiseFilter.shared.categories
        categoryOverrides = (defaults.dictionary(forKey: Keys.categoryOverrides) as? [String: Bool]) ?? [:]
        disabledRuleIDs = Set(defaults.stringArray(forKey: Keys.disabledRuleIDs) ?? [])
    }

    // MARK: - Category state

    func isCategoryEnabled(_ category: FilterCategory) -> Bool {
        categoryOverrides[category.id] ?? category.isEnabledByDefault
    }

    func isCategoryDefaultOn(_ category: FilterCategory) -> Bool {
        category.isEnabledByDefault
    }

    func setCategory(_ category: FilterCategory, enabled: Bool) {
        if enabled == category.isEnabledByDefault {
            categoryOverrides.removeValue(forKey: category.id)
        } else {
            categoryOverrides[category.id] = enabled
        }
        persist()
    }

    // MARK: - Rule state

    func isRuleEnabled(_ rule: FilterRule) -> Bool {
        !disabledRuleIDs.contains(rule.id)
    }

    func setRule(_ rule: FilterRule, enabled: Bool) {
        if enabled {
            disabledRuleIDs.remove(rule.id)
        } else {
            disabledRuleIDs.insert(rule.id)
        }
        persist()
    }

    func enabledRuleCount(in category: FilterCategory) -> Int {
        category.rules.filter { !disabledRuleIDs.contains($0.id) }.count
    }

    // MARK: - Reset

    func resetToDefaults() {
        categoryOverrides = [:]
        disabledRuleIDs = []
        categories = NoiseFilter.shared.categories
        persist()
    }

    // MARK: - Persistence

    private func persist() {
        defaults.set(categoryOverrides, forKey: Keys.categoryOverrides)
        defaults.set(Array(disabledRuleIDs), forKey: Keys.disabledRuleIDs)
        NotificationCenter.default.post(name: .filterRulesDidChange, object: nil)
    }
}

extension Notification.Name {
    static let filterRulesDidChange = Notification.Name("filterRulesDidChange")
}
