import AppKit
import SwiftUI

/// 菜单栏弹出的主面板：每块显示器一张卡片。
struct MenuBarPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if model.mediaKeysEnabled, !model.hasAccessibilityPermission {
                permissionBanner
            }

            if let status = model.status {
                statusRow(status)
            }

            if model.displays.isEmpty {
                Text(L10n.t("没有检测到显示器"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(model.displays) { snapshot in
                            DisplayCardView(snapshot: snapshot)
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.vertical, 2)
                }
                .frame(height: listHeight)
            }

            footer
        }
        .padding(12)
        .frame(width: 400)
    }

    /// ScrollView 在菜单栏面板里没有固有高度，会被压扁成一条；
    /// 这里按卡片数量算一个确定高度（最多 500，超出才滚动）。
    private var listHeight: CGFloat {
        let perCard: CGFloat = 214
        let needed = CGFloat(model.displays.count) * perCard + 16
        return min(500, max(200, needed))
    }

    // MARK: - 顶栏

    private var header: some View {
        HStack(spacing: 8) {
            OcticonImage(name: "device-desktop", size: 16)
                .foregroundStyle(.tint)
            Text("DisplayPilot")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
            Spacer()
            Button {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            } label: {
                OcticonImage(name: "gear", size: 14)
            }
            .buttonStyle(.plain)
            .help(L10n.t("设置"))

            Button {
                model.quit()
            } label: {
                OcticonImage(name: "power", size: 14)
            }
            .buttonStyle(.plain)
            .help(L10n.t("退出"))
        }
    }

    private var permissionBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            OcticonImage(name: "alert", size: 14)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.t("需要辅助功能权限"))
                    .font(.system(size: 11, weight: .semibold))
                Text("授权后 F1/F2 亮度键才会由 DisplayPilot 接管")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(L10n.t("去授权")) {
                model.requestAccessibilityPermission()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.mini)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.orange.opacity(0.12)))
    }

    private func statusRow(_ status: StatusMessage) -> some View {
        HStack(spacing: 6) {
            OcticonImage(name: status.kind == .error ? "x-circle" : (status.kind == .success ? "check-circle" : "info"), size: 12)
                .foregroundStyle(status.kind == .error ? .red : (status.kind == .success ? .green : .secondary))
            Text(status.text)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer()
        }
    }

    // MARK: - 底部预设

    private var footer: some View {
        VStack(spacing: 8) {
            Divider().opacity(0.4)
            HStack(spacing: 6) {
                OcticonImage(name: "star", size: 12)
                    .foregroundStyle(.secondary)
                Text(L10n.t("预设"))
                    .font(.system(size: 11, weight: .medium))
                Spacer()
                ForEach(Array(model.presets.prefix(3).enumerated()), id: \.element.id) { index, preset in
                    Button(preset.name) {
                        model.applyPreset(preset)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .help("\(preset.summary) · ⌥⌘\(index + 1)")
                    .contextMenu {
                        Button(L10n.t("删除")) { model.deletePreset(preset) }
                    }
                }
                if model.presets.isEmpty {
                    Text("⌥⌘↑/↓ 调亮度 · 卡片里可存预设")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}
