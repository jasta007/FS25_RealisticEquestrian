import math, random
from PIL import Image, ImageDraw, ImageFilter
import numpy as np
S = 2048; k = S/1000
OFF=[0,0]
def P(x,y): return ((x+OFF[0])*k, (y+OFF[1])*k)

def capsule(d, pts, widths, fill):
    # polyline of variable width, drawn as circles + quads
    for i in range(len(pts)-1):
        (x0,y0),(x1,y1) = pts[i], pts[i+1]; w0,w1 = widths[i], widths[i+1]
        steps = 24
        for s in range(steps+1):
            t = s/steps
            x = x0+(x1-x0)*t; y=y0+(y1-y0)*t; w=(w0+(w1-w0)*t)/2
            d.ellipse([ (x-w+OFF[0])*k,(y-w+OFF[1])*k,(x+w+OFF[0])*k,(y+w+OFF[1])*k ], fill=fill)

def rot_ellipse(d, cx, cy, rx, ry, ang, fill):
    pts=[]
    for i in range(120):
        t=2*math.pi*i/120
        x=rx*math.cos(t); y=ry*math.sin(t)
        a=math.radians(ang)
        pts.append(P(cx+x*math.cos(a)-y*math.sin(a), cy+x*math.sin(a)+y*math.cos(a)))
    d.polygon(pts, fill=fill)

def background():
    img = Image.new("RGB",(S,S))
    a = np.zeros((S,S,3))
    y = np.linspace(0,1,S)[:,None]
    sky_top = np.array([150,170,182]); sky_low = np.array([226,214,184])
    sky = sky_top*(1-y)+sky_low*y
    a[:] = sky[:, None, :].squeeze()[:, None, :] if False else sky[:, :][:, None, :].reshape(S,1,3)
    field_top = np.array([138,142,92]); field_bot=np.array([176,150,86])
    hz = int(0.63*S)
    yy = np.linspace(0,1,S-hz)[:,None]
    a[hz:] = (field_top*(1-yy)+field_bot*yy).reshape(S-hz,1,3)
    img = Image.fromarray(a.clip(0,255).astype('uint8'))
    d = ImageDraw.Draw(img)
    # cloud masses: warm lit tops, cool shadowed bellies, patches of blue between
    rnd = random.Random(3)
    blue = Image.new("L",(S,S),0); bd = ImageDraw.Draw(blue)
    for _ in range(10):
        cx=rnd.uniform(0,1000); cy=rnd.uniform(40,300); r=rnd.uniform(60,160)
        bd.ellipse([P(cx-r*2.2,cy-r*0.5),P(cx+r*2.2,cy+r*0.5)], fill=rnd.randint(90,160))
    blue = blue.filter(ImageFilter.GaussianBlur(70))
    img = Image.composite(Image.new("RGB",(S,S),(112,146,176)), img, blue)
    lit = Image.new("L",(S,S),0); ld = ImageDraw.Draw(lit)
    shade = Image.new("L",(S,S),0); sd = ImageDraw.Draw(shade)
    for _ in range(26):
        cx=rnd.uniform(-50,1050); cy=rnd.uniform(140,520); r=rnd.uniform(50,130)
        ld.ellipse([P(cx-r*1.9,cy-r*0.7),P(cx+r*1.9,cy+r*0.45)], fill=rnd.randint(120,200))
        sd.ellipse([P(cx-r*1.6,cy+r*0.05),P(cx+r*1.7,cy+r*0.55)], fill=rnd.randint(60,120))
    lit = lit.filter(ImageFilter.GaussianBlur(34)); shade = shade.filter(ImageFilter.GaussianBlur(40))
    img = Image.composite(Image.new("RGB",(S,S),(246,236,212)), img, lit)
    img = Image.composite(Image.new("RGB",(S,S),(168,166,164)), img, shade)
    d = ImageDraw.Draw(img)
    # distant treeline
    pts=[P(0,640)]
    x=0
    while x<=1000:
        pts.append(P(x, 618 - 22*abs(math.sin(x/37))*rnd.uniform(0.4,1.0) - (30 if 120<x<330 else 0)*math.sin((x-120)/210*math.pi) if 120<x<330 else 618 - 22*abs(math.sin(x/37))*rnd.uniform(0.4,1)))
        x+=8
    pts += [P(1000,650), P(0,650)]
    d.polygon(pts, fill=(96,108,92))
    d.rectangle([P(0,636),P(1000,652)], fill=(118,124,96))
    return img

