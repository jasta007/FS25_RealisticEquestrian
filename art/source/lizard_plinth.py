"""
Builds the Lizard plinth in placeables/sponsorPlinths/ (James, 2026-11-01): the special plinth
Lizard, the game's own brand, asks for when it offers a free one-off sponsorship of a hosted event
(EqLizard). It looks cheap and slapped together: a mound of whatever bulk material Lizard asked
for, logs laid across the top as a deck to park a machine on, a lizard cut out of planks standing
at the back (traced by James, LIZARD_OUTLINE) and the Lizard logotype on a board at the front.

It is a constructible, like the game's rental houses: bought for next to nothing, then built
from what the farm delivers to its triggers in front of it:

    SETUP       a few stakes; the bulk material: stone (1,000 l, as from stone picking),
                wood chips (1,000 l) or straw (10,000 l), tipped or (straw) as bales
    BUILDING_1  the mound is there; logs (WOOD, about five tree logs) at the wood trigger
    BUILDING_2  the logs are on top; planks (PLANKS pallets)
    FINALIZE    the lizard and the logo board go up, the stakes and triggers go

One placeable for each material ("lizardPlinthStone" ...), the mound textured with the game's
own fill plane for it; the shop shows only the one a farm's Lizard deal asks for (EqLizard).
After the event it collapses and is gone (EqLizard).

Everything is driven along x, onto the log deck from either side; the front (the logo board and
the triggers) faces -z. Keep the deck in EqPlinths.AREAS in step with DECK here.

Run from the repository root: python3 art/source/lizard_plinth.py

Part of Realistic Equestrian by Jasta007.
"""

import math
import os
import random
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(__file__))
import show_jumps as sj  # noqa: E402
import xc_jumps as xc  # noqa: E402
from xc_jumps import COLLISION_MASK, Mesh, fmt, shape_lines, store_image  # noqa: E402

OUT = "placeables/sponsorPlinths"
COLLISION_GROUP = "0x1037"      # as the other plinths (plinths.py): hooves sound on it
PRICE = 500

# The materials Lizard may ask for (James, 2026-11-01: "sometimes straw, sometimes stones,
# sometimes wood chips"; straw 10,000 l, the others 1,000 l). fillPlane: the game's texture.
VARIANTS = [
    {"name": "lizardPlinthStone", "fillType": "STONE", "amount": 1000, "rate": 1000, "fillPlane": "stone",
     "preview": (128, 124, 116), "tip": "STONE", "bale": False},
    {"name": "lizardPlinthWoodChips", "fillType": "WOODCHIPS", "amount": 1000, "rate": 1000, "fillPlane": "woodChips",
     "preview": (150, 112, 70), "tip": "WOODCHIPS", "bale": False},
    {"name": "lizardPlinthStraw", "fillType": "STRAW", "amount": 10000, "rate": 10000, "fillPlane": "straw",
     "preview": (206, 180, 104), "tip": "STRAW", "bale": True},
]
WOOD = 2000         # litres of logs, about five tree logs (James: "5 tree logs worth")
PLANKS = 1000       # litres of planks (James: 1,000 short planks rather than 500 long ones)


def read_amounts(path="data/sponsors.xml"):
    """The amounts from data/sponsors.xml's lizard block (EqLizard reads the same), so the two
    stay in step."""
    import xml.etree.ElementTree as ET
    global WOOD, PLANKS
    lizard = ET.parse(path).getroot().find("lizard")
    if lizard is None:
        return
    for material in lizard.findall("material"):
        for variant in VARIANTS:
            if variant["fillType"] == material.get("fillType"):
                variant["amount"] = int(float(material.get("amount")))
    for part in lizard.findall("part"):
        if part.get("fillType") == "WOOD":
            WOOD = int(float(part.get("amount")))
        elif part.get("fillType") == "PLANKS":
            PLANKS = int(float(part.get("amount")))

H = 0.9                     # the mound's top
DECK = {"hx": 2.05, "hz": 1.85}   # the log deck on top, logs along z, machines drive along x
LOG_D = 0.44
LOG_LEN = 3.6
DECK_TOP = H + 0.25         # where a parked machine's wheels are (the deck collision)
MOUND = {"rx": 5.3, "rz": 3.3}    # the footprint's half sizes (the ramps run along x)
TILE = 2.0                  # metres one fill plane texture covers
LIZARD = {"z": 2.35, "height": 3.4, "plank": 0.11, "gap": 0.016, "thick": 0.028}
BOARD = {"z": -3.05, "width": 2.6, "height": 0.8, "y0": 0.35}
TRIGGERS = {"z": -6.2, "hx": 2.6, "hz": 2.4}

