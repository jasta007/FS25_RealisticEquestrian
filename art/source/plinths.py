"""
Builds the sponsor plinths in placeables/sponsorPlinths/ (James, 2026-10-31): platforms to park
a sponsor's machines on for extra branding. A machine of the signed sponsor's brand standing on
a plinth's deck counts (EqPlinths); each plinth also carries sponsor boards.

- plinthDrive: drive on, drive off. A flat deck 0.75 m up with a ramp at each end, so a trailer
  never has to be backed up anything; a board on each side.
- plinthRamp / plinthRampLarge: a solid stone display ramp, the machine parked nose up on the
  slope, the board on the high front face; for smaller and bigger machines.
- plinthProductRamp: one bank of the product jump, mostly ramp up to a short flat top; the player
  sets two facing each other with a gap between (James, 2026-11-01: two parts). Three
  places for machines (each bank and the gap, about 4.8 m wide), or a cross country jump: up one
  ramp, over whatever stands in the gap, down the other. The banks are 2 m up so a horse never comes near
  the machine in the slot (James: we REALLY don't want it knocked); no flags of its own, the
  player sets course flags where they want it ridden.
- plinthTurntable: a round stone plinth with a ramp at the back and a disc that turns very
  slowly (node "eqTurntableDisc"); a machine left on the disc is held on it and turned with it
  (EqTurntable). The board bends round the front.

Plain rendered stone (a texture painted here) with painted copings along the top edges: the
Colour bought, or the sponsor's colour (shapes named "eqPaint", EqJumpColours). Logos are shapes
named "eqSponsor_<n>" ("...b" for a board's back face), as everywhere else; the boards' faces
are "eqBoardFace", which EqSponsorBoards paints dark behind a light logo. Unlike the cross
country pieces, plinths never hide: a machine on show shouldn't float over nothing.

Everything is ridden or driven along z. The geometry is inline: re-save the i3ds in GIANTS Editor
(art/source/ge-resave.ps1) so their collision works in game.

Keep the deck areas in scripts/facilities/EqPlinths.lua in step with the sizes here.

Run from the repository root: python3 art/source/plinths.py [names]

Part of Realistic Equestrian by Jasta007.
"""

import math
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(__file__))
import show_jumps as sj  # noqa: E402
import xc_jumps as xc  # noqa: E402
from eqdds import save_dxt1  # noqa: E402
from xc_jumps import COLLISION_MASK, Mesh, fmt, shape_lines, store_image  # noqa: E402
# Our jumps' collision group (xc_jumps.COLLISION_GROUP, 0x1034) plus the ground bits 0x1 and 0x2 a
# vanilla drive-on floor has (bunker silo 0x17): without them hooves go silent on a plinth (a trial,
# James 2026-11-01; the game's step sound code can't be read).
COLLISION_GROUP = "0x1037"

OUT = "placeables/sponsorPlinths"
STONE = "plinthStone_diffuse.dds"
STONE_TILE = 5.0        # metres the stone texture covers each way
METAL = "plinthMetal_diffuse.dds"
METAL_TILE = 1.6
LOGO_TEXTURE = "../bleachers/bleacherSponsor_diffuse.dds"
FLAGS = "../xcJumps/xcFlags_diffuse.dds"
ASPECT = sj.LOGO_ASPECT
COPING = (0.14, 0.06)   # the painted edge's width and how far it stands over the top

PLINTHS = [
    {"name": "plinthDrive", "price": 8000, "colour": "navy"},
    {"name": "plinthRamp", "price": 5000, "colour": "green", "size": (3.0, 4.6, 1.2)},
    {"name": "plinthRampLarge", "price": 7500, "colour": "green", "size": (3.8, 6.6, 1.6)},
    {"name": "plinthProductRamp", "price": 6000, "colour": "red"},
    {"name": "plinthTurntable", "price": 25000, "colour": "navy"},
]
DRIVE = {"half_x": 1.6, "half_deck": 3.0, "ramp": 3.5, "height": 0.75}
PRODUCT = {"half_x": 2.0, "top": 1.5, "ramp": 7.5, "height": 2.0, "gap": 4.8}
TURNTABLE = {"radius": 4.0, "disc": 3.45, "height": 0.7, "ramp": 3.5, "ramp_half": 1.6, "sides": 64}
DISC = "eqTurntableDisc"     # the node EqTurntable turns


