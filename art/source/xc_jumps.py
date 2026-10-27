"""
Builds the cross country fences in placeables/xcJumps/: one .xml and .i3d per fence, the textures
they share and a shop image for each.

Like the dressage arenas, the .i3d files keep their geometry inline (<IndexedTriangleSet>), so no
GIANTS tools are needed, and the textures are painted here rather than downloaded, so every pixel
is ours.

A log pile is a pyramid of logs lying along x, so the horse jumps it along z. Each fence has:
- "logs" and "logEnds": the visible logs (bark) and their sawn ends (rings),
- "flags": a post at each end of the face, red at +x and white at -x; the empty transform groups
  "eqFlagsRed" and "eqFlagsWhite" at their feet are what the course recorder reads as the jump's
  two ends (EqCourseHooks.findFlags, as with Riding Hall's "modernFlagsRed"/"modernFlagsWhite"),
- "collision": one invisible static prism following the pile's outline, with the collision filter
  Riding Hall 2k26's jumps use, so the horse has to jump it and can't snag on single logs.

Run from the repository root: python3 art/source/xc_jumps.py

Part of Realistic Equestrian by Jasta007.
"""

import math
import os
import random

import numpy as np
from PIL import Image, ImageDraw, ImageFont

OUT = "placeables/xcJumps"
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"

# name, price, the logs in each row from the bottom up, log diameter and length (metres)
LOG_PILES = [
    {"name": "xcLogPileSmall", "price": 600, "rows": [2, 1], "diameter": 0.40, "length": 3.6, "seed": 3},
    {"name": "xcLogPile", "price": 900, "rows": [3, 2, 1], "diameter": 0.38, "length": 4.2, "seed": 7},
]

# Fence markers: no fence of their own. Put one across anything you want ridden as a cross country
# fence (a map's logs, a bank you landscaped, another mod's prop). They glow gold in construction
# mode and are hidden while you ride (EqXcMarkers); only their flags' feet matter to the mod.
MARKERS = [
    {"name": "xcFenceMarker3m", "price": 250, "width": 3.0},
    {"name": "xcFenceMarker5m", "price": 250, "width": 5.0},
    {"name": "xcFenceMarker8m", "price": 250, "width": 8.0},
]
MARKER_BARS = (0.45, 1.0)   # heights of the two glowing rails
MARKER_BAR = 0.06
GOLD = (236, 184, 52)

SIDES = 16              # faces round each log
SINK = 0.04             # logs sit this far into the ground so they never float on a slope
STAGGER = 0.18          # most a log's ends stick out past the others (either way)
TAPER = 0.08            # a log is up to this share thinner at one end
BUMP = 0.035            # how far round a log wanders from a perfect circle (share of radius)
BARK_TILE = 1.0         # metres of log one bark texture covers, round and along
FLAG_GAP = 0.35         # posts stand this far past the logs' ends
POST_HEIGHT = 1.45
POST_SIZE = 0.07
FLAG_W, FLAG_H, FLAG_T = 0.42, 0.30, 0.012
CLIP = 300              # fences are small: drawn out to 300 m
# Riding Hall 2k26's static jump collision ("col" in props01.i3d): blocks the horse and the player.
COLLISION_GROUP = "0x1034"
COLLISION_MASK = "0xfffffbff"


# ---------------------------------------------------------------------------------------------
# Textures

def mark_dds(path, text=b"Realistic Equestrian by Jasta007"):
    """Name the author in the DDS header's reserved bytes, like the mod icon."""
    with open(path, "r+b") as f:
        f.seek(32)
        f.write(text[:44].ljust(44, b"\0"))


def periodic_noise(size, rng, scale_u, scale_v):
    """Smooth noise that tiles: white noise filtered in frequency space. scale_* = feature size in
    pixels across u (columns) and v (rows); a long v scale makes streaks running along v."""
    white = rng.standard_normal((size, size))
    fu = np.fft.fftfreq(size)[None, :]
    fv = np.fft.fftfreq(size)[:, None]
    gain = np.exp(-((fu * scale_u) ** 2 + (fv * scale_v) ** 2) * 4)
    out = np.real(np.fft.ifft2(np.fft.fft2(white) * gain))
    return (out - out.mean()) / (out.std() + 1e-9)