# James's trace of the lizard (lizard.svg, 2026-11-01): x right, y down, in the SVG's units.
LIZARD_OUTLINE = [
    (806, 584), (806, 575), (798, 552), (787, 559), (783, 556), (781, 550), (780, 539), (772, 535), (778, 535),
    (777, 528), (781, 533), (785, 528), (785, 535), (791, 532), (785, 538), (785, 540), (788, 548), (800, 538),
    (805, 531), (805, 520), (813, 510), (818, 510), (827, 504), (829, 504), (835, 508), (835, 510), (832, 520),
    (832, 525), (829, 534), (821, 538), (821, 541), (822, 543), (837, 558), (839, 551), (839, 549), (834, 543),
    (840, 546), (841, 539), (843, 545), (849, 540), (846, 547), (852, 548), (845, 551), (843, 563), (841, 566),
    (839, 566), (829, 561), (833, 575), (833, 584),
]


def clamp(v, lo, hi):
    return max(lo, min(hi, v))


# ---------------------------------------------------------------------------------------------
# The mound

def ray_to_rect(a, hx, hz):
    """How far a ray from the middle at angle a (x = cos, z = sin) runs inside the deck rectangle."""
    c, s = abs(math.cos(a)), abs(math.sin(a))
    return min(hx / c if c > 1e-6 else 1e9, hz / s if s > 1e-6 else 1e9)


def footprint(a, rng_waves):
    """The mound's edge at angle a: a rounded rectangle-ish superellipse, a little uneven."""
    c, s = math.cos(a), math.sin(a)
    p = 3.0
    r = (abs(c / MOUND["rx"]) ** p + abs(s / MOUND["rz"]) ** p) ** (-1 / p)
    wobble = sum(amp * math.sin(k * a + ph) for k, ph, amp in rng_waves)
    return r * (1 + wobble)


def mound_height(u, a, lumps):
    """Height at share u (0 at the deck's edge, 1 at the foot) along the ray at angle a."""
    base = H * (1 - u) ** 1.25 * (1 - 0.15 * u * (1 - u))
    bump = sum(amp * math.sin(k * a + ph) * math.sin(math.pi * u) for k, ph, amp in lumps)
    return max(0.0, base + bump)


def mound(collision=False):
    """The mound as a polar grid from the middle: flat (the deck) out to the deck's edge, then down
    to a foot sunk a little into the ground. The collision raises the deck to the logs' top."""
    rng = random.Random(5)
    waves = [(k, rng.uniform(0, 6.3), rng.uniform(0.01, 0.03)) for k in (3, 5, 7, 11)]
    lumps = [(k, rng.uniform(0, 6.3), rng.uniform(0.02, 0.05)) for k in (4, 6, 9)]
    sides = 72
    inner = [0.0, 0.35, 0.7, 1.0]           # shares of the deck's reach
    outer = [i / 10 for i in range(1, 11)]   # shares of the slope
    mesh = Mesh()
    grid = []
    for k in range(sides + 1):
        a = 2 * math.pi * k / sides
        d0 = ray_to_rect(a, DECK["hx"], DECK["hz"])
        r1 = footprint(a, waves)
        row = []
        for t in inner:
            y = DECK_TOP if collision else H
            row.append((math.cos(a) * d0 * t, y, math.sin(a) * d0 * t))
        for u in outer:
            r = d0 + (r1 - d0) * u
            row.append((math.cos(a) * r, mound_height(u, a, lumps), math.sin(a) * r))
        # the foot, under the ground so the mound never floats on a slope
        row.append((math.cos(a) * r1 * 1.04, -0.2, math.sin(a) * r1 * 1.04))
        grid.append(row)
    ids = []
    for k, row in enumerate(grid):
        ids_row = []
        for i, p in enumerate(row):
            ids_row.append(None)
        ids.append(ids_row)
    # normals from the neighbours
    for k in range(sides + 1):
        for i, p in enumerate(grid[k]):
            kp, km = grid[(k + 1) % sides], grid[(k - 1) % sides]
            ip, im = min(i + 1, len(grid[k]) - 1), max(i - 1, 0)
            along = xc.sub(grid[k][ip], grid[k][im])
            round_ = xc.sub(kp[i], km[i])
            n = xc.norm(xc.cross(along, round_)) if i > 0 else (0.0, 1.0, 0.0)
            if n[1] < 0:
                n = tuple(-v for v in n)
            ids[k][i] = mesh.vertex(p, n, (p[0] / TILE, p[2] / TILE))
    for k in range(sides):
        for i in range(len(grid[k]) - 1):
            a, b = ids[k][i], ids[k][i + 1]
            c, d = ids[k + 1][i + 1], ids[k + 1][i]
            mesh.tri(a, b, c)
            mesh.tri(a, c, d)
    return mesh


# ---------------------------------------------------------------------------------------------
# The logs, planks and boards

