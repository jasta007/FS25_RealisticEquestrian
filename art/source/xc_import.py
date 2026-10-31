"""
Turns the cross country jumps modelled in Blender (art/source/blender/xc_blender.py, exported to
art/source/models/<name>.obj) into the game's files in placeables/xcJumps/: the .i3d with inline
geometry, the .xml and the shop image. Textures are xc_jumps.py's, plus xcStain, xcDark, xcPeeledB and
xcBigLog. A shape named "eqSponsor_<n>" (the table's board) uses the bleachers' sponsor board
texture and gets a game brand's logo from EqSponsors.

Each OBJ object is one shape, named after the part after the jump's name ("xcCornerPlank_deck" is
"deck"), with its Blender material; "<name>_collision" becomes the static collision. The flags are
made here: a red and a white flag, each a shape under its "eqFlagsRed"/"eqFlagsWhite" transform
group, red at +x. A corner's Corner choice (EqXcCorners) swaps the two groups' places.

Run from the repository root: python3 art/source/xc_import.py

The game builds no collision from inline geometry, so after running this, re-save the six .i3d
files in GIANTS Editor (art/source/ge-resave.ps1, from inside PowerShell: & ge-resave.ps1 -Files a,b,c)
and commit the .i3d with its binary .i3d.shapes.

Part of Realistic Equestrian by Jasta007.
"""

import os
import sys
import tempfile

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
import bleachers  # noqa: E402
import xc_jumps as xc  # noqa: E402

MODELS = "art/source/models"
# A sponsor board's face shows our own board until EqSponsors puts a brand's logo on it (the
# bleachers' board, shared rather than copied).
SPONSOR_TEXTURE = "../bleachers/bleacherSponsor_diffuse.dds"
ME = "art/source/xc_import.py"

# name, price, the flags' distance from the middle (as in xc_blender.py), height, Corner choice
JUMPS = [
    {"name": "xcCornerPlank", "price": 1400, "flag_x": 2.45, "height": 1.10, "corner": True},
    {"name": "xcCornerLog", "price": 1500, "flag_x": 2.45, "height": 1.15, "corner": True},
    {"name": "xcRollTopQuarter", "price": 1100, "flag_x": 2.00, "height": 1.00, "corner": False},
    {"name": "xcRollTopHalf", "price": 1000, "flag_x": 1.90, "height": 0.95, "corner": False},
    {"name": "xcTable", "price": 1600, "flag_x": 2.25, "height": 1.15, "corner": False},
    {"name": "xcBigLog", "price": 900, "flag_x": 3.10, "height": 1.15, "corner": False},
]

CORNER_CONFIG = """
    <!-- Corner: which side the point is on, seen riding at it. Point right (the first) keeps the
         red flag at the point; Point left swaps the flags (EqXcCorners), so the corner is jumped
         the other way round. -->
    <eqCornerSide>
        <eqCornerSideConfigurations>
            <eqCornerSideConfiguration name="$l10n_eq_config_cornerRight" price="0"/>
            <eqCornerSideConfiguration name="$l10n_eq_config_cornerLeft" price="0"/>
        </eqCornerSideConfigurations>
    </eqCornerSide>
"""


def read_obj(path):
    """{object name: (material, Mesh)} with per corner normals and uvs as Blender wrote them."""
    positions, normals, uvs = [], [], []
    objects = {}
    current = None
    with open(path) as f:
        for line in f:
            parts = line.split()
            if not parts:
                continue
            tag = parts[0]
            if tag == "v":
                positions.append(tuple(float(v) for v in parts[1:4]))
            elif tag == "vn":
                normals.append(tuple(float(v) for v in parts[1:4]))
            elif tag == "vt":
                uvs.append(tuple(float(v) for v in parts[1:3]))
            elif tag == "o":
                current = [None, xc.Mesh(), {}]
                objects[parts[1]] = current
            elif tag == "usemtl":
                current[0] = parts[1]
            elif tag == "f":
                mesh, seen = current[1], current[2]
                ids = []
                for corner in parts[1:]:
                    v, t, n = (corner.split("/") + ["", ""])[:3]
                    key = (int(v), int(t) if t else 0, int(n) if n else 0)
                    if key not in seen:
                        p = positions[key[0] - 1]
                        uv = uvs[key[1] - 1] if key[1] else (0.0, 0.0)
                        nn = normals[key[2] - 1] if key[2] else (0.0, 1.0, 0.0)
                        seen[key] = len(mesh.verts)
                        mesh.verts.append((p, nn, uv))
                    ids.append(seen[key])
                for k in range(1, len(ids) - 1):
                    mesh.tris.append((ids[0], ids[k], ids[k + 1]))
    return {name: (material, mesh) for name, (material, mesh, _) in objects.items()}


