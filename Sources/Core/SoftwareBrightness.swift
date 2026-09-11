import AppKit
import CoreGraphics
import Foundation
import os

/// 软件调光：用伽马表把画面整体压暗，不碰显示器背光，
/// 因此和显示器的 DCR（动态对比度）不会打架。
final class SoftwareBrightness {
    static let shared = SoftwareBrightness()

    private let log = Logger(subsystem: "com.steve233.DisplayPilot", category: "software-brightness")
    private var factors: [CGDirectDisplayID: Double] = [:]
    private let lock = NSLock()
    private var observersInstalled = false

    private init() {}

    // MARK: - 对外

    func factor(for displayID: CGDirectDisplayID) -> Double {
        lock.lock(); defer { lock.unlock() }
        return factors[displayID] ?? 1.0
    }

    func set(_ factor: Double, on displayID: CGDirectDisplayID) {
        let clamped = min(max(factor, 0.05), 1.0)
        lock.lock()
        factors[displayID] = clamped
        lock.unlock()
        apply(clamped, to: displayID)
    }

    func forget(displayID: CGDirectDisplayID) {
        lock.lock(); factors.removeValue(forKey: displayID); lock.unlock()
    }

    /// 唤醒、改分辨率、换色彩描述文件之后重放一次（伽马状态会被系统重置）。
    func reapplyAll() {
        lock.lock()
        let snapshot = factors
        lock.unlock()
        for (displayID, factor) in snapshot where factor < 0.999 {
            apply(factor, to: displayID)
        }
    }

    func restoreAll() {
        lock.lock()
        factors.removeAll()
        lock.unlock()
        for displayID in DisplayManager.shared.onlineDisplayIDs() {
            apply(1.0, to: displayID)
        }
    }

    func startObserving() {
        guard !observersInstalled else { return }
        observersInstalled = true
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.reapplyAll()
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.reapplyAll()
        }
    }

    // MARK: - 伽马表

    private func apply(_ factor: Double, to displayID: CGDirectDisplayID) {
        let capacity = 256
        var table = [CGGammaValue](repeating: 0, count: capacity)
        for index in 0..<capacity {
            let input = CGGammaValue(index) / CGGammaValue(capacity - 1)
            table[index] = CGGammaValue(min(1.0, max(0.0, Double(input) * factor)))
        }
        let result = CGSetDisplayTransferByTable(displayID, UInt32(capacity), &table, &table, &table)
        if result != .success {
            log.debug("gamma write failed for display \(displayID): \(Int(result.rawValue))")
        }
    }
}
