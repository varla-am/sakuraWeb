"""Draws the Sakura DMG window background: a calm night sky, a moon, a cherry branch
and a dotted arrow from the app (top) down to Applications (bottom).

Usage: python3 background.py <out-dir>
Writes background.png (1x) and background@2x.png; make-dmg.sh joins them into one HiDPI TIFF.
Everything is laid out in window points (WIDTH x HEIGHT) and drawn 4x larger, then scaled down,
so edges come out smooth.
"""
import math
import random
import sys

from PIL import Image, ImageDraw, ImageFilter

WIDTH, HEIGHT = 420, 600   # the DMG window, in points
APP = (210, 175)           # where make-dmg.sh puts the app icon (its center)
APPLICATIONS = (210, 445)  # and the Applications link
S = 4                      # drawing scale


def px(v):
    return int(round(v * S))


def sky():
    """Deep navy at the top fading to night purple at the bottom."""
    top, middle, bottom = (8, 12, 34), (22, 20, 58), (46, 28, 72)
    img = Image.new("RGB", (px(WIDTH), px(HEIGHT)))
    draw = ImageDraw.Draw(img)
    for y in range(px(HEIGHT)):
        t = y / px(HEIGHT)
        a, b, k = (top, middle, t / 0.55) if t < 0.55 else (middle, bottom, (t - 0.55) / 0.45)
        draw.line([(0, y), (px(WIDTH), y)], fill=tuple(int(a[i] + (b[i] - a[i]) * k) for i in range(3)))
    return img.convert("RGBA")


def glow(size, center, radius, color, blur):
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    x, y = center
    ImageDraw.Draw(layer).ellipse([x - radius, y - radius, x + radius, y + radius], fill=color)
    return layer.filter(ImageFilter.GaussianBlur(blur))


def stars(img):
    rng = random.Random(7)
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    for _ in range(150):
        x, y = rng.uniform(0, WIDTH), rng.uniform(0, HEIGHT * 0.85)
        r = rng.choice([0.5, 0.6, 0.7, 0.8, 1.0, 1.2])
        a = rng.randint(70, 220)
        draw.ellipse([px(x - r), px(y - r), px(x + r), px(y + r)], fill=(255, 245, 250, a))
    img.alpha_composite(layer)
    # A few brighter ones with a soft four-point twinkle
    for x, y in [(60, 210), (372, 248), (318, 36), (34, 470), (392, 380), (150, 300)]:
        img.alpha_composite(glow(img.size, (px(x), px(y)), px(3), (255, 225, 240, 90), px(3)))
        sparkle = Image.new("RGBA", img.size, (0, 0, 0, 0))
        d = ImageDraw.Draw(sparkle)
        d.line([px(x - 5), px(y), px(x + 5), px(y)], fill=(255, 240, 248, 170), width=px(0.5))
        d.line([px(x), px(y - 5), px(x), px(y + 5)], fill=(255, 240, 248, 170), width=px(0.5))
        img.alpha_composite(sparkle.filter(ImageFilter.GaussianBlur(px(0.3))))
        img.alpha_composite(glow(img.size, (px(x), px(y)), px(1.1), (255, 255, 255, 255), 0))


def moon(img):
    cx, cy, r = 352, 74, 20
    img.alpha_composite(glow(img.size, (px(cx), px(cy)), px(r * 2.2), (255, 220, 235, 40), px(18)))
    disc = Image.new("L", img.size, 0)
    ImageDraw.Draw(disc).ellipse([px(cx - r), px(cy - r), px(cx + r), px(cy + r)], fill=255)
    bite = Image.new("L", img.size, 0)
    ImageDraw.Draw(bite).ellipse([px(cx - r + 9), px(cy - r - 5), px(cx + r + 9), px(cy + r - 5)], fill=255)
    crescent = Image.composite(Image.new("L", img.size, 0), disc, bite)
    light = Image.new("RGBA", img.size, (255, 244, 230, 255))
    light.putalpha(crescent)
    img.alpha_composite(light)


def hills(img):
    """Two soft, distant hill lines at the very bottom."""
    for base, amp, color, phase in [(560, 14, (60, 36, 88, 150), 0.6), (578, 10, (36, 22, 58, 230), 2.1)]:
        layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
        points = [(px(x), px(base - amp * math.sin(x / 70 + phase) - amp * 0.5 * math.sin(x / 31)))
                  for x in range(0, WIDTH + 1, 2)]
        ImageDraw.Draw(layer).polygon(points + [(px(WIDTH), px(HEIGHT)), (0, px(HEIGHT))], fill=color)
        img.alpha_composite(layer)


def bezier(p0, p1, p2, p3, t):
    u = 1 - t
    return tuple(u ** 3 * a + 3 * u * u * t * b + 3 * u * t * t * c + t ** 3 * d for a, b, c, d in zip(p0, p1, p2, p3))


