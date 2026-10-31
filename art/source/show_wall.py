"""
Builds the sponsor wall in placeables/showJumps/ (James, 2026-10-31): the first showpiece jump, a
painted wooden "brick" wall between two brick pillars with white copings and balls. The bottom is
one solid block; the top row is five blocks that fall when the horse hits them and go back up
afterwards, like the show jumps' poles (EqPoles: each block is an "eqPole<n>" group with an
"eqBlock" marker saying its size, so it tips off the wall and tumbles down rather than rolling).

The sponsor's logo spans the whole face, front and back, cut along the blocks: each piece is its
own shape, "eqSponsor_1" (the base's front) and "eqSponsor_1f<n>" (block n's front), "eqSponsor_2"
and "eqSponsor_2f<n>" for the back. EqSponsors puts the same logo texture on every piece of a
board, and the UVs split it, so knocking a block carries its piece of the logo away. The wall
counts as two sponsor boards. The pillars' balls take the pole colour (the sponsor's, with one).

Like the other show jumps the geometry is inline and needs a GIANTS Editor re-save
(art/source/ge-resave.ps1) before its collision works in game.

Run from the repository root: python3 art/source/show_wall.py

Part of Realistic Equestrian by Jasta007.
"""

import math
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(__file__))
import show_jumps as sj  # noqa: E402
from eqdds import save_dxt1  # noqa: E402
from xc_jumps import COLLISION_GROUP, COLLISION_MASK, Mesh, flag, fmt, shape_lines, store_image, textured_box  # noqa: E402

OUT = sj.OUT
NAME = "showJumpWall"
PRICE = 2500
HALF = 1.75             # the wall runs x -HALF..HALF between the pillars
DEPTH = 0.40            # front to back (square blocks: they lie the same height on any side)
HEIGHT = 1.20           # James: a bit taller than the upright (1.00 m)
BLOCKS = 5              # the knockable top row
BLOCK_GAP = 0.006
CAP = 0.06              # each block's white top
PLINTH = 0.08           # a strip along the foot in the wing colour
PILLAR = (0.62, 0.60, 1.62)   # width, depth, height of the brick pillars
BALL_R = 0.16
LOGO = (2.70, 1.00)     # the logo over the face (LOGO_ASPECT 2.7)
LOGO_Y = 0.11           # its foot
BRICK_TILE = 1.0        # metres the brick texture covers each way
BLOCK_BOTTOM = HEIGHT - DEPTH


def brick_texture(path, size=512):
    """Painted wooden bricks: 4 across and 12 up each metre, staggered, white mortar, reds with
    the odd darker or pinker brick (James's photos)."""
    rng = np.random.default_rng(7)
    img = np.zeros((size, size, 3))
    img[:] = (226, 222, 214)
    rows, across = 12, 4
    bh, bw = size / rows, size / across
    mortar = 5
    palette = [(178, 30, 32)] * 6 + [(150, 22, 30)] * 3 + [(196, 52, 52)] * 2 + [(206, 92, 120), (40, 34, 38), (110, 60, 130)]
    for r in range(rows):
        shift = bw / 2 if r % 2 else 0
        for c in range(-1, across + 1):
            x0, y0 = int(c * bw + shift + mortar / 2), int(r * bh + mortar / 2)
            x1, y1 = int((c + 1) * bw + shift - mortar / 2), int((r + 1) * bh - mortar / 2)
            colour = np.array(palette[rng.integers(len(palette))], dtype=float) + rng.normal(0, 6, 3)
            xs = [x % size for x in range(x0, x1)]
            block = colour + rng.normal(0, 3, (y1 - y0, len(xs), 1))
            img[y0:y1, xs] = block
    rgb = np.clip(img, 0, 255).astype(np.uint8)
    save_dxt1(Image.fromarray(rgb), path)
    return rgb


def moved(mesh, dx, dy, dz):
    out = Mesh()
    out.verts = [((p[0] + dx, p[1] + dy, p[2] + dz), n, uv) for p, n, uv in mesh.verts]
    out.tris = list(mesh.tris)
    return out


