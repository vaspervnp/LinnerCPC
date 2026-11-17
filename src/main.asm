; ===========================================================================
; LINNER - Amstrad CPC (any model, 64K)
; Entry point, hardware set-up and the 50 Hz main loop.
;
; Memory map
;   &0038         IM 1 interrupt vector (JP int_handler)
;   &0040-&6FFF   code, tables, level data
;   &7000-&73FF   terrain key ring (mirrored)
;   &7400-&757F   384 gap keys (the "old" ground of the first frame)
;   &7580-&75DF   scratch row: gap columns "draw" here
;   &7600-&76C5   object slots: 6 foes/items/traps, 3 shots
;   &7800-&7BFF   terrain run lengths (mirrored like the key ring)
;   &7C00-&7D7F   variables (cleared at start-up)
;   &7D80-&7FFF   stack
;   &8000-&FFFF   the screen: Mode 1 overscan 384x272, single buffer
;   &C4E0-&C6DF   (inside it, never displayed) the disk sector buffer
;
; Frame order: wait for VSYNC, then redraw Linner and the objects (the
; beam is still in the top border, ~2 ms before the first visible row),
; update the ground in place, and only then read input and run the game
; logic for the next frame. Everything on screen is XOR.
;
; Build switches (rasm -D): DEBUG=1 shows frame time as border colours,
; TEST_FRAMES=n runs a scripted demo for n frames and stops at &0000.
; ===========================================================================

  include "defs.asm"
  include "macros.asm"

  ifndef DEBUG
DEBUG equ 0
  endif
  ifndef TEST_FRAMES
TEST_FRAMES equ 0
  endif
  ifndef TEST_GEAR5
TEST_GEAR5 equ 0                ; tests: gear 5 unlocked from the start
  endif
  ifndef TEST_GHOST
TEST_GHOST equ 0                ; tests: Linner is phased out for good
  endif
  ifndef TEST_SOAK
TEST_SOAK equ 0                 ; tests: 1 = roll through water, 2 = also stay in gear 1
  endif
  ifndef TEST_HISCORE
TEST_HISCORE equ 0              ; tests: 1 life, score 1234, scripted name entry, disk
  endif

  buildsna
  bankset 0
  run start

  org &0040
start:
  di
  ld sp,&8000
  im 1
  ld a,&C3                      ; JP int_handler at the IM 1 vector
  ld (&0038),a
  ld hl,int_handler
  ld (&0039),hl
  ld hl,vars_start              ; clear the variables
  ld de,vars_start+1
  ld bc,vars_end-vars_start-1
  ld (hl),0
  ldir
  call video_init               ; overscan, black palette, screen cleared
  call objects_init
  ld bc,FDC_MOTOR               ; (the loader left the drive motor off)
  xor a
  out (c),a
  ei
  call hiscore_init             ; built-in table, then the disk's
  ld a,&FF
  call title_start

main_loop:
  call wait_frame
  ld a,(game_state)             ; title or name entry: no game world
  cp GS_TITLE
  jr c,.game
  if TEST_FRAMES
  call test_input
  else
  call pad_read
  endif
  call game_update
  jp main_loop
.game:
  BORDER HW_BRIGHT_RED
  call render
  BORDER HW_BLUE
  call game_step
  ld hl,frame_late              ; the last loop overran and its picture was
  ld a,(hl)                     ; dropped: the game moves on by one more
  or a                          ; step, so it never slows down (at most one
  jr z,.on_time                 ; step: a busy screen shows at 25 Hz)
  ld (hl),0
  ld a,(game_state)
  cp GS_TITLE
  call c,game_step
.on_time:
  ld a,(game_state)             ; (the game may have just ended: the HUD
  cp GS_TITLE                   ; is gone with the rest of the screen)
  call c,hud_update
  BORDER HW_BLACK
  jp main_loop

; One step of the game: input, then the logic.
game_step:
  if TEST_FRAMES
  call test_input
  else
  call pad_read
  endif
  jp game_update

  if TEST_FRAMES
; Scripted input for headless runs: gear shifts at fixed loops, and an
; autopilot that jumps when a gap or water line is just ahead (holding the
; button for a full jump). After TEST_FRAMES loops we jump to &0000, where
; Caprice32's CAP32_WAITBREAK and tools/cpcsim.py stop.
test_input:
  ld hl,(test_frame)
  inc hl
  ld (test_frame),hl
  ld de,TEST_FRAMES
  or a
  sbc hl,de
  jp z,0
  add hl,de
  ld a,(game_state)
  cp GS_TITLE
  jp z,test_title
  cp GS_ENTRY
  jp z,test_entry
  ld c,0                        ; C = pad bits this loop
  if TEST_SOAK == 2             ; (2: stay in gear 1, too slow for the water:
  ld a,(game_state)             ; shift down every 16 loops)
  cp GS_PLAY
  jr nz,.auto
  ld a,l
  and 15
  jr nz,.auto
  ld c,1<<PAD_LEFT
  endif
  if 0                          ; (the gears go up by themselves now)
  ld a,(game_state)             ; playing: shift up every 16 loops while
  cp GS_PLAY                    ; the gear is below the limit (4, or 5 with
  jr nz,.auto                   ; Max Speed or TEST_GEAR5)
  ld a,l
  and 15
  jr nz,.auto
  ld a,(max_gear)
  ld hl,gear
  cp (hl)
  jr z,.auto
  ld c,1<<PAD_RIGHT
  endif
