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
- The test demo (autopilot) shifts up every 16 loops while the gear is below
  max_gear (4; 5 with Max Speed or `-DTEST_GEAR5=1`), aims straight ahead
  and 30 degrees up by turns (32 loops each), keeps FIRE held; it jumps when a gap or water is 4 px ahead of
  Linner's centre or a Rectangle / spikes are within 24 px (as a ghost:
  gaps only). `-DTEST_GHOST=1` keeps Linner phased out, `-DTEST_LEVEL=n`
  starts at level n. `TESTDEFS=-DTEST_SOAK=1` rolls into water instead,
  `-DTEST_SOAK=2` also stays in gear 1 (sinks, restarts). Pass `-B` when
  changing TESTDEFS or TEST_FRAMES (make doesn't track them).
- The game boots into the title: test builds press FIRE there as soon as it
  takes input (25 frames), so the demo starts a couple of loops later.
- `make hitest`: high score round trip on a real disk image in Caprice32
  (the test snapshot plus `build/hitest/linner.dsk` in drive A): one life,
  score preset to 1234, sinks, enters "CPC64" through the pad and typed
  keys (DEL included), writes HISCORE.DAT via the FDC, reads it back and
  shows the title -> `build/hitest.png` must list CPC64 001329 first (the
  built-in table would mean the save or the load failed).
- `tools/hiscore.py [--where] disk.dsk` prints the table in a disk's
  HISCORE.DAT (and which track/sector it is on).
- `make release`: build/release/linner-$(VERSION).zip (disc, snapshot,
  release/README.txt, release/label.svg). DISC.BAS shows a loading screen.
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
- Phase 8, all six levels (2400-loop cpcsim runs per level, ghost + gear 5
  and normal autopilot): no gameplay loop over budget except the frame a
  finish message is printed (~21K, once) and 3 loops in level 6 (~20.1K,
  Linner jumping on a slope with 3 things + 3 shots). Level resets go over
  by design (palette black). 3000-loop demos: normal render avg 6.9K +
  logic 4.0K, ghost 7.5K + 4.3K; both pixel-exact.
- The HUD does at most one job per frame (a digit, a gear box or the
  soggy bar), so a score change never spikes a frame.
- Terrain keys round to nearest (segments start at y + 0.5, slopes rounded)
  so consecutive columns never jump more than one row; the tool checks it.

## Game rules so far
- Controls: LEFT/RIGHT shift gear (1..4, gear 5 locked), COPY or joystick
  fire 2 jumps (hold for a full jump), UP/DOWN aim (19 steps of 10 degrees,
  0 = straight ahead, 9 = up, 18 = behind; repeats when held), SPACE /
  fire 1 shoots (hold: one shot every 8 frames, 3 in flight at most: a
  4th cost ~900 us a frame).
- The ray keeps rolling with the distance (Phase 3); the aim is a short
  tick just outside the rim. Shots start at the tick, fly at 5 px/frame
  plus Linner's speed, and stop at the Line, the screen edges or a foe.
- Foes (objects.asm, spawned from `foe` lines in the level; 6 slots for
  foes, items and traps, 3 for shots):
  Rectangles (16x12) march along the Line at 0.5 px/frame and turn back at
  gaps and water; Triangles (15x13) drift at 1 px/frame bobbing +-12 rows
  and stay above the Line. Linner can't shoot downwards: a Rectangle lower
  than him has to be jumped. Touching a foe loses the life. 10 points per
  Rectangle, 15 per Triangle (score is 6 BCD digits).
- Jump: vy -5 rows/frame, gravity 0.25, cut to -2 on release: 50 rows high,
  40 frames long (40 px at gear 1 ... 140 px at gear 5). Linner lands only
  coming from above (within LAND_TOL rows); once below a surface he keeps
  falling. Grounded, he follows the ground unless it drops > DROP_MAX rows
  in a frame (ledges, gap edges), then falls.
- Gaps: falling off the bottom loses the life. Water: speed drains to 0.5
  px/frame and the soggy meter (HUD bar) fills 1 per frame; at 80 he sinks.
  Crossing fast or jumping is "traversing correctly". Dry ground drains it.
- Game flow (game.asm): READY ("LEVEL n: NAME", 90 frames frozen) ->
  PLAY -> past the finish post: COMPLETE (Linner coasts, every second left
  = 10 points, then the next level; after the last one "THE LINE IS
  YOURS!" and the same ending as a game over) ->
  ... Losing a life restarts the level (`level_setup`: palette black, XOR
  everything away, ground_wipe, re-init, full redraw); 3 lives, then GAME
  OVER (4 s), the name entry if the score makes the Top 10, and the title.
  The timer (`time N` in the level, BCD) running out
  loses a life too.
- Powerups (Rhombus, `item X speed|phase ALT`): Max Speed unlocks gear 5
  for 20 s (HUD box 5 turns green); Phase Out makes Linner a dotted ghost
  for 10 s (flickering for the last 2): foes, spikes and water can't hurt
  him; gaps still can. Both end with the life. +50 points each.
- Traps: `trap X spikes` (19x8 on the Line). The finish post is added by
  the tool at the end of the last segment; after it the Line runs on flat.
- HUD: gear boxes, soggy bar, "SCORE 000000", "T 060", "@X3" (lives).
  Text uses a 5x7 font (gen_tables.py) via print_hud (write) / print_xor
  (messages over the play area, removed by printing again).

- Title (GS_TITLE, hiscore.asm): the Top 10, a blinking "PRESS FIRE", the
  controls; FIRE or JUMP starts a game. A new entry blinks.
- Name entry (GS_ENTRY): 5 characters starting "A    "; UP/DOWN cycle
  A-Z 0-9 . - ! space (repeats when held), RIGHT/FIRE next, LEFT back,
  FIRE on the last one finishes. Or type: letters, digits, . - space,
  DEL clears (on a blank: the one before), RETURN/ENTER finishes. Typed
  keys come from keymap edges (key_prev). Ties keep the older entry above.
- Title and entry screens are plain XOR text on a cleared screen
  (`screen_clear`: cls + every "drawn" flag reset, so level_setup's XOR
  wipes find nothing); the main loop skips render and HUD in those states.

## High scores on disk (disk.asm)
- HISCORE.DAT (512 zero bytes = "use the built-in table") is put on the
  disk by iDSK without a header. At boot the game finds it in the
  directory (track 0, sector &C1, user 0, extent 0), converts its first
  block to track/sector (data format: block*2 = logical sector, 9 per
  track, &C1 first, no reserved tracks) and reads it. The sector holds
  "LINNERHI", 10 x (name 5 + BCD score 3) and a checksum (A5, add + rlca).
- The firmware is gone, so the uPD765 is driven directly (polled, non-DMA,
  interrupts off): specify &03,&A1,&03, recalibrate, seek, read/write
  with EOT = R (a good end is ST0 &40, ST1 &80). Motor on + 50 frames of
  spin-up before each access (the loader turns the motor off).
- Every FDC wait has a time-out except the 32 us/byte data loops; with no
  FDC (port reads &FF), no disc or no HISCORE.DAT, disk_track stays &FF
  and the table lives in RAM only. A failed save says "COULD NOT SAVE".
- SECTOR_BUF is &C4E0: screen RAM that is never displayed (charlines
  21..33 end at &C4DF in each 2K row block of the &C000 page).
- Scripted demos (TEST_FRAMES without TEST_HISCORE) skip the disk.

## Levels (levels/levelN.txt -> build/levels.asm)
- `tools/level2asm.py out.asm levels/level1.txt ...` (the Makefile passes
  every levels/level*.txt in order) emits levelN data and `level_table`
  (12 bytes per level: segments, foes, goal, time, name, start key);
  `level_load` copies the current entry into lv_segs..lv_key.
- Besides the slope budget the tool checks, and fails the build on:
  each gap's gear (a full jump of 40ish frames at the gear's speed must
  cover the gap minus GAP_EDGE = 8 px; gear 5 only with a speed Rhombus
  at most 3000 px before), each water stretch's gear (jump in from the
  edge, then roll until SOGGY_MAX), Rectangles / spikes over gaps or
  water, more than 6 things within 450 px (slots: extra ones never
  appear), a time limit under 1.3 x the level's length at gear 3-4, and
  a screen whose predicted loop time passes 19968 - 1500 us.
