import math, random
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageEnhance
src = Image.open("under.png").convert("RGB")
S = src.size[0]
base = np.asarray(src).astype(np.float32)
gray = np.asarray(src.convert("L").filter(ImageFilter.GaussianBlur(6))).astype(np.float32)
gy, gx = np.gradient(gray)
mag = np.hypot(gx, gy)
rnd = random.Random(42)

# canvas toned like a primed ground
canvas = Image.new("RGB", (S, S), (196, 180, 150))
subject = np.asarray(Image.open("subject.png")) > 0
plate = Image.open("plate.png").convert("RGB")
def layer(radius, jitter, alpha, length, only_edges=False, sat=1.0, in_subject=False, hue=10, from_plate=False):
    global canvas
    blurred = np.asarray((plate if from_plate else src).filter(ImageFilter.GaussianBlur(radius / 2))).astype(np.float32)
    over = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(over, "RGBA")
    step = max(2, int(radius * (1.1 if in_subject else 0.75)))
    pts = [(x, y) for y in range(0, S, step) for x in range(0, S, step)]
    rnd.shuffle(pts)
    for x, y in pts:
        x = min(S - 1, max(0, x + rnd.randint(-step, step)))
        y = min(S - 1, max(0, y + rnd.randint(-step, step)))
        if only_edges and mag[y, x] < 2.5:
            continue
        if in_subject and not subject[y, x]:
            continue
        c = blurred[y, x] * (1 + rnd.uniform(-jitter, jitter))
        c = c + np.array([rnd.uniform(-1, 1), rnd.uniform(-1, 1), rnd.uniform(-1, 1)]) * hue
        c = np.clip(c, 0, 255)
        # stroke direction: along edges where there are any, else gently horizontal
        if mag[y, x] > 1.5:
            ang = math.atan2(gy[y, x], gx[y, x]) + math.pi / 2
        else:
            ang = rnd.uniform(-0.35, 0.35) + (0 if y > S * 0.6 else rnd.uniform(-0.3, 0.3))
        L = length * rnd.uniform(0.6, 1.3)
        dx, dy = math.cos(ang) * L / 2, math.sin(ang) * L / 2
        w = max(1, int(radius * rnd.uniform(0.7, 1.1)))
        d.line([(x - dx, y - dy), (x + dx, y + dy)], fill=(int(c[0]), int(c[1]), int(c[2]), int(255 * alpha)), width=w)
    canvas = Image.alpha_composite(canvas.convert("RGBA"), over).convert("RGB")

layer(70, 0.05, 0.95, 220, hue=3, from_plate=True)
layer(38, 0.06, 0.85, 130, hue=4, from_plate=True)
# lay the subject in flat first, the way a painter blocks in before working the strokes
obj = Image.open("object.png").convert("L")
fence_and_horse = np.asarray(obj) > 0
canvas = Image.composite(src.filter(ImageFilter.GaussianBlur(4)), canvas, obj)
layer(16, 0.08, 0.9, 44, in_subject=True)
layer(8, 0.08, 0.9, 22, only_edges=True, in_subject=True)
layer(3, 0.05, 0.95, 9, only_edges=True, in_subject=True)

# canvas weave and a faint varnish warmth
noise = np.random.default_rng(1).normal(0, 3, (S, S, 1)).astype(np.float32)
weave = (np.sin(np.arange(S) / 2.2)[None, :, None] + np.sin(np.arange(S) / 2.2)[:, None, None]) * 0.7
arr = np.asarray(canvas).astype(np.float32) + noise + weave
arr = arr * np.array([1.03, 1.0, 0.93])
img = Image.fromarray(np.clip(arr, 0, 255).astype("uint8"))
img = ImageEnhance.Color(img).enhance(0.92)
# soft vignette
v = Image.new("L", (S, S), 0); dv = ImageDraw.Draw(v)
dv.ellipse([-S * 0.15, -S * 0.15, S * 1.15, S * 1.15], fill=255)
v = v.filter(ImageFilter.GaussianBlur(S // 8))
img = Image.composite(img, Image.new("RGB", (S, S), (70, 58, 40)), v)
img.save("painted.png")
crop = img.crop((int(0.06 * S), int(0.09 * S), int(0.86 * S), int(0.89 * S)))
crop.save("painted_crop.png")
crop.resize((512, 512), Image.LANCZOS).save("painted_small.png")