def bark_texture(path, size=512):
    """Grey-brown bark with deep fissures running along the log (v) and plates between them."""
    rng = np.random.default_rng(11)
    # fissures: narrow across the log, long along it, wobbling sideways
    wobble = periodic_noise(size, rng, 40, 90) * 6
    cols = (np.arange(size)[None, :] + wobble) % size
    ridges = np.zeros((size, size))
    lanes = 9
    phase = periodic_noise(size, rng, 200, 160)
    for k in range(lanes):
        centre = (k + 0.5) * size / lanes
        d = np.abs(((cols - centre + size / 2) % size) - size / 2)
        width = 4.5 + 2.5 * phase
        ridges = np.maximum(ridges, np.clip(1 - d / np.maximum(width, 1.5), 0, 1))
    # cross breaks in the plates, so they read as bark and not corduroy
    breaks = np.clip(periodic_noise(size, rng, 6, 2) - 1.6, 0, 1)
    plates = periodic_noise(size, rng, 30, 70)
    grain = periodic_noise(size, rng, 1.5, 6)
    light = 0.62 + 0.10 * plates + 0.06 * grain - 0.55 * ridges ** 1.5 - 0.25 * breaks
    light = np.clip(light, 0.08, 1)
    base = np.array([112, 92, 72], dtype=float)
    tint = periodic_noise(size, rng, 80, 80)[..., None] * np.array([6, 4, 2])
    rgb = np.clip(light[..., None] * (base + tint) * 1.25, 0, 255).astype(np.uint8)
    Image.fromarray(rgb, "RGB").save(path, pixel_format="DXT1")
    mark_dds(path)
    return rgb


def log_end_texture(path, size=256):
    """A sawn log end: pale wood with growth rings, a dark pith, a few cracks and the bark rim."""
    rng = np.random.default_rng(5)
    y, x = np.mgrid[0:size, 0:size]
    u = (x + 0.5) / size * 2 - 1
    v = (y + 0.5) / size * 2 - 1
    r = np.hypot(u, v)
    a = np.arctan2(v, u)
    wobble = periodic_noise(size, rng, 30, 30) * 0.015
    rr = r + wobble + 0.01 * np.sin(a * 3 + 1)
    rings = 0.5 + 0.5 * np.sin(rr * 2 * math.pi * 14) ** 7
    light = 0.86 - 0.16 * rings - 0.10 * rr
    for crack_angle in (0.4, 2.3, 4.4):
        da = np.abs((a - crack_angle + math.pi) % (2 * math.pi) - math.pi)
        light -= 0.45 * np.clip(1 - da * r / 0.012, 0, 1) * (r < 0.6) * (r > 0.08)
    light -= 0.5 * np.clip(1 - r / 0.05, 0, 1)
    rgb = light[..., None] * np.array([214, 178, 128], dtype=float)
    # bark rim
    rim = np.clip((r - 0.86) / 0.04, 0, 1)[..., None]
    rgb = rgb * (1 - rim) + rim * np.array([74, 58, 44])
    rgb = np.clip(rgb, 0, 255).astype(np.uint8)
    Image.fromarray(rgb, "RGB").save(path, pixel_format="DXT1")
    mark_dds(path)
    return rgb


# One row of four cells: red flag, white flag, post, gold (markers).
FLAG_CELLS = [(196, 28, 32), (240, 240, 236), (196, 170, 128), GOLD]


def flag_texture(path, cell=32):
    img = Image.new("RGB", (cell * len(FLAG_CELLS), cell))
    draw = ImageDraw.Draw(img)
    for i, colour in enumerate(FLAG_CELLS):
        draw.rectangle([i * cell, 0, (i + 1) * cell - 1, cell - 1], fill=colour)
    img.save(path, pixel_format="DXT1")
    mark_dds(path)
    return np.asarray(img)


