#!/usr/bin/env python3
"""Convert a level description (levels/*.txt) into Z80 data, checking that
it fits the frame budget.

  level2asm.py out.asm levels/level1.txt [levels/level2.txt ...] [--no-budget]

Each file becomes level1, level2, ... (labels levelN, levelN_foes, ...) and
level_table lists them in order (LEVEL_COUNT entries of LEVEL_ENTRY bytes:
dw segments, foes, goal, time (BCD), name; db start key, 0).

Text format, one segment per line ('#' starts a comment):

  name TEXT                 the level's name ("LEVEL 2: TEXT"; capitals,
                            digits, space ! - . : only, 16 at most)
  start ALT                 starting ground altitude
  time SECONDS              the level's time limit (default 60)
  LEN ALT TYPE              ground runs LEN pixels to altitude ALT
  foe X rect                a Rectangle whose left edge starts X pixels into
                            the level (it marches on the ground)
  foe X tri ALT             a Triangle bobbing around altitude ALT (same
                            scale as the ground, may go up to 240)
  item X speed ALT          a Rhombus: Max Speed (gear 5 for 20 s)
  item X phase ALT          a Rhombus: Phase Out (a ghost for 10 s)
  trap X spikes             spikes on the Line

The finish post stands at the end of the last segment; after it the Line
runs on flat (the level ends when Linner passes the post).

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
(1 Rectangle, 2 Triangle, 4/5 Rhombus, 6 spikes, 7 finish post; param = top
row of a bobbing thing's centre), LABEL_length, LABEL_goal (the finish x)
and LABEL_time (the time limit in BCD).
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
ITEMS = {"speed": 4, "phase": 5}
TRAPS = {"spikes": 6}
GOAL = 7
TRI_H = 13
RHOMB_H = 17


JUMP_VY = 5.0           # rows per frame up at take-off (hero.asm)
GRAVITY = 0.25
GEAR_SPEEDS = [1.0, 1.5, 2.0, 2.75, 3.5]
GEAR_NORMAL = 4         # gear 5 needs the Max Speed Rhombus
LAND_ROOM = 80          # px from a gap/water edge where jumps land
JUMP_TOP = 72            # a full jump's top above the ground (50 + 2 r + slack)
GAP_EDGE = 8            # Linner (r 10) still stands on an edge with his centre
                        # this far past it: a jump may be this much shorter
FAST_PX = 3000          # how far a Max Speed Rhombus reaches (20 s at gear 5, minus slack)
FONT = set(" !-.:0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ")


def parse(src):
    start = None
    time = 60
    name = ""
    segs = []
    foes = []
    for n, line in enumerate(open(src), 1):
        line = line.split("#")[0].split()
        if not line:
            continue
        where = f"{src}:{n}"
        if line[0] == "name":
            name = " ".join(line[1:]).upper()
            if len(name) > 16 or not set(name) <= FONT:
                sys.exit(f"{where}: name: 16 characters at most, A-Z 0-9 space ! - . :")
            continue
        if line[0] == "start":
            start = int(line[1])
            continue
        if line[0] == "time":
            time = int(line[1])
            if not 1 <= time <= 999:
                sys.exit(f"{where}: time must be 1..999 seconds")
            continue
        if line[0] == "item":
            x, kind, alt = int(line[1]), line[2], int(line[3])
            if kind not in ITEMS:
                sys.exit(f"{where}: unknown item {kind}")
            foes.append((x, ITEMS[kind], 254 - alt - RHOMB_H // 2, where))
            continue
        if line[0] == "trap":
            x, kind = int(line[1]), line[2]
            if kind not in TRAPS:
                sys.exit(f"{where}: unknown trap {kind}")
            foes.append((x, TRAPS[kind], 0, where))
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
    return name, start, time, segs, sorted(foes)


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
    return keys, where, out


def check(keys, where):
    # rows of consecutive ground columns must stay connected
    n = len(keys)
    for i in range(n):
        a, b = keys[i - 1], keys[i]
        if a != 0xFF and b != 0xFF and abs((a & 127) - (b & 127)) > 1:
            sys.exit(f"{where[i]}: the generated line jumps {abs((a & 127) - (b & 127))} rows")
    # per-window change budget; after the end the Line runs on flat
    ext = keys + [keys[-1]] * (SCREEN_W + SCROLL_MAX)
    changed = [1 if ext[i] != ext[i - SCROLL_MAX] else 0 for i in range(len(ext))]
    win = sum(changed[SCROLL_MAX:SCROLL_MAX + SCREEN_W])
    worst, worst_at = win, 0
    for s in range(1, n):
        win += changed[s + SCROLL_MAX + SCREEN_W - 1] - changed[s + SCROLL_MAX - 1]
        if win > worst:
            worst, worst_at = win, s
    return worst, worst_at


def air_time(rise):
    """Frames from take-off until a full jump comes down to `rise` rows above
    where it started (None if it never gets that high)."""
    y, vy, t = 0.0, -JUMP_VY, 0
    top = False
    while t < 200:
        y += vy
        vy += GRAVITY
        t += 1
        if vy > 0:
            top = True
        if top and -y <= rise:
            return t
    return None


WATER_DRAG = 8 / 256    # hero.asm: speed lost per frame on water...
WATER_MIN = 0.5         # ... down to this
SOGGY_MAX = 80          # frames on water before he sinks
MAX_THINGS = 6          # object slots for foes, items and traps
THING_SPAN = 450        # px a thing stays alive around the screen


def water_reach(v, jump):
    """How far onto water Linner gets at speed v before sinking, rolling in
    (or jumping in from the edge first)."""
    d = v * 40 - GAP_EDGE if jump else 0
    for _ in range(SOGGY_MAX):
        v = max(WATER_MIN, v - WATER_DRAG)
        d += v
    return d


def gaps(segs, start, foes, src):
    """The gear each gap needs (a full jump taken at the last moment must
    reach the far edge). Gear 5 needs a Max Speed Rhombus
    not too far before the gap."""
    x, cur, need = 0, start, []
    speed_items = [f[0] for f in foes if f[1] == ITEMS["speed"]]
    for i, (ln, alt, typ, w) in enumerate(segs):
        if typ == "water":
            gear = next((g for g, v in enumerate(GEAR_SPEEDS, 1)
                         if water_reach(v, True) >= ln), None)
            if gear is None or gear > GEAR_NORMAL:
                sys.exit(f"{w}: {ln} px of water: too long to cross")
            need.append((x, ln, gear))
        if typ == "gap":
            after = segs[i + 1][1] if i + 1 < len(segs) else alt
            t = air_time(after - cur)
            gear = None
            if t:
                for g, v in enumerate(GEAR_SPEEDS, 1):
                    if v * t >= ln - GAP_EDGE:
                        gear = g
                        break
            if gear is None:
                sys.exit(f"{w}: a {ln} px gap rising {after - cur} rows can't be jumped")
            if gear > GEAR_NORMAL and not any(0 < x - s <= FAST_PX for s in speed_items):
                sys.exit(f"{w}: this gap needs gear 5: put a speed Rhombus before it")
            need.append((x, ln, gear))
        x += ln
        cur = alt
    return need


# Frame cost of a screen, fitted on the simulator (tools/cpcsim.py --slow
# 1.25, all six levels): a loop takes ~COST_BASE us, plus COST_COL per
# changing ground column, COST_THING per foe/item/trap alive and COST_SHOT per
# shot in flight (counted as all MAX_SHOTS: the fire button held). The
# worst screen at top speed must leave COST_MARGIN of the 19968 us frame.
COST_BASE, COST_COL, COST_THING, COST_SHOT = 4541, 74, 1389, 899
MAX_SHOTS = 3
FRAME_US = 19968
COST_MARGIN = 1500


def frame_cost(keys, foes):
    """Worst predicted loop time over the level: (us, scroll x, columns,
    things). A thing is alive from 384 px ahead until 40 px off the left."""
    ext = keys + [keys[-1]] * (SCREEN_W + SCROLL_MAX)
    pre = [0]
    for i in range(len(ext)):
        pre.append(pre[-1] + (1 if i >= SCROLL_MAX and ext[i] != ext[i - SCROLL_MAX] else 0))
    xs = sorted([f[0] for f in foes] + [len(keys) - 2])
    worst = (0, 0, 0, 0)
    for s in range(0, len(keys), 2):
        cols = pre[s + SCREEN_W] - pre[s]
        things = sum(1 for x in xs if s - 40 <= x < s + SCREEN_W)
        us = COST_BASE + COST_COL * cols + COST_THING * things + COST_SHOT * MAX_SHOTS
        if us > worst[0]:
            worst = (us, s, cols, things)
    return worst


def fairness(keys, foes):
    """Spots where a foe makes a jump unfair (warnings, not errors).
    A Triangle drifts left at 1 px/frame from the moment it spawns (screen
    x 384, Linner at 96), so it meets Linner ~70..120 px before its x: a
    gap, water or spikes there means jumping into it. A Rectangle patrols
    its whole stretch of ground: spikes on the same stretch, or a landing
    right at its edge, leave no room."""
    bad = lambda k: k == 0xFF or k & 0x80
    spikes = [f[0] for f in foes if f[1] == TRAPS["spikes"]]
    out = []
    for x, typ, param, w in foes:
        if not 0 <= x < len(keys):
            continue                    # (reported elsewhere)
        if typ == FOES["tri"]:
            lo, hi = max(0, x - 125), max(0, x - 65)
            low = 254 - param - TRI_H // 2 - 12         # its lowest altitude
            ground = [MAX_ALT - (k & 127) for k in keys[lo:hi] if k != 0xFF]
            reach = max(ground, default=0) + JUMP_TOP   # a full jump's top
            if low < reach and (any(bad(k) for k in keys[lo:hi])
                                or any(lo - 19 < sx < hi for sx in spikes)):
                out.append(f"{w}: the Triangle meets Linner around x={lo}..{hi}, "
                           f"where he has to jump")
        if typ == FOES["rect"]:
            a = x
            while a > 0 and not bad(keys[a - 1]):
                a -= 1
            b = x
            while b < len(keys) and not bad(keys[b]):
                b += 1
            if any(a <= sx < b and abs(sx - x) < 160 for sx in spikes):
                out.append(f"{w}: the Rectangle patrols {a}..{b}, spikes included")
            if b - a < 120:
                out.append(f"{w}: the Rectangle's stretch {a}..{b} is short: "
                           f"no room to land")
            elif (x - a < LAND_ROOM and a > 0) or b - (x + 16) < LAND_ROOM:
                out.append(f"{w}: the Rectangle starts where a jump lands")
        if typ == TRAPS["spikes"]:
            a = x
            while a > 0 and not bad(keys[a - 1]):
                a -= 1
            if a > 0 and x - a < LAND_ROOM:
                out.append(f"{w}: spikes {x - a} px after a gap or water: "
                           f"a jump lands on them")
    return out


def level(src, label, budget, o):
    name, start, time, segs, foes = parse(src)
    keys, where, data = generate(start, segs)
    worst, at = check(keys, where)
    need = gaps(segs, start, foes, src)
    for x, typ, _, w in foes:       # Rectangles and spikes stand on ground
        width = {FOES["rect"]: 16, TRAPS["spikes"]: 19}.get(typ)
        if width and any(k == 0xFF or k & 0x80 for k in keys[x:x + width]):
            sys.exit(f"{w}: x={x} puts it over a gap or water")
    for msg in fairness(keys, foes):
        print(f"  warning: {msg}")
    us, cs, ccols, cthings = frame_cost(keys, foes)
    if budget and us > FRAME_US - COST_MARGIN:
        sys.exit(f"{src}: the screen at scroll x={cs} ({ccols} changing columns, "
                 f"{cthings} foes/items/traps) would take ~{us} us a frame (limit "
                 f"{FRAME_US - COST_MARGIN}): fewer things there, or gentler slopes")
    xs = sorted(f[0] for f in foes) + [len(keys) - 2]
    for i in range(len(xs)):
        if sum(1 for x in xs[i:] if x - xs[i] < THING_SPAN) > MAX_THINGS:
            sys.exit(f"{src}: more than {MAX_THINGS} foes/items/traps within "
                     f"{THING_SPAN} px of x={xs[i]}: some would never appear")
    top = min(max([g for _, _, g in need], default=1), GEAR_NORMAL)
    pace = max(top, 3)              # the gear a player needs anyway, at least 3
    secs = len(keys) / (GEAR_SPEEDS[pace - 1] * 50)
    report = (f"{src}: \"{name}\", {len(keys)} px, time {time} s (~{secs:.0f} s at gear "
              f"{pace}), gaps/water need gear {[g for _, _, g in need]}; worst screen at "
              f"x={at} ({where[at]}): {worst} changing columns (budget {MAX_CHANGED}); "
              f"busiest frame ~{us} us")
    if budget and worst > MAX_CHANGED:
        sys.exit(report + f"\n  over budget ({MAX_CHANGED}): use gentler or shorter slopes there")
    if time < secs * 1.3:
        sys.exit(report + "\n  the time limit is too tight")
    print(report)

    o += [f"; {label}: generated from {src}",
          f"; worst screen: {worst} changing columns at top speed",
          f"{label}_start_key equ {key(start)}",
          f"{label}_name: db \"{name}\",0",
          f"{label}:"]
    for ln, typ, slope, kend in data:
        o.append(f"  db {ln},&{typ:02X}\n  dw {slope & 0xFFFF}\n  db {kend}")
    o.append("  db 0")
    o.append(f"; {len(data)} segments, {len(keys)} pixels")
    o.append(f"{label}_length equ {len(keys)}")
    o.append(f"{label}_goal equ {len(keys)}")
    o.append(f"{label}_time equ &{time:04d}")
    foes.append((len(keys) - 2, GOAL, 0, src))      # the finish post
    foes.sort()
    o.append(f"{label}_foes:")
    for x, typ, param, w in foes:
        if not 0 <= x <= len(keys):
            sys.exit(f"{w}: foe outside the level (0..{len(keys) - 1})")
        o.append(f"  dw {x}\n  db {typ},{param}")
    o.append("  dw &FFFF")


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    budget = "--no-budget" not in sys.argv
    out_path, srcs = args[0], args[1:]
    o = ["; generated by tools/level2asm.py - do not edit"]
    labels = [f"level{i}" for i in range(1, len(srcs) + 1)]
    for src, label in zip(srcs, labels):
        level(src, label, budget, o)
    o += [f"LEVEL_COUNT equ {len(srcs)}", "LEVEL_ENTRY equ 12", "level_table:"]
    for label in labels:
        o.append(f"  dw {label}, {label}_foes, {label}_goal, {label}_time, {label}_name")
        o.append(f"  db {label}_start_key, 0")
    with open(out_path, "w") as f:
        f.write("\n".join(o) + "\n")


if __name__ == "__main__":
    main()
