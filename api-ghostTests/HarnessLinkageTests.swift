import XCTest

@testable import APIGhost

final class HarnessLinkageTests: XCTestCase {
    func testFixturesAreDeterministicAndDistinct() {
        let captures = CaptureFixtures.all()
        XCTAssertEqual(captures.count, 6)

        let uuids = Set(captures.map { $0.uuid })
        XCTAssertEqual(uuids.count, captures.count, "fixture UUIDs must be unique")

        let timestamps = Set(captures.map { $0.timestamp })
        XCTAssertEqual(timestamps.count, captures.count, "distinct timestamps guarantee stable export ordering")
    }
}
