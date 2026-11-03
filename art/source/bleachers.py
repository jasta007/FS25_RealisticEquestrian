"""
Builds the bleachers in placeables/bleachers/: one .xml and .i3d per size, the textures they share
and a shop image for each.

Bleachers are seating for the events you host (James, 2026-10-28): data/hosting.xml counts every
placeable under placeables/bleachers/ within 60 m of a course or dressage arena. Three sizes,
3 rows x 6 m, 5 rows x 10 m and 8 rows x 16 m.

Looking from the front, spectators sit facing -z: row 1 is at the front (z = 0) and the rows climb
towards +z, with a rail along the back. A row of sponsor boards stands in front of them, facing -z
too, so it reads from the arena. Each board's face is its own shape, "eqSponsor_<n>", with its own
material: EqSponsors puts a brand logo from the game on it at run time (the brands are the game's,
never shipped here). The texture it starts with is our own board.

Like the other art scripts, the .i3d files keep their geometry inline, and the textures are
painted here. Collision: one static mesh for the rows, the benches' row and the boards, with the
filter Riding Hall 2k26's jumps use, so horses and players can't walk through.

Run from the repository root: python3 art/source/bleachers.py

Part of Realistic Equestrian by Jasta007.
"""

import os
import random

import numpy as np
from PIL import Image, ImageDraw, ImageFont

from eqdds import save_dxt1
from xc_jumps import COLLISION_GROUP, COLLISION_MASK, Mesh, fmt, shape_lines, store_image

OUT = "placeables/bleachers"
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
CLIP = 400

# name, rows, length (m), price, daily upkeep, sponsor boards in front
SIZES = [
    {"name": "bleachers3x6", "rows": 3, "length": 6, "price": 6000, "upkeep": 5, "boards": 3},
    {"name": "bleachers5x10", "rows": 5, "length": 10, "price": 15000, "upkeep": 10, "boards": 5},
    {"name": "bleachers8x16", "rows": 8, "length": 16, "price": 35000, "upkeep": 20, "boards": 8},
]

ROW_DEPTH = 0.8         # each row's tread, front to back
ROW_RISE = 0.42         # each row is this much higher than the one in front
BASE = 0.3              # the front row's tread above the ground
BENCH_FROM = 0.42       # the bench sits at the back of the tread, from here...
BENCH_TO = 0.74         # ...to here (metres from the tread's front edge)
BENCH_HEIGHT = 0.42
RAIL_HEIGHT = 1.0       # the back rail above the top row
RAIL_POST = 0.06
RAIL_STEP = 2.0         # most space between rail posts
BOARD_GAP = 1.4         # the boards' face stands this far in front of row 1
BOARD_THICK = 0.06
BOARD_BOTTOM = 0.1
BOARD_TOP = 0.9
BOARD_SPACE = 0.08      # between neighbouring boards
LOGO_INSET = 0.07       # the logo's margin inside a board

# Texture atlas: 4 x 4 cells of 64 px, each a flat colour with a little grain.
CELL = 64
CELLS = 4
COLOURS = {
    "steel": (150, 154, 158),      # the stepped frame
    "bench": (198, 202, 206),      # aluminium benches
    "rail": (36, 76, 52),          # dark green back rail and board posts
    "board": (238, 236, 228),      # the boards' backing
    "trim": (30, 66, 46),          # the boards' edges
}
CELL_OF = {name: i for i, name in enumerate(COLOURS)}

# The board a sponsor slot shows until a brand logo is put on it: our own, cream and green.
SPONSOR_SIZE = (512, 192)


