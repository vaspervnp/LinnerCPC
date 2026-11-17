#!/usr/bin/env python3
"""Convert a level description (levels/*.txt) into Z80 data, checking that
it fits the frame budget.

  level2asm.py out.asm levels/level1.txt [levels/level2.txt ...] [--no-budget]

Each file becomes level1, level2, ... (labels levelN, levelN_foes, ...) and
level_table lists them in order (LEVEL_COUNT entries of LEVEL_ENTRY bytes:
dw segments, foes, goal, time easy / medium / hard (BCD), name, waypoints;
db start key, waypoint count). The level's `time` is for hard; easy and
medium run the world at DIFFICULTY of its speed and get time / factor.

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
  item X speed ALT [SECS]   a Rhombus: Max Speed (gear 5 for SECS seconds,
                            3..8, default 5)
  item X phase ALT [SECS]   a Rhombus: Phase Out (a ghost for SECS seconds)
  trap X spikes             spikes on the Line

The finish post stands at the end of the last segment; after it the Line
runs on flat (the level ends when Linner passes the post).

ALT is the altitude of the ground line in pixels above its lowest position
(0..126; screen row = 270 - ALT). TYPE is ground, water or gap. Slopes are
limited to 45 degrees (|change in ALT| <= LEN) so the line drawn one pixel
per column stays connected.

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

Output (compact: the levels are long and memory is short), per segment:
  db len, key           ground: key = height key at the end (0 = highest,
                        126 = lowest); water: &80 + key
  db len, &FF, key      a gap, and the height key after it
terminated by a 0 length. The Z80 works out each slope when the segment
starts: round((key_end - key_now) * 256 / len), as generate() does here.
Then LABEL_foes, sorted by x: db dx, tb [, param] where dx is the distance
from the previous record (records with tb = 0 are just steps of 255 px),
tb = type (1 Rectangle, 2 Triangle, 4/5 Rhombus, 6 spikes, 7 finish post)
+ 16 x seconds (Rhombus), and param (Triangle, Rhombus only) = the top row
of its bobbing centre; ended by db 0,&FF. Also LABEL_length, LABEL_goal
(the finish x) and LABEL_time (the time limit in BCD).

Waypoints (the user asked: at least 3, more on longer levels): the tool
places max(3, round(length / WAY_EVERY)) of them as evenly as it can, each
where a restart in gear 1 is safe: at a segment start or inside a flat
segment (split there, which generates the same keys), no gap or water just
ahead, room to reach the gear the next gap or water needs, not between a
Max Speed Rhombus and the chasm it is for (the boost ends with the life),
and the post's screens within the frame budget. A restart skips the things
less than WAY_CLEAR px ahead of it (its foe pointer starts after them).
LABEL_ways: per waypoint
  dw segment, db key, dw scroll x, dw foe record, dw x before it, dw pass x
(WAY_SIZE bytes): the generator, spawn and scroll state to restart from,
and the x where Linner passes its post (a T_WAY thing in the foe list).
"""
import sys

TYPES = {"ground": 0x00, "water": 0x80, "gap": 0xFF}
MAX_ALT = 126
SCREEN_W = 384
SCROLL_MAX = 5          # pixels per frame at gear 4 (4.81 -> steps of 4 and 5);
                        # gear 5 (7 px) may drop a frame (the user allows it)
MAX_CHANGED = 120       # ~6.5K NOPs of changed columns; objects need the rest


def key(alt):
    return MAX_ALT - alt


FOES = {"rect": 1, "tri": 2}
ITEMS = {"speed": 4, "phase": 5}
TRAPS = {"spikes": 6}
GOAL = 7
WAY = 8                 # a waypoint post (added by the tool)
TRI_H = 13
RHOMB_H = 17


JUMP_VY = 5.0           # rows per frame up at take-off (hero.asm)
GRAVITY = 0.25
GEAR_SPEEDS = [1.0, 1.875, 3.0, 4.8125, 7.0]   # hero.asm gear_speed
GEAR_NORMAL = 4         # gear 5 needs the Max Speed Rhombus
LAND_ROOM = 80          # px from a gap/water edge where jumps land
JUMP_TOP = 72            # a full jump's top above the ground (50 + 2 r + slack)
GAP_EDGE = 8            # Linner (r 10) still stands on an edge with his centre
                        # this far past it: a jump may be this much shorter