def flag_uv(index):
    """Centre of a flag texture cell."""
    return (index + 0.5) / len(FLAG_CELLS), 0.5


# ---------------------------------------------------------------------------------------------
# Geometry

def sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def norm(a):
    length = math.sqrt(dot(a, a)) or 1.0
    return (a[0] / length, a[1] / length, a[2] / length)


class Mesh:
    def __init__(self):
        self.verts = []  # (p, n, uv)
        self.tris = []

    def vertex(self, p, n, uv):
        self.verts.append((p, n, uv))
        return len(self.verts) - 1

    def tri(self, a, b, c):
        """Wound counter-clockwise seen from the side its vertex normals face."""
        pa, pb, pc = self.verts[a][0], self.verts[b][0], self.verts[c][0]
        n = self.verts[a][1]
        if dot(cross(sub(pb, pa), sub(pc, pa)), n) < 0:
            b, c = c, b
        self.tris.append((a, b, c))

    def quad(self, corners, n, uvs):
        ids = [self.vertex(p, n, uv) for p, uv in zip(corners, uvs)]
        self.tri(ids[0], ids[1], ids[2])
        self.tri(ids[0], ids[2], ids[3])

    def box(self, x0, x1, y0, y1, z0, z1, uv):
        """A box in one flat texture cell, without its bottom."""
        faces = [
            ((0, 0, 1), [(x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)]),
            ((0, 0, -1), [(x1, y0, z0), (x0, y0, z0), (x0, y1, z0), (x1, y1, z0)]),
            ((1, 0, 0), [(x1, y0, z1), (x1, y0, z0), (x1, y1, z0), (x1, y1, z1)]),
            ((-1, 0, 0), [(x0, y0, z0), (x0, y0, z1), (x0, y1, z1), (x0, y1, z0)]),
            ((0, 1, 0), [(x0, y1, z1), (x1, y1, z1), (x1, y1, z0), (x0, y1, z0)]),
        ]
        for n, corners in faces:
            self.quad(corners, n, [uv] * 4)

    def bounds(self):
        ps = [p for p, _, _ in self.verts]
        lo = [min(p[i] for p in ps) for i in range(3)]
        hi = [max(p[i] for p in ps) for i in range(3)]
        centre = [(lo[i] + hi[i]) / 2 for i in range(3)]
        radius = max(math.dist(centre, p) for p in ps)
        return centre, radius


def layout(jump):
    """Every log as (y, z, x0, x1, r0, r1, seed): rows stacked in the grooves of the row below."""
    rng = random.Random(jump["seed"])
    d = jump["diameter"]
    half = jump["length"] / 2
    logs = []
    for row, count in enumerate(jump["rows"]):
        y = d / 2 + row * d * math.sqrt(3) / 2 - SINK
        for i in range(count):
            z = (i - (count - 1) / 2) * d
            r = d / 2 * rng.uniform(0.94, 1.03)
            thin = r * (1 - rng.uniform(0.2, 1) * TAPER)
            r0, r1 = (r, thin) if rng.random() < 0.5 else (thin, r)
            x0 = -half + rng.uniform(-STAGGER, STAGGER)
            x1 = half + rng.uniform(-STAGGER, STAGGER)
            logs.append((y, z, x0, x1, r0, r1, rng.randrange(1 << 30)))
    return logs


def height(jump):
    """Top of the top log above the ground."""
    d = jump["diameter"]
    return d + (len(jump["rows"]) - 1) * d * math.sqrt(3) / 2 - SINK


