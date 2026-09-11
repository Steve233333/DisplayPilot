import AppKit
import CoreGraphics
import Foundation
import os

/// 覆盖层调光：在目标显示器上盖一层半透明黑窗。
///
/// 为什么需要它：隔空播放 / 无线拓展 / 虚拟屏这类显示器的画面是"编码后送出去"的，
/// 伽马表写进去不报错但没有任何视觉效果（实测 AirPlay 屏就是 write=0 但画面不变暗）。
/// 盖一层窗是内容层面的压暗，任何显示器都有效。
final class OverlayDimming {
    static let shared = OverlayDimming()

    private let log = Logger(subsystem: "com.steve233.DisplayPilot", category: "overlay-dimming")
    private var panels: [CGDirectDisplayID: NSPanel] = [:]
    private var factors: [CGDirectDisplayID: Double] = [:]
    private let lock = NSLock()
    private var observing = false

    private init() {}

    // MARK: - 对外

    /// factor = 1.0 表示不压暗（移除覆盖层）。
    func set(_ factor: Double, on displayID: CGDirectDisplayID) {
        let clamped = min(max(factor, 0.0), 1.0)
        lock.lock()
        factors[displayID] = clamped
        lock.unlock()

        guard clamped < 0.999 else {
            remove(displayID)
            return
        }
        startObservingIfNeeded()
        apply(clamped, on: displayID)
    }

    func factor(for displayID: CGDirectDisplayID) -> Double? {
        lock.lock(); defer { lock.unlock() }
        return factors[displayID]
    }

    func remove(_ displayID: CGDirectDisplayID) {
        lock.lock()
        factors.removeValue(forKey: displayID)
        let panel = panels.removeValue(forKey: displayID)
        lock.unlock()
        panel?.orderOut(nil)
        panel?.close()
    }

    func removeAll() {
        lock.lock()
        let all = panels
        panels.removeAll()
        factors.removeAll()
        lock.unlock()
        for (_, panel) in all {
            panel.orderOut(nil)
            panel.close()
        }
    }

    /// 屏幕布局变化（分辨率、排列、插拔）后重新贴合。
    func relayout() {
        lock.lock()
        let current = factors
        lock.unlock()
        for (displayID, factor) in current {
            apply(factor, on: displayID)
        }

        let online = Set(DisplayManager.shared.onlineDisplayIDs())
        lock.lock()
        let stale = panels.keys.filter { !online.contains($0) }
        lock.unlock()
        for id in stale { remove(id) }
    }

    // MARK: - 实现

    private func apply(_ factor: Double, on displayID: CGDirectDisplayID) {
        guard let screen = NSScreen.screens.first(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID
        }) else {
            log.debug("no NSScreen for display \(displayID)")
            return
        }

        let panel = panel(for: displayID)
        panel.setFrame(screen.frame, display: false)
        panel.backgroundColor = NSColor.black.withAlphaComponent(1.0 - factor)
        panel.orderFrontRegardless()
    }

    private func panel(for displayID: CGDirectDisplayID) -> NSPanel {
        lock.lock()
        if let existing = panels[displayID] {
            lock.unlock()
            return existing
        }
        lock.unlock()

        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .screenSaver          // 盖住普通窗口，也能盖住全屏应用
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true     // 点击穿透，照常操作这块屏
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.animationBehavior = .none

        lock.lock()
        panels[displayID] = panel
        lock.unlock()
        return panel
    }

    private func startObservingIfNeeded() {
        guard !observing else { return }
        observing = true
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.relayout()
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.relayout()
        }
    }
}