POWER_SECS = (3, 8)     # how long a Rhombus lasts, seconds
POWER_DEFAULT = 5
FONT = set(" !-.:0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ")


def parse(src):
    return parse_text(open(src).read(), src)


def parse_text(text, src):
    start = None
    time = 60
    name = ""
    segs = []
    foes = []
    for n, line in enumerate(text.splitlines(), 1):
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
            secs = int(line[4]) if len(line) > 4 else POWER_DEFAULT
            if kind not in ITEMS:
                sys.exit(f"{where}: unknown item {kind}")
            if not POWER_SECS[0] <= secs <= POWER_SECS[1]:
                sys.exit(f"{where}: a Rhombus lasts {POWER_SECS[0]}..{POWER_SECS[1]} seconds")
            foes.append((x, ITEMS[kind] | secs << 4, 254 - alt - RHOMB_H // 2, where))
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
        d = key(alt) - key(cur)         # seg_load: |d| * 256 + len / 2, / len
        slope = 0 if typ == "gap" else (1 if d >= 0 else -1) * ((abs(d) * 256 + ln // 2) // ln)
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


DEBUG_SPOTS = False
PLACE_WAYS = True       # levelgen.py turns it off while a level grows
WAY_EVERY = 3500        # px of level per waypoint (at least 3)
WAY_CLEAR = 250         # a restart skips the things this far ahead of it
WAY_POST = 14           # the post stands this far ahead of the restart x
WAY_SIZE = 11
ACCEL = 12 / 256        # hero.asm: speed gained per frame
DIFFICULTY = (0.6, 0.8, 1.0)    # easy, medium, hard: the world's speed


def run_up(gear):
    """Pixels from a standstill in gear 1 to the gear's speed, shifting
    up at once (RIGHT), plus some slack."""
    v = GEAR_SPEEDS[gear - 1]
    return (v * v - 1) / (2 * ACCEL) + 60


def waypoints(segs, start, keys, foes, need, src):
    """Pick the waypoints: [(segment index, offset into it, restart x)]."""
    n = max(3, round(len(keys) / WAY_EVERY))
    bad = lambda k: k == 0xFF or k & 0x80
    boosts = [(f[0], f[1] >> 4) for f in foes if f[1] & 15 == ITEMS["speed"]]
    chasms = [gx for gx, _, gear in need if gear > GEAR_NORMAL]
    # a restart between a Max Speed Rhombus and its chasm has no boost
    no_go = [(sx - 100, gx) for sx, secs in boosts for gx in chasms
             if sx < gx <= sx + fast_reach(secs)]
    flats, x, cur = [], 0, start    # (x, segment, length a restart may split)
    for i, (ln, alt, typ, w) in enumerate(segs):
        if typ == "ground":         # flat: anywhere; a slope: at its start
            flats.append((x, i, ln if alt == cur else 1))
        x += ln
        cur = alt
    things = sorted([f[0] for f in foes] + [len(keys) - 2])
    ext = keys + [keys[-1]] * (SCREEN_W + SCROLL_MAX)
    pre = [0]
    for i in range(len(ext)):
        pre.append(pre[-1] + (1 if i >= SCROLL_MAX and ext[i] != ext[i - SCROLL_MAX] else 0))

    def cheap(px):                  # the post's screens stay in the budget
        for s in range(max(0, px - SCREEN_W) & ~1, min(len(keys), px + 41), 2):
            n_things = 1 + sum(1 for x in things if s - 40 <= x < s + SCREEN_W)
            us = (COST_BASE + COST_COL * (pre[s + SCREEN_W] - pre[s])
                  + COST_THING * n_things + COST_SHOT * MAX_SHOTS)
            if us > FRAME_US - COST_MARGIN or n_things > MAX_THINGS:
                return False
        return True

    def ok(p):                      # p = scroll x at the restart
        w = p + HERO_X
        if p < 600 or p > len(keys) - 1500:
            return False
        if any(a <= w <= b for a, b in no_go):
            return False
        for gx, ln, gear in need:   # the first gap / water ahead
            if gx + ln > w:
                if gx - w < run_up(min(gear, GEAR_NORMAL)):
                    return False
                break
        return not any(bad(k) for k in keys[p:w + 120]) and cheap(w + WAY_POST)

    spots = []                      # every safe restart, 16 px apart
    for x0, i, ln in flats:
        for off in range(0, ln, 16):
            if ok(x0 + off):
                spots.append((x0 + off, i, off))
    if DEBUG_SPOTS: print('SPOTS', [p for p,_,_ in spots])
    # choose n of them so that the runs between waypoints (and from the
    # start / to the finish) are as even as possible: least sum of squares
    INF = 10 ** 18
    m = len(spots)
    best = [[(INF, -1, 0)] * m for _ in range(n + 1)]    # (cost, prev, longest)
    for j, (p, _, _) in enumerate(spots):
        best[1][j] = (p * p, -1, p)
    for k in range(2, n + 1):
        for j, (p, _, _) in enumerate(spots):
            for i in range(j):
                q = spots[i][0]
                c = best[k - 1][i]
                if p - q < 1000 or c[0] >= INF:
                    continue
                v = c[0] + (p - q) ** 2
                if v < best[k][j][0]:
                    best[k][j] = (v, i, max(c[2], p - q))
    end = min(((best[n][j][0] + (len(keys) - spots[j][0]) ** 2,
                max(best[n][j][2], len(keys) - spots[j][0]), j) for j in range(m)
               if best[n][j][0] < INF), default=None)
    end = end and (end[1], end[2])
    limit = len(keys) * 8 // (5 * (n + 1))
    if end is None or end[0] > limit:
        sys.exit(f"{src}: can't place {n} waypoints at most {limit} px apart "
                 f"(ground, room to speed up, frame budget): {'longest run ' + str(end[0]) if end else 'too few safe spots'}")
    out, j, k = [], end[1], n
    while k:
        p, i, off = spots[j]
        out.append((i, off, p))
        j = best[k][j][1]
        k -= 1
    out.reverse()
    return out


def fast_reach(secs):
    """How far past a Max Speed Rhombus Linner still lands a gear-5 jump:
    ~47 frames from gear 4 up to 7 px/frame (~276 px, ACCEL 12/256), then
    7 px/frame until the boost runs out, minus some slack for the landing."""
    return 276 + 7.0 * (secs * 50 - 47) - 40


def gaps(segs, start, foes, src):
    """The gear each gap needs (a full jump taken at the last moment must
    reach the far edge). Gear 5 needs a Max Speed Rhombus
    not too far before the gap. Consecutive gap (or water) segments are
    one stretch: a segment holds 255 px at most."""
    x, cur, need = 0, start, []
    speed_items = [(f[0], f[1] >> 4) for f in foes if f[1] & 15 == ITEMS["speed"]]
    i = 0
    while i < len(segs):
        ln, alt, typ, w = segs[i]
        j = i + 1
        if typ in ("water", "gap"):
            while j < len(segs) and segs[j][2] == typ:
                ln += segs[j][0]
                alt = segs[j][1]
                j += 1
        if typ == "water":
            gear = next((g for g, v in enumerate(GEAR_SPEEDS, 1)
                         if water_reach(v, True) >= ln), None)
            if gear is None or gear > GEAR_NORMAL:
                sys.exit(f"{w}: {ln} px of water: too long to cross")
            need.append((x, ln, gear))
        if typ == "gap":
            after = segs[j][1] if j < len(segs) else alt
            t = air_time(after - cur)
            gear = None
            if t:
                for g, v in enumerate(GEAR_SPEEDS, 1):
                    if v * t >= ln - GAP_EDGE:
                        gear = g
                        break
            if gear is None:
                sys.exit(f"{w}: a {ln} px gap rising {after - cur} rows can't be jumped")
            if gear > GEAR_NORMAL and not any(0 < x + ln - s <= fast_reach(secs)
                                              for s, secs in speed_items):
                sys.exit(f"{w}: this gap needs gear 5: put a speed Rhombus before it, "
                         f"close enough to land before the boost ends")
            need.append((x, ln, gear))
        x += ln
        cur = alt
        i = j
    return need


# Frame cost of a screen, fitted on the simulator (tools/cpcsim.py --slow
# 1.25, all six levels): a loop takes ~COST_BASE us, plus COST_COL per
# changing ground column, COST_THING per foe/item/trap alive and COST_SHOT per
# shot in flight (counted as all MAX_SHOTS: the fire button held). The
# worst screen at top speed must leave COST_MARGIN of the 19968 us frame.
# The sound (sound.asm, from the interrupt) adds ~600 us to a busy frame:
# SOUND_US on top of the fitted base.
SOUND_US = 600
COST_BASE, COST_COL, COST_THING, COST_SHOT = 4541 + SOUND_US, 74, 1389, 899
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


# A Triangle drifts 1 px/frame towards Linner from the moment it appears
# (AHEAD px ahead of him: screen x 384, Linner at HERO_X), so they meet
# AHEAD / (v + 1) px before its x: for a cruise in gear 3..4, with some slack.
HERO_X = 30                     # src/defs.asm
AHEAD = SCREEN_W - HERO_X
MEET = (int(AHEAD / (GEAR_SPEEDS[3] + 1)) - 15, int(AHEAD / (GEAR_SPEEDS[2] + 1)) + 15)


def landings(keys, where, foes=()):
    """A full jump over a gap or water, taken at the last moment in gear 4
    (the cruise: the gears climb by themselves; gear 5 for a chasm only Max
    Speed clears), must come down on dry ground, not in the next gap or
    water."""
    bad = lambda k: k == 0xFF or k & 0x80
    v = GEAR_SPEEDS[GEAR_NORMAL - 1]
    x = 1
    while x < len(keys):
        if bad(keys[x]) and not bad(keys[x - 1]):
            start = x
            while x < len(keys) and bad(keys[x]):
                x += 1
            rise = (keys[start - 1] & 127) - (keys[min(x, len(keys) - 1)] & 127)
            t = air_time(rise)
            if t:
                w = x - start           # a chasm beyond gear 4: Max Speed's jump
                vv = v if v * t >= w - GAP_EDGE else GEAR_SPEEDS[-1]
                land = start - 4 + int(vv * t)
                pre = (f"{where[start]}: a full jump in gear 4 over the stretch at "
                       f"x={start} comes down at x={land}")
                if land < len(keys) and any(bad(k) for k in keys[land - 10:land + 10]):
                    sys.exit(pre + ", in a gap or water")
                for fx, typ, param, _ in foes:
                    typ &= 15
                    if typ == TRAPS["spikes"] and land - 30 < fx < land + 20:
                        sys.exit(pre + f", on the spikes at x={fx}")
                    # a Rectangle marches ~25 px towards him before they meet
                    if typ == FOES["rect"] and land - 30 < fx - 25 < land + 30:
                        sys.exit(pre + f", on the Rectangle at x={fx}")
                    if typ == FOES["tri"]:
                        low = 254 - param - TRI_H // 2 - 12
                        reach = MAX_ALT - (keys[start - 1] & 127) + JUMP_TOP
                        if low < reach and fx - MEET[1] < land + 20 and fx - MEET[0] > start - 4:
                            sys.exit(pre + f", the Triangle at x={fx} meets him in the air")
        x += 1


def fairness(keys, foes):
    """Spots where a foe makes a jump unfair (warnings, not errors).
    A Triangle drifts left at 1 px/frame from the moment it spawns (screen
    x 384, Linner at HERO_X), so it meets Linner MEET px before its x: a
    gap, water or spikes there means jumping into it. A Rectangle patrols
    its whole stretch of ground: spikes on the same stretch, or a landing
    right at its edge, leave no room."""
    bad = lambda k: k == 0xFF or k & 0x80
    spikes = [f[0] for f in foes if f[1] == TRAPS["spikes"]]
    out = []
    for x, typ, param, w in foes:
        if not 0 <= x < len(keys):
            continue                    # (reported elsewhere)
        typ &= 15
        if typ == FOES["tri"]:
            lo, hi = max(0, x - MEET[1]), max(0, x - MEET[0])
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


def level(src, label, budget, o, text=None):
    name, start, time, segs, foes = parse(src) if text is None else parse_text(text, src)
    keys, where, data = generate(start, segs)
    worst, at = check(keys, where)
    need = gaps(segs, start, foes, src)
    landings(keys, where, foes)
    ways = waypoints(segs, start, keys, foes, need, src) if PLACE_WAYS else []
    labels = {}                     # split the flat segments at the waypoints
    for i, off, p in sorted(ways, reverse=True):
        ln, alt, typ, w = segs[i]
        if off:
            segs[i:i + 1] = [(off, alt, typ, w), (ln - off, alt, typ, w)]
    x = 0
    starts = {}
    for i, s in enumerate(segs):
        starts[x] = i
        x += s[0]
    for k, (_, _, p) in enumerate(ways, 1):
        labels[starts[p]] = (k, p)
        foes.append((p + HERO_X + WAY_POST, WAY, 0, src))
    foes.sort()
    keys2, where, data = generate(start, segs)
    assert keys2 == keys, "splitting a flat segment changed the ground"
    ways_at = [p for _, _, p in ways]
    for x, typ, _, w in foes:       # Rectangles and spikes stand on ground
        width = {FOES["rect"]: 16, TRAPS["spikes"]: 19}.get(typ & 15)
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

    times = [min(999, -(-time * 10 // round(f * 10))) for f in DIFFICULTY]
    o += [f"; {label}: generated from {src}",
          f"; worst screen: {worst} changing columns at top speed",
          f"{label}_start_key equ {key(start)}",
          f"{label}_name: db \"{name}\",0",
          f"{label}:"]
    size = 0
    seg_key = {}
    y = key(start)
    for i, (ln, typ, slope, kend) in enumerate(data):
        if i in labels:
            o.append(f"{label}_w{labels[i][0]}:")
            seg_key[labels[i][0]] = y
        y = kend
        if typ == 0xFF:
            o.append(f"  db {ln},&FF,{kend}")
            size += 3
        else:
            o.append(f"  db {ln},{typ | kend}")
            size += 2
    o.append("  db 0")
    o.append(f"; {len(data)} segments, {len(keys)} pixels")
    o.append(f"{label}_length equ {len(keys)}")
    o.append(f"{label}_goal equ {len(keys)}")
    for d, t in zip(("e", "m", "h"), times):
        o.append(f"{label}_time_{d} equ &{t:04d}")
    foes.append((len(keys) - 2, GOAL, 0, src))      # the finish post
    foes.sort()
    o.append(f"{label}_foes:")
    last = 0
    pending = [(k, p + HERO_X + WAY_CLEAR) for k, p in enumerate(ways_at, 1)]
    bases = {}
    for x, typ, param, w in foes:
        if not 0 <= x <= len(keys):
            sys.exit(f"{w}: foe outside the level (0..{len(keys) - 1})")
        while pending and x >= pending[0][1]:
            k = pending.pop(0)[0]
            o.append(f"{label}_f{k}:")
            bases[k] = last
        while x - last > 255:
            o.append("  db 255,0")
            last += 255
            size += 2
        if typ & 15 in (FOES["tri"], ITEMS["speed"], ITEMS["phase"]):
            o.append(f"  db {x - last},{typ},{param}")
            size += 3
        else:
            o.append(f"  db {x - last},{typ}")
            size += 2
        last = x
    o.append("  db 0,&FF")
    o.append(f"{label}_ways:")
    for k, p in enumerate(ways_at, 1):
        o.append(f"  dw {label}_w{k}")
        o.append(f"  db {seg_key[k]}")
        o.append(f"  dw {p}, {label}_f{k}, {bases[k]}, {p + HERO_X + WAY_POST}")
        size += WAY_SIZE
    o.append(f"{label}_nways equ {len(ways_at)}")
    print(f"  waypoints at x={[p + HERO_X for p in ways_at]}; time easy/medium/hard {times} s")
    o.append(f"; {size + 3 + len(name) + 1} bytes")
    print(f"  {size + 3 + len(name) + 1} bytes of level data")


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    budget = "--no-budget" not in sys.argv
    out_path, srcs = args[0], args[1:]
    o = ["; generated by tools/level2asm.py - do not edit"]
    labels = [f"level{i}" for i in range(1, len(srcs) + 1)]
    for src, label in zip(srcs, labels):
        level(src, label, budget, o)
    o += [f"LEVEL_COUNT equ {len(srcs)}", "LEVEL_ENTRY equ 18",
          f"WAY_SIZE equ {WAY_SIZE}", "level_table:"]
    for label in labels:
        o.append(f"  dw {label}, {label}_foes, {label}_goal")
        o.append(f"  dw {label}_time_e, {label}_time_m, {label}_time_h")
        o.append(f"  dw {label}_name, {label}_ways")
        o.append(f"  db {label}_start_key, {label}_nways")
    with open(out_path, "w") as f:
        f.write("\n".join(o) + "\n")


if __name__ == "__main__":
    main()
