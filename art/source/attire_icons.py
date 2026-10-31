"""Wardrobe icons for the recoloured base-game items (breeches, gloves, jacket).

The game's meshes are locked in its archives, so these start from the game's own icons as the
wardrobe shows them, selected (on the green tile, which keys out cleanly): screenshots James
took on 2026-10-31, kept out of the repository in art/source/private/ (wardrobe_trousers.png,
wardrobe_gloves.png, wardrobe_jackets.png). Each is cut out and recoloured to the item's
first colour: white breeches, black leather gloves, a black jacket with a white shirt.

    python3 art/source/attire_icons.py

Part of Realistic Equestrian by Jasta007.
"""

import os
import sys

import numpy as np
from PIL import Image, ImageFilter

sys.path.insert(0, os.path.dirname(__file__))
from eqdds import save_dxt5  # noqa: E402

PRIVATE = "art/source/private"
OUT = "data/attire"
# screenshot, the selected tile's box in it, the paint bucket's box in that crop
CROPS = {
    "breeches": ("wardrobe_trousers.png", (1010, 0, 1370, 360), (30, 250, 100, 310)),
    "gloves": ("wardrobe_gloves.png", (370, 360, 710, 670), (20, 200, 90, 260)),
    "jacket": ("wardrobe_jackets.png", (675, 960, 1020, 1310), (30, 240, 90, 300)),
}


def cut(name):
    """The crop as floats and its alpha: the green tile and the dark page around it removed."""
    file, box, bucket = CROPS[name]
    a = np.asarray(Image.open(os.path.join(PRIVATE, file)).convert("RGB").crop(box)).astype(np.float32)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    green = (g > r + 18) & (g > b + 30)
    page = (np.abs(r - 40) < 14) & (np.abs(g - 42) < 14) & (np.abs(b - 38) < 14) & (np.abs(r - g) < 8)
    alpha = ~(green | page)
    x0, y0, x1, y1 = bucket
    alpha[y0:y1, x0:x1] = False
    alpha = Image.fromarray((alpha * 255).astype(np.uint8)).filter(ImageFilter.MedianFilter(5))
    return a, np.asarray(alpha).astype(np.float32) / 255


def lum(a):
    return a[..., 0] * 0.3 + a[..., 1] * 0.59 + a[..., 2] * 0.11


def blur(values, radius):
    image = Image.fromarray(np.clip(values, 0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(radius))
    return np.asarray(image).astype(np.float32)


def save(grey, alpha, name, blue=1.0):
    rgb = np.clip(np.stack([grey, grey, grey * blue], -1), 0, 255).astype(np.uint8)
    image = Image.fromarray(rgb).convert("RGBA")
    image.putalpha(Image.fromarray((alpha * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.8)))
    image = image.crop(image.getbbox())
    w, h = image.size
    side = int(max(w, h) * 1.08)
    square = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    square.paste(image, ((side - w) // 2, (side - h) // 2))
    path = os.path.join(OUT, name + "_icon.dds")
    save_dxt5(square.resize((256, 256), Image.LANCZOS), path)
    print("wrote", path)


def main():
    a, alpha = cut("breeches")
    t = np.clip((blur(lum(a), 1.2) - 55) / 85, 0, 1) ** 0.8
    save(150 + 102 * t, alpha, "breeches", 0.99)

    a, alpha = cut("gloves")
    # one even black leather: the old fabric panels and highlights flattened (James, 2026-10-31)
    save(10 + 0.5 * np.minimum(blur(lum(a), 2.0), 48), alpha, "gloves", 1.0)

    a, alpha = cut("jacket")
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    shirt = ((r > 150) & (r - g > 25) & (b > g - 15)).astype(np.uint8) * 255
    shirt = np.asarray(Image.fromarray(shirt).filter(ImageFilter.MaxFilter(3))).astype(np.float32) / 255
    cloth = 8 + 0.16 * blur(lum(a), 3)
    white = np.clip(150 + 0.45 * lum(a), 0, 252)
    save(cloth * (1 - shirt) + white * shirt, alpha, "jacket", 1.04)


if __name__ == "__main__":
    main()
