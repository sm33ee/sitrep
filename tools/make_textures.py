"""SITREP · the glass skin's textures (white, tinted in the game), as TGA files.
Run from the repo root:  python3 tools/make_textures.py
Writes SITREP/Media/*.tga: rounded fills and rings (9-slice: a corner is the
radius in pixels of a 64 x 64 texture), a soft shadow, and the glyphs."""
import math, os, struct

OUT = os.path.join("SITREP", "Media")
SS = 4  # supersampling per axis

def write_tga(path, w, h, alpha):
    # 32-bit BGRA, uncompressed, origin top-left; white, the alpha from `alpha`
    with open(path, "wb") as f:
        f.write(struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, w, h, 32, 0x28))
        for y in range(h):
            for x in range(w):
                a = max(0, min(255, int(round(alpha[y][x] * 255))))
                f.write(bytes((255, 255, 255, a)))

def raster(w, h, inside):
    """Coverage 0..1 per pixel of a shape given by inside(px, py) (supersampled)."""
    img = []
    for y in range(h):
        row = []
        for x in range(w):
            n = 0
            for sy in range(SS):
                for sx in range(SS):
                    if inside(x + (sx + 0.5) / SS, y + (sy + 0.5) / SS):
                        n += 1
            row.append(n / (SS * SS))
        img.append(row)
    return img

def rrect_dist(px, py, w, h, r):
    """Signed distance to the rounded rectangle 0..w, 0..h with corner radius r
    (negative inside): the usual rounded-box distance."""
    qx = abs(px - w / 2) - (w / 2 - r)
    qy = abs(py - h / 2) - (h / 2 - r)
    outside = math.hypot(max(qx, 0), max(qy, 0))
    inside = min(max(qx, qy), 0)
    return outside + inside - r

def fill(r):
    S = 64
    return raster(S, S, lambda px, py: rrect_dist(px, py, S, S, r) <= 0)

def ring(r, t):
    S = 64
    return raster(S, S, lambda px, py: -t < rrect_dist(px, py, S, S, r) <= 0)

def shadow():
    # a soft halo: 1 at the inner rounded rect (inset 16, radius 12), fading over 16 px
    S, inset, r, blur = 64, 16, 12, 16.0
    img = []
    for y in range(S):
        row = []
        for x in range(S):
            d = rrect_dist(x + 0.5 - inset, y + 0.5 - inset, S - 2 * inset, S - 2 * inset, r)
            a = 1.0 if d <= 0 else max(0.0, 1 - d / blur)
            row.append(a * a * (3 - 2 * a))  # smoothstep
        img.append(row)
    return img

def poly_inside(pts):
    def inside(px, py):
        c = False
        n = len(pts)
        for i in range(n):
            x1, y1 = pts[i]; x2, y2 = pts[(i + 1) % n]
            if (y1 > py) != (y2 > py) and px < (x2 - x1) * (py - y1) / (y2 - y1) + x1:
                c = not c
        return c
    return inside

def seg(ax, ay, bx, by, w):
    """Inside a stroke from (ax, ay) to (bx, by), w wide, round ends."""
    def inside(px, py):
        dx, dy = bx - ax, by - ay
        t = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)))
        return math.hypot(px - (ax + t * dx), py - (ay + t * dy)) <= w / 2
    return inside

def any_of(*fs):
    return lambda px, py: any(f(px, py) for f in fs)