def logs():
    """The deck: logs along z, side by side along x, half sunk into the mound."""
    barks, ends = Mesh(), Mesh()
    rng = random.Random(17)
    count = int(round(2 * DECK["hx"] / LOG_D))
    for i in range(count):
        x = -DECK["hx"] + LOG_D / 2 + i * (2 * DECK["hx"] - LOG_D) / (count - 1)
        r = LOG_D / 2 * rng.uniform(0.92, 1.04)
        thin = r * (1 - rng.uniform(0.1, 0.25))
        r0, r1 = (r, thin) if rng.random() < 0.5 else (thin, r)
        z0 = -LOG_LEN / 2 + rng.uniform(-0.2, 0.2)
        z1 = LOG_LEN / 2 + rng.uniform(-0.2, 0.2)
        bark, end = Mesh(), Mesh()
        # built along x by xc.build_log, then turned a quarter round y: (x, y, z) -> (z, y, -x)
        xc.build_log((H + r * 0.35, x, -z1, -z0, r0, r1, rng.randrange(1 << 30)), bark, end)
        for src, dst in ((bark, barks), (end, ends)):
            base = len(dst.verts)
            for p, n, uv in src.verts:
                dst.verts.append(((p[2], p[1], -p[0]), (n[2], n[1], -n[0]), uv))
            dst.tris += [(a + base, b + base, c + base) for a, b, c in src.tris]
    return barks, ends


def plank_uv(board, u0, u1):
    """A strip of the plank texture: one of its eight boards, u along the plank."""
    v0, v1 = (board + 0.12) / 8, (board + 0.88) / 8
    return [(u0, v0), (u1, v0), (u1, v1), (u0, v1)]


def oriented_box(mesh, centre, axes, half, board, u_len=1.5):
    """A box with half sizes half along three unit axes (along, up, out), planks textured along
    the first axis, all six faces."""
    ax, ay, az = axes
    hx, hy, hz = half

    def at(sx, sy, sz):
        return tuple(centre[i] + ax[i] * sx * hx + ay[i] * sy * hy + az[i] * sz * hz for i in range(3))
    u = 2 * hx / u_len
    faces = [
        (az, [at(-1, -1, 1), at(1, -1, 1), at(1, 1, 1), at(-1, 1, 1)], plank_uv(board, 0, u)),
        (tuple(-v for v in az), [at(1, -1, -1), at(-1, -1, -1), at(-1, 1, -1), at(1, 1, -1)], plank_uv(board, 0, u)),
        (ay, [at(-1, 1, 1), at(1, 1, 1), at(1, 1, -1), at(-1, 1, -1)], plank_uv(board, 0, u)),
        (tuple(-v for v in ay), [at(-1, -1, -1), at(1, -1, -1), at(1, -1, 1), at(-1, -1, 1)], plank_uv(board, 0, u)),
        (ax, [at(1, -1, 1), at(1, -1, -1), at(1, 1, -1), at(1, 1, 1)], plank_uv(board, 0, 0.05)),
        (tuple(-v for v in ax), [at(-1, -1, -1), at(-1, -1, 1), at(-1, 1, 1), at(-1, 1, -1)], plank_uv(board, 0, 0.05)),
    ]
    for n, corners, uvs in faces:
        mesh.quad(corners, n, uvs)


def outline_metres():
    """The lizard's outline in metres: x across (centred), y up from its feet."""
    xs = [p[0] for p in LIZARD_OUTLINE]
    ys = [p[1] for p in LIZARD_OUTLINE]
    scale = LIZARD["height"] / (max(ys) - min(ys))
    cx = (min(xs) + max(xs)) / 2
    # seen from the front (-z), +x is on the viewer's left: mirror x so it reads as traced
    return [(-(x - cx) * scale, (max(ys) - y) * scale) for x, y in LIZARD_OUTLINE[::-1]]


def spans_at(poly, y):
    """Where a horizontal line at y is inside the polygon: a list of (x0, x1)."""
    xs = []
    for (x0, y0), (x1, y1) in zip(poly, poly[1:] + poly[:1]):
        if (y0 <= y < y1) or (y1 <= y < y0):
            xs.append(x0 + (y - y0) * (x1 - x0) / (y1 - y0))
    xs.sort()
    return [(xs[i], xs[i + 1]) for i in range(0, len(xs) - 1, 2)]


def merge(spans):
    spans = sorted(spans)
    out = []
    for a, b in spans:
        if out and a <= out[-1][1] + 0.02:
            out[-1] = (out[-1][0], max(out[-1][1], b))
        else:
            out.append((a, b))
    return out