.auto:
  ld a,(hero_grounded)
  or a
  jr z,.air
  ld a,(pad)                    ; just landed with the button held: let go
  and 1<<PAD_JUMP
  jr nz,.set
  ld hl,(scroll_wx)
  ld de,HERO_X+TEST_LOOKAHEAD
  add hl,de
  call ring_addr
  ld a,(hl)
  inc a
  jr z,.jump                    ; a gap ahead
  if TEST_SOAK == 0             ; (TEST_SOAK: roll into water)
  ld b,a
  push bc                       ; (C holds the pad bits)
  call hero_phased              ; a ghost doesn't mind water or foes
  pop bc
  jr z,.set
  ld a,b
  cp KEY_WATER+1
  jr nc,.jump                   ; water ahead
  endif
  ld ix,OBJECTS                 ; a Rectangle or spikes close ahead: jump
  ld b,MAX_FOES
.foe:
  ld a,(ix+O_TYPE)
  cp T_RECT
  jr z,.isfoe
  cp T_SPIKE
  jr nz,.nofoe
.isfoe:
  bit F_VIS,(ix+O_FLAGS)
  jr z,.nofoe
  ld l,(ix+O_NSX)
  ld h,(ix+O_NSX+1)
  ld de,-(HERO_X+LINNER_R)
  add hl,de
  ld a,h
  or a
  jr nz,.nofoe
  ld a,l
  cp 24
  jr c,.jump
.nofoe:
  ld de,OBJ_SIZE
  add ix,de
  djnz .foe
  jr .set
.air:
  ld a,(pad)                    ; keep holding jump in the air
  and 1<<PAD_JUMP
  jr z,.set
.jump:
  ld a,c
  or 1<<PAD_JUMP
  ld c,a
.set:
  ld a,(test_frame)             ; aim straight ahead, then 30 degrees up
  and 32                        ; (Triangles), 32 loops each
  jr z,.aim
  ld a,3
.aim:
  ld (hero_aim),a
  ld a,c                        ; keep firing
  or 1<<PAD_FIRE
  ld c,a
  ld a,(pad)
  cpl
  and c
  ld (pad_new),a
  ld a,c
  ld (pad),a
  ret
TEST_LOOKAHEAD equ 4            ; jump when the gap / water is this far ahead
                                ; of Linner's centre (late, for a long jump)

; Title: press FIRE (once the title takes input), but not after a name
; entry: the test ends there, showing the table.
test_title:
  ld c,0
  ld a,(test_step)
  inc a
  jr z,test_pad                 ; (&FF: the name is in)
  ld a,(state_timer)
  or a
  jr nz,test_pad
  ld c,1<<PAD_FIRE
  jr test_pad

; Name entry: the script below, one event per line (frame, pad, key).
test_entry:
  ld hl,test_step
  inc (hl)
  ld b,(hl)
  ld a,&FF                      ; no key down...
  ld hl,keymap
  ld c,10
.clr:
  ld (hl),a
  inc hl
  dec c
  jr nz,.clr
  ld hl,test_name_script
.lp:
  ld a,(hl)
  or a
  jr z,test_pad
  cp b
  jr z,.event
  inc hl
  inc hl
  inc hl
  jr .lp
.event:
  inc hl
  ld c,(hl)
  inc hl
  ld a,(hl)                     ; ... or the scripted one
  or a
  jr z,.last
  call test_key
.last:
  ld a,b
  cp TEST_NAME_END
  jr nz,test_pad
  ld a,&FF                      ; done: the title shows the table
  ld (test_step),a
  ; fall through
test_pad:
  ld a,(pad)
  cpl
  and c
  ld (pad_new),a
  ld a,c
  ld (pad),a
  ret

; A = key code: hold it down in keymap.
test_key:
  push bc
  ld c,a
  rrca
  rrca
  rrca
  rrca
  and &0F
  ld e,a
  ld d,0
  ld hl,keymap
  add hl,de
  ld a,c
  and 7
  ld b,a
  ld a,&FE
  inc b
  jr .go
.rot:
  rlca
