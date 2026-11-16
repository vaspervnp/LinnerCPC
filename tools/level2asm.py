#!/usr/bin/env python3
"""Convert a level description (levels/*.txt) into Z80 data, checking that
it fits the frame budget.

  level2asm.py levels/level1.txt label out.asm [--no-budget]

Text format, one segment per line ('#' starts a comment):

  start ALT                 starting ground altitude
  LEN ALT TYPE              ground runs LEN pixels to altitude ALT
  foe X rect                a Rectangle whose left edge starts X pixels into
                            the level (it marches on the ground)
  foe X tri ALT             a Triangle bobbing around altitude ALT (same
                            scale as the ground, may go up to 240)

ALT is the altitude of the ground line in pixels above its lowest position
(0..126; screen row = 270 - ALT). TYPE is ground, water or gap. Slopes are
limited to 45 degrees (|change in ALT| <= LEN) so the line drawn one pixel
per column stays connected. The level loops, so the last segment must end
at the start altitude.

Slope budget: the ground renderer only touches columns whose height changed
since the last frame, at ~55 NOPs each (an unchanged column costs ~11). At
top speed the screen scrolls up to SCROLL_MAX pixels per frame, and a column
changes when the ground under it differs from the ground SCROLL_MAX pixels
further on. The tool replays the Z80's terrain generator exactly and checks
that no screen-wide window (384 columns) has more than MAX_CHANGED changing
columns. A slope that climbs or drops DY rows over LEN pixels changes about
min(LEN, SCROLL_MAX x DY) columns, so short steep ramps between flats are
cheap and long slopes or big height changes on one screen are not.
--no-budget skips the check (benchmarks).

Output, 5 bytes per segment, terminated by a 0 length:
  db len, type          type: &00 ground, &80 water, &FF gap
  dw slope              signed 8.8 change of the height key per pixel
  db key_end            height key at the end (0 = highest, 126 = lowest)
then LABEL_foes: (dw x, db type, db param) sorted by x, ended by dw &FFFF
(type 1 Rectangle, 2 Triangle with param = top row of its bob centre), and
LABEL_length = the level's length in pixels (it loops).
"""
import sys

TYPES = {"ground": 0x00, "water": 0x80, "gap": 0xFF}
MAX_ALT = 126
SCREEN_W = 384
SCROLL_MAX = 4          # pixels per frame at gear 5 (3.5 -> steps of 3 and 4)
MAX_CHANGED = 120       # ~6.5K NOPs of changed columns; objects need the rest


def key(alt):
    return MAX_ALT - alt


FOES = {"rect": 1, "tri": 2}
TRI_H = 13


def parse(src):
    start = None
    segs = []
    foes = []
    for n, line in enumerate(open(src), 1):
        line = line.split("#")[0].split()
        if not line:
            continue
        where = f"{src}:{n}"
        if line[0] == "start":
            start = int(line[1])
            continue
        if line[0] == "foe":
            x, kind = int(line[1]), line[2]
            if kind not in FOES:
                sys.exit(f"{where}: unknown foe {kind}")
            param = 0
            if kind == "tri":
                alt = int(line[3])
                if not 0 <= alt <= 240:
                    sys.exit(f"{where}: altitude must be 0..240")
                param = 254 - alt - TRI_H // 2
            foes.append((x, FOES[kind], param, where))
            continue
        ln, alt, typ = int(line[0]), int(line[1]), line[2]
        if not 1 <= ln <= 255:
            sys.exit(f"{where}: length must be 1..255")
        if not 0 <= alt <= MAX_ALT:
            sys.exit(f"{where}: altitude must be 0..{MAX_ALT}")
        if typ not in TYPES:
            sys.exit(f"{where}: unknown type {typ}")
        segs.append((ln, alt, typ, where))
    if start is None or not segs:
        sys.exit(f"{src}: needs a start line and at least one segment")
    return start, segs, sorted(foes)


def generate(start, segs):
    """Replay src/terrain.asm gen_column: the key of every world column, and
    the source line each column comes from."""
    keys, where = [], []
    y = key(start) << 8 | 0x80      # segments start half a row in: keys round
    cur = start
    out = []
    for ln, alt, typ, w in segs:
        if abs(alt - cur) > ln:
            sys.exit(f"{w}: slope steeper than 45 degrees")
        slope = round((key(alt) - key(cur)) * 256 / ln)
        out.append((ln, TYPES[typ], slope, key(alt)))
        for _ in range(ln):
            k = y >> 8
            keys.append(0xFF if typ == "gap" else k | TYPES[typ])
            where.append(w)
            y = (y + slope) & 0xFFFF
        y = key(alt) << 8 | 0x80
        cur = alt
    if cur != start:
        sys.exit(f"level loops, so it must end at altitude {start} (ends at {cur})")
    return keys, where, out


def check(keys, where):
    # rows of consecutive ground columns must stay connected
    n = len(keys)
    for i in range(n):
        a, b = keys[i - 1], keys[i]
        if a != 0xFF and b != 0xFF and abs((a & 127) - (b & 127)) > 1:
            sys.exit(f"{where[i]}: the generated line jumps {abs((a & 127) - (b & 127))} rows")
    # per-window change budget (the level loops, so wrap around)
    ext = keys * (2 + (SCREEN_W + SCROLL_MAX) // n)
    changed = [1 if ext[i] != ext[i - SCROLL_MAX] else 0 for i in range(len(ext))]
    win = sum(changed[SCROLL_MAX:SCROLL_MAX + SCREEN_W])
    worst, worst_at = win, 0
    for s in range(1, n):
        win += changed[s + SCROLL_MAX + SCREEN_W - 1] - changed[s + SCROLL_MAX - 1]
        if win > worst:
            worst, worst_at = win, s
    return worst, worst_at


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    budget = "--no-budget" not in sys.argv
    src, label, out_path = args[:3]
    start, segs, foes = parse(src)
    keys, where, data = generate(start, segs)
    worst, at = check(keys, where)
    est = 7700 + worst * 54
    report = (f"{src}: {len(keys)} px, worst screen at x={at} ({where[at]}): "
              f"{worst} changing columns at top speed, ~{est} us per frame")
    if budget and worst > MAX_CHANGED:
        sys.exit(report + f"\n  over budget ({MAX_CHANGED}): use gentler or shorter slopes there")
    print(report)

    o = [f"; generated by tools/level2asm.py from {src} - do not edit",
         f"; worst screen: {worst} changing columns at top speed",
         f"{label}_start_key equ {key(start)}", f"{label}:"]
    for ln, typ, slope, kend in data:
        o.append(f"  db {ln},&{typ:02X}\n  dw {slope & 0xFFFF}\n  db {kend}")
    o.append("  db 0")
    o.append(f"; {len(data)} segments, {len(keys)} pixels")
    o.append(f"{label}_length equ {len(keys)}")
    o.append(f"{label}_foes:")
    for x, typ, param, w in foes:
        if not 0 <= x < len(keys):
            sys.exit(f"{w}: foe outside the level (0..{len(keys) - 1})")
        o.append(f"  dw {x}\n  db {typ},{param}")
    o.append("  dw &FFFF")
    with open(out_path, "w") as f:
        f.write("\n".join(o) + "\n")


if __name__ == "__main__":
    main()
