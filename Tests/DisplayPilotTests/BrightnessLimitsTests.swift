import XCTest
@testable import DisplayPilot

/// 亮度区间：滑杆的 0%～100% 映射到用户设定的 [最低, 最高]。
final class BrightnessLimitsTests: XCTestCase {
    func testDefaultLimitsAreFullRange() {
        let limits = BrightnessLimits()
        XCTAssertTrue(limits.isDefault)
        XCTAssertEqual(limits.output(for: 0), 0, accuracy: 0.0001)
        XCTAssertEqual(limits.output(for: 0.5), 0.5, accuracy: 0.0001)
        XCTAssertEqual(limits.output(for: 1), 1, accuracy: 0.0001)
    }

    func testSliderMapsIntoCustomRange() {
        let limits = BrightnessLimits(minimum: 0.1, maximum: 0.8)
        XCTAssertEqual(limits.output(for: 0), 0.1, accuracy: 0.0001)
        XCTAssertEqual(limits.output(for: 0.5), 0.45, accuracy: 0.0001)
        XCTAssertEqual(limits.output(for: 1), 0.8, accuracy: 0.0001)
        XCTAssertFalse(limits.isDefault)
        XCTAssertEqual(limits.rangeText, "10% – 80%")
    }

    func testRoundTripBetweenSliderAndHardwareValue() {
        let limits = BrightnessLimits(minimum: 0.2, maximum: 0.6)
        for slider in stride(from: 0.0, through: 1.0, by: 0.1) {
            let output = limits.output(for: slider)
            XCTAssertEqual(limits.sliderValue(for: output), slider, accuracy: 0.0001)
        }
    }

    func testClampingAndDegenerateRange() {
        let limits = BrightnessLimits(minimum: 0.5, maximum: 0.5)
        XCTAssertEqual(limits.sliderValue(for: 0.7), 0, accuracy: 0.0001, "区间退化时不应除零")
        XCTAssertEqual(BrightnessLimits.clamp(2), 1)
        XCTAssertEqual(BrightnessLimits.clamp(-1), 0)
    }

    func testLimitsCodableRoundTrip() throws {
        let map = ["A": BrightnessLimits(minimum: 0.05, maximum: 0.95)]
        let data = try JSONEncoder().encode(map)
        let decoded = try JSONDecoder().decode([String: BrightnessLimits].self, from: data)
        XCTAssertEqual(decoded["A"]?.minimum, 0.05)
        XCTAssertEqual(decoded["A"]?.maximum, 0.95)
    }
}
