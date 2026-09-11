import AppKit
import CoreGraphics
import Foundation
import os

/// 软件调光：用伽马表把画面整体压暗，不碰显示器背光，
/// 因此和显示器的 DCR（动态对比度）不会打架。
final class SoftwareBrightness {
    static let shared = SoftwareBrightness()

    /// 伽马表 API 运行时解析：万一将来 macOS 删掉这个符号（BetterDisplay 2.2.6
    /// 就是这么被系统更新干掉的），App 依然能启动，只是软件调光不可用。
    private typealias SetTableFn = @convention(c) (
        CGDirectDisplayID, UInt32,
        UnsafePointer<CGGammaValue>, UnsafePointer<CGGammaValue>, UnsafePointer<CGGammaValue>
    ) -> Int32

    private static let coreGraphics: UnsafeMutableRawPointer? =
        dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_NOW)

    private static let setTableFn: SetTableFn? = {
        guard let coreGraphics, let symbol = dlsym(coreGraphics, "CGSetDisplayTransferByTable") else { return nil }
        return unsafeBitCast(symbol, to: SetTableFn.self)
    }()

    /// 这台机器上还能不能用伽马表调光。
    static var isAvailable: Bool { setTableFn != nil }

    private let log = Logger(subsystem: "com.steve233.DisplayPilot", category: "software-brightness")
    private var factors: [CGDirectDisplayID: Double] = [:]
    private let lock = NSLock()
    private var observersInstalled = false

    private init() {}

    // MARK: - 对外

    /// 把"感知亮度"换算成伽马系数。
    /// 伽马表是线性压亮度，而人眼对亮度的感知接近 sRGB（≈ 2.2 次方），
    /// 直接用百分比压会让 60% 看起来像 80% —— 这里做一次反向补偿，
    /// 让滑杆上的百分比和眼睛看到的亮度对得上。
    static func perceptualFactor(for level: Double) -> Double {
        let clamped = min(max(level, 0.0), 1.0)
        return pow(clamped, 2.2)
    }

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
        guard let setTable = Self.setTableFn else {
            log.error("CGSetDisplayTransferByTable 在当前系统上不可用，软件调光已跳过")
            return
        }
        let capacity = 256
        var table = [CGGammaValue](repeating: 0, count: capacity)
        for index in 0..<capacity {
            let input = CGGammaValue(index) / CGGammaValue(capacity - 1)
            table[index] = CGGammaValue(min(1.0, max(0.0, Double(input) * factor)))
        }
        let result = table.withUnsafeBufferPointer { buffer -> Int32 in
            guard let base = buffer.baseAddress else { return -1 }
            return setTable(displayID, UInt32(capacity), base, base, base)
        }
        if result != 0 {
            log.debug("gamma write failed for display \(displayID): \(result)")
        }
    }
}