def flag_mesh(colour, side, pole):
    mesh = xc.Mesh()
    xc.flag(mesh, 0.0, colour, side, pole)
    return mesh


def write_i3d(name, path, shapes, col, flags):
    """shapes: (node name, mesh, material); flags: (group name, x, shape name, mesh)."""
    sponsors = [m for m in sorted({s[2] for s in shapes}) if m.startswith("eqSponsor")]
    used = [m for m in xc.MATERIALS if m[0] in {s[2] for s in shapes} | {"xcFlags"}]
    used += [(m, SPONSOR_TEXTURE, None, False) for m in sponsors]
    files = sorted({t for _, t, _, _ in used} | {n for _, _, n, _ in used if n})
    all_shapes = [(node, mesh) for node, mesh, _ in shapes] + [(shape, mesh) for _, _, shape, mesh in flags] + [("collision", col)]
    lines = [
        '<?xml version="1.0" encoding="iso-8859-1"?>',
        "",
        f'<i3D name="{name}" version="1.6" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
        'xsi:noNamespaceSchemaLocation="http://i3d.giants.ch/schema/i3d-1.6.xsd">',
        "  <Asset>",
        '    <Export program="Realistic Equestrian xc_import.py" version="1"/>',
        "  </Asset>",
        "  <Files>",
    ]
    lines += [f'    <File fileId="{i + 1}" filename="{t}"/>' for i, t in enumerate(files)]
    lines += ["  </Files>", "  <Materials>"]
    ids = {}
    for i, (material, texture, normal, emissive) in enumerate(used):
        ids[material] = i + 1
        blend = ' alphaBlending="true"' if material.startswith("eqSponsor") else ""
        lines.append(f'    <Material name="{material}" materialId="{i + 1}" specularColor="0.1 0.7 0"{blend}>')
        lines.append(f'      <Texture fileId="{files.index(texture) + 1}"/>')
        if normal:
            lines.append(f'      <Normalmap fileId="{files.index(normal) + 1}"/>')
        lines.append("    </Material>")
    lines += ["  </Materials>", "  <Shapes>"]
    for i, (node, mesh) in enumerate(all_shapes):
        lines += xc.shape_lines(mesh, f"{name}_{node}", i + 1)
    lines += ["  </Shapes>", "  <Scene>", f'    <TransformGroup name="{name}" nodeId="1">']
    node_id = 2
    for i, (node, _, material) in enumerate(shapes):
        lines.append(f'      <Shape name="{node}" shapeId="{i + 1}" clipDistance="{xc.CLIP}" nodeId="{node_id}" '
                     f'materialIds="{ids[material]}" castsShadows="true" receiveShadows="true"/>')
        node_id += 1
    for k, (group, x, shape, _) in enumerate(flags):
        lines.append(f'      <TransformGroup name="{group}" translation="{x:.5g} 0 0" nodeId="{node_id}">')
        lines.append(f'        <Shape name="{shape}" shapeId="{len(shapes) + k + 1}" clipDistance="{xc.CLIP}" nodeId="{node_id + 1}" '
                     f'materialIds="{ids["xcFlags"]}" castsShadows="true" receiveShadows="true"/>')
        lines.append("      </TransformGroup>")
        node_id += 2
    lines.append(f'      <TransformGroup name="collision" nodeId="{node_id}">')
    lines.append(f'        <Shape name="col" shapeId="{len(all_shapes)}" static="true" collisionFilterGroup="{xc.COLLISION_GROUP}" '
                 f'collisionFilterMask="{xc.COLLISION_MASK}" density="0.01" nodeId="{node_id + 1}" nonRenderable="true" materialIds="1"/>')
    lines += ["      </TransformGroup>", "    </TransformGroup>", "  </Scene>", "</i3D>"]
    with open(path, "w", encoding="iso-8859-1", newline="\n") as f:
        f.write("\n".join(lines) + "\n")


