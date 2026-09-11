#!/usr/bin/env python3
"""把一张方形图片变成 macOS App 图标全套尺寸。

用法:
    python3 tools/apply_icon.py ~/Downloads/my-icon.png            # 自动套 macOS 圆角+留白
    python3 tools/apply_icon.py ~/Downloads/my-icon.png --no-mask  # 图里已经自带圆角和透明边

生成 Sources/Resources/Assets.xcassets/AppIcon.appiconset 下的 10 个尺寸 + Contents.json，
之后 make run / ./build.sh 就会带上新图标。
"""
import json
import os
import sys

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Sources", "Resources", "Assets.xcassets", "AppIcon.appiconset")
MASTER = 1024

VARIANTS = [
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


def square(image: Image.Image) -> Image.Image:
    """居中裁剪成正方形。"""
    width, height = image.size
    side = min(width, height)
    left = (width - side) // 2
    top = (height - side) // 2
    return image.crop((left, top, left + side, top + side))


def macos_mask(image: Image.Image) -> Image.Image:
    """套上 macOS 图标规范：内容占 81%，圆角为边长的 18.5%。"""
    size = MASTER
    inset = int(size * 0.094)
    radius = int(size * 0.185)

    scaled = image.resize((size, size), Image.LANCZOS)
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [inset, inset, size - inset, size - inset], radius=radius, fill=255
    )
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.paste(scaled, (0, 0), mask)
    return out


def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    apply_mask = "--no-mask" not in sys.argv

    if not args:
        print(__doc__)
        return 2
    source = os.path.expanduser(args[0])
    if not os.path.exists(source):
        print(f"找不到文件：{source}")
        return 1

    master = Image.open(source).convert("RGBA")
    if master.size[0] != master.size[1]:
        print(f"图片不是正方形（{master.size[0]}×{master.size[1]}），已自动居中裁剪")
    master = square(master)

    if apply_mask:
        has_alpha = master.getchannel("A").getextrema()[0] < 250
        if has_alpha:
            print("检测到透明通道：保留原图排版（不再套圆角）。想强制套圆角可加 --mask-force")
        if not has_alpha or "--mask-force" in sys.argv:
            master = macos_mask(master)
    else:
        master = master.resize((MASTER, MASTER), Image.LANCZOS)

    os.makedirs(OUT, exist_ok=True)
    images = []
    for filename, size, scale, logical in VARIANTS:
        master.resize((size, size), Image.LANCZOS).save(os.path.join(OUT, filename))
        images.append({"filename": filename, "idiom": "mac", "scale": scale, "size": logical})

    with open(os.path.join(OUT, "Contents.json"), "w", encoding="utf-8") as fh:
        json.dump({"images": images, "info": {"author": "xcode", "version": 1}}, fh, indent=2)

    print(f"已应用新图标：{len(images)} 个尺寸 → {OUT}")
    print("接着跑 `make run` 或 `./build.sh` 就会带上它。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
