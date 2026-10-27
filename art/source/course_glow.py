"""
Builds placeables/courseGlow/courseGlow.i3d: the glowing marks a show jumping or cross country
round draws over the next fence (EqCourseGlow). Not a shop item: the round loads it once and
clones its two shapes, scaled and placed per fence.

- "glowBar": a bar 1 m long along +z from its origin, 1 m across in x and y, centred, for the
  fence line (scaled thin, set along the fence with setDirection).
- "glowPole": a pole 1 m high up +y from its origin, 1 m across, for the flags.

One see-through gold material that glows (alpha blended, emissive), no collision, no shadows
(James, 2026-10-27: poles snapped to the flags and just a glow, the bar thicker but subtle).

Run from the repository root: python3 art/source/course_glow.py

Part of Realistic Equestrian by Jasta007.
"""

import os

OUT = "placeables/courseGlow/courseGlow.i3d"
COLOUR = (1.0, 0.8, 0.25)
ALPHA = 0.35
SIDES = 12


def fmt(values):
    return " ".join(f"{v:.6g}" for v in values)


def bar():
    """A box: x and y from -0.5 to 0.5, z from 0 to 1."""
    verts, tris = [], []
    faces = [
        ((0, 0, 1), [(-.5, -.5, 1), (.5, -.5, 1), (.5, .5, 1), (-.5, .5, 1)]),
        ((0, 0, -1), [(.5, -.5, 0), (-.5, -.5, 0), (-.5, .5, 0), (.5, .5, 0)]),
        ((1, 0, 0), [(.5, -.5, 1), (.5, -.5, 0), (.5, .5, 0), (.5, .5, 1)]),
        ((-1, 0, 0), [(-.5, -.5, 0), (-.5, -.5, 1), (-.5, .5, 1), (-.5, .5, 0)]),
        ((0, 1, 0), [(-.5, .5, 1), (.5, .5, 1), (.5, .5, 0), (-.5, .5, 0)]),
        ((0, -1, 0), [(-.5, -.5, 0), (.5, -.5, 0), (.5, -.5, 1), (-.5, -.5, 1)]),
    ]
    for n, quad in faces:
        base = len(verts)
        for p in quad:
            verts.append((p, n))
        tris += [(base, base + 1, base + 2), (base, base + 2, base + 3)]
    return verts, tris


def pole():
    """A cylinder of SIDES sides, radius 0.5, from y 0 to 1, with a top cap."""
    import math
    verts, tris = [], []
    for i in range(SIDES):
        a0, a1 = 2 * math.pi * i / SIDES, 2 * math.pi * (i + 1) / SIDES
        n = (math.cos((a0 + a1) / 2), 0, math.sin((a0 + a1) / 2))
        p0 = (0.5 * math.cos(a0), 0, 0.5 * math.sin(a0))
        p1 = (0.5 * math.cos(a1), 0, 0.5 * math.sin(a1))
        base = len(verts)
        verts += [(p0, n), (p1, n), ((p1[0], 1, p1[2]), n), ((p0[0], 1, p0[2]), n)]
        tris += [(base, base + 2, base + 1), (base, base + 3, base + 2)]
    centre = len(verts)
    verts.append(((0, 1, 0), (0, 1, 0)))
    for i in range(SIDES):
        a0, a1 = 2 * math.pi * i / SIDES, 2 * math.pi * (i + 1) / SIDES
        base = len(verts)
        verts += [((0.5 * math.cos(a0), 1, 0.5 * math.sin(a0)), (0, 1, 0)), ((0.5 * math.cos(a1), 1, 0.5 * math.sin(a1)), (0, 1, 0))]
        tris.append((centre, base + 1, base))
    return verts, tris


def shape(lines, name, shape_id, mesh, radius):
    verts, tris = mesh
    # Both windings, so the see-through glow shows from inside and out whatever the culling.
    tris = tris + [(t[0], t[2], t[1]) for t in tris]
    lines.append(f'    <IndexedTriangleSet name="{name}" shapeId="{shape_id}" bvCenter="0 0.5 0.5" bvRadius="{radius}">')
    lines.append(f'      <Vertices count="{len(verts)}" normal="true">')
    for p, n in verts:
        lines.append(f'        <v p="{fmt(p)}" n="{fmt(n)}"/>')
    lines.append("      </Vertices>")
    lines.append(f'      <Triangles count="{len(tris)}">')
    for t in tris:
        lines.append(f'        <t vi="{t[0]} {t[1]} {t[2]}"/>')
    lines.append("      </Triangles>")
    lines.append('      <Subsets count="1">')
    lines.append(f'        <Subset firstVertex="0" numVertices="{len(verts)}" firstIndex="0" numIndices="{len(tris) * 3}"/>')
    lines.append("      </Subsets>")
    lines.append("    </IndexedTriangleSet>")


def main():
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    c = COLOUR
    lines = [
        '<?xml version="1.0" encoding="iso-8859-1"?>',
        "",
        '<i3D name="courseGlow" version="1.6" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
        'xsi:noNamespaceSchemaLocation="http://i3d.giants.ch/schema/i3d-1.6.xsd">',
        "  <Asset>",
        '    <Export program="Realistic Equestrian course_glow.py" version="1"/>',
        "  </Asset>",
        "  <Materials>",
        f'    <Material name="courseGlow" materialId="1" diffuseColor="{fmt(c)} {ALPHA}" emissiveColor="{fmt(c)} 1" '
        'specularColor="0 0 0" alphaBlending="true"/>',
        "  </Materials>",
        "  <Shapes>",
    ]
    shape(lines, "glowBar", 1, bar(), 1)
    shape(lines, "glowPole", 2, pole(), 1)
    lines += [
        "  </Shapes>",
        "  <Scene>",
        '    <TransformGroup name="courseGlow" nodeId="1">',
        '      <Shape name="glowBar" shapeId="1" nodeId="2" materialIds="1" castsShadows="false" receiveShadows="false" clipDistance="300"/>',
        '      <Shape name="glowPole" shapeId="2" nodeId="3" materialIds="1" castsShadows="false" receiveShadows="false" clipDistance="300"/>',
        "    </TransformGroup>",
        "  </Scene>",
        "</i3D>",
    ]
    with open(OUT, "w", encoding="iso-8859-1", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
    print(OUT, "built")


if __name__ == "__main__":
    main()
