import XCTest
@testable import DisplayPilot

final class BrightnessCurveTests: XCTestCase {
    func testEndpointsArePinned() {
        for curve in BrightnessCurve.allCases {
            XCTAssertEqual(curve.factor(for: 0), 0, accuracy: 0.0001)
            XCTAssertEqual(curve.factor(for: 1), 1, accuracy: 0.0001)
        }
    }

    func testCurvesAreMonotonic() {
        for curve in BrightnessCurve.allCases {
            var previous = -1.0
            for step in stride(from: 0.0, through: 1.0, by: 0.05) {
                let value = curve.factor(for: step)
                XCTAssertGreaterThanOrEqual(value, previous, "\(curve) 在 \(step) 处不单调")
                previous = value
            }
        }
    }

    func testGentleIsSofterThanPerceptualInTheUpperRange() {
        // 高端：柔和曲线每 1% 的变化更小（就是「生硬」的根源）
        let gentle = BrightnessCurve.gentle.factor(for: 1.0) - BrightnessCurve.gentle.factor(for: 0.95)
        let perceptual = BrightnessCurve.perceptual.factor(for: 1.0) - BrightnessCurve.perceptual.factor(for: 0.95)
        XCTAssertLessThan(gentle, perceptual)
        XCTAssertEqual(BrightnessCurve.gentle.factor(for: 0.5), pow(0.5, 1.6), accuracy: 0.0001)
    }

    func testEasingIsMonotonicAndHitsBothEnds() {
        XCTAssertEqual(BrightnessCurve.eased(0), 0, accuracy: 0.0001)
        XCTAssertEqual(BrightnessCurve.eased(1), 1, accuracy: 0.0001)
        // ease-out：前半段走得更快
        XCTAssertGreaterThan(BrightnessCurve.eased(0.5), 0.5)
        var previous = -1.0
        for step in stride(from: 0.0, through: 1.0, by: 0.1) {
            let value = BrightnessCurve.eased(step)
            XCTAssertGreaterThanOrEqual(value, previous)
            previous = value
        }
    }

    func testCurvePersists() {
        let store = SettingsStore.shared
        let original = store.curve
        store.curve = .linear
        XCTAssertEqual(store.curve, .linear)
        store.curve = original
        XCTAssertEqual(store.curve, original)
    }
}
