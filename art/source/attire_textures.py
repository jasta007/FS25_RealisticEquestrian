"""Flat textures for the dressage outfit (data/attire/).

The wardrobe's tweed jacket has its check painted into its diffuse map, and the Chelsea boots
have their brown baked in with no colour mask. EqAttire swaps their diffuse map for one of these
at runtime. A flat texture needs no UV layout, so it fits a base-game mesh we cannot read.

    python3 art/source/attire_textures.py
"""

import os
import sys

import numpy as np
from PIL import Image, ImageFilter

sys.path.insert(0, os.path.dirname(__file__))
from eqdds import save_dxt1  # noqa: E402

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

# The full-seat breeches (botEquestrian): white with a dark upper seat. Mapped with eqUvGrid
# (James's screenshots, 2026-10-31): the texture wraps round the body with the back seam at its
# left/right edge, waist at the top. Columns G, H | A, B of the 8 x 8 grid are the seat, rows 1-3
# its upper part. The dark ends lower at the seam than at the hips, like a real full seat.
SEAT_SIZE = 512
SEAT_WIDTH = 2 / 8  # either side of the seam
SEAT_DEPTH_SEAM, SEAT_DEPTH_HIP = 3.0 / 8, 2.2 / 8
SEAT_CLOTH, SEAT_DARK = 235, 14


def seat():
    """The full-seat breeches diffuse."""
    u = (np.arange(SEAT_SIZE) + 0.5) / SEAT_SIZE
    seam = np.minimum(u, 1 - u)  # distance round the body from the back seam
    depth = SEAT_DEPTH_SEAM + (SEAT_DEPTH_HIP - SEAT_DEPTH_SEAM) * np.clip(seam / SEAT_WIDTH, 0, 1)
    v = u[:, None]
    dark = (seam[None, :] <= SEAT_WIDTH) & (v <= depth[None, :])
    image = Image.fromarray(np.where(dark, SEAT_DARK, SEAT_CLOTH).astype(np.uint8))
    # a soft edge, so the panel doesn't look cut out
    grey = np.asarray(image.filter(ImageFilter.GaussianBlur(1.2)))
    return np.repeat(grey[:, :, None], 3, axis=2)


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, colour in TEXTURES.items():
        image = np.zeros((SIZE, SIZE, 3), np.uint8)
        image[:, :] = colour
        path = os.path.join(OUT, name + ".dds")
        save_dxt1(image, path)
        print("wrote", os.path.relpath(path))
    path = os.path.join(OUT, "breechesSeat_diffuse.dds")
    save_dxt1(seat(), path)
    print("wrote", os.path.relpath(path))


if __name__ == "__main__":
    main()