def lizard(base_y):
    """The lizard: rows of planks nailed across two battens, each plank as long as the outline is
    wide there (a few samples over its height), a little uneven, as if cut by eye."""
    mesh = Mesh()
    poly = outline_metres()
    rng = random.Random(3)
    t, z = LIZARD["thick"], LIZARD["z"]
    step = LIZARD["plank"] + LIZARD["gap"]
    rows = int(LIZARD["height"] / step) + 1
    for row in range(rows):
        y0 = row * step
        y1 = y0 + LIZARD["plank"]
        samples = [y0 + (y1 - y0) * f for f in (0.1, 0.35, 0.65, 0.9)]
        spans = merge([s for y in samples for s in spans_at(poly, y)])
        for a, b in spans:
            if b - a < 0.03:
                continue
            a -= rng.uniform(0.0, 0.03)
            b += rng.uniform(0.0, 0.03)
            tilt = rng.uniform(-0.025, 0.025)
            along = xc.norm((1.0, tilt, 0.0))
            up = xc.norm((-tilt, 1.0, 0.0))
            zz = z + rng.uniform(-0.006, 0.006)
            oriented_box(mesh, ((a + b) / 2, base_y + (y0 + y1) / 2, zz), (along, up, (0.0, 0.0, -1.0)),
                         ((b - a) / 2, LIZARD["plank"] / 2, t / 2), rng.randrange(8))
    # two battens behind, down into the mound, and a prop behind each
    for bx in (-0.32, 0.28):
        top = base_y + 1.55
        bottom = base_y - 0.45
        oriented_box(mesh, (bx, (top + bottom) / 2, z + t + 0.02), ((0.0, 1.0, 0.0), (1.0, 0.0, 0.0), (0.0, 0.0, 1.0)),
                     ((top - bottom) / 2, 0.045, 0.02), rng.randrange(8))
        foot = (bx, base_y - 0.35, z + 1.1)
        head = (bx, base_y + 1.1, z + t + 0.05)
        along = xc.norm(xc.sub(head, foot))
        mid = tuple((foot[i] + head[i]) / 2 for i in range(3))
        length = math.dist(foot, head)
        side = (1.0, 0.0, 0.0)
        out = xc.norm(xc.cross(along, side))
        oriented_box(mesh, mid, (along, out, side), (length / 2, 0.035, 0.03), rng.randrange(8))
    return mesh


def board():
    """The logo board at the front on two stakes, leaning back a little: a plank frame round a
    black face with the logo on it ("eqSponsor_1", always Lizard's: EqSponsors)."""
    planks, face, logos = Mesh(), Mesh(), {}
    rng = random.Random(9)
    w, h, y0, z = BOARD["width"], BOARD["height"], BOARD["y0"], BOARD["z"]
    lean = math.radians(8)
    up = (0.0, math.cos(lean), math.sin(lean))
    out = (0.0, -math.sin(lean), math.cos(lean))      # towards +z (the back)
    back = tuple(-v for v in out)                      # the face looks towards -z

    def p(x, v, d=0.0):
        return (x, y0 + up[1] * v + out[1] * d, z + up[2] * v + out[2] * d)
    # stakes into the ground
    for sx in (-w / 2 + 0.25, w / 2 - 0.25):
        oriented_box(planks, p(sx, h / 2 - 0.25, 0.06), (up, (1.0, 0.0, 0.0), out), (h / 2 + 0.45, 0.05, 0.03), rng.randrange(8))
    # the black face
    face.quad([p(-w / 2, 0, 0), p(w / 2, 0, 0), p(w / 2, h, 0), p(-w / 2, h, 0)], back, [(0, 0), (1, 0), (1, 1), (0, 1)])
    face.quad([p(w / 2, 0, 0.02), p(-w / 2, 0, 0.02), p(-w / 2, h, 0.02), p(w / 2, h, 0.02)], out, [(0, 0), (1, 0), (1, 1), (0, 1)])
    # a frame of planks round it
    t = 0.07
    for cx, cv, hx, hv in ((0, -t / 2, w / 2 + t, t / 2), (0, h + t / 2, w / 2 + t, t / 2)):
        oriented_box(planks, p(cx, cv, -0.012), ((1.0, 0.0, 0.0), up, back), (hx, hv, 0.02), rng.randrange(8))
    for cx in (-w / 2 - t / 2, w / 2 + t / 2):
        oriented_box(planks, p(cx, h / 2, -0.012), (up, (1.0, 0.0, 0.0), back), (h / 2, t / 2, 0.02), rng.randrange(8))
    # the logo, as wide as the face allows at the logo texture's shape
    lw, lh = w - 0.2, h - 0.14
    if lw / lh > sj.LOGO_ASPECT:
        lw = lh * sj.LOGO_ASPECT
    else:
        lh = lw / sj.LOGO_ASPECT
    logo = Mesh()
    d = -0.006
    logo.quad([p(lw / 2, (h - lh) / 2, d), p(-lw / 2, (h - lh) / 2, d), p(-lw / 2, (h + lh) / 2, d), p(lw / 2, (h + lh) / 2, d)],
              back, [(0, 0), (1, 0), (1, 1), (0, 1)])
    logos["eqSponsor_1"] = logo
    return planks, face, logos


