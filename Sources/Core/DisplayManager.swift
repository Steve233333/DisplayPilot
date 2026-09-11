import AppKit
import ColorSync
import CoreGraphics
import Foundation

/// 一台显示器在某一时刻的快照。
struct DisplaySnapshot: Identifiable, Hashable {
    var id: CGDirectDisplayID { displayID }
    let displayID: CGDirectDisplayID
    let identity: DisplayIdentity
    let currentMode: ScaledMode?
    let availableModes: [ScaledMode]
    let isMain: Bool
    /// EDID 报告的原生像素（IOKit DisplayAttributes），虚拟显示器通常没有。
    var edidNative: CGSize?

    var hiDPIModes: [ScaledMode] { availableModes.filter(\.isHiDPI) }

    /// 面板真实像素（生成 override 与判断等比例都用它）：
    /// 优先用 EDID 里的原生时序；虚拟/隔空播放显示器没有 EDID 时用当前模式的 backing，
    /// 但只在它没被超采样放大过（< 1.5×）时才信。
    var nativeResolution: (width: Int, height: Int) {
        let largestOneToOne = availableModes
            .filter { !$0.isHiDPI }
            .max { $0.backingWidth * $0.backingHeight < $1.backingWidth * $1.backingHeight }

        if let edid = edidNative, edid.width > 0, edid.height > 0 {
            return (Int(edid.width), Int(edid.height))
        }
        if let current = currentMode, let reference = largestOneToOne {
            let currentArea = Double(current.backingWidth * current.backingHeight)
            let referenceArea = Double(reference.backingWidth * reference.backingHeight)
            if currentArea <= referenceArea * 2.25 {
                return (current.backingWidth, current.backingHeight)
            }
        }
        if let reference = largestOneToOne {
            return (reference.backingWidth, reference.backingHeight)
        }
        if let mode = currentMode { return (mode.backingWidth, mode.backingHeight) }
        return (1920, 1080)
    }

    /// 做滑杆用的档位：默认只留 **HiDPI + 与面板等比例** 的档位，
    /// 这样既不会选到模糊的 1×，也不会选到留黑边的 4:3/16:9 档位。
    func scalingChoices(hidpiOnly: Bool = true, aspectTolerant: Bool = true) -> [ScaledMode] {
        let native = nativeResolution
        let nativeAspect = Double(native.width) / Double(native.height)
        var seen = Set<String>()
        var result: [ScaledMode] = []
        for mode in availableModes.sorted(by: {
            $0.logicalWidth * $0.logicalHeight > $1.logicalWidth * $1.logicalHeight
        }) where mode.refresh >= 59.0 {
            if hidpiOnly, !mode.isHiDPI { continue }
            if aspectTolerant, mode.backingHeight > 0 {
                let aspect = Double(mode.backingWidth) / Double(mode.backingHeight)
                if abs(aspect - nativeAspect) / nativeAspect > 0.02 { continue }
            }
            let key = "\(mode.backingWidth)x\(mode.backingHeight)-\(mode.logicalWidth)x\(mode.logicalHeight)"
            if seen.insert(key).inserted { result.append(mode) }
        }
        return result
    }
}

/// 显示器与显示模式的读写入口。
final class DisplayManager {
    static let shared = DisplayManager()

    private let modeOptions: CFDictionary = [
        kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue as Any
    ] as CFDictionary

    // MARK: - 枚举

