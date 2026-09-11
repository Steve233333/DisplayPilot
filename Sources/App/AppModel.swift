import AppKit
import CoreGraphics
import Foundation
import Observation
import os

struct StatusMessage: Identifiable, Equatable {
    enum Kind { case info, success, error }
    let id = UUID()
    var text: String
    var kind: Kind
}

/// 这块屏的平滑缩放档位状态。
enum ScalingStatus: Equatable {
    case installed
    case missing
    case unsupported(String)
}

/// 设置窗口的标签页（面板里的「管理预设…」会跳到对应页）。
enum SettingsTab: String, Hashable, CaseIterable {
    case general, displays, presets, shortcuts, permissions, about
}

@MainActor
@Observable
final class AppModel {
    // MARK: - 状态

    var displays: [DisplaySnapshot] = []
    var presets: [Preset] = []
    var status: StatusMessage?
    var isBusy = false
    var hasAccessibilityPermission = MediaKeyTap.hasAccessibilityPermission
    /// 事件 tap 是否真的装上了 —— 这才代表 F1/F2 接管生效。
    /// macOS 的 AXIsProcessTrusted() 对自制签名/重编译过的 App 经常误报，
    /// 所以「能不能建出 tap」才是唯一可信的判据。
    var mediaKeysActive = false
    var launchAtLogin = LaunchAtLogin.isEnabled
    /// 可观察的镜像状态：SwiftUI 只能观察 AppModel 自己的属性，
    /// 引擎里的字典（BrightnessController）改了它不知道 —— 之前滑块和数字
    /// 对不上就是这个原因。
    var levels: [String: Double] = [:]
    var backends: [String: BrightnessBackend] = [:]
    var limits: [String: BrightnessLimits] = [:]
    var scalingStatuses: [String: ScalingStatus] = [:]
    var settingsTab: SettingsTab = .general

    var mediaKeysEnabled: Bool
    var osdEnabled: Bool
    var ladderDensity: LadderDensity
    var hidpiOnlyChoices: Bool
    var brightnessCurve: BrightnessCurve
    var smoothBrightnessTransitions: Bool
    private var permissionTimer: Timer?

    func setMediaKeysEnabled(_ enabled: Bool) {
        mediaKeysEnabled = enabled
        settings.mediaKeysEnabled = enabled
        applyMediaKeyState()
    }

    func setOSDEnabled(_ enabled: Bool) {
        osdEnabled = enabled
        settings.osdEnabled = enabled
    }

    func setLadderDensity(_ density: LadderDensity) {
        ladderDensity = density
        settings.ladderDensity = density
    }

    func setHidpiOnly(_ enabled: Bool) {
        hidpiOnlyChoices = enabled
        settings.hidpiOnlyChoices = enabled
    }

    func setBrightnessCurve(_ curve: BrightnessCurve) {
        brightnessCurve = curve
        settings.curve = curve
        // 曲线变了立刻按当前滑杆位置重放一次，方便直接听/看效果。
        for snapshot in displays { brightness.setLevel(brightness.level(for: snapshot), for: snapshot, showOSD: false) }
    }

    func setSmoothBrightnessTransitions(_ enabled: Bool) {
        smoothBrightnessTransitions = enabled
        settings.smoothBrightnessTransitions = enabled
    }

    // MARK: - 依赖

    private let manager = DisplayManager.shared
    private let brightness = BrightnessController.shared
    private let settings = SettingsStore.shared
    private let installer = OverrideInstaller.shared
    private let log = Logger(subsystem: "com.steve233.DisplayPilot", category: "model")
    private var started = false

    init() {
        mediaKeysEnabled = settings.mediaKeysEnabled
        osdEnabled = settings.osdEnabled
        ladderDensity = settings.ladderDensity
        hidpiOnlyChoices = settings.hidpiOnlyChoices
        brightnessCurve = settings.curve
        smoothBrightnessTransitions = settings.smoothBrightnessTransitions
        presets = settings.presets()
    }

    // MARK: - 启动

