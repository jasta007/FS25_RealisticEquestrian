"""
Builds the marker rope in placeables/xcJumps/ (James, 2026-10-31): a spline fence like the cross
country flags, a white rope on thin stakes to mark out the way, with nothing a horse can bump
into. Two segment kinds (N/M in the fence brush): plain rope, and rope with a small sign hanging
in the middle of each panel showing the sponsor's logo.

Each sign's faces are shapes "eqSponsor_1" and "eqSponsor_1b", cloned per panel by the game;
EqSponsors puts the logo on all of them but counts them for very little (ROPE_SIGN in
EqSponsors, capped for all ropes together) so lines of rope can't buy a farm its branding.

The only collision is a flat box sunk half into the ground under each stake and panel, as the
flag fence's guide line has, so construction mode can pick the rope to delete. The rope and signs
lean with the slope like the base game's fence panels (placeable shader, vertexOffset).

Run from the repository root: python3 art/source/rope_fence.py

Part of Realistic Equestrian by Jasta007.
"""

import math
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(__file__))
import xc_jumps as xc  # noqa: E402
from xc_jumps import COLLISION_MASK, FENCE_COLLISION_GROUP, Mesh, flag_uv, fmt, shape_lines, store_image  # noqa: E402

OUT = xc.OUT
NAME = "xcRope"
PRICE = 20
PANEL = 2.5             # a panel's length; stretched up to MAX_SCALE
MAX_SCALE = 1.4
ROPE_Y = 0.85           # the rope's height at the stakes
SAG = 0.07
ROPE_R = 0.011
STAKE = (0.035, 1.0)    # width, height
SIGN = (0.50, 0.22)     # the hanging sign's width and height
ASPECT = 2.7
SPONSOR_TEXTURE = "../bleachers/bleacherSponsor_diffuse.dds"


def rope_y(z):
    t = z / PANEL
    return ROPE_Y - SAG * 4 * t * (1 - t)


def rope(mesh, sides=6, steps=12):
    """The rope along z from 0 to PANEL, sagging in the middle."""
    rings = []
    for i in range(steps + 1):
        z = PANEL * i / steps
        y = rope_y(z)
        ring = []
        for k in range(sides + 1):
            a = 2 * math.pi * k / sides
            n = (math.cos(a), math.sin(a), 0.0)
            ring.append(mesh.vertex((n[0] * ROPE_R, y + n[1] * ROPE_R, z), n, flag_uv(1)))
        rings.append(ring)
    for i in range(steps):
        for k in range(sides):
            a, b, c, d = rings[i][k], rings[i][k + 1], rings[i + 1][k + 1], rings[i + 1][k]
            mesh.tri(a, b, c)
            mesh.tri(a, c, d)


def sign():
    """A small board hanging from the rope's middle on two cords, and its two logo faces."""
    board, logos = Mesh(), {}
    w, h = SIGN
    zc = PANEL / 2
    top = rope_y(zc) - 0.05
    xc.textured_box(board, -0.006, 0.006, top - h, top, zc - w / 2, zc + w / 2)
    # the bottom face too: textured_box leaves it out
    board.quad([(-0.006, top - h, zc - w / 2), (0.006, top - h, zc - w / 2), (0.006, top - h, zc + w / 2), (-0.006, top - h, zc + w / 2)],
               (0, -1, 0), [flag_uv(1)] * 4)
    board.verts = [(p, n, flag_uv(1)) for p, n, _ in board.verts]
    for dz in (-w / 2 + 0.05, w / 2 - 0.05):
        z = zc + dz
        xc.textured_box(board, -0.003, 0.003, top, rope_y(z), z - 0.003, z + 0.003)
    board.verts = [(p, n, flag_uv(1)) for p, n, _ in board.verts]
    lw = w - 0.04
    lh = min(h - 0.04, lw / ASPECT)
    yc = top - h / 2
    for facing, name in ((1, "eqSponsor_1"), (-1, "eqSponsor_1b")):
        x = facing * 0.0065
        mesh = Mesh()
        # facing +x, seen from +x the rope runs right towards -z
        left, right = zc + facing * lw / 2, zc - facing * lw / 2
        mesh.quad([(x, yc - lh / 2, left), (x, yc - lh / 2, right), (x, yc + lh / 2, right), (x, yc + lh / 2, left)],
                  (facing, 0, 0), [(0, 0), (1, 0), (1, 1), (0, 1)])
        logos[name] = mesh
    return board, logos


