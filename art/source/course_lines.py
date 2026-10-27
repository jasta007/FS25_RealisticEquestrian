"""
Builds the show jumping start and finish line placeables in placeables/courseLines/: one .xml and
.i3d each, a shared texture and a shop image each.

Like the dressage arenas (dressage_arenas.py) the .i3d files keep their geometry inline, so no
GIANTS tools are needed, and have no collision. A line is two posts LINE_WIDTH apart with a flag
board on top, red on the right and white on the left as the horse rides through towards +z, as
on a real course, and a sign reading START or FINISH by the white post. Empty transform groups
named "eqLineRed" and "eqLineWhite" at the posts are what the show jumping round reads
(EqCourseHooks).

Run from the repository root: python3 art/source/course_lines.py

Part of Realistic Equestrian by Jasta007.
"""

import os

from PIL import Image, ImageDraw, ImageFont

from dressage_arenas import FONT, Mesh, fmt, mark_dds

OUT = "placeables/courseLines"
TEXTURE = "courseLines_diffuse.dds"

LINES = [
    {"name": "courseStartLine", "word": "START", "price": 300},
    {"name": "courseFinishLine", "word": "FINISH", "price": 300},
]

LINE_WIDTH = 8.0
POST_SIZE = 0.1
POST_HEIGHT = 1.4
FLAG_WIDTH = 0.45
FLAG_HEIGHT = 0.35
FLAG_THICK = 0.04
SIGN_LETTER = 0.22
SIGN_HEIGHT = 0.9

# The texture is one row of cells: white, red, dark grey, then A to Z. The Mesh class from the
# arena script picks a cell by letter, so these stand-in "letters" name the colour cells.
CELL = 64
CELLS = 32
COLOURS = [(245, 245, 242), (205, 30, 35), (40, 40, 40)]


def texture(path):
    img = Image.new("RGB", (CELL * CELLS, CELL), COLOURS[0])
    draw = ImageDraw.Draw(img)
    for i, colour in enumerate(COLOURS):
        draw.rectangle([i * CELL, 0, (i + 1) * CELL - 1, CELL - 1], fill=colour)
    font = ImageFont.truetype(FONT, int(CELL * 0.72))
    for i in range(26):
        cx = (i + 3) * CELL + CELL / 2
        if i + 3 >= CELLS:
            break
        draw.text((cx, CELL / 2), chr(65 + i), font=font, fill=(18, 18, 18), anchor="mm")
    img.save(path, pixel_format="DXT1")


def cell(index):
    pad = 0.5 / (CELL * CELLS)
    return index / CELLS + pad, (index + 1) / CELLS - pad


class LineMesh(Mesh):
    """Mesh with faces painted from our own cells: 0 white, 1 red, 2 grey, 3.. letters A.."""

    def face(self, a, b, c, d, n, index, letter=False):
        u0, u1 = cell(index)
        base = len(self.verts)
        for p, uv in ((a, (u0, 0.0)), (b, (u1, 0.0)), (c, (u1, 1.0)), (d, (u0, 1.0))):
            self.verts.append((p, n, uv if letter else ((u0 + u1) / 2, 0.5)))
        self.tris.append((base, base + 1, base + 2))
        self.tris.append((base, base + 2, base + 3))

    def block(self, x0, x1, y0, y1, z0, z1, index, front=None, back=None):
        """A box in one colour; front (+z) and back (-z) faces may carry a letter cell."""
        self.face((x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1), (0, 0, 1),
                  front if front is not None else index, front is not None)
        self.face((x1, y0, z0), (x0, y0, z0), (x0, y1, z0), (x1, y1, z0), (0, 0, -1),
                  back if back is not None else index, back is not None)
        self.face((x1, y0, z1), (x1, y0, z0), (x1, y1, z0), (x1, y1, z1), (1, 0, 0), index)
        self.face((x0, y0, z0), (x0, y0, z1), (x0, y1, z1), (x0, y1, z0), (-1, 0, 0), index)
        self.face((x0, y1, z1), (x1, y1, z1), (x1, y1, z0), (x0, y1, z0), (0, 1, 0), index)


def build_mesh(line):
    mesh = LineMesh()
    half = LINE_WIDTH / 2
    p = POST_SIZE / 2
    # Riding towards +z, the right hand is -x: the red post.
    for x, colour in ((-half, 1), (half, 0)):
        mesh.block(x - p, x + p, 0, POST_HEIGHT, -p, p, 2)
        side = -1 if x < 0 else 1
        fx0, fx1 = sorted((x, x + side * FLAG_WIDTH))
        mesh.block(fx0, fx1, POST_HEIGHT - FLAG_HEIGHT, POST_HEIGHT, -FLAG_THICK / 2, FLAG_THICK / 2, colour)
    # The sign by the white post: letters read from the approach side (-z faces the rider).
    word = line["word"]
    s = SIGN_LETTER
    start = half - 0.4 - s * len(word)
    for i, letter in enumerate(word):
        x0 = start + i * s
        index = ord(letter) - 65 + 3
        # Seen from -z the -z face reads right to left, so the letters go in reverse there.
        back_letter = ord(word[len(word) - 1 - i]) - 65 + 3
        mesh.block(x0, x0 + s, SIGN_HEIGHT - s, SIGN_HEIGHT, -0.02, 0.02, 0, front=index, back=back_letter)
    return mesh


