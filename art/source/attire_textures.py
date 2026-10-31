"""Flat textures for the dressage outfit (data/attire/).

The wardrobe's tweed jacket has its check painted into its diffuse map, and the Chelsea boots
have their brown baked in with no colour mask. EqAttire swaps their diffuse map for one of these
at runtime. A flat texture needs no UV layout, so it fits a base-game mesh we cannot read.

    python3 art/source/attire_textures.py
"""

import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from eqdds import save_bc7, save_dxt1  # noqa: E402
from PIL import Image, ImageDraw  # noqa: E402

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "data", "attire")

# name -> sRGB colour. Cloth is near white so the item's colour (the shader's colorScale on its
# mask) shows as picked; boots have no mask, so their texture is their colour.
TEXTURES = {
    "plainCloth_diffuse": (235, 235, 235),
    "blackLeather_diffuse": (24, 22, 22),
    # the top hat (top_hat.py): a black silk hat has no colour mask either
    "blackSilk_diffuse": (16, 16, 18),
}
SIZE = 16


def hat_icon(path, size=256):
    """The top hat's wardrobe icon: a black silk hat drawn flat, lit from the left."""
    scale = 4
    s = size * scale
    image = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    cx = s // 2
    crown_w, crown_top, crown_bottom = int(s * 0.34), int(s * 0.16), int(s * 0.70)
    brim_w, brim_h = int(s * 0.80), int(s * 0.16)
    # brim back half, crown, band, brim front half, each in vertical stripes for a sheen
    draw.ellipse((cx - brim_w // 2, crown_bottom - brim_h // 2, cx + brim_w // 2, crown_bottom + brim_h // 2), fill=(22, 22, 26, 255))
    for x in range(cx - crown_w // 2, cx + crown_w // 2):
        t = (x - (cx - crown_w // 2)) / crown_w
        shade = int(22 + 70 * max(0.0, 1 - abs(t - 0.3) * 3.2))
        draw.line((x, crown_top, x, crown_bottom), fill=(shade, shade, shade + 4, 255))
        band = int(12 + 25 * max(0.0, 1 - abs(t - 0.3) * 3.2))
        draw.line((x, crown_bottom - int(s * 0.10), x, crown_bottom - int(s * 0.02)), fill=(band, band, band + 2, 255))
    draw.ellipse((cx - crown_w // 2, crown_top - int(s * 0.04), cx + crown_w // 2, crown_top + int(s * 0.04)), fill=(40, 40, 46, 255))
    draw.chord((cx - brim_w // 2, crown_bottom - brim_h // 2, cx + brim_w // 2, crown_bottom + brim_h // 2), 0, 180, fill=(30, 30, 35, 255))
    image = image.resize((size, size), Image.LANCZOS)
    save_bc7(image, path)


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, colour in TEXTURES.items():
        image = np.zeros((SIZE, SIZE, 3), np.uint8)
        image[:, :] = colour
        path = os.path.join(OUT, name + ".dds")
        save_dxt1(image, path)
        print("wrote", os.path.relpath(path))
    path = os.path.join(OUT, "topHat_icon.dds")
    hat_icon(path)
    print("wrote", os.path.relpath(path))


if __name__ == "__main__":
    main()
