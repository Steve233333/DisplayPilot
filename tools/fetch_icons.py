#!/usr/bin/env python3
"""下载 Octicons 图标并生成 Xcode 资源目录（含 AppIcon）。

用法: python3 tools/fetch_icons.py
依赖: gh（已登录）、Pillow

图标来自 https://github.com/primer/octicons （MIT）。SVG 以「模板图」方式
放进 imageset，运行时可随系统深浅色 / 强调色着色。
"""
import base64
import json
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOG = os.path.join(ROOT, "Sources", "Resources", "Assets.xcassets")

# 界面里用到的图标（16px 版本，命名以 Octicons 实际文件为准）
ICONS = [
    "device-desktop",      # 显示器
    "screen-full",         # 缩放 / 分辨率
    "sliders",             # 亮度
    "sun",                 # 亮度高
    "moon",                # 亮度低
    "gear",                # 设置
    "check-circle",        # 成功
    "x-circle",            # 失败
    "sync",                # 重新探测
    "alert",               # 警告（DDC 闪烁）
    "info",                # 说明
    "star",                # 预设
    "pin",                 # 固定
    "rocket",              # 启动项
    "chevron-down",        # 折叠
    "chevron-right",       # 展开
    "plus",                # 增加
    "dash",                # 减少
    "power",               # 退出
    "grabber",             # 拖拽手柄
    "light-bulb",          # 提示
    "arrow-up",            # 快捷键
    "arrow-down",          # 快捷键
    "apps",                # 预设组
    "eye",                 # 预览
    "paintbrush",          # 外观
    "key",                 # 快捷键 / 权限
]


def fetch_svg(name: str) -> str | None:
    path = f"icons/{name}-16.svg"
    try:
        out = subprocess.run(
            ["gh", "api", f"repos/primer/octicons/contents/{path}", "--jq", ".content"],
            capture_output=True, text=True, check=True,
        ).stdout.strip()
    except subprocess.CalledProcessError:
        return None
    return base64.b64decode(out).decode("utf-8")


def write_imageset(name: str, svg: str) -> None:
    folder = os.path.join(CATALOG, f"{name}.imageset")
    os.makedirs(folder, exist_ok=True)
    with open(os.path.join(folder, f"{name}.svg"), "w", encoding="utf-8") as fh:
        fh.write(svg)
    contents = {
        "images": [{"filename": f"{name}.svg", "idiom": "universal"}],
        "info": {"author": "xcode", "version": 1},
        "properties": {
            "preserves-vector-representation": True,
            "template-rendering-intent": "template",
        },
    }
    with open(os.path.join(folder, "Contents.json"), "w", encoding="utf-8") as fh:
        json.dump(contents, fh, indent=2)


def make_app_icon() -> None:
    """用 Pillow 画一个简洁的 AppIcon（深浅渐变底 + 显示器 + 光晕）。"""
    try:
        from PIL import Image, ImageDraw
    except ImportError:
        print("跳过 AppIcon：没有安装 Pillow（pip3 install pillow）")
        return

    size = 1024
    img = Image.new("RGB", (size, size), (24, 27, 36))
    draw = ImageDraw.Draw(img)
    # 背景竖向渐变
    top, bottom = (46, 54, 82), (14, 16, 24)
    for y in range(size):
        t = y / (size - 1)
        draw.line([(0, y), (size, y)],
                  fill=tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))

    # 显示器机身
    draw.rounded_rectangle([150, 236, 874, 696], radius=56, fill=(246, 248, 252))
    draw.rounded_rectangle([192, 278, 832, 654], radius=36, fill=(20, 22, 30))

    # 屏幕里 5 根递增的亮度柱
    bar_width, gap = 92, 26
    for i in range(5):
        x0 = 244 + i * (bar_width + gap)
        height = 96 + i * 44
        y0 = 612 - height
        shade = 96 + i * 34
        draw.rounded_rectangle(
            [x0, y0, x0 + bar_width, 612], radius=16,
            fill=(min(255, shade), min(255, shade + 16), min(255, shade + 48)),
        )

    # 底座
    draw.rounded_rectangle([466, 696, 558, 744], radius=16, fill=(246, 248, 252))
    draw.rounded_rectangle([344, 744, 680, 796], radius=26, fill=(246, 248, 252))

    folder = os.path.join(CATALOG, "AppIcon.appiconset")
    os.makedirs(folder, exist_ok=True)
    img.save(os.path.join(folder, "icon-1024.png"))
    contents = {
        "images": [
            {"filename": "icon-1024.png", "idiom": "mac", "scale": "1x", "size": "512x512"},
            {"idiom": "mac", "scale": "2x", "size": "512x512"},
        ],
        "info": {"author": "xcode", "version": 1},
    }
    with open(os.path.join(folder, "Contents.json"), "w", encoding="utf-8") as fh:
        json.dump(contents, fh, indent=2)
    print("AppIcon 已生成")


def main() -> int:
    icon_only = "--icon-only" in sys.argv
    os.makedirs(CATALOG, exist_ok=True)
    with open(os.path.join(CATALOG, "Contents.json"), "w", encoding="utf-8") as fh:
        json.dump({"info": {"author": "xcode", "version": 1}}, fh, indent=2)

    if icon_only:
        make_app_icon()
        return 0

    ok, missing = 0, []
    for name in ICONS:
        if os.path.exists(os.path.join(CATALOG, f"{name}.imageset", "Contents.json")):
            ok += 1
            continue
        svg = fetch_svg(name)
        if svg is None:
            missing.append(name)
            continue
        write_imageset(name, svg)
        ok += 1
    make_app_icon()
    print(f"完成：{ok} 个图标写入 {CATALOG}")
    if missing:
        print("以下图标在 Octicons 中不存在（已跳过）：", ", ".join(missing))
    return 0


if __name__ == "__main__":
    sys.exit(main())