def glyph(kind):
    S = 32
    c = S / 2
    W = 3.2  # stroke width of the line icons (chat buttons)
    if kind == "hash":
        f = any_of(seg(12, 5, 10, 27, W), seg(22, 5, 20, 27, W), seg(6, 12, 27, 12, W), seg(5, 20, 26, 20, W))
    elif kind == "mic":
        body = lambda px, py: rrect_dist(px - 11, py - 3, 10, 17, 5) <= 0 and rrect_dist(px - 11, py - 3, 10, 17, 5) > -W
        arc = lambda px, py: py >= 13 and abs(math.hypot(px - c, py - 13) - 9.5) <= W / 2
        f = any_of(body, arc, seg(c, 22.5, c, 28, W), seg(11, 28, 21, 28, W))
    elif kind == "speaker":
        box = poly_inside([(5, 12), (11, 12), (18, 5), (18, 27), (11, 20), (5, 20)])
        wave = lambda px, py: px >= 21 and abs(math.hypot(px - 18, py - c) - 7) <= W / 2 and abs(py - c) <= 8
        f = any_of(box, wave)
    elif kind == "menu":
        f = any_of(seg(6, 9, 26, 9, W), seg(6, 16, 26, 16, W), seg(6, 23, 26, 23, W))
    elif kind == "down":  # a chevron
        f = any_of(seg(8, 12, c, 21, W + 0.6), seg(c, 21, 24, 12, W + 0.6))
    elif kind == "up":
        f = any_of(seg(8, 20, c, 11, W + 0.6), seg(c, 11, 24, 20, W + 0.6))
    else:
        f = None
    if f is not None:
        return raster(S, S, f)
    if kind == "diamond":
        f = poly_inside([(c, 2), (S - 2, c), (c, S - 2), (2, c)])
    elif kind == "plus":
        f = lambda px, py: (abs(px - c) <= 4.5 and 3 <= py <= S - 3) or (abs(py - c) <= 4.5 and 3 <= px <= S - 3)
    elif kind == "ring":
        f = lambda px, py: 9 <= math.hypot(px - c, py - c) <= 13.5
    elif kind == "dot":
        f = lambda px, py: math.hypot(px - c, py - c) <= 9
    elif kind == "triangle":
        f = poly_inside([(c, 3), (S - 3, S - 4), (3, S - 4)])
    elif kind == "star":
        pts = []
        for i in range(8):
            ang = math.pi / 4 * i - math.pi / 2
            rad = 14 if i % 2 == 0 else 5
            pts.append((c + rad * math.cos(ang), c + rad * math.sin(ang)))
        f = poly_inside(pts)
    elif kind == "lock":
        body = lambda px, py: 7 <= px <= S - 7 and 14 <= py <= S - 4
        shackle = lambda px, py: py <= 16 and 5.5 <= math.hypot(px - c, py - 14) <= 9.5
        f = lambda px, py: body(px, py) or shackle(px, py)
    elif kind == "bang":
        f = lambda px, py: (abs(px - c) <= 3.5 and 3 <= py <= 20) or math.hypot(px - c, py - 26.5) <= 3.8
    else:
        raise ValueError(kind)
    return raster(S, S, f)

# The minimap's rounded masks: the map stretches the mask over itself, so a
# corner of 12 px on screen needs a smaller radius in the mask the bigger the map
# is. One mask per radius (in px of the 256 px mask); SITREP picks the nearest.
MAP_RADII = (26, 20, 15, 12, 9, 7, 5)

def mapmask(r):
    S = 256
    return raster(S, S, lambda px, py: rrect_dist(px, py, S, S, r) <= 0)

def png(path, img, scale=4, bg=(30, 36, 38)):
    """A preview: the alpha over a dark ground, enlarged (to look at, not for the game)."""
    import zlib
    h, w = len(img), len(img[0])
    raw = b""
    for y in range(h * scale):
        raw += b"\x00"
        for x in range(w * scale):
            a = img[y // scale][x // scale]
            raw += bytes(int(bg[i] + (255 - bg[i]) * a) for i in range(3))
    def chunk(t, d): return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w * scale, h * scale, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))

def main():
    os.makedirs(OUT, exist_ok=True)
    for r in (4, 8, 12):
        write_tga(os.path.join(OUT, "fill%d.tga" % r), 64, 64, fill(r))
        for t in (1, 2, 3):
            write_tga(os.path.join(OUT, "ring%d_%d.tga" % (r, t)), 64, 64, ring(r, t))
    write_tga(os.path.join(OUT, "shadow.tga"), 64, 64, shadow())
    for r in MAP_RADII:
        write_tga(os.path.join(OUT, "mapmask%d.tga" % r), 256, 256, mapmask(r))
    for g in ("diamond", "plus", "ring", "dot", "triangle", "star", "lock", "bang", "hash", "mic", "speaker", "menu", "down", "up"):
        write_tga(os.path.join(OUT, "glyph_%s.tga" % g), 32, 32, glyph(g))

if __name__ == "__main__":
    import sys
    if len(sys.argv) > 1:  # a preview PNG of the shapes into that folder
        d = sys.argv[1]
        png(os.path.join(d, "fill8.png"), fill(8)); png(os.path.join(d, "ring8_2.png"), ring(8, 2))
        png(os.path.join(d, "shadow.png"), shadow())
        sheet = [sum((glyph(g)[y] for g in ("diamond", "plus", "ring", "dot", "triangle", "star", "lock", "bang")), []) for y in range(32)]
        png(os.path.join(d, "glyphs.png"), sheet, 3)
    else:
        main()