def build_logs(jump):
    bark, ends = Mesh(), Mesh()
    for y, z, x0, x1, r0, r1, seed in layout(jump):
        rng = random.Random(seed)
        bumps = [1 + rng.uniform(-BUMP, BUMP) for _ in range(SIDES)]
        turn = rng.uniform(0, 2 * math.pi)
        mean_r = (r0 + r1) / 2
        u_scale = 2 * math.pi * mean_r / BARK_TILE
        v_shift = rng.uniform(0, 1)
        rings = []
        for end, (x, r) in enumerate(((x0, r0), (x1, r1))):
            ring = []
            for k in range(SIDES + 1):
                a = turn + 2 * math.pi * k / SIDES
                b = bumps[k % SIDES]
                p = (x, y + math.sin(a) * r * b, z + math.cos(a) * r * b)
                n = (0.0, math.sin(a), math.cos(a))
                uv = (k / SIDES * u_scale, x / BARK_TILE + v_shift)
                ring.append(bark.vertex(p, n, uv))
            rings.append(ring)
        for k in range(SIDES):
            a, b = rings[0][k], rings[0][k + 1]
            c, e = rings[1][k + 1], rings[1][k]
            bark.tri(a, b, c)
            bark.tri(a, c, e)
        # sawn ends: a fan round the middle, the ring texture mapped flat
        for x, r, nx in ((x0, r0, -1.0), (x1, r1, 1.0)):
            n = (nx, 0.0, 0.0)
            spin = rng.uniform(0, 2 * math.pi)
            centre = ends.vertex((x, y, z), n, (0.5, 0.5))
            rim = []
            for k in range(SIDES):
                a = turn + 2 * math.pi * k / SIDES
                b = bumps[k]
                p = (x, y + math.sin(a) * r * b, z + math.cos(a) * r * b)
                t = a - turn + spin
                uv = (0.5 + 0.5 * math.cos(t) * 0.95, 0.5 + 0.5 * math.sin(t) * 0.95)
                rim.append(ends.vertex(p, n, uv))
            for k in range(SIDES):
                ends.tri(centre, rim[k], rim[(k + 1) % SIDES])
    return bark, ends


def flag_posts(half, mesh=None):
    """Posts at each end of a fence face, red at +x and white at -x, each flag flying outwards.
    Returns the mesh and the posts' feet."""
    mesh = mesh or Mesh()
    s = POST_SIZE / 2
    feet = {}
    for name, x, colour, side in (("eqFlagsRed", half, 0, 1), ("eqFlagsWhite", -half, 1, -1)):
        mesh.box(x - s, x + s, -0.1, POST_HEIGHT, -s, s, flag_uv(2))
        fx0, fx1 = (x + s, x + s + FLAG_W) if side > 0 else (x - s - FLAG_W, x - s)
        top = POST_HEIGHT - 0.04
        mesh.box(fx0, fx1, top - FLAG_H, top, -FLAG_T / 2, FLAG_T / 2, flag_uv(colour))
        feet[name] = (x, 0.0, 0.0)
    return mesh, feet


def log_pile_half(jump):
    """Half the distance between a log pile's flags."""
    return jump["length"] / 2 + STAGGER + FLAG_GAP


def marker_mesh(marker):
    """Two gold rails between gold posts, and the red and white flags."""
    half = marker["width"] / 2
    gold = Mesh()
    s = MARKER_BAR / 2
    for y in MARKER_BARS:
        gold.box(-half, half, y - s, y + s, -s, s, flag_uv(3))
    flags, feet = flag_posts(half)
    return gold, flags, feet


def collision(jump):
    """One prism round the pile's outline (seen from the side), as long as the shortest log."""
    d = jump["diameter"]
    logs = layout(jump)
    x0 = max(log[2] for log in logs)
    x1 = min(log[3] for log in logs)
    bottom = jump["rows"][0] * d / 2
    top_half = jump["rows"][-1] * d / 2 * 0.7
    top = height(jump) - 0.03
    outline = [(-bottom, 0.0), (bottom, 0.0), (top_half, top), (-top_half, top)]
    mesh = Mesh()
    uv = (0.5, 0.5)
    for x, nx in ((x0, -1.0), (x1, 1.0)):
        ids = [mesh.vertex((x, y, z), (nx, 0.0, 0.0), uv) for z, y in outline]
        mesh.tri(ids[0], ids[1], ids[2])
        mesh.tri(ids[0], ids[2], ids[3])
    for i in range(4):
        (za, ya), (zb, yb) = outline[i], outline[(i + 1) % 4]
        n = norm((0.0, zb - za, -(yb - ya)))
        if dot(n, (0.0, (ya + yb) / 2 - top / 2, (za + zb) / 2)) < 0:
            n = (0.0, -n[1], -n[2])
        mesh.quad([(x0, ya, za), (x1, ya, za), (x1, yb, zb), (x0, yb, zb)], n, [uv] * 4)
    return mesh


