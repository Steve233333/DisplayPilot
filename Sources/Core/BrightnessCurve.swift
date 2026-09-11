import Foundation

/// 亮度响应曲线：把滑杆的 0…1 换算成真正下发给后端的输出系数。
///
/// 伽马表/DCC 都是线性压亮度，但人眼对亮度的感受是接近 sRGB 的非线性，
/// 所以需要一条曲线把两者接起来。指数越大，低端压得越狠、高端每 1% 越敏感。
enum BrightnessCurve: String, Codable, CaseIterable, Sendable {
    /// 1:1，不做补偿。
    case linear
    /// 折中：低端不会一夜变黑，高端也不会一跳一大截。
    case gentle
    /// 感知补偿（≈sRGB），数字与眼睛感受最一致。
    case perceptual

    var exponent: Double {
        switch self {
        case .linear: return 1.0
        case .gentle: return 1.6
        case .perceptual: return 2.2
        }
    }

    var titleZH: String {
        switch self {
        case .linear: return "线性"
        case .gentle: return "柔和"
        case .perceptual: return "感知"
        }
    }

    var detailZH: String {
        switch self {
        case .linear: return "滑杆与输出 1:1，高端最细腻，但低端会偏亮（50% 看着像 70%）"
        case .gentle: return "推荐：低端不突兀，高端每 1% 也不会跳一大截"
        case .perceptual: return "数字与眼睛感受最一致，但靠近 100% 时每格的变化更明显"
        }
    }

    /// 缓动：让一次亮度变化在 0.2 秒内滑过去，而不是硬跳。
    static func eased(_ t: Double) -> Double {
        let clamped = min(max(t, 0), 1)
        return 1 - pow(1 - clamped, 2)   // ease-out quad
    }

    func factor(for level: Double) -> Double {
        let clamped = min(max(level, 0), 1)
        return pow(clamped, exponent)
    }
}
