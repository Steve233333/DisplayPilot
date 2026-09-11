import XCTest
@testable import DisplayPilot

final class PresetLogicTests: XCTestCase {
    private func preset(_ name: String, slot: Int? = nil, width: Int? = nil, height: Int? = nil, brightness: Double? = nil, display: String? = nil) -> Preset {
        Preset(name: name, backingWidth: width, backingHeight: height, brightness: brightness, hotkeySlot: slot, displayUUID: display)
    }

    func testNextFreeSlotSkipsTakenSlots() {
        XCTAssertEqual(PresetLogic.nextFreeSlot(in: []), 0)
        XCTAssertEqual(PresetLogic.nextFreeSlot(in: [preset("a", slot: 0)]), 1)
        XCTAssertEqual(PresetLogic.nextFreeSlot(in: [preset("a", slot: 2)]), 0)
        XCTAssertNil(PresetLogic.nextFreeSlot(in: [preset("a", slot: 0), preset("b", slot: 1), preset("c", slot: 2)]))
    }

    func testHotkeyLookupIsBySlotNotOrder() {
        let list = [preset("写代码", slot: 2), preset("看片", slot: 0)]
        XCTAssertEqual(PresetLogic.preset(in: list, forSlot: 0)?.name, "看片")
        XCTAssertEqual(PresetLogic.preset(in: list, forSlot: 2)?.name, "写代码")
        XCTAssertNil(PresetLogic.preset(in: list, forSlot: 1))
    }

    func testAssigningSlotStealsItFromTheOldOwner() {
        let a = preset("a", slot: 0)
        let b = preset("b")
        let updated = PresetLogic.assigning(slot: 0, to: b.id, in: [a, b])
        XCTAssertNil(updated.first { $0.id == a.id }?.hotkeySlot, "旧占用者应被解绑")
        XCTAssertEqual(updated.first { $0.id == b.id }?.hotkeySlot, 0)
    }

    func testUnassigningSlot() {
        let a = preset("a", slot: 1)
        let updated = PresetLogic.assigning(slot: nil, to: a.id, in: [a])
        XCTAssertNil(updated.first?.hotkeySlot)
    }

    func testMovingSwapsWithinBounds() {
        let a = preset("a"), b = preset("b"), c = preset("c")
        let moved = PresetLogic.moving(id: c.id, by: -1, in: [a, b, c])
        XCTAssertEqual(moved.map(\.name), ["a", "c", "b"])
        XCTAssertEqual(PresetLogic.moving(id: a.id, by: -1, in: [a, b]).map(\.name), ["a", "b"], "越界不动")
        XCTAssertEqual(PresetLogic.moving(id: b.id, by: 1, in: [a, b]).map(\.name), ["a", "b"], "越界不动")
    }

    func testUpdatingOverwritesModeAndBrightnessOnly() {
        let original = preset("写代码", slot: 1, width: 2560, height: 1600, brightness: 0.5, display: "UUID")
        let mode = ScaledMode(logicalWidth: 1728, logicalHeight: 1080, backingWidth: 3456, backingHeight: 2160, refresh: 60)
        let updated = PresetLogic.updating(original, mode: mode, brightness: 0.8)
        XCTAssertEqual(updated.name, "写代码")
        XCTAssertEqual(updated.hotkeySlot, 1)
        XCTAssertEqual(updated.displayUUID, "UUID")
        XCTAssertEqual(updated.backingWidth, 3456)
        XCTAssertEqual(updated.backingHeight, 2160)
        XCTAssertEqual(updated.brightness, 0.8)
    }

    func testDisplayOrderPutsSlottedFirst() {
        let a = preset("a")
        let b = preset("b", slot: 2)
        let c = preset("c", slot: 0)
        XCTAssertEqual(PresetLogic.displayOrder([a, b, c]).map(\.name), ["c", "b", "a"])
    }

    func testSummaryText() {
        XCTAssertEqual(preset("x", width: 3456, height: 2160, brightness: 0.8).summary, "3456×2160 · 亮度 80%")
        XCTAssertEqual(preset("x").summary, "空预设")
    }
}
