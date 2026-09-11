import AppKit
import SwiftUI

/// 屏幕底部居中的小 OSD：图标 + 进度条 + 百分比。
@MainActor
final class OSDController {
    static let shared = OSDController()

    private var panel: NSPanel?
    private var hideWorkItem: DispatchWorkItem?

    private init() {}

    func show(level: Double, displayName: String, backend: BrightnessBackend, screen: NSScreen?) {
        let target = screen ?? NSScreen.main ?? NSScreen.screens.first
        guard let target else { return }

        let view = OSDView(level: level, displayName: displayName, backend: backend)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 260, height: 76)

        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.contentView = hosting

        let size = NSSize(width: 260, height: 76)
        let origin = NSPoint(
            x: target.frame.midX - size.width / 2,
            y: target.visibleFrame.minY + 90
        )
        panel.setFrame(NSRect(origin: origin, size: size), display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }

        hideWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let panel = self?.panel else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.35
                panel.animator().alphaValue = 0
            } completionHandler: {
                panel.orderOut(nil)
            }
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: work)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 76),
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
        return panel
    }
}

struct OSDView: View {
    let level: Double
    let displayName: String
    let backend: BrightnessBackend

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                OcticonImage(name: level > 0.55 ? "sun" : "moon", size: 14)
                    .foregroundStyle(.white)
                Text("\(Int((level * 100).rounded()))%")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Spacer(minLength: 4)
                Text(backend.titleZH)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.65))
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.18))
                    Capsule()
                        .fill(.white.opacity(0.92))
                        .frame(width: max(6, geometry.size.width * level))
                }
            }
            .frame(height: 6)
            Text(displayName)
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
