#!/usr/bin/env python3
"""Lengthen the levels: keep each hand-made level as its opening and add
generated sections in the level's theme after it.

    tools/levelgen.py [N ...]        (default: all six)

levels/levelN.txt keeps everything above the line "# === generated ==="
(the hand-made part, with its name and start); everything below it is
rewritten, and so is the time limit. The sections are drawn at random (a
fixed seed per level, so a run is repeatable) and the whole level must pass
tools/level2asm.py with no errors and no fairness warnings: when a section
breaks a rule, it and the ones after it are drawn again.
"""
import contextlib
import io
import math
import os
import random
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
import level2asm as L  # noqa: E402

MARK = "# === generated ==="

# Per level: total length, the highest gear a gap or water may need (5 =
# with a Max Speed Rhombus first), how many gear-5 chasms, and the mix of
# sections (weights).
THEMES = {
    1: dict(length=12000, gear=3, chasms=0, mix=dict(
        flat=2, rect=5, tri=3, ramp=3, hill=2, steps=1, gap=4, puddle=3, spikes=2,
        plateau=1, rhombus=1)),
    2: dict(length=12800, gear=3, chasms=0, mix=dict(
        flat=1, rect=4, tri=7, ramp=3, hill=6, steps=3, plateau=3, gap=4, puddle=1,
        spikes=2, rhombus=1)),
    3: dict(length=13600, gear=3, chasms=0, mix=dict(
        flat=1, rect=5, tri=6, ramp=2, hill=1, gap=2, puddle=3, water=6, valley=4,
        spikes=1, rhombus=2)),
    4: dict(length=14400, gear=3, chasms=0, mix=dict(
        flat=1, rect=6, tri=6, ramp=2, plateau=3, gap=3, puddle=1, spikes=4, bureau=4,
        rhombus=2)),
    5: dict(length=15200, gear=4, chasms=3, mix=dict(
        flat=1, rect=2, tri=3, ramp=2, steps=2, gap=6, ledge=6, puddle=1, spikes=1,
        plateau=1, rhombus=1)),
    6: dict(length=16800, gear=4, chasms=3, mix=dict(
        flat=1, rect=4, tri=6, ramp=2, hill=2, steps=1, gap=4, ledge=3, puddle=2,
        water=3, valley=2, spikes=2, bureau=4, plateau=2, rhombus=2)),
}

V = L.GEAR_SPEEDS
T_FLAT = L.air_time(0)          # a full jump over level ground (frames)


def gap_width(gear, rng, rise=0):
    """A gap that needs exactly `gear` (and is jumpable with it)."""
    t = L.air_time(rise)
    hi = int(V[gear - 1] * t + L.GAP_EDGE) - 6 - 3 * gear   # (late jumps at speed)
    lo = int(V[gear - 2] * t + L.GAP_EDGE) + 4 if gear > 1 else 16
    return rng.randint(lo, max(lo, hi))


def water_len(gear, rng):
    hi = int(L.water_reach(V[gear - 1], True)) - 6
    lo = int(L.water_reach(V[gear - 2], True)) + 6 if gear > 1 else 24
    return rng.randint(lo, max(lo, hi))


class Gen:
    def __init__(self, n, rng, alt):
        self.n, self.rng = n, rng
        self.alt = alt                  # current ground altitude
        self.lines = []                 # (text, section)
        self.x = 0
        self.sec = 0

    def seg(self, ln, alt, typ="ground", note=""):
        self.x += ln
        flat = typ == "ground" and alt == self.alt
        last = next((l for l in reversed(self.lines) if isinstance(l, list)), None)
        if (flat and last and last[2] == "ground" and last[1] == alt == last[4]
                and last[0] < 255):
            add = min(ln, 255 - last[0])        # merge level runs: fewer bytes
            last[0] += add
            ln -= add
        while ln > 0:
            part = min(ln, 255)
            self.lines.append([part, alt, typ, note, self.alt if typ == "ground" else None])
            ln -= part
            note = ""
        self.alt = alt

    def thing(self, text):
        self.lines.append(text)

    def flat(self, ln, note=""):
        self.seg(ln, self.alt, note=note)

    def ramp(self, dy):
        a = max(8, min(110, self.alt + dy))
        dy = a - self.alt
        if dy:
            self.seg(max(abs(dy), self.rng.randint(abs(dy), abs(dy) * 2)), a)


