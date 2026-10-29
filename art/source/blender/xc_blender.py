"""
Builds the corners and roll tops in Blender (James, 2026-10-29), one collection per jump, and
exports each to an OBJ that art/source/xc_import.py turns into the game's i3d, xml and shop image.

Run inside Blender (Scripting tab, or the MCP add-on): it clears and rebuilds only its own
collections, so anything else in the scene is left alone. Set TEX and OUT first.

Axes here are Blender's: X is the jump's length (the red flag's end is +X), Y is the way the horse
goes (it comes from -Y), Z is up. The OBJ export (forward -Z, up Y) turns that into the game's
x, y, z with the horse coming from +z, red flag on its right: like the log piles.

Part of Realistic Equestrian by Jasta007.
"""

import math
import os
import random

import bpy

TEX = r"C:\Users\User\Documents\RealisticEquestrian\xcJumps\textures"
OUT = r"C:\Users\User\Documents\RealisticEquestrian\xcJumps\obj"
SPACING = 6.0           # jumps stand this far apart along X in the scene, for looking at

BOARD = (2.0, 1.6)      # metres one plank texture covers: along the grain (u), across the 8 boards (v)
ROUND_V = 1.5           # metres of round wood one peeled/dark texture covers along it

CORNER_LENGTH = 4.4     # along X, apex at +X
CORNER_TIP = 0.2        # half the width of the cut-off apex
CORNER_TIP_X = 0.5      # where the apex is: the flags bracket only the narrow end (James: take it
                        # at the narrow end or get into trouble), the wide end runs on past the white flag
CORNER_HALF_ANGLE = 30  # degrees each arm turns away from the flag line (a 60 degree corner)
FLAG_GAP = 0.45         # flags stand this far past the ends

JUMPS = [
    {"name": "xcCornerPlank", "kind": "cornerPlank", "height": 1.10},
    {"name": "xcCornerLog", "kind": "cornerLog", "height": 1.15},
    {"name": "xcRollTopQuarter", "kind": "rollQuarter", "height": 1.00, "length": 3.4},
    {"name": "xcRollTopHalf", "kind": "rollHalf", "height": 0.95, "length": 3.2},
    {"name": "xcTable", "kind": "table", "height": 1.15, "length": 3.6, "depth": 2.2},
    {"name": "xcBigLog", "kind": "bigLog", "height": 1.15, "length": 5.6},
]


# ---------------------------------------------------------------------------------------------
# Building meshes

class Part:
    """Faces for one object: each face a list of (position, uv) corners. A face given a point
    inside the solid it bounds is turned to face away from it."""

    def __init__(self, material, smooth=False):
        self.material = material
        self.smooth = smooth
        self.faces = []

    def face(self, corners, inside=None):
        if inside is not None:
            n = [0.0, 0.0, 0.0]
            for k in range(len(corners)):
                a, b = corners[k][0], corners[(k + 1) % len(corners)][0]
                n[0] += (a[1] - b[1]) * (a[2] + b[2])
                n[1] += (a[2] - b[2]) * (a[0] + b[0])
                n[2] += (a[0] - b[0]) * (a[1] + b[1])
            mid = [sum(c[0][i] for c in corners) / len(corners) for i in range(3)]
            if sum(n[i] * (mid[i] - inside[i]) for i in range(3)) < 0:
                corners = corners[::-1]
        self.faces.append(corners)


