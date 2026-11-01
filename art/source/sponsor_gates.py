"""
Builds the two sponsor gates in placeables/xcJumps/ (James, 2026-10-31): not jumps, gates to ride
through, wide and tall enough that getting a horse through is never hard.

- xcGateArch: a showy start/finish arch, banner towers either side of a 6 m opening under a
  banner crossbar 3.6 m up, the sponsor's logo in the middle of the crossbar (both faces) and
  up each tower; weighted white feet.
- xcGateSimple: a "ride through here" gate for finding the way round a course: two peeled timber
  posts 4 m apart, a white board across the top at 3.4 m with the logo on both faces.

Logos are shapes named "eqSponsor_<n>" (and "...b" for a board's back, "...f<k>" for more pieces
of the same board); EqSponsors puts the sponsor's logo on them and counts the boards. The banners
and the board are painted with the game's vehicle shader, shapes named "eqPaint": the Colour
choice in the shop, or the signed sponsor's colour (EqSponsorBoards, EqJumpColours). No flags:
a gate is no fence, so the course recorder never takes it for one. Like the other cross country
pieces they can be placed anywhere and hide outside construction and rounds unless bought with
Disappearing: No.

The geometry is inline: re-save both i3ds in GIANTS Editor (art/source/ge-resave.ps1) so their
collision works in game.

Run from the repository root: python3 art/source/sponsor_gates.py

Part of Realistic Equestrian by Jasta007.
"""

import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(__file__))
import show_jumps as sj  # noqa: E402
import xc_jumps as xc  # noqa: E402
from xc_jumps import COLLISION_GROUP, COLLISION_MASK, Mesh, fmt, shape_lines, store_image, textured_box  # noqa: E402

OUT = "placeables/xcJumps"
ASPECT = sj.LOGO_ASPECT

GATES = [
    {"name": "xcGateArch", "price": 4500, "boards": 3, "colour": "navy"},
    {"name": "xcGateSimple", "price": 1200, "boards": 1, "colour": "white"},
]


def logo_quad(cx, cy, z, facing, width, height, turned=False):
    """A logo on a face at z facing +z (1) or -z (-1), centred at (cx, cy); turned: reading up
    the face (a tower), width then running along y."""
    mesh = Mesh()
    if not turned:
        left, right = cx - facing * width / 2, cx + facing * width / 2
        corners = [(left, cy - height / 2), (right, cy - height / 2), (right, cy + height / 2), (left, cy + height / 2)]
    else:
        # the logo's bottom edge on the face's right, seen from where it faces; it reads upwards
        right, left = cx + facing * height / 2, cx - facing * height / 2
        corners = [(right, cy - width / 2), (right, cy + width / 2), (left, cy + width / 2), (left, cy - width / 2)]
    mesh.quad([(x, y, z) for x, y in corners], (0, 0, facing), [(0, 0), (1, 0), (1, 1), (0, 1)])
    return mesh


def arch():
    white, paint, logos, cols = Mesh(), Mesh(), {}, []
    clear, tw, td, th = 3.0, 0.9, 0.5, 4.4      # half the opening, tower width, depth, height
    bar0, bar1, bd = 3.6, 4.4, 0.4               # crossbar from, to, depth
    for side, number in ((1, 2), (-1, 3)):
        x0, x1 = sorted((side * clear, side * (clear + tw)))
        textured_box(paint, x0, x1, 0.25, th, -td / 2, td / 2)
        # white frame round the banner: corner posts, the weighted foot
        for px in (x0, x1 - 0.06):
            for pz in (-td / 2 - 0.01, td / 2 - 0.05):
                textured_box(white, px, px + 0.06, 0.0, th, pz, pz + 0.06)
        textured_box(white, x0 - 0.15, x1 + 0.15, 0.0, 0.25, -0.6, 0.6)
        cols.append((x0 - 0.15, x1 + 0.15, 0.0, th, -0.6, 0.6))
        lw = 2.6
        for facing, suffix in ((1, ""), (-1, "b")):
            # raised a little (James, 2026-11-01)
            logos[f"eqSponsor_{number}{suffix}"] = logo_quad((x0 + x1) / 2, 1.0 + lw / 2, facing * (td / 2 + 0.002), facing,
                                                            lw, lw / ASPECT, turned=True)
    span = clear + tw
    textured_box(paint, -span, span, bar0, bar1, -bd / 2, bd / 2)
    for y in (bar0 - 0.05, bar1):
        textured_box(white, -span - 0.02, span + 0.02, y, y + 0.05, -bd / 2 - 0.02, bd / 2 + 0.02)
    cols.append((-span, span, bar0, bar1, -bd / 2, bd / 2))
    lh = 0.68
    lw = lh * ASPECT
    # one in the middle of the crossbar (James, 2026-11-01: not three in a row)
    for facing, suffix in ((1, ""), (-1, "b")):
        logos[f"eqSponsor_1{suffix}"] = logo_quad(0.0, (bar0 + bar1) / 2, facing * (bd / 2 + 0.002), facing, lw, lh)
    return {"white": white, "paint": paint}, logos, cols


