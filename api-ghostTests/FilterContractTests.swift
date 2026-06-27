import Foundation
import Testing

@testable import APIGhost

private let defaultOnCategoryIDs = [
    "analytics", "advertising", "error-session", "consent", "marketing", "cdns", "non-api-content"
]

// MARK: - On-disk contract (no singleton)

@Suite
struct BlocklistContractTests {
    private func loadBlocklist() throws -> BlocklistFile {
        let url = try #require(
            Bundle.main.url(forResource: "DefaultBlocklist", withExtension: "json"),
            "DefaultBlocklist.json must be bundled in the app"
        )
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(BlocklistFile.self, from: data)
    }

    @Test
    func decodesVersion3WithEightCategories() throws {
        let file = try loadBlocklist()
        #expect(file.version == 3)
        #expect(file.categories.count == 8)
    }

    @Test
    func socialOffByDefaultEveryOtherCategoryOn() throws {
        let file = try loadBlocklist()
        let byID = Dictionary(uniqueKeysWithValues: file.categories.map { ($0.id, $0) })

        for id in defaultOnCategoryIDs {
            let category = try #require(byID[id], "missing category \(id)")
            #expect(category.enabledByDefault == true, "\(id) must be ON by default")
        }

        let social = try #require(byID["social"], "missing social category")
        #expect(social.enabledByDefault == false, "social must ship OFF by default")
    }

    @Test
    func domainPathContentTypeCountsPreserved() throws {
        let file = try loadBlocklist()
        let domains = file.categories.reduce(0) { $0 + $1.domains.count }
        let paths = file.categories.reduce(0) { $0 + $1.pathPatterns.count }
        let contentTypes = file.categories.reduce(0) { $0 + $1.contentTypes.count }
        #expect(domains == 116)
        #expect(paths == 29)
        #expect(contentTypes == 10)
    }

    @Test
    func toFilterCategoryTagsEveryRuleWithCategoryIDAndNotCustom() throws {
        let file = try loadBlocklist()
        for category in file.categories {
            let mapped = category.toFilterCategory()
            #expect(mapped.id == category.id)

            let expectedRuleCount =
                category.domains.count + category.pathPatterns.count + category.contentTypes.count
            #expect(mapped.rules.count == expectedRuleCount, "rule count mismatch for \(category.id)")

            for rule in mapped.rules {
                #expect(rule.categoryID == category.id, "rule \(rule.pattern) must be tagged with \(category.id)")
                #expect(rule.isCustom == false, "prebuilt rule \(rule.pattern) must not be custom")
            }
        }
    }
}

// MARK: - Runtime activation contract (singleton)

@Suite(.serialized)
struct NoiseFilterContractTests {
    private var filter: NoiseFilter { NoiseFilter.shared }

    @Test
    func categoriesContainAllEightWithSocialOff() throws {
        let categories = filter.categories
        #expect(categories.count == 8)

        let byID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        for id in defaultOnCategoryIDs {
            #expect(byID[id]?.isEnabledByDefault == true, "\(id) must be ON by default")
        }
        let social = try #require(byID["social"], "missing social category")
        #expect(social.isEnabledByDefault == false)
    }

    @Test
    func defaultOnCategoryBlocksAnalyticsDomain() {
        filter.isEnabled = true
        #expect(filter.isDomainBlocked("www.google-analytics.com").blocked == true)
    }

    @Test
    func socialDomainsAreNotBlockedByDefault() {
        filter.isEnabled = true
        for host in ["x.com", "facebook.com", "reddit.com", "spotify.com", "t.co"] {
            #expect(filter.isDomainBlocked(host).blocked == false, "\(host) must not be blocked by default")
        }
    }

    @Test
    func prebuiltRulesAreTaggedAndNotCustom() {
        for category in filter.categories {
            for rule in category.rules {
                #expect(rule.categoryID != nil, "prebuilt rule \(rule.pattern) must carry a categoryID")
                #expect(rule.isCustom == false, "prebuilt rule \(rule.pattern) must not be custom")
            }
        }
    }

    @Test
    func customAddedRuleIsMarkedCustom() throws {
        let pattern = "unit-test-custom.example"
        filter.addDomainRule(pattern, isWildcard: false)
        defer { filter.removeDomainRule(pattern) }

        let added = try #require(
            filter.customRulesList.first { $0.pattern == pattern },
            "custom rule should be present after addDomainRule"
        )
        #expect(added.isCustom == true)
        #expect(added.categoryID == nil)
    }
}
