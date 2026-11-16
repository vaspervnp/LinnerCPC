LINNER - a pointless journey
============================
Amstrad CPC 464 / 664 / 6128 (64K is enough), 3" disc.

In the single-colour void of the Vectorverse there is only The Line, kept
flat for eons by the Bureau of Sharp Angles. Linner is a circle with a
rebellious ray trapped inside him, and he wants to go *up*. He warps The
Line into hills and valleys; the Bureau answers with Rectangles,
Triangles, abysses and Water Lines (circles can't swim).

Roll fast. Shoot sharp. Stay well-rounded.


LOADING
-------
Insert the disc and type    RUN"DISC
(linner.dsk in an emulator; on a real CPC, write it to a 3" or 3.5"
disc with your usual tools - keep the whole image, high scores are saved
on it.)


CONTROLS                      keyboard              joystick
--------
Shift gear up / down          RIGHT / LEFT          right / left
Aim the ray up / down         UP / DOWN             up / down
Shoot                         Z                     fire 1
Jump (hold for a full jump)   SPACE                 fire 2

The ray aims in 10-degree steps from straight ahead to straight up and
behind (hold UP/DOWN to sweep it). Shots fly from the aim tick on the rim;
up to 3 at once. Linner can't shoot downwards: a Rectangle below him has
to be jumped.


THE RULES
---------
* Five gears: 1.0 to 2.75 pixels per frame in gears 1-4. Gear 5 (3.5) is
  locked; the Max Speed Rhombus opens it for 20 seconds.
* Wide gaps need speed: a full jump lasts 40 frames, so it carries Linner
  40 px in gear 1, 60 in gear 2, 80 in gear 3, 110 in gear 4, 140 in 5.
  Falling into a gap costs a life.
* Water Lines slow Linner down and soak him (the blue bar at the top); at
  full soak he sinks. Cross them fast, jump into them late, or jump them.
* Touching a Rectangle, a Triangle or spikes costs a life.
  Rectangle 10 points, Triangle 15, Rhombus 50.
* Phase Out Rhombus: 10 seconds as a ghost - foes, spikes and water can't
  hurt him (gaps still can). It flickers just before it ends.
* Every level has a clock. Each second left at the finish post is worth
  10 points; running out of time costs a life.
* 3 lives. Losing one restarts the level.
* Six levels: The Flat Line, Swells, Water Lines, The Bureau, Chasms,
  End of the Line.


HIGH SCORES
-----------
A Top 10 score lets you etch a 5-character name into the disc: UP/DOWN
picks a letter, RIGHT or fire moves on, LEFT goes back, fire on the last
letter is done - or just type it (DEL deletes, RETURN finishes). The
table is saved in HISCORE.DAT on the game disc, so keep the disc
writable. Emulators: Caprice32 asks to save the changed disc when you quit
(or use "Save dsk A" in its F1 menu).


FILES
-----
linner.dsk     the game disc (DISC.BAS, LOADER.BIN, LINNER.BIN, HISCORE.DAT)
linner.sna     snapshot of the game (starts at the title; no disc access,
               so high scores aren't saved)
label.svg      a label for the disc
manual_en.pdf  the player's manual (English)
manual_el.pdf  the player's manual (Greek)


TECHNICAL
---------
Mode 1 full overscan (384 x 272), 50 frames per second, single screen
buffer: everything is drawn with XOR and only the parts that changed are
redrawn. The firmware is switched off; the high score table is read and
written straight through the uPD765 floppy controller.

Written in Z80 assembly (rasm), built with iDSK, tested on Caprice32 and
CPCEMU.
