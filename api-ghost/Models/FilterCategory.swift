import Foundation

struct FilterCategory: Identifiable, Codable, Hashable, Sendable {
    let id: String

    let name: String

    let description: String

    let isEnabledByDefault: Bool

    let rules: [FilterRule]
}

extension FilterCategory {
    static let fallbackCategoryID = "default"
}
