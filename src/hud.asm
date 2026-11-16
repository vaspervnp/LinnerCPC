; ===========================================================================
; HUD (screen rows 0..15, above the play area)
; Gear indicator: five boxes, lit up to the current gear. The fifth stays
; blue while it is locked (it needs the Maximum Speed powerup).
; Soggy meter: a blue bar that fills while Linner rolls on water.
; ===========================================================================

HUD_BOX_ROW0   equ &8000+3*&800+32  ; screen row 3, byte column 0
HUD_BOX_COL    equ 2
HUD_BOX_W      equ 3                ; bytes (12 pixels)
HUD_H          equ 10               ; rows
SOGGY_COL      equ 24               ; bar: byte columns 24..43
SOGGY_BYTES    equ 20               ; SOGGY_MAX / 4

hud_update:
  ld a,(gear)
  ld hl,hud_gear
  cp (hl)
  call nz,hud_gears
  ld a,(hero_soggy)             ; the bar moves at most one byte per frame
  srl a
  srl a
  ld hl,hud_soggy
  cp (hl)
  ret z
  jr c,.shrink
  ld a,(hl)
  inc (hl)
  ld c,&0F                      ; pen 2
  jr hud_soggy_byte
.shrink:
  dec (hl)
  ld a,(hl)
  ld c,0
  ; fall through

; A = bar byte (0..19), C = value: fill that byte column of the bar.
hud_soggy_byte:
  add a,SOGGY_COL
  ; fall through

; A = byte column, C = value: fill HUD_H rows of it.
hud_column:
  ld e,a
  ld d,0
  ld hl,HUD_BOX_ROW0
  add hl,de
  ld b,HUD_H
.row:
  ld (hl),c
  DOWN
  djnz .row
  ret

; Full HUD: gear boxes, empty soggy bar with its end marks.
hud_draw:
  call hud_gears
  ld a,SOGGY_COL-1
  ld c,&10                      ; pen 1, rightmost pixel: left end mark
  call hud_column
  ld a,SOGGY_COL+SOGGY_BYTES
  ld c,&80                      ; pen 1, leftmost pixel: right end mark
  call hud_column
  xor a
  ld (hud_soggy),a
.clear:
  push af
  ld c,0
  call hud_soggy_byte
  pop af
  inc a
  cp SOGGY_BYTES
  jr nz,.clear
  ret

hud_gears:
  ld a,(gear)
  ld (hud_gear),a
  ld b,1                        ; box number
.box:
  ld a,(gear)
  cp b
  ld a,&FF                      ; pen 3: lit
  jr nc,.fill
  ld a,(max_gear)
  cp b
  ld a,&F0                      ; pen 1: available
  jr nc,.fill
  ld a,&0F                      ; pen 2: locked
.fill:
  ld c,a
  push bc
  ld a,b                        ; column = HUD_BOX_COL + (b-1)*(W+1)
  dec a
  add a,a
  add a,a
  add a,HUD_BOX_COL
  push af
  call hud_column
  pop af
  inc a
  push af
  call hud_column
  pop af
  inc a
  call hud_column
  pop bc
  inc b
  ld a,b
  cp GEARS+1
  jr nz,.box
  ret