def stakes():
    """The site before anything is built: four stakes with a plank across the front."""
    mesh = Mesh()
    rng = random.Random(21)
    for sx, sz in ((-3.2, -2.0), (3.2, -2.0), (-3.2, 2.0), (3.2, 2.0)):
        oriented_box(mesh, (sx, 0.45, sz), ((0.0, 1.0, 0.0), (1.0, 0.0, 0.0), (0.0, 0.0, 1.0)), (0.65, 0.04, 0.04), rng.randrange(8))
    oriented_box(mesh, (0.0, 0.85, -2.06), ((1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, 1.0)), (3.3, 0.06, 0.012), rng.randrange(8))
    return mesh


def box_mesh(cx, cy, cz, hx, hy, hz):
    """A closed box (triggers and collision)."""
    mesh = Mesh()
    mesh.box(cx - hx, cx + hx, cy - hy, cy + hy, cz - hz, cz + hz, (0.5, 0.5))
    mesh.quad([(cx - hx, cy - hy, cz - hz), (cx + hx, cy - hy, cz - hz), (cx + hx, cy - hy, cz + hz), (cx - hx, cy - hy, cz + hz)],
              (0, -1, 0), [(0.5, 0.5)] * 4)
    return mesh


# ---------------------------------------------------------------------------------------------
# Files

def lizard_base():
    """Where the lizard's feet are: on the mound's slope behind the deck, a little sunk in."""
    return 0.75