def logo_piece(x0, x1, y0, y1, z, facing):
    """The part of the logo over x0..x1, y0..y1 of a face at z facing +z (1) or -z (-1), its UVs
    cut from the whole logo; None where the logo isn't."""
    lw, lh = LOGO
    lx0, lx1, ly0, ly1 = -lw / 2, lw / 2, LOGO_Y, LOGO_Y + lh
    a, b, c, d = max(x0, lx0), min(x1, lx1), max(y0, ly0), min(y1, ly1)
    if a >= b or c >= d:
        return None
    mesh = Mesh()

    def uv(x, y):
        u = (x - lx0) / lw if facing > 0 else (lx1 - x) / lw
        return (u, (y - ly0) / lh)
    corners = [(a, c), (b, c), (b, d), (a, d)]
    mesh.quad([(x, y, z) for x, y in corners], (0, 0, facing), [uv(x, y) for x, y in corners])
    return mesh


def ball(mesh, x, y, z, r, rings=8, sides=16):
    for i in range(rings):
        t0, t1 = math.pi * i / rings - math.pi / 2, math.pi * (i + 1) / rings - math.pi / 2
        for k in range(sides):
            a0, a1 = 2 * math.pi * k / sides, 2 * math.pi * (k + 1) / sides
            pts = [(t0, a0), (t0, a1), (t1, a1), (t1, a0)]
            ns = [(math.cos(t) * math.cos(a), math.sin(t), math.cos(t) * math.sin(a)) for t, a in pts]
            ids = [mesh.vertex((x + n[0] * r, y + n[1] * r, z + n[2] * r), n, (0.5, 0.5)) for n in ns]
            mesh.tri(ids[0], ids[1], ids[2])
            mesh.tri(ids[0], ids[2], ids[3])


def build():
    """Static parts by material, the blocks, the collision boxes, the flags' feet."""
    bricks, white, paint, wing = Mesh(), Mesh(), Mesh(), Mesh()
    cols, logos = [], {}
    d = DEPTH / 2
    # the solid base: bricks, a plinth in the wing colour along the foot
    textured_box(bricks, -HALF, HALF, 0.0, BLOCK_BOTTOM, -d, d, BRICK_TILE)
    textured_box(wing, -HALF - 0.005, HALF + 0.005, 0.0, PLINTH, -d - 0.02, d + 0.02)
    cols.append((-HALF, HALF, 0.0, BLOCK_BOTTOM, -d, d))
    for facing, number in ((1, 1), (-1, 2)):
        piece = logo_piece(-HALF, HALF, PLINTH, BLOCK_BOTTOM, facing * (d + 0.0015), facing)
        if piece is not None:
            logos[f"eqSponsor_{number}"] = piece
    # the pillars
    pw, pd, ph = PILLAR
    for side in (1, -1):
        x0, x1 = sorted((side * (HALF + 0.03), side * (HALF + 0.03 + pw)))
        textured_box(bricks, x0, x1, 0.0, ph, -pd / 2, pd / 2, BRICK_TILE)
        textured_box(white, x0 - 0.03, x1 + 0.03, ph, ph + 0.07, -pd / 2 - 0.03, pd / 2 + 0.03)
        textured_box(white, x0 + 0.12, x1 - 0.12, ph + 0.07, ph + 0.11, -pd / 2 + 0.12, pd / 2 - 0.12)
        ball(paint, (x0 + x1) / 2, ph + 0.11 + BALL_R * 0.95, 0.0, BALL_R)
        textured_box(wing, x0 - 0.005, x1 + 0.005, 0.0, PLINTH, -pd / 2 - 0.02, pd / 2 + 0.02)
        cols.append((x0, x1, 0.0, ph + 0.11 + 2 * BALL_R, -pd / 2, pd / 2))
    # the top row of blocks, each built where it stands (so the bricks run on from the base) and
    # then moved round its own middle
    blocks = []
    width = 2 * HALF / BLOCKS
    for i in range(BLOCKS):
        bx0 = -HALF + i * width + BLOCK_GAP / 2
        bx1 = bx0 + width - BLOCK_GAP
        cx, cy = (bx0 + bx1) / 2, BLOCK_BOTTOM + DEPTH / 2
        body, cap = Mesh(), Mesh()
        textured_box(body, bx0, bx1, BLOCK_BOTTOM, HEIGHT - CAP, -d, d, BRICK_TILE)
        textured_box(cap, bx0, bx1, HEIGHT - CAP, HEIGHT, -d - 0.012, d + 0.012)
        # the cap's underside where it overhangs
        for z0, z1, n in ((d, d + 0.012, 1), (-d - 0.012, -d, -1)):
            cap.quad([(bx0, HEIGHT - CAP, z0), (bx1, HEIGHT - CAP, z0), (bx1, HEIGHT - CAP, z1), (bx0, HEIGHT - CAP, z1)],
                     (0, -1, 0), [(0.5, 0.5)] * 4)
        pieces = {}
        for facing, number in ((1, 1), (-1, 2)):
            piece = logo_piece(bx0, bx1, BLOCK_BOTTOM, HEIGHT - CAP, facing * (d + 0.0015), facing)
            if piece is not None:
                pieces[f"eqSponsor_{number}f{i + 1}"] = moved(piece, -cx, -cy, 0.0)
        blocks.append({"centre": (cx, cy, 0.0), "half": (bx1 - bx0) / 2, "body": moved(body, -cx, -cy, 0.0),
                       "cap": moved(cap, -cx, -cy, 0.0), "logos": pieces,
                       "col": (-(bx1 - bx0) / 2, (bx1 - bx0) / 2, -DEPTH / 2, DEPTH / 2, -d, d)})
    half = HALF + 0.03 + pw + sj.FLAG_OUT
    flags = Mesh()
    pole = max(sj.STAND_H + 0.1, HEIGHT + 0.55)
    flag(flags, half, 0, 1, pole)
    flag(flags, -half, 1, -1, pole)
    feet = {"eqFlagsRed": (half, 0.0, 0.0), "eqFlagsWhite": (-half, 0.0, 0.0)}
    return {"bricks": bricks, "white": white, "paint": paint, "wing": wing, "flags": flags}, logos, blocks, cols, feet


