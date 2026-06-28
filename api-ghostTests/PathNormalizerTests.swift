import Foundation
import Testing

@testable import APIGhost

@Suite
struct PathNormalizerTests {
    private let normalizer = PathNormalizer.shared

    // MARK: - registrableDomain

    @Test(arguments: [
        ("api.example.com", "example.com"),
        ("example.com", "example.com"),
        ("a.b.c.example.com", "example.com"),
        ("foo.bar.co.uk", "bar.co.uk"),
        ("api.shop.com.au", "shop.com.au"),
        ("x.y.co.jp", "y.co.jp"),
        ("localhost", "localhost"),
        ("EXAMPLE.COM", "example.com")
    ])
    func registrableDomainResolvesEtldPlusOne(host: String, expected: String) {
        #expect(PathNormalizer.registrableDomain(host) == expected)
    }

    @Test
    func registrableDomainStripsPort() {
        #expect(PathNormalizer.registrableDomain("example.com:8080") == "example.com")
        #expect(PathNormalizer.registrableDomain("api.example.com:443") == "example.com")
    }

    @Test
    func registrableDomainFallsThroughForIPAddress() {
        #expect(PathNormalizer.registrableDomain("192.168.1.1") == "1.1")
    }

    // MARK: - thirdPartyCategory

    @Test(arguments: [
        ("cdn.jsdelivr.net", "CDN"),
        ("d111111abcdef8.cloudfront.net", "CDN"),
        ("analytics.example.com", "Analytics / Telemetry"),
        ("api.mixpanel.com", "Analytics / Telemetry"),
        ("o123.ingest.sentry.io", "Error / Session Tracking"),
        ("consent.example.com", "Consent / CMP"),
        ("ads.example.com", "Advertising"),
        ("fonts.gstatic.com", "Fonts / Assets")
    ])
    func thirdPartyCategoryMatchesKeywords(host: String, expected: String) {
        #expect(PathNormalizer.thirdPartyCategory(for: host) == expected)
    }

    @Test
    func thirdPartyCategoryReturnsNilWhenUnmatched() {
        #expect(PathNormalizer.thirdPartyCategory(for: "api.example.com") == nil)
    }

    // MARK: - normalizePath: parameterization

    @Test
    func normalizesNumericId() {
        let (normalized, params) = normalizer.normalizePath("/users/12847")
        #expect(normalized == "/users/{id}")
        #expect(params.count == 1)
        #expect(params.first?.segment == "12847")
        #expect(params.first?.type == .numericId)
    }

    @Test
    func normalizesUUID() {
        let (normalized, _) = normalizer.normalizePath("/items/550e8400-e29b-41d4-a716-446655440000")
        #expect(normalized == "/items/{uuid}")
    }

    @Test
    func normalizesHash() {
        let (normalized, _) = normalizer.normalizePath("/files/5f4dcc3b5aa765d61d8327deb882cf99")
        #expect(normalized == "/files/{hash}")
    }

    @Test
    func normalizesToken() {
        let jwt = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dQw4w9WgXcQ1aBcDeF2gHi"
        let (normalized, params) = normalizer.normalizePath("/session/\(jwt)")
        #expect(normalized == "/session/{token}")
        #expect(params.first?.type == .token)
    }

    @Test
    func preservesStaticSegments() {
        let (normalized, params) = normalizer.normalizePath("/api/v1/users/profile")
        #expect(normalized == "/api/v1/users/profile")
        #expect(params.isEmpty)
    }

    @Test
    func normalizesMultipleIdsInOnePath() {
        let (normalized, params) = normalizer.normalizePath("/orgs/12847/projects/98765")
        #expect(normalized == "/orgs/{id}/projects/{id}")
        #expect(params.count == 2)
    }

    @Test
    func shortNumericSegmentIsNotParameterized() {
        let (normalized, _) = normalizer.normalizePath("/users/12")
        #expect(normalized == "/users/12")
    }

    // MARK: - normalizePaths: sibling-aware numeric collapse

    @Test
    func shortNumericSiblingsCollapseToId() {
        let result = normalizer.normalizePaths(["/users/7", "/users/42"])
        #expect(result["/users/7"] == "/users/{id}")
        #expect(result["/users/42"] == "/users/{id}")
    }

    @Test
    func loneShortNumericStaysLiteralAcrossBatch() {
        let result = normalizer.normalizePaths(["/users/12", "/orders/9"])
        #expect(result["/users/12"] == "/users/12")
        #expect(result["/orders/9"] == "/orders/9")
    }

    @Test
    func versionSegmentsAreNeverTreatedAsNumericIds() {
        let result = normalizer.normalizePaths(["/v1/users/7", "/v1/users/42"])
        #expect(result["/v1/users/7"] == "/v1/users/{id}")
        #expect(result["/v1/users/42"] == "/v1/users/{id}")
    }

    @Test
    func nestedNumericSiblingsCollapseAtEachPosition() {
        let result = normalizer.normalizePaths(["/users/7/posts/1", "/users/8/posts/2"])
        #expect(result["/users/7/posts/1"] == "/users/{id}/posts/{id}")
        #expect(result["/users/8/posts/2"] == "/users/{id}/posts/{id}")
    }

    // MARK: - normalizePath: edge cases

    @Test
    func emptyPathReturnsRoot() {
        let (normalized, params) = normalizer.normalizePath("")
        #expect(normalized == "/")
        #expect(params.isEmpty)
    }

    @Test
    func rootPathReturnsRoot() {
        let (normalized, _) = normalizer.normalizePath("/")
        #expect(normalized == "/")
    }

    @Test
    func collapsesEmptySegments() {
        let (normalized, _) = normalizer.normalizePath("/users//12847/")
        #expect(normalized == "/users/{id}")
    }

    // MARK: - detectParameterType

    @Test
    func detectParameterTypeReturnsNilForStaticWord() {
        #expect(normalizer.detectParameterType("profile") == nil)
    }

    @Test
    func detectParameterTypeFlagsLongMixedSegmentAsUnknown() {
        #expect(normalizer.detectParameterType("aB3xY7zK9mN2qR5tW8") == .unknown)
    }

    @Test
    func isProbablyDynamicThresholds() {
        #expect(normalizer.isProbablyDynamic("short") == false)
        #expect(normalizer.isProbablyDynamic("aB3xY7zK9mN2qR") == true)
        #expect(normalizer.isProbablyDynamic(String(repeating: "x", count: 31)) == true)
    }

    // MARK: - Path analysis utilities

    @Test
    func extractParameterTypesFindsPlaceholders() {
        let types = normalizer.extractParameterTypes(from: "/users/{id}/files/{uuid}")
        #expect(types == [.numericId, .uuid])
    }

    @Test
    func countDynamicSegmentsCountsPlaceholders() {
        #expect(normalizer.countDynamicSegments(in: "/users/{id}/files/{hash}") == 2)
        #expect(normalizer.countDynamicSegments(in: "/users/profile") == 0)
    }

    @Test
    func generateMatchingPatternBuildsRegex() throws {
        let pattern = try #require(normalizer.generateMatchingPattern(for: "/users/{id}/profile"))
        let regex = try NSRegularExpression(pattern: pattern)
        let candidate = "/users/12847/profile"
        let range = NSRange(candidate.startIndex..., in: candidate)
        #expect(regex.firstMatch(in: candidate, range: range) != nil)

        let nonMatch = "/users/12847/settings"
        let nonRange = NSRange(nonMatch.startIndex..., in: nonMatch)
        #expect(regex.firstMatch(in: nonMatch, range: nonRange) == nil)
    }
}
