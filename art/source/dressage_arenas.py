"""
Builds the dressage arena placeables in placeables/dressageArena/: one .xml and .i3d per size, the
letter texture shared by all of them and a shop image for each.

The .i3d files keep their geometry inline (<IndexedTriangleSet>), so no GIANTS tools are needed.
Each arena is one shape (the white rail, the letter boxes and the centre line plates) with no
collision, and an empty transform group per letter, named "eqMarker_<letter>", which the dressage
routine reads (EqDressageHooks).

Layout, looking down with A nearest: K E H (and V S on 20x60) up the left side, F B M (P R) up the
right side, C at the far end and D X G (L I) on the centre line. Letters on the long sides stand
6 m from the corners and 12 m apart, as in the FEI arena plans; the 15x30 schooling arena spaces the
20x40 letters in proportion.

Run from the repository root: python3 art/source/dressage_arenas.py

Part of Realistic Equestrian by Jasta007.
"""

import os

from PIL import Image, ImageDraw, ImageFont

OUT = "placeables/dressageArena"
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"

# name, width, length, letters along the long sides (left, right) and the centre line, each with
# its distance from the A end in metres.
ARENAS = [
    {
        # a schooling arena: the 20x40 letters, spaced in proportion
        "name": "dressageArena15x30", "width": 15, "length": 30, "price": 1000,
        "left": [("K", 4.5), ("E", 15), ("H", 25.5)],
        "right": [("F", 4.5), ("B", 15), ("M", 25.5)],
        "centre": [("D", 4.5), ("X", 15), ("G", 25.5)],
    },
    {
        "name": "dressageArena20x40", "width": 20, "length": 40, "price": 1500,
        "left": [("K", 6), ("E", 20), ("H", 34)],
        "right": [("F", 6), ("B", 20), ("M", 34)],
        "centre": [("D", 6), ("X", 20), ("G", 34)],
    },
    {
        "name": "dressageArena20x60", "width": 20, "length": 60, "price": 2000,
        "left": [("K", 6), ("V", 18), ("E", 30), ("S", 42), ("H", 54)],
        "right": [("F", 6), ("P", 18), ("B", 30), ("R", 42), ("M", 54)],
        "centre": [("D", 6), ("L", 18), ("X", 30), ("I", 42), ("G", 54)],
    },
]

# Rail: white boards round the edge, with a gap at A to ride in.
RAIL_HEIGHT = 0.3
RAIL_THICK = 0.06
# Half the board sits below the ground, so the rail stands 15 cm high (James, 2026-10-27).
RAIL_SUNK = 0.15
GATE = 2.0
# Letter boxes stand this far outside the rail; centre line letters are plates on the ground.
MARKER_GAP = 0.6
MARKER_SIZE = 0.32
MARKER_HEIGHT = 0.42
PLATE_SIZE = 0.5
PLATE_HEIGHT = 0.02

# The texture is one row of cells, a plain white one first and then A to Z. One row means a
# flipped V coordinate can only turn a letter upside down, never swap it for another.
CELL = 64
CELLS = 32


def letter_texture(path):
    img = Image.new("RGB", (CELL * CELLS, CELL), (245, 245, 242))
    draw = ImageDraw.Draw(img)
    font = ImageFont.truetype(FONT, int(CELL * 0.72))
    for i in range(26):
        cx = (i + 1) * CELL + CELL / 2
        draw.text((cx, CELL / 2), chr(65 + i), font=font, fill=(18, 18, 18), anchor="mm")
        # a thin grey frame so the letter face reads as a board
        x0 = (i + 1) * CELL
        draw.rectangle([x0 + 1, 1, x0 + CELL - 2, CELL - 2], outline=(150, 150, 150), width=1)
    img.save(path, pixel_format="DXT1")
    mark_dds(path)


def mark_dds(path, text=b"Realistic Equestrian by Jasta007"):
    """Name the author in the DDS header's reserved bytes, like the mod icon."""
    with open(path, "r+b") as f:
        f.seek(32)
        f.write(text[:44].ljust(44, b"\0"))


def cell_uv(letter):
    """u0, u1 of a letter's cell (None = the white cell), inset half a texel."""
    index = 0 if letter is None else ord(letter) - 64
    pad = 0.5 / (CELL * CELLS)
    return index / CELLS + pad, (index + 1) / CELLS - pad