def section(g, kind, theme):
    r = g.rng
    lo = max(1, theme["gear"] - 1)          # gaps and water: this gear or one below
    if kind == "flat":
        g.flat(r.randint(60, 160))
    elif kind == "rect":
        g.flat(r.randint(85, 110))
        g.thing(f"foe {g.x} rect")
        g.flat(r.randint(95, 130))
    elif kind == "tri":
        g.flat(r.randint(125, 150))
        g.thing(f"foe {g.x} tri {g.alt + r.randint(30, 90)}")
        g.flat(r.randint(20, 60))
    elif kind == "ramp":
        g.flat(r.randint(40, 90))
        g.ramp(r.choice([-1, 1]) * r.randint(10, 22))
        g.flat(r.randint(40, 90))
    elif kind == "hill":                    # up, a plateau, down (or a dip)
        dy = r.randint(10, 22) * (1 if g.alt < 60 else -1)
        g.flat(r.randint(40, 80))
        g.ramp(dy)
        g.flat(r.randint(30, 90))
        g.ramp(-dy)
        g.flat(r.randint(40, 80))
    elif kind == "plateau":                 # a Rectangle on a raised stretch
        dy = r.randint(10, 20) * (1 if g.alt < 60 else -1)
        g.flat(r.randint(40, 70))
        g.ramp(dy)
        g.flat(r.randint(85, 100))
        g.thing(f"foe {g.x} rect")
        g.flat(r.randint(95, 120))
        g.ramp(-dy)
        g.flat(r.randint(30, 60))
    elif kind == "steps":                   # stairs up or down
        d = r.choice([-1, 1]) * r.randint(6, 10)
        g.flat(r.randint(30, 60))
        for _ in range(r.randint(2, 4)):
            g.ramp(d)
            g.flat(r.randint(24, 50))
        g.flat(r.randint(30, 60))
    elif kind in ("gap", "ledge"):
        gear = r.randint(lo, theme["gear"])
        rise = r.randint(-24, 16) if kind == "ledge" else 0
        a = max(8, min(110, g.alt + rise))
        rise = a - g.alt
        g.flat(r.randint(70, 130))
        g.seg(gap_width(gear, r, rise), a, "gap", note=f"gear {gear}")
        g.flat(r.randint(90, 130))
    elif kind == "puddle":
        g.flat(r.randint(60, 110))
        g.seg(r.randint(24, 60), g.alt, "water")
        g.flat(r.randint(90, 120))
    elif kind == "water":
        gear = r.randint(lo, min(theme["gear"], 4))
        g.flat(r.randint(70, 130))
        g.seg(water_len(gear, r), g.alt, "water", note=f"gear {gear}")
        g.flat(r.randint(90, 130))
    elif kind == "valley":                  # down into water and up again
        dy = r.randint(10, 18)
        if g.alt - dy < 8:
            dy = -dy
        g.flat(r.randint(40, 80))
        g.ramp(-dy)
        g.seg(water_len(r.randint(lo, min(theme["gear"], 3)), r), g.alt, "water")
        g.ramp(dy)
        g.flat(r.randint(90, 120))
    elif kind == "spikes":
        g.flat(r.randint(85, 120))
        g.thing(f"trap {g.x} spikes")
        g.flat(r.randint(60, 110))
    elif kind == "bureau":                  # a Triangle over a Rectangle's beat
        g.flat(r.randint(85, 110))
        g.thing(f"foe {g.x} rect")
        g.flat(r.randint(120, 150))
        g.thing(f"foe {g.x} tri {g.alt + r.randint(45, 90)}")
        g.flat(r.randint(90, 120))
    elif kind == "rhombus":
        g.flat(r.randint(60, 120))
        what = r.choice(["speed", "phase", "phase"])
        g.thing(f"item {g.x} {what} {g.alt + r.randint(14, 40)} {r.randint(3, 8)}")
        g.flat(r.randint(40, 100))
    elif kind == "chasm":                   # Max Speed, then a gear-5 gap
        secs = r.randint(5, 8)
        g.flat(r.randint(90, 120), note="Max Speed, then the chasm")
        g.thing(f"item {g.x} speed {g.alt + 12} {secs}")
        w = gap_width(5, r)
        # ~276 px to get from gear 4 up to 7 px/frame, then the jump
        run = min(r.randint(300, 340), int(L.fast_reach(secs) - w) - 10)
        g.flat(run, note="up to gear 5")
        g.seg(w, g.alt, "gap", note="gear 5")
        g.flat(r.randint(110, 150))
    else:
        raise ValueError(kind)