def stone_texture(path, size=1024):
    """A plain rendered finish (James, 2026-11-01: blocks stood out, then the mottling repeated too
    plainly): warm light grey, very soft clouding with no edges (noise smoothed in frequency, so it
    tiles), a fine grain. Covers STONE_TILE metres each way."""
    rng = np.random.default_rng(11)
    f = np.fft.fftfreq(size)
    radius = np.sqrt(f[:, None] ** 2 + f[None, :] ** 2)

    def noise(scale, amount):
        # scale: the clouds' size as a share of the tile
        spectrum = np.fft.fft2(rng.normal(0, 1, (size, size))) * np.exp(-(radius * scale * size / 4) ** 2)
        field = np.real(np.fft.ifft2(spectrum))
        return field / (field.std() + 1e-9) * amount
    base = np.array([170.0, 166.0, 156.0])
    shade = noise(0.25, 3.0) + noise(0.06, 1.6) + rng.normal(0, 1.8, (size, size))
    img = base[None, None, :] + shade[..., None]
    rgb = np.clip(img, 0, 255).astype(np.uint8)
    save_dxt1(Image.fromarray(rgb), path)
    return rgb


def metal_texture(path, size=512):
    """Tread plate for the turntable's disc: grey steel with raised lozenges in rows that cross,
    so the turning shows. Covers METAL_TILE metres."""
    rng = np.random.default_rng(5)
    img = np.zeros((size, size, 3)) + np.array([118.0, 121.0, 125.0])
    img += rng.normal(0, 3, (size, size, 1))
    cell = size // 16
    yy, xx = np.mgrid[0:cell, 0:cell]
    for row in range(16):
        for colm in range(16):
            # lozenges alternate direction like real tread plate
            u = (xx - cell / 2) / (cell * 0.42)
            v = (yy - cell / 2) / (cell * 0.12)
            if (row + colm) % 2:
                u, v = (yy - cell / 2) / (cell * 0.42), (xx - cell / 2) / (cell * 0.12)
            lozenge = (np.abs(u) + np.abs(v)) < 1
            lit = np.where(lozenge, 22.0 - 10.0 * (u + v), 0.0)
            img[row * cell:(row + 1) * cell, colm * cell:(colm + 1) * cell] += lit[..., None]
    rgb = np.clip(img, 0, 255).astype(np.uint8)
    save_dxt1(Image.fromarray(rgb), path)
    return rgb


def prism(mesh, outline, origin, ua, ub, n, depth, tile=1.0):
    """sj.prism with true face normals on the sides (sj.prism points them from the outline's
    middle, near enough for boxes but not for a long thin ramp)."""
    start = len(mesh.verts)
    sj.prism(mesh, outline, origin, ua, ub, n, depth, tile)
    area = sum(outline[i][0] * outline[(i + 1) % len(outline)][1] - outline[(i + 1) % len(outline)][0] * outline[i][1]
               for i in range(len(outline)))
    if xc.dot(xc.cross(ua, ub), n) * area < 0:
        outline = outline[::-1]
    ca = sum(a for a, _ in outline) / len(outline)
    cb = sum(b for _, b in outline) / len(outline)
    sides = start + 2 * len(outline)
    for k in range(len(outline)):
        (a0, b0), (a1, b1) = outline[k], outline[(k + 1) % len(outline)]
        da, db = a1 - a0, b1 - b0
        pa, pb = db, -da
        if pa * ((a0 + a1) / 2 - ca) + pb * ((b0 + b1) / 2 - cb) < 0:
            pa, pb = -pa, -pb
        normal = xc.norm(tuple(pa * ua[i] + pb * ub[i] for i in range(3)))
        for v in range(sides + 4 * k, sides + 4 * k + 4):
            p, _, uv = mesh.verts[v]
            mesh.verts[v] = (p, normal, uv)
    # the side quads' triangles were wound to the old normals: wind them again
    first_side_tri = len(mesh.tris) - 2 * len(outline)
    for t in range(first_side_tri, len(mesh.tris)):
        a, b, c = mesh.tris[t]
        pa_, pb_, pc_ = mesh.verts[a][0], mesh.verts[b][0], mesh.verts[c][0]
        if xc.dot(xc.cross(xc.sub(pb_, pa_), xc.sub(pc_, pa_)), mesh.verts[a][1]) < 0:
            mesh.tris[t] = (a, c, b)


