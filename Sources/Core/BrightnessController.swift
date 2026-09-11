import AppKit
import CoreGraphics
import Foundation
import os

/// 亮度总控：解析每屏策略（自动/硬件/软件），把 0…1 的亮度落到具体后端。
@MainActor
final class BrightnessController {
    static let shared = BrightnessController()

    private let log = Logger(subsystem: "com.steve233.DisplayPilot", category: "brightness")
    private let settings = SettingsStore.shared

    /// 每块屏当前亮度（0…1）与解析出的后端。
    private(set) var levels: [String: Double] = [:]
    private(set) var backends: [String: BrightnessBackend] = [:]

    private var ddcMax: [String: UInt16] = [:]
    private var ddcProbed: Set<String> = []
    private let ddcQueue = DispatchQueue(label: "com.steve233.DisplayPilot.ddc", qos: .userInitiated)

    private init() {}

    // MARK: - 查询

    func level(for snapshot: DisplaySnapshot) -> Double {
        let uuid = snapshot.identity.uuid
        if let value = levels[uuid] { return value }
        let fallback = settings.level(for: uuid) ?? initialLevel(for: snapshot)
        levels[uuid] = fallback
        return fallback
    }

    func backend(for snapshot: DisplaySnapshot) -> BrightnessBackend {
        let uuid = snapshot.identity.uuid
        if let value = backends[uuid] { return value }
        let resolved = resolveBackend(for: snapshot)
        backends[uuid] = resolved
        return resolved
    }

    func policy(for snapshot: DisplaySnapshot) -> BrightnessPolicy {
        settings.policy(for: snapshot.identity.uuid)
    }

    func setPolicy(_ policy: BrightnessPolicy, for snapshot: DisplaySnapshot) {
        settings.setPolicy(policy, for: snapshot.identity.uuid)
        backends.removeValue(forKey: snapshot.identity.uuid)
        ddcProbed.remove(snapshot.identity.uuid)
        DDCBrightness.shared.invalidate(displayID: snapshot.displayID)
        // 换后端时把当前亮度重新落一次，避免两边状态不一致。
        setLevel(level(for: snapshot), for: snapshot, showOSD: false)
    }

    // MARK: - 设置亮度

    func setLevel(_ level: Double, for snapshot: DisplaySnapshot, showOSD: Bool = true, delta: Double? = nil) {
        let uuid = snapshot.identity.uuid
        let clamped = min(max(level, 0.0), 1.0)
        levels[uuid] = clamped
        settings.setLevel(clamped, for: uuid)

        switch backend(for: snapshot) {
        case .hardware:
            writeHardware(clamped, for: snapshot)
        case .software:
            SoftwareBrightness.shared.set(SoftwareBrightness.perceptualFactor(for: clamped), on: snapshot.displayID)
        }

        if showOSD, settings.osdEnabled {
            OSDController.shared.show(
                level: clamped,
                displayName: snapshot.identity.name,
                backend: backend(for: snapshot),
                screen: NSScreen.screens.first {
                    ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == snapshot.displayID
                }
            )
        }
    }

    func nudge(_ delta: Double, for snapshot: DisplaySnapshot) {
        setLevel(level(for: snapshot) + delta, for: snapshot)
    }

    /// 亮度键 / 快捷键作用的目标：鼠标所在屏幕，拿不到就主屏。
    func targetSnapshot(from snapshots: [DisplaySnapshot]) -> DisplaySnapshot? {
        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }),
           let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
           let match = snapshots.first(where: { $0.displayID == number.uint32Value }) {
            return match
        }
        return snapshots.first(where: \.isMain) ?? snapshots.first
    }

    /// 显示器变化后重新校准（重连、换后端、首次运行）。
    func refresh(_ snapshots: [DisplaySnapshot]) {
        for snapshot in snapshots {
            let uuid = snapshot.identity.uuid
            if backends[uuid] == nil {
                backends[uuid] = resolveBackend(for: snapshot)
            }
            if levels[uuid] == nil {
                levels[uuid] = settings.level(for: uuid) ?? initialLevel(for: snapshot)
            }
            // 软件调光在屏幕参数变化后需要重放。
            if backend(for: snapshot) == .software, let level = levels[uuid] {
                SoftwareBrightness.shared.set(SoftwareBrightness.perceptualFactor(for: level), on: snapshot.displayID)
            }
        }
        let alive = Set(snapshots.map(\.identity.uuid))
        for uuid in levels.keys where !alive.contains(uuid) {
            levels.removeValue(forKey: uuid)
            backends.removeValue(forKey: uuid)
            ddcMax.removeValue(forKey: uuid)
            ddcProbed.remove(uuid)
        }
    }

    /// 策略变更（例如首次运行预置了「强制软件」）后丢掉已解析的后端，
    /// 下一次查询会按新策略重新解析。
    func forgetResolvedBackends() {
        backends.removeAll()
        ddcProbed.removeAll()
        // 一并丢掉内存里从 DDC 读来的亮度，改从（刚预置好的）设置里取，
        // 免得"强制软件"策略沿用了硬件读回的百分比。
        levels.removeAll()
    }

    // MARK: - 后端解析

    private func resolveBackend(for snapshot: DisplaySnapshot) -> BrightnessBackend {
        let uuid = snapshot.identity.uuid
        switch policy(for: snapshot) {
        case .software:
            return .software
        case .hardware:
            return .hardware
        case .automatic:
            if ddcProbed.contains(uuid) {
                if let maxValue = ddcMax[uuid], maxValue > 0 { return .hardware }
                return .software
            }
            ddcProbed.insert(uuid)
            if let reading = DDCBrightness.shared.read(displayID: snapshot.displayID) {
                ddcMax[uuid] = reading.max
                // 首次探测到硬件亮度时，把当前值同步进来（只读这一次）。
                levels[uuid] = Double(reading.current) / Double(reading.max)
                return .hardware
            }
            log.notice("display \(uuid, privacy: .public): DDC unavailable, using software dimming")
            return .software
        }
    }

    private func writeHardware(_ level: Double, for snapshot: DisplaySnapshot) {
        let uuid = snapshot.identity.uuid
        ddcQueue.async { [weak self] in
            guard let self else { return }
            let maxValue: UInt16
            if let cached = self.ddcMax[uuid] {
                maxValue = cached
            } else if let reading = DDCBrightness.shared.read(displayID: snapshot.displayID) {
                maxValue = reading.max
                Task { @MainActor in self.ddcMax[uuid] = reading.max }
            } else {
                return
            }
            let raw = UInt16((Double(maxValue) * level).rounded())
            let ok = DDCBrightness.shared.write(raw, displayID: snapshot.displayID)
            if !ok {
                Task { @MainActor in
                    self.log.notice("DDC write failed on \(uuid, privacy: .public); falling back to software for this session")
                    self.backends[uuid] = .software
                    SoftwareBrightness.shared.set(SoftwareBrightness.perceptualFactor(for: level), on: snapshot.displayID)
                }
            }
        }
    }

    private func initialLevel(for snapshot: DisplaySnapshot) -> Double {
        if policy(for: snapshot) == .software { return 1.0 }
        if let reading = DDCBrightness.shared.read(displayID: snapshot.displayID), reading.max > 0 {
            ddcMax[snapshot.identity.uuid] = reading.max
            return Double(reading.current) / Double(reading.max)
        }
        return 1.0
    }
}
