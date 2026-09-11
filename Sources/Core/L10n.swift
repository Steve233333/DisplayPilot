import Foundation

/// 极简中英双语：系统语言非中文时切换到英文文案。
/// （没有用 .lproj 资源，避免构建期依赖，行为等价于运行时查表。）
enum L10n {
    static let isEnglish: Bool = {
        let language = Locale.preferredLanguages.first?.lowercased() ?? "en"
        return !language.hasPrefix("zh")
    }()

    static func t(_ chinese: String) -> String {
        guard isEnglish else { return chinese }
        return english[chinese] ?? chinese
    }

    private static let english: [String: String] = [
        "显示": "Displays",
        "分辨率": "Resolution",
        "亮度": "Brightness",
        "预设": "Presets",
        "设置": "Settings",
        "退出": "Quit",
        "主显示器": "Main",
        "内置": "Built-in",
        "自动": "Auto",
        "强制硬件": "Force hardware",
        "强制软件": "Force software",
        "硬件 DDC": "Hardware DDC",
        "软件调光": "Software dimming",
        "启用平滑缩放": "Enable smooth scaling",
        "刷新档位": "Refresh modes",
        "还原原生": "Restore native",
        "重新识别": "Re-detect",
        "正在写入系统配置…": "Writing system configuration…",
        "档位已就绪": "Modes are ready",
        "已还原为系统原生模式表": "Restored the system's native mode list",
        "亮度后端": "Brightness backend",
        "开机自启": "Launch at login",
        "接管 F1/F2 亮度键": "Take over F1/F2 brightness keys",
        "显示 OSD": "Show OSD",
        "需要辅助功能权限": "Accessibility permission required",
        "去授权": "Grant access",
        "权限已授予": "Permission granted",
        "档位密度": "Mode ladder density",
        "平滑（61 档）": "Smooth (61 steps)",
        "精简（6 档）": "Compact (6 steps)",
        "快捷键": "Shortcuts",
        "权限": "Permissions",
        "关于": "About",
        "通用": "General",
        "版本": "Version",
        "保存当前为预设": "Save current as preset",
        "预设名称": "Preset name",
        "删除": "Delete",
        "应用": "Apply",
        "取消": "Cancel",
        "保存": "Save",
        "该显示器没有可用的 DDC 通道，已使用软件调光": "No DDC channel available; using software dimming",
        "DCR 模式下硬件调光可能闪烁": "Hardware dimming may flicker in DCR mode",
        "Icons: GitHub Octicons (MIT)": "Icons: GitHub Octicons (MIT)",
    ]
}