def solid(mesh, col, profile, x0, x1):
    """A body whose side outline (z, y), convex, runs across x0..x1: stone on all faces."""
    prism(mesh, profile, (x0, 0.0, 0.0), (0, 0, 1), (0, 1, 0), (1, 0, 0), x1 - x0, tile=STONE_TILE)
    prism(col, profile, (x0, 0.0, 0.0), (0, 0, 1), (0, 1, 0), (1, 0, 0), x1 - x0)


def coping(mesh, top, x):
    """A painted strip along a top edge at x (the edge's middle), following the polyline top
    [(z, y), ...]."""
    w, up = COPING
    for (za, ya), (zb, yb) in zip(top, top[1:]):
        outline = [(za, ya - 0.04), (zb, yb - 0.04), (zb, yb + up), (za, ya + up)]
        prism(mesh, outline, (x - w / 2, 0.0, 0.0), (0, 0, 1), (0, 1, 0), (1, 0, 0), w)


def board(white, paint, logos, number, x, z, y0, width, height, facing):
    """A white board with a painted rim on a side face at x, facing +x (1) or -x (-1), centred on
    z, its foot at y0; the logo on it is "eqSponsor_<number>" (or "...b" facing -x)."""
    t = 0.04
    xa, xb = sorted((x, x + facing * t))
    xc_ = x + facing * (t + 0.005)
    xd_ = x + facing * (t + 0.008)
    prism(paint, [(z - width / 2, y0), (z + width / 2, y0), (z + width / 2, y0 + height), (z - width / 2, y0 + height)],
             (xa, 0.0, 0.0), (0, 0, 1), (0, 1, 0), (1, 0, 0), xb - xa)
    m = 0.04
    lo, hi = sorted((x + facing * t, xc_))
    prism(white, [(z - width / 2 + m, y0 + m), (z + width / 2 - m, y0 + m), (z + width / 2 - m, y0 + height - m),
                     (z - width / 2 + m, y0 + height - m)], (lo, 0.0, 0.0), (0, 0, 1), (0, 1, 0), (1, 0, 0), hi - lo)
    lw, lh = width - 2 * m - 0.06, height - 2 * m - 0.06
    if lw / lh > ASPECT:
        lw = lh * ASPECT
    else:
        lh = lw / ASPECT
    logo = Mesh()
    yc = y0 + height / 2
    # seen from where it faces: facing +x, +z is on the left
    left, right = (z + lw / 2, z - lw / 2) if facing > 0 else (z - lw / 2, z + lw / 2)
    logo.quad([(xd_, yc - lh / 2, left), (xd_, yc - lh / 2, right), (xd_, yc + lh / 2, right), (xd_, yc + lh / 2, left)],
              (facing, 0, 0), [(0, 0), (1, 0), (1, 1), (0, 1)])
    logos[f"eqSponsor_{number}" + ("" if facing > 0 else "b")] = logo


def front_board(white, paint, logos, number, z, y0, width, height):
    """A board on a front face at z facing -z, centred on x = 0."""
    t = 0.04
    prism(paint, [(-width / 2, y0), (width / 2, y0), (width / 2, y0 + height), (-width / 2, y0 + height)],
             (0.0, 0.0, z - t), (1, 0, 0), (0, 1, 0), (0, 0, 1), t)
    m = 0.04
    prism(white, [(-width / 2 + m, y0 + m), (width / 2 - m, y0 + m), (width / 2 - m, y0 + height - m), (-width / 2 + m, y0 + height - m)],
             (0.0, 0.0, z - t - 0.005), (1, 0, 0), (0, 1, 0), (0, 0, 1), 0.005)
    lw, lh = width - 2 * m - 0.06, height - 2 * m - 0.06
    if lw / lh > ASPECT:
        lw = lh * ASPECT
    else:
        lh = lw / ASPECT
    yc, zz = y0 + height / 2, z - t - 0.008
    logo = Mesh()
    # facing -z: +x is on the left
    logo.quad([(lw / 2, yc - lh / 2, zz), (-lw / 2, yc - lh / 2, zz), (-lw / 2, yc + lh / 2, zz), (lw / 2, yc + lh / 2, zz)],
              (0, 0, -1), [(0, 0), (1, 0), (1, 1), (0, 1)])
    logos[f"eqSponsor_{number}"] = logo


