#!/usr/bin/env python3
"""Generate the precomputed tables for Linner (build/tables.asm).

  gen_tables.py out.asm

Screen: Mode 1 overscan, 384x272, 96 bytes per line, single buffer at
&8000-&FFFF. CRTC R12/R13 = &2C/&10, so charlines 0..20 sit in &8000-&BFFF
starting 32 bytes into each 2K block, and charlines 21..33 continue at
&C000-&FFFF from offset 0. Game coordinates: x 0..383, y 0..255 = screen
rows 16..271 (rows 0..15 are the HUD).

Everything that needs trigonometry or geometry is computed here so the Z80
never multiplies or divides at run time.
"""
import math
import sys

R = 10              # Linner's radius in pixels
RAY = R - 2         # length of the internal ray
SHOT_SPEED = 5      # pixels per frame
HUD_ROWS = 16
SCREEN_ROWS = 272
GROUND_TOP = 128        # game y of height key 0
GROUND_DUMMY = 0x7580   # scratch "row" that gap keys write to (96 bytes)


def row_addr(r):
    """Screen address of the first byte of screen row r (0..271)."""
    c, ra = r >> 3, r & 7
    if c <= 20:
        return 0x8000 + ra * 0x800 + 32 + c * 96
    return 0xC000 + ra * 0x800 + (c - 21) * 96


def circle_pixels():
    """Midpoint circle outline, as a set of (dx, dy) offsets from the centre."""
    pts = set()
    x, y, d = R, 0, 1 - R
    while x >= y:
        for a, b in ((x, y), (y, x)):
            for sx in (1, -1):
                for sy in (1, -1):
                    pts.add((sx * a, sy * b))
        y += 1
        if d < 0:
            d += 2 * y + 1
        else:
            x -= 1
            d += 2 * (y - x) + 1
    return pts


def emit_move(out, frm, to):
    d = to - frm
    if d == 0:
        return
    if abs(d) <= 3:
        out.extend(["  inc hl" if d > 0 else "  dec hl"] * abs(d))
    else:
        out.append(f"  ld bc,{d & 0xFFFF}")
        out.append("  add hl,bc")


# Classic 5x7 font, column-major, bit 0 = top row.
FONT = {
    " ": [0, 0, 0, 0, 0], "!": [0x00, 0x00, 0x5F, 0x00, 0x00],
    "-": [0x08, 0x08, 0x08, 0x08, 0x08], ".": [0x00, 0x60, 0x60, 0x00, 0x00],
    ":": [0x00, 0x36, 0x36, 0x00, 0x00],
    "0": [0x3E, 0x51, 0x49, 0x45, 0x3E], "1": [0x00, 0x42, 0x7F, 0x40, 0x00],
    "2": [0x42, 0x61, 0x51, 0x49, 0x46], "3": [0x21, 0x41, 0x45, 0x4B, 0x31],
    "4": [0x18, 0x14, 0x12, 0x7F, 0x10], "5": [0x27, 0x45, 0x45, 0x45, 0x39],
    "6": [0x3C, 0x4A, 0x49, 0x49, 0x30], "7": [0x01, 0x71, 0x09, 0x05, 0x03],
    "8": [0x36, 0x49, 0x49, 0x49, 0x36], "9": [0x06, 0x49, 0x49, 0x29, 0x1E],
    "A": [0x7E, 0x11, 0x11, 0x11, 0x7E], "B": [0x7F, 0x49, 0x49, 0x49, 0x36],
    "C": [0x3E, 0x41, 0x41, 0x41, 0x22], "D": [0x7F, 0x41, 0x41, 0x22, 0x1C],
    "E": [0x7F, 0x49, 0x49, 0x49, 0x41], "F": [0x7F, 0x09, 0x09, 0x09, 0x01],
    "G": [0x3E, 0x41, 0x49, 0x49, 0x7A], "H": [0x7F, 0x08, 0x08, 0x08, 0x7F],
    "I": [0x00, 0x41, 0x7F, 0x41, 0x00], "J": [0x20, 0x40, 0x41, 0x3F, 0x01],
    "K": [0x7F, 0x08, 0x14, 0x22, 0x41], "L": [0x7F, 0x40, 0x40, 0x40, 0x40],
    "M": [0x7F, 0x02, 0x0C, 0x02, 0x7F], "N": [0x7F, 0x04, 0x08, 0x10, 0x7F],
    "O": [0x3E, 0x41, 0x41, 0x41, 0x3E], "P": [0x7F, 0x09, 0x09, 0x09, 0x06],
    "Q": [0x3E, 0x41, 0x51, 0x21, 0x5E], "R": [0x7F, 0x09, 0x19, 0x29, 0x46],
    "S": [0x46, 0x49, 0x49, 0x49, 0x31], "T": [0x01, 0x01, 0x7F, 0x01, 0x01],
    "U": [0x3F, 0x40, 0x40, 0x40, 0x3F], "V": [0x1F, 0x20, 0x40, 0x20, 0x1F],
    "W": [0x3F, 0x40, 0x38, 0x40, 0x3F], "X": [0x63, 0x14, 0x08, 0x14, 0x63],
    "Y": [0x07, 0x08, 0x70, 0x08, 0x07], "Z": [0x61, 0x51, 0x49, 0x45, 0x43],
    "@": [0x1C, 0x22, 0x41, 0x22, 0x1C],     # a little Linner (lives)
}


