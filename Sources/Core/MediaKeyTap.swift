import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import os

/// 拦截键盘上的亮度键（F1/F2），把它们交给 DisplayPilot 处理，
/// 同时吞掉系统原本的亮度事件。
///
/// 需要「辅助功能」权限；没有权限时事件 tap 建不起来，此时会回退到
/// 自定快捷键（⌥⌘↑/↓）。
final class MediaKeyTap {
    static let shared = MediaKeyTap()

    var onBrightnessUp: (() -> Void)?
    var onBrightnessDown: (() -> Void)?

    private let log = Logger(subsystem: "com.steve233.DisplayPilot", category: "media-keys")
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var selfReference: Unmanaged<MediaKeyTap>?

    private static let systemDefinedTypeRaw: UInt32 = 14
    private static let auxControlSubtype: Int16 = 8
    private static let brightnessUpKey = 2
    private static let brightnessDownKey = 3

    private init() {}

    var isRunning: Bool { tap != nil }

    static var hasAccessibilityPermission: Bool { AXIsProcessTrusted() }

    static func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - 生命周期

    func start() {
        guard tap == nil else { return }
        let retained = Unmanaged.passRetained(self)
        selfReference = retained

        let mask = CGEventMask(1 << Self.systemDefinedTypeRaw)
            | CGEventMask(1 << CGEventType.keyDown.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: mediaKeyCallback,
            userInfo: retained.toOpaque()
        ) else {
            retained.release()
            selfReference = nil
            log.notice("event tap creation failed (missing Accessibility permission?)")
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.tap = tap
        self.runLoopSource = source
        log.notice("media key tap armed")
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
            CFMachPortInvalidate(tap)
        }
        tap = nil
        runLoopSource = nil
        selfReference?.release()
        selfReference = nil
        log.notice("media key tap stopped")
    }

    // MARK: - 事件处理

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        if type.rawValue == Self.systemDefinedTypeRaw {
            guard let nsEvent = NSEvent(cgEvent: event),
                  nsEvent.subtype.rawValue == Self.auxControlSubtype
            else { return Unmanaged.passUnretained(event) }

            let data = nsEvent.data1
            let keyCode = Int((data & 0xFFFF_0000) >> 16)
            let flags = data & 0x0000_FFFF
            let isKeyDown = ((flags & 0xFF00) >> 8) == 0x0A
            guard isKeyDown else { return Unmanaged.passUnretained(event) }

            switch keyCode {
            case Self.brightnessUpKey:
                DispatchQueue.main.async { self.onBrightnessUp?() }
                return nil
            case Self.brightnessDownKey:
                DispatchQueue.main.async { self.onBrightnessDown?() }
                return nil
            default:
                return Unmanaged.passUnretained(event)
            }
        }

        // 没有内建屏幕时（Mac mini），系统可能不再发 NX_SYSDEFINED，
        // 但原始 keyDown 仍会流动：补一条兜底路径。
        if type == .keyDown {
            let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
            let isAuxDown = event.getIntegerValueField(.keyboardEventAutorepeat) == 0
            let flags = event.flags
            let hasFn = flags.contains(.maskSecondaryFn)
            if hasFn, isAuxDown {
                switch keyCode {
                case 122: // kVK_F1
                    DispatchQueue.main.async { self.onBrightnessDown?() }
                    return nil
                case 120: // kVK_F2
                    DispatchQueue.main.async { self.onBrightnessUp?() }
                    return nil
                default:
                    break
                }
            }
        }

        return Unmanaged.passUnretained(event)
    }
}

private let mediaKeyCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<MediaKeyTap>.fromOpaque(userInfo).takeUnretainedValue()
    return tap.handle(type: type, event: event)
}
