import Foundation

/// Shared filter-toggle persistence contract: written by the UI (FilterCategoryStore), read by Core (NoiseFilter).
enum FilterPersistence {
    nonisolated static let categoryOverridesKey = "filter.categoryOverrides"
    nonisolated static let disabledRuleIDsKey = "filter.disabledRuleIDs"
    nonisolated static let rulesDidChange = Notification.Name("filterRulesDidChange")
}