def font_tables(o):
    """font: 8 row bytes per glyph for codes 32..90 (pixels in bits 6..2, so
    each 8-pixel cell has a 1-pixel margin). nib_pen3: 4 pixels -> one Mode
    1 byte in pen 3."""
    o.append("FONT_FIRST equ 32")
    o.append("font:")
    for code in range(32, 91):
        cols = FONT.get(chr(code), [0] * 5)
        rows = []
        for r in range(8):
            b = 0
            for c in range(5):
                if (cols[c] >> r) & 1:
                    b |= 0x40 >> c
            rows.append(b)
        o.append("  db " + ",".join(f"&{v:02X}" for v in rows) + f"   ; {chr(code)!r}")
    o.append("  align 16")
    o.append("nib_pen3:")
    vals = []
    for n in range(16):
        b = 0
        for i in range(4):
            if n & (8 >> i):
                b |= 0x88 >> i
        vals.append(b)
    o.append("  db " + ",".join(f"&{v:02X}" for v in vals))


def sprite_code(name, shift, pts, height):
    """Compiled XOR sprite for one pixel phase.

    pts are (x, y) pixels relative to the bounding box's top-left corner.
    Entry: HL = screen address of the box's top-left byte, where the box's
    left edge x has x & 3 == shift. Calling it twice restores the screen.
    Trashes A, BC, HL.
    """
    rows = {}
    for x, y in pts:
        px = x + shift
        rows.setdefault(y, {}).setdefault(px >> 2, 0)
        rows[y][px >> 2] |= 0x88 >> (px & 3)
    out = [f"{name}_{shift}:"]
    col = 0
    for r in range(height):
        for c in sorted(rows.get(r, {})):
            emit_move(out, col, c)
            col = c
            out.append("  ld a,(hl)")
            out.append(f"  xor &{rows[r][c]:02X}")
            out.append("  ld (hl),a")
        if r != height - 1:
            out.append("  DOWNS")
    out.append("  ret")
    return out


def sprite(o, name, pts):
    """All four phases plus NAME_W, NAME_H and the NAME_tab jump table."""
    w = max(x for x, y in pts) + 1
    h = max(y for x, y in pts) + 1
    o.append(f"{name.upper()}_W equ {w}")
    o.append(f"{name.upper()}_H equ {h}")
    for sh in range(4):
        o.extend(sprite_code(name, sh, pts, h))
    o.append(f"{name}_tab:")
    o.append("  dw " + ",".join(f"{name}_{sh}" for sh in range(4)))
    o.append("")


def line_pixels(x0, y0, x1, y1):
    pts = set()
    n = max(abs(x1 - x0), abs(y1 - y0))
    for i in range(n + 1):
        pts.add((round(x0 + (x1 - x0) * i / n), round(y0 + (y1 - y0) * i / n)))
    return pts


def rect_pixels(w, h):
    return ({(x, 0) for x in range(w)} | {(x, h - 1) for x in range(w)}
            | {(0, y) for y in range(h)} | {(w - 1, y) for y in range(h)})