class Mesh:
    def __init__(self):
        self.verts = []  # (p, n, uv)
        self.tris = []

    def quad(self, a, b, c, d, n, letter=None):
        """Four corners counter-clockwise seen from the front; the letter's top is the c-d edge."""
        u0, u1 = cell_uv(letter)
        base = len(self.verts)
        for p, uv in ((a, (u0, 0.0)), (b, (u1, 0.0)), (c, (u1, 1.0)), (d, (u0, 1.0))):
            if letter is None:
                uv = ((u0 + u1) / 2, 0.5)
            self.verts.append((p, n, uv))
        self.tris.append((base, base + 1, base + 2))
        self.tris.append((base, base + 2, base + 3))

    def box(self, x0, x1, y0, y1, z0, z1, sides=None, top=None, bottom=True):
        """sides: the letter on the four upright faces; top: the letter on top, reading towards -z."""
        self.quad((x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1), (0, 0, 1), sides)
        self.quad((x1, y0, z0), (x0, y0, z0), (x0, y1, z0), (x1, y1, z0), (0, 0, -1), sides)
        self.quad((x1, y0, z1), (x1, y0, z0), (x1, y1, z0), (x1, y1, z1), (1, 0, 0), sides)
        self.quad((x0, y0, z0), (x0, y0, z1), (x0, y1, z1), (x0, y1, z0), (-1, 0, 0), sides)
        self.quad((x0, y1, z1), (x1, y1, z1), (x1, y1, z0), (x0, y1, z0), (0, 1, 0), top)
        if bottom:
            self.quad((x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1), (0, -1, 0))


def layout(arena):
    """Every marker as (letter, x, z, kind); A at +z, C at -z, K E H on -x."""
    w, l = arena["width"], arena["length"]
    half_w, half_l = w / 2, l / 2
    out = half_w + MARKER_GAP
    markers = [("A", 0.0, half_l + MARKER_GAP, "box"), ("C", 0.0, -half_l - MARKER_GAP, "box")]
    for letter, d in arena["left"]:
        markers.append((letter, -out, half_l - d, "box"))
    for letter, d in arena["right"]:
        markers.append((letter, out, half_l - d, "box"))
    for letter, d in arena["centre"]:
        markers.append((letter, 0.0, half_l - d, "plate"))
    return markers


def build_mesh(arena):
    mesh = Mesh()
    half_w, half_l = arena["width"] / 2, arena["length"] / 2
    t, y0, y1 = RAIL_THICK, -RAIL_SUNK, RAIL_HEIGHT - RAIL_SUNK
    # long sides, the C end, and the A end either side of the gate
    mesh.box(-half_w - t, -half_w, y0, y1, -half_l - t, half_l + t)
    mesh.box(half_w, half_w + t, y0, y1, -half_l - t, half_l + t)
    mesh.box(-half_w, half_w, y0, y1, -half_l - t, -half_l)
    mesh.box(-half_w, -GATE / 2, y0, y1, half_l, half_l + t)
    mesh.box(GATE / 2, half_w, y0, y1, half_l, half_l + t)
    for letter, x, z, kind in layout(arena):
        if kind == "box":
            s = MARKER_SIZE / 2
            mesh.box(x - s, x + s, 0, MARKER_HEIGHT, z - s, z + s, sides=letter)
        else:
            s = PLATE_SIZE / 2
            mesh.box(x - s, x + s, 0, PLATE_HEIGHT, z - s, z + s, top=letter, bottom=False)
    return mesh


def fmt(values):
    return " ".join(f"{v:.6g}" for v in values)


def write_i3d(arena, path):
    mesh = build_mesh(arena)
    half_w, half_l = arena["width"] / 2, arena["length"] / 2
    radius = ((half_w + 1) ** 2 + (half_l + 1) ** 2) ** 0.5
    lines = [
        '<?xml version="1.0" encoding="iso-8859-1"?>',
        "",
        f'<i3D name="{arena["name"]}" version="1.6" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
        'xsi:noNamespaceSchemaLocation="http://i3d.giants.ch/schema/i3d-1.6.xsd">',
        "  <Asset>",
        '    <Export program="Realistic Equestrian dressage_arenas.py" version="1"/>',
        "  </Asset>",
        "  <Files>",
        '    <File fileId="1" filename="dressageLetters_diffuse.dds"/>',
        "  </Files>",
        "  <Materials>",
        '    <Material name="dressageLetters" materialId="1" specularColor="0.25 0.5 0">',
        '      <Texture fileId="1"/>',
        "    </Material>",
        "  </Materials>",
        "  <Shapes>",
        f'    <IndexedTriangleSet name="{arena["name"]}" shapeId="1" bvCenter="0 0.2 0" bvRadius="{radius:.6g}">',
        f'      <Vertices count="{len(mesh.verts)}" normal="true" uv0="true">',
    ]
    for p, n, uv in mesh.verts:
        lines.append(f'        <v p="{fmt(p)}" n="{fmt(n)}" t0="{fmt(uv)}"/>')
    lines.append("      </Vertices>")
    lines.append(f'      <Triangles count="{len(mesh.tris)}">')
    for tri in mesh.tris:
        lines.append(f'        <t vi="{tri[0]} {tri[1]} {tri[2]}"/>')
    lines.append("      </Triangles>")
    lines.append('      <Subsets count="1">')
    lines.append(f'        <Subset firstVertex="0" numVertices="{len(mesh.verts)}" firstIndex="0" numIndices="{len(mesh.tris) * 3}"/>')
    lines.append("      </Subsets>")
    lines.append("    </IndexedTriangleSet>")
    lines.append("  </Shapes>")
    lines.append("  <Scene>")
    lines.append(f'    <TransformGroup name="{arena["name"]}" nodeId="1">')
    lines.append(f'      <Shape name="arena" shapeId="1" clipDistance="250" nodeId="2" materialIds="1" castsShadows="true" receiveShadows="true"/>')
    lines.append('      <TransformGroup name="eqMarkers" nodeId="3">')
    node = 4
    for letter, x, z, kind in layout(arena):
        y = PLATE_HEIGHT if kind == "plate" else MARKER_HEIGHT
        lines.append(f'        <TransformGroup name="eqMarker_{letter}" translation="{fmt((x, y, z))}" nodeId="{node}"/>')
        node += 1
    lines.append("      </TransformGroup>")
    lines.append("    </TransformGroup>")
    lines.append("  </Scene>")
    lines.append("</i3D>")
    with open(path, "w", encoding="iso-8859-1", newline="\n") as f:
        f.write("\n".join(lines) + "\n")


