import CoreGraphics
import Foundation

/// 交互式文档截图工具：等你手动打开 DisplayPilot 的面板 / 设置窗口，
/// 自动把两个窗口分别截下来存到 docs/panel.png、docs/settings.png。
///
/// 用法: swift tools/capture_docs.swift [等待秒数，默认 180]
let timeout = CommandLine.arguments.count > 1 ? Double(CommandLine.arguments[1]) ?? 180 : 180
let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let docs = repoRoot.appendingPathComponent("docs")
try? FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)

struct Window {
    let name: String
    let number: Int
    let rect: CGRect
}

func displayPilotWindows() -> [Window] {
    guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
        return []
    }
    return list.compactMap { window in
        guard let owner = window[kCGWindowOwnerName as String] as? String, owner.contains("DisplayPilot") else { return nil }
        guard let bounds = window[kCGWindowBounds as String] as? [String: Any] else { return nil }
        let rect = CGRect(
            x: (bounds["X"] as? Double) ?? 0,
            y: (bounds["Y"] as? Double) ?? 0,
            width: (bounds["Width"] as? Double) ?? 0,
            height: (bounds["Height"] as? Double) ?? 0
        )
        guard rect.width > 200, rect.height > 200 else { return nil }
        let name = window[kCGWindowName as String] as? String ?? ""
        let number = window[kCGWindowNumber as String] as? Int ?? 0
        return Window(name: name, number: number, rect: rect)
    }
}

func capture(_ window: Window, to path: String, margin: CGFloat = 26) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    if window.number > 0 {
        // 按窗口 ID 截：不会把压在它上面的面板/其它窗口拍进去
        process.arguments = ["-x", "-o", "-l", "\(window.number)", path]
    } else {
        let rect = window.rect.insetBy(dx: -margin, dy: -margin)
        process.arguments = [
            "-x", "-R",
            "\(Int(rect.origin.x)),\(Int(rect.origin.y)),\(Int(rect.width)),\(Int(rect.height))",
            path,
        ]
    }
    try? process.run()
    process.waitUntilExit()
    print("已保存 \(path)  (\(Int(window.rect.width))×\(Int(window.rect.height)))")
}

print("等待 DisplayPilot 的面板与设置窗口…（最多 \(Int(timeout)) 秒）")
let deadline = Date().addingTimeInterval(timeout)
var gotPanel = false
var gotSettings = false

while Date() < deadline, !(gotPanel && gotSettings) {
    for window in displayPilotWindows() {
        // 面板：宽约 400pt 且明显是竖长卡片；设置窗口更宽（~550pt）。
        // OSD（260×76）、亮度区间弹窗（~280pt）这些都要排除掉。
        if !gotPanel, (380...470).contains(window.rect.width), window.rect.height > 400 {
            capture(window, to: docs.appendingPathComponent("panel.png").path)
            gotPanel = true
        } else if !gotSettings, window.rect.width >= 470, window.rect.height > 380 {
            capture(window, to: docs.appendingPathComponent("settings.png").path)
            gotSettings = true
        }
    }
    Thread.sleep(forTimeInterval: 0.4)
}

print(gotPanel && gotSettings ? "两张都拿到了 ✅" : "超时结束（panel=\(gotPanel) settings=\(gotSettings)）")
