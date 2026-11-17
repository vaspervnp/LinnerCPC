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
  and 30 degrees up by turns (32 loops each), (Linner fires by himself); it jumps when a gap or water is 4 px ahead of
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
- `make video`: build/linner_video.mp4 (tools/video.py; ~4 min, 12300
  frames): a TEST_VIDEO=1 demo build (TEST_TITLE_WAIT=500 loops on the
  title, RIGHT to HARD at loop 380, no gear 5: its long jumps landed on a
  Rectangle in level 1, a second jump when coming down onto a gap, water,
  spikes or a Rectangle, `video_danger`; a jump for a Rhombus above him
  timed by video_jump_t, `video_item` (the user asked); the aim at the
  nearest Triangle ahead with half its dx as lead, `video_aim`) clears
  levels 1-3 taking 12 of their 13 Rhombuses, loses all 3 lives at x 656
  in level 4, enters CPC64 and ends on the title. TEST_VIDEO builds leave
  out disk.asm (stubs): the test code didn't fit the code area. video.py
  renders cpcsim frames (384x272 -> x4) and synthesises the AY (125 kHz,
  pure Python lanes in big ints, no numpy) from psg_log, then ffmpeg muxes
  (s16be raw audio, highpass/lowpass, fades). `--no-video --log` plans
  a run fast (~1500 frames/4 s); `--wav` saves the sound.
- `tools/hiscore.py [--where] disk.dsk` prints the table in a disk's
  HISCORE.DAT (and which track/sector it is on).
- `make release`: build/release/linner-$(VERSION).zip (disc, snapshot,
  release/README.txt, release/label.svg, the PDF manuals). DISC.BAS draws
  a vector world (sun, mountains, perspective floor, The Line, Linner and
  foes) with firmware DRAW before it loads LOADER.BIN.
- README.md (repo front page) and docs/manual_en.md / manual_el.md use the
  shots in docs/screenshots/. `make screens` remakes them (tools/screens.sh:
  no-DEBUG demo builds run in cpcsim to a fixed loop, since Caprice32 misses
  an early &0000; the loading screen is a disc boot in Caprice32 with 140
  padding keys, LOADING_PAD: fewer and DISC.BAS hasn't finished drawing). `make manuals` -> docs/manual_*.pdf (tools/manual2pdf.py:
  Markdown -> HTML with embedded images -> headless Chrome; under WSL it
  uses the Windows chrome.exe). Keep the manuals in step with game changes.
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
- With the faster gears (5000-loop cpcsim runs per level): gear 4 cruise
  drops a picture in 0-3% of loops on busy screens (frame skip keeps the
  pace; level 6's dense opening the most), the ghost runs 1-53 per run.
  Level resets go over by design (palette black). Particles cost ~0.5 ms
  a frame: they rest on frames with 6+ objects or when catching up.
- Warp particles (particles.asm, the user asked for them): 6 white
  streaks in the sky (game y 12..104) moving left at 1.5x..4x Linner's
  speed, 1-3 px long by speed; half of them move each frame (two frames'
  step; mask pairs from part_masks, so a streak is 1-2 byte XORs). render draws them after the objects;
  level_setup wipes and re-inits them, screen_clear re-inits them.
- Sound (sound.asm, from the interrupt, the user asked): ~0.6 ms a frame
  on top; level2asm's SOUND_US (600) is in COST_BASE (level 3's slope at
  x 1304 was steepened 36 -> 30 px to stay in budget) and particles rest
  with 5+ objects alive (PART_MAX_OBJ 5, was 6): borderline screens
  otherwise tipped into 25 Hz stretches (an overrun loop runs two steps,
  so it stays late until the screen gets lighter).
- The HUD does at most one job per frame (a digit, a gear box or the
  soggy bar), so a score change never spikes a frame.
- Terrain keys round to nearest (segments start at y + 0.5, slopes rounded)
  so consecutive columns never jump more than one row; the tool checks it.

## Game rules so far
- Speed (the user's choice): gears 1.0, 1.875, 3.0, 4.81, 7.0 px/frame
  (gear 5 = twice the old top), and Linner shifts up by himself every
  GEAR_TIME = 150 frames (gear_timer; any shift restarts it; hero_init
  sets gear 1, so every level and life starts slow). ACCEL/DECEL doubled,
  DROP_MAX 8 so 45-degree slopes hold at 7 px/frame. level2asm's
  GEAR_SPEEDS / fast_reach / SCROLL_MAX (5: the frame budget is checked at
  gear 4) follow hero.asm.
- Frame skip (the user allows a dropped frame at speed): when a loop
  overruns, wait_frame skips that frame's picture (waits for the next
  VSYNC instead of drawing mid-frame) and sets frame_late; the main loop
  then runs one extra game_step (input + logic), at most one, so the game
  keeps its 50 Hz pace and only the picture drops to 25 Hz.
