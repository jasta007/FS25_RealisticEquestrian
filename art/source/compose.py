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

green = (31, 58, 43, 255); brass = (150, 120, 70, 255); cream = (242, 233, 212, 255)
logotype(1, green, brass).save("logotype_green.png")
logotype(1, cream, (214, 190, 140, 255)).save("logotype_cream.png")
# preview on paper
paper = Image.new("RGBA", (1400, 520), (244, 238, 224, 255))
paper.alpha_composite(logotype(1, green, brass)); paper.convert("RGB").save("logotype_preview.png")

# ICON
paint = Image.open("painted_crop.png").convert("RGB").resize((1024, 1024), Image.LANCZOS)
icon = paint.convert("RGBA")
# darken the lower band so the lettering sits on the painting, not on a box
grad = Image.new("L", (1, 1024), 0)
for y in range(1024):
    t = max(0, (y - 600) / 424)
    grad.putpixel((0, y), int(255 * min(1, t ** 1.2) * 0.82))
grad = grad.resize((1024, 1024))
icon = Image.composite(Image.new("RGBA", (1024, 1024), (24, 26, 20, 255)), icon, grad)
logo = logotype(0.66, cream, (214, 190, 140, 255), rule_len=110)
icon.alpha_composite(logo, ((1024 - logo.width) // 2, 1024 - logo.height - 20))
# fine inset frame line, like a mount
d = ImageDraw.Draw(icon)
d.rectangle([22, 22, 1001, 1001], outline=(226, 210, 172, 150), width=3)
icon = icon.convert("RGB")
icon.resize((512, 512), Image.LANCZOS).save("icon_512.png")
icon.resize((256, 256), Image.LANCZOS).save("icon_256.png")
icon.resize((512, 512), Image.LANCZOS).save("icon_RealisticEquestrian.dds", pixel_format="DXT1")
