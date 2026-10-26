from PIL import Image, ImageDraw, ImageFont, ImageFilter
import numpy as np
F = "fonts/"
WORD_FONT = F + "PlayfairDisplaySC-Regular.ttf"
WORD_SCALE = 0.62
SWASH = False
WORD_BASELINE = 345
def italic(size, wght=560):
    f = ImageFont.truetype(WORD_FONT, int(size * WORD_SCALE))
    try: f.set_variation_by_axes([wght])
    except Exception: pass
    return f
CAPS_FONT = F + "PlayfairDisplaySC-Regular.ttf"
CAPS_SCALE = 0.8
def caps(size):
    return ImageFont.truetype(CAPS_FONT, int(size * CAPS_SCALE))

def spaced(draw, xy, text, font, fill, tracking, anchor_center=True):
    widths = [draw.textlength(ch, font=font) for ch in text]
    total = sum(widths) + tracking * (len(text) - 1)
    x, y = xy
    if anchor_center: x -= total / 2
    for ch, w in zip(text, widths):
        draw.text((x, y), ch, font=font, fill=fill, anchor="ls")
        x += w + tracking
    return total

def bezier(p, n=200):
    (x0, y0), (x1, y1), (x2, y2), (x3, y3) = p
    for i in range(n + 1):
        t = i / n; u = 1 - t
        yield t, (u**3*x0 + 3*u*u*t*x1 + 3*u*t*t*x2 + t**3*x3, u**3*y0 + 3*u*u*t*y1 + 3*u*t*t*y2 + t**3*y3)

def swash_q(img, d, font, cx, baseline, scale, ink):
    """Replace the q's short footed descender with a longer tail that sweeps back under the E."""
    word = "Equestrian"
    x0 = cx - font.getlength(word) / 2
    qx, ux = x0 + font.getlength("E"), x0 + font.getlength("Eq")
    # Find the stem's centre just above the foot, then clear the foot.
    import numpy as np
    a = np.array(img.split()[3])
    y_cut = int(baseline + 68 * scale)
    row = np.where(a[y_cut, int(qx):int(ux)] > 128)[0]
    stem = int(qx) + (row.min() + row.max()) / 2
    half = (row.max() - row.min() + 1) / 2
    d.rectangle([qx - 30 * scale, y_cut + 1, ux - 4 * scale, baseline + 100 * scale], fill=(0, 0, 0, 0))
    # Carry the italic stem on down, then turn it into a tapering hairline curling up at the end.
    curve = [(stem, y_cut), (stem - 6 * scale, y_cut + 40 * scale), (stem - 40 * scale, y_cut + 58 * scale),
             (stem - 150 * scale, y_cut + 46 * scale)]
    for t, (x, y) in bezier(curve, 400):
        r = half * (1 - t) ** 1.15 + 1.2 * scale
        d.ellipse([x - r, y - r, x + r, y + r], fill=ink)
    tail = [curve[3], (stem - 185 * scale, y_cut + 42 * scale), (stem - 205 * scale, y_cut + 30 * scale),
            (stem - 200 * scale, y_cut + 16 * scale)]
    for t, (x, y) in bezier(tail, 200):
        r = 1.2 * scale * (1 - 0.4 * t)
        d.ellipse([x - r, y - r, x + r, y + r], fill=ink)