def write_xml(arena, path):
    name = arena["name"]
    text = f"""<?xml version="1.0" encoding="utf-8" standalone="no"?>
<!-- Made by art/source/dressage_arenas.py: change that and run it again rather than editing this. -->
<placeable type="simplePlaceable">
    <storeData>
        <name>$l10n_eq_shop_{name}</name>
        <functions>
            <function>$l10n_eq_shop_dressageArena_function</function>
        </functions>
        <image>placeables/dressageArena/store_{name}.dds</image>
        <price>{arena["price"]}</price>
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
        <vertexBufferMemoryUsage>0</vertexBufferMemoryUsage>
        <indexBufferMemoryUsage>0</indexBufferMemoryUsage>
        <textureMemoryUsage>0</textureMemoryUsage>
        <instanceVertexBufferMemoryUsage>0</instanceVertexBufferMemoryUsage>
        <instanceIndexBufferMemoryUsage>0</instanceIndexBufferMemoryUsage>
    </storeData>

    <base>
        <filename>placeables/dressageArena/{name}.i3d</filename>
        <canBeRenamed>false</canBeRenamed>
    </base>

    <placement useRandomYRotation="false" useManualYRotation="true">
        <!-- The arena is {arena["width"]} x {arena["length"]} m inside the rail; letters stand outside it. -->
    </placement>
</placeable>
"""
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)


def store_image(arena, path):
    """A top-down plan of the arena for the shop."""
    size = 512
    img = Image.new("RGB", (size, size), (52, 60, 44))
    draw = ImageDraw.Draw(img)
    w, l = arena["width"], arena["length"]
    scale = (size - 90) / (l + 2 * MARKER_GAP + 2)
    cx, cy = size / 2, size / 2

    def at(x, z):
        return cx + x * scale, cy - z * scale * -1

    x0, y0 = at(-w / 2, -l / 2)
    x1, y1 = at(w / 2, l / 2)
    draw.rectangle([x0, y0, x1, y1], fill=(176, 150, 112))
    rail = max(2, int(scale * 0.25))
    gate = GATE / 2 * scale
    draw.line([x0, y0, x0, y1], fill=(250, 250, 250), width=rail)
    draw.line([x1, y0, x1, y1], fill=(250, 250, 250), width=rail)
    draw.line([x0, y0, x1, y0], fill=(250, 250, 250), width=rail)
    draw.line([x0, y1, cx - gate, y1], fill=(250, 250, 250), width=rail)
    draw.line([cx + gate, y1, x1, y1], fill=(250, 250, 250), width=rail)
    font = ImageFont.truetype(FONT, 22)
    small = ImageFont.truetype(FONT, 17)
    for letter, x, z, kind in layout(arena):
        px, py = at(x * 1.25 if kind == "box" and x != 0 else x, z + (1 if z > l / 2 else -1 if z < -l / 2 else 0) * 1.2)
        if kind == "box":
            r = 13
            draw.rectangle([px - r, py - r, px + r, py + r], fill=(250, 250, 250), outline=(30, 30, 30))
            draw.text((px, py), letter, font=font, fill=(20, 20, 20), anchor="mm")
        else:
            draw.text((px, py), letter, font=small, fill=(60, 45, 30), anchor="mm")
    label = ImageFont.truetype(FONT, 30)
    draw.text((size - 16, size - 14), f"{w} x {l} m", font=label, fill=(250, 250, 250), anchor="rd")
    img.save(path, pixel_format="DXT1")
    mark_dds(path)


def main():
    os.makedirs(OUT, exist_ok=True)
    letter_texture(os.path.join(OUT, "dressageLetters_diffuse.dds"))
    for arena in ARENAS:
        write_i3d(arena, os.path.join(OUT, arena["name"] + ".i3d"))
        write_xml(arena, os.path.join(OUT, arena["name"] + ".xml"))
        store_image(arena, os.path.join(OUT, "store_" + arena["name"] + ".dds"))
        print(arena["name"], "markers:", " ".join(m[0] for m in layout(arena)))


if __name__ == "__main__":
    main()