def branch(draw, curve, w0, w1, color):
    """A tapering branch: overlapping circles along a curve."""
    for i in range(240):
        t = i / 239
        x, y = bezier(*curve, t)
        w = (w0 + (w1 - w0) * t) / 2
        draw.ellipse([px(x - w), px(y - w), px(x + w), px(y + w)], fill=color)


def petal_shape(length, width, color, angle):
    tile = Image.new("RGBA", (px(length * 2), px(length * 2)), (0, 0, 0, 0))
    c = px(length)
    ImageDraw.Draw(tile).ellipse([c - px(width / 2), c - px(length), c + px(width / 2), c], fill=color)
    return tile.rotate(angle, resample=Image.BICUBIC)


def flower(img, x, y, size, rng):
    angle0 = rng.uniform(0, 72)
    pink = rng.choice([(255, 183, 208, 245), (250, 166, 196, 245), (255, 200, 220, 245)])
    img.alpha_composite(glow(img.size, (px(x), px(y)), px(size * 1.3), (255, 150, 190, 60), px(size * 0.9)))
    for k in range(5):
        tile = petal_shape(size, size * 0.85, pink, angle0 + k * 72)
        img.alpha_composite(tile, (px(x) - tile.width // 2, px(y) - tile.height // 2))
    d = ImageDraw.Draw(img)
    r = size * 0.28
    d.ellipse([px(x - r), px(y - r), px(x + r), px(y + r)], fill=(255, 236, 244, 255))
    r = size * 0.13
    d.ellipse([px(x - r), px(y - r), px(x + r), px(y + r)], fill=(214, 80, 130, 255))


def sakura(img):
    rng = random.Random(3)
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    bark = (70, 42, 74, 255)
    main = ((-20, 44), (55, 26), (105, 74), (172, 58))
    branch(d, main, 10, 2.5, bark)
    branch(d, (bezier(*main, 0.45), (92, 80), (104, 100), (124, 112)), 4.5, 1.2, bark)
    branch(d, (bezier(*main, 0.68), (128, 50), (140, 30), (154, 18)), 3.5, 1, bark)
    branch(d, (bezier(*main, 0.25), (40, 70), (34, 86), (26, 98)), 3.5, 1, bark)
    img.alpha_composite(layer)
    for x, y, s in [(42, 30, 8.5), (64, 46, 10), (86, 40, 8), (100, 64, 9), (122, 110, 8.5),
                    (112, 92, 7), (136, 54, 9.5), (152, 20, 7.5), (168, 60, 8), (178, 48, 6),
                    (28, 96, 7.5), (44, 78, 6.5), (146, 36, 6)]:
        flower(img, x, y, s, rng)
    # Buds
    d = ImageDraw.Draw(img)
    for x, y in [(186, 54), (158, 12), (130, 118), (20, 104), (74, 32)]:
        d.ellipse([px(x - 2.4), px(y - 2.4), px(x + 2.4), px(y + 2.4)], fill=(236, 120, 162, 255))


def falling_petals(img):
    rng = random.Random(11)
    for x, y in [(196, 96), (250, 128), (300, 210), (92, 182), (54, 262), (340, 312),
                 (110, 360), (318, 420), (78, 480), (352, 500), (270, 300)]:
        size = rng.uniform(3.2, 4.6)
        tile = petal_shape(size, size * 0.7, (255, 190, 214, rng.randint(150, 220)), rng.uniform(0, 360))
        img.alpha_composite(tile, (px(x) - tile.width // 2, px(y) - tile.height // 2))


def dotted_arrow(img):
    """A line of dots from under the app's name down to a chevron of dots above Applications."""
    x = APP[0]
    top, tip = APP[1] + 92, APPLICATIONS[1] - 70
    spacing, r = 11, 2.4
    # Counted up from the tip, so the shaft and the chevron share it evenly
    dots = []
    y = tip
    while y >= top:
        dots.append((x, y))
        y -= spacing
    # The chevron's arms, dots as far apart as the shaft's
    step = spacing / math.sqrt(2)
    for k in range(1, 5):
        dots += [(x - k * step, tip - k * step), (x + k * step, tip - k * step)]
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    for dx, dy in dots:
        # Fainter at the top, brighter toward the tip
        a = int(120 + 135 * (dy - top) / (tip - top))
        d.ellipse([px(dx - r), px(dy - r), px(dx + r), px(dy + r)], fill=(255, 196, 220, a))
    img.alpha_composite(layer.filter(ImageFilter.GaussianBlur(px(1.6))))
    img.alpha_composite(layer)


def main(out):
    img = sky()
    stars(img)
    moon(img)
    hills(img)
    falling_petals(img)
    sakura(img)
    dotted_arrow(img)
    img = img.convert("RGB")
    img.resize((WIDTH * 2, HEIGHT * 2), Image.LANCZOS).save(f"{out}/background@2x.png")
    img.resize((WIDTH, HEIGHT), Image.LANCZOS).save(f"{out}/background.png")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else ".")
