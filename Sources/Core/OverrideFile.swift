import Foundation

/// `/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-<hex>/DisplayProductID-<hex>`
/// 这个 plist 决定 macOS 为某块显示器生成哪些“缩放分辨率”。
///
/// 关键：必须同时写 `DisplayPixelDimensions` 和 `default-resolution`，
/// 否则系统会把缩放档位当成真实输出时序发给显示器，画面会留黑边。
struct OverrideFile: Equatable {
    var vendorID: UInt32
    var productID: UInt32
    var pixelWidth: Int
    var pixelHeight: Int
    var defaultRefresh: Int
    /// 每项 8 字节大端：[backingWidth][backingHeight]
    var scaleResolutions: [Data]

    static let overridesRoot = URL(fileURLWithPath: "/Library/Displays/Contents/Resources/Overrides")

    var productHex: String { String(format: "%04x", productID) }
    var vendorHex: String { String(format: "%04x", vendorID) }

    var directoryURL: URL {
        Self.overridesRoot.appendingPathComponent("DisplayVendorID-\(String(format: "%x", vendorID))")
    }

    var fileURL: URL {
        directoryURL.appendingPathComponent("DisplayProductID-\(String(format: "%x", productID))")
    }

    // MARK: - 编码

    static func encode(backingWidth: Int, backingHeight: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: 8)
        bytes[0] = UInt8((backingWidth >> 24) & 0xFF)
        bytes[1] = UInt8((backingWidth >> 16) & 0xFF)
        bytes[2] = UInt8((backingWidth >> 8) & 0xFF)
        bytes[3] = UInt8(backingWidth & 0xFF)
        bytes[4] = UInt8((backingHeight >> 24) & 0xFF)
        bytes[5] = UInt8((backingHeight >> 16) & 0xFF)
        bytes[6] = UInt8((backingHeight >> 8) & 0xFF)
        bytes[7] = UInt8(backingHeight & 0xFF)
        return Data(bytes)
    }

    func plistObject() -> [String: Any] {
        [
            "DisplayProductID": productID,
            "DisplayVendorID": vendorID,
            "DisplayPixelDimensions": Self.encode(backingWidth: pixelWidth, backingHeight: pixelHeight),
            "default-resolution": Self.encode(backingWidth: pixelWidth, backingHeight: pixelHeight)
                + Data([0, 0, 0, UInt8(defaultRefresh & 0xFF)]),
            "scale-resolutions": scaleResolutions,
        ]
    }

    func data() throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: plistObject(), format: .xml, options: 0)
    }

    func write(to url: URL) throws {
        try data().write(to: url, options: .atomic)
    }

    // MARK: - 解析 / 比对

    static func parse(_ data: Data, vendorID: UInt32, productID: UInt32) -> OverrideFile? {
        guard let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dict = object as? [String: Any],
              let scales = dict["scale-resolutions"] as? [Data]
        else { return nil }

        let pixels = (dict["DisplayPixelDimensions"] as? Data).flatMap(decodeSize)
        let defaultRes = (dict["default-resolution"] as? Data).flatMap { raw -> (Int, Int, Int)? in
            guard raw.count >= 12 else { return nil }
            let w = Int(UInt32(raw[0]) << 24 | UInt32(raw[1]) << 16 | UInt32(raw[2]) << 8 | UInt32(raw[3]))
            let h = Int(UInt32(raw[4]) << 24 | UInt32(raw[5]) << 16 | UInt32(raw[6]) << 8 | UInt32(raw[7]))
            let hz = Int(UInt32(raw[8]) << 24 | UInt32(raw[9]) << 16 | UInt32(raw[10]) << 8 | UInt32(raw[11]))
            return (w, h, hz)
        }

        return OverrideFile(
            vendorID: vendorID,
            productID: productID,
            pixelWidth: pixels?.width ?? 0,
            pixelHeight: pixels?.height ?? 0,
            defaultRefresh: defaultRes?.2 ?? 60,
            scaleResolutions: scales
        )
    }

    private static func decodeSize(_ raw: Data) -> (width: Int, height: Int)? {
        guard raw.count >= 8 else { return nil }
        let w = Int(UInt32(raw[0]) << 24 | UInt32(raw[1]) << 16 | UInt32(raw[2]) << 8 | UInt32(raw[3]))
        let h = Int(UInt32(raw[4]) << 24 | UInt32(raw[5]) << 16 | UInt32(raw[6]) << 8 | UInt32(raw[7]))
        return (w, h)
    }

    /// 盘上的文件和这份内容一致（顺序无关）→ 不用重写、不用再弹管理员密码。
    func matches(onDisk url: URL = URL(fileURLWithPath: "/")) -> Bool {
        let target = url.path == "/" ? fileURL : url
        guard let data = try? Data(contentsOf: target),
              let existing = OverrideFile.parse(data, vendorID: vendorID, productID: productID)
        else { return false }
        return existing.pixelWidth == pixelWidth
            && existing.pixelHeight == pixelHeight
            && existing.defaultRefresh == defaultRefresh
            && Set(existing.scaleResolutions) == Set(scaleResolutions)
    }

    // MARK: - 档位生成

    /// 等距柔性缩放梯：宽从原生按 `step` 递减到 `minScale`，高按面板比例跟随，
    /// 每一项的 backing（渲染像素）都是逻辑尺寸的 2 倍。
    static func ladder(
        nativeWidth: Int,
        nativeHeight: Int,
        step: Int = 16,
        minScale: Double = 0.5
    ) -> [(logicalWidth: Int, logicalHeight: Int, backingWidth: Int, backingHeight: Int)] {
        guard nativeWidth > 0, nativeHeight > 0 else { return [] }
        let minWidth = Int((Double(nativeWidth) * minScale).rounded())
        var result: [(Int, Int, Int, Int)] = []
        var width = nativeWidth
        while width >= minWidth {
            let height = Int((Double(width) * Double(nativeHeight) / Double(nativeWidth)).rounded())
            if width >= 800, height >= 600 {
                result.append((width, height, width * 2, height * 2))
            }
            width -= step
        }
        return result
    }

    /// 精简档位：原生 + 几个常用比例。
    static func compactLadder(nativeWidth: Int, nativeHeight: Int) -> [(logicalWidth: Int, logicalHeight: Int, backingWidth: Int, backingHeight: Int)] {
        let ratios: [Double] = [1.0, 0.9, 0.75, 0.625, 0.5]
        return ratios.map { ratio in
            let width = Int((Double(nativeWidth) * ratio).rounded()) & ~1
            let height = Int((Double(nativeHeight) * ratio).rounded()) & ~1
            return (width, height, width * 2, height * 2)
        }
        .filter { $0.0 >= 800 && $0.1 >= 600 }
    }

    static func generate(identity: DisplayIdentity, native: (width: Int, height: Int), density: LadderDensity) -> OverrideFile {
        let stops = density == .full
            ? ladder(nativeWidth: native.width, nativeHeight: native.height)
            : compactLadder(nativeWidth: native.width, nativeHeight: native.height)
        return OverrideFile(
            vendorID: identity.vendorID,
            productID: identity.productID,
            pixelWidth: native.width,
            pixelHeight: native.height,
            defaultRefresh: 60,
            scaleResolutions: stops.map { encode(backingWidth: $0.backingWidth, backingHeight: $0.backingHeight) }
        )
    }
}
