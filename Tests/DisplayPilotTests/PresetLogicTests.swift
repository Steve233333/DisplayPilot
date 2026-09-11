import XCTest
@testable import DisplayPilot

final class PresetLogicTests: XCTestCase {
    private func preset(_ name: String, slot: Int? = nil, width: Int? = nil, height: Int? = nil, brightness: Double? = nil, display: String? = nil) -> Preset {
        Preset(name: name, backingWidth: width, backingHeight: height, brightness: brightness, displayUUID: display)
    }

    func testMovingSwapsWithinBounds() {
        let a = preset("a"), b = preset("b"), c = preset("c")
        let moved = PresetLogic.moving(id: c.id, by: -1, in: [a, b, c])
        XCTAssertEqual(moved.map(\.name), ["a", "c", "b"])
        XCTAssertEqual(PresetLogic.moving(id: a.id, by: -1, in: [a, b]).map(\.name), ["a", "b"], "越界不动")
        XCTAssertEqual(PresetLogic.moving(id: b.id, by: 1, in: [a, b]).map(\.name), ["a", "b"], "越界不动")
    }

    func testUpdatingOverwritesModeAndBrightnessOnly() {
        let original = preset("写代码", width: 2560, height: 1600, brightness: 0.5, display: "UUID")
        let mode = ScaledMode(logicalWidth: 1728, logicalHeight: 1080, backingWidth: 3456, backingHeight: 2160, refresh: 60)
        let updated = PresetLogic.updating(original, mode: mode, brightness: 0.8)
        XCTAssertEqual(updated.name, "写代码")
        XCTAssertEqual(updated.displayUUID, "UUID")
        XCTAssertEqual(updated.backingWidth, 3456)
        XCTAssertEqual(updated.backingHeight, 2160)
        XCTAssertEqual(updated.brightness, 0.8)
    }

    func testSummaryText() {
        XCTAssertEqual(preset("x", width: 3456, height: 2160, brightness: 0.8).summary, "3456×2160 · 亮度 80%")
        XCTAssertEqual(preset("x").summary, "空预设")
    }
}
