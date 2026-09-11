import CoreGraphics
import Foundation
import IOKit
import os

/// 通过 IOAVService（Apple Silicon 上的私有 DDC 通道）读写显示器亮度。
///
/// 协议要点（VCP 0x10 = 亮度）：
///   写：payload [0x84, 0x03, vcp, hi, lo] + 校验和（种子 0x6E ^ 0x51）
///   读：请求 [0x82, 0x01, vcp] + 校验和，等待 ~40ms 后读 12 字节回复，
///       回复里 [6..7]=最大值、[8..9]=当前值，[10]=校验和。
/// 只在用户操作时发命令，绝不做后台轮询 —— 你这台显示器在 DCR 模式下
/// 被反复写背光就会闪。
final class DDCBrightness {
    static let shared = DDCBrightness()

    struct Reading {
        var current: UInt16
        var max: UInt16
    }

    static let brightnessVCP: UInt8 = 0x10
    static let contrastVCP: UInt8 = 0x12

    private let log = Logger(subsystem: "com.steve233.DisplayPilot", category: "ddc")
    private var channelCache: [CGDirectDisplayID: CFTypeRef] = [:]
    private var deadSince: [CGDirectDisplayID: Date] = [:]
    private let lock = NSLock()
    private let retryInterval: TimeInterval = 30

    private typealias CreateFn = @convention(c) (CFAllocator?, io_service_t) -> Unmanaged<CFTypeRef>?
    private typealias IOFn = @convention(c) (CFTypeRef, UInt32, UInt32, UnsafeMutablePointer<UInt8>, UInt32) -> Int32