def stake():
    mesh = Mesh()
    s = STAKE[0] / 2
    xc.textured_box(mesh, -s, s, -0.15, STAKE[1], -s, s)
    mesh.verts = [(p, n, flag_uv(1) if p[1] < STAKE[1] - 0.12 else flag_uv(0)) for p, n, _ in mesh.verts]
    return mesh


def ground_box(z0, z1):
    mesh = Mesh()
    mesh.box(-0.03, 0.03, -0.03, 0.03, z0, z1, (0.5, 0.5))
    return mesh


def slope(p):
    return (p[2] / PANEL, 0.0)


def write_i3d(path, stake_mesh, plain, signed, board, logos):
    lines = ['<?xml version="1.0" encoding="iso-8859-1"?>', "",
             f'<i3D name="{NAME}" version="1.6" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
             'xsi:noNamespaceSchemaLocation="http://i3d.giants.ch/schema/i3d-1.6.xsd">',
             "  <Asset>", '    <Export program="Realistic Equestrian rope_fence.py" version="1"/>', "  </Asset>",
             "  <Files>", '    <File fileId="1" filename="xcFlags_diffuse.dds"/>',
             '    <File fileId="2" filename="$data/shaders/placeableShader.xml"/>',
             f'    <File fileId="3" filename="{SPONSOR_TEXTURE}"/>', "  </Files>", "  <Materials>",
             '    <Material name="xcFlags" materialId="1" specularColor="0.1 0.7 0">', '      <Texture fileId="1"/>', "    </Material>",
             # leans with the slope, like the base game's fence panels
             '    <Material name="xcRope" materialId="2" specularColor="0.1 0.7 0" customShaderId="2" customShaderVariation="vertexOffset_Decal">',
             '      <Texture fileId="1"/>', "    </Material>",
             '    <Material name="eqSponsor" materialId="3" specularColor="0.2 0 0" alphaBlending="true" customShaderId="2" '
             'customShaderVariation="vertexOffset_Decal">', '      <Texture fileId="3"/>', "    </Material>",
             "  </Materials>", "  <Shapes>"]
    shapes = [("stake", stake_mesh, None), ("stakeCol", ground_box(-0.03, 0.03), None),
              ("rope", plain, slope), ("ropeCol", ground_box(PANEL / 2 - 0.03, PANEL / 2 + 0.03), None),
              ("ropeSign", signed, slope), ("sign", board, slope)]
    shapes += [(k, m, slope) for k, m in logos.items()]
    shapes += [("signCol", ground_box(PANEL / 2 - 0.03, PANEL / 2 + 0.03), None)]
    ids = {}
    for i, (key, mesh, uv1) in enumerate(shapes):
        ids[key] = i + 1
        lines += shape_lines(mesh, f"{NAME}_{key}", i + 1, uv1=uv1)
    lines += ["  </Shapes>", "  <Scene>"]
    node = [0]

    def nid():
        node[0] += 1
        return node[0]

    def vis(indent, name, key, material, shadows=True):
        return (f'{indent}<Shape name="{name}" shapeId="{ids[key]}" clipDistance="{xc.CLIP}" nodeId="{nid()}" materialIds="{material}" '
                f'castsShadows="{str(shadows).lower()}" receiveShadows="true"/>')

    def col(indent, key):
        return (f'{indent}<Shape name="col" shapeId="{ids[key]}" static="true" collisionFilterGroup="{FENCE_COLLISION_GROUP}" '
                f'collisionFilterMask="{COLLISION_MASK}" density="0.01" nodeId="{nid()}" nonRenderable="true" materialIds="1"/>')
    lines.append(f'    <TransformGroup name="gates" nodeId="{nid()}"/>')
    lines.append(f'    <TransformGroup name="poles" nodeId="{nid()}">')
    lines.append(f'      <TransformGroup name="eqRopeStake" nodeId="{nid()}">')
    lines.append(vis("        ", "stake", "stake", 1))
    lines.append(col("        ", "stakeCol"))
    lines.append("      </TransformGroup>")
    lines.append("    </TransformGroup>")
    lines.append(f'    <TransformGroup name="panels" nodeId="{nid()}">')
    lines.append(f'      <TransformGroup name="eqRope" nodeId="{nid()}">')
    lines.append(vis("        ", "rope", "rope", 2, shadows=False))
    lines.append(col("        ", "ropeCol"))
    lines.append("      </TransformGroup>")
    lines.append(f'      <TransformGroup name="eqRopeSign" nodeId="{nid()}">')
    lines.append(vis("        ", "rope", "ropeSign", 2, shadows=False))
    lines.append(vis("        ", "sign", "sign", 2))
    for key in logos:
        lines.append(vis("        ", key, key, 3, shadows=False))
    lines.append(col("        ", "signCol"))
    lines.append("      </TransformGroup>")
    lines.append("    </TransformGroup>")
    lines += ["  </Scene>", "</i3D>"]
    with open(path, "w", encoding="iso-8859-1", newline="\n") as f:
        f.write("\n".join(lines) + "\n")


