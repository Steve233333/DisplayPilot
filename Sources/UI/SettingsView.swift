import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label(L10n.t("通用"), systemImage: "gearshape") }
            displaysTab
                .tabItem { Label(L10n.t("显示"), systemImage: "display") }
            shortcutsTab
                .tabItem { Label(L10n.t("快捷键"), systemImage: "keyboard") }
            permissionsTab
                .tabItem { Label(L10n.t("权限"), systemImage: "lock.shield") }
            aboutTab
                .tabItem { Label(L10n.t("关于"), systemImage: "info.circle") }
        }
        .frame(width: 520, height: 380)
        .padding(16)
    }

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
            Text("平滑档位会写进显示器 override 文件（需要一次管理员密码）。在系统设置 → 显示器里也会多出这些档位，这是正常的。")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.top, 8)
    }

    private var displaysTab: some View {
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
                        Badge(text: model.backend(for: snapshot).titleZH,
                              tint: model.backend(for: snapshot) == .hardware ? .green : .orange)
                    }
                    Text("vendor \(snapshot.identity.vendorHex) · product \(snapshot.identity.productHex)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.3)))
            }
            Spacer()
        }
        .padding(.top, 8)
    }

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
            shortcutRow("⌥⌘1", "应用预设 1")
            shortcutRow("⌥⌘2", "应用预设 2")
            shortcutRow("⌥⌘3", "应用预设 3")
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

    private var permissionsTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                OcticonImage(name: model.hasAccessibilityPermission ? "check-circle" : "x-circle", size: 14)
                    .foregroundStyle(model.hasAccessibilityPermission ? .green : .red)
                Text(model.hasAccessibilityPermission ? L10n.t("权限已授予") : L10n.t("需要辅助功能权限"))
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