def moved(mesh, dx):
    out = xc.Mesh()
    out.verts = [((p[0] + dx, p[1], p[2]), n, uv) for p, n, uv in mesh.verts]
    out.tris = list(mesh.tris)
    return out


def flipped_v(mesh):
    """The preview renderer reads v from the top of the image; Blender and GIANTS from the bottom."""
    out = xc.Mesh()
    out.verts = [(p, n, (uv[0], 1 - uv[1])) for p, n, uv in mesh.verts]
    out.tris = list(mesh.tris)
    return out


def textures():
    """The textures' pixels for the shop images (painted into a scratch folder: the game's .dds
    files are already in placeables/xcJumps), and the new ones written for the game."""
    tmp = tempfile.mkdtemp()
    out = xc.OUT
    return {
        "xcPlanks": xc.plank_texture(os.path.join(tmp, "p.dds"), os.path.join(tmp, "pn.dds")),
        "xcPeeled": xc.peeled_texture(os.path.join(tmp, "e.dds")),
        "xcPeeledB": xc.peeled_texture(os.path.join(out, "xcPeeledB_diffuse.dds"), seed=53, colour=(196, 170, 136), contrast=0.12),
        "xcLogEnd": xc.log_end_texture(os.path.join(tmp, "l.dds")),
        "xcFlags": xc.flag_texture(os.path.join(tmp, "f.dds")),
        "xcStain": xc.stain_texture(os.path.join(out, "xcStain_diffuse.dds"), os.path.join(out, "xcStain_normal.dds")),
        "xcDark": xc.dark_wood_texture(os.path.join(out, "xcDark_diffuse.dds")),
        "xcBigLog": xc.big_log_texture(os.path.join(out, "xcBigLog_diffuse.dds")),
        "eqSponsor1": bleachers.sponsor_board(os.path.join(tmp, "s.dds")),
    }


def main():
    preview_dir = os.environ.get("XC_PREVIEW_DIR", "art/previews")
    pixels = textures()
    for jump in JUMPS:
        name = jump["name"]
        objects = read_obj(os.path.join(MODELS, name + ".obj"))
        shapes, col = [], None
        for obj, (material, mesh) in objects.items():
            part = obj[len(name) + 1:] if obj.startswith(name + "_") else obj
            if part == "collision":
                col = mesh
            else:
                shapes.append((part, mesh, material))
        pole = xc.pole_height(jump["height"])
        red, white = flag_mesh(0, 1, pole), flag_mesh(1, -1, pole)
        flags = [("eqFlagsRed", jump["flag_x"], "pennantRed", red), ("eqFlagsWhite", -jump["flag_x"], "pennantWhite", white)]
        write_i3d(name, os.path.join(xc.OUT, name + ".i3d"), shapes, col, flags)
        note = f"{jump['height']:.2f} m high; jumped along z, red flag at +x."
        xc.write_xml(name, jump["price"], note, os.path.join(xc.OUT, name + ".xml"),
                     extra=CORNER_CONFIG if jump["corner"] else "", made_by=f"{ME} from art/source/models/{name}.obj",
                     functions=["eq_shop_signboard_function"] if any(m.startswith("eqSponsor") for _, _, m in shapes) else [])
        meshes = [(flipped_v(mesh), pixels[material]) for _, mesh, material in shapes]
        meshes += [(moved(red, jump["flag_x"]), pixels["xcFlags"]), (moved(white, -jump["flag_x"]), pixels["xcFlags"])]
        xc.store_image(meshes, os.path.join(xc.OUT, "store_" + name + ".dds"), preview_dir)
        print(name, sum(len(m.tris) for _, m, _ in shapes), "triangles,", len(col.tris), "collision")


if __name__ == "__main__":
    main()
