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

- `tools/bench_terrain.py [slopes]`: loop time per gear on zigzag terrain of
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
  steep ramps (up to 45 deg) only short. Level 1: worst window 140 columns,
  measured 8.2K (gear 1) to 12.5K (gear 5) average, 16.3K worst loop.
- Terrain keys round to nearest (segments start at y + 0.5, slopes rounded)
  so consecutive columns never jump more than one row; the tool checks it.

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
