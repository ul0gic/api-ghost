import SwiftUI

@Observable
final class FilterCategoryStore {
    private(set) var categories: [FilterCategory]

    private var categoryOverrides: [String: Bool]
    private var disabledRuleIDs: Set<String>

    private let defaults = UserDefaults.standard

    init() {
        categories = NoiseFilter.shared.categories
        categoryOverrides =
            (defaults.dictionary(forKey: FilterPersistence.categoryOverridesKey) as? [String: Bool]) ?? [:]
        disabledRuleIDs = Set(defaults.stringArray(forKey: FilterPersistence.disabledRuleIDsKey) ?? [])
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
        defaults.set(categoryOverrides, forKey: FilterPersistence.categoryOverridesKey)
        defaults.set(Array(disabledRuleIDs), forKey: FilterPersistence.disabledRuleIDsKey)
        NotificationCenter.default.post(name: FilterPersistence.rulesDidChange, object: nil)
    }
}
