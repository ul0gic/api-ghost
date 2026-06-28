import Testing

@testable import APIGhost

struct HarnessLinkageTests {
    @Test
    func fixturesAreDeterministicAndDistinct() {
        let captures = CaptureFixtures.all()
        #expect(captures.count == 6)

        let uuids = Set(captures.map { $0.uuid })
        #expect(uuids.count == captures.count, "fixture UUIDs must be unique")

        let timestamps = Set(captures.map { $0.timestamp })
        #expect(timestamps.count == captures.count, "distinct timestamps guarantee stable export ordering")
    }
}
