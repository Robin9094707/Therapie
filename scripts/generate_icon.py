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

# Composite translucent layers before converting to RGB; drawing alpha directly
# into the final surface used to flatten the glass plate into solid white.
plate = Image.new("RGBA", (S, S), (0, 0, 0, 0))
d = ImageDraw.Draw(plate)
d.rounded_rectangle((270, 270, 1778, 1778), radius=390,
                    fill=(255, 255, 255, 20), outline=(255, 255, 255, 55), width=6)
base = Image.alpha_composite(base, plate)
mark_layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
d = ImageDraw.Draw(mark_layer)
points = []
for i in range(1200):
    t = i / 1199 * 2 * math.pi
    denom = 1 + math.sin(t) ** 2
    points.append((S / 2 + math.cos(t) / denom * 580,
                   S / 2 + math.sin(t) * math.cos(t) / denom * 750))
# Overlapping opaque discs give the continuous path smooth round joints.
for x, y in points:
    radius = 57
    d.ellipse((x-radius, y-radius, x+radius, y+radius), fill=(255, 255, 255, 255))
base = Image.alpha_composite(base, mark_layer)

# App Store icons must be opaque. Downsample for high-quality antialiasing.
final = base.convert("RGB").resize((FINAL, FINAL), Image.Resampling.LANCZOS)
OUT.parent.mkdir(parents=True, exist_ok=True)
final.save(OUT, "PNG", optimize=True)
print(f"Generated {OUT} ({OUT.stat().st_size} bytes)")


# Explicit iPhone slots produce loose 2x/3x icons used by SpringBoard.
import json
slots = [(20, 2), (20, 3), (29, 2), (29, 3), (40, 2), (40, 3), (60, 2), (60, 3)]
images = []
for points, scale in slots:
    name = f"AppIcon-{points}@{scale}x.png"
    final.resize((points * scale, points * scale), Image.Resampling.LANCZOS).save(OUT.parent / name)
    images.append({"idiom": "iphone", "size": f"{points}x{points}", "scale": f"{scale}x", "filename": name})
images.append({"idiom": "ios-marketing", "size": "1024x1024", "scale": "1x", "filename": "AppIcon.png"})
(OUT.parent / "Contents.json").write_text(json.dumps({"images": images, "info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
mark = OUT.parent.parent / "TherapyMark.imageset"
mark.mkdir(exist_ok=True)
final.resize((312, 312), Image.Resampling.LANCZOS).save(mark / "TherapyMark.png")
(mark / "Contents.json").write_text(json.dumps({"images": [{"idiom": "universal", "filename": "TherapyMark.png", "scale": "3x"}], "info": {"author": "xcode", "version": 1}}, indent=2) + "\n")

# Xcode 26 may keep the 3x icon only in Assets.car. Also ship the registered
# loose 3x image so sideloading tools and SpringBoard can resolve it directly.
resources = Path("TherapieApp/Resources")
resources.mkdir(exist_ok=True)
final.resize((180, 180), Image.Resampling.LANCZOS).save(resources / "AppIcon60x60@3x.png")
