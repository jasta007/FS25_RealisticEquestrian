from PIL import Image, ImageDraw, ImageFont, ImageFilter
import numpy as np
F = "fonts/"
def italic(size, wght=560):
    f = ImageFont.truetype(F + "CormorantGaramond-Italic[wght].ttf", size)
    try: f.set_variation_by_axes([wght])
    except Exception: pass
    return f
def caps(size):
    return ImageFont.truetype(F + "CormorantSC-SemiBold.ttf", size)

def spaced(draw, xy, text, font, fill, tracking, anchor_center=True):
    widths = [draw.textlength(ch, font=font) for ch in text]
    total = sum(widths) + tracking * (len(text) - 1)
    x, y = xy
    if anchor_center: x -= total / 2
    for ch, w in zip(text, widths):
        draw.text((x, y), ch, font=font, fill=fill, anchor="ls")
        x += w + tracking
    return total

def logotype(scale, ink, rule, rule_len=190):
    W, H = int(1400 * scale), int(520 * scale)
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
    d.text((cx, 410 * scale), "Equestrian", font=italic(int(300 * scale)), fill=ink, anchor="ms")
    # a small diamond under, like an engraver's flourish
    dy = 468 * scale; s = 9 * scale
    d.polygon([(cx, dy - s), (cx + s, dy), (cx, dy + s), (cx - s, dy)], fill=rule)
    d.line([(cx - 120 * scale, dy), (cx - 22 * scale, dy)], fill=rule, width=max(1, int(2 * scale)))
    d.line([(cx + 22 * scale, dy), (cx + 120 * scale, dy)], fill=rule, width=max(1, int(2 * scale)))
    return img


cream = (242, 233, 212, 255)
SRC = "herring_stable_1843.png"
N = 1024
icon = Image.open(SRC).convert("RGB").resize((N, N), Image.LANCZOS).convert("RGBA")
# A soft dark wash over the top, strongest behind the lettering and gone before the horse's head.
mask = Image.new("L", (N, N), 0)
md = ImageDraw.Draw(mask)
md.ellipse([N*0.08, -N*0.16, N*0.92, N*0.27], fill=175)
mask = mask.filter(ImageFilter.GaussianBlur(60))
icon = Image.composite(Image.new("RGBA", (N, N), (20, 17, 12, 255)), icon, mask)
logo = logotype(0.50, cream, (214, 190, 140, 255), rule_len=90)
logo = logo.crop((0, 0, logo.width, int(440 * 0.50)))  # no flourish: it would touch the ears
# shadow for legibility on the busy hay rack
alpha = logo.split()[3].filter(ImageFilter.GaussianBlur(6))
shadow = Image.new("RGBA", logo.size, (10, 8, 5, 0)); shadow.putalpha(alpha.point(lambda a: int(a*0.8)))
x = (N - logo.width) // 2 + 6; y = 14
icon.alpha_composite(shadow, (x + 2, y + 4)); icon.alpha_composite(logo, (x, y))
d = ImageDraw.Draw(icon)
d.rectangle([22, 22, N-23, N-23], outline=(226, 210, 172, 150), width=3)
icon = icon.convert("RGB")
icon.resize((512, 512), Image.LANCZOS).save("herring_512.png")
icon.resize((128, 128), Image.LANCZOS).save("herring_128.png")
icon.resize((512, 512), Image.LANCZOS).save("herring.dds", pixel_format="DXT1")
