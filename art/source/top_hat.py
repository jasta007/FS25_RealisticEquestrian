"""The dressage top hat (data/attire/topHat.i3d), from the low poly model James bought.

The model's licence allows using and modifying it in the mod but not re-uploading the file, so
the source OBJ stays out of the repository: put LP_TopHat.obj in art/source/private/ (ignored by
git) and run from the repository root:

    python3 art/source/top_hat.py [path to LP_TopHat.obj]

The OBJ is in centimetres, Y up, about twice real size, with the long axis of its oval brim
along Z and no UVs. It is scaled to a real hat (a crown about 19 x 20 cm, 19 cm tall), keeps its
origin at the middle of the brim's underside, and gets one UV (it wears a flat colour).

In game the hat hangs off the head's attach point. EqAttire turns its "eqHatFit" group upright
and in front once the player is dressed (the head joint's own axes are the rig's), so this file
only has to get its size right.

Part of Realistic Equestrian by Jasta007.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import xc_jumps as xc  # noqa: E402

SOURCE = "art/source/private/LP_TopHat.obj"
OUT = "data/attire/topHat.i3d"
# cm -> m and down to real size: crown 39 x 42.6 cm -> about 17.5 x 20.5 cm, 39 cm tall -> 18.7 cm.
SCALE = (0.0045, 0.0048, 0.0048)
TEXTURE = "blackSilk_diffuse.dds"


def read(path):
    """One Mesh, scaled, with per corner normals as the OBJ has them."""
    positions, normals = [], []
    mesh, seen = xc.Mesh(), {}
    with open(path) as f:
        for line in f:
            parts = line.split()
            if not parts:
                continue
            if parts[0] == "v":
                x, y, z = (float(v) for v in parts[1:4])
                positions.append((x * SCALE[0], y * SCALE[1], z * SCALE[2]))
            elif parts[0] == "vn":
                normals.append(tuple(float(v) for v in parts[1:4]))
            elif parts[0] == "f":
                ids = []
                for corner in parts[1:]:
                    v, _, n = (corner.split("/") + ["", ""])[:3]
                    key = (int(v), int(n) if n else 0)
                    if key not in seen:
                        normal = normals[key[1] - 1] if key[1] else (0.0, 1.0, 0.0)
                        # Scaling squashes the normals the other way.
                        nx, ny, nz = (normal[i] / SCALE[i] for i in range(3))
                        length = (nx * nx + ny * ny + nz * nz) ** 0.5 or 1.0
                        seen[key] = len(mesh.verts)
                        mesh.verts.append((positions[key[0] - 1], (nx / length, ny / length, nz / length), (0.5, 0.5)))
                    ids.append(seen[key])
                for k in range(1, len(ids) - 1):
                    mesh.tris.append((ids[0], ids[k], ids[k + 1]))
    return mesh


def main():
    source = sys.argv[1] if len(sys.argv) > 1 else SOURCE
    mesh = read(source)
    lines = [
        '<?xml version="1.0" encoding="iso-8859-1"?>',
        "",
        '<i3D name="topHat" version="1.6" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
        'xsi:noNamespaceSchemaLocation="http://i3d.giants.ch/schema/i3d-1.6.xsd">',
        "  <Asset>",
        '    <Export program="Realistic Equestrian top_hat.py" version="1"/>',
        "  </Asset>",
        "  <Files>",
        f'    <File fileId="1" filename="{TEXTURE}"/>',
        "  </Files>",
        "  <Materials>",
        '    <Material name="eqTopHat" materialId="1" specularColor="0.45 1 0">',
        '      <Texture fileId="1"/>',
        "    </Material>",
        "  </Materials>",
        "  <Shapes>",
    ]
    lines += xc.shape_lines(mesh, "topHat", 1)
    lines += [
        "  </Shapes>",
        "  <Scene>",
        '    <TransformGroup name="eqTopHat" nodeId="1">',
        '      <TransformGroup name="eqHatFit" nodeId="2">',
        '        <Shape name="topHat" shapeId="1" clipDistance="150" nodeId="3" materialIds="1" '
        'castsShadows="true" receiveShadows="true"/>',
        "      </TransformGroup>",
        "    </TransformGroup>",
        "  </Scene>",
        "</i3D>",
    ]
    with open(OUT, "w", encoding="iso-8859-1", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
    print(f"wrote {OUT}: {len(mesh.verts)} vertices, {len(mesh.tris)} triangles")


if __name__ == "__main__":
    main()
