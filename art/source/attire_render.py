"""A small software renderer for the outfit's wardrobe icons: a model on a clear background,
like the game's own icons (seen a little from above and to the side, lit from the upper left).

Part of Realistic Equestrian by Jasta007.
"""

import numpy as np
from PIL import Image


def render(meshes, size=256, yaw=35.0, pitch=-12.0, supersample=3):
    """meshes: [(Mesh, base rgb 0-1, shininess, spec strength)]. Returns an RGBA Pillow image,
    the model filling about 85% of it."""
    s = size * supersample
    cy, sy = np.cos(np.radians(yaw)), np.sin(np.radians(yaw))
    cp, sp = np.cos(np.radians(pitch)), np.sin(np.radians(pitch))
    turn = np.array([[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]])
    tip = np.array([[1, 0, 0], [0, cp, -sp], [0, sp, cp]])
    view = tip @ turn
    light = np.array([-0.5, 0.75, 0.45])
    light /= np.linalg.norm(light)
    half = light + np.array([0, 0, 1.0])
    half /= np.linalg.norm(half)

    parts = []
    for mesh, colour, shine, spec in meshes:
        p = np.array([v[0] for v in mesh.verts]) @ view.T
        n = np.array([v[1] for v in mesh.verts]) @ view.T
        parts.append((p, n, np.array(mesh.tris), np.array(colour), shine, spec))
    allp = np.concatenate([p for p, *_ in parts])
    lo, hi = allp.min(0), allp.max(0)
    scale = 0.85 * s / max(hi[0] - lo[0], hi[1] - lo[1])
    centre = (lo + hi) / 2

    colour_buf = np.zeros((s, s, 3))
    depth = np.full((s, s), -np.inf)
    for p, n, tris, colour, shine, spec in parts:
        sx = (p[:, 0] - centre[0]) * scale + s / 2
        sy_ = s / 2 - (p[:, 1] - centre[1]) * scale
        z = p[:, 2]
        nn = n / np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-9)
        diffuse = np.clip(nn @ light, 0, 1)
        specular = np.clip(nn @ half, 0, 1) ** shine
        rim = np.clip(1 - np.abs(nn[:, 2]), 0, 1) ** 3
        shade = colour[None, :] * (0.25 + 0.75 * diffuse[:, None]) + spec * specular[:, None] + 0.08 * rim[:, None]
        for a, b, c in tris:
            xs, ys = sx[[a, b, c]], sy_[[a, b, c]]
            x0, x1 = max(int(xs.min()), 0), min(int(xs.max()) + 1, s - 1)
            y0, y1 = max(int(ys.min()), 0), min(int(ys.max()) + 1, s - 1)
            if x1 < x0 or y1 < y0:
                continue
            area = (xs[1] - xs[0]) * (ys[2] - ys[0]) - (xs[2] - xs[0]) * (ys[1] - ys[0])
            if abs(area) < 1e-9:
                continue
            gx, gy = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
            w0 = ((xs[1] - gx) * (ys[2] - gy) - (xs[2] - gx) * (ys[1] - gy)) / area
            w1 = ((xs[2] - gx) * (ys[0] - gy) - (xs[0] - gx) * (ys[2] - gy)) / area
            w2 = 1 - w0 - w1
            inside = (w0 >= 0) & (w1 >= 0) & (w2 >= 0)
            if not inside.any():
                continue
            zz = w0 * z[a] + w1 * z[b] + w2 * z[c]
            region = depth[y0:y1 + 1, x0:x1 + 1]
            closer = inside & (zz > region)
            if not closer.any():
                continue
            region[closer] = zz[closer]
            col = (w0[..., None] * shade[a] + w1[..., None] * shade[b] + w2[..., None] * shade[c])
            colour_buf[y0:y1 + 1, x0:x1 + 1][closer] = col[closer]
    alpha = np.isfinite(depth).astype(np.float64)
    rgb = np.clip(colour_buf, 0, 1) ** (1 / 2.2)
    image = Image.fromarray(np.dstack([rgb * 255, alpha * 255]).astype(np.uint8), "RGBA")
    return image.resize((size, size), Image.LANCZOS)