    func onlineDisplayIDs() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &count)
        guard count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetOnlineDisplayList(count, &ids, &count)
        return ids
    }

    func activeDisplayIDs() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        guard count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        return ids
    }

    func snapshots() -> [DisplaySnapshot] {
        activeDisplayIDs().map { snapshot(for: $0) }
    }

    func snapshot(for id: CGDirectDisplayID) -> DisplaySnapshot {
        var snapshot = DisplaySnapshot(
            displayID: id,
            identity: identity(for: id),
            currentMode: currentMode(for: id),
            availableModes: modes(for: id),
            isMain: id == CGMainDisplayID()
        )
        snapshot.edidNative = nativeFormatResolution(for: id)
        return snapshot
    }

    /// 从 IOKit 的 DisplayAttributes 里读 EDID 原生时序（NativeFormat*）。
    private func nativeFormatResolution(for id: CGDirectDisplayID) -> CGSize? {
        let wantVendor = UInt32(CGDisplayVendorNumber(id))
        let wantProduct = UInt32(CGDisplayModelNumber(id))

        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        guard root != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(root) }

        var iterator: io_iterator_t = 0
        guard IORegistryEntryCreateIterator(
            root, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &iterator
        ) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        var entry = IOIteratorNext(iterator)
        while entry != IO_OBJECT_NULL {
            defer {
                IOObjectRelease(entry)
                entry = IOIteratorNext(iterator)
            }
            guard let attributes = IORegistryEntryCreateCFProperty(
                entry, "DisplayAttributes" as CFString, kCFAllocatorDefault, 0
            )?.takeRetainedValue() as? [String: Any],
                  let width = attributes["NativeFormatHorizontalPixels"] as? Int,
                  let height = attributes["NativeFormatVerticalPixels"] as? Int,
                  let product = attributes["ProductAttributes"] as? [String: Any]
            else { continue }

            let vendorID = (product["LegacyManufacturerID"] as? UInt32) ?? (product["LegacyManufacturerID"] as? Int).map { UInt32($0) }
            let productID = (product["ProductID"] as? UInt32) ?? (product["ProductID"] as? Int).map { UInt32($0) }
            guard vendorID == wantVendor, productID == wantProduct else { continue }
            return CGSize(width: width, height: height)
        }
        return nil
    }

    func displayID(forUUID uuid: String) -> CGDirectDisplayID? {
        onlineDisplayIDs().first { identity(for: $0).uuid == uuid }
    }

    // MARK: - 身份

    func identity(for id: CGDirectDisplayID) -> DisplayIdentity {
        let vendor = UInt32(CGDisplayVendorNumber(id))
        let product = UInt32(CGDisplayModelNumber(id))
        var uuidString = String(format: "v-%04x-p-%04x", vendor, product)
        if let cfUUID = CGDisplayCreateUUIDFromDisplayID(id) {
            uuidString = CFUUIDCreateString(nil, cfUUID.takeRetainedValue()) as String
        }
        return DisplayIdentity(
            uuid: uuidString,
            vendorID: vendor,
            productID: product,
            name: screenName(for: id) ?? "Display \(id)",
            isBuiltin: CGDisplayIsBuiltin(id) != 0
        )
    }

    private func screenName(for id: CGDirectDisplayID) -> String? {
        NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
        }?.localizedName
    }

    // MARK: - 模式

    func modes(for id: CGDirectDisplayID) -> [ScaledMode] {
        guard let cfModes = CGDisplayCopyAllDisplayModes(id, modeOptions) as? [CGDisplayMode] else {
            return []
        }
        return cfModes.map { mode in
            ScaledMode(
                logicalWidth: mode.width,
                logicalHeight: mode.height,
                backingWidth: mode.pixelWidth,
                backingHeight: mode.pixelHeight,
                refresh: mode.refreshRate
            )
        }
    }

    func currentMode(for id: CGDirectDisplayID) -> ScaledMode? {
        guard let mode = CGDisplayCopyDisplayMode(id) else { return nil }
        return ScaledMode(
            logicalWidth: mode.width,
            logicalHeight: mode.height,
            backingWidth: mode.pixelWidth,
            backingHeight: mode.pixelHeight,
            refresh: mode.refreshRate
        )
    }

    /// 切换模式。成功返回 true。
    @discardableResult
    func setMode(_ target: ScaledMode, on id: CGDirectDisplayID) -> Bool {
        let candidates = modes(for: id).filter {
            $0.backingWidth == target.backingWidth
                && $0.backingHeight == target.backingHeight
                && $0.logicalWidth == target.logicalWidth
                && $0.logicalHeight == target.logicalHeight
        }
        let picked = candidates.first { abs($0.refresh - target.refresh) < 1.0 } ?? candidates.first
        let wanted = picked ?? target

        guard let allModes = CGDisplayCopyAllDisplayModes(id, modeOptions) as? [CGDisplayMode],
              let mode = allModes.first(where: {
                  $0.pixelWidth == wanted.backingWidth
                      && $0.pixelHeight == wanted.backingHeight
                      && $0.width == wanted.logicalWidth
                      && $0.height == wanted.logicalHeight
                      && abs($0.refreshRate - wanted.refresh) < 1.0
              }) ?? allModes.first(where: {
                  $0.pixelWidth == wanted.backingWidth
                      && $0.pixelHeight == wanted.backingHeight
                      && $0.width == wanted.logicalWidth
              })
        else { return false }

        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success else { return false }
        CGConfigureDisplayWithDisplayMode(config, id, mode, nil)
        return CGCompleteDisplayConfiguration(config, .permanently) == .success
    }

    /// 物理分辨率（用于生成 override 的 DisplayPixelDimensions）。
    func panelNativeResolution(for id: CGDirectDisplayID) -> (width: Int, height: Int) {
        snapshot(for: id).nativeResolution
    }
}
