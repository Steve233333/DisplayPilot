#!/usr/bin/env python3
"""生成 macOS App 图标（Assets.xcassets/AppIcon.appiconset，全套尺寸）。

设计：圆角方形渐变底 + 白色显示器 + 屏幕里的亮度柱，
和 App 内用的 Octicons 显示器图标保持同一套视觉语言。

用法: python3 tools/make_icon.py
"""
import json
import os
import sys

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Sources", "Resources", "Assets.xcassets", "AppIcon.appiconset")

S = 4096          # 先用 4 倍画，再缩到 1024，边缘更干净
MASTER = 1024

# macOS 图标规范：内容占画布约 80%，圆角半径约为边长的 18%
INSET = int(S * 0.094)
RADIUS = int(S * 0.2)

TOP = (110, 168, 255)     # 亮蓝
BOTTOM = (43, 82, 226)    # 深蓝
SCREEN_BG = (13, 24, 56)
BAR_COLORS = [
    (150, 190, 255),
    (170, 205, 255),
    (195, 222, 255),
    (215, 235, 255),
    (255, 255, 255),
]


def rounded_mask(size: int, inset: int, radius: int) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle([inset, inset, size - inset, size - inset], radius=radius, fill=255)
    return mask


def gradient(size: int) -> Image.Image:
    img = Image.new("RGB", (size, size))
    draw = ImageDraw.Draw(img)
    for y in range(size):
        t = y / (size - 1)
        draw.line(
            [(0, y), (size, y)],
            fill=tuple(int(TOP[i] + (BOTTOM[i] - TOP[i]) * t) for i in range(3)),
        )
    return img


def build_master() -> Image.Image:
    bg = gradient(S).convert("RGBA")
    mask = rounded_mask(S, INSET, RADIUS)

    # 顶部高光
    highlight = Image.new("L", (S, S), 0)
    ImageDraw.Draw(highlight).ellipse(
        [-S * 0.35, -S * 0.75, S * 1.35, S * 0.42], fill=70
    )
    highlight = highlight.filter(ImageFilter.GaussianBlur(S * 0.06))
    bg = Image.composite(Image.new("RGBA", (S, S), (255, 255, 255, 255)), bg, highlight)

    canvas = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    canvas.paste(bg, (0, 0), mask)

    draw = ImageDraw.Draw(canvas)

    # 显示器机身
    body = [S * 0.205, S * 0.235, S * 0.795, S * 0.665]
    draw.rounded_rectangle(body, radius=S * 0.055, fill=(245, 248, 255, 255))

    # 屏幕
    screen = [S * 0.245, S * 0.275, S * 0.755, S * 0.625]
    draw.rounded_rectangle(screen, radius=S * 0.038, fill=SCREEN_BG + (255,))

    # 屏幕里的 5 根亮度柱（越高越亮）
    bar_w = (screen[2] - screen[0]) * 0.128
    gap = bar_w * 0.42
    total = bar_w * 5 + gap * 4
    start_x = screen[0] + ((screen[2] - screen[0]) - total) / 2
    base_y = screen[3] - S * 0.038
    for i in range(5):
        height = S * (0.055 + i * 0.032)
        x0 = start_x + i * (bar_w + gap)
        draw.rounded_rectangle(
            [x0, base_y - height, x0 + bar_w, base_y],
            radius=bar_w * 0.34,
            fill=BAR_COLORS[i] + (255,),
        )

    # 底座
    neck = [S * 0.455, S * 0.665, S * 0.545, S * 0.735]
    draw.rounded_rectangle(neck, radius=S * 0.014, fill=(245, 248, 255, 255))
    stand = [S * 0.375, S * 0.735, S * 0.625, S * 0.792]
    draw.rounded_rectangle(stand, radius=S * 0.026, fill=(245, 248, 255, 255))

    return canvas.resize((MASTER, MASTER), Image.LANCZOS)


def main() -> int:
    os.makedirs(OUT, exist_ok=True)
    master = build_master()

    variants = [
        ("icon_16x16.png", 16, "1x", "16x16"),
        ("icon_16x16@2x.png", 32, "2x", "16x16"),
        ("icon_32x32.png", 32, "1x", "32x32"),
        ("icon_32x32@2x.png", 64, "2x", "32x32"),
        ("icon_128x128.png", 128, "1x", "128x128"),
        ("icon_128x128@2x.png", 256, "2x", "128x128"),
        ("icon_256x256.png", 256, "1x", "256x256"),
        ("icon_256x256@2x.png", 512, "2x", "256x256"),
        ("icon_512x512.png", 512, "1x", "512x512"),
        ("icon_512x512@2x.png", 1024, "2x", "512x512"),
    ]

    images = []
    for filename, size, scale, logical in variants:
        master.resize((size, size), Image.LANCZOS).save(os.path.join(OUT, filename))
        images.append({"filename": filename, "idiom": "mac", "scale": scale, "size": logical})

    with open(os.path.join(OUT, "Contents.json"), "w", encoding="utf-8") as fh:
        json.dump({"images": images, "info": {"author": "xcode", "version": 1}}, fh, indent=2)

    print(f"图标已生成：{len(images)} 个尺寸 → {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
