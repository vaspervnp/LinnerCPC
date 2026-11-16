# Notes for working on Linner

Design: `linner_game_story.md`, plan: `milestones.md`.

## Build and run
- `make` builds `build/linner.dsk` (boot with `RUN"DISC`) and `build/linner.sna`.
- `make run` / `make run-dsk` play in Caprice32 (`EMU=cpcemu` for CPCEMU 2.5).
- `make debug`: the border shows frame time (red = Linner and the ground
  under him, yellow = the rest of the ground, blue = logic, black = idle).
- `make shot`: headless Caprice32 run of the scripted demo (TEST_FRAMES loops,
  then the game jumps to &0000 and `CAP32_WAITBREAK` takes `build/shot.png`).
- `make sim`: the same demo in `tools/cpcsim.py` (Python Z80, `--slow 1.25`
  approximates CPC wait states) with per-loop timing and `build/sim.png`.
- The test demo shifts up to gear 4 (loops 40/80/120) and an autopilot jumps
  when a gap or water is 14 px ahead. `TESTDEFS=-DTEST_SOAK=1` rolls into
  water instead, `-DTEST_SOAK=2` also stays in gear 1 (sinks, restarts);
  `-DTEST_GEAR5=1` unlocks gear 5. Pass `-B` when changing TESTDEFS or
  TEST_FRAMES (make doesn't track them).
- `tools/bench_terrain.py [slopes | level.txt]`: loop time per gear on zigzag terrain of
  a fixed slope (cpcsim, gear 5 unlocked). Use it after touching the ground
  renderer or the speeds.

## Frame budget (19968 us per frame)
- The ground costs ~11 NOPs per unchanged column and ~55 per changed one
  (old pixel cleared, new pixel set, both via the key-indexed `ground_lo`
  table). A column changes when the slope under it times the scroll step is
  >= ~1 row, so steep slopes at high gears change every column.
- Measured: flat ~7.6K at any gear; a screen of slope 1/8 fits gear 5
  (~16.9K avg); 1/4 only up to gear 2; 1/2 and steeper saturate at ~28K.
- Level design rule (the user chose a slope budget over frame drops):
  `tools/level2asm.py` replays the Z80 terrain generator and fails the build
  if any 384-px window has more than MAX_CHANGED (150) columns that change
  at top speed (4 px/frame). In practice: long stretches flat or <= 1/8,
  steep ramps (up to 45 deg) only short. Level 1 (with gaps): worst window
  139 columns, measured 8.3K (gear 1) to 12.9K (gear 5) average, 16.7K
  worst loop; the 1600-loop demo with jumps has no loop over budget.
- Terrain keys round to nearest (segments start at y + 0.5, slopes rounded)
  so consecutive columns never jump more than one row; the tool checks it.

## Game rules so far
- Controls: LEFT/RIGHT shift gear (1..4, gear 5 locked), COPY or joystick
  fire 2 jumps (hold for a full jump), SPACE / fire 1 is reserved for
  shooting (Phase 5). UP/DOWN reserved for aiming.
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
- No double buffering: the ground is updated column by column in place
  (only changed columns), objects are XOR-drawn right after VSYNC before the
  beam reaches them. Objects must never share pixels with the ground.
- Game y 0..255 = screen rows 16..271; rows 0..15 are the HUD. Ground keys
  0..126 map to game y 128..254 (bit 7 = water, &FF = gap). Slopes <= 45 deg.

## rasm gotchas
- Always `-amper`; `-v2` for snapshots (not for the loader, it warns).
- Macros must be defined before use (src/macros.asm is included first).
- `repeat n` / `rend`, not `rept`. `fail` is a directive: don't use it as a label.
- `ld ixh,l` doesn't exist (DD prefix turns L into IXL); go through A.
- Write `(a and b) == c`: `==` binds tighter than `and`.

## Emulators
- Caprice32 is the snap; `tools/cpcemu` runs it headless (SDL dummy drivers).
  The snap can't read /tmp, keep images under the repo.
- DISC.BAS must have CR LF line endings (the Makefile converts it).