- Frame cost model (fitted on cpcsim runs of all levels, see frame_cost):
  ~4541 us + 74 per changing ground column (at 4 px/frame) + 1389 per
  foe/item/trap alive (384 px ahead to 40 px behind the screen) + 899 per
  shot (counted as all 3). Objects cost far more than slopes: busy
  screens must be flat. The worst level screens are ~17.5K; the 1.5K
  margin plus the 4th shot dropped cover the model's p99 error (~2.4K:
  jumps redraw the whole circle, spawns, HUD digits).
- Fairness warnings (not errors; the levels have none): a Triangle meets
  Linner 65..125 px before its x (it drifts left as he comes): not over a
  gap / water / spikes if its bob reaches a full jump's top; spikes or a
  Rectangle start at least 80 px from a gap / water edge (landings); no
  spikes within 160 px of a Rectangle on its stretch.
- Checking a level: build `-DTEST_LEVEL=n` (with or without TEST_GHOST +
  TEST_GEAR5) and run it in cpcsim; the ghost autopilot finishes all six,
  the normal one levels 1-4 (5 needs Max Speed for the chasm).
- Levels: 1 The Flat Line, 2 Swells, 3 Water Lines, 4 The Bureau,
  5 Chasms (a gear-5 chasm after a speed Rhombus), 6 End of the Line.

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
- `print` and `fail` are directives, not usable as labels.
- Compiled sprites use DOWNS (fast path inline, charline wrap in
  `down_wrap`): the full DOWN inlined everywhere overflowed the code area.

## Emulators
- Caprice32 is the snap; `tools/cpcemu` runs it headless (SDL dummy drivers).
  The snap can't read /tmp, keep images under the repo.
- DISC.BAS must have CR LF line endings (the Makefile converts it).
- Booting the .dsk headless: `tools/cpcemu -nowait -keys $'run"disc\n'zzz...`
  needs ~1500 padding keys now that LINNER.BIN is ~24K and the game spins
  the drive up for a second (fewer and the screenshot catches a black
  screen). `CAP32_WAITBREAK` can't be used for a disk boot: the boot
  itself passes &0000.
- CPCEMU 2.5 (/usr/share/cpcemu, native SDL) has no headless mode:
  `tools/cpcemu25 [-keys "space Right"] -shot out.png file.dsk|sna` runs a
  private copy (build/cpcemu-run) on the desktop, sends keys with xdotool
  after the boot, grabs the window with tools/xgrab.py (its own
  PrintScreen BMP is blank) and stops it. Verified there: the disc boots,
  the game plays, the FDC save + read back works (hitest snapshot with
  `-disc`); whether CPCEMU writes the image file back wasn't confirmed.
- `tools/cpcemu` takes several images (e.g. a snapshot plus a .dsk for
  drive A). Caprice32 can't save a written .dsk headless (it only asks
  "Unsaved changes..." on quit, which is why cpcemu stops it once the
  screenshot exists) and `CAP32_SNAPSHOT` writes nothing headless: check
  disk writes by reading them back in the same run (`make hitest`).
