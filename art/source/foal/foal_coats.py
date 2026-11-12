"""Builds the foal's 8 coats and the 4x2 coat atlas from the TurboSquid foal pack (2487065).

    python3 foal_coats.py <pack folder> <out folder> [tile size, default 1024]

Coat order matches the base horse atlas (data/foals/horseAnimals.xml):
    row 0: grey, pinto, palomino, chestnut     row 1: bay, black, seal brown, dun
Recipes (James 2026-11-12): grey, black, dun = the pack's own albedos 3, 2, 4; pinto = albedo 1
darkened a lot to walnut brown, white kept; bay = dun a little darker; seal brown = darker still
with a blaze and socks; chestnut = dun redder and a bit darker; palomino = dun with a white mane
and tail. Masks come from the OBJ's UV islands and 3D positions, so they follow the model.
"""
import os, sys, pickle
import numpy as np
from PIL import Image, ImageFilter

PACK, OUT = sys.argv[1], sys.argv[2]
TILE = int(sys.argv[3]) if len(sys.argv) > 3 else 1024
WORK = 2048  # masks and recolours are made at this size, then scaled to TILE
os.makedirs(OUT, exist_ok=True)

# UV islands, numbered biggest first (see the island map this script saves).
HAIR = {6, 17, 18, 21, 22, 23, 24, 31, 32, 35, 36}     # tail tube + cards, mane and forelock strips
KEEP = {7, 8, 11, 12, 13, 14, 19, 20, 29, 30, 33, 34}  # eyes, mouth, teeth: never recoloured
HOOVES = {25, 26, 27, 28}


def load_obj(path):
    V, T, F = [], [], []
    for line in open(path):
        if line.startswith('v '): V.append([float(x) for x in line.split()[1:4]])
        elif line.startswith('vt '): T.append([float(x) for x in line.split()[1:3]])
        elif line.startswith('f '): F.append([tuple(int(x) for x in p.split('/')[:2]) for p in line.split()[1:]])
    return np.array(V), np.array(T), F


def islands(T, F):
    parent = list(range(len(T)))
    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]; a = parent[a]
        return a
    for f in F:
        root = find(f[0][1] - 1)
        for _, t in f[1:]: parent[find(t - 1)] = root
    groups = {}
    for i, f in enumerate(F): groups.setdefault(find(f[0][1] - 1), []).append(i)
    order = sorted(groups.values(), key=len, reverse=True)
    faceIsland = np.zeros(len(F), int)
    for n, faces in enumerate(order): faceIsland[faces] = n
    return faceIsland


def rasterize(V, T, F, faceIsland, size):
    """Per texel: island number (-1 = empty) and the interpolated 3D position."""
    isl = np.full((size, size), -1, np.int32)
    pos = np.zeros((size, size, 3), np.float32)
    for fi, f in enumerate(F):
        for k in range(1, len(f) - 1):
            tri = [f[0], f[k], f[k + 1]]
            uv = np.array([[T[t - 1][0] * size, (1 - T[t - 1][1]) * size] for _, t in tri])
            p = np.array([V[v - 1] for v, _ in tri])
            x0, y0 = np.floor(uv.min(0)).astype(int); x1, y1 = np.ceil(uv.max(0)).astype(int)
            x0, y0 = max(x0, 0), max(y0, 0); x1, y1 = min(x1, size - 1), min(y1, size - 1)
            if x1 < x0 or y1 < y0: continue
            xs, ys = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
            (ax, ay), (bx, by), (cx, cy) = uv
            den = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
            if abs(den) < 1e-9: continue
            w0 = ((by - cy) * (xs - cx) + (cx - bx) * (ys - cy)) / den
            w1 = ((cy - ay) * (xs - cx) + (ax - cx) * (ys - cy)) / den
            w2 = 1 - w0 - w1
            inside = (w0 >= -0.01) & (w1 >= -0.01) & (w2 >= -0.01)
            if not inside.any(): continue
            yy, xx = np.nonzero(inside)
            yy += y0; xx += x0
            isl[yy, xx] = faceIsland[fi]
            pos[yy, xx] = (w0[inside, None] * p[0] + w1[inside, None] * p[1] + w2[inside, None] * p[2])
    return isl, pos


