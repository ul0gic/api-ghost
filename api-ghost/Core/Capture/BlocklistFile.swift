//
//  BlocklistFile.swift
//  api-ghost
//
//  Created for APIGhost project
//

import Foundation

/// On-disk shape of the bundled `DefaultBlocklist.json` (schema version 3).
struct BlocklistFile: Decodable {
    let version: Int
    let categories: [BlocklistCategory]
}

/// One prebuilt category as stored in `DefaultBlocklist.json`.
struct BlocklistCategory: Decodable {
    let id: String
    let name: String
    let description: String
    let enabledByDefault: Bool
    let domains: [String]
    let pathPatterns: [String]
    let contentTypes: [String]

    private enum CodingKeys: String, CodingKey {
        case id, name, description, enabledByDefault, domains, pathPatterns, contentTypes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decode(String.self, forKey: .description)
        enabledByDefault = try container.decode(Bool.self, forKey: .enabledByDefault)
        domains = try container.decodeIfPresent([String].self, forKey: .domains) ?? []
        pathPatterns = try container.decodeIfPresent([String].self, forKey: .pathPatterns) ?? []
        contentTypes = try container.decodeIfPresent([String].self, forKey: .contentTypes) ?? []
    }
}

extension BlocklistCategory {
    /// Maps the on-disk category into the in-memory contract, tagging every rule with this category id.
    func toFilterCategory() -> FilterCategory {
        FilterCategory(
            id: id,
            name: name,
            description: description,
            isEnabledByDefault: enabledByDefault,
            rules: makeRules()
        )
    }

    private func makeRules() -> [FilterRule] {
        let domainRules = domains.map {
            makeRule(type: $0.hasPrefix("*.") ? .domainWildcard : .domainExact, pattern: $0)
        }
        let pathRules = pathPatterns.map { makeRule(type: .pathContains, pattern: $0) }
        let contentTypeRules = contentTypes.map { makeRule(type: .contentType, pattern: $0) }
        return domainRules + pathRules + contentTypeRules
    }

    private func makeRule(type: FilterRuleType, pattern: String) -> FilterRule {
        FilterRule(
            id: "\(id):\(type.rawValue):\(pattern)",
            type: type,
            pattern: pattern,
            description: name,
            categoryID: id,
            isCustom: false
        )
    }
}
