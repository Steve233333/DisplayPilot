import CoreGraphics
import Foundation
import IOKit

/// 让 WindowServer 重新读取某块显示器的 EDID / override，
/// 这样新写入的缩放档位不需要重启、也不需要拔线就能立刻出现。
enum DisplayReprobe {
    @discardableResult
    static func request(identity: DisplayIdentity) -> Bool {
        request(vendorID: identity.vendorID, productID: identity.productID)
    }

    @discardableResult
    static func request(vendorID: UInt32, productID: UInt32) -> Bool {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IODisplayConnect"), &iterator) == KERN_SUCCESS else {
            return false
        }
        defer { IOObjectRelease(iterator) }

        var probed = false
        var service = IOIteratorNext(iterator)
        while service != IO_OBJECT_NULL {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            guard let cfDict = IODisplayCreateInfoDictionary(service, IOOptionBits(kIODisplayOnlyPreferredName))?.takeRetainedValue(),
                  let dict = cfDict as? [String: Any]
            else { continue }

            let serviceVendor = (dict["DisplayVendorID"] as? UInt32)
                ?? (dict["DisplayVendorID"] as? Int).map { UInt32(bitPattern: Int32(truncatingIfNeeded: $0)) }
            let serviceProduct = (dict["DisplayProductID"] as? UInt32)
                ?? (dict["DisplayProductID"] as? Int).map { UInt32(bitPattern: Int32(truncatingIfNeeded: $0)) }

            guard serviceVendor == vendorID, serviceProduct == productID else { continue }
            IOServiceRequestProbe(service, 0)
            probed = true
            break
        }
        return probed
    }
}
