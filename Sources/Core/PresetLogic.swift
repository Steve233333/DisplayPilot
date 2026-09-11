import Foundation

/// 预设的纯逻辑（不碰 UserDefaults / 系统），方便单独测试。
enum PresetLogic {
    /// 上移（offset = -1）或下移（offset = +1）。
    static func moving(id: UUID, by offset: Int, in presets: [Preset]) -> [Preset] {
        guard let index = presets.firstIndex(where: { $0.id == id }) else { return presets }
        let target = index + offset
        guard presets.indices.contains(target) else { return presets }
        var copy = presets
        copy.swapAt(index, target)
        return copy
    }

    /// 用当前状态覆盖预设的分辨率与亮度（名字、槽位、绑定屏保持不变）。
    static func updating(_ preset: Preset, mode: ScaledMode?, brightness: Double) -> Preset {
        var copy = preset
        copy.backingWidth = mode?.backingWidth
        copy.backingHeight = mode?.backingHeight
        copy.brightness = brightness
        return copy
    }

}