def write_i3d(variant, path, parts):
    plane = variant["fillPlane"]
    files = [f"$data/fillPlanes/{plane}_diffuse.png", f"$data/fillPlanes/{plane}_normal.png",
             "../xcJumps/xcBarkA_diffuse.dds", "../xcJumps/xcBarkA_normal.dds", "../xcJumps/xcLogEnd_diffuse.dds",
             "../xcJumps/xcPlanks_diffuse.dds", "../xcJumps/xcPlanks_normal.dds", "../bleachers/bleacherSponsor_diffuse.dds"]
    fid = {f: i + 1 for i, f in enumerate(files)}
    lines = ['<?xml version="1.0" encoding="iso-8859-1"?>', "",
             f'<i3D name="{variant["name"]}" version="1.6" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
             'xsi:noNamespaceSchemaLocation="http://i3d.giants.ch/schema/i3d-1.6.xsd">',
             "  <Asset>", '    <Export program="Realistic Equestrian lizard_plinth.py" version="1"/>', "  </Asset>", "  <Files>"]
    lines += [f'    <File fileId="{fid[f]}" filename="{f}"/>' for f in files]
    lines += ["  </Files>", "  <Materials>",
              '    <Material name="lizardMound" materialId="1" specularColor="0.1 0.8 0">',
              f'      <Texture fileId="{fid[files[0]]}"/>', f'      <Normalmap fileId="{fid[files[1]]}"/>', "    </Material>",
              '    <Material name="lizardBark" materialId="2" specularColor="0.1 0.7 0">',
              f'      <Texture fileId="{fid[files[2]]}"/>', f'      <Normalmap fileId="{fid[files[3]]}"/>', "    </Material>",
              '    <Material name="lizardLogEnd" materialId="3" specularColor="0.1 0.7 0">',
              f'      <Texture fileId="{fid[files[4]]}"/>', "    </Material>",
              '    <Material name="lizardPlanks" materialId="4" specularColor="0.15 0.6 0">',
              f'      <Texture fileId="{fid[files[5]]}"/>', f'      <Normalmap fileId="{fid[files[6]]}"/>', "    </Material>",
              '    <Material name="lizardBoardFace" materialId="5" diffuseColor="0.03 0.03 0.03 1" specularColor="0.2 0.4 0"/>',
              '    <Material name="eqSponsor" materialId="6" specularColor="0.2 0.5 0" alphaBlending="true">',
              f'      <Texture fileId="{fid[files[7]]}"/>', "    </Material>",
              '    <Material name="trigger" materialId="7" diffuseColor="0.5 0.5 0.5 1"/>',
              "  </Materials>"]
    shapes = []
    for key, mesh in parts.items():
        if mesh["mesh"].tris:
            shapes.append((key, mesh))
    ids = {key: i + 1 for i, (key, _) in enumerate(shapes)}
    lines.append("  <Shapes>")
    for key, part in shapes:
        lines += shape_lines(part["mesh"], f'{variant["name"]}_{key}', ids[key])
    lines += ["  </Shapes>", "  <Scene>"]
    node = [1]
    mappings = []

    def nid():
        node[0] += 1
        return node[0]

    def shape(key, indent, path_, offset=None):
        part = parts[key]
        name = part.get("name", key)
        attrs = part.get("attrs", 'castsShadows="true" receiveShadows="true"')
        mappings.append((name, path_))
        move = f' translation="{fmt(offset)}"' if offset else ""
        lines.append(f'{indent}<Shape name="{name}" shapeId="{ids[key]}"{move} clipDistance="{xc.CLIP * 2}" nodeId="{nid()}" '
                     f'materialIds="{part["material"]}" {attrs}/>')

    # the scene: groups the constructible's states show and hide (mapped by name in the xml)
    groups = [
        ("site", ["stakes"]),
        ("mound", ["mound", "moundCol"]),
        ("logs", ["bark", "logEnds"]),
        # the lizard's group stands at its feet, so it tips over backwards there when it collapses
        ("lizard", ["lizard", "lizardCol"]),
        ("sign", ["boardPlanks", "boardFace", "eqSponsor_1"]),
        ("sellingStation", ["unloadTrigger", "palletTrigger", "woodTrigger", "woodActivationTrigger"]
         + (["baleTrigger"] if variant["bale"] else [])),
    ]
    lines.append(f'    <TransformGroup name="{variant["name"]}" nodeId="1">')
    for g, (group, keys) in enumerate(groups):
        mappings.append((group, f"0>{g}"))
        pivot = (0.0, lizard_base(), LIZARD["z"]) if group == "lizard" else None
        move = f' translation="{fmt(pivot)}"' if pivot else ""
        lines.append(f'      <TransformGroup name="{group}"{move} nodeId="{nid()}">')
        for c, key in enumerate(keys):
            shape(key, "        ", f"0>{g}|{c}", tuple(-v for v in pivot) if pivot else None)
        if group == "sellingStation":
            tz = TRIGGERS["z"]
            extra = [("unloadTriggerAINode", f"0 0 {tz:.5g}", "0 0 0"), ("unloadTriggerMarker", f"0 0 {tz:.5g}", None),
                     ("woodActivationTriggerMarker", f"{TRIGGERS['hx'] + 1.2:.5g} 0 {tz:.5g}", None)]
            for e, (name, translation, rotation) in enumerate(extra):
                mappings.append((name, f"0>{g}|{len(keys) + e}"))
                rot = f' rotation="{rotation}"' if rotation else ""
                lines.append(f'        <TransformGroup name="{name}" translation="{translation}"{rot} nodeId="{nid()}"/>')
        lines.append("      </TransformGroup>")
    g = len(groups)
    shape("infoTrigger", "      ", f"0>{g}")
    lines += ["    </TransformGroup>", "  </Scene>", "</i3D>"]
    with open(path, "w", encoding="iso-8859-1", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
    return mappings


def write_xml(variant, path, mappings):
    name = variant["name"]
    ft = variant["fillType"]
    bale = '\n            <baleTrigger triggerNode="baleTrigger" fillTypes="STRAW" deleteLitersPerSecond="10000"/>' if variant["bale"] else ""
    stone = "Stone" in name
    tip = variant["tip"]
    mapping_lines = "\n".join(f'        <i3dMapping id="{n}" node="{p}"/>' for n, p in mappings)
    text = f"""<?xml version="1.0" encoding="utf-8" standalone="no"?>
<!-- Made by art/source/lizard_plinth.py: change that and run it again rather than editing this. -->
<placeable type="constructible">
    <storeData>
        <name>$l10n_eq_shop_lizardPlinth</name>
        <functions>
            <function>$l10n_eq_shop_lizardPlinth_function</function>
            <function>$l10n_eq_shop_lizardPlinth_{ft.lower()}</function>
        </functions>
        <image>{OUT}/store_{name}.dds</image>
        <price>{PRICE}</price>
        <dailyUpkeep>0</dailyUpkeep>
        <lifetime>1000</lifetime>
        <rotation>0</rotation>
        <showInStore>false</showInStore>
        <brand>LIZARD</brand>
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
        <!-- Driven along x onto the log deck; the front, with the logo and the triggers, faces -z.
             The deck a machine counts on is in EqPlinths.AREAS. -->
    </placement>

    <triggerMarkers>
        <triggerMarker node="unloadTriggerMarker" filename="$data/shared/assets/marker/markerIconPallet.i3d" adjustToGround="true"/>
        <triggerMarker node="woodActivationTriggerMarker" filename="$data/shared/assets/marker/markerIconExclamationMark.i3d" adjustToGround="true"/>
    </triggerMarkers>

    <hotspots>
        <hotspot type="UNLOADING_PALLET" linkNode="unloadTriggerMarker" teleportNode="unloadTriggerMarker"/>
    </hotspots>

    <infoTrigger triggerNode="infoTrigger"/>

    <constructible>
        <stateMachine>
            <states>
                <state name="SETUP" class="ConstructibleStateBuilding">
                    <toggleMesh node="mound"  active="false" updatePhysics="true"/>
                    <toggleMesh node="logs"   active="false" updatePhysics="false"/>
                    <toggleMesh node="lizard" active="false" updatePhysics="true"/>
                    <toggleMesh node="sign"   active="false" updatePhysics="false"/>
                    <toggleHotspot index="1" isVisible="true"/>
                    <input fillType="{ft}" amount="{variant["amount"]}" usagePerHour="{variant["rate"]}"/>
                    <sounds>
                        <active template="constructibleActive"/>
                    </sounds>
                </state>

                <state name="BUILDING_1" class="ConstructibleStateBuilding">
                    <toggleMesh node="mound" active="true" updatePhysics="true"/>
                    <input fillType="WOOD" amount="{WOOD}" usagePerHour="2000"/>
                    <sounds>
                        <active template="constructibleActive"/>
                    </sounds>
                </state>

                <state name="BUILDING_2" class="ConstructibleStateBuilding">
                    <toggleMesh node="logs" active="true" updatePhysics="false"/>
                    <input fillType="PLANKS" amount="{PLANKS}" usagePerHour="1000"/>
                    <sounds>
                        <active template="constructibleActive"/>
                    </sounds>
                </state>

                <state name="FINALIZE" class="ConstructibleStateFinalize">
                    <toggleMesh node="lizard"         active="true"  updatePhysics="true"/>
                    <toggleMesh node="sign"           active="true"  updatePhysics="false"/>
                    <toggleMesh node="site"           active="false" updatePhysics="false"/>
                    <toggleMesh node="sellingStation" active="false" updatePhysics="true"/>
                    <toggleMesh node="infoTrigger"    active="false" updatePhysics="true"/>
                    <toggleHotspot index="1" isVisible="false"/>
                </state>

                <state name="DONE" class="ConstructibleState" isPreviewState="true"/>
            </states>

            <transitions>
                <transition from="SETUP"      to="BUILDING_1"/>
                <transition from="BUILDING_1" to="BUILDING_2"/>
                <transition from="BUILDING_2" to="FINALIZE"/>
                <transition from="FINALIZE"   to="DONE"/>
            </transitions>
        </stateMachine>

        <sellingStation appearsOnStats="false" supportsExtension="false">
            <unloadTrigger exactFillRootNode="unloadTrigger" aiNode="unloadTriggerAINode" fillTypes="{tip}"/>
            <palletTrigger triggerNode="palletTrigger" aiNode="unloadTriggerAINode" fillTypes="PLANKS{' STONE' if stone else ''}"/>
            <woodTrigger triggerNode="woodTrigger" aiNode="unloadTriggerAINode" activationTriggerNode="woodActivationTrigger" fillTypes="WOOD"/>{bale}
        </sellingStation>

        <storage isExtension="false" fillLevelSyncThreshold="50">
            <capacity fillType="{ft}" capacity="{int(variant["amount"] * 1.2)}"/>
            <capacity fillType="WOOD" capacity="{int(WOOD * 1.5)}"/>
            <capacity fillType="PLANKS" capacity="{int(PLANKS * 1.2)}"/>
        </storage>
    </constructible>

    <i3dMappings>
{mapping_lines}
    </i3dMappings>
</placeable>
"""
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)


