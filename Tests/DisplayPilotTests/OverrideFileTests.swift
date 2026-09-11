import XCTest
@testable import DisplayPilot

final class OverrideFileTests: XCTestCase {
    private let identity = DisplayIdentity(
        uuid: "TEST-UUID",
        vendorID: 19083,
        productID: 8817,
        name: "Test Panel",
        isBuiltin: false
    )

    func testEncodedBackingBytesMatchBetterDisplayLayout() {
        let data = OverrideFile.encode(backingWidth: 3840, backingHeight: 2400)
        XCTAssertEqual(data.map { String(format: "%02x", $0) }.joined(), "00000f0000000960")
        let smallest = OverrideFile.encode(backingWidth: 1920, backingHeight: 1200)
        XCTAssertEqual(smallest.map { String(format: "%02x", $0) }.joined(), "00000780000004b0")
    }

    func testGeneratedPlistCarriesPixelDimensionsAndDefaultResolution() throws {
        let file = OverrideFile.generate(identity: identity, native: (1920, 1200), density: .full)
        let plistData = try file.data()
        let object = try XCTUnwrap(
            try PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any]
        )
        XCTAssertEqual(object["DisplayVendorID"] as? UInt32, 19083)
        XCTAssertEqual(object["DisplayProductID"] as? UInt32, 8817)

        let pixels = try XCTUnwrap(object["DisplayPixelDimensions"] as? Data)
        XCTAssertEqual(pixels.count, 8)
        XCTAssertEqual(OverrideFile.parse(plistData, vendorID: 19083, productID: 8817)?.pixelWidth, 1920)

        let defaultResolution = try XCTUnwrap(object["default-resolution"] as? Data)
        XCTAssertEqual(defaultResolution.count, 12, "default-resolution 必须是 [宽][高][刷新率] 12 字节")

        let scales = try XCTUnwrap(object["scale-resolutions"] as? [Data])
        XCTAssertEqual(scales.count, 61)
    }

    func testRoundTripAndMatchesOnDisk() throws {
        let file = OverrideFile.generate(identity: identity, native: (1920, 1200), density: .full)
        let parsed = try XCTUnwrap(OverrideFile.parse(try file.data(), vendorID: 19083, productID: 8817))
        XCTAssertEqual(parsed.pixelWidth, 1920)
        XCTAssertEqual(parsed.pixelHeight, 1200)
        XCTAssertEqual(parsed.defaultRefresh, 60)
        XCTAssertEqual(Set(parsed.scaleResolutions), Set(file.scaleResolutions))

        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("displaypilot-test-\(UUID().uuidString).plist")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try file.write(to: temporary)

        XCTAssertTrue(file.matches(onDisk: temporary), "内容一致时不应重写、不应再弹密码")

        var trimmed = file
        trimmed.scaleResolutions.removeLast()
        XCTAssertFalse(trimmed.matches(onDisk: temporary))
    }

    func testOverridePathsFollowSystemLayout() {
        let file = OverrideFile.generate(identity: identity, native: (1920, 1200), density: .compact)
        XCTAssertTrue(file.directoryURL.path.hasSuffix("/Overrides/DisplayVendorID-4a8b"))
        XCTAssertTrue(file.fileURL.path.hasSuffix("/DisplayProductID-2271"))
    }

    func testPresetCodableRoundTrip() throws {
        let preset = Preset(name: "写代码", backingWidth: 3456, backingHeight: 2160, brightness: 0.8, hotkeySlot: 0, displayUUID: "U")
        let data = try JSONEncoder().encode([preset])
        let decoded = try JSONDecoder().decode([Preset].self, from: data)
        XCTAssertEqual(decoded.first?.name, "写代码")
        XCTAssertEqual(decoded.first?.backingWidth, 3456)
        XCTAssertEqual(decoded.first?.brightness, 0.8)
    }
}
