"""Software-renders the foal OBJ with each coat for a quick look (no game, no Blender).

    python3 foal_preview.py <HorseFoal.obj> <coat folder> <out.png>
"""
import sys, glob, os
import numpy as np
from PIL import Image, ImageDraw

def load(path):
    V, T, F = [], [], []
    for l in open(path):
        if l.startswith('v '): V.append([float(x) for x in l.split()[1:4]])
        elif l.startswith('vt '): T.append([float(x) for x in l.split()[1:3]])
        elif l.startswith('f '):
            f = [tuple(int(x) for x in p.split('/')[:2]) for p in l.split()[1:]]
            for k in range(1, len(f) - 1): F.append((f[0], f[k], f[k + 1]))
    return np.array(V), np.array(T), F

def render(V, T, F, tex, yaw, size=420):
    c, s = np.cos(yaw), np.sin(yaw)
    R = np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])
    P = V @ R.T
    tilt = np.radians(-12)
    Rx = np.array([[1, 0, 0], [0, np.cos(tilt), -np.sin(tilt)], [0, np.sin(tilt), np.cos(tilt)]])
    P = P @ Rx.T
    mid = (P.max(0) + P.min(0)) / 2; scale = size * 0.9 / (P.max(0) - P.min(0))[:2].max()
    sx = (P[:, 0] - mid[0]) * scale + size / 2; sy = size / 2 - (P[:, 1] - mid[1]) * scale; sz = P[:, 2]
    img = np.full((size, size, 3), 235, np.float32); zb = np.full((size, size), -1e9)
    th, tw = tex.shape[:2]
    light = np.array([0.4, 0.7, 0.6]); light /= np.linalg.norm(light)
    for (a, ta), (b, tb), (d, td) in F:
        ia, ib, id_ = a - 1, b - 1, d - 1
        x = np.array([sx[ia], sx[ib], sx[id_]]); y = np.array([sy[ia], sy[ib], sy[id_]]); z = np.array([sz[ia], sz[ib], sz[id_]])
        n = np.cross(P[ib] - P[ia], P[id_] - P[ia]); nl = np.linalg.norm(n)
        if nl == 0: continue
        shade = 0.55 + 0.45 * abs(np.dot(n / nl, light))
        x0, x1 = int(max(x.min(), 0)), int(min(x.max() + 1, size - 1)); y0, y1 = int(max(y.min(), 0)), int(min(y.max() + 1, size - 1))
        if x1 < x0 or y1 < y0: continue
        xs, ys = np.meshgrid(np.arange(x0, x1 + 1) + .5, np.arange(y0, y1 + 1) + .5)
        den = (y[1] - y[2]) * (x[0] - x[2]) + (x[2] - x[1]) * (y[0] - y[2])
        if abs(den) < 1e-9: continue
        w0 = ((y[1] - y[2]) * (xs - x[2]) + (x[2] - x[1]) * (ys - y[2])) / den
        w1 = ((y[2] - y[0]) * (xs - x[2]) + (x[0] - x[2]) * (ys - y[2])) / den
        w2 = 1 - w0 - w1
        m = (w0 >= 0) & (w1 >= 0) & (w2 >= 0)
        if not m.any(): continue
        zz = w0 * z[0] + w1 * z[1] + w2 * z[2]
        uv = w0[..., None] * T[ta - 1] + w1[..., None] * T[tb - 1] + w2[..., None] * T[td - 1]
        u = np.clip((uv[..., 0] % 1) * tw, 0, tw - 1).astype(int); v = np.clip((1 - uv[..., 1] % 1) * th, 0, th - 1).astype(int)
        col = tex[v, u]
        m &= col[..., 3] > 0.5
        sub = zb[y0:y1 + 1, x0:x1 + 1]
        m &= zz > sub
        sub[m] = zz[m]
        img[y0:y1 + 1, x0:x1 + 1][m] = col[..., :3][m] * 255 * shade
    return Image.fromarray(np.clip(img, 0, 255).astype(np.uint8))

V, T, F = load(sys.argv[1])
coats = sorted(glob.glob(os.path.join(sys.argv[2], 'coat_*.png')))
size = 420
sheet = Image.new('RGB', (size * 2 * 4, (size + 30) * 2), (255, 255, 255))
d = ImageDraw.Draw(sheet)
for i, path in enumerate(coats):
    tex = np.asarray(Image.open(path).convert('RGBA'), np.float32) / 255
    cx, cy = (i % 4) * size * 2, (i // 4) * (size + 30)
    sheet.paste(render(V, T, F, tex, np.radians(90)), (cx, cy + 30))
    sheet.paste(render(V, T, F, tex, np.radians(35)), (cx + size, cy + 30))
    d.text((cx + 10, cy + 8), os.path.basename(path)[7:-4], fill=(0, 0, 0))
sheet.save(sys.argv[3])
