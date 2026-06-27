//
//  FilterCategory.swift
//  api-ghost
//
//  Created for APIGhost project
//

import Foundation

/// A prebuilt group of filter rules the user can toggle as a unit.
/// Shared contract for the filtering runtime (active = rules of enabled categories) and the settings UI.
struct FilterCategory: Identifiable, Codable, Hashable, Sendable {
    /// Stable identifier matching the rules' `categoryID`.
    let id: String

    /// Display name shown in the filtering UI.
    let name: String

    /// Short explanation of what the category filters.
    let description: String

    /// Whether the category is active out of the box; Social is the one that ships off.
    let isEnabledByDefault: Bool

    /// The prebuilt rules contained in this category.
    let rules: [FilterRule]
}

extension FilterCategory {
    /// Category id assigned to the hardcoded fallback rules when the bundled blocklist is unavailable.
    static let fallbackCategoryID = "default"
}
