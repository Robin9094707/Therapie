from PIL import Image, ImageDraw, ImageFilter
import math
from pathlib import Path

OUT = Path("TherapieApp/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
S = 2048
FINAL = 1024

# Premium deep indigo / violet / aqua gradient.
img = Image.new("RGB", (S, S), (28, 25, 70))
px = img.load()
for y in range(S):
    ty = y / (S - 1)
    for x in range(S):
        tx = x / (S - 1)
        glow = max(0.0, 1.0 - math.hypot(tx - 0.26, ty - 0.18) / 0.8)
        glow2 = max(0.0, 1.0 - math.hypot(tx - 0.82, ty - 0.78) / 0.9)
        r = 28 + int(52 * tx + 28 * glow2)
        g = 25 + int(66 * ty + 54 * glow)
        b = 70 + int(86 * (1 - tx) + 38 * glow2)
        px[x, y] = (min(r, 255), min(g, 255), min(b, 255))

base = img.convert("RGBA")

# Ambient colored glows.
ambient = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ad = ImageDraw.Draw(ambient)
ad.ellipse((-160, -120, 1280, 1320), fill=(91, 220, 255, 105))
ad.ellipse((830, 760, 2260, 2200), fill=(209, 104, 255, 110))
ambient = ambient.filter(ImageFilter.GaussianBlur(250))
base = Image.alpha_composite(base, ambient)

draw = ImageDraw.Draw(base)

# Large central glass plate.
plate = (250, 250, 1798, 1798)
draw.rounded_rectangle(
    plate,
    radius=430,
    fill=(255, 255, 255, 34),
    outline=(255, 255, 255, 95),
    width=14,
)

# Soft inner highlight to sell the glass effect.
highlight = Image.new("RGBA", (S, S), (0, 0, 0, 0))
hd = ImageDraw.Draw(highlight)
hd.rounded_rectangle(
    (292, 292, 1756, 1140),
    radius=380,
    fill=(255, 255, 255, 22),
)
highlight = highlight.filter(ImageFilter.GaussianBlur(45))
base = Image.alpha_composite(base, highlight)
draw = ImageDraw.Draw(base)

# Therapy symbol: an infinity path representing continuity / regulation.
points = []
for i in range(900):
    t = i / 899 * 2 * math.pi
    denom = 1 + math.sin(t) ** 2
    x = math.cos(t) / denom
    y = math.sin(t) * math.cos(t) / denom
    points.append((S / 2 + x * 535, S / 2 + y * 455))

# Shadow, then crisp white path.
draw.line(points, fill=(21, 13, 55, 80), width=142, joint="curve")
draw.line(points, fill=(255, 255, 255, 238), width=112, joint="curve")

# Center heart: connection / care, kept simple for small icon sizes.
cx, cy = S // 2, S // 2 + 4
heart = [
    (cx, cy + 160),
    (cx - 218, cy - 18),
    (cx - 204, cy - 194),
    (cx - 78, cy - 225),
    (cx, cy - 132),
    (cx + 78, cy - 225),
    (cx + 204, cy - 194),
    (cx + 218, cy - 18),
]
draw.polygon(heart, fill=(255, 255, 255, 246))

# Tiny highlight, giving the mark a polished iOS feel.
draw.ellipse((cx - 82, cy - 150, cx - 28, cy - 96), fill=(255, 255, 255, 190))

# App Store icons must be opaque. Downsample for high-quality antialiasing.
final = base.convert("RGB").resize((FINAL, FINAL), Image.Resampling.LANCZOS)
OUT.parent.mkdir(parents=True, exist_ok=True)
final.save(OUT, "PNG", optimize=True)
print(f"Generated {OUT} ({OUT.stat().st_size} bytes)")