# ---------------------------------------------------------------------------------------------
# Files

def fmt(values):
    return " ".join(f"{v:.5g}" for v in values)


def shape_lines(mesh, name, shape_id):
    centre, radius = mesh.bounds()
    lines = [
        f'    <IndexedTriangleSet name="{name}" shapeId="{shape_id}" bvCenter="{fmt(centre)}" bvRadius="{radius:.5g}">',
        f'      <Vertices count="{len(mesh.verts)}" normal="true" uv0="true">',
    ]
    for p, n, uv in mesh.verts:
        lines.append(f'        <v p="{fmt(p)}" n="{fmt(n)}" t0="{fmt(uv)}"/>')
    lines.append("      </Vertices>")
    lines.append(f'      <Triangles count="{len(mesh.tris)}">')
    for a, b, c in mesh.tris:
        lines.append(f'        <t vi="{a} {b} {c}"/>')
    lines.append("      </Triangles>")
    lines.append('      <Subsets count="1">')
    lines.append(f'        <Subset firstVertex="0" numVertices="{len(mesh.verts)}" firstIndex="0" numIndices="{len(mesh.tris) * 3}"/>')
    lines.append("      </Subsets>")
    lines.append("    </IndexedTriangleSet>")
    return lines


MATERIALS = [
    # name, texture, emissive (glows without light)
    ("xcBark", "xcBark_diffuse.dds", False),
    ("xcLogEnd", "xcLogEnd_diffuse.dds", False),
    ("xcFlags", "xcFlags_diffuse.dds", False),
    ("xcMarkerGold", "xcFlags_diffuse.dds", True),
]


def write_i3d(name, path, shapes, feet, col=None, group=None):
    """shapes: (node name, mesh, material name, casts shadows). group: a transform group the
    visible shapes go under (the markers hide it while you ride)."""
    files = sorted({texture for _, texture, _ in MATERIALS})
    lines = [
        '<?xml version="1.0" encoding="iso-8859-1"?>',
        "",
        f'<i3D name="{name}" version="1.6" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
        'xsi:noNamespaceSchemaLocation="http://i3d.giants.ch/schema/i3d-1.6.xsd">',
        "  <Asset>",
        '    <Export program="Realistic Equestrian xc_jumps.py" version="1"/>',
        "  </Asset>",
        "  <Files>",
    ]
    for i, texture in enumerate(files):
        lines.append(f'    <File fileId="{i + 1}" filename="{texture}"/>')
    lines.append("  </Files>")
    lines.append("  <Materials>")
    material_ids = {}
    for i, (material, texture, emissive) in enumerate(MATERIALS):
        material_ids[material] = i + 1
        lines.append(f'    <Material name="{material}" materialId="{i + 1}" specularColor="0.15 0.6 0">')
        lines.append(f'      <Texture fileId="{files.index(texture) + 1}"/>')
        if emissive:
            lines.append(f'      <Emissivemap fileId="{files.index(texture) + 1}"/>')
        lines.append("    </Material>")
    lines.append("  </Materials>")
    lines.append("  <Shapes>")
    for i, (node, mesh, _, _) in enumerate(shapes):
        lines += shape_lines(mesh, f"{name}_{node}", i + 1)
    if col is not None:
        lines += shape_lines(col, name + "_collision", len(shapes) + 1)
    lines.append("  </Shapes>")
    lines.append("  <Scene>")
    lines.append(f'    <TransformGroup name="{name}" nodeId="1">')
    node_id = 2
    indent = "      "
    if group is not None:
        lines.append(f'{indent}<TransformGroup name="{group}" nodeId="{node_id}">')
        node_id += 1
        indent += "  "
    for i, (node, _, material, shadows) in enumerate(shapes):
        cast = "true" if shadows else "false"
        lines.append(f'{indent}<Shape name="{node}" shapeId="{i + 1}" clipDistance="{CLIP}" nodeId="{node_id}" '
                     f'materialIds="{material_ids[material]}" castsShadows="{cast}" receiveShadows="true"/>')
        node_id += 1
    if group is not None:
        lines.append("      </TransformGroup>")
    for flag in ("eqFlagsRed", "eqFlagsWhite"):
        lines.append(f'      <TransformGroup name="{flag}" translation="{fmt(feet[flag])}" nodeId="{node_id}"/>')
        node_id += 1
    if col is not None:
        lines.append(f'      <TransformGroup name="collision" nodeId="{node_id}">')
        lines.append(f'        <Shape name="col" shapeId="{len(shapes) + 1}" static="true" collisionFilterGroup="{COLLISION_GROUP}" '
                     f'collisionFilterMask="{COLLISION_MASK}" density="0.01" nodeId="{node_id + 1}" nonRenderable="true" materialIds="1"/>')
        lines.append("      </TransformGroup>")
    lines += ["    </TransformGroup>", "  </Scene>", "</i3D>"]
    with open(path, "w", encoding="iso-8859-1", newline="\n") as f:
        f.write("\n".join(lines) + "\n")


