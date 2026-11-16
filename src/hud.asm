; ===========================================================================
; HUD (screen rows 0..15, above the play area)
; Gear indicator: five boxes, lit up to the current gear. The fifth stays
; blue while it is locked (it needs the Maximum Speed powerup).
; ===========================================================================

HUD_BOX_ROW0   equ &8000+3*&800+32  ; screen row 3, byte column 0
HUD_BOX_COL    equ 2
HUD_BOX_W      equ 3                ; bytes (12 pixels)
HUD_BOX_H      equ 10

hud_update:
  ld a,(gear)
  ld hl,hud_gear
  cp (hl)
  ret z
  ld (hl),a
  ; fall through

hud_draw:
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
  ld e,a
  ld d,0
  ld hl,HUD_BOX_ROW0
  add hl,de
  ld b,HUD_BOX_H
.row:
  push hl
  ld (hl),c
  inc hl
  ld (hl),c
  inc hl
  ld (hl),c
  pop hl
  DOWN
  djnz .row
  pop bc
  inc b
  ld a,b
  cp GEARS+1
  jr nz,.box
  ret
