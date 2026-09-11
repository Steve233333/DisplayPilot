import XCTest
@testable import DisplayPilot

/// 对着本机真实存在的 override 文件做一次集成校验：
/// 内容一致时 App 不应该再弹管理员密码。
final class SystemOverrideIntegrationTests: XCTestCase {
    func testInstalledOverrideMatchesGeneratedLadder() throws {
        let path = "/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-4a8b/DisplayProductID-2271"
        guard FileManager.default.fileExists(atPath: path) else {
            throw XCTSkip("本机没有安装 override，跳过（属于正常情况）")
        }

        let identity = DisplayIdentity(
            uuid: "LOCAL",
            vendorID: 19083,
            productID: 8817,
            name: "DP",
            isBuiltin: false
        )
        let generated = OverrideFile.generate(identity: identity, native: (1920, 1200), density: .full)
        XCTAssertTrue(
            generated.matches(onDisk: URL(fileURLWithPath: path)),
            "盘上的 override 与 App 生成的档位不一致，会导致重复弹密码"
        )
    }
}
