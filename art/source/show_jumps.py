"""
Builds the show jumps in placeables/showJumps/: an upright and an oxer whose poles fall when the
horse hits them and go back up afterwards (EqPoles).

Each jump is jumped along z, with its stands at either end along x. The stands, their wings and
the cups stay put: one static collision box each. Every pole is its own transform group named
"eqPole<n>" holding the visible pole and a static collision box of its own, so the horse's leg
rays (EqTrainingHooks.legClearance) say which pole it clipped. EqPoles moves that group: it takes
the box's collision off, drops the pole off its cups with a scripted fall (no physics, so no
spinning beam of death), and later puts it back where the i3d has it and the collision back on.

Like the cross country fences, the geometry is inline (<IndexedTriangleSet>) and the textures are
painted here. The flags come from the cross country fences' texture (../xcJumps/xcFlags_diffuse.dds)
and stand just outside the stands: "eqFlagsRed" (+x) and "eqFlagsWhite" (-x) at their feet are
what the course recorder reads as the jump's two ends.

Run from the repository root: python3 art/source/show_jumps.py

Part of Realistic Equestrian by Jasta007.
"""

import math
import os

import numpy as np
from PIL import Image, ImageDraw

from eqdds import save_dxt1
from xc_jumps import (COLLISION_GROUP, COLLISION_MASK, FLAG_CELLS, Mesh, flag, fmt, round_rail,
                      shape_lines, store_image)

OUT = "placeables/showJumps"
CLIP = 300

# name, price, pole colour, and each row of poles as (z, top of the pole above the ground)
JUMPS = [
    {"name": "showJumpUpright", "price": 450, "colour": "red",
     "poles": [(0.0, 0.40), (0.0, 0.72), (0.0, 1.00)]},
    {"name": "showJumpOxer", "price": 700, "colour": "blue",
     "poles": [(-0.55, 0.45), (-0.55, 0.95), (0.55, 1.00)]},
]

POLE_LENGTH = 3.5       # metres between the cups' outer edges
POLE_R = 0.05           # a 10 cm pole
BAND = 0.25             # each colour band along a pole (bands repeat every 0.5 m)
STAND_X = POLE_LENGTH / 2 + 0.06   # the stands' middles: just past the pole ends
STAND_W = 0.10          # square stand posts
STAND_H = 1.60
FOOT_L = 0.80           # the crossed feet under each stand
FOOT_W = 0.08
FOOT_H = 0.06
CUP_W = 0.07            # a cup's width along the pole
CUP_H = 0.05            # its height below the pole's underside
CUP_D = 0.12            # how far it sticks out of the stand
WING_OUT = 0.9          # each wing reaches this far past its stand
WING_HIGH = 1.30        # the wing's top at the stand
WING_LOW = 0.70         # and at its outer end
WING_T = 0.04
FLAG_OUT = 0.08         # the flag poles stand this far outside the wing's end

# palette cells: (name, colour)
PALETTE = [("white", (240, 240, 236)), ("red", (196, 30, 36)), ("blue", (28, 70, 160)),
           ("cup", (60, 62, 66)), ("foot", (112, 82, 52))]


# ---------------------------------------------------------------------------------------------
# Textures

def palette_texture(path, cell=16):
    img = Image.new("RGB", (cell * len(PALETTE), cell))
    draw = ImageDraw.Draw(img)
    for i, (_, colour) in enumerate(PALETTE):
        draw.rectangle([i * cell, 0, (i + 1) * cell - 1, cell - 1], fill=colour)
    save_dxt1(img, path)
    return np.asarray(img)


def pal(name):
    """The middle of a palette cell."""
    index = [p[0] for p in PALETTE].index(name)
    return (index + 0.5) / len(PALETTE), 0.5


def pole_texture(colour, path):
    """Bands along v: round_rail runs v once every 1.5 m, so six BAND-long bands fill it."""
    rgb = dict(PALETTE)[colour]
    bands = round(1.5 / BAND)
    img = Image.new("RGB", (8, 16 * bands))
    draw = ImageDraw.Draw(img)
    for i in range(bands):
        draw.rectangle([0, i * 16, 7, i * 16 + 15], fill=rgb if i % 2 == 0 else dict(PALETTE)["white"])
    save_dxt1(img, path)
    return np.asarray(img)


def flags_texture():
    """The cross country flags' texture, as the shop render's copy."""
    cell = 32
    img = Image.new("RGB", (cell * len(FLAG_CELLS), cell))
    draw = ImageDraw.Draw(img)
    for i, colour in enumerate(FLAG_CELLS):
        draw.rectangle([i * cell, 0, (i + 1) * cell - 1, cell - 1], fill=colour)
    return np.asarray(img)


