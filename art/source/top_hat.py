"""The dressage top hat (data/attire/topHat.i3d) and its short version (shortTopHat.i3d), from the low poly model James bought.

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
import attire_render  # noqa: E402
import xc_jumps as xc  # noqa: E402
from eqdds import save_dxt5  # noqa: E402

SOURCE = "art/source/private/LP_TopHat.obj"
OUT = "data/attire/topHat.i3d"
ICON = "data/attire/topHat_icon.dds"
# cm -> m and down to real size: crown 39 x 42.6 cm -> about 17.5 x 20.5 cm, 39 cm tall -> 16.4 cm
# (James, 2026-10-31: "a little bit shorter" than 18.7 cm, longer front to back looked odd).
SCALE = (0.0045, 0.0042, 0.0048)
# The short hat (a dressage hat that's a safety helmet too, James 2026-10-31): the same hat with the
# crown's straight sides squashed. Brim and band (below SHORT[0] m) and the rounded top (above
# SHORT[1]) keep their shape, the top moves down; SHORT[2] of the sides is kept, 16.4 -> about 12.2 cm, as in his photo.
SHORT = (0.045, 0.138, 0.55)
SHORT_OUT = "data/attire/shortTopHat.i3d"
SHORT_ICON = "data/attire/shortTopHat_icon.dds"
TEXTURE = "blackSilk_diffuse.dds"


def squash(y, short):
    """A height on the short hat: the crown's sides between short[0] and short[1] kept short[2]."""
    low, high, keep = short
    if y <= low:
        return y
    if y <= high:
        return low + (y - low) * keep
    return y - (high - low) * (1 - keep)


def read(path, short=None):
    """One Mesh, scaled (and squashed to the short hat if short is given), with per corner
    normals as the OBJ has them (the squashed sides are upright, so theirs still fit)."""
    positions, normals = [], []
    mesh, seen = xc.Mesh(), {}
    with open(path) as f:
        for line in f:
            parts = line.split()
            if not parts:
                continue
            if parts[0] == "v":
                x, y, z = (float(v) for v in parts[1:4])
                y *= SCALE[1]
                positions.append((x * SCALE[0], squash(y, short) if short else y, z * SCALE[2]))
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


def write(mesh, name, out, icon):
    lines = [
        '<?xml version="1.0" encoding="iso-8859-1"?>',
        "",
        f'<i3D name="{name}" version="1.6" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
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
    lines += xc.shape_lines(mesh, name, 1)
    lines += [
        "  </Shapes>",
        "  <Scene>",
        f'    <TransformGroup name="eq{name[0].upper() + name[1:]}" nodeId="1">',
        '      <TransformGroup name="eqHatFit" nodeId="2">',
        f'        <Shape name="{name}" shapeId="1" clipDistance="150" nodeId="3" materialIds="1" '
        'castsShadows="true" receiveShadows="true"/>',
        "      </TransformGroup>",
        "    </TransformGroup>",
        "  </Scene>",
        "</i3D>",
    ]
    with open(out, "w", encoding="iso-8859-1", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
    print(f"wrote {out}: {len(mesh.verts)} vertices, {len(mesh.tris)} triangles")
    save_dxt5(attire_render.render([(mesh, (0.018, 0.018, 0.02), 40, 0.25)], pitch=15), icon)
    print(f"wrote {icon}")


def main():
    source = sys.argv[1] if len(sys.argv) > 1 else SOURCE
    write(read(source), "topHat", OUT, ICON)
    write(read(source, SHORT), "shortTopHat", SHORT_OUT, SHORT_ICON)


if __name__ == "__main__":
    main()
