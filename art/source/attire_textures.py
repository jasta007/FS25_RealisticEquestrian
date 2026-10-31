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
from eqdds import save_dxt1, save_dxt5  # noqa: E402
from PIL import Image, ImageDraw  # noqa: E402

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "data", "attire")

# name -> sRGB colour. Cloth is near white so the item's colour (the shader's colorScale on its
# mask) shows as picked; boots have no mask, so their texture is their colour.
TEXTURES = {
    "plainCloth_diffuse": (235, 235, 235),
    "blackLeather_diffuse": (24, 22, 22),
    # the top hat (top_hat.py): a black silk hat has no colour mask either
    "blackSilk_diffuse": (16, 16, 18),
    # a flat normal map: takes the tweed's weave and the gloves' knit off their shapes
    "flat_normal": (128, 128, 255),
}
SIZE = 16


def boots_icon(path, size=256):
    """The riding boots' wardrobe icon: a pair of tall black boots side on, lit from the left."""
    scale = 4
    s = size * scale
    image = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)

    def boot(x0, shade):
        top, ankle, sole = int(s * 0.10), int(s * 0.70), int(s * 0.86)
        w = int(s * 0.13)
        toe = x0 + int(s * 0.30)
        dark = (shade, shade, shade + 3, 255)
        draw.polygon([(x0, top), (x0 + w, top - int(s * 0.03)), (x0 + w, ankle), (toe, ankle + int(s * 0.06)),
                      (toe + int(s * 0.02), sole), (x0, sole)], fill=dark)
        draw.rectangle((x0, sole - int(s * 0.025), toe + int(s * 0.02), sole), fill=(8, 8, 10, 255))
        for x in range(x0 + int(w * 0.15), x0 + int(w * 0.45)):
            draw.line((x, top + int(s * 0.02), x, ankle), fill=(shade + 30, shade + 30, shade + 34, 255))

    boot(int(s * 0.06), 24)
    boot(int(s * 0.40), 34)
    image = image.resize((size, size), Image.LANCZOS)
    save_dxt5(image, path)


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, colour in TEXTURES.items():
        image = np.zeros((SIZE, SIZE, 3), np.uint8)
        image[:, :] = colour
        path = os.path.join(OUT, name + ".dds")
        save_dxt1(image, path)
        print("wrote", os.path.relpath(path))
    for name, draw in (("ridingBoots_icon", boots_icon),):
        path = os.path.join(OUT, name + ".dds")
        draw(path)
        print("wrote", os.path.relpath(path))


if __name__ == "__main__":
    main()
