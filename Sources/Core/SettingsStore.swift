import Foundation

/// 每块屏的亮度可用区间：滑杆上的 0%～100% 映射到 [minimum, maximum]。
struct BrightnessLimits: Codable, Hashable, Sendable {
    var minimum: Double = 0
    var maximum: Double = 1

    var isDefault: Bool { abs(minimum) < 0.001 && abs(maximum - 1) < 0.001 }
    var rangeText: String { "\(Int((minimum * 100).rounded()))% – \(Int((maximum * 100).rounded()))%" }

    static func clamp(_ value: Double) -> Double { Swift.min(Swift.max(value, 0), 1) }

    /// 滑杆值（0…1）→ 实际输出亮度。
    func output(for slider: Double) -> Double {
        minimum + Self.clamp(slider) * (maximum - minimum)
    }

    /// 实际输出亮度 → 滑杆值（用来把显示器的真实亮度映射回滑杆位置）。
    func sliderValue(for output: Double) -> Double {
        guard maximum - minimum > 0.0001 else { return 0 }
        return Self.clamp((output - minimum) / (maximum - minimum))
    }
}

/// 所有持久化状态（UserDefaults）：每屏亮度、每屏策略、预设、开关。
final class SettingsStore {
    static let shared = SettingsStore()

    private let defaults = UserDefaults.standard
    private enum Key {
        static let levels = "levels"                 // [uuid: Double]
        static let policies = "policies"             // [uuid: BrightnessPolicy.rawValue]
        static let presets = "presets"               // JSON
        static let density = "ladderDensity"
        static let mediaKeys = "mediaKeysEnabled"
        static let osd = "osdEnabled"
        static let customHotkeys = "customHotkeysEnabled"
        static let seeded = "didSeedKnownDisplays"
        static let hasLaunched = "hasLaunchedBefore"
        static let hidpiOnly = "hidpiOnlyChoices"
        static let limits = "brightnessLimits"
        static let brightnessCurve = "brightnessCurve"
        static let smoothTransitions = "smoothBrightnessTransitions"
    }

    private init() {}

    // MARK: - 首次运行

    /// 已知机型怪癖表（数据驱动，不是给某一台机器写死的逻辑）。
    /// 这些显示器在 DCR 模式下会被 DDC 写背光干扰而闪烁，所以首次运行
    /// 预置成"软件调光"；用户随时可以在面板/设置里改回来，改过就记住。
    /// 只有 vendor+product 完全命中才会生效，别人的显示器不受影响。
    static let knownQuirks: [(vendor: UInt32, product: UInt32, note: String)] = [
        (19083, 8817, "RTK 1920×1200 面板：DCR 模式下 DDC 调光会闪，默认软件调光"),
    ]

    /// 首次运行时套用已知机型怪癖。
    func seedKnownDisplaysIfNeeded(_ snapshots: [DisplaySnapshot]) {
        if defaults.bool(forKey: Key.seeded) { return }
        var policies = storedPolicies()
        for snapshot in snapshots {
            let identity = snapshot.identity
            let matched = Self.knownQuirks.contains {
                $0.vendor == identity.vendorID && $0.product == identity.productID
            }
            if matched {
                policies[identity.uuid] = BrightnessPolicy.software.rawValue
                // 软件调光从"不压暗"起步，避免一上来就把画面变暗。
                setLevel(1.0, for: identity.uuid)
            }
        }
        store(policies: policies)
        defaults.set(true, forKey: Key.seeded)
        defaults.set(true, forKey: Key.hasLaunched)
    }

    var hasLaunchedBefore: Bool {
        defaults.bool(forKey: Key.hasLaunched)
    }

    // MARK: - 亮度 / 策略

    func level(for uuid: String) -> Double? {
        (defaults.dictionary(forKey: Key.levels) as? [String: Double])?[uuid]
    }

    func setLevel(_ level: Double, for uuid: String) {
        var levels = (defaults.dictionary(forKey: Key.levels) as? [String: Double]) ?? [:]
        levels[uuid] = level
        defaults.set(levels, forKey: Key.levels)
    }

    func policy(for uuid: String) -> BrightnessPolicy {
        storedPolicies()[uuid].flatMap(BrightnessPolicy.init(rawValue:)) ?? .automatic
    }

    func setPolicy(_ policy: BrightnessPolicy, for uuid: String) {
        var policies = storedPolicies()
        policies[uuid] = policy.rawValue
        store(policies: policies)
    }

    private func storedPolicies() -> [String: String] {
        (defaults.dictionary(forKey: Key.policies) as? [String: String]) ?? [:]
    }

    private func store(policies: [String: String]) {
        defaults.set(policies, forKey: Key.policies)
    }

    var allPolicies: [String: BrightnessPolicy] {
        storedPolicies().compactMapValues(BrightnessPolicy.init(rawValue:))
    }

    // MARK: - 预设

    func presets() -> [Preset] {
        guard let data = defaults.data(forKey: Key.presets),
              let list = try? JSONDecoder().decode([Preset].self, from: data)
        else { return [] }
        return list
    }

    func setPresets(_ presets: [Preset]) {
        guard let data = try? JSONEncoder().encode(presets) else { return }
        defaults.set(data, forKey: Key.presets)
    }

    // MARK: - 开关

    var ladderDensity: LadderDensity {
        get { LadderDensity(rawValue: defaults.string(forKey: Key.density) ?? "") ?? .full }
        set { defaults.set(newValue.rawValue, forKey: Key.density) }
    }

    var mediaKeysEnabled: Bool {
        get { defaults.object(forKey: Key.mediaKeys) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.mediaKeys) }
    }

    var osdEnabled: Bool {
        get { defaults.object(forKey: Key.osd) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.osd) }
    }

    var customHotkeysEnabled: Bool {
        get { defaults.object(forKey: Key.customHotkeys) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.customHotkeys) }
    }

    /// 分辨率滑杆是否只显示 HiDPI 档位（默认开，避免选到模糊的 1×）。
    var hidpiOnlyChoices: Bool {
        get { defaults.object(forKey: Key.hidpiOnly) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.hidpiOnly) }
    }

    // MARK: - 亮度区间

    func limits(for uuid: String) -> BrightnessLimits {
        allLimits()[uuid] ?? BrightnessLimits()
    }

    func setLimits(_ limits: BrightnessLimits, for uuid: String) {
        var map = allLimits()
        map[uuid] = limits
        if let data = try? JSONEncoder().encode(map) {
            defaults.set(data, forKey: Key.limits)
        }
    }

    func allLimits() -> [String: BrightnessLimits] {
        guard let data = defaults.data(forKey: Key.limits),
              let map = try? JSONDecoder().decode([String: BrightnessLimits].self, from: data)
        else { return [:] }
        return map
    }

    // MARK: - 亮度曲线 / 过渡

    /// 亮度响应曲线（默认「柔和」，比原来的感知曲线在高端更细腻）。
    var curve: BrightnessCurve {
        get { BrightnessCurve(rawValue: defaults.string(forKey: Key.brightnessCurve) ?? "") ?? .gentle }
        set { defaults.set(newValue.rawValue, forKey: Key.brightnessCurve) }
    }

    /// 亮度变化是否做 0.2 秒缓动（默认开）。
    var smoothBrightnessTransitions: Bool {
        get { defaults.object(forKey: Key.smoothTransitions) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.smoothTransitions) }
    }
}