- Controls: LEFT/RIGHT shift gear (1..4, gear 5 locked), SPACE or joystick
  fire 2 jumps (hold for a full jump), UP/DOWN aim (19 steps of 10 degrees,
  0 = straight ahead, 9 = up, 18 = behind; held: first repeat after
  AIM_DELAY 4 frames, then AIM_RATE 3 steps per 4 frames via aim_acc, 3x
  the old 12 / 4, the user asked). Linner shoots by himself (the user's
  choice: no fire key), evenly spaced (the user asked: no 3-then-pause):
  shot_gap reloads shot_cool with a third of the new shot's flight to the
  screen edge or the top (gen_tables shot_gap_x per aim; shot_gap_y x the
  muzzle row / 256), so a slot frees as the next shot is due: ~23 frames
  aiming ahead. 3 slots (a 4th cost ~900 us a frame).
  Either joystick button jumps; nothing sets PAD_FIRE but the tests.
- The ray keeps rolling with the distance (Phase 3); the aim is a short
  tick just outside the rim. Shots start at the tick, fly at 5 px/frame
  plus Linner's *current* speed (shot_update adds speed to O_SHOT_VX each
  frame, so a shot fired in a low gear doesn't crawl once the gears
  climb), and stop at the Line, the screen edges or a foe.
- Foes (objects.asm, spawned from `foe` lines in the level; 6 slots for
  foes, items and traps, 3 for shots):
  Rectangles (16x12) march along the Line at 0.5 px/frame and turn back at
  gaps and water; Triangles (15x13) drift at 1 px/frame bobbing +-12 rows
  and stay above the Line. Linner can't shoot downwards: a Rectangle lower
  than him has to be jumped. Touching a foe loses the life. 10 points per
  Rectangle, 15 per Triangle (score is 6 BCD digits).
