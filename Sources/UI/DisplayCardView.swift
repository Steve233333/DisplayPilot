import AppKit
import SwiftUI

/// 单块显示器的卡片：分辨率档位 + 亮度 + 后端策略 + 覆盖文件操作 + 预设。
struct DisplayCardView: View {
    let snapshot: DisplaySnapshot

    @Environment(AppModel.self) private var model
    @State private var dragIndex: Double?
    @State private var presetName = ""
    @State private var showingPresetField = false

    private var choices: [ScaledMode] { snapshot.scalingChoices }

    private var currentIndex: Int {
        guard let current = snapshot.currentMode else { return 0 }
        if let index = choices.firstIndex(where: {
            $0.backingWidth == current.backingWidth && $0.backingHeight == current.backingHeight
        }) { return index }
        return 0
    }

    private var hoveredMode: ScaledMode? {
        guard let dragIndex, !choices.isEmpty else { return nil }
        let index = min(max(Int(dragIndex.rounded()), 0), choices.count - 1)
        return choices[index]
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                title
                resolutionSection
                brightnessSection
                actions
                if showingPresetField { presetField }
            }
        }
    }

    // MARK: - 标题

    private var title: some View {
        HStack(spacing: 6) {
            OcticonImage(name: "device-desktop", size: 13)
                .foregroundStyle(.secondary)
            Text(snapshot.identity.name)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
            if snapshot.isMain { Badge(text: L10n.t("主显示器"), tint: .blue) }
            if snapshot.identity.isBuiltin { Badge(text: L10n.t("内置")) }
            Spacer()
            Badge(text: "\(snapshot.nativeResolution.width)×\(snapshot.nativeResolution.height)", tint: .secondary)
        }
    }

    // MARK: - 分辨率

    private var resolutionSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                OcticonImage(name: "screen-full", size: 12)
                    .foregroundStyle(.secondary)
                Text(L10n.t("分辨率"))
                    .font(.system(size: 11, weight: .medium))
                Spacer()
                Text((hoveredMode ?? snapshot.currentMode)?.label ?? "—")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                if let mode = hoveredMode ?? snapshot.currentMode, mode.isHiDPI {
                    Badge(text: "HiDPI", tint: .purple)
                }
            }

            if choices.count > 1 {
                Slider(
                    value: Binding(
                        get: { dragIndex ?? Double(currentIndex) },
                        set: { dragIndex = $0 }
                    ),
                    in: 0...Double(choices.count - 1),
                    step: 1,
                    onEditingChanged: { editing in
                        if !editing, let index = dragIndex {
                            let clamped = min(max(Int(index.rounded()), 0), choices.count - 1)
                            model.setMode(choices[clamped], for: snapshot)
                            dragIndex = nil
                        }
                    }
                )
                .controlSize(.small)
                .disabled(model.isBusy)

                Text((hoveredMode ?? snapshot.currentMode)?.detail ?? "")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            } else {
                Text("当前系统只提供 \(choices.count) 个档位——点击下方「启用平滑缩放」注入 61 档柔性梯")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - 亮度

    private var brightnessSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                OcticonImage(name: model.backend(for: snapshot) == .hardware ? "sun" : "moon", size: 12)
                    .foregroundStyle(.secondary)
                Text(L10n.t("亮度"))
                    .font(.system(size: 11, weight: .medium))
                Spacer()
                Text("\(Int((model.level(for: snapshot) * 100).rounded()))%")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                Menu {
                    Picker(L10n.t("亮度后端"), selection: Binding(
                        get: { model.policy(for: snapshot) },
                        set: { model.setPolicy($0, for: snapshot) }
                    )) {
                        Text(L10n.t("自动")).tag(BrightnessPolicy.automatic)
                        Text(L10n.t("强制硬件")).tag(BrightnessPolicy.hardware)
                        Text(L10n.t("强制软件")).tag(BrightnessPolicy.software)
                    }
                    .pickerStyle(.inline)
                } label: {
                    Badge(
                        text: model.backend(for: snapshot).titleZH,
                        tint: model.backend(for: snapshot) == .hardware ? .green : .orange
                    )
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }

            Slider(
                value: Binding(
                    get: { model.level(for: snapshot) },
                    set: { model.setLevel($0, for: snapshot) }
                ),
                in: 0...1
            )
            .controlSize(.small)

            if model.policy(for: snapshot) == .hardware {
                Text(L10n.t("DCR 模式下硬件调光可能闪烁"))
                    .font(.system(size: 9))
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: - 操作

    private var actions: some View {
        HStack(spacing: 6) {
            Button {
                model.installScalingLadder(for: snapshot)
            } label: {
                Label(L10n.t("启用平滑缩放"), systemImage: "wand.and.stars")
                    .font(.system(size: 10))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.mini)
            .disabled(model.isBusy)

            Button {
                model.reprobe(snapshot)
            } label: {
                OcticonImage(name: "sync", size: 11)
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .help(L10n.t("重新识别"))

            Button {
                model.restoreNativeModes(for: snapshot)
            } label: {
                Text(L10n.t("还原原生"))
                    .font(.system(size: 10))
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .disabled(model.isBusy)

            Spacer()

            Button {
                showingPresetField.toggle()
            } label: {
                OcticonImage(name: "star", size: 11)
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .help(L10n.t("保存当前为预设"))
        }
    }

    private var presetField: some View {
        HStack(spacing: 6) {
            TextField(L10n.t("预设名称"), text: $presetName)
                .textFieldStyle(.roundedBorder)
                .controlSize(.mini)
                .onSubmit(commitPreset)
            Button(L10n.t("保存"), action: commitPreset)
                .controlSize(.mini)
                .buttonStyle(.borderedProminent)
                .disabled(presetName.trimmingCharacters(in: .whitespaces).isEmpty)
            Button(L10n.t("取消")) {
                showingPresetField = false
                presetName = ""
            }
            .controlSize(.mini)
        }
    }

    private func commitPreset() {
        let name = presetName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        model.savePreset(named: name, from: snapshot)
        presetName = ""
        showingPresetField = false
    }
}