def drive():
    stone, paint, white, col, logos = Mesh(), Mesh(), Mesh(), Mesh(), {}
    hx, hd, r, h = DRIVE["half_x"], DRIVE["half_deck"], DRIVE["ramp"], DRIVE["height"]
    profile = [(-hd - r, 0.0), (hd + r, 0.0), (hd, h), (-hd, h)]
    solid(stone, col, [(-hd - r, 0.0), (-hd, 0.0), (-hd, h)], -hx, hx)
    solid(stone, col, [(-hd, 0.0), (hd, 0.0), (hd, h), (-hd, h)], -hx, hx)
    solid(stone, col, [(hd, 0.0), (hd + r, 0.0), (hd, h)], -hx, hx)
    top = [profile[0], profile[3], profile[2], profile[1]]
    for side in (1, -1):
        coping(paint, top, side * (hx - COPING[0] / 2 + 0.02))
        board(white, paint, logos, 1, side * hx, 0.0, 0.08, 2 * hd - 1.2, h - 0.2, side)
    return {"stone": stone, "paint": paint, "white": white}, logos, col, {}


def ramp(size):
    stone, paint, white, col, logos = Mesh(), Mesh(), Mesh(), Mesh(), {}
    w, length, h = size
    zf, zb = -length / 2, length / 2
    solid(stone, col, [(zf, 0.0), (zb, 0.0), (zf, h)], -w / 2, w / 2)
    for side in (1, -1):
        coping(paint, [(zf, h), (zb, 0.0)], side * (w / 2 - COPING[0] / 2 + 0.02))
    # the high front's coping across the top edge
    prism(paint, [(-w / 2, h - 0.04), (w / 2, h - 0.04), (w / 2, h + COPING[1]), (-w / 2, h + COPING[1])],
             (0.0, 0.0, zf - 0.02), (1, 0, 0), (0, 1, 0), (0, 0, 1), COPING[0])
    front_board(white, paint, logos, 1, zf, 0.12, w - 0.4, h - 0.32)
    return {"stone": stone, "paint": paint, "white": white}, logos, col, {}


def product():
    """One bank of the product jump: its 2 m face at z = 0 facing -z (towards the gap), a short flat
    top, then the ramp down to the ground. Two set facing each other make the jump (EqPlinths)."""
    stone, paint, white, col, logos = Mesh(), Mesh(), Mesh(), Mesh(), {}
    hx, top, r, h = PRODUCT["half_x"], PRODUCT["top"], PRODUCT["ramp"], PRODUCT["height"]
    solid(stone, col, [(0.0, 0.0), (top, 0.0), (top, h), (0.0, h)], -hx, hx)
    solid(stone, col, [(top, 0.0), (top + r, 0.0), (top, h)], -hx, hx)
    for side in (1, -1):
        coping(paint, [(0.0, h), (top, h), (top + r, 0.0)], side * (hx - COPING[0] / 2 + 0.02))
        # the board on the side, under the top and the start of the ramp, set up and back along it
        # (James, 2026-11-01) as far as the slope above lets it
        board(white, paint, logos, 1, side * hx, 2.0, 0.28, 3.0, 1.05, side)
    # the take-off edge over the gap
    prism(paint, [(-hx, h - 0.04), (hx, h - 0.04), (hx, h + COPING[1]), (-hx, h + COPING[1])],
          (0.0, 0.0, -0.02), (1, 0, 0), (0, 1, 0), (0, 0, 1), COPING[0])
    return {"stone": stone, "paint": paint, "white": white}, logos, col, {}