def simple():
    white, paint, wood, face, logos, cols = Mesh(), Mesh(), Mesh(), Mesh(), {}, []
    half, post, top = 2.08, 0.15, 3.4             # posts' middles, their size, the top board's foot
    for side in (1, -1):
        x = side * half
        textured_box(wood, x - post / 2, x + post / 2, 0.0, top + 0.6, -post / 2, post / 2, 1.0)
        cols.append((x - post / 2, x + post / 2, 0.0, top + 0.6, -post / 2, post / 2))
    # the board across the top, in front of the posts' tops, a painted rim round its white face
    bw, bh, bz = 2 * half + 0.5, 0.55, post / 2
    for facing in (1, -1):
        z0 = facing * bz
        z1 = facing * (bz + 0.04)
        textured_box(paint, -bw / 2, bw / 2, top, top + bh, min(z0, z1), max(z0, z1))
        z2 = facing * (bz + 0.045)
        textured_box(face, -bw / 2 + 0.04, bw / 2 - 0.04, top + 0.04, top + bh - 0.04, min(z1, z2), max(z1, z2))
        lh = bh - 0.12
        logos["eqSponsor_1" + ("" if facing > 0 else "b")] = logo_quad(0.0, top + bh / 2, facing * (bz + 0.047), facing,
                                                                      lh * ASPECT, lh)
    # a little sloping cap on each post
    for side in (1, -1):
        x = side * half
        textured_box(white, x - post / 2 - 0.02, x + post / 2 + 0.02, top + 0.6, top + 0.64, -post / 2 - 0.02, post / 2 + 0.02)
    return {"white": white, "paint": paint, "wood": wood, "face": face}, logos, cols


PEELED = "xcPeeled_diffuse.dds"


