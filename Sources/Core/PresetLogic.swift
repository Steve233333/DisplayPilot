import Foundation

/// 预设的纯逻辑（不碰 UserDefaults / 系统），方便单独测试。
enum PresetLogic {
    /// 可绑定的快捷键槽位数：⌥⌘1…3
    static let slotCount = 3

    /// 下一个空闲槽位；三个都占满时返回 nil。
    static func nextFreeSlot(in presets: [Preset]) -> Int? {
        let used = Set(presets.compactMap(\.hotkeySlot))
        return (0..<slotCount).first { !used.contains($0) }
    }

    /// 按槽位取预设（⌥⌘N 走这里，跟列表顺序无关）。
    static func preset(in presets: [Preset], forSlot slot: Int) -> Preset? {
        presets.first { $0.hotkeySlot == slot }
    }

    /// 把某个槽位指派给指定预设；原先占用该槽位的预设会被解除绑定。
    static func assigning(slot: Int?, to id: UUID, in presets: [Preset]) -> [Preset] {
        presets.map { preset in
            var copy = preset
            if copy.id == id {
                copy.hotkeySlot = slot
            } else if let slot, copy.hotkeySlot == slot {
                copy.hotkeySlot = nil
            }
            return copy
        }
    }

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

    /// 面板底部的展示顺序：先按槽位 0→2，未绑定的按原来顺序排在后面。
    static func displayOrder(_ presets: [Preset]) -> [Preset] {
        presets.enumerated()
            .sorted { lhs, rhs in
                let left = lhs.element.hotkeySlot ?? Int.max
                let right = rhs.element.hotkeySlot ?? Int.max
                return left == right ? lhs.offset < rhs.offset : left < right
            }
            .map(\.element)
    }
}
