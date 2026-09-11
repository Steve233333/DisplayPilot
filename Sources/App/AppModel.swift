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

@MainActor
@Observable
final class AppModel {
    // MARK: - 状态

    var displays: [DisplaySnapshot] = []
    var presets: [Preset] = []
    var status: StatusMessage?
    var isBusy = false
    var hasAccessibilityPermission = MediaKeyTap.hasAccessibilityPermission
    var launchAtLogin = LaunchAtLogin.isEnabled

    var mediaKeysEnabled: Bool
    var osdEnabled: Bool
    var ladderDensity: LadderDensity
    var hidpiOnlyChoices: Bool
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
        GlobalHotkeys.shared.onPreset = { [weak self] index in self?.applyPreset(at: index) }
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
    }

    private func applyMediaKeyState() {
        if mediaKeysEnabled {
            MediaKeyTap.shared.start()
        } else {
            MediaKeyTap.shared.stop()
        }
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
        let granted = MediaKeyTap.hasAccessibilityPermission
        let changed = granted != hasAccessibilityPermission
        hasAccessibilityPermission = granted
        guard granted, mediaKeysEnabled, !MediaKeyTap.shared.isRunning else { return }
        MediaKeyTap.shared.start()
        if changed { status = StatusMessage(text: "已获得辅助功能权限，F1/F2 亮度键已接管", kind: .success) }
    }

    func refreshPermissionNow() {
        refreshPermissionState()
    }

    // MARK: - 亮度

    func level(for snapshot: DisplaySnapshot) -> Double {
        brightness.level(for: snapshot)
    }

    func backend(for snapshot: DisplaySnapshot) -> BrightnessBackend {
        brightness.backend(for: snapshot)
    }

    func policy(for snapshot: DisplaySnapshot) -> BrightnessPolicy {
        brightness.policy(for: snapshot)
    }

    func setPolicy(_ policy: BrightnessPolicy, for snapshot: DisplaySnapshot) {
        brightness.setPolicy(policy, for: snapshot)
    }

    func setLevel(_ level: Double, for snapshot: DisplaySnapshot) {
        brightness.setLevel(level, for: snapshot)
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

    func savePreset(named name: String, from snapshot: DisplaySnapshot) {
        let preset = Preset(
            name: name,
            backingWidth: snapshot.currentMode?.backingWidth,
            backingHeight: snapshot.currentMode?.backingHeight,
            brightness: brightness.level(for: snapshot),
            hotkeySlot: presets.count < 3 ? presets.count : nil,
            displayUUID: snapshot.identity.uuid
        )
        presets.append(preset)
        settings.setPresets(presets)
        status = StatusMessage(text: "已保存预设 \(name)", kind: .success)
    }

    func deletePreset(_ preset: Preset) {
        presets.removeAll { $0.id == preset.id }
        settings.setPresets(presets)
    }

    func applyPreset(at index: Int) {
        guard index >= 0, index < presets.count else { return }
        applyPreset(presets[index])
    }

    func applyPreset(_ preset: Preset) {
        for snapshot in displays {
            if let uuid = preset.displayUUID, uuid != snapshot.identity.uuid { continue }
            if let width = preset.backingWidth, let height = preset.backingHeight {
                let choices = snapshot.scalingChoices(hidpiOnly: hidpiOnlyChoices)
                if let mode = choices.first(where: { $0.backingWidth == width && $0.backingHeight == height }) {
                    manager.setMode(mode, on: snapshot.displayID)
                }
            }
            if let level = preset.brightness {
                brightness.setLevel(level, for: snapshot)
            }
        }
        refreshDisplays()
        status = StatusMessage(text: "已应用预设 \(preset.name)", kind: .success)
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