def write_xml(path):
    segment = lambda sid, panel: f"""        <segment id="{sid}" class="FenceSegment" maxVerticalAngle="45">
            <poles>
                <pole node="1>0" radius="{STAKE[0] / 2:g}"/>
            </poles>
            <panels maxScale="{MAX_SCALE:g}">
                <panel node="2>{panel}" length="{PANEL:g}"/>
            </panels>
        </segment>"""
    text = f"""<?xml version="1.0" encoding="utf-8" standalone="no"?>
<!-- Made by art/source/rope_fence.py: change that and run it again rather than editing this. -->
<!-- Segments (N/M): plain rope, rope with a sponsor sign. -->
<placeable type="newFence">
    <storeData>
        <name>$l10n_eq_shop_{NAME}</name>
        <functions>
            <function>$l10n_eq_shop_{NAME}_function</function>
            <function>$l10n_eq_shop_xcFlagsHidden_function</function>
        </functions>
        <image>placeables/xcJumps/store_{NAME}.dds</image>
        <price>{PRICE}</price>
        <dailyUpkeep>0</dailyUpkeep>
        <lifetime>1000</lifetime>
        <rotation>0</rotation>
        <brand>NONE</brand>
        <species>placeable</species>
        <category>fences</category>
        <canBeSold>true</canBeSold>
        <showInStore>true</showInStore>
        <brush>
            <type>newFence</type>
            <category>animals</category>
            <tab>horses</tab>
        </brush>
    </storeData>

    <base>
        <filename>placeables/xcJumps/{NAME}.i3d</filename>
        <canBeRenamed>false</canBeRenamed>
    </base>

    <placement useRandomYRotation="false" useManualYRotation="true">
        <sounds>
            <place template="fenceWoodImp"/>
            <destroy template="destroyFence"/>
        </sounds>
    </placement>

    <fence>
{segment("ROPE", 0)}
{segment("ROPE_SIGN", 1)}
    </fence>
</placeable>
"""
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)


def main():
    preview_dir = os.environ.get("XC_PREVIEW_DIR", "art/previews")
    stake_mesh, plain, signed = stake(), Mesh(), Mesh()
    rope(plain)
    rope(signed)
    board, logos = sign()
    write_i3d(os.path.join(OUT, NAME + ".i3d"), stake_mesh, plain, signed, board, logos)
    write_xml(os.path.join(OUT, NAME + ".xml"))
    # shop image: three panels, the middle one with its sign
    flags = np.asarray(Image.open(os.path.join(OUT, "xcFlags_diffuse.dds")).convert("RGB"), dtype=float)
    sponsor = xc.logo_preview()

    def at(mesh, dz, flip=False):
        out = Mesh()
        out.verts = [((p[0], p[1], p[2] + dz), n, (uv[0], 1 - uv[1]) if flip else uv) for p, n, uv in mesh.verts]
        out.tris = list(mesh.tris)
        return out
    meshes = []
    for i in range(3):
        dz = (i - 1.5) * PANEL
        meshes += [(at(stake_mesh, dz), flags), (at(plain if i != 1 else signed, dz), flags)]
        if i == 1:
            meshes += [(at(board, dz), flags)] + [(at(m, dz, flip=True), sponsor) for m in logos.values()]
    meshes.append((at(stake_mesh, 1.5 * PANEL), flags))
    store_image(meshes, os.path.join(OUT, "store_" + NAME + ".dds"), preview_dir, yaw=-60, pitch=18)
    print(NAME, "rope and sign panels")


if __name__ == "__main__":
    main()
