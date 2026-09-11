import AppKit
import Combine
import SwiftUI

/// OSD 的内容模型。面板只建一次，拖滑杆时只更新这个模型，
/// 所以不会像之前那样每次改亮度都重建窗口 → 一直闪。
@MainActor
final class OSDModel: ObservableObject {
    @Published var level: Double = 1
    @Published var displayName: String = ""
    @Published var backend: BrightnessBackend = .software
}

/// 屏幕底部居中的小 OSD：图标 + 进度条 + 百分比。
@MainActor
final class OSDController {
    static let shared = OSDController()

    private let model = OSDModel()
    private var panel: NSPanel?
    private var hideWorkItem: DispatchWorkItem?

    private init() {}

    func show(level: Double, displayName: String, backend: BrightnessBackend, screen: NSScreen?) {
        model.level = min(max(level, 0), 1)
        model.displayName = displayName
        model.backend = backend

        guard let target = screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let panel = ensurePanel()
        position(panel, on: target)

        hideWorkItem?.cancel()

        if !panel.isVisible || panel.alphaValue < 0.99 {
            // 只有「从无到有」才淡入；连续拖动时只更新内容，不再闪。
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                panel.animator().alphaValue = 1
            }
        } else {
            panel.orderFrontRegardless()
        }

        let work = DispatchWorkItem { [weak self] in self?.hide() }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: work)
    }

    private func hide() {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            panel.animator().alphaValue = 0
        } completionHandler: {
            panel.orderOut(nil)
        }
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let size = NSSize(width: 260, height: 76)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: OSDView(model: model))
        self.panel = panel
        return panel
    }

    private func position(_ panel: NSPanel, on screen: NSScreen) {
        let size = panel.frame.size
        let origin = NSPoint(
            x: screen.frame.midX - size.width / 2,
            y: screen.visibleFrame.minY + 90
        )
        panel.setFrame(NSRect(origin: origin, size: size), display: false)
    }
}

struct OSDView: View {
    @ObservedObject var model: OSDModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                OcticonImage(name: model.level > 0.55 ? "sun" : "moon", size: 14)
                    .foregroundStyle(.white)
                Text("\(Int((model.level * 100).rounded()))%")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                Spacer(minLength: 4)
                Text(model.backend.titleZH)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.65))
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.18))
                    Capsule()
                        .fill(.white.opacity(0.92))
                        .frame(width: max(6, geometry.size.width * model.level))
                }
            }
            .frame(height: 6)
            Text(model.displayName)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(width: 260, height: 76, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.black.opacity(0.62))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        )
    }
}