def atlas(path):
    rng = np.random.default_rng(11)
    img = np.zeros((CELL * CELLS, CELL * CELLS, 3))
    # Every cell is filled, the spare ones repeating the colours, so the small mip levels
    # (which average neighbouring cells) stay these colours rather than fading to black.
    names = list(COLOURS)
    for i in range(CELLS * CELLS):
        name = names[i % len(names)]
        colour = COLOURS[name]
        x, y = (i % CELLS) * CELL, (i // CELLS) * CELL
        grain = rng.normal(0, 4, (CELL, CELL, 1))
        if name == "bench":
            # brushed: streaks along u
            grain = grain * 0.4 + rng.normal(0, 5, (CELL, 1, 1))
        img[y:y + CELL, x:x + CELL] = np.array(colour) + grain
    rgb = np.clip(img, 0, 255).astype(np.uint8)
    save_dxt1(Image.fromarray(rgb), path)
    return rgb


def cell_uv(name):
    # V counts up from the bottom of the image in GIANTS, so row 0 (the top) is near v = 1.
    i = CELL_OF[name]
    return ((i % CELLS + 0.5) / CELLS, 1 - (i // CELLS + 0.5) / CELLS)


def sponsor_board(path):
    """Our own board, shown until a brand's logo is put on: drawn into the window of the image a
    logo face shows (xc_jumps.LOGO_CROP), in an image shaped like the game's brand logos."""
    import xc_jumps
    full = Image.new("RGB", (512, 256), COLOURS["board"])
    u0, u1, v0, v1 = xc_jumps.LOGO_CROP
    box = (int(round(max(0, u0) * 512)), int(round((1 - v1) * 256)), int(round(min(1, u1) * 512)), int(round((1 - v0) * 256)))
    window = _board_design().resize((box[2] - box[0], box[3] - box[1]), Image.LANCZOS)
    full.paste(window, box[:2])
    save_dxt1(full, path)
    # the shop pictures map a logo face to the whole texture: give them just the window it shows
    return np.asarray(window)


def _board_design():
    w, h = SPONSOR_SIZE
    img = Image.new("RGB", (w, h), COLOURS["board"])
    draw = ImageDraw.Draw(img)
    draw.rectangle([6, 6, w - 7, h - 7], outline=COLOURS["trim"], width=6)
    # a horseshoe, open side up, with its nail holes
    cx, cy, r = 92, h / 2 + 4, 46
    draw.arc([cx - r, cy - r, cx + r, cy + r], -40, 220, fill=COLOURS["trim"], width=16)
    for angle in (10, 50, 130, 170):
        a = np.radians(angle)
        hx, hy = cx + (r - 8) * np.cos(a), cy + (r - 8) * np.sin(a)
        draw.ellipse([hx - 3, hy - 3, hx + 3, hy + 3], fill=COLOURS["board"])
    big = ImageFont.truetype(FONT, 46)
    small = ImageFont.truetype(FONT, 24)
    draw.text((170, h / 2 - 22), "REALISTIC", font=big, fill=COLOURS["trim"], anchor="lm")
    draw.text((170, h / 2 + 28), "EQUESTRIAN", font=small, fill=(120, 96, 40), anchor="lm")
    return img


def box(mesh, x0, x1, y0, y1, z0, z1, cell):
    mesh.box(x0, x1, y0, y1, z0, z1, cell_uv(cell))


def build(size):
    """The frame (steel, benches, rail, boards) in one mesh, each board's logo face, and collision."""
    rows, length = size["rows"], size["length"]
    half = length / 2
    frame, col = Mesh(), Mesh()
    for r in range(rows):
        top = BASE + r * ROW_RISE
        z0, z1 = r * ROW_DEPTH, (r + 1) * ROW_DEPTH
        box(frame, -half, half, 0, top, z0, z1, "steel")
        box(col, -half, half, 0, top, z0, z1, "steel")
        box(frame, -half + 0.05, half - 0.05, top, top + BENCH_HEIGHT, z0 + BENCH_FROM, z0 + BENCH_TO, "bench")
    # the back rail: posts and a top bar
    top = BASE + (rows - 1) * ROW_RISE
    back = rows * ROW_DEPTH
    posts = max(2, int(length / RAIL_STEP) + 1)
    for i in range(posts):
        x = -half + 0.05 + (length - 0.1) * i / (posts - 1)
        box(frame, x - RAIL_POST / 2, x + RAIL_POST / 2, top, top + RAIL_HEIGHT, back - RAIL_POST, back, "rail")
    box(frame, -half, half, top + RAIL_HEIGHT - 0.06, top + RAIL_HEIGHT, back - RAIL_POST - 0.01, back + 0.01, "rail")
    box(col, -half, half, top, top + RAIL_HEIGHT, back - RAIL_POST, back, "rail")

    # sponsor boards in front, their faces at z = -BOARD_GAP
    logos = []
    # each board's face, a plain painted quad behind its logo: EqJumpColours paints it dark
    # behind a pale logo (James, 2026-11-01: white Volvo on the white boards)
    face = Mesh()
    count = size["boards"]
    width = length / count
    zf, zb = -BOARD_GAP, -BOARD_GAP + BOARD_THICK
    for i in range(count):
        x0 = -half + i * width + BOARD_SPACE / 2
        x1 = x0 + width - BOARD_SPACE
        box(frame, x0, x1, BOARD_BOTTOM, BOARD_TOP, zf, zb, "board")
        box(frame, x0, x1, BOARD_TOP, BOARD_TOP + 0.03, zf - 0.005, zb + 0.005, "trim")
        for px in (x0 + 0.1, x1 - 0.1):
            box(frame, px - 0.03, px + 0.03, 0, BOARD_BOTTOM, zf + 0.01, zb - 0.01, "rail")
        box(col, x0, x1, 0, BOARD_TOP, zf, zb, "board")
        zface = zf - 0.002
        face.quad([(x1, BOARD_BOTTOM, zface), (x0, BOARD_BOTTOM, zface), (x0, BOARD_TOP, zface), (x1, BOARD_TOP, zface)],
                  (0, 0, -1), [(0, 0), (1, 0), (1, 1), (0, 1)])
        # the logo: one quad just in front of the board's face, the whole texture on it
        logo = Mesh()
        lx0, lx1 = x0 + LOGO_INSET, x1 - LOGO_INSET
        ly0, ly1 = BOARD_BOTTOM + LOGO_INSET, BOARD_TOP - LOGO_INSET
        z = zf - 0.004
        # facing -z: seen from the front, +x is on the left, so u runs from +x to -x; v = 0 is
        # the image's bottom row in GIANTS
        logo.quad([(lx1, ly0, z), (lx0, ly0, z), (lx0, ly1, z), (lx1, ly1, z)], (0, 0, -1),
                  [(0, 0), (1, 0), (1, 1), (0, 1)])
        logos.append(logo)
    return frame, logos, col, face


SHADER = "$data/shaders/vehicleShader.xml"
PAINT_MAPS = {"detailDiffuse": "$data/shared/detailLibrary/calibrated/calibratedPaint_diffuse.png",
              "detailNormal": "$data/shared/detailLibrary/calibrated/calibratedPaint_normal.png",
              "detailSpecular": "$data/shared/detailLibrary/calibrated/calibratedPaint_specular.png"}
FACE_WHITE = (0.80, 0.80, 0.78)   # EqSponsorBoards.FACE_WHITE


def write_i3d(size, path, frame, logos, col, face):
    name = size["name"]
    lines = [
        '<?xml version="1.0" encoding="iso-8859-1"?>',
        "",
        f'<i3D name="{name}" version="1.6" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
        'xsi:noNamespaceSchemaLocation="http://i3d.giants.ch/schema/i3d-1.6.xsd">',
        "  <Asset>",
        '    <Export program="Realistic Equestrian bleachers.py" version="1"/>',
        "  </Asset>",
        "  <Files>",
        '    <File fileId="1" filename="bleachers_diffuse.dds"/>',
        '    <File fileId="2" filename="bleacherSponsor_diffuse.dds"/>',
        f'    <File fileId="3" filename="{SHADER}"/>',
    ] + [f'    <File fileId="{4 + i}" filename="{f}"/>' for i, f in enumerate(PAINT_MAPS.values())] + [
        "  </Files>",
        "  <Materials>",
        '    <Material name="bleachers" materialId="1" specularColor="0.3 0.6 0">',
        '      <Texture fileId="1"/>',
        "    </Material>",
    ]
    # One material per board, so each can show its own logo (EqSponsors replaces the texture).
    for i in range(len(logos)):
        lines += [
            f'    <Material name="eqSponsor{i + 1}" materialId="{i + 2}" specularColor="0.2 0 0" alphaBlending="true">',
            '      <Texture fileId="2"/>',
            "    </Material>",
        ]
    face_id = len(logos) + 2
    lines.append(f'    <Material name="eqBoardFace" materialId="{face_id}" customShaderId="3">')
    lines += [f'      <Custommap name="{k}" fileId="{4 + i}"/>' for i, k in enumerate(PAINT_MAPS)]
    lines += [f'      <CustomParameter name="colorScale" value="{fmt(FACE_WHITE)}"/>',
              '      <CustomParameter name="smoothnessScale" value="0.4"/>',
              '      <CustomParameter name="metalnessScale" value="0"/>', "    </Material>"]
    lines.append("  </Materials>")
    lines.append("  <Shapes>")
    lines += shape_lines(frame, f"{name}_frame", 1)
    for i, logo in enumerate(logos):
        lines += shape_lines(logo, f"{name}_sponsor{i + 1}", i + 2)
    lines += shape_lines(face, f"{name}_face", face_id)
    col_id = len(logos) + 3
    lines += shape_lines(col, f"{name}_collision", col_id)
    lines.append("  </Shapes>")
    lines.append("  <Scene>")
    lines.append(f'    <TransformGroup name="{name}" nodeId="1">')
    lines.append(f'      <Shape name="frame" shapeId="1" clipDistance="{CLIP}" nodeId="2" materialIds="1" '
                 'castsShadows="true" receiveShadows="true"/>')
    lines.append(f'      <Shape name="eqBoardFace" shapeId="{face_id}" clipDistance="{CLIP}" nodeId="3" materialIds="{face_id}" '
                 'castsShadows="false" receiveShadows="true"/>')
    lines.append('      <TransformGroup name="eqSponsors" nodeId="4">')
    node = 5
    for i in range(len(logos)):
        lines.append(f'        <Shape name="eqSponsor_{i + 1}" shapeId="{i + 2}" clipDistance="{CLIP}" nodeId="{node}" '
                     f'materialIds="{i + 2}" castsShadows="false" receiveShadows="true"/>')
        node += 1
    lines.append("      </TransformGroup>")
    lines.append(f'      <TransformGroup name="collision" nodeId="{node}">')
    lines.append(f'        <Shape name="col" shapeId="{col_id}" static="true" collisionFilterGroup="{COLLISION_GROUP}" '
                 f'collisionFilterMask="{COLLISION_MASK}" density="0.01" nodeId="{node + 1}" nonRenderable="true" materialIds="1"/>')
    lines.append("      </TransformGroup>")
    lines += ["    </TransformGroup>", "  </Scene>", "</i3D>"]
    with open(path, "w", encoding="iso-8859-1", newline="\n") as f:
        f.write("\n".join(lines) + "\n")


def write_xml(size, path):
    name = size["name"]
    rows, length = size["rows"], size["length"]
    depth = rows * ROW_DEPTH
    text = f"""<?xml version="1.0" encoding="utf-8" standalone="no"?>
<!-- Made by art/source/bleachers.py: change that and run it again rather than editing this. -->
<placeable type="simplePlaceable">
    <storeData>
        <name>$l10n_eq_shop_{name}</name>
        <functions>
            <function>$l10n_eq_shop_bleachers_function</function>
            <function>$l10n_eq_shop_bleachersSponsors_function</function>
            <function>$l10n_eq_shop_signboard_function</function>
        </functions>
        <image>placeables/bleachers/store_{name}.dds</image>
        <price>{size["price"]}</price>
        <dailyUpkeep>{size["upkeep"]}</dailyUpkeep>
        <lifetime>1000</lifetime>
        <rotation>0</rotation>
        <brand>NONE</brand>
        <species>placeable</species>
        <category>animalpens</category>
        <brush>
            <type>placeable</type>
            <category>animals</category>
            <tab>horses</tab>
        </brush>
    </storeData>

    <base>
        <filename>placeables/bleachers/{name}.i3d</filename>
        <canBeRenamed>false</canBeRenamed>
    </base>

    <placement useRandomYRotation="false" useManualYRotation="true">
        <!-- {rows} rows over {length} x {depth:.1f} m; spectators face -z, the sponsor boards stand {BOARD_GAP:g} m in front. -->
    </placement>
</placeable>
"""
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)


def main():
    os.makedirs(OUT, exist_ok=True)
    preview_dir = "art/previews"
    atlas_rgb = atlas(os.path.join(OUT, "bleachers_diffuse.dds"))
    sponsor_rgb = sponsor_board(os.path.join(OUT, "bleacherSponsor_diffuse.dds"))
    for size in SIZES:
        name = size["name"]
        frame, logos, col, face = build(size)
        write_i3d(size, os.path.join(OUT, name + ".i3d"), frame, logos, col, face)
        write_xml(size, os.path.join(OUT, name + ".xml"))
        # our preview renderer reads v from the top of the image, GIANTS from the bottom
        plain = np.full((4, 4, 3), COLOURS["board"], dtype=float)
        store_image([(frame, atlas_rgb[::-1]), (face, plain)] + [(logo, sponsor_rgb[::-1]) for logo in logos],
                    os.path.join(OUT, "store_" + name + ".dds"), preview_dir, yaw=-140)
        print(name, len(frame.tris) + sum(len(m.tris) for m in logos), "triangles,", len(logos), "sponsor boards")


if __name__ == "__main__":
    random.seed(1)
    main()