def check(text, path):
    """Run level2asm on the text: (error message or None, warnings)."""
    out = io.StringIO()
    try:
        with contextlib.redirect_stdout(out):
            L.level(path, "levelx", True, [], text=text)
    except SystemExit as e:
        return str(e), []
    warns = [l for l in out.getvalue().splitlines() if "warning" in l]
    return None, warns


def build(n):
    path = f"levels/level{n}.txt"
    text = open(path).read()
    base = text.split(MARK)[0].rstrip("\n") + "\n"
    name, start, _, segs, foes = L.parse_text(base, path)
    base_len = sum(s[0] for s in segs)
    theme = THEMES[n]
    kinds, weights = zip(*theme["mix"].items())
    span = theme["length"] - base_len
    chasms = [base_len + span * (i + 1) // (theme["chasms"] + 1) for i in range(theme["chasms"])]
    pace = max(min(theme["gear"], 4), 3)
    rng = random.Random(n * 1000)

    def render(g, final):
        total = g.x + (0 if final else 160)
        secs = total / (V[pace - 1] * 50)
        time = min(999, int(math.ceil(secs * 1.45 / 5) * 5))
        body = re.sub(r"(?m)^time .*$", f"time {time}", base)
        out = [f"\n{MARK}", f"# tools/levelgen.py: {theme['length']} px in all"]
        for l in g.lines:
            if isinstance(l, list):
                ln, alt, typ, note, _ = l
                out.append(f"{ln:<3} {alt:<3} {typ}" + (f"  # {note}" if note else ""))
            else:
                out.append(l)
        if not final:
            out.append(f"160 {g.alt} ground")
        return body + "\n".join(out) + "\n", time

    g = Gen(n, rng, start)
    g.x = base_len
    stack = []                      # snapshots before each section
    fails = 0
    tries = 0
    while g.x < theme["length"] - 200:
        tries += 1
        if tries > 3000:
            sys.exit(f"level {n}: no luck after {tries} sections (at x={g.x})")
        stack.append(([list(l) if isinstance(l, list) else l for l in g.lines],
                      g.x, g.alt, g.sec))
        if chasms and g.x >= chasms[0]:
            kind = "chasm"
        else:
            kind = rng.choices(kinds, weights)[0]
        section(g, kind, theme)
        g.sec += 1
        err, warns = check(render(g, False)[0], path)
        if err is None and not warns:
            if kind == "chasm":
                chasms.pop(0)
            fails = 0
            continue
        fails += 1
        back = 1 if fails < 8 else 2        # stuck: undo one more section
        for _ in range(min(back, len(stack))):
            g.lines, g.x, g.alt, g.sec = stack.pop()
        if fails > 40:
            sys.exit(f"level {n}: stuck at x={g.x}: {(err or warns[0]).splitlines()[-1]}")
    g.flat(160, note="the finish post")
    full, time = render(g, True)
    err, warns = check(full, path)
    if err or warns:
        sys.exit(f"level {n}: {err or warns}")
    open(path, "w").write(full)
    print(f"{path}: {g.x} px, time {time} s")


def main():
    os.makedirs("build", exist_ok=True)
    ns = [int(a) for a in sys.argv[1:]] or list(THEMES)
    for n in ns:
        build(n)


if __name__ == "__main__":
    main()