def circle(radius, sides, start=0.0):
    return [(radius * math.cos(start + 2 * math.pi * k / sides), radius * math.sin(start + 2 * math.pi * k / sides))
            for k in range(sides)]


def cylinder(mesh, radius, y0, y1, sides, tile=STONE_TILE):
    """A closed upright cylinder: its outline in (x, z), extruded up."""
    prism(mesh, circle(radius, sides), (0.0, y0, 0.0), (1, 0, 0), (0, 0, 1), (0, 1, 0), y1 - y0, tile=tile)


def turntable():
    stone, paint, white, col, logos, disc = Mesh(), Mesh(), Mesh(), Mesh(), {}, Mesh()
    t = TURNTABLE
    R, r, h, n = t["radius"], t["disc"], t["height"], t["sides"]
    cylinder(stone, R, 0.0, h, n)
    cylinder(col, R, 0.0, h + 0.02, n)
    # a painted collar round the top edge, showing as a ring round the disc
    cylinder(paint, R + 0.012, h - 0.12, h + 0.015, n)
    # the disc that turns, a tread plate flush with the top, in its own node
    cylinder(disc, r, h - 0.03, h + 0.02, n, tile=METAL_TILE)
    # the ramp up at the back (+z): level with the top from the disc's edge out over the collar,
    # then down (James: no rails, flush with the circle)
    hw, length = t["ramp_half"], t["ramp"]
    z0, z1 = r + 0.02, R + 0.05
    # just under the collar's top, so its square corners don't show over the round edge (James)
    top = h + 0.008
    solid(stone, col, [(z0, 0.0), (R + length, 0.0), (z1, top), (z0, top)], -hw, hw)
    # a curved board round the front (-z), the logo bent round it in strips
    # the board only as wide as the logo needs, so the logo fills it (James, 2026-11-01: it sat
    # small in the middle of a long board)
    y0, bh = 0.08, h - 0.22
    width = (bh - 0.08) * ASPECT + 0.3
    steps = 12
    span = width / R
    for layer, mesh, out, inset in ((0, paint, 0.04, 0.0), (1, white, 0.046, 0.04)):
        for k in range(steps):
            a0 = -span / 2 + span * k / steps
            a1 = -span / 2 + span * (k + 1) / steps
            r0, r1 = R + out - 0.04, R + out
            pts = [(r0 * math.sin(a0), -r0 * math.cos(a0)), (r1 * math.sin(a0), -r1 * math.cos(a0)),
                   (r1 * math.sin(a1), -r1 * math.cos(a1)), (r0 * math.sin(a1), -r0 * math.cos(a1))]
            if layer == 1:
                # the white face sits inside the painted rim
                trim = inset / R
                if k == 0:
                    pts = [(rr * math.sin(a0 + trim), -rr * math.cos(a0 + trim)) if i < 2 else pts[i]
                           for i, rr in enumerate((r0, r1, r1, r0))]
                if k == steps - 1:
                    pts = [(rr * math.sin(a1 - trim), -rr * math.cos(a1 - trim)) if i >= 2 else pts[i]
                           for i, rr in enumerate((r0, r1, r1, r0))]
            lo, hi = (y0, y0 + bh) if layer == 0 else (y0 + inset, y0 + bh - inset)
            prism(mesh, pts, (0.0, lo, 0.0), (1, 0, 0), (0, 0, 1), (0, 1, 0), hi - lo)
    lh = bh - 0.08
    lw = min(lh * ASPECT, width - 0.2)
    lh = lw / ASPECT
    logo = Mesh()
    rl = R + 0.048
    la = lw / rl
    yc = y0 + bh / 2
    for k in range(steps):
        a0 = -la / 2 + la * k / steps
        a1 = -la / 2 + la * (k + 1) / steps
        # facing -z from the front: +x is on the left, so u runs from +x (a > 0) to -x
        u0, u1 = 1 - k / steps, 1 - (k + 1) / steps
        p0 = (rl * math.sin(a0), -rl * math.cos(a0))
        p1 = (rl * math.sin(a1), -rl * math.cos(a1))
        nm = (math.sin((a0 + a1) / 2), 0.0, -math.cos((a0 + a1) / 2))
        logo.quad([(p0[0], yc - lh / 2, p0[1]), (p1[0], yc - lh / 2, p1[1]), (p1[0], yc + lh / 2, p1[1]), (p0[0], yc + lh / 2, p0[1])],
                  nm, [(u0, 0), (u1, 0), (u1, 1), (u0, 1)])
    logos["eqSponsor_1"] = logo
    return {"stone": stone, "paint": paint, "white": white, "disc": disc}, logos, col, {}