def soft(mask, radius):
    img = Image.fromarray((mask * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(radius))
    return np.asarray(img, np.float32) / 255


def grow(mask, px):
    img = Image.fromarray((mask * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(px * 2 + 1))
    return np.asarray(img, np.float32) / 255


def albedo(n):
    im = Image.open(os.path.join(PACK, 'HorseFoal_Textures', 'texture', 'HorseFoal_Albedo%d.png' % n)).convert('RGBA')
    return np.asarray(im.resize((WORK, WORK), Image.LANCZOS), np.float32) / 255


def lum(rgb):
    return rgb[..., 0] * 0.299 + rgb[..., 1] * 0.587 + rgb[..., 2] * 0.114


def recolour(src, mask, mul, gamma=1.0):
    """Multiply rgb by mul (per channel) where mask is 1; gamma < 1 brightens shadows a little."""
    out = src.copy()
    rgb = np.clip(src[..., :3], 0, 1) ** gamma * np.array(mul, np.float32)
    out[..., :3] = src[..., :3] * (1 - mask[..., None]) + np.clip(rgb, 0, 1) * mask[..., None]
    return out


def blend(a, b, mask):
    out = a.copy()
    out[..., :3] = a[..., :3] * (1 - mask[..., None]) + b[..., :3] * mask[..., None]
    return out


def main():
    V, T, F = load_obj(os.path.join(PACK, 'HorseFoal_OBJ', 'HorseFoal.obj'))
    faceIsland = islands(T, F)
    cache = os.path.join(OUT, 'raster_%d.npz' % WORK)
    if os.path.exists(cache):
        z = np.load(cache); isl, pos = z['isl'], z['pos']
    else:
        isl, pos = rasterize(V, T, F, faceIsland, WORK)
        np.savez_compressed(cache, isl=isl, pos=pos)
    # fill the gutters with the nearest island so blurred masks don't bleed odd colours
    hair = soft(grow(np.isin(isl, list(HAIR)).astype(np.float32), 6), 2)
    keep = grow(np.isin(isl, list(KEEP | HOOVES)).astype(np.float32), 2)
    coat = np.clip(1 - keep, 0, 1)
    x, y, z = pos[..., 0], pos[..., 1], pos[..., 2]
    on = isl >= 0

    # socks: lower legs from the coronet (just above the hoof) to about the fetlock-cannon
    socks = on & (y > 0.0) & (y < 0.24) & ~np.isin(isl, list(HOOVES | HAIR))
    socks = soft(socks.astype(np.float32), 6) * coat
    # blaze: a stripe down the front of the face, from the forehead to the nostrils
    # blaze after James's reference foal: a broad star between the eyes, a narrow stripe down the
    # nose bridge, then widening again over the muzzle to the nostrils; slightly off-centre
    t = (y - 1.05) / 0.4                                       # ~0 at the nostrils, ~1 at the forehead
    # head landmarks (OBJ, metres): eyes y 1.29-1.32, nostrils y 1.14-1.17, forehead front ends at z 0.62 (y 1.43)
    star = 0.032 * np.exp(-((t - 0.70) / 0.09) ** 2)           # forehead star, centred just above the eyes (y ~1.33)
    snip = 0.010 * np.exp(-((t - 0.26) / 0.07) ** 2)           # muzzle widening between the nostrils (y ~1.155)
    half = 0.007 + star + snip + 0.0015 * np.sin(t * 13.0)
    drift = 0.003 * np.sin(t * 5.0 + 0.6)
    face = on & np.isin(isl, [1]) & (np.abs(x - drift) < half) & (z > 0.62) & (y > 1.05) & (t < 0.88)
    # keep only the upper (front) surface of the head: at each depth z the centre line runs over
    # the face and back under the jaw, so drop the texels in the lower half (the chin and throat)
    bins = np.floor(z / 0.01).astype(np.int64)
    for b in np.unique(bins[face]):
        sel = face & (bins == b)
        ys = y[sel]
        face[sel] = ys > (ys.min() + ys.max()) / 2
    blaze = soft(face.astype(np.float32), 3) * coat

    a1, a2, a3, a4 = albedo(1), albedo(2), albedo(3), albedo(4)
    body = coat * (1 - hair)

    # pinto: walnut brown with the white kept (white = bright and unsaturated in albedo 1)
    sat = a1[..., :3].max(-1) - a1[..., :3].min(-1)
    white = soft(((lum(a1[..., :3]) > 0.62) & (sat < 0.12)).astype(np.float32), 2)
    pinto = recolour(a1, coat * (1 - white), (0.52, 0.42, 0.36), 1.05)

    bay = recolour(a4, body, (0.78, 0.66, 0.54))
    bay = recolour(bay, hair * coat, (0.35, 0.3, 0.27))           # bay: darker mane and tail
    seal = recolour(a4, coat, (0.42, 0.33, 0.27), 1.1)
    # albedo 3's muzzle is dark skin, so lighten the blaze source below y 1.21 for a white snip
    lift = (np.clip((1.21 - y) / 0.03, 0, 1) * (y > 1.0))[..., None]     # head only, not the socks
    whiteSrc = a3.copy()
    whiteSrc[..., :3] = a3[..., :3] * (1 - lift) + (1 - (1 - a3[..., :3]) * 0.3) * np.array((0.97, 0.9, 0.86), np.float32) * lift
    seal = blend(seal, whiteSrc, np.maximum(blaze, socks))
    chestnut = recolour(a4, coat, (0.92, 0.6, 0.4))
    palomino = recolour(a4, body, (1.02, 0.88, 0.62))
    pale = recolour(a3, np.ones_like(hair), (1.0, 0.97, 0.9))
    palomino = blend(palomino, pale, hair * coat)

    coats = [('grey', a3), ('pinto', pinto), ('palomino', palomino), ('chestnut', chestnut),
             ('bay', bay), ('black', a2), ('sealBrown', seal), ('dun', a4)]
    atlas = Image.new('RGBA', (TILE * 4, TILE * 2))
    for i, (name, img) in enumerate(coats):
        tile = Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8), 'RGBA').resize((TILE, TILE), Image.LANCZOS)
        tile.save(os.path.join(OUT, 'coat_%d_%s.png' % (i + 1, name)))
        # the engine counts tileVIndex from the bottom of the image, so coat row 0 goes at the bottom
        atlas.paste(tile, ((i % 4) * TILE, (1 - i // 4) * TILE))
    # tileAndMirrorShader alpha-tests the diffuse alpha at the RAW mesh UVs (glossmapTexCoords,
    # before the atlas transform), while colour is read inside the coat's tile. So the alpha
    # channel holds the one hair-card mask stretched over the whole atlas.
    mask = Image.fromarray(np.asarray(atlas)[:TILE, :TILE, 3]).resize((TILE * 4, TILE * 2), Image.LANCZOS)
    atlas.putalpha(mask)
    atlas.save(os.path.join(OUT, 'foal_diffuse_atlas.png'))
    rng = np.random.RandomState(1)
    colours = rng.randint(40, 255, (64, 3)).astype(np.uint8)
    Image.fromarray(np.where(on[..., None], colours[isl % 64], 0)).resize((1024, 1024)).save(os.path.join(OUT, 'islands.png'))


if __name__ == '__main__':
    main()