.go:
  djnz .rot
  and (hl)
  ld (hl),a
  pop bc
  ret

; Joystick UP twice ("C"), FIRE, then typed: P, X, DEL (clears the blank,
; goes back over the X), C, 6, 4, RETURN. The table gets "CPC64".
test_name_script:
  db 10,1<<PAD_UP,0
  db 16,1<<PAD_UP,0
  db 22,1<<PAD_FIRE,0
  db 28,0,&33
  db 34,0,&77
  db 40,0,&97
  db 46,0,&76
  db 52,0,&60
  db 58,0,&70
  db 64,0,&22
TEST_NAME_END equ 64
  db 0
  endif

  include "video.asm"
  include "input.asm"
  include "gfx.asm"
  include "terrain.asm"
  include "hero.asm"
  include "objects.asm"
  include "hud.asm"
  include "text.asm"
  include "game.asm"
  include "hiscore.asm"
  include "menu.asm"
  include "particles.asm"
  include "disk.asm"
  include "tables.asm"
  include "levels.asm"

  assert (pix_mask and &FF) == 0

code_end:
  assert code_end <= RING
  save "linner.bin",&0040,code_end-&0040

; ---------------------------------------------------------------------------
; Variables (cleared at start-up; not in linner.bin)
; ---------------------------------------------------------------------------
VARS equ &7C00
  org VARS
vars_start:
vsync_count:    db 0
last_vsync:     db 0
frame_drops:    db 0
frame_late:     db 0            ; the last loop overran: one logic step to catch up
keymap:         defs 10
pad:            db 0
pad_new:        db 0
test_frame:     dw 0
; terrain
scroll_wx:      dw 0
scroll_frac:    db 0
gen_wx:         dw 0
gen_y:          dw 0
gen_slope:      dw 0
gen_len:        db 0
gen_type:       db 0
gen_end:        db 0
gen_ptr:        dw 0
gen_prev:       db 0
gen_run:        db 0
drawn_wx:       dw 0
drawn_valid:    db 0
g_active:       db 0
g_old:          dw 0
g_new:          dw 0
; Linner
gear:           db 0
gear_timer:     db 0            ; frames to the next automatic gear up
max_gear:       db 0
speed:          dw 0
hero_cy_frac:   db 0            ; (hero_cy_frac) as a word = centre y in 8.8
hero_cy:        db 0
hero_vy:        dw 0
hero_grounded:  db 0
hero_state:     db 0
hero_timer:     db 0
hero_hidden:    db 0
hero_soggy:     db 0
hero_on_water:  db 0
hero_angle:     dw 0
hero_drawn:     db 0
hero_drawn_cy:  db 0
hero_drawn_ang: db 0
hero_redraw:    db 0
hud_soggy:      db 0
hero_aim:       db 0
aim_repeat:     db 0
shot_cool:      db 0
marker_drawn:   db 0
marker_dcy:     db 0
marker_daim:    db 0
mk_x1:          dw 0
mk_y0:          db 0
mk_y1:          db 0
score:          db 0,0,0        ; BCD, most significant first
lives:          db 0
level_num:      db 0
game_state:     db 0
state_timer:    db 0
time_left:      dw 0            ; BCD seconds
time_tick:      db 0
hero_fast:      dw 0            ; frames of Max Speed left
hero_phase:     dw 0            ; frames of Phase Out left
hero_ctab:      dw 0            ; circle_tab or ghost_tab
hero_drawn_ctab: dw 0
msg_cur:        dw 0
hud_want:       defs 10
hud_shown:      defs 10
hud_char:       db 0,0
hud_box:        defs 5          ; the look each gear box has on screen
spawn_ptr:      dw 0
spawn_base:     dw 0
spawn_x:        dw 0            ; world x of the record at spawn_ptr
gu_min:         db 0
; the current level (a copy of its level_table entry)
lv_segs:        dw 0
lv_foes:        dw 0
lv_goal:        dw 0
lv_time:        dw 0
lv_name:        dw 0
lv_key:         db 0,0
msg_buf:        defs 28
; high scores and the disk
hiscores:       defs HS_COUNT*HS_SIZE
title_hl:       db 0
title_tick:     db 0
entry_rank:     db 0
entry_pos:      db 0
entry_name:     defs 5
key_prev:       defs 10
hs_row:         defs 18
disk_track:     db 0
disk_sector:    db 0
fdc_res:        defs 8
test_step:      db 0
parts:          defs N_PARTS*P_SIZE   ; warp particles
part_turn:      db 0
part_step:      dw 0
part_mi:        db 0
part_busy:      db 0
part_next:      db 0
menu_phase:     db 0            ; the menu floor's roll, 0..15

vars_end:

  assert vars_end <= VARS+&180    ; the stack has the rest, down from &8000