def write_i3d(name, colour, path, statics, logos, col, feet):
    files = [sj.SHADER] + list(sj.PAINT_MAPS.values()) + [STONE, LOGO_TEXTURE, FLAGS, METAL]
    fid = {f: i + 1 for i, f in enumerate(files)}
    mat = {"stone": 1, "paint": 2, "white": 3, "logo": 4, "flags": 5, "metal": 6}

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
             "  <Asset>", '    <Export program="Realistic Equestrian plinths.py" version="1"/>', "  </Asset>", "  <Files>"]
    lines += [f'    <File fileId="{fid[f]}" filename="{f}"/>' for f in files]
    lines += ["  </Files>", "  <Materials>",
              f'    <Material name="plinthStone" materialId="{mat["stone"]}" specularColor="0.15 0.6 0">',
              f'      <Texture fileId="{fid[STONE]}"/>', "    </Material>"]
    lines += paint_material("plinthPaint", mat["paint"], sj.COLOUR[colour])
    lines += paint_material("plinthWhite", mat["white"], sj.WHITE)
    lines += [f'    <Material name="eqSponsor" materialId="{mat["logo"]}" specularColor="0.2 0 0" alphaBlending="true">',
              f'      <Texture fileId="{fid[LOGO_TEXTURE]}"/>', "    </Material>",
              f'    <Material name="xcFlags" materialId="{mat["flags"]}" specularColor="0.1 0.7 0">',
              f'      <Texture fileId="{fid[FLAGS]}"/>', "    </Material>",
              f'    <Material name="plinthMetal" materialId="{mat["metal"]}" specularColor="0.6 0.6 0">',
              f'      <Texture fileId="{fid[METAL]}"/>', "    </Material>", "  </Materials>"]
    shapes = [(f"s_{k}", m) for k, m in statics.items() if m.tris] + [(f"l_{k}", m) for k, m in logos.items()]
    shapes.append(("col", col))
    ids = {key: i + 1 for i, (key, _) in enumerate(shapes)}
    lines.append("  <Shapes>")
    for key, mesh in shapes:
        lines += shape_lines(mesh, f"{name}_{key}", ids[key])
    lines += ["  </Shapes>", "  <Scene>"]
    node = [1]

    def nid():
        node[0] += 1
        return node[0]
    names = {"stone": "stone", "paint": "eqPaint", "white": "eqBoardFace", "flags": "flags"}
    lines.append(f'    <TransformGroup name="{name}" nodeId="1">')
    for key, mesh in statics.items():
        if mesh.tris and key == "disc":
            lines.append(f'      <TransformGroup name="{DISC}" nodeId="{nid()}">')
            lines.append(f'        <Shape name="disc" shapeId="{ids["s_" + key]}" clipDistance="{xc.CLIP * 2}" nodeId="{nid()}" '
                         f'materialIds="{mat["metal"]}" castsShadows="true" receiveShadows="true"/>')
            lines.append("      </TransformGroup>")
        elif mesh.tris:
            lines.append(f'      <Shape name="{names[key]}" shapeId="{ids["s_" + key]}" clipDistance="{xc.CLIP * 2}" nodeId="{nid()}" '
                         f'materialIds="{mat[key]}" castsShadows="true" receiveShadows="true"/>')
    for key in logos:
        lines.append(f'      <Shape name="{key}" shapeId="{ids["l_" + key]}" clipDistance="{xc.CLIP * 2}" nodeId="{nid()}" '
                     f'materialIds="{mat["logo"]}" castsShadows="false" receiveShadows="true"/>')
    for flag_name in ("eqFlagsRed", "eqFlagsWhite"):
        if flag_name in feet:
            lines.append(f'      <TransformGroup name="{flag_name}" translation="{fmt(feet[flag_name])}" nodeId="{nid()}"/>')
    lines.append(f'      <TransformGroup name="collision" nodeId="{nid()}">')
    lines.append(f'        <Shape name="col" shapeId="{ids["col"]}" static="true" collisionFilterGroup="{COLLISION_GROUP}" '
                 f'collisionFilterMask="{COLLISION_MASK}" density="0.01" nodeId="{nid()}" nonRenderable="true" materialIds="1"/>')
    lines += ["      </TransformGroup>", "    </TransformGroup>", "  </Scene>", "</i3D>"]
    with open(path, "w", encoding="iso-8859-1", newline="\n") as f:
        f.write("\n".join(lines) + "\n")


