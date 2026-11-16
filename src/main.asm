; ===========================================================================
; LINNER - Amstrad CPC (any model, 64K)
; Entry point, hardware set-up and the 50 Hz main loop.
;
; Memory map
;   &0038         IM 1 interrupt vector (JP int_handler)
;   &0040-&6FFF   code, tables, level data, variables
;   &7000-&73FF   terrain key ring (mirrored)
;   &7400-&757F   384 gap keys (the "old" ground of the first frame)
;   &7580-&75DF   scratch row: gap columns "draw" here
;   &7580-&7FFF   stack (grows down from &8000)
;   &8000-&FFFF   the screen: Mode 1 overscan 384x272, single buffer
;
; Frame order: wait for VSYNC, then draw Linner (the beam is still in the
; top border, ~2 ms before the first visible row), update the ground in
; place, and only then read input and run the game logic for next frame.
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
  call terrain_init
  call hero_init
  call hud_draw
  call render                   ; first full draw while the palette is black
  ei
  call wait_frame
  xor a
  ld (frame_drops),a
  call palette_set

main_loop:
  call wait_frame
  BORDER HW_BRIGHT_RED
  call render
  BORDER HW_BLUE
  if TEST_FRAMES
  call test_input
  else
  call pad_read
  endif
  call hero_update
  call hud_update
  BORDER HW_BLACK
  jp main_loop

; Bring the screen up to date with the game state (ground and Linner).
render:
  call ground_begin
  call hero_erase
  ld e,HERO_XB0                 ; the ground under Linner first...
  ld b,HERO_XB1-HERO_XB0
  call ground_cols
  call hero_draw                ; ...then Linner, before the beam gets there
  BORDER HW_BRIGHT_YELLOW
  ld e,0                        ; the rest of the ground
  ld b,HERO_XB0
  call ground_cols
  ld e,HERO_XB1
  ld b,BYTES_PER_LINE-HERO_XB1
  call ground_cols
  jp ground_end

  if TEST_FRAMES
; Scripted input for headless runs: (frame, pad_new bits) pairs. After
; TEST_FRAMES frames we jump to &0000, where Caprice32's CAP32_WAITBREAK
; and tools/cpcsim.py stop and take the screenshot.
test_script:
  db 40, 1<<PAD_RIGHT
  db 80, 1<<PAD_RIGHT
  db 120, 1<<PAD_RIGHT
  db 160, 1<<PAD_RIGHT          ; gear 5 (refused unless TEST_GEAR5)
  db 0
test_input:
  ld hl,(test_frame)
  inc hl
  ld (test_frame),hl
  ld de,TEST_FRAMES
  or a
  sbc hl,de
  jp z,0
  add hl,de
  xor a
  ld (pad_new),a
  ld a,h
  or a
  ret nz
  ld a,l
  ld hl,test_script
.lp:
  ld b,(hl)
  inc b
  dec b
  ret z
  inc hl
  cp b
  ld c,(hl)
  inc hl
  jr nz,.lp
  ld a,c
  ld (pad_new),a
  ret
  endif

  include "video.asm"
  include "input.asm"
  include "gfx.asm"
  include "terrain.asm"
  include "hero.asm"
  include "hud.asm"
  include "tables.asm"
  include "level1.asm"

  assert (pix_mask and &FF) == 0

; ---------------------------------------------------------------------------
; Variables (cleared at start-up)
; ---------------------------------------------------------------------------
vars_start:
vsync_count:    db 0
last_vsync:     db 0
frame_drops:    db 0
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
drawn_wx:       dw 0
drawn_valid:    db 0
g_active:       db 0
g_old:          dw 0
g_new:          dw 0
; Linner
gear:           db 0
max_gear:       db 0
speed:          dw 0
hero_cy:        db 0
hero_cy_new:    db 0
hero_angle:     dw 0
hero_drawn:     db 0
hero_drawn_cy:  db 0
hero_drawn_ang: db 0
hero_redraw:    db 0
hud_gear:       db 0
vars_end:

code_end:
  assert code_end <= RING
  save "linner.bin",&0040,code_end-&0040
