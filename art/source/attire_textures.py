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
from eqdds import save_dxt1  # noqa: E402

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "data", "attire")

# name -> sRGB colour. Cloth is near white so the item's colour (the shader's colorScale on its
# mask) shows as picked; boots have no mask, so their texture is their colour.
TEXTURES = {
    "plainCloth_diffuse": (235, 235, 235),
    "blackLeather_diffuse": (24, 22, 22),
}
SIZE = 16


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, colour in TEXTURES.items():
        image = np.zeros((SIZE, SIZE, 3), np.uint8)
        image[:, :] = colour
        path = os.path.join(OUT, name + ".dds")
        save_dxt1(image, path)
        print("wrote", os.path.relpath(path))


if __name__ == "__main__":
    main()
