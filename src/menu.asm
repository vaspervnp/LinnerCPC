; ===========================================================================
; The menus' vector world (title, high scores, name entry): a floor whose
; cross lines roll towards the viewer, radial floor lines, low mountains, a
; striped sun on the horizon and stars, all XOR under the text, in their own
; palette (pen 2 magenta, as on the loading screen). Data: tables.asm
; (tools/gen_tables.py, menu_world).
; ===========================================================================

PEN1_MASK equ &F0
PEN2_MASK equ &0F
PEN3_MASK equ &FF

menu_palette:                   ; pens 0..3, border
  db HW_BLACK, HW_BRIGHT_GREEN, HW_BRIGHT_MAGENTA, HW_BRIGHT_WHITE, HW_BLACK

; Draw the world on a cleared screen (the text goes on top of it).
menu_world:
  ld a,PEN2_MASK                ; radial floor lines
  call line_pen
  ld hl,menu_radials
  ld b,MENU_N_RADIALS
.rad:
  push bc
  call mw_line
  pop bc
  djnz .rad
  ld a,PEN1_MASK                ; mountains: a polyline over the horizon
  call line_pen
  ld hl,menu_peaks
  ld b,MENU_N_PEAKS-1
.peak:
  push bc
  push hl
  call mw_line
  pop hl
  inc hl                        ; the next segment starts at this end
  inc hl
  inc hl
  pop bc
  djnz .peak
  ld a,PEN2_MASK                ; the sun
  call line_pen
  ld hl,menu_stripes
  ld b,MENU_N_STRIPES
.sun:
  push bc
  ld e,(hl)
  inc hl
  ld d,(hl)
  inc hl
  push de
  ld e,(hl)
  inc hl
  ld d,(hl)
  inc hl
  ld b,(hl)
  inc hl
  ld c,b
  ex (sp),hl                    ; HL = x0, DE = x1; the pointer on the stack
  call line_xor
  pop hl
  pop bc
  djnz .sun
  ld a,PEN3_MASK                ; (the game draws in pen 3)
  call line_pen
  ld hl,menu_stars
  ld b,MENU_N_STARS
.star:
  push bc
  ld e,(hl)
  inc hl
  ld d,(hl)
  inc hl
  ld a,(hl)
  inc hl
  push hl
  ex de,hl                      ; HL = x
  ld e,a                        ; E = y
  call pix_addr
  ld a,(hl)
  xor c
  ld (hl),a
  pop hl
  pop bc
  djnz .star
  xor a
  ld (menu_phase),a
  jp menu_floor_xor

; HL -> dw x0, db y0, dw x1, db y1: XOR that line. HL advances 6 bytes.
mw_line:
  ld e,(hl)
  inc hl
  ld d,(hl)
  inc hl
  ld b,(hl)
  inc hl
  push de                       ; x0
  ld e,(hl)
  inc hl
  ld d,(hl)
  inc hl
  ld c,(hl)
  inc hl
  ex (sp),hl                    ; HL = x0, the pointer on the stack
  call line_xor
  pop hl
  ret

; Every frame in the menus: roll the floor one step towards the viewer.
menu_tick:
  call menu_floor_xor           ; off
  ld hl,menu_phase
  ld a,(hl)
  inc a
  and 15
  ld (hl),a
  jp menu_floor_xor             ; on

; XOR the floor's cross lines at menu_phase.
menu_floor_xor:
  ld a,(menu_phase)
  ld e,a
  ld d,0
  ld hl,menu_floor
  ld b,MENU_FLOOR_LINES
.row:
  add hl,de
  djnz .row
  ld b,MENU_FLOOR_LINES
.lp:
  push bc
  push hl
  ld e,(hl)
  ld c,PEN2_MASK
  call hline_xor
  pop hl
  inc hl
  pop bc
  djnz .lp
  ret