SHADER, PAINT_MAPS = sj.SHADER, sj.PAINT_MAPS
FLAGS_TEXTURE = "../xcJumps/xcFlags_diffuse.dds"
BRICKS_TEXTURE = "sjBricks_diffuse.dds"


def write_i3d(path, statics, logos, blocks, cols, feet):
    files = [SHADER] + list(PAINT_MAPS.values()) + [FLAGS_TEXTURE, BRICKS_TEXTURE, sj.SPONSOR_TEXTURE]
    fid = {f: i + 1 for i, f in enumerate(files)}
    mat = {"white": 1, "paint": 2, "wing": 3, "flags": 4, "bricks": 5, "logo": 6}

    def paint_material(name, mid, colour):
        lines = [f'    <Material name="{name}" materialId="{mid}" customShaderId="{fid[SHADER]}">']
        lines += [f'      <Custommap name="{k}" fileId="{fid[v]}"/>' for k, v in PAINT_MAPS.items()]
        lines += [f'      <CustomParameter name="colorScale" value="{fmt(colour)}"/>',
                  '      <CustomParameter name="smoothnessScale" value="0.55"/>',
                  '      <CustomParameter name="metalnessScale" value="0"/>', "    </Material>"]
        return lines
    lines = ['<?xml version="1.0" encoding="iso-8859-1"?>', "",
             f'<i3D name="{NAME}" version="1.6" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
             'xsi:noNamespaceSchemaLocation="http://i3d.giants.ch/schema/i3d-1.6.xsd">',
             "  <Asset>", '    <Export program="Realistic Equestrian show_wall.py" version="1"/>', "  </Asset>", "  <Files>"]
    lines += [f'    <File fileId="{fid[f]}" filename="{f}"/>' for f in files]
    lines += ["  </Files>", "  <Materials>"]
    lines += paint_material("sjWhite", mat["white"], sj.WHITE)
    lines += paint_material("sjPaint", mat["paint"], sj.WHITE)
    lines += paint_material("sjWingPaint", mat["wing"], sj.COLOUR["navy"])
    lines += [f'    <Material name="sjFlags" materialId="{mat["flags"]}" specularColor="0.1 0.6 0">',
              f'      <Texture fileId="{fid[FLAGS_TEXTURE]}"/>', "    </Material>",
              f'    <Material name="sjBricks" materialId="{mat["bricks"]}" specularColor="0.3 0.5 0">',
              f'      <Texture fileId="{fid[BRICKS_TEXTURE]}"/>', "    </Material>",
              f'    <Material name="eqSponsor" materialId="{mat["logo"]}" specularColor="0.2 0.5 0" alphaBlending="true">',
              f'      <Texture fileId="{fid[sj.SPONSOR_TEXTURE]}"/>', "    </Material>", "  </Materials>"]
    shapes = []    # (id key, mesh)
    for key, mesh in statics.items():
        shapes.append((f"s_{key}", mesh))
    for key, mesh in logos.items():
        shapes.append((f"l_{key}", mesh))
    for i, box in enumerate(cols):
        shapes.append((f"col{i + 1}", sj.collision_box(*box)))
    for i, block in enumerate(blocks):
        shapes += [(f"b{i}_body", block["body"]), (f"b{i}_cap", block["cap"]), (f"b{i}_col", sj.collision_box(*block["col"]))]
        shapes += [(f"b{i}_{key}", mesh) for key, mesh in block["logos"].items()]
    ids = {key: i + 1 for i, (key, _) in enumerate(shapes)}
    lines.append("  <Shapes>")
    for key, mesh in shapes:
        lines += shape_lines(mesh, f"{NAME}_{key}", ids[key])
    lines += ["  </Shapes>", "  <Scene>"]
    node = [1]

    def nid():
        node[0] += 1
        return node[0]

    def vis(indent, name, key, material, shadows=True):
        return (f'{indent}<Shape name="{name}" shapeId="{ids[key]}" clipDistance="{sj.CLIP}" nodeId="{nid()}" '
                f'materialIds="{mat[material]}" castsShadows="{str(shadows).lower()}" receiveShadows="true"/>')

    def col(indent, key):
        return (f'{indent}<Shape name="col" shapeId="{ids[key]}" static="true" collisionFilterGroup="{COLLISION_GROUP}" '
                f'collisionFilterMask="{COLLISION_MASK}" density="0.01" nodeId="{nid()}" nonRenderable="true" materialIds="1"/>')
    names = {"bricks": ("bricks", "bricks"), "white": ("frame", "white"), "paint": ("eqPaint", "paint"),
             "wing": ("eqWingPaint", "wing"), "flags": ("flags", "flags")}
    lines.append(f'    <TransformGroup name="{NAME}" nodeId="1">')
    for key in statics:
        name, material = names[key]
        lines.append(vis("      ", name, f"s_{key}", material))
    for key in logos:
        lines.append(vis("      ", key, f"l_{key}", "logo", shadows=False))
    for flag_name in ("eqFlagsRed", "eqFlagsWhite"):
        lines.append(f'      <TransformGroup name="{flag_name}" translation="{fmt(feet[flag_name])}" nodeId="{nid()}"/>')
    lines.append(f'      <TransformGroup name="collision" nodeId="{nid()}">')
    for i in range(len(cols)):
        lines.append(col("        ", f"col{i + 1}"))
    lines.append("      </TransformGroup>")
    for i, block in enumerate(blocks):
        lines.append(f'      <TransformGroup name="eqPole{i + 1}" translation="{fmt(block["centre"])}" nodeId="{nid()}">')
        lines.append(vis("        ", "bricks", f"b{i}_body", "bricks"))
        lines.append(vis("        ", "frame", f"b{i}_cap", "white"))
        for key in block["logos"]:
            lines.append(vis("        ", key, f"b{i}_{key}", "logo", shadows=False))
        lines.append(col("        ", f"b{i}_col"))
        lines.append(f'        <TransformGroup name="eqEnd" translation="{fmt((block["half"], 0.0, 0.0))}" nodeId="{nid()}"/>')
        lines.append(f'        <TransformGroup name="eqBlock" translation="{fmt((0.0, DEPTH / 2, DEPTH / 2))}" nodeId="{nid()}"/>')
        lines.append("      </TransformGroup>")
    lines += ["    </TransformGroup>", "  </Scene>", "</i3D>"]
    with open(path, "w", encoding="iso-8859-1", newline="\n") as f:
        f.write("\n".join(lines) + "\n")


