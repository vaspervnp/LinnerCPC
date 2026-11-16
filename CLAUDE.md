# Notes for working on Linner

Design: `linner_game_story.md`, plan: `milestones.md`.

## Build and run
- `make` builds `build/linner.dsk` (boot with `RUN"DISC`) and `build/linner.sna`.
- `make run` / `make run-dsk` play in Caprice32 (`EMU=cpcemu` for CPCEMU 2.5).
- `make debug`: the border shows frame time (red = rendering: Linner,
  objects, ground; blue = input and logic; black = idle).
- `make shot`: headless Caprice32 run of the scripted demo (TEST_FRAMES loops,
  then the game jumps to &0000 and `CAP32_WAITBREAK` takes `build/shot.png`).
- `make sim`: the same demo in `tools/cpcsim.py` (Python Z80, `--slow 1.25`
  approximates CPC wait states) with per-loop timing and `build/sim.png`.
- The test demo shifts up to gear 4 (loops 40/80/120), aims straight ahead
  and keeps FIRE held; an autopilot jumps when a gap or water is 14 px ahead
  or a Rectangle is within 24 px. `TESTDEFS=-DTEST_SOAK=1` rolls into
  water instead, `-DTEST_SOAK=2` also stays in gear 1 (sinks, restarts);
  `-DTEST_GEAR5=1` unlocks gear 5. Pass `-B` when changing TESTDEFS or
  TEST_FRAMES (make doesn't track them).
- `tools/bench_terrain.py [slopes | level.txt]`: loop time per gear on
  zigzag terrain of a fixed slope or on a level (cpcsim, gear 5 unlocked,
  the demo autopilot shooting, Linner phased out so nothing ends the run).
  Use it after touching the renderer, speeds or objects.

## Frame budget (19968 us per frame)
- Ground: ~11 NOPs per unchanged column and ~55 per changed one (old pixel
  XORed off, new XORed on, via the key-indexed `ground_lo` and per-phase
  `ground_pen*` tables). The sweep runs right to left and skips whole
  groups of 4 columns using the run lengths the generator stores at RUNS
  (a column is unchanged when its key has held for at least the scroll
  step), so flat ground costs almost nothing.
- A slope that climbs or drops DY rows over LEN px changes about
  min(LEN, 4 x DY) columns per frame at top speed (4 px/frame): short steep
  ramps are cheap, long gentle slopes and big height changes are not.
- Level design rule (the user chose a slope budget over frame drops):
  `tools/level2asm.py` replays the Z80 terrain generator and fails the build
  if any 384-px window has more than MAX_CHANGED (120) changing columns.
- Level 1 (Phase 5): worst window 92 columns. 1600-loop demo with foes and
  shots: render avg 7.9K, logic avg 3.8K, worst loop ~18.3K, none over.
  bench (gear 5 unlocked): 8.1K..13.4K average per gear, 16.9K worst.
- Terrain keys round to nearest (segments start at y + 0.5, slopes rounded)
  so consecutive columns never jump more than one row; the tool checks it.

## Game rules so far
- Controls: LEFT/RIGHT shift gear (1..4, gear 5 locked), COPY or joystick
  fire 2 jumps (hold for a full jump), UP/DOWN aim (19 steps of 10 degrees,
  0 = straight ahead, 9 = up, 18 = behind; repeats when held), SPACE /
  fire 1 shoots (hold: one shot every 8 frames, 4 in flight at most).
- The ray keeps rolling with the distance (Phase 3); the aim is a short
  tick just outside the rim. Shots start at the tick, fly at 5 px/frame
  plus Linner's speed, and stop at the Line, the screen edges or a foe.
- Foes (objects.asm, spawned from `foe` lines in the level, 4 at a time):
  Rectangles (16x12) march along the Line at 0.5 px/frame and turn back at
  gaps and water; Triangles (15x13) drift at 1 px/frame bobbing +-12 rows
  and stay above the Line. Linner can't shoot downwards: a Rectangle lower
  than him has to be jumped. Touching a foe loses the life. score += 10 per
  Rectangle, 15 per Triangle (not shown yet).
- Jump: vy -5 rows/frame, gravity 0.25, cut to -2 on release: 50 rows high,
  40 frames long (40 px at gear 1 ... 140 px at gear 5). Linner lands only
  coming from above (within LAND_TOL rows); once below a surface he keeps
  falling. Grounded, he follows the ground unless it drops > DROP_MAX rows
  in a frame (ledges, gap edges), then falls.
- Gaps: falling off the bottom loses the life. Water: speed drains to 0.5
  px/frame and the soggy meter (HUD bar) fills 1 per frame; at 80 he sinks.
  Crossing fast or jumping is "traversing correctly". Dry ground drains it.
- Losing a life restarts level 1 (`level_restart`: XOR Linner away,
  `ground_wipe`, re-init, full redraw with the palette black).

## Architecture decisions (from the user)
- Mode 1 full overscan, 384x272, **single buffer** at &8000-&FFFF (32K via
  the R12 bits 2-3 trick, R12/R13 = &2C/&10 so charline 21 starts exactly at
  &C000). Runs on any 64K CPC; code lives in &0040-&6FFF.
- No double buffering: everything is XOR (ground, Linner, foes, shots), so
  any layer can be redrawn without disturbing the others. Each frame
  Linner and the objects are erased and redrawn first (right after VSYNC,
  before the beam reaches them), then the ground's changed columns.
- Game y 0..255 = screen rows 16..271; rows 0..15 are the HUD. Ground keys
  0..126 map to game y 128..254 (bit 7 = water, &FF = gap). Slopes <= 45 deg.

## rasm gotchas
- Always `-amper`; `-v2` for snapshots (not for the loader, it warns).
- Macros must be defined before use (src/macros.asm is included first).
- `repeat n` / `rend`, not `rept`. `fail` is a directive: don't use it as a label.
- `ld ixh,l` doesn't exist (DD prefix turns L into IXL); go through A.
- Write `(a and b) == c`: `==` binds tighter than `and`.
- Labels are case-insensitive: a variable `shot_cool` clashes with an equ
  `SHOT_COOL`. Local labels are reachable as `global.local` (used for SMC).

## Emulators
- Caprice32 is the snap; `tools/cpcemu` runs it headless (SDL dummy drivers).
  The snap can't read /tmp, keep images under the repo.
- DISC.BAS must have CR LF line endings (the Makefile converts it).
