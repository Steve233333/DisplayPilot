import XCTest
@testable import DisplayPilot

final class LadderTests: XCTestCase {
    func testFullLadderMatchesBetterDisplayGrid() {
        let stops = OverrideFile.ladder(nativeWidth: 1920, nativeHeight: 1200)
        XCTAssertEqual(stops.count, 61, "1920×1200 面板从原生到 50% 每 16 点一档应为 61 档")

        let first = stops.first
        XCTAssertEqual(first?.logicalWidth, 1920)
        XCTAssertEqual(first?.logicalHeight, 1200)
        XCTAssertEqual(first?.backingWidth, 3840)
        XCTAssertEqual(first?.backingHeight, 2400)

        let last = stops.last
        XCTAssertEqual(last?.logicalWidth, 960)
        XCTAssertEqual(last?.logicalHeight, 600)
        XCTAssertEqual(last?.backingWidth, 1920)
        XCTAssertEqual(last?.backingHeight, 1200)
    }

    func testEveryStopIsDoubleBackedAndSixteenPointStepped() {
        let stops = OverrideFile.ladder(nativeWidth: 2560, nativeHeight: 1440)
        for (index, stop) in stops.enumerated() {
            XCTAssertEqual(stop.backingWidth, stop.logicalWidth * 2)
            XCTAssertEqual(stop.backingHeight, stop.logicalHeight * 2)
            if index > 0 {
                XCTAssertEqual(stops[index - 1].logicalWidth - stop.logicalWidth, 16)
            }
        }
    }

    func testKnownStopsExist() {
        let stops = OverrideFile.ladder(nativeWidth: 1920, nativeHeight: 1200)
        let widths = Set(stops.map(\.logicalWidth))
        for expected in [1920, 1728, 1600, 1440, 1280, 960] {
            XCTAssertTrue(widths.contains(expected), "缺少 \(expected) 档")
        }
    }

    func testCompactLadderIsShort() {
        let stops = OverrideFile.compactLadder(nativeWidth: 1920, nativeHeight: 1200)
        XCTAssertTrue((3...6).contains(stops.count))
        XCTAssertEqual(stops.first?.logicalWidth, 1920)
    }
}