- Jump (hard's values; see Difficulty): vy -5 rows/frame, gravity 0.25, cut to -2 on release: 50 rows high,
  40 frames long (40 px at gear 1 ... 280 px at gear 5). Linner lands only
  coming from above (within LAND_TOL rows); once below a surface he keeps
  falling. Grounded, he follows the ground unless it drops > DROP_MAX rows
  in a frame (ledges, gap edges), then falls.
- Second jump (the user asked): pressing jump again during a jump (once;
  hero_jumps 0/1/2, not after rolling off a ledge) sets vy to JUMP_V2 =
  -2.5: half the speed, 20 frames, half the distance, ~12 rows up.
  level2asm's checks ignore it (they stay the conservative case), and the
  autopilot never uses it (it only holds the button in the air).
- Gaps: falling off the bottom loses the life. Water: speed drains to 0.5
  px/frame and the soggy meter (HUD bar) fills 1 per frame; at 80 he sinks.
  Crossing fast or jumping is "traversing correctly". Dry ground drains it.
- Difficulty (the user asked: easy / medium max speed 60% / 80% of hard,
  hard = as before): `difficulty` 0/1/2, LEFT/RIGHT on the title ("DIFFICULTY
  < MEDIUM >", default medium; test builds hard, DIFF_DEFAULT), game_new
  copies a diff_table entry (gen_tables.py, DIFF_SIZE 37) into `phys`
  (p_gears, p_accel, ... p_bonus) and the code reads the speeds from there.
  The whole world is scaled so the levels play the same in space: speeds
  x f (gears, jump / 2nd jump / cut, VY_MAX, water min, Rectangle,
  Triangle, soggy fill per frame via hero_soggy_f), accelerations x f*f
  (gravity, accel, decel, water drag), frame counts / f (gear-up time,
  powerup frames per second p_fps). Level times come from level2asm per
  difficulty (time / f); the finish bonus is 6 / 8 / 10 points a second.
  Shots keep 5 px/frame. Ghost runs on easy and medium finish levels 1, 5,
  6 like hard (DIFF_DEFAULT=0/1 test builds). The table marks each entry
  E/M/H: 2 - difficulty in bit 7 of its first two name letters (0 = hard,
  as every table saved before), hs_mark / hs_row_xor.
- Waypoints (the user asked: 3+ per level by length, a lost life restarts
  at the last one passed): level2asm places max(3, round(len / 3500)) as
  evenly as it can (least sum of squared runs) where a gear-1 restart is
  safe: a segment start or inside a flat segment (split there: same keys),
  no gap/water within 120 px, run_up() to the next gap's gear, not between
  a Max Speed Rhombus and its chasm, the post's screens in the frame
  budget. A restart skips the things < WAY_CLEAR (250) px ahead (its foe
  pointer starts after them). LABEL_ways records (WAY_SIZE 11): segment,
  key, scroll x, foe record, x before it, pass x. level_setup restarts
  from wp_last's record (terrain_start, objects_clear + objects_start,
  time = wp_time); game_play saves time_left in wp_time when Linner passes
  the next post (wp_next); level_begin (new level, new game) clears
  wp_last. READY says "LEVEL n: WAYPOINT k". Posts are T_WAY things (no
  collisions, like T_GOAL); both posts are drawn by post_xor (a 1-px post
  with a 4-px flag, ~60 bytes), not compiled sprites: the goal's compiled
  sprite was ~3K and the code area was full.
- Game flow (game.asm): READY ("LEVEL n: NAME", 90 frames frozen) ->
  PLAY -> past the finish post: COMPLETE (Linner coasts, every second left
  = 10 points, then the next level; after the last one "THE LINE IS
  YOURS!" and the same ending as a game over) ->
  ... Losing a life restarts the level at the last waypoint (`level_setup`:
  palette black, XOR everything away, ground_wipe, re-init, full redraw); 3 lives, then GAME
  OVER (4 s), the name entry if the score makes the Top 10, and the title.
  The timer (`time N` in the level, BCD) running out
  loses a life too.
- Powerups (Rhombus, `item X speed|phase ALT [SECS]`, SECS 3..8, default
  5; the user wants 3-8 s): Max Speed unlocks gear 5 (HUD box 5 turns
  green); Phase Out makes Linner a dotted ghost (flickering for the last
  second): foes, spikes and water can't hurt him; gaps still can. The
  seconds ride in the foe record's type byte (x16) and in the slot's O_VY
  until the pickup. Both end with the life. +50 points each.
- Traps: `trap X spikes` (19x8 on the Line). The finish post is added by
  the tool at the end of the last segment; after it the Line runs on flat.
- HUD: gear boxes, soggy bar (10 bytes, 8 soggy units each), "V 4.8"
  (speed, px/frame: 2 more digits in the HUD digit queue), "SCORE 000000",
  "T 060", "@X3" (lives).
  Text uses a 5x7 font (gen_tables.py) via print_hud (write) / print_xor
  (messages over the play area, removed by printing again).

- Title (GS_TITLE, hiscore.asm): the Top 10 (rows 10 apart from y 36,
  "10. ABCDE  001234 H"), a blinking "PRESS FIRE" (y 140), the difficulty
  (y 152), the controls; FIRE or JUMP starts a game. A new entry blinks.
- Name entry (GS_ENTRY): 5 characters starting "A    "; UP/DOWN cycle
  A-Z 0-9 . - ! space (repeats when held), RIGHT/FIRE next, LEFT back,
  FIRE on the last one finishes. Or type: letters, digits, . - space,
  DEL clears (on a blank: the one before), RETURN/ENTER finishes. Typed
  keys come from keymap edges (key_prev). Ties keep the older entry above.
- Title and entry screens are XOR text over the menus' vector world
  (menu.asm, data from gen_tables.py menu_world: radial floor lines,
  mountains, a striped sun, stars, and a floor whose 7 cross lines roll
  towards the viewer, 16 phases, menu_tick every frame via hline_xor),
  in menu_palette (pen 2 magenta), on a cleared screen (`screen_clear`:
  cls + every "drawn" flag reset, so level_setup's XOR wipes find
  nothing); the main loop skips render and HUD in those states.
  line_xor takes a pen (line_pen: &F0 pen 1, &0F pen 2, &FF pen 3; put it
  back to &FF, the game draws in pen 3).

## Sound (sound.asm, build/music.asm from tools/gen_music.py)
- int_handler counts the frame's interrupts (int_n, 0 at the VSYNC one)
  and runs sound_tick in the 6th (~3 ms before VSYNC: the 1st is the
  drawing's, Linner and objects race the beam). AF/BC/DE/HL pushed by
  int_handler, IX by sound_tick; no shadow registers (terrain uses exx).
- kbd_scan runs with interrupts off (both touch the PSG through the PPI);
  the mixer keeps bit 6 = 0 (port A input). disk_load / disk_save call
  sound_mute after `di` (a held note would drone through the FDC access).
- State at SND = &7700 (free RAM between the object slots and RUNS),
  cleared by sound_init. Channels A (bass), B (lead / arpeggio), C (drums
  or a second voice); effects take over C (sfx_tick writes C's fields,
  CH_PNOTE = &FF so the music recomputes its period). snd_env walks the
  channel's first fields with HL (no IX); held envelope frames skip it
  (CH_HELD); periods / noise are compared and written only when a period
  changed (snd_dirty); registers go out when they differ from ay_last.
- Requests are single bytes: music_play (A = SONG_x, C = key; the same song
  in the same key keeps playing), sfx_play (A = SFX_x = its priority; a
  playing effect is replaced only by an equal or higher one; SHOT doesn't
  cut a drum hit of volume 9+).
- Songs: TITLE (title and name entry), GAME (level_begin, key from
  level_keys: 0,2,3,-2,5,7; keeps going through lost lives), DONE (finish
  post), OVER (game over). Data format and the effects' table are
  described in gen_music.py. Labels are case-insensitive: arpm / arpM and
  AY_REGS / ay_regs clashed.

## High scores on disk (disk.asm)
- The disc is an Extended DSK: iDSK writes "MV - CPCEMU" and
  tools/dsk2edsk.py converts it in make_dsk. Retro Virtual Machine v2
  saved the standard image after the game's write as an extended one with
  only the written track (the user's disc broke); extended images are
  written back whole.
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
  (18 bytes per level, see below);
  `level_load` copies the current entry into lv_segs..lv_nways
  (LEVEL_ENTRY 18: segments, foes, goal, times easy/medium/hard, name,
  waypoints; start key, waypoint count).
- Compact data (memory is the limit: ~2.6K of levels for ~86K px): a
  segment is `db len, key` (water: &80+key; a gap `db len, &FF, key`), and
  seg_load works out the slope, round(|dy| * 256 + len/2) / len, exactly as
  level2asm.generate (the two must agree: a cpcsim run that compares the
  ring with generate() found 0 mismatches). Foe records are `db dx, tb
  [, param]` (dx from the previous record, 255-px steps with tb = 0; param
  only for Triangles and Rhombuses; ends with db 0,&FF).
- The levels are 4x+ the Phase 8 ones and each longer than the last (the
  user asked): 12012, 12904, 13799, 14405, 15301, 16802 px. Each file keeps
  its hand-made opening above `# === generated ===`; `tools/levelgen.py
  [N]` rewrites the rest (themed random sections, fixed seeds) and the
  time limit, growing the level section by section and backtracking when
  level2asm reports an error or a fairness warning (with PLACE_WAYS off:
  the waypoints are placed once, on the finished level).
- Besides the slope budget the tool checks, and fails the build on:
  each gap's gear (a full jump of 40ish frames at the gear's speed must
  cover the gap minus GAP_EDGE = 8 px; gear 5 only after a speed Rhombus
  close enough to land before its seconds run out, fast_reach), each
  water stretch's gear (jump in from the
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
- For the faster gears level2asm also fails the build when a full jump in
  gear 4 (the cruise; gear 5 for a Max Speed chasm) over a gap or water,
  taken at the last moment, comes down in the next gap or water, on
  spikes, on a Rectangle (allowing ~25 px of its march) or where a
  Triangle meets him (landings()). Consecutive gap/water segments count as
  one stretch. The hand-made openings were widened / thinned for it (a
  few Triangles dropped, marked in the files).
- Picking up Max Speed shifts straight into gear 5.
- Fairness warnings (not errors; the levels have none): a Triangle meets
  Linner MEET (45..103 px at gear 3-4 speeds, from AHEAD = 384 - HERO_X)
  before its x (it drifts left as he comes): not over a
  gap / water / spikes if its bob reaches a full jump's top; spikes or a
  Rectangle start at least 80 px from a gap / water edge (landings); no
  spikes within 160 px of a Rectangle on its stretch.
- Checking a level: build `-DTEST_LEVEL=n` (with or without TEST_GHOST +
  TEST_GEAR5) and run it in cpcsim; the ghost autopilot (gear 4 cruise,
  gear 5 from Max Speed) finishes all six; the normal one levels 2 and 3
  (it dies where a Rectangle has a Triangle above it: it jumps the
  Rectangle instead of shooting, and its aim only swings 0/30 degrees).
  The autopilot no longer presses RIGHT (the gears climb by themselves);
  TEST_SOAK=2 presses LEFT to stay slow.
- Levels: 1 The Flat Line, 2 Swells, 3 Water Lines, 4 The Bureau,
  5 Chasms (4 gear-5 chasms, each after a speed Rhombus), 6 End of the
  Line (4 too).

## Architecture decisions (from the user)
- Linner's centre is at screen x HERO_X = 30 (the user asked: only his
  own width free behind him); gen_tables.py (shot gaps) and level2asm.py
  (HERO_X, MEET) carry the same number.
- Mode 1 full overscan, 384x272, **single buffer** at &8000-&FFFF (32K via
  the R12 bits 2-3 trick, R12/R13 = &2C/&10 so charline 21 starts exactly at
  &C000). Runs on any 64K CPC; code, tables and levels live in
  &0040-&6FFF (code_end ~&6DED: ~530 bytes left), the variables at &7C00-&7DFF (not in
  LINNER.BIN, cleared at start-up; ~&7D9C used), the stack below &8000.
  Text buffers sit among the variables: hs_row (20) overran disk_track /
  disk_sector once (the save then wrote the wrong sector), so size them
  with the longest text.
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