def write_i3d(name, colour, path, statics, logos, cols):
    files = [sj.SHADER] + list(sj.PAINT_MAPS.values()) + [PEELED, "../bleachers/bleacherSponsor_diffuse.dds"]
    fid = {f: i + 1 for i, f in enumerate(files)}
    mat = {"white": 1, "paint": 2, "wood": 3, "logo": 4, "face": 1}

    def paint_material(mname, mid, rgb):
        lines = [f'    <Material name="{mname}" materialId="{mid}" customShaderId="{fid[sj.SHADER]}">']
        lines += [f'      <Custommap name="{k}" fileId="{fid[v]}"/>' for k, v in sj.PAINT_MAPS.items()]
        lines += [f'      <CustomParameter name="colorScale" value="{fmt(rgb)}"/>',
                  '      <CustomParameter name="smoothnessScale" value="0.55"/>',
                  '      <CustomParameter name="metalnessScale" value="0"/>', "    </Material>"]
        return lines
    lines = ['<?xml version="1.0" encoding="iso-8859-1"?>', "",
             f'<i3D name="{name}" version="1.6" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
             'xsi:noNamespaceSchemaLocation="http://i3d.giants.ch/schema/i3d-1.6.xsd">',
             "  <Asset>", '    <Export program="Realistic Equestrian sponsor_gates.py" version="1"/>', "  </Asset>", "  <Files>"]
    lines += [f'    <File fileId="{fid[f]}" filename="{f}"/>' for f in files]
    lines += ["  </Files>", "  <Materials>"]
    lines += paint_material("gateWhite", mat["white"], sj.WHITE)
    lines += paint_material("gatePaint", mat["paint"], sj.COLOUR[colour])
    lines += [f'    <Material name="xcPeeled" materialId="{mat["wood"]}" specularColor="0.1 0.7 0">',
              f'      <Texture fileId="{fid[PEELED]}"/>', "    </Material>",
              f'    <Material name="eqSponsor" materialId="{mat["logo"]}" specularColor="0.2 0.5 0" alphaBlending="true">',
              f'      <Texture fileId="{fid["../bleachers/bleacherSponsor_diffuse.dds"]}"/>', "    </Material>", "  </Materials>"]
    shapes = [(f"s_{k}", m) for k, m in statics.items() if m.tris] + [(f"l_{k}", m) for k, m in logos.items()]
    shapes += [(f"col{i + 1}", sj.collision_box(*box)) for i, box in enumerate(cols)]
    ids = {key: i + 1 for i, (key, _) in enumerate(shapes)}
    lines.append("  <Shapes>")
    for key, mesh in shapes:
        lines += shape_lines(mesh, f"{name}_{key}", ids[key])
    lines += ["  </Shapes>", "  <Scene>"]
    node = [1]

    def nid():
        node[0] += 1
        return node[0]
    names = {"white": "frame", "paint": "eqPaint", "wood": "posts", "face": "eqBoardFace"}
    lines.append(f'    <TransformGroup name="{name}" nodeId="1">')
    for key, mesh in statics.items():
        if mesh.tris:
            lines.append(f'      <Shape name="{names[key]}" shapeId="{ids["s_" + key]}" clipDistance="{xc.CLIP * 2}" nodeId="{nid()}" '
                         f'materialIds="{mat[key]}" castsShadows="true" receiveShadows="true"/>')
    for key in logos:
        lines.append(f'      <Shape name="{key}" shapeId="{ids["l_" + key]}" clipDistance="{xc.CLIP * 2}" nodeId="{nid()}" '
                     f'materialIds="{mat["logo"]}" castsShadows="false" receiveShadows="true"/>')
    lines.append(f'      <TransformGroup name="collision" nodeId="{nid()}">')
    for i in range(len(cols)):
        lines.append(f'        <Shape name="col" shapeId="{ids[f"col{i + 1}"]}" static="true" collisionFilterGroup="{COLLISION_GROUP}" '
                     f'collisionFilterMask="{COLLISION_MASK}" density="0.01" nodeId="{nid()}" nonRenderable="true" materialIds="1"/>')
    lines += ["      </TransformGroup>", "    </TransformGroup>", "  </Scene>", "</i3D>"]
    with open(path, "w", encoding="iso-8859-1", newline="\n") as f:
        f.write("\n".join(lines) + "\n")


def main():
    preview_dir = os.environ.get("XC_PREVIEW_DIR", "art/previews")
    sponsor = xc.logo_preview()
    planks = np.asarray(Image.open(os.path.join(OUT, PEELED)).convert("RGB"), dtype=float)
    for gate, builder in zip(GATES, (arch, simple)):
        name = gate["name"]
        statics, logos, cols = builder()
        write_i3d(name, gate["colour"], os.path.join(OUT, name + ".i3d"), statics, logos, cols)
        extra = "\n" + sj.colour_configurations("eqPoleColour", gate["colour"]) + "\n"
        xc.write_xml(name, gate["price"], "A gate to ride through, not a jump: ridden along z.", os.path.join(OUT, name + ".xml"),
                     extra=extra, made_by="art/source/sponsor_gates.py", functions=["eq_shop_signboard_function"])
        # the xml's first line says what it is: a gate, not a cross country jump
        with open(os.path.join(OUT, name + ".xml"), encoding="utf-8") as f:
            text = f.read()
        text = text.replace("$l10n_eq_shop_xcJump_function", "$l10n_eq_shop_xcGate_function")
        with open(os.path.join(OUT, name + ".xml"), "w", encoding="utf-8", newline="\n") as f:
            f.write(text)

        def flip(mesh):
            out = Mesh()
            out.verts = [(p, n, (uv[0], 1 - uv[1])) for p, n, uv in mesh.verts]
            out.tris = list(mesh.tris)
            return out
        meshes = [(statics["white"], sj.flat(sj.WHITE)), (statics["paint"], sj.flat(sj.COLOUR[gate["colour"]]))]
        if "wood" in statics:
            meshes.append((statics["wood"], planks))
        if "face" in statics:
            meshes.append((statics["face"], sj.flat(sj.WHITE)))
        meshes += [(flip(m), sponsor) for m in logos.values()]
        store_image([m for m in meshes if m[0].tris], os.path.join(OUT, "store_" + name + ".dds"), preview_dir)
        print(name, len(logos), "logo faces,", len(cols), "collision boxes")


if __name__ == "__main__":
    main()