def logotype(path=None):
    """The shop picture's stand-in for Lizard's logo (the real one is read in game): white
    letters on black."""
    img = Image.new("RGB", (512, 160), (8, 8, 8))
    draw = ImageDraw.Draw(img)
    font = ImageFont.truetype(xc.FONT, 120)
    box = draw.textbbox((0, 0), "LIZARD", font=font)
    draw.text(((512 - (box[2] - box[0])) / 2 - box[0], (160 - (box[3] - box[1])) / 2 - box[1]), "LIZARD", font=font, fill=(250, 250, 250))
    return np.asarray(img, dtype=float)


def noise_texture(rgb, seed, size=256):
    rng = np.random.default_rng(seed)
    base = np.array(rgb, dtype=float)
    n = xc.periodic_noise(size, rng, 30, 30) * 0.5 + xc.periodic_noise(size, rng, 90, 90) * 0.5
    img = base[None, None, :] * (0.85 + 0.3 * n[..., None])
    return np.clip(img, 0, 255)


def build(variant):
    base_y = lizard_base()
    barks, ends = logs()
    planks, face, logos = board()
    tz, thx, thz = TRIGGERS["z"], TRIGGERS["hx"], TRIGGERS["hz"]
    trigger = 'kinematic="true" compound="true" trigger="true" collisionFilterGroup="0x20000000" castsShadows="false" receiveShadows="false" nonRenderable="true"'
    parts = {
        "stakes": {"mesh": stakes(), "material": 4},
        "mound": {"mesh": mound(), "material": 1, "name": "moundSurface"},
        "moundCol": {"mesh": mound(collision=True), "material": 7, "name": "collision",
                     "attrs": f'static="true" collisionFilterGroup="{COLLISION_GROUP}" collisionFilterMask="{COLLISION_MASK}" density="0.01" nonRenderable="true"'},
        "bark": {"mesh": barks, "material": 2, "name": "logBark"},
        "logEnds": {"mesh": ends, "material": 3},
        "lizard": {"mesh": lizard(base_y), "material": 4, "name": "planks"},
        "boardPlanks": {"mesh": planks, "material": 4},
        "boardFace": {"mesh": face, "material": 5},
        "eqSponsor_1": {"mesh": logos["eqSponsor_1"], "material": 6, "attrs": 'castsShadows="false" receiveShadows="true"'},
        "lizardCol": {"mesh": box_mesh(0.0, base_y + 0.9, LIZARD["z"] + 0.04, 0.75, 0.95, 0.08), "material": 7, "name": "lizardCollision",
                      "attrs": f'static="true" collisionFilterGroup="{COLLISION_GROUP}" collisionFilterMask="{COLLISION_MASK}" density="0.01" nonRenderable="true"'},
        "unloadTrigger": {"mesh": box_mesh(0.0, 0.0, tz, thx, 0.15, thz), "material": 7,
                          "attrs": 'kinematic="true" trigger="true" collisionFilterGroup="0x40000000" collisionFilterMask="0x20000000" castsShadows="false" receiveShadows="false" nonRenderable="true"'},
        "palletTrigger": {"mesh": box_mesh(0.0, 1.6, tz, thx, 1.6, thz), "material": 7,
                          "attrs": trigger + ' collisionFilterMask="0x10000"'},
        "woodTrigger": {"mesh": box_mesh(0.0, 1.2, tz, thx, 1.2, thz), "material": 7,
                        "attrs": trigger + ' collisionFilterMask="0x800"'},
        "woodActivationTrigger": {"mesh": box_mesh(thx + 1.2, 1.0, tz, 1.0, 1.0, 1.0), "material": 7,
                                  "attrs": trigger + ' collisionFilterMask="0x100000"'},
        "baleTrigger": {"mesh": box_mesh(0.0, 1.6, tz, thx, 1.6, thz), "material": 7,
                        "attrs": trigger + ' collisionFilterMask="0x40000"'},
        "infoTrigger": {"mesh": box_mesh(0.0, 1.5, -1.5, 6.0, 2.0, 7.5), "material": 7,
                        "attrs": 'static="true" trigger="true" collisionFilterGroup="0x20000000" collisionFilterMask="0x100000" castsShadows="false" receiveShadows="false" nonRenderable="true"'},
    }
    return parts


