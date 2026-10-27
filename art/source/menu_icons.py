"""The menu tab icons atlas, gui/eqMenuIcons.dds: white line icons on transparent, 512 px each.

- events (0, 0): the rosette, kept from the existing atlas (read back from the current file).
- staff (512, 0): two people, for the Staff tab.

Run from the repo root: python3 art/source/menu_icons.py. Needs Pillow, numpy and etcpak.
The atlas is DXT5 without mipmaps, like the file it replaces.
"""

import struct

import etcpak
import numpy as np
from PIL import Image, ImageDraw

SIZE = 512
SCALE = 4
STROKE = 17


def person(draw, cx, top, head, shoulders, height, width):
    """One figure: a head circle and a shoulders arch, as outlines."""
    s = SCALE
    w = STROKE * s
    draw.ellipse([(cx - head) * s, top * s, (cx + head) * s, (top + 2 * head) * s], outline=255, width=w)
    y0 = top + 2 * head + shoulders
    box = [(cx - width) * s, y0 * s, (cx + width) * s, (y0 + 2 * height) * s]
    draw.arc(box, 180, 360, fill=255, width=w)
    # Close the arch at the bottom so it reads as a body.
    draw.line([(cx - width) * s + w // 2, (y0 + height) * s, (cx + width) * s - w // 2, (y0 + height) * s], fill=255, width=w)


def staff_icon():
    mask = Image.new("L", (SIZE * SCALE, SIZE * SCALE), 0)
    draw = ImageDraw.Draw(mask)
    person(draw, 330, 120, 62, 26, 120, 120)    # behind, right
    # The front figure is drawn over a cleared area so the lines don't cross.
    s = SCALE
    draw.ellipse([(200 - 92) * s, 120 * s, (200 + 92) * s, (120 + 184) * s], fill=0)
    draw.rectangle([(200 - 160) * s, 330 * s, (200 + 160) * s, 470 * s], fill=0)
    person(draw, 200, 135, 72, 30, 140, 140)
    mask = mask.resize((SIZE, SIZE), Image.LANCZOS)
    img = Image.new("RGBA", (SIZE, SIZE), (255, 255, 255, 0))
    img.putalpha(mask)
    return img


def save_dxt5(img, path):
    w, h = img.size
    data = etcpak.compress_bc3(np.ascontiguousarray(np.asarray(img.convert("RGBA"))).tobytes(), w, h)
    header = struct.pack("<4s7I44x", b"DDS ", 124, 0x1 | 0x2 | 0x4 | 0x1000 | 0x80000, h, w, len(data), 0, 1)
    header += struct.pack("<2I4s5I", 32, 0x4, b"DXT5", 0, 0, 0, 0, 0)
    header += struct.pack("<5I", 0x1000, 0, 0, 0, 0)
    assert len(header) == 128
    with open(path, "wb") as f:
        f.write(header + data)


def main():
    events = Image.open("gui/eqMenuIcons.dds").convert("RGBA").crop((0, 0, SIZE, SIZE))
    atlas = Image.new("RGBA", (SIZE * 2, SIZE), (255, 255, 255, 0))
    atlas.paste(events, (0, 0))
    atlas.paste(staff_icon(), (SIZE, 0))
    save_dxt5(atlas, "gui/eqMenuIcons.dds")


if __name__ == "__main__":
    main()