    private static let handle: UnsafeMutableRawPointer? =
        dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW)

    private static let createFn: CreateFn? = {
        guard let handle, let symbol = dlsym(handle, "IOAVServiceCreateWithService") else { return nil }
        return unsafeBitCast(symbol, to: CreateFn.self)
    }()

    private static let readFn: IOFn? = {
        guard let handle, let symbol = dlsym(handle, "IOAVServiceReadI2C") else { return nil }
        return unsafeBitCast(symbol, to: IOFn.self)
    }()

    private static let writeFn: IOFn? = {
        guard let handle, let symbol = dlsym(handle, "IOAVServiceWriteI2C") else { return nil }
        return unsafeBitCast(symbol, to: IOFn.self)
    }()

    // MARK: - 对外 API

    /// 读 VCP。读不到返回 nil（= 这块屏没有可用的 DDC 通道）。
    func read(displayID: CGDirectDisplayID, vcp: UInt8 = DDCBrightness.brightnessVCP) -> Reading? {
        guard Self.readFn != nil, Self.writeFn != nil else { return nil }
        guard let channel = channel(for: displayID) else { return nil }

        var checksum = UInt8(0x6E ^ 0x51)
        var payload: [UInt8] = [0x82, 0x01, vcp]
        for byte in payload { checksum ^= byte }
        payload.append(checksum)

        var buffer = payload
        guard Self.writeFn?(channel, 0x37, 0x51, &buffer, UInt32(buffer.count)) == 0 else {
            markDead(displayID)
            return nil
        }
        Thread.sleep(forTimeInterval: 0.04)

        var reply = [UInt8](repeating: 0, count: 12)
        guard Self.readFn?(channel, 0x37, 0x51, &reply, UInt32(reply.count)) == 0 else {
            markDead(displayID)
            return nil
        }
        guard reply[0] == 0x6E, reply[2] == 0x02, reply[3] == 0x00, reply[4] == vcp else {
            markDead(displayID)
            return nil
        }
        var expected = UInt8(0x50)
        for index in 0...9 { expected ^= reply[index] }
        guard expected == reply[10] else {
            markDead(displayID)
            return nil
        }

        let maximum = UInt16(reply[6]) << 8 | UInt16(reply[7])
        let current = UInt16(reply[8]) << 8 | UInt16(reply[9])
        guard maximum > 0 else { return nil }
        return Reading(current: current, max: maximum)
    }

    /// 写 VCP。成功返回 true。
    @discardableResult
    func write(_ value: UInt16, displayID: CGDirectDisplayID, vcp: UInt8 = DDCBrightness.brightnessVCP) -> Bool {
        guard Self.writeFn != nil else { return false }
        guard let channel = channel(for: displayID) else { return false }

        var checksum = UInt8(0x6E ^ 0x51)
        var payload: [UInt8] = [0x84, 0x03, vcp, UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
        for byte in payload { checksum ^= byte }
        payload.append(checksum)

        var buffer = payload
        let result = Self.writeFn?(channel, 0x37, 0x51, &buffer, UInt32(buffer.count))
        if result != 0 {
            log.debug("DDC write failed: \(result ?? -1, privacy: .public)")
            markDead(displayID)
            return false
        }
        return true
    }

    /// 这块屏有没有可用 DDC 通道（探测一次，结果缓存）。
    func hasChannel(displayID: CGDirectDisplayID) -> Bool {
        channel(for: displayID) != nil
    }

    func invalidate(displayID: CGDirectDisplayID) {
        lock.lock()
        channelCache.removeValue(forKey: displayID)
        deadSince.removeValue(forKey: displayID)
        lock.unlock()
    }

    func invalidateAll() {
        lock.lock()
        channelCache.removeAll()
        deadSince.removeAll()
        lock.unlock()
    }

    // MARK: - 通道发现

    private func markDead(_ displayID: CGDirectDisplayID) {
        lock.lock()
        deadSince[displayID] = Date()
        channelCache.removeValue(forKey: displayID)
        lock.unlock()
    }

    private func channel(for displayID: CGDirectDisplayID) -> CFTypeRef? {
        lock.lock()
        if let cached = channelCache[displayID] {
            lock.unlock()
            return cached
        }
        if let since = deadSince[displayID], Date().timeIntervalSince(since) < retryInterval {
            lock.unlock()
            return nil
        }
        lock.unlock()

        guard let service = findAVService(for: displayID) else {
            markDead(displayID)
            return nil
        }
        lock.lock()
        channelCache[displayID] = service
        deadSince[displayID] = nil
        lock.unlock()
        return service
    }

    /// 沿 IOService 平面深度优先遍历：记住最近看到的显示器身份，
    /// 遇到外部 DDC 通道（DCPAVServiceProxy, Location = External）就和它配对。
    private func findAVService(for displayID: CGDirectDisplayID) -> CFTypeRef? {
        guard let create = Self.createFn else { return nil }
        let wantVendor = UInt32(CGDisplayVendorNumber(displayID))
        let wantProduct = UInt32(CGDisplayModelNumber(displayID))

        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        guard root != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(root) }

        var iterator: io_iterator_t = 0
        guard IORegistryEntryCreateIterator(
            root, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &iterator
        ) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        var lastVendor: UInt32 = 0
        var lastProduct: UInt32 = 0

        var entry = IOIteratorNext(iterator)
        while entry != IO_OBJECT_NULL {
            defer {
                IOObjectRelease(entry)
                entry = IOIteratorNext(iterator)
            }

            if let attributes = IORegistryEntryCreateCFProperty(
                entry, "DisplayAttributes" as CFString, kCFAllocatorDefault, 0
            )?.takeRetainedValue() as? [String: Any],
               let product = attributes["ProductAttributes"] as? [String: Any] {
                if let vendor = product["LegacyManufacturerID"] as? UInt32,
                   let pid = product["ProductID"] as? UInt32 {
                    lastVendor = vendor
                    lastProduct = pid
                }
            }

            guard ioClassName(of: entry) == "DCPAVServiceProxy" else { continue }
            let location = IORegistryEntryCreateCFProperty(
                entry, "Location" as CFString, kCFAllocatorDefault, 0
            )?.takeRetainedValue() as? String
            guard location == nil || location == "External" else { continue }
            guard lastVendor == wantVendor, lastProduct == wantProduct else { continue }
            guard let service = create(kCFAllocatorDefault, entry) else { continue }
            return service.takeRetainedValue()
        }
        return nil
    }

    private func ioClassName(of entry: io_registry_entry_t) -> String? {
        guard let name = IOObjectCopyClass(entry)?.takeRetainedValue() else { return nil }
        return name as String
    }
}
