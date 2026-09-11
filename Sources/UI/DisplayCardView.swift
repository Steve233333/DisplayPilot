import AppKit
import SwiftUI

/// 单块显示器的卡片：分辨率档位 + 亮度 + 后端策略 + 覆盖文件操作 + 预设。
struct DisplayCardView: View {
    let snapshot: DisplaySnapshot

    @Environment(AppModel.self) private var model
    @State private var dragIndex: Double?
    @State private var presetName = ""
    @State private var showingPresetField = false
    @State private var showingRange = false

    private var choices: [ScaledMode] {
        snapshot.scalingChoices(hidpiOnly: model.hidpiOnlyChoices)
    }

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
                Menu {
                    Toggle("只显示 HiDPI 档位", isOn: Binding(
                        get: { model.hidpiOnlyChoices },
                        set: { model.setHidpiOnly($0) }
                    ))
                    Text("只列出与面板等比例的档位：既不会模糊，也不会留黑边")
                } label: {
                    Badge(
                        text: model.hidpiOnlyChoices ? "HiDPI" : "全部档位",
                        tint: model.hidpiOnlyChoices ? .purple : .secondary
                    )
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
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
                Button {
                    showingRange.toggle()
                } label: {
                    OcticonImage(name: "sliders", size: 11)
                }
                .buttonStyle(.plain)
                .help("设定最低/最高亮度：滑杆的 0% 和 100% 会落在这个区间里")
                .popover(isPresented: $showingRange, arrowEdge: .bottom) {
                    rangeEditor
                }
                Text("\(Int((model.level(for: snapshot) * 100).rounded()))%")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
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

            if !model.limits(for: snapshot).isDefault {
                Text("滑杆区间：0% → \(Int((model.limits(for: snapshot).minimum * 100).rounded()))% ，100% → \(Int((model.limits(for: snapshot).maximum * 100).rounded()))%")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }

            if model.policy(for: snapshot) == .hardware {
                Text(L10n.t("DCR 模式下硬件调光可能闪烁"))
                    .font(.system(size: 9))
                    .foregroundStyle(.orange)
            }
        }
    }

    /// 最低/最高亮度设定器。
    private var rangeEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("亮度区间")
                .font(.system(size: 12, weight: .semibold))
            Text("滑杆上的 0%～100% 只会落在这段区间里，用来避开显示器最暗/最亮时不舒服的两端。")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("最低").font(.system(size: 11))
                    Spacer()
                    Text("\(Int((model.limits(for: snapshot).minimum * 100).rounded()))%")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                }
                Slider(value: Binding(
                    get: { model.limits(for: snapshot).minimum },
                    set: { newValue in
                        var limits = model.limits(for: snapshot)
                        limits.minimum = min(newValue, limits.maximum - 0.02)
                        model.setLimits(limits, for: snapshot)
                    }
                ), in: 0...1)
                .controlSize(.small)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("最高").font(.system(size: 11))
                    Spacer()
                    Text("\(Int((model.limits(for: snapshot).maximum * 100).rounded()))%")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                }
                Slider(value: Binding(
                    get: { model.limits(for: snapshot).maximum },
                    set: { newValue in
                        var limits = model.limits(for: snapshot)
                        limits.maximum = max(newValue, limits.minimum + 0.02)
                        model.setLimits(limits, for: snapshot)
                    }
                ), in: 0...1)
                .controlSize(.small)
            }

            HStack {
                Button("重置为 0%–100%") {
                    model.setLimits(BrightnessLimits(), for: snapshot)
                }
                .controlSize(.small)
                Spacer()
                Button("完成") { showingRange = false }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(14)
        .frame(width: 280)
    }

    // MARK: - 操作

    private var actions: some View {
        HStack(spacing: 6) {
            scalingButton

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

    /// 「启用平滑缩放」按钮：按当前状态显示不同文案，并把原因说清楚。
    @ViewBuilder
    private var scalingButton: some View {
        switch model.scalingStatus(for: snapshot) {
        case .installed:
            Button {
                model.reprobe(snapshot)
            } label: {
                Label("平滑缩放已启用", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 10))
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .help("61 档等比例缩放已经在系统里了（所以点它不会看到变化）。点一下只会让系统重新识别一次档位。")
        case .missing:
            Button {
                model.installScalingLadder(for: snapshot)
            } label: {
                Label(L10n.t("启用平滑缩放"), systemImage: "wand.and.stars")
                    .font(.system(size: 10))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.mini)
            .disabled(model.isBusy)
            .help("往系统里写入 61 档等比例 HiDPI 档位（原生 → 50%，每 16 点一档），写完立刻生效，需要一次管理员密码。")
        case .unsupported(let reason):
            Button {
            } label: {
                Label("不支持平滑缩放", systemImage: "slash.circle")
                    .font(.system(size: 10))
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .disabled(true)
            .help(reason)
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
