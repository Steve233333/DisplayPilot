import CoreGraphics
import Foundation

/// 一块物理显示器的稳定身份。
/// uuid 优先取 ColorSync/IOKit 的显示器 UUID（跨重连稳定），失败时退化为 vendor-product。
struct DisplayIdentity: Hashable, Codable, Sendable {
    var uuid: String
    var vendorID: UInt32
    var productID: UInt32
    var name: String
    var isBuiltin: Bool

    var vendorHex: String { String(format: "%04x", vendorID) }
    var productHex: String { String(format: "%04x", productID) }
}

/// 一个显示模式：backing = GPU 实际渲染像素，logical = “看起来多大”（点数）。
struct ScaledMode: Hashable, Codable, Sendable, Identifiable {
    var logicalWidth: Int
    var logicalHeight: Int
    var backingWidth: Int
    var backingHeight: Int
    var refresh: Double

    var id: String { "\(backingWidth)x\(backingHeight)-\(logicalWidth)x\(logicalHeight)-\(Int(refresh.rounded()))" }
    var isHiDPI: Bool { backingWidth != logicalWidth || backingHeight != logicalHeight }
    var label: String { "\(logicalWidth) × \(logicalHeight)" }
    var scaleFactor: Double { logicalWidth > 0 ? Double(backingWidth) / Double(logicalWidth) : 1 }

    var detail: String {
        isHiDPI
            ? "渲染 \(backingWidth)×\(backingHeight) · 缩放 \(String(format: "%.2f", scaleFactor))×"
            : "原生 \(backingWidth)×\(backingHeight)"
    }
}

/// 每块显示器各自的亮度后端策略。
enum BrightnessPolicy: String, Codable, CaseIterable, Sendable {
    /// 每个会话探测一次 DDC：能用就走硬件，否则走软件。
    case automatic
    /// 强制硬件（DDC/CI）。DCR 模式下可能闪烁。
    case hardware
    /// 强制软件调光（伽马表），不碰显示器背光。
    case software

    var titleZH: String {
        switch self {
        case .automatic: return "自动"
        case .hardware: return "强制硬件"
        case .software: return "强制软件"
        }
    }
}

enum BrightnessBackend: String, Codable, Sendable {
    case hardware
    case software

    var titleZH: String {
        switch self {
        case .hardware: return "硬件 DDC"
        case .software: return "软件调光"
        }
    }
}

/// 一键预设：分辨率 + 亮度，可绑定 ⌥⌘1…3。
struct Preset: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var name: String
    var backingWidth: Int?
    var backingHeight: Int?
    var brightness: Double?
    var displayUUID: String?

    var summary: String {
        var parts: [String] = []
        if let w = backingWidth, let h = backingHeight { parts.append("\(w)×\(h)") }
        if let b = brightness { parts.append("亮度 \(Int((b * 100).rounded()))%") }
        return parts.isEmpty ? "空预设" : parts.joined(separator: " · ")
    }
}

/// 柔性缩放的档位密度。
enum LadderDensity: String, Codable, CaseIterable, Sendable {
    /// BetterDisplay 同款等距梯：原生宽 16 点一档直到 50%。
    case full
    /// 只保留几个常用档位。
    case compact

    var titleZH: String {
        switch self {
        case .full: return "平滑（61 档）"
        case .compact: return "精简（6 档）"
        }
    }
}