def write_xml(name, price, note, path):
    text = f"""<?xml version="1.0" encoding="utf-8" standalone="no"?>
<!-- Made by art/source/xc_jumps.py: change that and run it again rather than editing this. -->
<placeable type="simplePlaceable">
    <storeData>
        <name>$l10n_eq_shop_{name}</name>
        <functions>
            <function>$l10n_eq_shop_{"xcFenceMarker" if "Marker" in name else "xcJump"}_function</function>
        </functions>
        <image>placeables/xcJumps/store_{name}.dds</image>
        <price>{price}</price>
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
        <vertexBufferMemoryUsage>0</vertexBufferMemoryUsage>
        <indexBufferMemoryUsage>0</indexBufferMemoryUsage>
        <textureMemoryUsage>0</textureMemoryUsage>
        <instanceVertexBufferMemoryUsage>0</instanceVertexBufferMemoryUsage>
        <instanceIndexBufferMemoryUsage>0</instanceIndexBufferMemoryUsage>
    </storeData>

    <base>
        <filename>placeables/xcJumps/{name}.i3d</filename>
        <canBeRenamed>false</canBeRenamed>
    </base>

    <placement useRandomYRotation="false" useManualYRotation="true">
        <!-- {note} -->
    </placement>
</placeable>
"""
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)


# ---------------------------------------------------------------------------------------------
# Shop image: a small software render of the fence itself, three-quarter view.

def render(meshes, size=512, yaw=-35, pitch=18):
    """Painter's algorithm over flat-shaded, texture-tinted triangles. meshes: (mesh, texture)."""
    cy, sy = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
    cp, sp = math.cos(math.radians(pitch)), math.sin(math.radians(pitch))

    def view(p):
        x, y, z = p
        x, z = x * cy + z * sy, -x * sy + z * cy
        y, z = y * cp - z * sp, y * sp + z * cp
        return x, y, z

    light = norm((-0.4, 0.8, 0.5))
    polys = []
    pts = []
    for mesh, tex in meshes:
        h, w = tex.shape[:2]
        for a, b, c in mesh.tris:
            ps = [mesh.verts[i][0] for i in (a, b, c)]
            n = norm(cross(sub(ps[1], ps[0]), sub(ps[2], ps[0])))
            vs = [view(p) for p in ps]
            vn = view(n)
            if vn[2] < 0:
                continue  # facing away
            uv = [mesh.verts[i][2] for i in (a, b, c)]
            u = (sum(t[0] for t in uv) / 3) % 1
            v = (sum(t[1] for t in uv) / 3) % 1
            colour = tex[min(h - 1, int(v * h)), min(w - 1, int(u * w))].astype(float)
            shade = 0.45 + 0.65 * max(0.0, dot(n, light))
            depth = sum(p[2] for p in vs) / 3
            polys.append((depth, vs, tuple(int(min(255, ch * shade)) for ch in colour[:3])))
            pts += vs
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    span = max(max(xs) - min(xs), max(ys) - min(ys))
    scale = size * 0.8 / span
    ox = size / 2 - (max(xs) + min(xs)) / 2 * scale
    oy = size * 0.55 + (max(ys) + min(ys)) / 2 * scale
    img = Image.new("RGB", (size, size))
    draw = ImageDraw.Draw(img)
    # sky to grass
    horizon = int(size * 0.42)
    for y in range(size):
        if y < horizon:
            t = y / horizon
            colour = (int(150 + 60 * t), int(190 + 40 * t), int(225 + 20 * t))
        else:
            t = (y - horizon) / (size - horizon)
            colour = (int(96 - 30 * t), int(128 - 30 * t), int(62 - 20 * t))
        draw.line([0, y, size, y], fill=colour)
    for _, vs, colour in sorted(polys, key=lambda item: item[0]):
        draw.polygon([(ox + x * scale, oy - y * scale) for x, y, _ in vs], fill=colour)
    return img