def main():
    read_amounts()
    preview_dir = os.environ.get("XC_PREVIEW_DIR", "art/previews")
    planks_rgb = np.asarray(Image.open("placeables/xcJumps/xcPlanks_diffuse.dds").convert("RGB"), dtype=float)
    bark_rgb = np.asarray(Image.open("placeables/xcJumps/xcBarkA_diffuse.dds").convert("RGB"), dtype=float)
    ends_rgb = np.asarray(Image.open("placeables/xcJumps/xcLogEnd_diffuse.dds").convert("RGB"), dtype=float)
    for variant in VARIANTS:
        parts = build(variant)
        mappings = write_i3d(variant, os.path.join(OUT, variant["name"] + ".i3d"), parts)
        write_xml(variant, os.path.join(OUT, variant["name"] + ".xml"), mappings)

        def flip(mesh):
            out = Mesh()
            out.verts = [(p, n, (uv[0], 1 - uv[1])) for p, n, uv in mesh.verts]
            out.tris = list(mesh.tris)
            return out
        meshes = [(parts["mound"]["mesh"], noise_texture(variant["preview"], 4)), (parts["bark"]["mesh"], bark_rgb),
                  (parts["logEnds"]["mesh"], ends_rgb), (parts["lizard"]["mesh"], planks_rgb),
                  (parts["boardPlanks"]["mesh"], planks_rgb), (parts["boardFace"]["mesh"], xc_flat((8, 8, 8))),
                  (flip(parts["eqSponsor_1"]["mesh"]), logotype())]
        store_image([m for m in meshes if m[0].tris], os.path.join(OUT, "store_" + variant["name"] + ".dds"), preview_dir, yaw=-145)
        print(variant["name"], len(parts["mound"]["mesh"].tris), "mound triangles,",
              len(parts["lizard"]["mesh"].tris) // 12, "planks")


def xc_flat(rgb):
    return np.full((4, 4, 3), rgb, dtype=float)


if __name__ == "__main__":
    main()
