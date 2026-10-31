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
import attire_render  # noqa: E402
import xc_jumps as xc  # noqa: E402
from eqdds import save_dxt1, save_dxt5  # noqa: E402

PRIVATE = "art/source/private"
OUT = "data/attire"
# The ankle's height above the sole: the boot turns about it, and is cut there.
ANKLE = 0.12
# Triangles this far either side of the cut go in both pieces.
OVERLAP = 0.025
# The model's "black" is a very dark brown; take it to black leather, keeping its detail. Only the
# dark leather: the tan lining inside the top stays as it is.
DARKEN = 0.45
DESATURATE = 0.8
LINING = (90, 130)  # luminance where the leather fades into the lining
# The shaft widens up the calf (James's fit, 2026-10-31): as it is at the bottom of the calf, up to
# 1.4x side to side and 1.2x front to back at the top. Depth grows backwards from the shin.
CALF = (0.18, 0.50)  # heights above the sole where the widening starts and is full
CALF_WIDTH, CALF_DEPTH = 1.4, 1.2
CALF_CENTRE_X, SHIN_FRONT_Z = 0.003, 0.055
# The brown boots: the leather's detail (its brightness against the average) on a brown, sRGB.
LEATHER_GREY = 21
BROWNS = {"darkBrown": (64, 40, 26), "redBrown": (112, 50, 30)}


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


def calf(position, normal):
    """A shaft vertex widened for the calf at its height."""
    (x, y, z), (nx, ny, nz) = position, normal
    t = min(1.0, max(0.0, (y - CALF[0]) / (CALF[1] - CALF[0])))
    sx, sz = 1 + (CALF_WIDTH - 1) * t, 1 + (CALF_DEPTH - 1) * t
    x = CALF_CENTRE_X + (x - CALF_CENTRE_X) * sx
    z = SHIN_FRONT_Z + (z - SHIN_FRONT_Z) * sz
    nx, nz = nx / sx, nz / sz
    length = (nx * nx + ny * ny + nz * nz) ** 0.5 or 1.0
    return (x, y, z), (nx / length, ny / length, nz / length)


def piece(verts, tris, keep, origin_y, mirror, shape=None):
    """A Mesh of the triangles keep() takes, moved so (0, origin_y, 0) is its origin, each vertex
    first through shape() if given."""
    mesh, remap = xc.Mesh(), {}
    for tri in tris:
        ys = [verts[i][0][1] for i in tri]
        if not keep(min(ys), max(ys)):
            continue
        out = []
        for i in tri:
            if i not in remap:
                position, normal, uv = verts[i]
                if shape is not None:
                    position, normal = shape(position, normal)
                (x, y, z), (nx, ny, nz) = position, normal
                if mirror:
                    x, nx = -x, -nx
                remap[i] = mesh.vertex((x, y - origin_y, z), (nx, ny, nz), uv)
            out.append(remap[i])
        mesh.tris.append(tuple(out) if not mirror else (out[0], out[2], out[1]))
    return mesh


def textures():
    """Write the game's textures; returns {colour: diffuse as 0-1 floats} for the icons. The black
    one is the i3d's own, the browns are swapped in by EqAttire (eqDiffuse)."""
    source = np.asarray(Image.open(os.path.join(PRIVATE, "ridingBoot_diffuse.png")).convert("RGB")).astype(np.float32)
    grey = source.mean(axis=2, keepdims=True)
    lining = np.clip((grey - LINING[0]) / (LINING[1] - LINING[0]), 0, 1)
    leathers = {"": (grey + (source - grey) * (1 - DESATURATE)) * DARKEN}
    for name, colour in BROWNS.items():
        leathers[name] = grey / LEATHER_GREY * np.array(colour, dtype=np.float32)
    diffuses = {}
    for name, leather in leathers.items():
        diffuse = np.clip(leather * (1 - lining) + source * lining, 0, 255).astype(np.uint8)
        save_dxt1(diffuse, os.path.join(OUT, f"ridingBoots{'_' + name if name else ''}_diffuse.dds"))
        diffuses[name] = diffuse.astype(np.float32) / 255
    normal = np.asarray(Image.open(os.path.join(PRIVATE, "ridingBoot_normal.png")).convert("RGB"))
    save_dxt1(normal, os.path.join(OUT, "ridingBoots_normal.dds"))
    return diffuses


def icon(verts, tris, diffuse, path):
    """The wardrobe icon: the left boot side on, its texture sampled at each vertex (OBJ v runs
    from the bottom, the image from the top)."""
    mesh = xc.Mesh()
    mesh.verts, mesh.tris = verts, tris
    h, w = diffuse.shape[:2]
    colours = np.array([diffuse[int((1 - uv[1] % 1) * (h - 1)), int(uv[0] % 1 * (w - 1))] for _, _, uv in verts])
    image = attire_render.render([(mesh, colours ** 2.2 * 1.6, 40, 0.18)], yaw=60, pitch=10)
    save_dxt5(image, path)


def main():
    verts, tris = read(os.path.join(PRIVATE, "ridingBoot.obj"))
    # The OBJ's v runs from the bottom like GIANTS'; flip it if the textures come out upside down.
    shapes = []
    for side, mirror in (("L", False), ("R", True)):
        shaft = piece(verts, tris, lambda lo, hi: hi > ANKLE + OVERLAP or lo > ANKLE - OVERLAP, ANKLE, mirror, calf)
        foot = piece(verts, tris, lambda lo, hi: lo < ANKLE + OVERLAP, ANKLE, mirror)
        shapes += [("eqBootShaft" + side, shaft), ("eqBootFoot" + side, foot)]
    for name, diffuse in textures().items():
        icon(verts, tris, diffuse, os.path.join(OUT, f"ridingBoots{'_' + name if name else ''}_icon.dds"))

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
    # The game takes the item (node="1") out of the file and then still expects a first child, as
    # its own clothes have their skeleton there: an empty group keeps that place.
    lines += ["  </Shapes>", "  <Scene>", '    <TransformGroup name="eqBootSkeleton" nodeId="1"/>',
              '    <TransformGroup name="eqRidingBoots" nodeId="2">']
    node_id = 3
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