def store_image(meshes, label, path, preview_dir):
    img = render(meshes)
    draw = ImageDraw.Draw(img)
    font = ImageFont.truetype(FONT, 28)
    draw.text((img.width - 16, img.height - 14), label, font=font, fill=(250, 250, 250), anchor="rd")
    img.save(path, pixel_format="DXT1")
    mark_dds(path)
    # a PNG copy to look at, kept out of the mod
    os.makedirs(preview_dir, exist_ok=True)
    img.save(os.path.join(preview_dir, os.path.basename(path).replace(".dds", ".png")))


def main():
    preview_dir = os.environ.get("XC_PREVIEW_DIR", "art/previews")
    os.makedirs(OUT, exist_ok=True)
    bark = bark_texture(os.path.join(OUT, "xcBark_diffuse.dds"))
    ends = log_end_texture(os.path.join(OUT, "xcLogEnd_diffuse.dds"))
    flags = flag_texture(os.path.join(OUT, "xcFlags_diffuse.dds"))
    for jump in LOG_PILES:
        name = jump["name"]
        bark_mesh, ends_mesh = build_logs(jump)
        posts, feet = flag_posts(log_pile_half(jump))
        shapes = [("logs", bark_mesh, "xcBark", True), ("logEnds", ends_mesh, "xcLogEnd", True), ("flags", posts, "xcFlags", True)]
        write_i3d(name, os.path.join(OUT, name + ".i3d"), shapes, feet, col=collision(jump))
        depth = jump["rows"][0] * jump["diameter"]
        write_xml(name, jump["price"], f"{height(jump):.2f} m high, {depth:.2f} m deep; jumped along z, red flag at +x.",
                  os.path.join(OUT, name + ".xml"))
        store_image([(bark_mesh, bark), (ends_mesh, ends), (posts, flags)], f"{height(jump):.2f} m",
                    os.path.join(OUT, "store_" + name + ".dds"), preview_dir)
        print(name, f"{height(jump):.2f} m high,", len(layout(jump)), "logs,",
              len(bark_mesh.tris) + len(ends_mesh.tris) + len(posts.tris), "triangles")
    for marker in MARKERS:
        name = marker["name"]
        gold, posts, feet = marker_mesh(marker)
        shapes = [("rails", gold, "xcMarkerGold", False), ("flags", posts, "xcFlags", False)]
        write_i3d(name, os.path.join(OUT, name + ".i3d"), shapes, feet, group="eqXcMarkerVisual")
        write_xml(name, marker["price"], f"A {marker['width']:g} m fence face with no fence: hidden while riding.",
                  os.path.join(OUT, name + ".xml"))
        store_image([(gold, flags), (posts, flags)], f"{marker['width']:g} m",
                    os.path.join(OUT, "store_" + name + ".dds"), preview_dir)
        print(name, f"{marker['width']:g} m")


if __name__ == "__main__":
    main()