# ---------------------------------------------------------------------------------------------
# Geometry

def pole_mesh():
    """One pole along x round its middle, with white end caps."""
    mesh, ends = Mesh(), Mesh()
    round_rail(mesh, ends, (-POLE_LENGTH / 2, 0.0, 0.0), (POLE_LENGTH / 2, 0.0, 0.0), POLE_R, sides=16)
    # the caps are plain white, from the palette
    ends.verts = [(p, n, pal("white")) for p, n, _ in ends.verts]
    return mesh, ends


def box_mesh(x0, x1, y0, y1, z0, z1, cell):
    mesh = Mesh()
    mesh.box(x0, x1, y0, y1, z0, z1, pal(cell))
    return mesh


def merge(target, mesh):
    base = len(target.verts)
    target.verts += mesh.verts
    target.tris += [(a + base, b + base, c + base) for a, b, c in mesh.tris]


def wing(mesh, x, side, z):
    """A solid wing panel from the stand outwards (side = +1 for +x), sloping down, with a
    coloured top rail."""
    x0, x1 = x + side * STAND_W / 2, x + side * (STAND_W / 2 + WING_OUT)
    for nz, zz in ((1.0, z + WING_T / 2), (-1.0, z - WING_T / 2)):
        corners = [(x0, 0.0, zz), (x1, 0.0, zz), (x1, WING_LOW, zz), (x0, WING_HIGH, zz)]
        ids = [mesh.vertex(p, (0.0, 0.0, nz), pal("white")) for p in corners]
        mesh.tri(ids[0], ids[1], ids[2])
        mesh.tri(ids[0], ids[2], ids[3])
    # the outer end post and the sloping top
    end = Mesh()
    end.box(min(x1, x1 - side * 0.06), max(x1, x1 - side * 0.06), 0.0, WING_LOW + 0.04, z - 0.04, z + 0.04, pal("white"))
    merge(mesh, end)


def stand(mesh, x, z, colour):
    """A stand: a square post with a coloured top, on crossed feet."""
    s = STAND_W / 2
    merge(mesh, box_mesh(x - s, x + s, 0.0, STAND_H - 0.25, z - s, z + s, "white"))
    merge(mesh, box_mesh(x - s, x + s, STAND_H - 0.25, STAND_H, z - s, z + s, colour))
    merge(mesh, box_mesh(x - FOOT_L / 2, x + FOOT_L / 2, 0.0, FOOT_H, z - FOOT_W / 2, z + FOOT_W / 2, "foot"))
    merge(mesh, box_mesh(x - FOOT_W / 2, x + FOOT_W / 2, 0.0, FOOT_H, z - FOOT_L / 2, z + FOOT_L / 2, "foot"))


def frame(jump):
    """The stands, wings, cups and feet of a jump (one mesh in palette colours), its collision
    boxes and the flags' feet."""
    mesh, flags, cols = Mesh(), Mesh(), []
    rows = sorted({z for z, _ in jump["poles"]})
    for z in rows:
        for side in (1, -1):
            x = side * STAND_X
            stand(mesh, x, z, jump["colour"])
            s = STAND_W / 2
            cols.append((x - s, x + s, 0.0, STAND_H, z - s, z + s))
    # one wing each side, on the front row (an oxer's back stands go without)
    z = rows[0] if len(rows) == 1 else (rows[0] + rows[-1]) / 2
    for side in (1, -1):
        x = side * STAND_X
        wing(mesh, x, side, z)
        x0, x1 = sorted((x + side * STAND_W / 2, x + side * (STAND_W / 2 + WING_OUT)))
        cols.append((x0, x1, 0.0, WING_HIGH, z - WING_T, z + WING_T))
    # an oxer's stands are joined at the foot by a ground rail on each side
    if len(rows) > 1:
        for side in (1, -1):
            x = side * STAND_X
            merge(mesh, box_mesh(x - FOOT_W / 2, x + FOOT_W / 2, 0.0, FOOT_H, rows[0], rows[-1], "foot"))
    # the cups: under each pole end, sticking out of the stand's inner face
    for z, top in jump["poles"]:
        under = top - 2 * POLE_R
        for side in (1, -1):
            inner = side * (STAND_X - STAND_W / 2)
            x0, x1 = sorted((inner, inner - side * CUP_D))
            merge(mesh, box_mesh(x0, x1, under - CUP_H, under, z - CUP_W / 2, z + CUP_W / 2, "cup"))
    half = STAND_X + STAND_W / 2 + WING_OUT + FLAG_OUT
    flag(flags, half, 0, 1, STAND_H + 0.1)
    flag(flags, -half, 1, -1, STAND_H + 0.1)
    # flags beside the wing: shift them onto its row
    flags.verts = [((p[0], p[1], p[2] + z), n, uv) for p, n, uv in flags.verts]
    feet = {"eqFlagsRed": (half, 0.0, z), "eqFlagsWhite": (-half, 0.0, z)}
    return mesh, flags, cols, feet


