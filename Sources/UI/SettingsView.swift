import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var newPresetName = ""
    @State private var newPresetDisplayUUID: String?

    var body: some View {
        TabView(selection: Binding(
            get: { model.settingsTab },
            set: { model.settingsTab = $0 }
        )) {
            generalTab
                .tabItem { Label(L10n.t("通用"), systemImage: "gearshape") }
                .tag(SettingsTab.general)
            displaysTab
                .tabItem { Label(L10n.t("显示"), systemImage: "display") }
                .tag(SettingsTab.displays)
            presetsTab
                .tabItem { Label(L10n.t("预设"), systemImage: "star") }
                .tag(SettingsTab.presets)
            shortcutsTab
                .tabItem { Label(L10n.t("快捷键"), systemImage: "keyboard") }
                .tag(SettingsTab.shortcuts)
            permissionsTab
                .tabItem { Label(L10n.t("权限"), systemImage: "lock.shield") }
                .tag(SettingsTab.permissions)
            aboutTab
                .tabItem { Label(L10n.t("关于"), systemImage: "info.circle") }
                .tag(SettingsTab.about)
        }
        .frame(width: 560, height: 420)
        .padding(16)
    }

    // MARK: - 通用

    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle(L10n.t("开机自启"), isOn: Binding(
                get: { model.launchAtLogin },
                set: { model.toggleLaunchAtLogin($0) }
            ))
            Toggle(L10n.t("显示 OSD"), isOn: Binding(
                get: { model.osdEnabled },
                set: { model.setOSDEnabled($0) }
            ))
            Picker(L10n.t("档位密度"), selection: Binding(
                get: { model.ladderDensity },
                set: { model.setLadderDensity($0) }
            )) {
                Text(L10n.t("平滑（61 档）")).tag(LadderDensity.full)
                Text(L10n.t("精简（6 档）")).tag(LadderDensity.compact)
            }
            .pickerStyle(.segmented)
            Toggle("分辨率列表只显示 HiDPI 档位", isOn: Binding(
                get: { model.hidpiOnlyChoices },
                set: { model.setHidpiOnly($0) }
            ))
            Divider().opacity(0.5)
            VStack(alignment: .leading, spacing: 6) {
                Text("亮度曲线").font(.system(size: 11, weight: .medium))
                Picker("", selection: Binding(
                    get: { model.brightnessCurve },
                    set: { model.setBrightnessCurve($0) }
                )) {
                    ForEach(BrightnessCurve.allCases, id: \.self) { curve in
                        Text(curve.titleZH).tag(curve)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                Text(model.brightnessCurve.detailZH)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Toggle("亮度过渡动画（约 0.2 秒缓动，避免硬跳）", isOn: Binding(
                get: { model.smoothBrightnessTransitions },
                set: { model.setSmoothBrightnessTransitions($0) }
            ))
            Text("平滑档位会写进显示器 override 文件（需要一次管理员密码）；系统设置 → 显示器里会多出这些档位，属正常现象。")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.top, 8)
    }

    // MARK: - 显示

    private var displaysTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if model.displays.isEmpty {
                    Text(L10n.t("没有检测到显示器")).foregroundStyle(.secondary)
                }
                ForEach(model.displays) { snapshot in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(snapshot.identity.name).font(.system(size: 12, weight: .semibold))
                            Spacer()
                            Badge(text: "\(snapshot.nativeResolution.width)×\(snapshot.nativeResolution.height)", tint: .secondary)
                        }
                        HStack(spacing: 8) {
                            Text(L10n.t("亮度后端"))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Picker("", selection: Binding(
                                get: { model.policy(for: snapshot) },
                                set: { model.setPolicy($0, for: snapshot) }
                            )) {
                                Text(L10n.t("自动")).tag(BrightnessPolicy.automatic)
                                Text(L10n.t("强制硬件")).tag(BrightnessPolicy.hardware)
                                Text(L10n.t("强制软件")).tag(BrightnessPolicy.software)
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(width: 260)
                            Spacer()
                            Badge(text: model.backend(for: snapshot) == .hardware
                                  ? model.backend(for: snapshot).titleZH
                                  : model.softwareStrategyTitle(for: snapshot),
                                  tint: model.backend(for: snapshot) == .hardware ? .green : .orange)
                        }
                        Text("vendor \(snapshot.identity.vendorHex) · product \(snapshot.identity.productHex)")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.3)))
                }
            }
            .padding(.top, 8)
        }
    }

    // MARK: - 预设

    private var presetsTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                TextField("新预设名称", text: $newPresetName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 190)
                Picker("", selection: $newPresetDisplayUUID) {
                    Text("所有显示器").tag(String?.none)
                    ForEach(model.displays) { snapshot in
                        Text(snapshot.identity.name).tag(String?.some(snapshot.identity.uuid))
                    }
                }
                .labelsHidden()
                .frame(width: 200)
                Button("保存当前为预设") {
                    let target = model.displays.first { $0.identity.uuid == newPresetDisplayUUID }
                        ?? model.primarySnapshot
                    if let target {
                        let name = newPresetName.trimmingCharacters(in: .whitespacesAndNewlines)
                        model.savePreset(named: name.isEmpty ? "预设 \(model.presets.count + 1)" : name, from: target)
                        newPresetName = ""
                    }
                }
                .disabled(model.primarySnapshot == nil)
                Spacer()
            }

            if model.presets.isEmpty {
                VStack(spacing: 6) {
                    OcticonImage(name: "star", size: 20).foregroundStyle(.tertiary)
                    Text("还没有预设")
                        .font(.system(size: 12, weight: .medium))
                    Text("在面板的显示器卡片里点 ☆ 存当前状态，或直接用上面的输入框；保存后可在这里改名字、换绑屏、更新参数、排序。")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 380)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(Array(model.presets.enumerated()), id: \.element.id) { index, preset in
                            presetRow(preset, index: index)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 8)
    }

    private func presetRow(_ preset: Preset, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                OcticonImage(name: "star", size: 11).foregroundStyle(.secondary)
                TextField("名称", text: Binding(
                    get: { preset.name },
                    set: { model.renamePreset(preset, to: $0) }
                ))
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 150)

                Menu {
                    Button("所有显示器") { model.rebind(preset, to: nil) }
                    Divider()
                    ForEach(model.displays) { snapshot in
                        Button(snapshot.identity.name) { model.rebind(preset, to: snapshot) }
                    }
                } label: {
                    Badge(text: displayName(for: preset), tint: .secondary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()

                Spacer()

                Button { model.movePreset(preset, by: -1) } label: { OcticonImage(name: "arrow-up", size: 11) }
                    .buttonStyle(.plain)
                    .disabled(index == 0)
                Button { model.movePreset(preset, by: 1) } label: { OcticonImage(name: "arrow-down", size: 11) }
                    .buttonStyle(.plain)
                    .disabled(index == model.presets.count - 1)
            }

            HStack(spacing: 8) {
                Text(preset.summary)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("应用") { model.applyPreset(preset) }
                    .controlSize(.small)
                Button("用当前状态更新") { model.updatePresetWithCurrent(preset) }
                    .controlSize(.small)
                Button("删除", role: .destructive) { model.deletePreset(preset) }
                    .controlSize(.small)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.3)))
    }

    private func displayName(for preset: Preset) -> String {
        guard let uuid = preset.displayUUID else { return "所有显示器" }
        return model.displays.first { $0.identity.uuid == uuid }?.identity.name ?? "未连接"
    }

    // MARK: - 快捷键

    private var shortcutsTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(L10n.t("接管 F1/F2 亮度键"), isOn: Binding(
                get: { model.mediaKeysEnabled },
                set: { model.setMediaKeysEnabled($0) }
            ))
            Text("需要辅助功能权限；没有权限时会自动回退到下面的自定快捷键。")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Divider()
            shortcutRow("⌥⌘↑", "亮度 +5%")
            shortcutRow("⌥⌘↓", "亮度 −5%")
            Text("预设故意不占快捷键：从面板底部点选，或到「预设」页管理。")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.top, 8)
    }

    private func shortcutRow(_ keys: String, _ description: String) -> some View {
        HStack {
            Text(keys)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 5).fill(.quaternary.opacity(0.5)))
            Text(description).font(.system(size: 11))
            Spacer()
        }
    }

    // MARK: - 权限 / 关于

    private var permissionsTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                OcticonImage(name: model.mediaKeysActive ? "check-circle" : "x-circle", size: 14)
                    .foregroundStyle(model.mediaKeysActive ? .green : .red)
                Text(model.mediaKeysActive
                     ? "F1/F2 已接管（事件 tap 运行中）"
                     : (model.hasAccessibilityPermission ? "权限已授予，正在重试接管…" : L10n.t("需要辅助功能权限")))
                    .font(.system(size: 12, weight: .medium))
            }
            Text("辅助功能权限只用于接管 F1/F2 亮度键。调整亮度和分辨率本身不需要任何权限；写入平滑缩放档位需要一次管理员密码（系统弹窗）。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(L10n.t("去授权")) { model.requestAccessibilityPermission() }
                Button("打开系统设置") { model.openAccessibilitySettings() }
            }
            Spacer()
        }
        .padding(.top, 8)
    }

    private var aboutTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("DisplayPilot \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                .font(.system(size: 13, weight: .semibold))
            Text("自用的 macOS 显示器工具：柔性 HiDPI 缩放 + 软件/硬件亮度。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(L10n.t("Icons: GitHub Octicons (MIT)"))
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Text("DDC/CI 与媒体键部分的实现参考了 Crisp（MIT），详见仓库 THIRD_PARTY_NOTICES.md。")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.top, 8)
    }
}
