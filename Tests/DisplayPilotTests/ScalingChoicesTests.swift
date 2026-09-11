import CoreGraphics
import XCTest
@testable import DisplayPilot

/// 档位筛选：只留 HiDPI + 与面板等比例的档位（黑边就是这么来的）。
final class ScalingChoicesTests: XCTestCase {
    private func mode(_ pw: Int, _ ph: Int, _ lw: Int, _ lh: Int, hz: Double = 60) -> ScaledMode {
        ScaledMode(logicalWidth: lw, logicalHeight: lh, backingWidth: pw, backingHeight: ph, refresh: hz)
    }

    /// 一台 1920×1200（16:10）面板，模式表里混着 4:3 / 5:4 / 16:9 的干扰项。
    private func makeSnapshot(edidNative: CGSize?) -> DisplaySnapshot {
        let modes = [
            mode(1920, 1200, 1920, 1200),   // 原生 1×
            mode(3840, 2400, 1920, 1200),   // HiDPI 2×
            mode(3456, 2160, 1728, 1080),   // HiDPI（旧习惯档位）
            mode(3200, 2000, 1600, 1000),   // HiDPI
            mode(2560, 1600, 1280, 800),    // HiDPI
            mode(1280, 1024, 1280, 1024),   // 5:4 —— 会留黑边
            mode(2560, 2048, 1280, 1024),   // 5:4 HiDPI —— 会留黑边
            mode(1600, 900, 1600, 900),     // 16:9 —— 会留黑边
        ]
        return DisplaySnapshot(
            displayID: 1,
            identity: DisplayIdentity(uuid: "X", vendorID: 1, productID: 2, name: "T", isBuiltin: false),
            currentMode: modes[2],
            availableModes: modes,
            isMain: true,
            edidNative: edidNative
        )
    }

    func testHiDPIFilterKeepsOnlyCrispModes() {
        let snapshot = makeSnapshot(edidNative: CGSize(width: 1920, height: 1200))
        let choices = snapshot.scalingChoices(hidpiOnly: true)
        XCTAssertTrue(choices.allSatisfy(\.isHiDPI), "开了只显示 HiDPI 就不该出现 1× 档位")
        XCTAssertFalse(choices.contains { $0.logicalWidth == 1920 && $0.logicalHeight == 1200 && !$0.isHiDPI })
    }

    func testAspectFilterDropsModesThatWouldLetterbox() {
        let snapshot = makeSnapshot(edidNative: CGSize(width: 1920, height: 1200))
        let choices = snapshot.scalingChoices(hidpiOnly: true)
        let aspectRatios = choices.map { Double($0.backingWidth) / Double($0.backingHeight) }
        for ratio in aspectRatios {
            XCTAssertEqual(ratio, 1.6, accuracy: 0.02, "16:10 面板上不该出现会留黑边的比例")
        }
        XCTAssertFalse(choices.contains { $0.backingWidth == 1280 && $0.backingHeight == 1024 })
        XCTAssertFalse(choices.contains { $0.backingWidth == 1600 && $0.backingHeight == 900 })
    }

    func testEverythingStillAvailableWhenFilterTurnedOff() {
        let snapshot = makeSnapshot(edidNative: CGSize(width: 1920, height: 1200))
        let choices = snapshot.scalingChoices(hidpiOnly: false, aspectTolerant: false)
        XCTAssertTrue(choices.contains { !$0.isHiDPI })
        XCTAssertTrue(choices.contains { $0.backingWidth == 1280 && $0.backingHeight == 1024 })
    }

    func testEDIDNativeWinsOverSupersampledCurrentMode() {
        let snapshot = makeSnapshot(edidNative: CGSize(width: 1920, height: 1200))
        XCTAssertEqual(snapshot.nativeResolution.width, 1920)
        XCTAssertEqual(snapshot.nativeResolution.height, 1200)
    }

    func testVirtualDisplayFallbackUsesCurrentBackingWhenNotSupersampled() {
        // 隔空播放这类没有 EDID 的显示器：当前模式 backing 3048×2032 就是它的真实像素
        let modes = [
            mode(2160, 1440, 2160, 1440),
            mode(3048, 2032, 1524, 1016),
        ]
        let snapshot = DisplaySnapshot(
            displayID: 4,
            identity: DisplayIdentity(uuid: "V", vendorID: 0, productID: 0, name: "AirPlay", isBuiltin: false),
            currentMode: modes[1],
            availableModes: modes,
            isMain: false,
            edidNative: nil
        )
        XCTAssertEqual(snapshot.nativeResolution.width, 3048)
        XCTAssertEqual(snapshot.nativeResolution.height, 2032)
    }

    func testPerceptualBrightnessCurveMatchesSlider() {
        // 50% 的滑杆应该给出约 22% 的伽马系数（= 感觉上就是 50% 亮）
        XCTAssertEqual(SoftwareBrightness.perceptualFactor(for: 0.5), 0.2176, accuracy: 0.01)
        XCTAssertEqual(SoftwareBrightness.perceptualFactor(for: 1.0), 1.0, accuracy: 0.0001)
        XCTAssertEqual(SoftwareBrightness.perceptualFactor(for: 0.0), 0.0, accuracy: 0.0001)
    }
}