def write_i3d(line, path):
    mesh = build_mesh(line)
    half = LINE_WIDTH / 2
    lines = [
        '<?xml version="1.0" encoding="iso-8859-1"?>',
        "",
        f'<i3D name="{line["name"]}" version="1.6" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
        'xsi:noNamespaceSchemaLocation="http://i3d.giants.ch/schema/i3d-1.6.xsd">',
        "  <Asset>",
        '    <Export program="Realistic Equestrian course_lines.py" version="1"/>',
        "  </Asset>",
        "  <Files>",
        f'    <File fileId="1" filename="{TEXTURE}"/>',
        "  </Files>",
        "  <Materials>",
        '    <Material name="courseLines" materialId="1" specularColor="0.25 0.5 0">',
        '      <Texture fileId="1"/>',
        "    </Material>",
        "  </Materials>",
        "  <Shapes>",
        f'    <IndexedTriangleSet name="{line["name"]}" shapeId="1" bvCenter="0 0.7 0" bvRadius="{half + 1:.6g}">',
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
    lines.append(f'    <TransformGroup name="{line["name"]}" nodeId="1">')
    lines.append('      <Shape name="line" shapeId="1" clipDistance="250" nodeId="2" materialIds="1" castsShadows="true" receiveShadows="true"/>')
    lines.append(f'      <TransformGroup name="eqLineRed" translation="{fmt((-half, 0, 0))}" nodeId="3"/>')
    lines.append(f'      <TransformGroup name="eqLineWhite" translation="{fmt((half, 0, 0))}" nodeId="4"/>')
    lines.append("    </TransformGroup>")
    lines.append("  </Scene>")
    lines.append("</i3D>")
    with open(path, "w", encoding="iso-8859-1", newline="\n") as f:
        f.write("\n".join(lines) + "\n")


def write_xml(line, path):
    name = line["name"]
    text = f"""<?xml version="1.0" encoding="utf-8" standalone="no"?>
<!-- Made by art/source/course_lines.py: change that and run it again rather than editing this. -->
<placeable type="simplePlaceable">
    <storeData>
        <name>$l10n_eq_shop_{name}</name>
        <functions>
            <function>$l10n_eq_shop_courseLine_function</function>
        </functions>
        <image>placeables/courseLines/store_{name}.dds</image>
        <price>{line["price"]}</price>
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
        <filename>placeables/courseLines/{name}.i3d</filename>
        <canBeRenamed>false</canBeRenamed>
    </base>

    <placement useRandomYRotation="false" useManualYRotation="true">
        <!-- Two posts {LINE_WIDTH:g} m apart: ride through with the red flag on your right. -->
    </placement>
</placeable>
"""
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)


def store_image(line, path):
    size = 512
    img = Image.new("RGB", (size, size), (52, 60, 44))
    draw = ImageDraw.Draw(img)
    draw.rectangle([0, 300, size, size], fill=(176, 150, 112))
    # Seen from the approach, as the rider sees it: red on the right.
    for x, colour in ((130, COLOURS[0]), (382, COLOURS[1])):
        draw.rectangle([x - 6, 120, x + 6, 340], fill=COLOURS[2])
        fx = x - 70 if x < 256 else x
        draw.rectangle([fx, 120, fx + 70, 170], fill=colour, outline=(30, 30, 30))
    draw.line([136, 330, 376, 330], fill=(250, 250, 250), width=3)
    font = ImageFont.truetype(FONT, 56)
    draw.text((size / 2, 420), line["word"], font=font, fill=(250, 250, 250), anchor="mm")
    img.save(path, pixel_format="DXT1")
    mark_dds(path)


def main():
    os.makedirs(OUT, exist_ok=True)
    texture(os.path.join(OUT, TEXTURE))
    mark_dds(os.path.join(OUT, TEXTURE))
    for line in LINES:
        write_i3d(line, os.path.join(OUT, line["name"] + ".i3d"))
        write_xml(line, os.path.join(OUT, line["name"] + ".xml"))
        store_image(line, os.path.join(OUT, "store_" + line["name"] + ".dds"))
        print(line["name"], "built")


if __name__ == "__main__":
    main()