def material(name):
    found = bpy.data.materials.get(name)
    if found is not None:
        return found
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    bsdf = nodes.get("Principled BSDF")
    image = nodes.new("ShaderNodeTexImage")
    image.image = bpy.data.images.load(os.path.join(TEX, name + ".png"), check_existing=True)
    mat.node_tree.links.new(image.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.85
    return mat


def make_object(name, part, collection, parent):
    verts, faces, uvs, index = [], [], [], {}
    for corners in part.faces:
        ids = []
        for p, uv in corners:
            key = tuple(round(c, 6) for c in p)
            if key not in index:
                index[key] = len(verts)
                verts.append(p)
            ids.append(index[key])
            uvs.append(uv)
        faces.append(ids)
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    layer = mesh.uv_layers.new(name="UVMap")
    for loop, uv in zip(layer.data, uvs):
        loop.uv = uv
    mesh.polygons.foreach_set("use_smooth", [part.smooth] * len(mesh.polygons))
    if part.material is not None:
        mesh.materials.append(material(part.material))
    mesh.validate()
    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    obj.parent = parent
    return obj


def offset(poly, d):
    """A convex counter-clockwise polygon moved d outwards (negative: inwards)."""
    n = len(poly)
    lines = []
    for i in range(n):
        (x0, y0), (x1, y1) = poly[i], poly[(i + 1) % n]
        length = math.hypot(x1 - x0, y1 - y0)
        nx, ny = (y1 - y0) / length, -(x1 - x0) / length
        lines.append(((x0 + nx * d, y0 + ny * d), (x1 - x0, y1 - y0)))
    out = []
    for i in range(n):
        (p, r), (q, s) = lines[i - 1], lines[i]
        cross = r[0] * s[1] - r[1] * s[0]
        t = ((q[0] - p[0]) * s[1] - (q[1] - p[1]) * s[0]) / cross
        out.append((p[0] + r[0] * t, p[1] + r[1] * t))
    return out


def walls(part, bottom, top, z0, z1, boards=True, edges=None, inside=None):
    """Side faces between a bottom outline at z0 and a top one at z1 (same corner count), facing
    away from inside (default: the middle of the outline). Boards run up the wall (the grain
    along u), v counts metres along the outline."""
    n = len(top)
    if inside is None:
        inside = (sum(p[0] for p in top) / n, sum(p[1] for p in top) / n, (z0 + z1) / 2)
    along = 0.0
    for i in range(n):
        j = (i + 1) % n
        if edges is not None and i not in edges:
            continue
        length = math.hypot(top[j][0] - top[i][0], top[j][1] - top[i][1])
        dx, dy = (top[j][0] - top[i][0]) / length, (top[j][1] - top[i][1]) / length

        def uv(q, z):
            # metres along the wall measured straight along its top edge, so the board lines stay
            # straight on a leaning wall; boards: grain up the wall, else boards lie along it
            v = (along + (q[0] - top[i][0]) * dx + (q[1] - top[i][1]) * dy) / BOARD[1]
            u = z / BOARD[0]
            return (u, v) if boards else (v * BOARD[1] / BOARD[0], u * BOARD[0] / BOARD[1])
        part.face([((*bottom[i], z0), uv(bottom[i], z0)), ((*bottom[j], z0), uv(bottom[j], z0)),
                   ((*top[j], z1), uv(top[j], z1)), ((*top[i], z1), uv(top[i], z1))], inside)
        along += length


def cap(part, poly, z, down=False):
    """A flat face over a polygon; boards across X (grain along Y)."""
    corners = [((x, y, z), (y / BOARD[0], x / BOARD[1])) for x, y in poly]
    middle = (sum(p[0] for p in poly) / len(poly), sum(p[1] for p in poly) / len(poly))
    part.face(corners, (middle[0], middle[1], z + (1 if down else -1)))


def disc(part, centre, axis, radius, a0, a1, steps, flip=False, uv_scale=0.45):
    """A flat (part) disc facing +X (flip: -X), from angle a0 to a1 round the centre in the YZ
    plane; uv laid like a log end."""
    cx, cy, cz = centre
    rim = []
    for k in range(steps + 1):
        a = a0 + (a1 - a0) * k / steps
        rim.append(((cx, cy + math.cos(a) * radius, cz + math.sin(a) * radius),
                    (0.5 + uv_scale * math.cos(a), 0.5 + uv_scale * math.sin(a))))
    middle = (centre, (0.5, 0.5))
    for k in range(steps):
        part.face([middle, rim[k], rim[k + 1]], (cx + (1 if flip else -1), cy, cz))


def log_x(part, ends, x0, x1, y, z, r, sides=16, half=False, seed=0, end_cap=True):
    """A round log along X from x0 to x1 centred at (y, z); half: only the top half (flat side down).
    Bark-free peeled wood: u round it, v along it. Its ends go in the ends part."""
    rng = random.Random(seed)
    spin = rng.uniform(0, 1)
    a0, a1 = (0.0, math.pi) if half else (0.0, 2 * math.pi)
    angles = [a0 + (a1 - a0) * k / sides for k in range(sides + 1)]
    ring = [(math.cos(a), math.sin(a)) for a in angles]
    for k in range(sides):
        (c0, s0), (c1, s1) = ring[k], ring[k + 1]
        u0, u1 = spin + k / sides * 0.5, spin + (k + 1) / sides * 0.5
        part.face([((x0, y + c0 * r, z + s0 * r), (u0, x0 / ROUND_V)), ((x0, y + c1 * r, z + s1 * r), (u1, x0 / ROUND_V)),
                   ((x1, y + c1 * r, z + s1 * r), (u1, x1 / ROUND_V)), ((x1, y + c0 * r, z + s0 * r), (u0, x1 / ROUND_V))],
                  ((x0 + x1) / 2, y, z))
    if end_cap and ends is not None:
        disc(ends, (x1, y, z), "x", r, a0, a1, sides)
        disc(ends, (x0, y, z), "x", r, a0, a1, sides, flip=True)


def half_log_up(part, ends, base, top, out, r, sides=8, rng=None):
    """A half round log standing up from base to top (x, y, z), its round side facing out (a unit
    vector in XY). The flat back is left open (it backs onto a wall); the top gets a half end.
    rng: each log's grain shifted, stretched and twisted its own way."""
    rng = rng or random.Random(0)
    u_off, v_off = rng.uniform(0, 1), rng.uniform(0, 1)
    u_scale, v_scale, twist = rng.uniform(0.35, 0.7), rng.uniform(0.7, 1.4), rng.uniform(-0.12, 0.12)
    side = (-out[1], out[0])
    ang = [-math.pi / 2 + math.pi * k / sides for k in range(sides + 1)]
    pts = [(out[0] * math.cos(a) + side[0] * math.sin(a), out[1] * math.cos(a) + side[1] * math.sin(a)) for a in ang]
    length = top[2] - base[2]
    for k in range(sides):
        (dx0, dy0), (dx1, dy1) = pts[k], pts[k + 1]
        u0, u1 = u_off + k / sides * u_scale, u_off + (k + 1) / sides * u_scale
        v1 = v_off + length * v_scale / ROUND_V
        part.face([((base[0] + dx0 * r, base[1] + dy0 * r, base[2]), (u0, v_off)),
                   ((base[0] + dx1 * r, base[1] + dy1 * r, base[2]), (u1, v_off)),
                   ((top[0] + dx1 * r, top[1] + dy1 * r, top[2]), (u1 + twist, v1)),
                   ((top[0] + dx0 * r, top[1] + dy0 * r, top[2]), (u0 + twist, v1))],
                  ((base[0] + top[0]) / 2, (base[1] + top[1]) / 2, (base[2] + top[2]) / 2))
    middle = (top, (0.5, 0.5))
    for k in range(sides):
        (dx0, dy0), (dx1, dy1) = pts[k], pts[k + 1]
        ends.face([middle, ((top[0] + dx0 * r, top[1] + dy0 * r, top[2]), (0.5 + 0.45 * dx0, 0.5 + 0.45 * dy0)),
                   ((top[0] + dx1 * r, top[1] + dy1 * r, top[2]), (0.5 + 0.45 * dx1, 0.5 + 0.45 * dy1))],
                  (top[0], top[1], top[2] - 1))


def log_between(part, ends, a, b, r, sides=14, seed=0):
    """A round log from a to b (both on the same height), capped at both ends."""
    dx, dy = b[0] - a[0], b[1] - a[1]
    length = math.hypot(dx, dy)
    ax, ay = dx / length, dy / length
    sx, sy = -ay, ax
    spin = random.Random(seed).uniform(0, 1)
    angles = [2 * math.pi * k / sides for k in range(sides + 1)]

    def at(p, a):
        return (p[0] + sx * math.cos(a) * r, p[1] + sy * math.cos(a) * r, p[2] + math.sin(a) * r)
    for k in range(sides):
        u0, u1 = spin + k / sides * 0.5, spin + (k + 1) / sides * 0.5
        part.face([(at(a, angles[k]), (u0, 0)), (at(b, angles[k]), (u0, length / ROUND_V)),
                   (at(b, angles[k + 1]), (u1, length / ROUND_V)), (at(a, angles[k + 1]), (u1, 0))],
                  tuple((a[i] + b[i]) / 2 for i in range(3)))
    for p, other in ((a, b), (b, a)):
        rim = [(at(p, angles[k]), (0.5 + 0.45 * math.cos(angles[k]), 0.5 + 0.45 * math.sin(angles[k]))) for k in range(sides + 1)]
        for k in range(sides):
            ends.face([(p, (0.5, 0.5)), rim[k], rim[k + 1]], other)


def prism(part, poly, z0, z1):
    """A closed box over a convex polygon (for collision)."""
    walls(part, poly, poly, z0, z1)
    cap(part, poly, z1)
    cap(part, poly, z0, down=True)


def profile_prism(part, profile, x0, x1):
    """A closed solid along X from a convex (y, z) profile, counter-clockwise seen from +X."""
    n = len(profile)
    cy, cz = sum(p[0] for p in profile) / n, sum(p[1] for p in profile) / n
    for i in range(n):
        (y0, z0), (y1, z1) = profile[i], profile[(i + 1) % n]
        part.face([((x0, y0, z0), (0, 0)), ((x0, y1, z1), (0, 0)), ((x1, y1, z1), (0, 0)), ((x1, y0, z0), (0, 0))],
                  ((x0 + x1) / 2, cy, cz))
    for x, other in ((x1, x0), (x0, x1)):
        part.face([((x, y, z), (0, 0)) for y, z in profile], (other, cy, cz))


# ---------------------------------------------------------------------------------------------
# The jumps

def corner_outline():
    """The corner seen from above: apex (cut off) at CORNER_TIP_X, the arms opening towards -X."""
    far = CORNER_TIP_X - CORNER_LENGTH
    wide = CORNER_TIP + CORNER_LENGTH * math.tan(math.radians(CORNER_HALF_ANGLE))
    return [(CORNER_TIP_X, -CORNER_TIP), (CORNER_TIP_X, CORNER_TIP), (far, wide), (far, -wide)]


def corner_plank(jump):
    """Weathered vertical boards leaning out a little at the foot, under a brown stained deck
    whose deep edge board overhangs all round (James's photo DSCN1649)."""
    h = jump["height"]
    outline = corner_outline()
    boards, deck = Part("xcPlanks"), Part("xcStain")
    trim = 0.16
    walls(boards, offset(outline, 0.08), outline, -0.05, h - trim)
    lid = offset(outline, 0.04)
    walls(deck, lid, lid, h - trim, h, boards=False)
    cap(deck, lid, h)
    cap(deck, lid, h - trim, down=True)
    col = Part(None)
    prism(col, offset(outline, 0.08), 0.0, h)
    return {"boards": boards, "deck": deck}, col, CORNER_TIP_X + FLAG_GAP


def corner_log(jump):
    """Half round peeled logs standing side by side round the box, leaning in a little at the top,
    a round log capping each side and the wide end, a plank deck inside (photo 284751502)."""
    h = jump["height"]
    rng = random.Random(5)
    outline = corner_outline()
    logs, ends, deck = Part("xcPeeled", smooth=True), Part("xcLogEnd"), Part("xcPlanks")
    logs_b = Part("xcPeeledB", smooth=True)   # every other log or so: greyer, more streaked wood
    r = 0.085
    foot = offset(outline, 0.07)
    n = len(outline)
    for i in range(n):
        j = (i + 1) % n
        (x0, y0), (x1, y1) = outline[i], outline[j]
        (fx0, fy0), (fx1, fy1) = foot[i], foot[j]
        length = math.hypot(x1 - x0, y1 - y0)
        out = ((y1 - y0) / length, -(x1 - x0) / length)
        count = max(2, int(length / (2 * r)))
        for k in range(count):
            t = (k + 0.5) / count
            top_h = h - 0.10 + rng.uniform(-0.03, 0.03)
            base = (fx0 + (fx1 - fx0) * t, fy0 + (fy1 - fy0) * t, -0.05)
            top = (x0 + (x1 - x0) * t, y0 + (y1 - y0) * t, top_h)
            half_log_up(logs_b if rng.random() < 0.45 else logs, ends, base, top, out, r * rng.uniform(0.92, 1.05), rng=rng)
    inner = offset(outline, -0.01)
    walls(deck, offset(foot, -0.01), inner, -0.05, h - 0.12)
    cap(deck, inner, h - 0.12)
    # round logs along both arms and across the wide end, resting on the half logs
    rail = 0.085
    a, b, c, d = offset(outline, 0.0)
    for p, q, seed in ((b, c, 1), (d, a, 2), (c, d, 3)):
        log_between(logs, ends, (p[0], p[1], h - 0.12 + rail), (q[0], q[1], h - 0.12 + rail), rail, seed=seed)
    col = Part(None)
    prism(col, offset(outline, 0.1), 0.0, h)
    return {"logs": logs, "logsB": logs_b, "ends": ends, "deck": deck}, col, CORNER_TIP_X + FLAG_GAP


def roll_logs(jump, centre_y, a0, a1, r, material, rng):
    """Logs side by side round an arc of radius height - r about (centre_y, 0), from angle a0 to
    a1 (0 = towards -Y, the horse)."""
    h, length = jump["height"], jump["length"]
    logs, ends = Part(material, smooth=True), Part("xcLogEnd" if material == "xcPeeled" else material)
    rc = h - r
    first = math.asin(r / rc)
    start = max(a0, first)
    stop = min(a1, math.pi - first)
    step = 2 * math.asin(r / rc)
    count = int((stop - start) / step) + 1
    for k in range(count):
        a = start + (stop - start) * k / max(1, count - 1)
        y = centre_y - rc * math.cos(a)
        z = rc * math.sin(a)
        rr = r * rng.uniform(0.94, 1.04)
        x0 = -length / 2 + rng.uniform(-0.03, 0.03)
        x1 = length / 2 + rng.uniform(-0.03, 0.03)
        log_x(logs, ends, x0, x1, y, z, rr, seed=rng.randrange(1 << 20))
    return logs, ends, rc


def roll_quarter(jump):
    """Peeled logs round a quarter circle, the curve towards the horse, a vertical boarded back
    and plank frames at both ends (James's photo)."""
    h, length = jump["height"], jump["length"]
    rng = random.Random(9)
    r = 0.07
    cy = h / 2
    logs, ends, rc = roll_logs(jump, cy, 0.0, math.pi / 2, r, "xcPeeled", rng)
    frames = Part("xcPlanks")
    back_y = cy + r * 0.6
    # the boarded back: one solid 4 cm wall, ends and top closed
    hx = length / 2 - 0.1
    back = [(hx, back_y), (hx, back_y + 0.04), (-hx, back_y + 0.04), (-hx, back_y)]
    walls(frames, back, back, 0.0, h - r)
    cap(frames, back, h - r)
    steps = 10
    for x, flip in ((length / 2 - 0.25, False), (-length / 2 + 0.25, True)):
        outline = [(cy - (rc - r * 0.3) * math.cos(math.pi / 2 * k / steps), (rc - r * 0.3) * math.sin(math.pi / 2 * k / steps))
                   for k in range(steps + 1)] + [(back_y, h - r), (back_y, 0.0)]
        dx = 0.05 if flip else -0.05
        middle = (sum(p[0] for p in outline) / len(outline), sum(p[1] for p in outline) / len(outline))
        for d in (0.0, dx):
            corners = [((x + d, y, z), (z / BOARD[0], y / BOARD[1])) for y, z in outline]
            frames.face(corners, (x + dx / 2, middle[0], middle[1]))
    col = Part(None)
    profile = [(cy - h * math.cos(math.pi / 2 * k / 8), h * math.sin(math.pi / 2 * k / 8)) for k in range(9)] + [(back_y + 0.04, h), (back_y + 0.04, 0.0)]
    profile_prism(col, list(reversed(profile)), -length / 2, length / 2)
    return {"logs": logs, "ends": ends, "frames": frames}, col, length / 2 + 0.3


def roll_half(jump):
    """A drum of dark logs round a half circle, closed by dark half discs set just inside the log
    ends (James's photo)."""
    h, length = jump["height"], jump["length"]
    rng = random.Random(13)
    r = 0.065
    logs, ends, rc = roll_logs(jump, 0.0, 0.0, math.pi, r, "xcDark", rng)
    panels = Part("xcDark")
    for x, flip in ((length / 2 - 0.06, False), (-length / 2 + 0.06, True)):
        # the outer face looks out along X, the inner one back into the drum
        disc(panels, (x, 0.0, 0.0), "x", rc, 0.0, math.pi, 16, flip=flip, uv_scale=0.5)
        disc(panels, (x - 0.04 if not flip else x + 0.04, 0.0, 0.0), "x", rc, 0.0, math.pi, 16, flip=not flip, uv_scale=0.5)
    col = Part(None)
    profile = [(-h * math.cos(math.pi * k / 12), h * math.sin(math.pi * k / 12)) for k in range(13)]
    profile_prism(col, list(reversed(profile)), -length / 2, length / 2)
    return {"logs": logs, "ends": ends, "panels": panels}, col, length / 2 + 0.3


def post(part, ends, x, y, z0, z1, r, sides=14, seed=0):
    """A round post standing from z0 to z1 with a sawn top (in ends)."""
    spin = random.Random(seed).uniform(0, 1)
    angles = [2 * math.pi * k / sides for k in range(sides + 1)]
    for k in range(sides):
        a0, a1 = angles[k], angles[k + 1]
        u0, u1 = spin + k / sides * 0.5, spin + (k + 1) / sides * 0.5
        part.face([((x + math.cos(a0) * r, y + math.sin(a0) * r, z0), (u0, z0 / ROUND_V)),
                   ((x + math.cos(a1) * r, y + math.sin(a1) * r, z0), (u1, z0 / ROUND_V)),
                   ((x + math.cos(a1) * r, y + math.sin(a1) * r, z1), (u1, z1 / ROUND_V)),
                   ((x + math.cos(a0) * r, y + math.sin(a0) * r, z1), (u0, z1 / ROUND_V))], (x, y, (z0 + z1) / 2))
    rim = [((x + math.cos(a) * r, y + math.sin(a) * r, z1), (0.5 + 0.45 * math.cos(a), 0.5 + 0.45 * math.sin(a))) for a in angles]
    for k in range(sides):
        ends.face([((x, y, z1), (0.5, 0.5)), rim[k], rim[k + 1]], (x, y, z1 - 1))


def table(jump):
    """A boarded box with a stained deck overhanging all round, round posts at the corners
    standing a little proud and a sponsor board on the face (James's photo; the board's logo is
    a brand from the game, put on by EqSponsors like the bleachers' boards)."""
    h, length, depth = jump["height"], jump["length"], jump["depth"]
    hx, hy = length / 2, depth / 2
    trim = 0.12
    outline = [(hx, -hy), (hx, hy), (-hx, hy), (-hx, -hy)]
    boards, deck = Part("xcPlanks"), Part("xcStain")
    posts, ends = Part("xcPeeled", smooth=True), Part("xcLogEnd")
    walls(boards, outline, outline, -0.05, h - trim, boards=False)
    lid = offset(outline, 0.06)
    walls(deck, lid, lid, h - trim, h, boards=False)
    cap(deck, lid, h)
    cap(deck, lid, h - trim, down=True)
    r = 0.12
    for i, (x, y) in enumerate(outline):
        post(posts, ends, x + (r * 0.4 if x > 0 else -r * 0.4), y + (r * 0.4 if y > 0 else -r * 0.4), -0.05, h + 0.06, r, seed=i)
    # the sponsor board: a stained backing a little proud of the face, the logo panel on it
    bw, bh, bz = 2.1, 0.81, 0.18
    board = [(bw / 2, -hy - 0.04), (bw / 2, -hy), (-bw / 2, -hy), (-bw / 2, -hy - 0.04)]
    walls(deck, board, board, bz, bz + bh, boards=False)
    cap(deck, board, bz + bh)
    sponsor = Part("eqSponsor1")
    lw, lh, ly = 2.0, 0.75, -hy - 0.042
    lz = bz + (bh - lh) / 2
    sponsor.face([((-lw / 2, ly, lz), (0, 0)), ((lw / 2, ly, lz), (1, 0)), ((lw / 2, ly, lz + lh), (1, 1)), ((-lw / 2, ly, lz + lh), (0, 1))],
                 (0.0, 0.0, lz + lh / 2))
    col = Part(None)
    prism(col, offset(outline, 0.12), 0.0, h)
    return {"boards": boards, "deck": deck, "posts": posts, "ends": ends, "eqSponsor_1": sponsor}, col, hx + 0.45


def big_log(jump):
    """One big peeled trunk lying on the ground: lumpy, tapering, slightly bowed, with sawn ends
    (James's photos)."""
    h, length = jump["height"], jump["length"]
    rng = random.Random(21)
    sink = 0.08
    r0 = (h + sink) / 2
    logs, ends = Part("xcBigLog", smooth=True), Part("xcLogEnd")
    sides, rings = 28, 16
    waves = [(rng.choice([2, 3, 5]), rng.uniform(0, 6.3), rng.uniform(-2, 2), rng.uniform(0.02, 0.05)) for _ in range(4)]
    swell = [(rng.uniform(0.1, 0.9), rng.uniform(0, 6.3), rng.uniform(0.04, 0.09)) for _ in range(4)]

    def radius(a, t):
        rr = r0 * (1.04 - 0.10 * t)
        rr *= 1 + sum(amp * math.sin(k * a + ph + dr * t) for k, ph, dr, amp in waves)
        for st, sa, size in swell:
            da = (a - sa + math.pi) % (2 * math.pi) - math.pi
            rr += r0 * size * math.exp(-(da / 0.5) ** 2 - ((t - st) * length / 0.4) ** 2)
        return rr

    def centre(t):
        return 0.03 * math.sin(math.pi * t), r0 - sink + 0.02 * math.sin(math.pi * t)
    grid = []
    for i in range(rings + 1):
        t = i / rings
        x = -length / 2 + length * t
        cy, cz = centre(t)
        grid.append([(x, cy + math.cos(2 * math.pi * k / sides) * radius(2 * math.pi * k / sides, t),
                      cz + math.sin(2 * math.pi * k / sides) * radius(2 * math.pi * k / sides, t)) for k in range(sides + 1)])
    for i in range(rings):
        for k in range(sides):
            # its own texture once round and once along: u = 0.25 on top, 0.75 underneath
            u0, u1 = k / sides, (k + 1) / sides
            v0, v1 = i / rings, (i + 1) / rings
            cy, cz = centre((i + 0.5) / rings)
            logs.face([(grid[i][k], (u0, v0)), (grid[i][k + 1], (u1, v0)), (grid[i + 1][k + 1], (u1, v1)), (grid[i + 1][k], (u0, v1))],
                      ((grid[i][0][0] + grid[i + 1][0][0]) / 2, cy, cz))
    for i, flip in ((rings, False), (0, True)):
        cy, cz = centre(i / rings)
        x = grid[i][0][0]
        rim = [(grid[i][k], (0.5 + 0.47 * math.cos(2 * math.pi * k / sides), 0.5 + 0.47 * math.sin(2 * math.pi * k / sides))) for k in range(sides + 1)]
        for k in range(sides):
            ends.face([((x, cy, cz), (0.5, 0.5)), rim[k], rim[k + 1]], (x + (1 if flip else -1), cy, cz))
    # two sawn-off branches, both leaning towards the far end like the tree grew
    grow = r0 / 0.465   # the stubs were sized on a 0.85 m log
    for t, a, br, bl in ((0.63, math.radians(55), 0.075 * grow, 0.16 * grow), (0.27, math.radians(-25), 0.05 * grow, 0.10 * grow)):
        cy, cz = centre(t)
        rr = radius(a, t) * 0.92
        out = (0.0, math.cos(a), math.sin(a))
        base = (-length / 2 + length * t, cy + out[1] * rr, cz + out[2] * rr)
        axis = (0.35, out[1], out[2])
        n = math.sqrt(sum(c * c for c in axis))
        axis = tuple(c / n for c in axis)
        tip = tuple(base[i] + axis[i] * bl for i in range(3))
        branch(logs, ends, base, tip, br, t, a / (2 * math.pi) % 1.0)
    col = Part(None)
    profile = []
    for k in range(12):
        a = 2 * math.pi * k / 12
        profile.append((math.cos(a) * r0 * 0.98, max(0.0, r0 - sink + math.sin(a) * r0 * 0.98)))
    clean = []
    for p in profile:
        if not clean or abs(p[0] - clean[-1][0]) > 1e-4 or abs(p[1] - clean[-1][1]) > 1e-4:
            clean.append(p)
    profile_prism(col, list(reversed(clean)), -length / 2 + 0.1, length / 2 - 0.1)
    return {"log": logs, "ends": ends}, col, length / 2 + 0.3


def branch(part, ends, base, tip, r, v, u, sides=10):
    """A sawn-off branch stub from base (inside the trunk) to tip, a little thicker at its foot,
    in the big log's texture near (u, v); its sawn end in ends."""
    axis = tuple(tip[i] - base[i] for i in range(3))
    length = math.sqrt(sum(c * c for c in axis))
    axis = tuple(c / length for c in axis)
    side = (axis[1] * 0 - axis[2] * 1, axis[2] * 0 - axis[0] * 0, axis[0] * 1 - axis[1] * 0)
    n = math.sqrt(sum(c * c for c in side)) or 1.0
    side = tuple(c / n for c in side)
    up = (axis[1] * side[2] - axis[2] * side[1], axis[2] * side[0] - axis[0] * side[2], axis[0] * side[1] - axis[1] * side[0])

    def ring(p, rad, k):
        a = 2 * math.pi * k / sides
        return tuple(p[i] + (side[i] * math.cos(a) + up[i] * math.sin(a)) * rad for i in range(3))
    middle = tuple((base[i] + tip[i]) / 2 for i in range(3))
    for k in range(sides):
        corners = [(ring(base, r * 1.3, k), (u + k * 0.004, v)), (ring(base, r * 1.3, k + 1), (u + (k + 1) * 0.004, v)),
                   (ring(tip, r, k + 1), (u + (k + 1) * 0.004, v + 0.03)), (ring(tip, r, k), (u + k * 0.004, v + 0.03))]
        part.face(corners, middle)
    rim = [(ring(tip, r, k), (0.5 + 0.45 * math.cos(2 * math.pi * k / sides), 0.5 + 0.45 * math.sin(2 * math.pi * k / sides)))
           for k in range(sides + 1)]
    for k in range(sides):
        ends.face([(tip, (0.5, 0.5)), rim[k], rim[k + 1]], base)


BUILDERS = {"cornerPlank": corner_plank, "cornerLog": corner_log, "rollQuarter": roll_quarter, "rollHalf": roll_half,
            "table": table, "bigLog": big_log}


# ---------------------------------------------------------------------------------------------
# Scene and export

def collection_for(name):
    root = bpy.context.scene.collection
    found = bpy.data.collections.get(name)
    if found is not None:
        for obj in list(found.objects):
            data = obj.data
            bpy.data.objects.remove(obj)
            if data is not None and data.users == 0:
                bpy.data.meshes.remove(data)
    else:
        found = bpy.data.collections.new(name)
        root.children.link(found)
    return found


def flag_marker(name, x, collection, parent):
    empty = bpy.data.objects.new(name, None)
    empty.empty_display_type = "SINGLE_ARROW"
    empty.empty_display_size = 1.6
    empty.location = (x, 0.0, 0.0)
    collection.objects.link(empty)
    empty.parent = parent
    return empty


def build(index, jump):
    parts, col, flag_x = BUILDERS[jump["kind"]](jump)
    coll = collection_for(jump["name"])
    root = bpy.data.objects.new(jump["name"], None)
    root.empty_display_size = 0.3
    root.location = (index * SPACING, 0.0, 0.0)
    coll.objects.link(root)
    for name, part in parts.items():
        make_object(f"{jump['name']}_{name}", part, coll, root)
    collision = make_object(f"{jump['name']}_collision", col, coll, root)
    collision.display_type = "WIRE"
    collision.hide_render = True
    flag_marker(f"{jump['name']}_eqFlagsRed", flag_x, coll, root)
    flag_marker(f"{jump['name']}_eqFlagsWhite", -flag_x, coll, root)
    return root


def export(jump):
    """One OBJ per jump, at the origin, axes turned for the game."""
    os.makedirs(OUT, exist_ok=True)
    root = bpy.data.objects[jump["name"]]
    saved = root.location.copy()
    root.location = (0.0, 0.0, 0.0)
    bpy.context.view_layer.update()
    for obj in bpy.context.view_layer.objects:
        obj.select_set(obj.parent == root and obj.type == "MESH")
    bpy.ops.wm.obj_export(filepath=os.path.join(OUT, jump["name"] + ".obj"), export_selected_objects=True,
                          forward_axis="NEGATIVE_Z", up_axis="Y", export_uv=True, export_normals=True,
                          export_materials=True, export_triangulated_mesh=True, apply_modifiers=True)
    root.location = saved
    bpy.context.view_layer.update()


def main(export_too=True):
    for i, jump in enumerate(JUMPS):
        build(i, jump)
    if export_too:
        for jump in JUMPS:
            export(jump)