def tri_pixels(w, h):
    apex = (w // 2, 0)
    return (line_pixels(*apex, 0, h - 1) | line_pixels(*apex, w - 1, h - 1)
            | line_pixels(0, h - 1, w - 1, h - 1))


MENU_HY = 200          # the horizon of the menus' vector world (game y)


def menu_world(o):
    """The vector world under the title and name entry screens: a floor
    whose cross lines roll towards the viewer, radial floor lines, low
    mountains, a striped sun on the horizon and a few stars."""
    hy, cx = MENU_HY, 192
    o.append(f"MENU_HY equ {hy}")
    # floor cross lines: 16 phases x 7 lines (game y), perspective y = hy +
    # 55 / (7.9 - depth)
    o.append("MENU_FLOOR_LINES equ 7")
    o.append("menu_floor:")
    for p in range(16):
        ys = [hy + round(55 / (7.9 - (k + p / 16))) for k in range(7)]
        o.append("  db " + ",".join(str(min(y, 255)) for y in ys))
    # radial lines from the horizon to the bottom edge, clipped to the screen
    rad = []
    for j in range(-9, 10):
        x0, y0, x1, y1 = cx + j * 10, hy + 1, cx + j * 52, 255
        if x1 < 0:
            y1 = round(y0 + (y1 - y0) * (0 - x0) / (x1 - x0)); x1 = 0
        if x1 > 383:
            y1 = round(y0 + (y1 - y0) * (383 - x0) / (x1 - x0)); x1 = 383
        if y1 > y0:
            rad.append((x0, y0, x1, y1))
    o.append(f"MENU_N_RADIALS equ {len(rad)}")
    o.append("menu_radials:")
    for x0, y0, x1, y1 in rad:
        o.append(f"  dw {x0}\n  db {y0}\n  dw {x1}\n  db {y1}")
    # mountains: low in the middle (under the centred text), higher outside
    hs = [6, 16, 9, 20, 8, 5, 3, 6, 2, 5, 3, 7, 5, 4, 18, 10, 20, 8, 0]
    xs = [round(i * 383 / (len(hs) - 1)) for i in range(len(hs))]
    o.append(f"MENU_N_PEAKS equ {len(hs)}")
    o.append("menu_peaks:")
    for x, h in zip(xs, hs):
        o.append(f"  dw {x}\n  db {hy - h}")
    # the sun: stripes of a half disc, right of the centred text
    sx, r = 336, 20
    stripes = [(sx - round(math.sqrt(r * r - d * d)), sx + round(math.sqrt(r * r - d * d)), hy - d)
               for d in range(2, r, 3)]
    o.append(f"MENU_N_STRIPES equ {len(stripes)}")
    o.append("menu_stripes:")
    for x0, x1, y in stripes:
        o.append(f"  dw {x0}, {x1}\n  db {y}")
    # stars at the sides, clear of the text
    import random
    rng = random.Random(64)
    stars = []
    while len(stars) < 28:
        x, y = rng.randint(4, 379), rng.randint(2, hy - 30)
        if 56 <= x <= 328:
            continue
        stars.append((x, y))
    o.append(f"MENU_N_STARS equ {len(stars)}")
    o.append("menu_stars:")
    for x, y in stars:
        o.append(f"  dw {x}\n  db {y}")


def main():
    out_path = sys.argv[1]
    o = []
    o.append("; generated by tools/gen_tables.py - do not edit")
    o.append(f"LINNER_R equ {R}")
    o.append(f"HUD_ROWS equ {HUD_ROWS}")
    o.append(f"GROUND_DUMMY equ &{GROUND_DUMMY:04X}")
    o.append("")

    # Row address tables, indexed by game y (0..255 -> screen row y+16)
    o.append("  align 256")
    o.append("row_lo:")
    addrs = [row_addr(y + HUD_ROWS) for y in range(256)]
    for i in range(0, 256, 16):
        o.append("  db " + ",".join(f"&{a & 0xFF:02X}" for a in addrs[i:i + 16]))
    o.append("row_hi:")
    for i in range(0, 256, 16):
        o.append("  db " + ",".join(f"&{a >> 8:02X}" for a in addrs[i:i + 16]))

    # Ground rows indexed by the raw height key: 0..126 ground and 128..254
    # water both map to game y 128+(key & 127); 127 and 255 (gap) map to a
    # scratch row so the renderer never has to test for gaps.
    gl = []
    for k in range(256):
        if k & 127 == 127:
            gl.append(GROUND_DUMMY)
        else:
            gl.append(row_addr(GROUND_TOP + (k & 127) + HUD_ROWS))
    o.append("ground_lo:")
    for i in range(0, 256, 16):
        o.append("  db " + ",".join(f"&{a & 0xFF:02X}" for a in gl[i:i + 16]))
    o.append("ground_hi:")
    for i in range(0, 256, 16):
        o.append("  db " + ",".join(f"&{a >> 8:02X}" for a in gl[i:i + 16]))

    # XOR pen bits of a ground pixel by key, one page per pixel phase:
    # ground = pen 1 (bitplane 0), water = pen 2 (bitplane 1), gap = nothing.
    for ph in range(4):
        m = 0x88 >> ph
        o.append(f"ground_pen{ph}:")
        pens = [0 if k & 127 == 127 else (m & (0x0F if k & 0x80 else 0xF0)) for k in range(256)]
        for i in range(0, 256, 16):
            o.append("  db " + ",".join(f"&{v:02X}" for v in pens[i:i + 16]))

    # Ray end point offsets: 256 angle units per turn, y grows downwards so
    # increasing angles turn clockwise on screen (the way Linner rolls).
    o.append("ray_dx:")
    rdx = [round(RAY * math.cos(2 * math.pi * a / 256)) for a in range(256)]
    rdy = [round(RAY * math.sin(2 * math.pi * a / 256)) for a in range(256)]
    for i in range(0, 256, 16):
        o.append("  db " + ",".join(str(v & 0xFF) for v in rdx[i:i + 16]))
    o.append("ray_dy:")
    for i in range(0, 256, 16):
        o.append("  db " + ",".join(str(v & 0xFF) for v in rdy[i:i + 16]))

    # Generic sine table (signed, x127) for aiming and enemy motion later on.
    o.append("sin_tab:")
    st = [round(127 * math.sin(2 * math.pi * a / 256)) for a in range(256)]
    for i in range(0, 256, 16):
        o.append("  db " + ",".join(str(v & 0xFF) for v in st[i:i + 16]))

    # Pixel masks for x & 3 (both bitplanes, i.e. pen 3)
    o.append("pix_mask:")
    o.append("  db &88,&44,&22,&11")

    # Contact profile: for column offsets -R..R, how far below the centre the
    # lowest outline pixel is. Linner rests with every outline pixel strictly
    # above the ground: cy = min(ground_y(cx+dx) - prof[dx]) - 1.
    pts = circle_pixels()
    prof = [max(dy for dx, dy in pts if dx == c) for c in range(-R, R + 1)]
    o.append("contact_prof:")
    o.append("  db " + ",".join(str(p) for p in prof))
    o.append("")
    # The same, compiled: HL -> ring key under the circle's left column.
    # Returns C = min(ground_y - prof) over the 2R+1 columns, 255 if all
    # gaps. Trashes A, HL.
    o.append("contact_scan:")
    o.append("  ld c,255")
    for i, p in enumerate(prof):
        o.append("  ld a,(hl)")
        o.append("  cp &FF")
        o.append(f"  jr z,@cs{i}")
        o.append("  and &7F")
        o.append(f"  add a,{128 - p}")
        o.append("  cp c")
        o.append(f"  jr nc,@cs{i}")
        o.append("  ld c,a")
        o.append(f"@cs{i}:")
        if i != len(prof) - 1:
            o.append("  inc hl")
    o.append("  ret")
    o.append("")

    # Linner's circle: same compiled-XOR scheme, box origin at (cx-R, cy-R)
    sprite(o, "circle", {(x + R, y + R) for x, y in pts})
    o.append("circle_xor_tab equ circle_tab")
    o.append("")

    # The Bureau of Sharp Angles
    sprite(o, "rect", rect_pixels(16, 12))     # by-the-book Rectangle
    sprite(o, "tri", tri_pixels(15, 13))       # edgy Triangle
    sprite(o, "shot", {(0, 0), (1, 0), (0, 1), (1, 1)})

    # Linner phased out: every other pixel of the circle (a ghost)
    sprite(o, "ghost", {(x + R, y + R) for x, y in pts if (x + y) & 1 == 0})
    # Rhombus powerups: a diamond with a bar (Max Speed: across, Phase Out:
    # up and down), the spike trap and the finish post
    W2, H2 = 6, 8
    diamond = (line_pixels(W2, 0, 0, H2) | line_pixels(0, H2, W2, 2 * H2)
               | line_pixels(W2, 2 * H2, 2 * W2, H2) | line_pixels(2 * W2, H2, W2, 0))
    sprite(o, "rhomb_speed", diamond | line_pixels(3, H2, 2 * W2 - 3, H2))
    sprite(o, "rhomb_phase", diamond | line_pixels(W2, 3, W2, 2 * H2 - 3))
    spikes = set()
    for k in range(3):
        spikes |= line_pixels(6 * k, 7, 6 * k + 3, 0) | line_pixels(6 * k + 3, 0, 6 * k + 6, 7)
    sprite(o, "spike", spikes | line_pixels(0, 7, 18, 7))
    post = line_pixels(0, 0, 0, 47) | line_pixels(1, 0, 1, 47)
    flag = line_pixels(2, 0, 13, 5) | line_pixels(13, 5, 2, 10)
    sprite(o, "goal", post | flag)
    font_tables(o)

    # Aiming: 19 angles, 0..180 degrees in 10 degree steps, from straight
    # ahead (0) through straight up (9) to straight behind (18).
    angs = [math.radians(10 * k) for k in range(19)]
    def tab(label, vals, word=False):
        o.append(f"{label}:")
        o.append(("  dw " if word else "  db ") + ",".join(str(v & (0xFFFF if word else 0xFF)) for v in vals))
    tab("aim_x0", [round(13 * math.cos(t)) for t in angs])   # marker / muzzle
    tab("aim_y0", [round(-13 * math.sin(t)) for t in angs])
    tab("aim_x1", [round(17 * math.cos(t)) for t in angs])
    tab("aim_y1", [round(-17 * math.sin(t)) for t in angs])
    tab("shot_vx", [round(SHOT_SPEED * 256 * math.cos(t)) for t in angs], True)
    tab("shot_vy", [round(-SHOT_SPEED * 256 * math.sin(t)) for t in angs], True)
    o.append(f"AIM_STEPS equ {len(angs)}")
    # Shot spacing: fire_shot waits a third of the new shot's flight time
    # (3 slots), so a slot frees about when the next shot is due and the
    # shots come evenly instead of 3 quick ones and a long pause. On screen
    # a shot moves at its aim velocity (the scroll cancels Linner's speed),
    # so the time to the left / right edge is fixed per aim (shot_gap_x,
    # already divided by 3); the time to the top depends on the muzzle's
    # row y0: frames/3 = y0 * shot_gap_y / 256 (0 = never reaches the top).
    HERO_X, SCREEN_W, SHOT_W_ = 3 * R, 384, 2    # src/defs.asm HERO_X
    gx, gy = [], []
    for t in angs:
        vx = SHOT_SPEED * math.cos(t)
        vy = SHOT_SPEED * math.sin(t)
        x0 = HERO_X + round(13 * math.cos(t)) - SHOT_W_ // 2
        if vx > 0.01:
            life = (SCREEN_W - SHOT_W_ - x0) / vx
        elif vx < -0.01:
            life = x0 / -vx
        else:
            life = 765
        gx.append(min(255, round(life / 3)))
        gy.append(0 if vy < 0.01 else min(255, round(256 / (3 * vy))))
    tab("shot_gap_x", gx)
    tab("shot_gap_y", gy)

    # Triangle bobbing: 64 steps of 12*sin
    tab("bob_tab", [round(12 * math.sin(2 * math.pi * i / 64)) for i in range(64)])

    menu_world(o)

    with open(out_path, "w") as f:
        f.write("\n".join(o) + "\n")


if __name__ == "__main__":
    main()