def horse_layer(img):
    OFF[0], OFF[1] = 10, 28
    d = ImageDraw.Draw(img)
    bay=(96,54,30); dark=(44,28,20); black=(26,20,18); light=(122,72,40)
    # far-side legs (darker)
    capsule(d, [(350,450),(336,500),(272,526),(214,534),(192,546)], [60,44,26,18,16], dark)   # far hind
    capsule(d, [(612,462),(670,478),(632,512)], [40,26,18], dark)                              # far fore tucked
    # tail
    capsule(d, [(312,416),(276,424),(240,440),(206,462)], [36,32,24,10], (34,22,18))
    # body
    rot_ellipse(d, 482, 438, 160, 76, -12, bay)
    rot_ellipse(d, 372, 442, 84, 80, -12, bay)     # hindquarters
    rot_ellipse(d, 596, 418, 62, 66, -12, bay)     # chest/shoulder
    # sheen on the rump and shoulder
    rot_ellipse(d, 372, 410, 54, 22, -22, (138,84,46))
    rot_ellipse(d, 604, 392, 30, 20, -40, (132,80,44))
    # neck
    capsule(d, [(598,420),(648,356),(700,300)], [118,92,62], bay)
    # head as a wedge
    d.polygon([P(694,280),P(716,272),P(752,302),P(790,336),P(794,352),P(772,360),P(744,346),P(718,334),P(696,312)], fill=bay)
    capsule(d, [(712,276),(708,252)], [14,6], dark)   # ear
    capsule(d, [(588,366),(613,330),(646,302),(680,278)], [16,14,12,8], black)  # mane along the crest
    d.ellipse([P(736,300),P(744,308)], fill=black)   # eye
    # near legs
    capsule(d, [(380,468),(368,516),(300,544),(234,552),(208,566)], [74,54,30,20,18], light)    # near hind
    capsule(d, [(212,562),(196,570)], [22,22], black)
    capsule(d, [(628,468),(698,488),(652,528)], [48,30,20], light)                              # near fore tucked
    capsule(d, [(654,528),(642,522)], [22,22], black)
    # saddle cloth and saddle
    rot_ellipse(d, 502, 390, 52, 32, -12, (232,226,210))
    rot_ellipse(d, 506, 376, 40, 14, -12, (60,36,22))
    # rider
    navy=(38,44,64); cream=(226,220,200); boot=(22,20,20)
    capsule(d, [(494,366),(554,386)], [42,34], cream)        # thigh
    capsule(d, [(554,386),(540,444)], [30,24], boot)         # boot
    capsule(d, [(490,358),(532,316),(568,294)], [48,46,40], navy)  # torso
    capsule(d, [(562,300),(608,330),(646,350)], [22,18,14], navy)  # arm
    d.ellipse([P(576,254),P(614,290)], fill=(30,28,30))      # helmet
    d.ellipse([P(594,276),P(608,292)], fill=(170,124,96))   # face
    d.line([P(646,350),P(770,340)], fill=(30,20,16), width=int(4*k))
    OFF[0], OFF[1] = 0, 0
    return img

def fence(img):
    d = ImageDraw.Draw(img)
    wood=(118,96,72); shade=(84,66,50)
    for x in (300, 790):
        d.rectangle([P(x-12,585),P(x+12,730)], fill=shade)
        d.rectangle([P(x-12,585),P(x-2,730)], fill=wood)
    for y in (600, 640, 680):
        d.polygon([P(250,y),P(850,y-6),P(850,y+10),P(250,y+16)], fill=wood)
        d.polygon([P(250,y+10),P(850,y+4),P(850,y+10),P(250,y+16)], fill=shade)
    # brush/hedge under the rails
    rnd=random.Random(9)
    for _ in range(900):
        x=rnd.uniform(262,838); y=rnd.uniform(684,738)+ (10 if x<300 or x>800 else 0); r=rnd.uniform(4,12)
        g=rnd.randint(42,96)
        d.ellipse([P(x-r,y-r*0.6),P(x+r,y+r*0.6)], fill=(g-6,g+4+rnd.randint(0,10),g-26))
    return img

def ground_shadow(img):
    sh = Image.new("L",(S,S),0); d=ImageDraw.Draw(sh)
    d.ellipse([P(330,760),P(700,800)], fill=120)
    sh=sh.filter(ImageFilter.GaussianBlur(30))
    return Image.composite(Image.new("RGB",(S,S),(96,90,52)), img, sh)

if __name__=="__main__":
    img = background(); img = ground_shadow(img)
    img.save("plate.png")
    img = fence(img)
    # horse on its own layer so it can be lit from above
    hl = Image.new("RGB",(S,S),(255,0,255)); hl = horse_layer(hl)
    ha = np.asarray(hl).astype(np.float32)
    mask = ~((ha[:,:,0]==255)&(ha[:,:,1]==0)&(ha[:,:,2]==255))
    yy = (np.arange(S)/k)[:,None]
    light = np.clip(1.6 - (yy-280)/240*1.0, 0.55, 1.6)[:, :, None]
    xx = (np.arange(S)/k)[None,:]
    light = light * np.clip(0.9 + (xx-300)/1500, 0.85, 1.15)[:, :, None]
    lit = np.clip(ha*light, 0, 255)
    arr = np.asarray(img).astype(np.float32)
    arr[mask] = lit[mask]
    img = Image.fromarray(arr.astype('uint8'))
    subj = Image.fromarray((mask*255).astype('uint8'))
    fz = Image.new("L",(S,S),0); fd = ImageDraw.Draw(fz)
    fd.rectangle([P(240,580),P(860,745)], fill=255)
    fd.rectangle([P(0,600),P(1000,655)], fill=255)
    from PIL import ImageChops
    obj = Image.fromarray((mask*255).astype('uint8'))
    od = ImageDraw.Draw(obj)
    od.rectangle([P(240,582),P(860,742)], fill=255)
    obj.filter(ImageFilter.GaussianBlur(3)).save("object.png")
    subj = ImageChops.lighter(subj, fz).filter(ImageFilter.MaxFilter(31))
    subj.save("subject.png")
    img.save("under.png"); img.resize((512,512), Image.LANCZOS).save("under_small.png")
