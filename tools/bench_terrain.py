#!/usr/bin/env python3
"""Frame-time benchmark: loop work per gear on terrain of a fixed slope.

  tools/bench_terrain.py [slope | level.txt ...]   (default: 0 0.25 0.5 0.75 1)

For each slope it writes a zigzag level, assembles a TEST build (gear 5
unlocked, the scripted demo shifts up every 40 loops) and runs it in
tools/cpcsim.py at --slow 1.25. Times are microseconds per main-loop pass;
one frame is 19968.
"""
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
from cpcsim import CPC  # noqa: E402

BUDGET = 19968
WINDOWS = ((105, 130, 1), (150, 170, 2), (190, 210, 3), (230, 250, 4), (280, 595, 5))


def level_text(m):
    """Zigzag terrain of slope m, long enough for the whole run (levels
    don't loop: past the end the Line runs on flat)."""
    if m == 0:
        return "start 40\n" + "200 40 ground\n" * 20
    run = 40
    rise = round(run * m)
    return f"start 30\n" + f"{run} {30 + rise} ground\n{run} 30 ground\n" * 40


def bench(m):
    d = os.path.join(ROOT, "build", "bench")
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, "level.txt"), "w") as f:
        f.write(open(m).read() if isinstance(m, str) else level_text(m))
    subprocess.run(["python3", "tools/level2asm.py", f"{d}/level.txt", "level1", f"{d}/level1.asm", "--no-budget"],
                   cwd=ROOT, check=True, stdout=subprocess.DEVNULL)
    r = subprocess.run(["rasm", "-amper", "-v2", "-I.", "-I../../src", "-I..", "-DTEST_FRAMES=600",
                        "-DDEBUG=1", "-DTEST_GEAR5=1", "-DTEST_GHOST=1", "../../src/main.asm", "-oi", "linner.sna"],
                       cwd=d, capture_output=True, text=True)
    if "error" in r.stdout.lower() + r.stderr.lower():
        sys.exit(r.stdout + r.stderr)
    cpc = CPC(os.path.join(d, "linner.sna"))
    cpc.slow = 1.25
    while not cpc.stopped and cpc.frame < 900:
        cpc.run_frame()
    loops = cpc.work_end
    out = []
    for lo, hi, g in WINDOWS:
        w = loops[lo:hi]
        out.append(f"g{g} {sum(w) / len(w):6.0f}{'*' if max(w) > BUDGET else ' '}" if w else f"g{g}   -   ")
    name = os.path.basename(m) if isinstance(m, str) else f"slope {m:4.2f}"
    print(f"{name:>11s}: " + "  ".join(out) + f"   worst {max(loops[20:]):.0f}")


def main():
    slopes = [a if a.endswith(".txt") else float(a) for a in sys.argv[1:]] or [0, 0.25, 0.5, 0.75, 1]
    print("avg us per loop by gear (* = some loops over the 19968 us frame)")
    for m in slopes:
        bench(m)


if __name__ == "__main__":
    main()
