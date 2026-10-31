"""A labelled test grid (data/attire/uvGrid_diffuse.dds) for finding where a base-game item's
texture lands on the body: eqUvGrid puts it on as the item's diffuse map, and a screenshot shows
which squares cover which part. 8 x 8 squares, columns A-H left to right, rows 1-8 top to
bottom, each its own colour, the label's reading direction showing any mirroring.

    python3 art/source/uv_grid.py

Part of Realistic Equestrian by Jasta007.
"""

import colorsys
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(__file__))
from eqdds import save_dxt1  # noqa: E402

SIZE, CELLS = 1024, 8
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
OUT = "data/attire/uvGrid_diffuse.dds"


def main():
    image = Image.new("RGB", (SIZE, SIZE))
    draw = ImageDraw.Draw(image)
    font = ImageFont.truetype(FONT, 46)
    cell = SIZE // CELLS
    for row in range(CELLS):
        for col in range(CELLS):
            hue = col / CELLS
            light = 0.35 + 0.4 * (row % 2) + 0.05 * (row // 2)
            r, g, b = (int(255 * c) for c in colorsys.hls_to_rgb(hue, light, 0.9))
            box = (col * cell, row * cell, (col + 1) * cell - 1, (row + 1) * cell - 1)
            draw.rectangle(box, fill=(r, g, b), outline=(0, 0, 0), width=3)
            text = "ABCDEFGH"[col] + str(row + 1)
            ink = (0, 0, 0) if light > 0.55 else (255, 255, 255)
            draw.text((col * cell + cell // 2, row * cell + cell // 2), text, font=font, fill=ink, anchor="mm")
            # a small mark in the top left corner of each square shows which way up it is
            draw.rectangle((col * cell + 8, row * cell + 8, col * cell + 24, row * cell + 24), fill=ink)
    save_dxt1(np.asarray(image), OUT)
    image.save(os.path.join(os.environ.get("TMPDIR", "/tmp"), "uvGrid.png"))
    print(f"wrote {OUT}")


if __name__ == "__main__":
    main()