    func start() {
        guard !started else { return }
        started = true

        SoftwareBrightness.shared.startObserving()
        refreshDisplays()
        settings.seedKnownDisplaysIfNeeded(displays)
        brightness.forgetResolvedBackends()
        brightness.refresh(displays)

        GlobalHotkeys.shared.onBrightnessUp = { [weak self] in self?.nudgeBrightness(+0.05) }
        GlobalHotkeys.shared.onBrightnessDown = { [weak self] in self?.nudgeBrightness(-0.05) }
        if settings.customHotkeysEnabled { GlobalHotkeys.shared.start() }

        MediaKeyTap.shared.onBrightnessUp = { [weak self] in self?.nudgeBrightness(+0.05) }
        MediaKeyTap.shared.onBrightnessDown = { [weak self] in self?.nudgeBrightness(-0.05) }
        applyMediaKeyState()
        startPermissionPolling()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshDisplays()
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                DDCBrightness.shared.invalidateAll()
                self?.refreshDisplays()
            }
        }
    }

    func refreshDisplays() {
        displays = manager.snapshots()
        brightness.refresh(displays)
        hasAccessibilityPermission = MediaKeyTap.hasAccessibilityPermission
        syncMirrors()
    }

    /// 把引擎里的状态同步到可观察属性。
    private func syncMirrors() {
        for snapshot in displays {
            let uuid = snapshot.identity.uuid
            levels[uuid] = brightness.level(for: snapshot)
            backends[uuid] = brightness.backend(for: snapshot)
            limits[uuid] = brightness.limits(for: snapshot)
            scalingStatuses[uuid] = computeScalingStatus(for: snapshot)
        }
    }

    private func computeScalingStatus(for snapshot: DisplaySnapshot) -> ScalingStatus {
        if snapshot.identity.isBuiltin {
            return .unsupported("内置屏幕不支持自定义缩放档位（macOS 会忽略它的 override）")
        }
        if snapshot.identity.vendorID == 0 || snapshot.identity.productID == 0 {
            return .unsupported("这块显示器没有报 vendor/product，写不了 override")
        }
        let native = manager.panelNativeResolution(for: snapshot.displayID)
        let expected = OverrideFile.generate(identity: snapshot.identity, native: native, density: ladderDensity)
        return expected.matches() ? .installed : .missing
    }

    private func applyMediaKeyState() {
        if mediaKeysEnabled {
            MediaKeyTap.shared.start()
        } else {
            MediaKeyTap.shared.stop()
        }
        mediaKeysActive = MediaKeyTap.shared.isRunning
        log.notice("media keys: enabled=\(self.mediaKeysEnabled, privacy: .public) tap=\(self.mediaKeysActive, privacy: .public) axTrusted=\(MediaKeyTap.hasAccessibilityPermission, privacy: .public)")
    }

    /// 系统设置的辅助功能开关是随时可变的，App 必须自己轮询：
    /// 授权后立刻把事件 tap 装上，并撤掉那条橙色横幅。
    private func startPermissionPolling() {
        permissionTimer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshPermissionState() }
        }
        RunLoop.main.add(timer, forMode: .common)
        permissionTimer = timer
    }

    func refreshPermissionState() {
        let wasActive = mediaKeysActive
        // 只要 tap 没装上就重试一次（授权后无需重启 App 就能接管）。
        if mediaKeysEnabled, !MediaKeyTap.shared.isRunning {
            MediaKeyTap.shared.start()
        }
        mediaKeysActive = MediaKeyTap.shared.isRunning
        hasAccessibilityPermission = MediaKeyTap.hasAccessibilityPermission || mediaKeysActive
        if mediaKeysActive, !wasActive {
            status = StatusMessage(text: "F1/F2 亮度键已接管", kind: .success)
            log.notice("media key tap armed (axTrusted=\(MediaKeyTap.hasAccessibilityPermission, privacy: .public))")
        }
    }

    func refreshPermissionNow() {
        refreshPermissionState()
    }

    // MARK: - 亮度

    func level(for snapshot: DisplaySnapshot) -> Double {
        levels[snapshot.identity.uuid] ?? brightness.level(for: snapshot)
    }

    func backend(for snapshot: DisplaySnapshot) -> BrightnessBackend {
        backends[snapshot.identity.uuid] ?? brightness.backend(for: snapshot)
    }

    /// 软件调光机制：无线屏是覆盖层，普通屏是伽马表。
    func softwareStrategyTitle(for snapshot: DisplaySnapshot) -> String {
        brightness.softwareStrategy(for: snapshot) == .overlay ? "软件调光 · 覆盖层" : "软件调光"
    }

    func policy(for snapshot: DisplaySnapshot) -> BrightnessPolicy {
        brightness.policy(for: snapshot)
    }

    func setPolicy(_ policy: BrightnessPolicy, for snapshot: DisplaySnapshot) {
        brightness.setPolicy(policy, for: snapshot)
    }

    func setLevel(_ level: Double, for snapshot: DisplaySnapshot) {
        brightness.setLevel(level, for: snapshot)
        levels[snapshot.identity.uuid] = min(max(level, 0), 1)
        backends[snapshot.identity.uuid] = brightness.backend(for: snapshot)
    }

    func limits(for snapshot: DisplaySnapshot) -> BrightnessLimits {
        limits[snapshot.identity.uuid] ?? brightness.limits(for: snapshot)
    }

    func setLimits(_ newLimits: BrightnessLimits, for snapshot: DisplaySnapshot) {
        let normalized = BrightnessLimits(
            minimum: min(max(newLimits.minimum, 0), 0.98),
            maximum: min(max(newLimits.maximum, newLimits.minimum + 0.02), 1)
        )
        brightness.setLimits(normalized, for: snapshot)
        limits[snapshot.identity.uuid] = normalized
        levels[snapshot.identity.uuid] = brightness.level(for: snapshot)
    }

    func scalingStatus(for snapshot: DisplaySnapshot) -> ScalingStatus {
        scalingStatuses[snapshot.identity.uuid] ?? computeScalingStatus(for: snapshot)
    }

    func nudgeBrightness(_ delta: Double) {
        guard let target = brightness.targetSnapshot(from: displays) else { return }
        brightness.nudge(delta, for: target)
    }

    // MARK: - 缩放

    func currentMode(for snapshot: DisplaySnapshot) -> ScaledMode? {
        snapshot.currentMode
    }

    func setMode(_ mode: ScaledMode, for snapshot: DisplaySnapshot) {
        if manager.setMode(mode, on: snapshot.displayID) {
            status = StatusMessage(text: "已切换到 \(mode.label)", kind: .success)
            refreshDisplays()
        } else {
            status = StatusMessage(text: "切换分辨率失败：\(mode.label)", kind: .error)
        }
    }

    /// 写入 override 并让系统立刻重新识别（不需要重启）。
    func installScalingLadder(for snapshot: DisplaySnapshot) {
        guard !isBusy else { return }
        guard !snapshot.identity.isBuiltin else {
            status = StatusMessage(text: "内置屏幕不支持自定义缩放档位（macOS 会忽略它的 override）", kind: .error)
            return
        }
        guard snapshot.identity.vendorID != 0, snapshot.identity.productID != 0 else {
            status = StatusMessage(text: "这块显示器没有可用的 vendor/product，无法写 override", kind: .error)
            return
        }
        isBusy = true
        status = StatusMessage(text: L10n.t("正在写入系统配置…"), kind: .info)

        let identity = snapshot.identity
        let native = manager.panelNativeResolution(for: snapshot.displayID)
        let density = ladderDensity
        let expectedLadder = density == .full
            ? OverrideFile.ladder(nativeWidth: native.width, nativeHeight: native.height)
            : OverrideFile.compactLadder(nativeWidth: native.width, nativeHeight: native.height)
        let expectedBackings = Set(expectedLadder.map { "\($0.backingWidth)x\($0.backingHeight)" })
        let displayID = snapshot.displayID

        Task.detached(priority: .userInitiated) { [installer] in
            var message = StatusMessage(text: L10n.t("档位已就绪"), kind: .success)
            do {
                let file = OverrideFile.generate(identity: identity, native: native, density: density)
                try installer.install(file)
                DisplayReprobe.request(identity: identity)
                try? await Task.sleep(nanoseconds: 900_000_000)

                // 校验：系统真的把新档位列出来了吗？（某些显示器/KVM 需要拔插线）
                let observed = await MainActor.run {
                    Set(DisplayManager.shared.modes(for: displayID).map { "\($0.backingWidth)x\($0.backingHeight)" })
                }
                if expectedBackings.isDisjoint(with: observed) {
                    message = StatusMessage(
                        text: "已写入配置，但系统还没列出新档位：请拔插一次显示器连线，或重启后再试",
                        kind: .error
                    )
                }
            } catch {
                message = StatusMessage(text: error.localizedDescription, kind: .error)
            }
            await MainActor.run {
                self.isBusy = false
                self.status = message
                self.refreshDisplays()
            }
        }
    }

    func restoreNativeModes(for snapshot: DisplaySnapshot) {
        guard !isBusy else { return }
        isBusy = true
        let identity = snapshot.identity

        Task.detached(priority: .userInitiated) { [installer] in
            var message = StatusMessage(text: L10n.t("已还原为系统原生模式表"), kind: .success)
            do {
                try installer.restore(identity: identity)
                DisplayReprobe.request(identity: identity)
                try? await Task.sleep(nanoseconds: 900_000_000)
            } catch {
                message = StatusMessage(text: error.localizedDescription, kind: .error)
            }
            await MainActor.run {
                self.isBusy = false
                self.status = message
                self.refreshDisplays()
            }
        }
    }

    func reprobe(_ snapshot: DisplaySnapshot) {
        DisplayReprobe.request(identity: snapshot.identity)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            refreshDisplays()
            status = StatusMessage(text: L10n.t("档位已就绪"), kind: .success)
        }
    }

    // MARK: - 预设

    /// 保存当前状态为新预设：分辨率 + 亮度 + 绑定这块显示器。
    func savePreset(named name: String, from snapshot: DisplaySnapshot) {
        let preset = Preset(
            name: name,
            backingWidth: snapshot.currentMode?.backingWidth,
            backingHeight: snapshot.currentMode?.backingHeight,
            brightness: brightness.level(for: snapshot),
            displayUUID: snapshot.identity.uuid
        )
        presets.append(preset)
        settings.setPresets(presets)
        status = StatusMessage(text: "已保存预设 \(name)", kind: .success)
    }

    func deletePreset(_ preset: Preset) {
        presets.removeAll { $0.id == preset.id }
        settings.setPresets(presets)
        status = StatusMessage(text: "已删除预设 \(preset.name)", kind: .success)
    }

    func renamePreset(_ preset: Preset, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = presets.firstIndex(where: { $0.id == preset.id }) else { return }
        presets[index].name = trimmed
        settings.setPresets(presets)
    }

    /// 用当前状态覆盖预设（改分辨率/亮度后想更新原预设时用）。
    @discardableResult
    func updatePresetWithCurrent(_ preset: Preset) -> Bool {
        guard let snapshot = targetSnapshot(for: preset) else {
            status = StatusMessage(text: "找不到预设绑定的显示器（可能未连接）", kind: .error)
            return false
        }
        let level = brightness.level(for: snapshot)
        let updated = PresetLogic.updating(preset, mode: snapshot.currentMode, brightness: level)
        guard let index = presets.firstIndex(where: { $0.id == preset.id }) else { return false }
        presets[index] = updated
        settings.setPresets(presets)
        status = StatusMessage(text: "已用当前状态更新「\(preset.name)」", kind: .success)
        return true
    }

    /// 更换预设绑定的显示器。
    func rebind(_ preset: Preset, to snapshot: DisplaySnapshot?) {
        guard let index = presets.firstIndex(where: { $0.id == preset.id }) else { return }
        presets[index].displayUUID = snapshot?.identity.uuid
        settings.setPresets(presets)
    }

    func movePreset(_ preset: Preset, by offset: Int) {
        presets = PresetLogic.moving(id: preset.id, by: offset, in: presets)
        settings.setPresets(presets)
    }

    func applyPreset(_ preset: Preset) {
        let targets = displays.filter { snapshot in
            guard let uuid = preset.displayUUID else { return true }
            return uuid == snapshot.identity.uuid
        }
        guard !targets.isEmpty else {
            status = StatusMessage(text: "「\(preset.name)」绑定的显示器当前未连接", kind: .error)
            return
        }
        for snapshot in targets {
            if let width = preset.backingWidth, let height = preset.backingHeight {
                // 先用「全部档位」找，找不到再用当前的过滤条件找，避免因为 HiDPI 过滤而失效。
                let all = snapshot.scalingChoices(hidpiOnly: false, aspectTolerant: false)
                let filtered = snapshot.scalingChoices(hidpiOnly: hidpiOnlyChoices)
                let mode = all.first { $0.backingWidth == width && $0.backingHeight == height }
                    ?? filtered.first { $0.backingWidth == width && $0.backingHeight == height }
                if let mode { manager.setMode(mode, on: snapshot.displayID) }
            }
            if let level = preset.brightness {
                brightness.setLevel(level, for: snapshot)
            }
        }
        refreshDisplays()
        status = StatusMessage(text: "已应用预设 \(preset.name)", kind: .success)
    }

    /// 预设要作用的显示器快照（用于「更新为当前」）。
    private func targetSnapshot(for preset: Preset) -> DisplaySnapshot? {
        if let uuid = preset.displayUUID {
            return displays.first { $0.identity.uuid == uuid }
        }
        return displays.first(where: \.isMain) ?? displays.first
    }

    /// 在设置里管理预设时用来创建新预设：默认取主屏。
    var primarySnapshot: DisplaySnapshot? {
        displays.first(where: \.isMain) ?? displays.first
    }

    // MARK: - 权限 / 开机自启

    func requestAccessibilityPermission() {
        MediaKeyTap.requestAccessibilityPermission()
        status = StatusMessage(text: "请在「系统设置 → 隐私与安全性 → 辅助功能」里勾选 DisplayPilot，然后重启 App", kind: .info)
    }

    func toggleLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLogin.set(enabled)
            launchAtLogin = LaunchAtLogin.isEnabled
            status = StatusMessage(text: enabled ? "已设置开机自启" : "已关闭开机自启", kind: .success)
        } catch {
            launchAtLogin = LaunchAtLogin.isEnabled
            status = StatusMessage(text: error.localizedDescription, kind: .error)
        }
    }

    func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    func quit() {
        SoftwareBrightness.shared.restoreAll()
        NSApplication.shared.terminate(nil)
    }
}