def write_xml(plinth, path, jump):
    name = plinth["name"]
    jump_line = "            <function>$l10n_eq_shop_productJump_function</function>\n" if jump else ""
    if name == "plinthTurntable":
        jump_line = "            <function>$l10n_eq_shop_turntable_function</function>\n"
    text = f"""<?xml version="1.0" encoding="utf-8" standalone="no"?>
<!-- Made by art/source/plinths.py: change that and run it again rather than editing this. -->
<placeable type="simplePlaceable">
    <storeData>
        <name>$l10n_eq_shop_{name}</name>
        <functions>
            <function>$l10n_eq_shop_plinth_function</function>
{jump_line}        </functions>
        <image>{OUT}/store_{name}.dds</image>
        <price>{plinth["price"]}</price>
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
        <filename>{OUT}/{name}.i3d</filename>
        <canBeRenamed>false</canBeRenamed>
    </base>

    <placement useRandomYRotation="false" useManualYRotation="true">
        <!-- Driven along z. The decks a sponsor's machine counts on are in EqPlinths.AREAS. -->
    </placement>

{sj.colour_configurations("eqPoleColour", plinth["colour"])}
</placeable>
"""
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)


def main(names=()):
    preview_dir = os.environ.get("XC_PREVIEW_DIR", "art/previews")
    os.makedirs(OUT, exist_ok=True)
    stone_rgb = stone_texture(os.path.join(OUT, STONE))
    metal_rgb = metal_texture(os.path.join(OUT, METAL))
    sponsor = xc.logo_preview()
    flags_rgb = np.asarray(Image.open("placeables/xcJumps/xcFlags_diffuse.dds").convert("RGB"), dtype=float)
    builders = {"plinthDrive": drive, "plinthRamp": lambda: ramp(PLINTHS[1]["size"]),
                "plinthRampLarge": lambda: ramp(PLINTHS[2]["size"]), "plinthProductRamp": product,
                "plinthTurntable": turntable}
    for plinth in PLINTHS:
        name = plinth["name"]
        if names and name not in names:
            continue
        statics, logos, col, feet = builders[name]()
        write_i3d(name, plinth["colour"], os.path.join(OUT, name + ".i3d"), statics, logos, col, feet)
        write_xml(plinth, os.path.join(OUT, name + ".xml"), name == "plinthProductRamp")

        def flip(mesh):
            out = Mesh()
            out.verts = [(p, n, (uv[0], 1 - uv[1])) for p, n, uv in mesh.verts]
            out.tris = list(mesh.tris)
            return out
        meshes = [(statics["stone"], stone_rgb), (statics["paint"], sj.flat(sj.COLOUR[plinth["colour"]])),
                  (statics["white"], sj.flat(sj.WHITE))]
        if "flags" in statics:
            meshes.append((flip(statics["flags"]), flags_rgb))
        if "disc" in statics:
            meshes.append((statics["disc"], metal_rgb))
        meshes += [(flip(m), sponsor) for m in logos.values()]
        store_image([m for m in meshes if m[0].tris], os.path.join(OUT, "store_" + name + ".dds"), preview_dir, yaw=-130)
        print(name, len(logos), "logo faces,", len(col.tris), "collision triangles")


if __name__ == "__main__":
    main(tuple(sys.argv[1:]))