def collision_box(x0, x1, y0, y1, z0, z1):
    mesh = Mesh()
    mesh.box(x0, x1, y0, y1, z0, z1, (0.5, 0.5))
    return mesh


# ---------------------------------------------------------------------------------------------
# Files

def write_i3d(jump, path, frame_mesh, flags, cols, feet, pole, ends):
    name = jump["name"]
    pole_file = f"sjPole_{jump['colour']}_diffuse.dds"
    files = ["sjPalette_diffuse.dds", pole_file, "../xcJumps/xcFlags_diffuse.dds"]
    materials = [("sjPalette", 1), ("sjPole", 2), ("sjFlags", 3)]
    shapes = [("frame", frame_mesh), ("flags", flags), ("pole", pole), ("poleEnds", ends)]
    shapes += [(f"col{i + 1}", collision_box(*box)) for i, box in enumerate(cols)]
    pole_col = collision_box(-POLE_LENGTH / 2, POLE_LENGTH / 2, -POLE_R, POLE_R, -POLE_R, POLE_R)
    shapes.append(("poleCol", pole_col))
    ids = {shape: i + 1 for i, (shape, _) in enumerate(shapes)}
    lines = [
        '<?xml version="1.0" encoding="iso-8859-1"?>',
        "",
        f'<i3D name="{name}" version="1.6" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
        'xsi:noNamespaceSchemaLocation="http://i3d.giants.ch/schema/i3d-1.6.xsd">',
        "  <Asset>",
        '    <Export program="Realistic Equestrian show_jumps.py" version="1"/>',
        "  </Asset>",
        "  <Files>",
    ]
    lines += [f'    <File fileId="{i + 1}" filename="{f}"/>' for i, f in enumerate(files)]
    lines.append("  </Files>")
    lines.append("  <Materials>")
    for material, file_id in materials:
        lines.append(f'    <Material name="{material}" materialId="{file_id}" specularColor="0.1 0.6 0">')
        lines.append(f'      <Texture fileId="{file_id}"/>')
        lines.append("    </Material>")
    lines.append("  </Materials>")
    lines.append("  <Shapes>")
    for shape, mesh in shapes:
        lines += shape_lines(mesh, f"{name}_{shape}", ids[shape])
    lines.append("  </Shapes>")
    lines.append("  <Scene>")
    node = [1]

    def next_id():
        node[0] += 1
        return node[0]

    def col_line(indent, shape_name, shape):
        return (f'{indent}<Shape name="{shape_name}" shapeId="{ids[shape]}" static="true" collisionFilterGroup="{COLLISION_GROUP}" '
                f'collisionFilterMask="{COLLISION_MASK}" density="0.01" nodeId="{next_id()}" nonRenderable="true" materialIds="1"/>')

    lines.append(f'    <TransformGroup name="{name}" nodeId="1">')
    lines.append(f'      <Shape name="frame" shapeId="{ids["frame"]}" clipDistance="{CLIP}" nodeId="{next_id()}" materialIds="1" castsShadows="true" receiveShadows="true"/>')
    lines.append(f'      <Shape name="flags" shapeId="{ids["flags"]}" clipDistance="{CLIP}" nodeId="{next_id()}" materialIds="3" castsShadows="true" receiveShadows="true"/>')
    for flag_name in ("eqFlagsRed", "eqFlagsWhite"):
        lines.append(f'      <TransformGroup name="{flag_name}" translation="{fmt(feet[flag_name])}" nodeId="{next_id()}"/>')
    lines.append(f'      <TransformGroup name="collision" nodeId="{next_id()}">')
    for i in range(len(cols)):
        lines.append(col_line("        ", "col", f"col{i + 1}"))
    lines.append("      </TransformGroup>")
    # Poles from the bottom up, so eqPole1 is the lowest (EqPoles drops the highest it can).
    poles = sorted(jump["poles"], key=lambda p: p[1])
    for i, (z, top) in enumerate(poles):
        lines.append(f'      <TransformGroup name="eqPole{i + 1}" translation="{fmt((0.0, top - POLE_R, z))}" nodeId="{next_id()}">')
        lines.append(f'        <Shape name="pole" shapeId="{ids["pole"]}" clipDistance="{CLIP}" nodeId="{next_id()}" materialIds="2" castsShadows="true" receiveShadows="true"/>')
        lines.append(f'        <Shape name="poleEnds" shapeId="{ids["poleEnds"]}" clipDistance="{CLIP}" nodeId="{next_id()}" materialIds="1" castsShadows="false" receiveShadows="true"/>')
        lines.append(col_line("        ", "poleCol", "poleCol"))
        lines.append("      </TransformGroup>")
    lines += ["    </TransformGroup>", "  </Scene>", "</i3D>"]
    with open(path, "w", encoding="iso-8859-1", newline="\n") as f:
        f.write("\n".join(lines) + "\n")


