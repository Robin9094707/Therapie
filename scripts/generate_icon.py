from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024
img = Image.new("RGB", (SIZE, SIZE), (42, 31, 90))
px = img.load()

# Smooth premium gradient, no text.
for y in range(SIZE):
    for x in range(SIZE):
        tx = x / (SIZE - 1)
        ty = y / (SIZE - 1)
        r = int(42 + 55 * tx + 15 * (1 - ty))
        g = int(31 + 110 * ty + 20 * tx)
        b = int(90 + 95 * (1 - tx) + 35 * ty)
        px[x, y] = (min(r,255), min(g,255), min(b,255))

glow = Image.new("RGBA", (SIZE, SIZE), (0,0,0,0))
gd = ImageDraw.Draw(glow)
gd.ellipse((70, 50, 640, 620), fill=(120, 220, 255, 92))
gd.ellipse((430, 370, 1040, 980), fill=(212, 120, 255, 86))
glow = glow.filter(ImageFilter.GaussianBlur(110))
img = Image.alpha_composite(img.convert("RGBA"), glow)

draw = ImageDraw.Draw(img)

# Glass tile
tile = (150, 150, 874, 874)
draw.rounded_rectangle(tile, radius=220, fill=(255,255,255,38), outline=(255,255,255,92), width=8)

# Infinity-like therapy path
points = []
import math
for i in range(520):
    t = i / 519 * 2 * math.pi
    denom = 1 + math.sin(t) ** 2
    x = math.cos(t) / denom
    y = math.sin(t) * math.cos(t) / denom
    points.append((512 + x * 260, 515 + y * 235))

draw.line(points, fill=(255,255,255,235), width=58, joint="curve")

# Small heart in the center
cx, cy = 512, 512
heart = [
    (cx, cy+70),
    (cx-120, cy-35),
    (cx-105, cy-135),
    (cx-20, cy-145),
    (cx, cy-105),
    (cx+20, cy-145),
    (cx+105, cy-135),
    (cx+120, cy-35)
]
draw.polygon(heart, fill=(255,255,255,225))

img.convert("RGB").save("TherapieApp/Assets.xcassets/AppIcon.appiconset/AppIcon.png", quality=95)
