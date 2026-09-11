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

    var hiDPIModes: [ScaledMode] { availableModes.filter(\.isHiDPI) }

    /// 面板真实像素：取最大的非 HiDPI 模式；拿不到就退回当前模式的 backing。
    var nativeResolution: (width: Int, height: Int) {
        if let native = availableModes.filter({ !$0.isHiDPI }).max(by: {
            $0.backingWidth * $0.backingHeight < $1.backingWidth * $1.backingHeight
        }) {
            return (native.backingWidth, native.backingHeight)
        }
        if let mode = currentMode { return (mode.backingWidth, mode.backingHeight) }
        return (1920, 1080)
    }

    /// 用来做滑杆的档位：优先 HiDPI 梯，附带原生 1× 档。
    var scalingChoices: [ScaledMode] {
        var seen = Set<String>()
        var result: [ScaledMode] = []
        for mode in availableModes.sorted(by: {
            $0.logicalWidth * $0.logicalHeight > $1.logicalWidth * $1.logicalHeight
        }) where mode.refresh >= 59.0 {
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
        let main = CGMainDisplayID()
        return activeDisplayIDs().map { id in
            DisplaySnapshot(
                displayID: id,
                identity: identity(for: id),
                currentMode: currentMode(for: id),
                availableModes: modes(for: id),
                isMain: id == main
            )
        }
    }

    func snapshot(for id: CGDirectDisplayID) -> DisplaySnapshot {
        DisplaySnapshot(
            displayID: id,
            identity: identity(for: id),
            currentMode: currentMode(for: id),
            availableModes: modes(for: id),
            isMain: id == CGMainDisplayID()
        )
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
