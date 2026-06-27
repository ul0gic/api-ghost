import Foundation
import Testing

@testable import APIGhost

// MARK: - FilterEngine drop semantics & toggling (2.1.5a / 2.1.5c)

/// `FilterEngine` is pure and singleton-free, so these run fully isolated and parallel-safe — no `.shared`, no UserDefaults.
@Suite
struct FilterEngineTests {
    private static let analytics = FilterCategory(
        id: "analytics",
        name: "Analytics",
        description: "",
        isEnabledByDefault: true,
        rules: [
            FilterRule(id: "an-domain", type: .domainWildcard, pattern: "*.tracker.example"),
            FilterRule(id: "an-path", type: .pathContains, pattern: "/collect")
        ]
    )

    private static let ads = FilterCategory(
        id: "ads",
        name: "Ads",
        description: "",
        isEnabledByDefault: true,
        rules: [FilterRule(id: "ad-domain", type: .domainWildcard, pattern: "*.doubleclick.net")]
    )

    private static let media = FilterCategory(
        id: "media",
        name: "Media",
        description: "",
        isEnabledByDefault: true,
        rules: [FilterRule(id: "media-ct", type: .contentType, pattern: "image/*")]
    )

    private static let social = FilterCategory(
        id: "social",
        name: "Social",
        description: "",
        isEnabledByDefault: false,
        rules: [FilterRule(id: "social-domain", type: .domainWildcard, pattern: "*.facebook.com")]
    )

    private static let allCategories = [analytics, ads, media, social]

    private func engine(
        overrides: [String: Bool] = [:],
        disabledRuleIDs: Set<String> = [],
        isEnabled: Bool = true
    ) -> FilterEngine {
        FilterEngine(
            categories: Self.allCategories,
            categoryOverrides: overrides,
            disabledRuleIDs: disabledRuleIDs,
            isEnabled: isEnabled
        )
    }

    // MARK: Drop semantics

    @Test
    func dropsBlockedDomain() {
        let decision = engine().decision(host: "a.tracker.example", path: "/v1/users")
        #expect(decision.shouldCapture == false, "a matched domain is dropped, never stored")
        #expect(decision.reason != nil, "a dropped request carries an attributable reason")
    }

    @Test
    func dropsBlockedPath() {
        #expect(engine().decision(host: "api.app.example", path: "/collect").shouldCapture == false)
    }

    @Test
    func dropsBlockedContentType() {
        let decision = engine().decision(host: "api.app.example", path: "/img", contentType: "image/png")
        #expect(decision.shouldCapture == false)
    }

    @Test
    func capturesUnmatchedRequest() {
        let decision = engine().decision(host: "api.app.example", path: "/v1/users", contentType: "application/json")
        #expect(decision.shouldCapture == true, "first-party API traffic is captured")
        #expect(decision.reason == nil)
    }

    @Test
    func socialCategoryOffByDefaultIsNotDropped() {
        #expect(engine().decision(host: "www.facebook.com", path: "/x").shouldCapture == true)
    }

    @Test
    func disabledEngineCapturesEverything() {
        let decision = engine(isEnabled: false)
            .decision(host: "a.tracker.example", path: "/collect", contentType: "image/png")
        #expect(decision.shouldCapture == true, "nothing is dropped while filtering is off")
    }

    // MARK: Category & rule toggling (2.1.5c)

    @Test
    func disablingCategoryDropsItsRules() {
        #expect(engine().decision(host: "x.doubleclick.net", path: "/p").shouldCapture == false)
        #expect(engine(overrides: ["ads": false]).decision(host: "x.doubleclick.net", path: "/p").shouldCapture == true)
    }

    @Test
    func enablingOffByDefaultCategoryAppliesItsRules() {
        #expect(engine().decision(host: "www.facebook.com", path: "/x").shouldCapture == true)
        let enabled = engine(overrides: ["social": true]).decision(host: "www.facebook.com", path: "/x")
        #expect(enabled.shouldCapture == false, "enabling an off-by-default category applies its rules")
    }

    @Test
    func disablingOneRuleKeepsOtherRulesInTheCategory() {
        let withRuleOff = engine(disabledRuleIDs: ["an-domain"])
        #expect(withRuleOff.decision(host: "a.tracker.example", path: "/v1").shouldCapture == true,
                "the disabled domain rule no longer applies")
        #expect(withRuleOff.decision(host: "api.app.example", path: "/collect").shouldCapture == false,
                "its sibling path rule still applies")
    }

    @Test
    func filterDecisionMakesDropAllOrNothing() {
        let dropped = FilterDecision.filter("Domain blocked: example")
        #expect(dropped.shouldCapture == false)
        #expect(dropped.reason == "Domain blocked: example")

        #expect(FilterDecision.capture.shouldCapture == true)
        #expect(FilterDecision.capture.reason == nil)
    }
}

// MARK: - Session Filtered counter (2.1.2 / 2.1.5b)

/// `FilterSessionCounter` is the in-memory, thread-safe source of truth for the session "Filtered" tally — never a DB query.
@Suite
struct FilterSessionCounterTests {
    @Test
    func incrementIsMonotonicAndReturnsNewValue() {
        let counter = FilterSessionCounter()
        #expect(counter.value == 0)
        #expect(counter.increment() == 1)
        #expect(counter.increment() == 2)
        #expect(counter.value == 2)
    }

    @Test
    func resetReturnsToZero() {
        let counter = FilterSessionCounter()
        counter.increment()
        counter.increment()
        counter.reset()
        #expect(counter.value == 0)
    }

    @Test
    func concurrentIncrementsAreNotLost() async {
        let counter = FilterSessionCounter()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<1000 {
                group.addTask { _ = counter.increment() }
            }
        }
        #expect(counter.value == 1000, "the lock-guarded counter must not drop increments under concurrency")
    }
}

/// `recordFiltered()` bumps the sync `sessionFilteredCount` source of truth; assert that (deterministic), not the async AppState mirror.
@MainActor
@Suite(.serialized)
struct SessionFilteredCountIntegrationTests {
    @Test
    func recordFilteredBumpsSessionCountPerDrop() {
        TrafficCapture.shared.resetSessionFilteredCount()
        defer { TrafficCapture.shared.resetSessionFilteredCount() }

        for _ in 0..<3 {
            TrafficCapture.shared.recordFiltered()
        }
        #expect(TrafficCapture.shared.sessionFilteredCount == 3, "each dropped request bumps the sync session counter")
    }
}