def write_xml(path):
    text = f"""<?xml version="1.0" encoding="utf-8" standalone="no"?>
<!-- Made by art/source/show_wall.py: change that and run it again rather than editing this. -->
<placeable type="simplePlaceable">
    <storeData>
        <name>$l10n_eq_shop_{NAME}</name>
        <functions>
            <function>$l10n_eq_shop_showJumpWall_function</function>
            <function>$l10n_eq_shop_showJumpHidden_function</function>
        </functions>
        <image>placeables/showJumps/store_{NAME}.dds</image>
        <price>{PRICE}</price>
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
        <filename>placeables/showJumps/{NAME}.i3d</filename>
        <canBeRenamed>false</canBeRenamed>
    </base>

    <placement useRandomYRotation="false" useManualYRotation="true">
        <!-- {HEIGHT:.2f} m high, {DEPTH:.2f} m deep; jumped along z, red flag at +x. Top blocks eqPole1.. fall (EqPoles). -->
    </placement>

    <!-- Disappearing: No (the first, default) keeps the jump in the world; Yes hides it outside
         construction, course editing and rounds, like the cross country pieces (EqXcHide). -->
    <eqDisappearing>
        <eqDisappearingConfigurations>
            <eqDisappearingConfiguration name="$l10n_ui_no" price="0"/>
            <eqDisappearingConfiguration name="$l10n_ui_yes" price="0"/>
        </eqDisappearingConfigurations>
    </eqDisappearing>

{sj.colour_configurations("eqPoleColour", "white")}

{sj.colour_configurations("eqWingColour", "navy")}

</placeable>
"""
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)


