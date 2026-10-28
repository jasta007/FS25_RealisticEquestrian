"""The staff portraits atlas, gui/eqStaffFaces.dds: 20 faces as white line art on transparent.

Faces by kawsar4404 (Depositphotos, licensed by Jasta007). The source EPS is not in the repo:
pass its path. The sheet is 4 columns by 5 rows; faces are numbered row by row from 1 and go
into a 5 x 4 grid of 204 px cells (200 px used) in a 1024 x 1024 atlas, DXT5 without mipmaps.
Which faces are male, female or either lives in EqStaff.FACES.

Run from the repo root: python3 art/source/staff_faces.py <Silhouettes.eps>. Needs Ghostscript,
Pillow, numpy and etcpak.
"""

import os
import subprocess
import sys
import tempfile

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(__file__))
from menu_icons import save_dxt5  # noqa: E402

ATLAS = 1024
CELL = 204
FACE = 200
COLUMNS = 5


def spans(profile):
    """Runs of non-zero values: the rows or columns of faces on the sheet."""
    out, start = [], None
    for i, value in enumerate(profile > 0):
        if value and start is None:
            start = i
        if not value and start is not None:
            out.append((start, i))
            start = None
    if start is not None:
        out.append((start, len(profile)))
    return out


def main(eps):
    with tempfile.TemporaryDirectory() as tmp:
        png = os.path.join(tmp, "sheet.png")
        subprocess.run(["gs", "-q", "-dSAFER", "-dBATCH", "-dNOPAUSE", "-dEPSCrop", "-sDEVICE=pnggray",
                        "-dGraphicsAlphaBits=4", "-r144", "-sOutputFile=" + png, eps], check=True)
        sheet = np.array(Image.open(png).convert("L"))
    ink = 255 - sheet
    rows, cols = spans((ink > 127).sum(1)), spans((ink > 127).sum(0))
    assert len(rows) == 5 and len(cols) == 4, (rows, cols)

    atlas = Image.new("RGBA", (ATLAS, ATLAS), (255, 255, 255, 0))
    index = 0
    for top, bottom in rows:
        for left, right in cols:
            cell = ink[top:bottom, left:right]
            ys, xs = np.nonzero(cell > 8)
            cell = cell[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
            # Square, centred, with a small margin, then down to FACE px.
            side = int(max(cell.shape) * 1.06)
            square = np.zeros((side, side), dtype=np.uint8)
            y0, x0 = (side - cell.shape[0]) // 2, (side - cell.shape[1]) // 2
            square[y0:y0 + cell.shape[0], x0:x0 + cell.shape[1]] = cell
            alpha = Image.fromarray(square).resize((FACE, FACE), Image.LANCZOS)
            face = Image.new("RGBA", (FACE, FACE), (255, 255, 255, 0))
            face.putalpha(alpha)
            atlas.paste(face, ((index % COLUMNS) * CELL, (index // COLUMNS) * CELL))
            index += 1
    save_dxt5(atlas, "gui/eqStaffFaces.dds")

    with open("gui/eqStaffFaces.xml", "w") as f:
        f.write("<!-- Realistic Equestrian by Jasta007. Faces by kawsar4404. Made by art/source/staff_faces.py. -->\n")
        f.write("<texture>\n\t<meta>\n\t\t<filename>eqStaffFaces.dds</filename>\n")
        f.write('\t\t<size width="%d" height="%d"/>\n\t</meta>\n\t<slices>\n' % (ATLAS, ATLAS))
        for i in range(index):
            f.write('\t\t<slice id="face%02d" uvs="%dpx %dpx %dpx %dpx"/>\n'
                    % (i + 1, (i % COLUMNS) * CELL, (i // COLUMNS) * CELL, FACE, FACE))
        f.write("\t</slices>\n</texture>\n")
    print("wrote %d faces" % index)


if __name__ == "__main__":
    main(sys.argv[1])
