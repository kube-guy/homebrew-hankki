#!/usr/bin/env python3
"""앱 아이콘을 그려 Resources/AppIcon.png 와 Resources/AppIcon.icns 로 만든다.

    python3 -m pip install pillow
    python3 scripts/render-icon.py

재료를 담은 밥그릇이 '재료로 고르는 한 끼'다. 색은 앱 화면과 같다(짙은 초록 바탕, 주황 띠).
lunch-draw 아이콘과 같은 macOS 격자(1024 캔버스 안 824 정사각, 모서리 반경 185)를 쓴다.
"""
import math
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

RESOURCES = Path(__file__).resolve().parent.parent / "Resources"
K = 4  # 4배로 그린 뒤 줄여 가장자리를 부드럽게 한다
N = 1024 * K

INK_TOP, INK_BOTTOM = (0x3A, 0x5A, 0x4B), (0x1E, 0x32, 0x29)
CREAM, CREAM_SHADE = (0xFF, 0xF6, 0xEC), (0xF0, 0xDC, 0xC6)
ORANGE, ORANGE_LIGHT = (0xFF, 0x97, 0x5F), (0xFF, 0xC0, 0x96)
RICE = (0xF6, 0xEB, 0xDA)
YOLK = (0xFF, 0xC2, 0x3D)
LEAF, LEAF_VEIN = (0x7F, 0xB0, 0x69), (0x5E, 0x8C, 0x4B)


def box(x0, y0, x1, y1):
    return [v * K for v in (x0, y0, x1, y1)]


def tile_mask():
    mask = Image.new("L", (N, N), 0)
    ImageDraw.Draw(mask).rounded_rectangle(box(100, 100, 924, 924), radius=185 * K, fill=255)
    return mask


def gradient(top, bottom):
    column = Image.new("RGB", (1, N))
    for y in range(N):
        t = y / (N - 1)
        column.putpixel((0, y), tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)))
    return column.resize((N, N))


def rotated(layer_box, draw_fn, angle):
    """작은 투명 레이어에 그린 뒤 돌려서 돌려준다 (잎처럼 기울어진 모양)."""
    x0, y0, x1, y1 = layer_box
    layer = Image.new("RGBA", ((x1 - x0) * K, (y1 - y0) * K), (0, 0, 0, 0))
    draw_fn(ImageDraw.Draw(layer), layer.size)
    return layer.rotate(angle, resample=Image.BICUBIC, expand=False), (x0 * K, y0 * K)


def render():
    canvas = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    mask = tile_mask()

    # 그림자
    shadow = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    shadow.paste((0, 0, 0, 72), (0, 10 * K), mask)
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(28 * K)))

    # 바탕
    background = gradient(INK_TOP, INK_BOTTOM).convert("RGBA")
    background.putalpha(mask)
    canvas.alpha_composite(background)

    art = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    d = ImageDraw.Draw(art)

    # 김 두 줄
    for x in (466, 558):
        points = [(x + 16 * math.sin(i / 10 * 3.2), 196 + i * 11) for i in range(13)]
        d.line([(px * K, py * K) for px, py in points], fill=CREAM + (235,), width=30 * K, joint="curve")
        for px, py in (points[0], points[-1]):
            d.ellipse(box(px - 15, py - 15, px + 15, py + 15), fill=CREAM + (235,))

    # 그릇 안쪽 면(뒤쪽 테두리)
    d.ellipse(box(222, 478, 802, 562), fill=CREAM_SHADE)
    # 밥
    d.pieslice(box(300, 400, 724, 640), 180, 360, fill=RICE)
    d.rectangle(box(300, 518, 724, 522), fill=RICE)

    # 달걀 프라이
    d.ellipse(box(352, 428, 494, 504), fill=(0xE6, 0xD6, 0xBF))
    d.ellipse(box(350, 422, 492, 498), fill=(255, 255, 255))
    d.ellipse(box(396, 432, 450, 482), fill=YOLK)
    d.ellipse(box(408, 440, 424, 454), fill=(255, 226, 150))
    # 당근 두 조각
    for cx, cy, r in ((560, 470, 34), (618, 494, 28)):
        d.ellipse(box(cx - r, cy - r, cx + r, cy + r), fill=ORANGE)
        d.ellipse(box(cx - r * 0.55, cy - r * 0.55, cx + r * 0.55, cy + r * 0.55), fill=ORANGE_LIGHT)

    # 잎
    def leaf(draw, size):
        w, h = size
        draw.ellipse([0, h * 0.18, w, h * 0.82], fill=LEAF)
        draw.line([(w * 0.08, h / 2), (w * 0.92, h / 2)], fill=LEAF_VEIN, width=6 * K)
    leaf_layer, at = rotated((500, 386, 610, 444), leaf, 22)
    art.alpha_composite(leaf_layer, at)

    # 그릇 몸통(앞쪽 반원)과 앞 테두리
    d.pieslice(box(222, 270, 802, 790), 0, 180, fill=CREAM)
    # 주황 띠
    d.arc(box(236, 440, 788, 640), 32, 148, fill=ORANGE, width=24 * K)
    # 굽
    d.rounded_rectangle(box(428, 752, 596, 800), radius=18 * K, fill=CREAM)

    # 그릇 아래 그림자는 바탕 안에서만
    art_shadow = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    art_shadow.paste((0, 0, 0, 60), (0, 14 * K), art.getchannel("A"))
    art_shadow = art_shadow.filter(ImageFilter.GaussianBlur(16 * K))
    art_shadow.putalpha(ImageChops.multiply(art_shadow.getchannel("A"), mask))
    canvas.alpha_composite(art_shadow)
    canvas.alpha_composite(art)

    return canvas.resize((1024, 1024), Image.LANCZOS)


if __name__ == "__main__":
    icon = render()
    icon.save(RESOURCES / "AppIcon.png")
    icon.save(RESOURCES / "AppIcon.icns", sizes=[(16, 16), (32, 32), (64, 64), (128, 128), (256, 256), (512, 512), (1024, 1024)])
    print(RESOURCES / "AppIcon.png")
    print(RESOURCES / "AppIcon.icns")