def write_xml(jump, path):
    name = jump["name"]
    top = max(t for _, t in jump["poles"])
    zs = [z for z, _ in jump["poles"]]
    text = f"""<?xml version="1.0" encoding="utf-8" standalone="no"?>
<!-- Made by art/source/show_jumps.py: change that and run it again rather than editing this. -->
<placeable type="simplePlaceable">
    <storeData>
        <name>$l10n_eq_shop_{name}</name>
        <functions>
            <function>$l10n_eq_shop_showJump_function</function>
            <function>$l10n_eq_shop_showJumpHidden_function</function>
        </functions>
        <image>placeables/showJumps/store_{name}.dds</image>
        <price>{jump["price"]}</price>
        <dailyUpkeep>0</dailyUpkeep>
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
        <filename>placeables/showJumps/{name}.i3d</filename>
        <canBeRenamed>false</canBeRenamed>
    </base>

    <placement useRandomYRotation="false" useManualYRotation="true">
        <!-- {top:.2f} m high, {max(zs) - min(zs):.2f} m spread; jumped along z, red flag at +x. Poles eqPole1.. fall (EqPoles). -->
    </placement>

    <!-- Disappearing: No (the first, default) keeps the jump in the world; Yes hides it outside
         construction, course editing and rounds, like the cross country pieces (EqXcHide). -->
    <eqDisappearing>
        <eqDisappearingConfigurations>
            <eqDisappearingConfiguration name="$l10n_ui_no" price="0"/>
            <eqDisappearingConfiguration name="$l10n_ui_yes" price="0"/>
        </eqDisappearingConfigurations>
    </eqDisappearing>
</placeable>
"""
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)


def main():
    preview_dir = os.environ.get("XC_PREVIEW_DIR", "art/previews")
    os.makedirs(OUT, exist_ok=True)
    palette = palette_texture(os.path.join(OUT, "sjPalette_diffuse.dds"))
    flags_rgb = flags_texture()
    pole, ends = pole_mesh()
    textures = {}
    for jump in JUMPS:
        colour = jump["colour"]
        if colour not in textures:
            textures[colour] = pole_texture(colour, os.path.join(OUT, f"sjPole_{colour}_diffuse.dds"))
        frame_mesh, flags, cols, feet = frame(jump)
        write_i3d(jump, os.path.join(OUT, jump["name"] + ".i3d"), frame_mesh, flags, cols, feet, pole, ends)
        write_xml(jump, os.path.join(OUT, jump["name"] + ".xml"))
        # the shop image: the poles placed where the i3d puts them
        placed, placed_ends = Mesh(), Mesh()
        for z, top in jump["poles"]:
            for source, target in ((pole, placed), (ends, placed_ends)):
                moved = Mesh()
                moved.verts = [((p[0], p[1] + top - POLE_R, p[2] + z), n, uv) for p, n, uv in source.verts]
                moved.tris = list(source.tris)
                merge(target, moved)
        top = max(t for _, t in jump["poles"])
        store_image([(frame_mesh, palette), (placed, textures[colour]), (placed_ends, palette), (flags, flags_rgb)],
                    f"{top:.2f} m", os.path.join(OUT, "store_" + jump["name"] + ".dds"), preview_dir, yaw=-30, pitch=14)
        print(jump["name"], f"{top:.2f} m,", len(jump["poles"]), "poles,",
              len(frame_mesh.tris) + len(flags.tris) + len(jump["poles"]) * (len(pole.tris) + len(ends.tris)), "triangles")


if __name__ == "__main__":
    main()