def main(preview_dir=None, sponsor_preview=False):
    preview_dir = preview_dir or os.environ.get("XC_PREVIEW_DIR", "art/previews")
    bricks_rgb = brick_texture(os.path.join(OUT, BRICKS_TEXTURE))
    statics, logos, blocks, cols, feet = build()
    write_i3d(os.path.join(OUT, NAME + ".i3d"), statics, logos, blocks, cols, feet)
    write_xml(os.path.join(OUT, NAME + ".xml"))
    sponsor = np.asarray(Image.open("placeables/bleachers/bleacherSponsor_diffuse.dds").convert("RGB"), dtype=float)

    def flip(mesh):
        out = Mesh()
        out.verts = [(p, n, (uv[0], 1 - uv[1])) for p, n, uv in mesh.verts]
        out.tris = list(mesh.tris)
        return out
    flat = sj.flat
    meshes = [(statics["bricks"], bricks_rgb), (statics["white"], flat(sj.WHITE)), (statics["paint"], flat(sj.WHITE)),
              (statics["wing"], flat(sj.COLOUR["navy"])), (statics["flags"], sj.flags_texture())]
    meshes += [(flip(m), sponsor) for m in logos.values()]
    for block in blocks:
        cx, cy, cz = block["centre"]
        meshes += [(moved(block["body"], cx, cy, cz), bricks_rgb), (moved(block["cap"], cx, cy, cz), flat(sj.WHITE))]
        meshes += [(flip(moved(m, cx, cy, cz)), sponsor) for m in block["logos"].values()]
    store_image(meshes, os.path.join(OUT, "store_" + NAME + ".dds"), preview_dir)
    print(NAME, f"{HEIGHT:.2f} m,", len(blocks), "blocks,", len(cols), "collision boxes")


if __name__ == "__main__":
    main()
