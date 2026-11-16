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

; One HUD job per frame: a digit, else a gear box, else the soggy bar.
hud_update:
  call hud_text_update
  ret nz
  call hud_gears
  ret nz
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

; Full HUD: gear boxes, empty soggy bar with its end marks, the texts.
hud_draw:
  call hud_labels
  ld b,GEARS                    ; (hud_box mirrors the screen: 0 at boot)
.all:
  push bc
  call hud_gears
  pop bc
  djnz .all
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

; Bring the gear boxes up to date: at most one box (3 x 10 bytes) per
; frame, only where its look changed.
hud_gears:
  ld b,1                        ; box number
  ld hl,hud_box
.box:
  ld a,(gear)
  cp b
  ld c,&FF                      ; pen 3: lit
  jr nc,.got
  ld a,(max_gear)
  cp b
  ld c,&F0                      ; pen 1: available
  jr nc,.got
  ld c,&0F                      ; pen 2: locked
.got:
  ld a,(hl)
  cp c
  jr nz,.draw
  inc hl
  inc b
  ld a,b
  cp GEARS+1
  jr nz,.box
  xor a                         ; Z: nothing to do
  ret
.draw:
  ld (hl),c
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
  or 1                          ; NZ: drew a box
  ret
