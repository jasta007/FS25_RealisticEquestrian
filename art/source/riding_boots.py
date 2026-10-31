"""The tall dressage boots (data/attire/ridingBoots.i3d), from the boot model James bought.

The model's licence allows using and modifying it in the mod but not re-uploading the files, so
the sources stay out of the repository: put ridingBoot.obj (one left boot, converted in Blender:
metres, Y up, toe +Z, sole on y=0, ankle above the origin), ridingBoot_diffuse.png and
ridingBoot_normal.png in art/source/private/ (ignored by git) and run from the repository root:

    python3 art/source/riding_boots.py

Wardrobe clothes bend with the body through skinning, which needs the game's rig. These boots
are solid pieces instead, like the skeleton mod's bones: each boot is cut at the ankle into a
shaft and a foot, and EqAttire links the shaft to the shin bone and the foot to the foot bone
when the character is dressed. The cut overlaps a little so the ankle shows no gap as it bends.
The right boot is the left one mirrored.

Part of Realistic Equestrian by Jasta007.
"""

import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(__file__))
import xc_jumps as xc  # noqa: E402
from eqdds import save_dxt1  # noqa: E402

PRIVATE = "art/source/private"
OUT = "data/attire"
# The ankle's height above the sole: the boot turns about it, and is cut there.
ANKLE = 0.12
# Triangles this far either side of the cut go in both pieces.
OVERLAP = 0.025
# The model's "black" is a very dark brown; take it to black leather, keeping its detail.
DARKEN = 0.45
DESATURATE = 0.8


def read(path):
    """[(position, normal, uv)] and triangles, from a triangulated OBJ."""
    positions, normals, uvs = [], [], []
    verts, seen, tris = [], {}, []
    with open(path) as f:
        for line in f:
            parts = line.split()
            if not parts:
                continue
            if parts[0] == "v":
                positions.append(tuple(float(v) for v in parts[1:4]))
            elif parts[0] == "vn":
                normals.append(tuple(float(v) for v in parts[1:4]))
            elif parts[0] == "vt":
                u, v = (float(x) for x in parts[1:3])
                uvs.append((u, v))
            elif parts[0] == "f":
                ids = []
                for corner in parts[1:]:
                    v, t, n = (corner.split("/") + ["", ""])[:3]
                    key = (int(v), int(t) if t else 0, int(n) if n else 0)
                    if key not in seen:
                        seen[key] = len(verts)
                        verts.append((positions[key[0] - 1],
                                      normals[key[2] - 1] if key[2] else (0.0, 1.0, 0.0),
                                      uvs[key[1] - 1] if key[1] else (0.0, 0.0)))
                    ids.append(seen[key])
                for k in range(1, len(ids) - 1):
                    tris.append((ids[0], ids[k], ids[k + 1]))
    return verts, tris


def piece(verts, tris, keep, origin_y, mirror):
    """A Mesh of the triangles keep() takes, moved so (0, origin_y, 0) is its origin."""
    mesh, remap = xc.Mesh(), {}
    for tri in tris:
        ys = [verts[i][0][1] for i in tri]
        if not keep(min(ys), max(ys)):
            continue
        out = []
        for i in tri:
            if i not in remap:
                (x, y, z), (nx, ny, nz), uv = verts[i]
                if mirror:
                    x, nx = -x, -nx
                remap[i] = mesh.vertex((x, y - origin_y, z), (nx, ny, nz), uv)
            out.append(remap[i])
        mesh.tris.append(tuple(out) if not mirror else (out[0], out[2], out[1]))
    return mesh


def textures():
    diffuse = np.asarray(Image.open(os.path.join(PRIVATE, "ridingBoot_diffuse.png")).convert("RGB")).astype(np.float32)
    grey = diffuse.mean(axis=2, keepdims=True)
    diffuse = (grey + (diffuse - grey) * (1 - DESATURATE)) * DARKEN
    save_dxt1(np.clip(diffuse, 0, 255).astype(np.uint8), os.path.join(OUT, "ridingBoots_diffuse.dds"))
    normal = np.asarray(Image.open(os.path.join(PRIVATE, "ridingBoot_normal.png")).convert("RGB"))
    save_dxt1(normal, os.path.join(OUT, "ridingBoots_normal.dds"))


def main():
    verts, tris = read(os.path.join(PRIVATE, "ridingBoot.obj"))
    # The OBJ's v runs from the bottom like GIANTS'; flip it if the textures come out upside down.
    shapes = []
    for side, mirror in (("L", False), ("R", True)):
        shaft = piece(verts, tris, lambda lo, hi: hi > ANKLE + OVERLAP or lo > ANKLE - OVERLAP, ANKLE, mirror)
        foot = piece(verts, tris, lambda lo, hi: lo < ANKLE + OVERLAP, ANKLE, mirror)
        shapes += [("eqBootShaft" + side, shaft), ("eqBootFoot" + side, foot)]
    textures()

    lines = [
        '<?xml version="1.0" encoding="iso-8859-1"?>',
        "",
        '<i3D name="ridingBoots" version="1.6" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
        'xsi:noNamespaceSchemaLocation="http://i3d.giants.ch/schema/i3d-1.6.xsd">',
        "  <Asset>",
        '    <Export program="Realistic Equestrian riding_boots.py" version="1"/>',
        "  </Asset>",
        "  <Files>",
        '    <File fileId="1" filename="ridingBoots_diffuse.dds"/>',
        '    <File fileId="2" filename="ridingBoots_normal.dds"/>',
        "  </Files>",
        "  <Materials>",
        '    <Material name="eqRidingBoots" materialId="1" specularColor="0.55 1 0">',
        '      <Texture fileId="1"/>',
        '      <Normalmap fileId="2"/>',
        "    </Material>",
        "  </Materials>",
        "  <Shapes>",
    ]
    for i, (name, mesh) in enumerate(shapes):
        lines += xc.shape_lines(mesh, name, i + 1)
    lines += ["  </Shapes>", "  <Scene>", '    <TransformGroup name="eqRidingBoots" nodeId="1">']
    node_id = 2
    # Each piece is a group (moved onto its bone, origin at the ankle) holding its shape.
    for i, (name, _) in enumerate(shapes):
        lines.append(f'      <TransformGroup name="{name}" nodeId="{node_id}">')
        lines.append(f'        <Shape name="{name}Shape" shapeId="{i + 1}" clipDistance="150" nodeId="{node_id + 1}" '
                     'materialIds="1" castsShadows="true" receiveShadows="true"/>')
        lines.append("      </TransformGroup>")
        node_id += 2
    lines += ["    </TransformGroup>", "  </Scene>", "</i3D>"]
    path = os.path.join(OUT, "ridingBoots.i3d")
    with open(path, "w", encoding="iso-8859-1", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
    print(f"wrote {path}: " + ", ".join(f"{n} {len(m.tris)} tris" for n, m in shapes))


if __name__ == "__main__":
    main()