SIG_FONT = "/usr/share/fonts/truetype/liberation/LiberationSerif-Italic.ttf"
def sign(icon, scale):
    """Paint the author's signature into the straw at the bottom left, as a painter would."""
    N = icon.width
    layer = Image.new("RGBA", icon.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    font = ImageFont.truetype(SIG_FONT, int(30 * scale))
    d.text((52 * scale, N - 52 * scale), "Jasta007", font=font, fill=(58, 34, 16, 205), anchor="ls")
    layer = layer.rotate(4, resample=Image.BICUBIC, center=(52 * scale, N - 52 * scale))
    layer = layer.filter(ImageFilter.GaussianBlur(0.35 * scale))
    out = icon.convert("RGBA"); out.alpha_composite(layer)
    return out

def mark_dds(path, text=b"Realistic Equestrian by Jasta007"):
    """Write the maker's name into the DDS header's reserved bytes (offset 32, 44 bytes)."""
    with open(path, "r+b") as f:
        f.seek(32); f.write(text[:44].ljust(44, b"\0"))

def logotype(scale, ink, rule, rule_len=190, flourish=True, swash=True):
    W, H = int(1400 * scale), int(540 * scale)
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cx = W / 2
    # REALISTIC, letterspaced small caps between fine rules
    t = spaced(d, (cx, 150 * scale), "REALISTIC", caps(int(92 * scale)), ink, 34 * scale)
    y = 118 * scale
    gap = 34 * scale
    d.line([(cx - t / 2 - gap - rule_len * scale, y), (cx - t / 2 - gap, y)], fill=rule, width=max(1, int(3 * scale)))
    d.line([(cx + t / 2 + gap, y), (cx + t / 2 + gap + rule_len * scale, y)], fill=rule, width=max(1, int(3 * scale)))
    # Equestrian, a lively italic
    d.text((cx, WORD_BASELINE * scale), "Equestrian", font=italic(int(300 * scale)), fill=ink, anchor="ms")
    if swash and SWASH: swash_q(img, d, italic(int(300 * scale)), cx, 410 * scale, scale, ink)
    if not flourish: return img
    # a small diamond under, like an engraver's flourish
    dy = 468 * scale; s = 9 * scale
    d.polygon([(cx, dy - s), (cx + s, dy), (cx, dy + s), (cx - s, dy)], fill=rule)
    d.line([(cx - 120 * scale, dy), (cx - 22 * scale, dy)], fill=rule, width=max(1, int(2 * scale)))
    d.line([(cx + 22 * scale, dy), (cx + 120 * scale, dy)], fill=rule, width=max(1, int(2 * scale)))
    return img


cream = (242, 233, 212, 255)
OUT = "icon"
SRC = "herring_stable_1843.png"
N = 1024
icon = Image.open(SRC).convert("RGB").resize((N, N), Image.LANCZOS).convert("RGBA")
# A soft dark wash over the top, strongest behind the lettering and gone before the horse's head.
mask = Image.new("L", (N, N), 0)
md = ImageDraw.Draw(mask)
md.ellipse([N*0.08, -N*0.16, N*0.92, N*0.27], fill=175)
mask = mask.filter(ImageFilter.GaussianBlur(60))
icon = Image.composite(Image.new("RGBA", (N, N), (20, 17, 12, 255)), icon, mask)
logo = logotype(0.50, cream, (214, 190, 140, 255), rule_len=90, flourish=False)  # the diamond would touch the ears
# shadow for legibility on the busy hay rack
alpha = logo.split()[3].filter(ImageFilter.GaussianBlur(6))
shadow = Image.new("RGBA", logo.size, (10, 8, 5, 0)); shadow.putalpha(alpha.point(lambda a: int(a*0.8)))
x = (N - logo.width) // 2 + 6; y = 14
icon.alpha_composite(shadow, (x + 2, y + 4)); icon.alpha_composite(logo, (x, y))
icon = sign(icon, 1)
d = ImageDraw.Draw(icon)
d.rectangle([22, 22, N-23, N-23], outline=(226, 210, 172, 150), width=3)
icon = icon.convert("RGB")
icon.resize((512, 512), Image.LANCZOS).save(OUT + "_512.png")
icon.resize((128, 128), Image.LANCZOS).save(OUT + "_128.png")
icon.resize((512, 512), Image.LANCZOS).save(OUT + ".dds", pixel_format="DXT1")
mark_dds(OUT + ".dds")

logotype(1, (31, 58, 43, 255), (150, 120, 70, 255)).save("logotype_green.png")
logotype(1, cream, (214, 190, 140, 255)).save("logotype_cream.png")
